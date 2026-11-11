using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;
using Windows.Graphics;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;

namespace WindowSlice.LiveCapture
{
    public sealed class LiveWindowCapture : IDisposable
    {
        private const uint D3d11CreateDeviceBgraSupport = 0x20;
        private const uint D3d11CpuAccessRead = 0x20000;
        private const int D3d11DriverTypeHardware = 1;
        private const uint D3d11SdkVersion = 7;
        private const int D3d11UsageStaging = 3;
        private const int D3d11MapRead = 1;
        private static readonly Guid GraphicsCaptureItemInteropId = new Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356");
        private static readonly Guid GraphicsCaptureItemId = new Guid("79C3F95B-31F7-4EC2-A464-632EF5D30760");
        private static readonly Guid Direct3dDxgiInterfaceAccessId = new Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1");
        private static readonly Guid DxgiDeviceId = new Guid("54EC77FA-1377-44E6-8C32-88FD5F44C84C");
        private static readonly Guid D3d11Texture2dId = new Guid("6F15AAF2-D208-4E89-9AB4-489535D34F9C");

        private readonly object _sync = new object();
        private IDirect3DDevice _winrtDevice;
        private GraphicsCaptureItem _item;
        private Direct3D11CaptureFramePool _framePool;
        private GraphicsCaptureSession _session;
        private IntPtr _d3dDevice;
        private IntPtr _deviceContext;
        private IntPtr _stagingTexture;
        private int _stagingWidth;
        private int _stagingHeight;
        private SizeInt32 _captureSize;
        private bool _disposed;

        [StructLayout(LayoutKind.Sequential)]
        private struct Texture2DDescription
        {
            public uint Width;
            public uint Height;
            public uint MipLevels;
            public uint ArraySize;
            public uint Format;
            public uint SampleCount;
            public uint SampleQuality;
            public int Usage;
            public uint BindFlags;
            public uint CpuAccessFlags;
            public uint MiscFlags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MappedSubresource
        {
            public IntPtr Data;
            public uint RowPitch;
            public uint DepthPitch;
        }

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int CreateTexture2DDelegate(IntPtr device, ref Texture2DDescription description, IntPtr initialData, out IntPtr texture);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate void CopyResourceDelegate(IntPtr context, IntPtr destination, IntPtr source);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int MapDelegate(IntPtr context, IntPtr resource, uint subresource, int mapType, uint mapFlags, out MappedSubresource mapped);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate void UnmapDelegate(IntPtr context, IntPtr resource, uint subresource);

        [ComImport]
        [Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IGraphicsCaptureItemInterop
        {
            [PreserveSig]
            int CreateForWindow(IntPtr window, ref Guid interfaceId, out IntPtr item);

            [PreserveSig]
            int CreateForMonitor(IntPtr monitor, ref Guid interfaceId, out IntPtr item);
        }

        [ComImport]
        [Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IDirect3DDxgiInterfaceAccess
        {
            void GetInterface(ref Guid interfaceId, out IntPtr result);
        }

        [DllImport("combase.dll", CharSet = CharSet.Unicode)]
        private static extern int WindowsCreateString(string value, uint length, out IntPtr handle);

        [DllImport("combase.dll")]
        private static extern int WindowsDeleteString(IntPtr handle);

        [DllImport("combase.dll")]
        private static extern int RoGetActivationFactory(IntPtr className, ref Guid interfaceId, out IntPtr factory);

        [DllImport("d3d11.dll", EntryPoint = "D3D11CreateDevice")]
        private static extern int D3d11CreateDevice(
            IntPtr adapter,
            int driverType,
            IntPtr software,
            uint flags,
            IntPtr featureLevels,
            uint featureLevelCount,
            uint sdkVersion,
            out IntPtr device,
            out int featureLevel,
            out IntPtr immediateContext);

        [DllImport("d3d11.dll", EntryPoint = "CreateDirect3D11DeviceFromDXGIDevice")]
        private static extern int CreateDirect3D11DeviceFromDxgiDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

        private LiveWindowCapture(IntPtr window, bool allowVisibleBorder)
        {
            try
            {
                CreateD3dDevice();
                CreateCaptureItem(window);
                SizeInt32 size = _item.Size;
                _framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
                    _winrtDevice,
                    DirectXPixelFormat.B8G8R8A8UIntNormalized,
                    2,
                    size);
                _captureSize = size;
                _session = _framePool.CreateCaptureSession(_item);
                try
                {
                    System.Reflection.PropertyInfo borderProperty = typeof(GraphicsCaptureSession).GetProperty("IsBorderRequired");
                    if (borderProperty == null || !borderProperty.CanWrite)
                    {
                        if (!allowVisibleBorder)
                            throw new PlatformNotSupportedException("This Windows version cannot disable the system border for Graphics Capture.");
                    }
                    else
                        borderProperty.SetValue(_session, false, null);
                }
                catch (Exception ex)
                {
                    if (!allowVisibleBorder)
                        throw new PlatformNotSupportedException("Windows could not disable the system border for Graphics Capture.", ex);
                    System.Diagnostics.Trace.TraceWarning("Windows did not allow disabling the Graphics Capture border in this capture test: " + ex.ToString());
                }
                _session.StartCapture();
            }
            catch
            {
                Dispose();
                throw;
            }
        }

        public static LiveWindowCapture Create(IntPtr window)
        {
            return Create(window, false);
        }

        public static LiveWindowCapture Create(IntPtr window, bool allowVisibleBorder)
        {
            if (window == IntPtr.Zero) throw new ArgumentException("A source window is required.", "window");
            return new LiveWindowCapture(window, allowVisibleBorder);
        }

        public Bitmap Capture()
        {
            lock (_sync)
            {
                if (_disposed) throw new ObjectDisposedException("LiveWindowCapture");
                Direct3D11CaptureFrame frame = null;
                try
                {
                    for (int attempt = 0; attempt < 25; attempt++)
                    {
                        frame = _framePool.TryGetNextFrame();
                        if (frame == null) { Thread.Sleep(8); continue; }
                        SizeInt32 frameSize = frame.ContentSize;
                        if (frameSize.Width == _captureSize.Width && frameSize.Height == _captureSize.Height) break;
                        frame.Dispose();
                        frame = null;
                        _captureSize = frameSize;
                        _framePool.Recreate(
                            _winrtDevice,
                            DirectXPixelFormat.B8G8R8A8UIntNormalized,
                            2,
                            frameSize);
                    }
                    if (frame == null) throw new InvalidOperationException("Windows Graphics Capture has not produced a frame yet.");
                    SizeInt32 size = frame.ContentSize;
                    if (size.Width < 1 || size.Height < 1)
                        throw new InvalidOperationException("Windows Graphics Capture returned an empty frame.");
                    IntPtr sourceTexture = GetFrameTexture(frame.Surface);
                    try
                    {
                        EnsureStagingTexture(size.Width, size.Height);
                        CopyResourceDelegate copy = GetDeviceContextMethod<CopyResourceDelegate>(47);
                        copy(_deviceContext, _stagingTexture, sourceTexture);
                        MappedSubresource mapped;
                        MapDelegate map = GetDeviceContextMethod<MapDelegate>(14);
                        int result = map(_deviceContext, _stagingTexture, 0, D3d11MapRead, 0, out mapped);
                        if (result < 0) Marshal.ThrowExceptionForHR(result);
                        try
                        {
                            return CopyMappedPixels(mapped, size.Width, size.Height);
                        }
                        finally
                        {
                            GetDeviceContextMethod<UnmapDelegate>(15)(_deviceContext, _stagingTexture, 0);
                        }
                    }
                    finally { Marshal.Release(sourceTexture); }
                }
                finally
                {
                    if (frame != null) frame.Dispose();
                }
            }
        }

        public void DiscardPendingFrames()
        {
            lock (_sync)
            {
                if (_disposed) throw new ObjectDisposedException("LiveWindowCapture");
                for (int attempt = 0; attempt < 4; attempt++)
                {
                    Direct3D11CaptureFrame frame = _framePool.TryGetNextFrame();
                    if (frame == null) break;
                    frame.Dispose();
                }
            }
        }

        private void CreateCaptureItem(IntPtr window)
        {
            IntPtr name = IntPtr.Zero;
            IntPtr factoryPointer = IntPtr.Zero;
            IntPtr itemPointer = IntPtr.Zero;
            try
            {
                string runtimeClass = "Windows.Graphics.Capture.GraphicsCaptureItem";
                int result = WindowsCreateString(runtimeClass, (uint)runtimeClass.Length, out name);
                if (result < 0) Marshal.ThrowExceptionForHR(result);
                Guid interopId = GraphicsCaptureItemInteropId;
                result = RoGetActivationFactory(name, ref interopId, out factoryPointer);
                if (result < 0) Marshal.ThrowExceptionForHR(result);
                IGraphicsCaptureItemInterop interop = (IGraphicsCaptureItemInterop)Marshal.GetObjectForIUnknown(factoryPointer);
                Guid itemId = GraphicsCaptureItemId;
                result = interop.CreateForWindow(window, ref itemId, out itemPointer);
                if (result < 0) Marshal.ThrowExceptionForHR(result);
                _item = (GraphicsCaptureItem)Marshal.GetObjectForIUnknown(itemPointer);
            }
            finally
            {
                if (itemPointer != IntPtr.Zero) Marshal.Release(itemPointer);
                if (factoryPointer != IntPtr.Zero) Marshal.Release(factoryPointer);
                if (name != IntPtr.Zero) WindowsDeleteString(name);
            }
        }

        private void CreateD3dDevice()
        {
            int featureLevel;
            int result = D3d11CreateDevice(
                IntPtr.Zero,
                D3d11DriverTypeHardware,
                IntPtr.Zero,
                D3d11CreateDeviceBgraSupport,
                IntPtr.Zero,
                0,
                D3d11SdkVersion,
                out _d3dDevice,
                out featureLevel,
                out _deviceContext);
            if (result < 0) Marshal.ThrowExceptionForHR(result);

            IntPtr dxgiDevice = QueryInterface(_d3dDevice, DxgiDeviceId);
            IntPtr graphicsDevice = IntPtr.Zero;
            try
            {
                result = CreateDirect3D11DeviceFromDxgiDevice(dxgiDevice, out graphicsDevice);
                if (result < 0) Marshal.ThrowExceptionForHR(result);
                _winrtDevice = (IDirect3DDevice)Marshal.GetObjectForIUnknown(graphicsDevice);
            }
            finally
            {
                Marshal.Release(dxgiDevice);
                if (graphicsDevice != IntPtr.Zero) Marshal.Release(graphicsDevice);
            }
        }

        private static IntPtr GetFrameTexture(IDirect3DSurface surface)
        {
            IntPtr unknown = Marshal.GetIUnknownForObject(surface);
            try
            {
                IDirect3DDxgiInterfaceAccess access = (IDirect3DDxgiInterfaceAccess)Marshal.GetObjectForIUnknown(unknown);
                IntPtr texture;
                Guid interfaceId = D3d11Texture2dId;
                access.GetInterface(ref interfaceId, out texture);
                return texture;
            }
            finally { Marshal.Release(unknown); }
        }

        private void EnsureStagingTexture(int width, int height)
        {
            if (_stagingTexture != IntPtr.Zero && _stagingWidth == width && _stagingHeight == height) return;
            if (_stagingTexture != IntPtr.Zero)
            {
                Marshal.Release(_stagingTexture);
                _stagingTexture = IntPtr.Zero;
            }
            Texture2DDescription description = new Texture2DDescription
            {
                Width = (uint)width,
                Height = (uint)height,
                MipLevels = 1,
                ArraySize = 1,
                Format = 87,
                SampleCount = 1,
                Usage = D3d11UsageStaging,
                CpuAccessFlags = D3d11CpuAccessRead
            };
            CreateTexture2DDelegate create = GetDeviceMethod<CreateTexture2DDelegate>(5);
            int result = create(_d3dDevice, ref description, IntPtr.Zero, out _stagingTexture);
            if (result < 0) Marshal.ThrowExceptionForHR(result);
            _stagingWidth = width;
            _stagingHeight = height;
        }

        private Bitmap CopyMappedPixels(MappedSubresource mapped, int width, int height)
        {
            Bitmap bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            BitmapData data = null;
            try
            {
                data = bitmap.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                int rowLength = checked(width * 4);
                byte[] row = new byte[rowLength];
                for (int y = 0; y < height; y++)
                {
                    Marshal.Copy(IntPtr.Add(mapped.Data, checked(y * (int)mapped.RowPitch)), row, 0, rowLength);
                    Marshal.Copy(row, 0, IntPtr.Add(data.Scan0, y * data.Stride), rowLength);
                }
                bitmap.UnlockBits(data);
                data = null;
                return bitmap;
            }
            catch
            {
                if (data != null) bitmap.UnlockBits(data);
                bitmap.Dispose();
                throw;
            }
        }

        private T GetDeviceMethod<T>(int index) where T : class
        {
            return GetVtableMethod<T>(_d3dDevice, index);
        }

        private T GetDeviceContextMethod<T>(int index) where T : class
        {
            return GetVtableMethod<T>(_deviceContext, index);
        }

        private static T GetVtableMethod<T>(IntPtr instance, int index) where T : class
        {
            if (instance == IntPtr.Zero) throw new ObjectDisposedException("Direct3D device");
            IntPtr vtable = Marshal.ReadIntPtr(instance);
            IntPtr function = Marshal.ReadIntPtr(vtable, index * IntPtr.Size);
            return Marshal.GetDelegateForFunctionPointer(function, typeof(T)) as T;
        }

        private static IntPtr QueryInterface(IntPtr instance, Guid interfaceId)
        {
            IntPtr vtable = Marshal.ReadIntPtr(instance);
            IntPtr function = Marshal.ReadIntPtr(vtable, 0);
            QueryInterfaceDelegate query = (QueryInterfaceDelegate)Marshal.GetDelegateForFunctionPointer(function, typeof(QueryInterfaceDelegate));
            IntPtr result;
            int status = query(instance, ref interfaceId, out result);
            if (status < 0) Marshal.ThrowExceptionForHR(status);
            return result;
        }

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int QueryInterfaceDelegate(IntPtr instance, ref Guid interfaceId, out IntPtr result);

        public void Dispose()
        {
            lock (_sync)
            {
                if (_disposed) return;
                _disposed = true;
                if (_session != null) { _session.Dispose(); _session = null; }
                if (_framePool != null) { _framePool.Dispose(); _framePool = null; }
                if (_item != null) { Marshal.FinalReleaseComObject(_item); _item = null; }
                if (_winrtDevice != null) { Marshal.FinalReleaseComObject(_winrtDevice); _winrtDevice = null; }
                if (_stagingTexture != IntPtr.Zero) { Marshal.Release(_stagingTexture); _stagingTexture = IntPtr.Zero; }
                if (_deviceContext != IntPtr.Zero) { Marshal.Release(_deviceContext); _deviceContext = IntPtr.Zero; }
                if (_d3dDevice != IntPtr.Zero) { Marshal.Release(_d3dDevice); _d3dDevice = IntPtr.Zero; }
            }
        }
    }
}
