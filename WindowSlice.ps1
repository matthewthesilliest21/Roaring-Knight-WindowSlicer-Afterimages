param(
    [switch]$Configure,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$source = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Diagnostics;
using System.IO;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using System.Media;
using System.Collections.Generic;

namespace WindowSlice
{
    public sealed class Settings
    {
        public string Hotkey;
        public string QuickSliceHotkey;
        public string SelectionHotkey;
        public string PrecisionHotkey;
        public string DisperseSnapshotsHotkey;
        public string Direction = "Vertical";
        public int MultiSlashCount = 6;
        public string MultiPattern = "Radial";
        public int DurationMs = 600;
        public int DistancePx = 180;
        public string SlashColor = "#08080B";
        public string OutlineColor = "#E6182A";
        public int SlashThickness = 18;
        public bool ConfirmBeforeClose = true;
        public bool AllowRepeatedSlices = false;
        public bool KeepFragments = false;
        public bool FragmentsCanBeSliced = false;
        public bool UnlimitedPerformance = false;
        public bool ClickToDisperse = false;
        public bool RotateFragmentsWithArrowKeys = false;
        public bool KeepWindowsOpenAfterSlicing = false;
        public bool DetachedPiecesInteractive = false;
        public bool RefreshLiveFragments = false;

        public void Normalize()
        {
            bool hasLegacyShortcut = !String.IsNullOrWhiteSpace(Hotkey);
            if (String.IsNullOrWhiteSpace(QuickSliceHotkey))
                QuickSliceHotkey = hasLegacyShortcut && String.Equals(Hotkey, "Ctrl+Alt+Q", StringComparison.OrdinalIgnoreCase) ? "Ctrl+Shift+Q" : "Ctrl+Alt+Q";
            if (String.IsNullOrWhiteSpace(SelectionHotkey))
                SelectionHotkey = hasLegacyShortcut ? Hotkey : "F8";
            if (String.IsNullOrWhiteSpace(PrecisionHotkey)) PrecisionHotkey = "Ctrl+Shift+F8";

            HotkeySpec quick;
            if (!HotkeySpec.TryParse(QuickSliceHotkey, out quick)) QuickSliceHotkey = "Ctrl+Alt+Q";
            HotkeySpec selection;
            if (!HotkeySpec.TryParse(SelectionHotkey, out selection)) SelectionHotkey = "F8";
            HotkeySpec precision;
            if (!HotkeySpec.TryParse(PrecisionHotkey, out precision)) PrecisionHotkey = "Ctrl+Shift+F8";

            HotkeySpec.TryParse(QuickSliceHotkey, out quick);
            HotkeySpec.TryParse(SelectionHotkey, out selection);
            HotkeySpec.TryParse(PrecisionHotkey, out precision);
            if (SameHotkey(quick, selection))
            {
                SelectionHotkey = "F8";
                HotkeySpec.TryParse(SelectionHotkey, out selection);
                if (SameHotkey(quick, selection))
                {
                    SelectionHotkey = "Ctrl+Alt+S";
                    HotkeySpec.TryParse(SelectionHotkey, out selection);
                }
            }
            if (SameHotkey(quick, precision) || SameHotkey(selection, precision))
            {
                PrecisionHotkey = "Ctrl+Shift+F9";
                HotkeySpec.TryParse(PrecisionHotkey, out precision);
                if (SameHotkey(quick, precision) || SameHotkey(selection, precision)) PrecisionHotkey = "Ctrl+Alt+P";
            }
            HotkeySpec disperse;
            if (!String.IsNullOrWhiteSpace(DisperseSnapshotsHotkey) &&
                (!HotkeySpec.TryParse(DisperseSnapshotsHotkey, out disperse) ||
                 SameHotkey(quick, disperse) || SameHotkey(selection, disperse) || SameHotkey(precision, disperse)))
                DisperseSnapshotsHotkey = String.Empty;
            Hotkey = QuickSliceHotkey;

            if (String.Equals(Direction, "Horizontal", StringComparison.OrdinalIgnoreCase)) Direction = "Horizontal";
            else if (String.Equals(Direction, "Diagonal", StringComparison.OrdinalIgnoreCase)) Direction = "Diagonal";
            else if (String.Equals(Direction, "MultiSlash", StringComparison.OrdinalIgnoreCase)) Direction = "MultiSlash";
            else Direction = "Vertical";
            if (!String.Equals(MultiPattern, "Random", StringComparison.OrdinalIgnoreCase)) MultiPattern = "Radial";
            else MultiPattern = "Random";
            SlashColor = NormalizeHexColor(SlashColor, "#08080B");
            OutlineColor = NormalizeHexColor(OutlineColor, "#E6182A");
            if (!UnlimitedPerformance)
            {
                if (MultiSlashCount < 2) MultiSlashCount = 2;
                if (MultiSlashCount > 25) MultiSlashCount = 25;
                if (DurationMs < 150) DurationMs = 150;
                if (DurationMs > 6000) DurationMs = 6000;
                if (DistancePx < 0) DistancePx = 0;
                if (DistancePx > 600) DistancePx = 600;
                if (SlashThickness < 1) SlashThickness = 1;
                if (SlashThickness > 40) SlashThickness = 40;
            }
            if (!KeepWindowsOpenAfterSlicing) DetachedPiecesInteractive = false;
            if (!CanRefreshLiveFragments(KeepWindowsOpenAfterSlicing, KeepFragments)) RefreshLiveFragments = false;
        }

        internal static bool CanRefreshLiveFragments(bool keepWindowsOpen, bool keepFragments)
        {
            return keepWindowsOpen && !keepFragments;
        }

        private static bool SameHotkey(HotkeySpec left, HotkeySpec right)
        {
            return left != null && right != null && left.Modifiers == right.Modifiers && left.Key == right.Key;
        }

        private static string NormalizeHexColor(string value, string fallback)
        {
            if (String.IsNullOrEmpty(value) || value.Length != 7 || value[0] != '#') return fallback;
            try
            {
                int red = Int32.Parse(value.Substring(1, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                int green = Int32.Parse(value.Substring(3, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                int blue = Int32.Parse(value.Substring(5, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                return String.Format(CultureInfo.InvariantCulture, "#{0:X2}{1:X2}{2:X2}", red, green, blue);
            }
            catch { return fallback; }
        }
    }

    internal sealed class HotkeySpec
    {
        public uint Modifiers;
        public Keys Key;

        public static bool TryParse(string value, out HotkeySpec spec)
        {
            spec = null;
            if (String.IsNullOrWhiteSpace(value)) return false;
            string[] parts = value.Split('+');
            uint mods = 0;
            Keys key = Keys.None;
            bool hasKey = false;
            for (int i = 0; i < parts.Length; i++)
            {
                string part = parts[i].Trim();
                if (part.Length == 0) return false;
                if (String.Equals(part, "Ctrl", StringComparison.OrdinalIgnoreCase) || String.Equals(part, "Control", StringComparison.OrdinalIgnoreCase))
                {
                    if ((mods & Native.ModControl) != 0) return false;
                    mods |= Native.ModControl;
                }
                else if (String.Equals(part, "Alt", StringComparison.OrdinalIgnoreCase))
                {
                    if ((mods & Native.ModAlt) != 0) return false;
                    mods |= Native.ModAlt;
                }
                else if (String.Equals(part, "Shift", StringComparison.OrdinalIgnoreCase))
                {
                    if ((mods & Native.ModShift) != 0) return false;
                    mods |= Native.ModShift;
                }
                else if (String.Equals(part, "Win", StringComparison.OrdinalIgnoreCase) || String.Equals(part, "Windows", StringComparison.OrdinalIgnoreCase))
                {
                    return false;
                }
                else
                {
                    if (hasKey) return false;
                    Keys parsed;
                    if (!Enum.TryParse<Keys>(part, true, out parsed)) return false;
                    parsed = parsed & Keys.KeyCode;
                    if (parsed == Keys.None || parsed == Keys.ControlKey || parsed == Keys.ShiftKey || parsed == Keys.Menu ||
                        parsed == Keys.LWin || parsed == Keys.RWin) return false;
                    key = parsed;
                    hasKey = true;
                }
            }
            if (key == Keys.F12) return false;
            bool bareFunctionKey = key >= Keys.F1 && key <= Keys.F24;
            if (!hasKey || (mods == 0 && !bareFunctionKey)) return false;
            spec = new HotkeySpec { Modifiers = mods, Key = key };
            return true;
        }

        public static string Format(Keys key, Keys modifiers)
        {
            StringBuilder result = new StringBuilder();
            if ((modifiers & Keys.Control) != 0) result.Append("Ctrl+");
            if ((modifiers & Keys.Alt) != 0) result.Append("Alt+");
            if ((modifiers & Keys.Shift) != 0) result.Append("Shift+");
            result.Append(key.ToString());
            return result.ToString();
        }
    }

    internal static class Native
    {
        public const uint ModAlt = 0x0001;
        public const uint ModControl = 0x0002;
        public const uint ModShift = 0x0004;
        private const uint ModNoRepeat = 0x4000;
        private const int WmHotkey = 0x0312;
        private const int WmClose = 0x0010;
        private const int DwmwaExtendedFrameBounds = 9;
        private const int DwmwaCloaked = 14;
        private const int TokenElevation = 20;
        private const uint ProcessQueryLimitedInformation = 0x1000;
        private const uint TokenQuery = 0x0008;
        private const int SwRestore = 9;
        private const int SwHide = 0;
        private const int SwShow = 5;
        private const int SwShowNoActivate = 4;
        private const uint SwpNoActivate = 0x0010;
        private const uint SwpNoZOrder = 0x0004;
        private const uint SwpShowWindow = 0x0040;
        private const uint SwpNoMove = 0x0002;
        private const uint SwpNoSize = 0x0001;
        private const uint SwpFrameChanged = 0x0020;
        private const int GwHwndPrev = 3;
        private const uint GwOwner = 4;
        private static readonly IntPtr HwndTopmost = new IntPtr(-1);
        private static readonly IntPtr HwndNotTopmost = new IntPtr(-2);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        private struct POINT { public int X; public int Y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct TOKEN_ELEVATION { public int TokenIsElevated; }

        [StructLayout(LayoutKind.Sequential)]
        public struct SIZE { public int cx; public int cy; }

        [StructLayout(LayoutKind.Sequential)]
        public struct DWM_THUMBNAIL_PROPERTIES
        {
            public uint dwFlags;
            public RECT rcDestination;
            public RECT rcSource;
            public byte opacity;
            [MarshalAs(UnmanagedType.Bool)] public bool fVisible;
            [MarshalAs(UnmanagedType.Bool)] public bool fSourceClientAreaOnly;
        }

        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int virtualKey);
        [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(POINT point);
        [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr handle, uint flags);
        public delegate bool EnumWindowsProc(IntPtr handle, IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint virtualKey);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool PostMessage(IntPtr hWnd, int message, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hWnd, uint command);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern bool ScreenToClient(IntPtr hWnd, ref POINT point);
        [DllImport("user32.dll")] private static extern IntPtr ChildWindowFromPointEx(IntPtr parent, POINT point, uint flags);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int maxCount);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll", SetLastError = true)] private static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out RECT value, int size);
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hWnd, int attribute, out int value, int size);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)] private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int index);
        [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)] private static extern IntPtr GetWindowLongPtr32(IntPtr hWnd, int index);
        [DllImport("gdi32.dll", SetLastError = true)] private static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);
        [DllImport("gdi32.dll", SetLastError = true)] private static extern int CombineRgn(IntPtr destination, IntPtr source1, IntPtr source2, int mode);
        [DllImport("gdi32.dll", SetLastError = true)] private static extern bool EqualRgn(IntPtr first, IntPtr second);
        [DllImport("user32.dll", SetLastError = true)] private static extern int GetWindowRgn(IntPtr hWnd, IntPtr region);
        [DllImport("user32.dll", SetLastError = true)] private static extern int SetWindowRgn(IntPtr hWnd, IntPtr region, bool redraw);
        [DllImport("gdi32.dll", SetLastError = true)] private static extern IntPtr CreatePolygonRgn(POINT[] points, int pointCount, int fillMode);
        [DllImport("gdi32.dll", SetLastError = true)] private static extern bool PtInRegion(IntPtr region, int x, int y);
        [DllImport("gdi32.dll", SetLastError = true)] private static extern bool DeleteObject(IntPtr handle);
        [DllImport("dwmapi.dll")] public static extern int DwmRegisterThumbnail(IntPtr destination, IntPtr source, out IntPtr thumbnail);
        [DllImport("dwmapi.dll")] public static extern int DwmUnregisterThumbnail(IntPtr thumbnail);
        [DllImport("dwmapi.dll")] public static extern int DwmQueryThumbnailSourceSize(IntPtr thumbnail, out SIZE size);
        [DllImport("dwmapi.dll")] public static extern int DwmUpdateThumbnailProperties(IntPtr thumbnail, ref DWM_THUMBNAIL_PROPERTIES properties);
        [DllImport("dwmapi.dll")] public static extern int DwmFlush();
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr GetDC(IntPtr handle);
        [DllImport("user32.dll", SetLastError = true)] private static extern int ReleaseDC(IntPtr handle, IntPtr dc);
        [DllImport("user32.dll", SetLastError = true)] internal static extern IntPtr SetWindowsHookEx(int hookId, HookProcedure callback, IntPtr module, uint threadId);
        [DllImport("user32.dll", SetLastError = true)] internal static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll", SetLastError = true)] internal static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr wParam, IntPtr lParam);
        [DllImport("gdi32.dll", SetLastError = true)] private static extern bool BitBlt(IntPtr destination, int destinationX, int destinationY, int width, int height, IntPtr source, int sourceX, int sourceY, uint operation);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr OpenProcess(uint access, bool inherit, uint processId);
        [DllImport("kernel32.dll", SetLastError = true)] private static extern bool CloseHandle(IntPtr handle);
        [DllImport("advapi32.dll", SetLastError = true)] private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true)] private static extern bool GetTokenInformation(IntPtr token, int infoClass, out TOKEN_ELEVATION information, int size, out int returned);

        internal const uint ScreenCaptureBltOperation = 0x00CC0020U | 0x40000000U;
        internal delegate IntPtr HookProcedure(int code, IntPtr wParam, IntPtr lParam);

        public static void CaptureScreen(Bitmap destination, Rectangle bounds)
        {
            if (destination == null) throw new ArgumentNullException("destination");
            if (bounds.Width <= 0 || bounds.Height <= 0 ||
                destination.Width != bounds.Width || destination.Height != bounds.Height)
                throw new ArgumentException("The destination bitmap must match the screen capture bounds.", "bounds");
            IntPtr sourceDc = GetDC(IntPtr.Zero);
            if (sourceDc == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not access the desktop drawing surface.");
            using (Graphics graphics = Graphics.FromImage(destination))
            {
                IntPtr destinationDc = IntPtr.Zero;
                try
                {
                    destinationDc = graphics.GetHdc();
                    if (!BitBlt(destinationDc, 0, 0, bounds.Width, bounds.Height, sourceDc, bounds.X, bounds.Y, ScreenCaptureBltOperation))
                        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not copy the screen into the snapshot.");
                }
                finally
                {
                    if (destinationDc != IntPtr.Zero) graphics.ReleaseHdc(destinationDc);
                    ReleaseDC(IntPtr.Zero, sourceDc);
                }
            }
            MakeBitmapOpaque(destination);
        }

        internal static void MakeBitmapOpaque(Bitmap bitmap)
        {
            if (bitmap == null) throw new ArgumentNullException("bitmap");
            Rectangle bounds = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
            BitmapData data = bitmap.LockBits(bounds, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            try
            {
                for (int y = 0; y < data.Height; y++)
                {
                    IntPtr row = IntPtr.Add(data.Scan0, y * data.Stride);
                    for (int x = 0; x < data.Width; x++)
                    {
                        IntPtr pixel = IntPtr.Add(row, x * 4);
                        Marshal.WriteInt32(pixel, Marshal.ReadInt32(pixel) | unchecked((int)0xFF000000));
                    }
                }
            }
            finally { bitmap.UnlockBits(data); }
        }

        public static bool RegisterHotkey(IntPtr handle, int id, uint modifiers, Keys key)
        {
            return RegisterHotKey(handle, id, modifiers | ModNoRepeat, (uint)key);
        }

        public static void PutTopmostWithoutActivate(IntPtr handle, Rectangle bounds)
        {
            SetWindowPos(handle, HwndTopmost, bounds.X, bounds.Y, bounds.Width, bounds.Height, SwpNoActivate | SwpShowWindow);
        }

        public static IntPtr RaiseWindowWithoutActivate(IntPtr handle, out bool wasTopmost)
        {
            IntPtr style = IntPtr.Size == 8 ? GetWindowLongPtr64(handle, -20) : GetWindowLongPtr32(handle, -20);
            wasTopmost = (style.ToInt64() & 0x00000008L) != 0;
            IntPtr previous = GetWindow(handle, GwHwndPrev);
            if (!SetWindowPos(handle, HwndTopmost, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoActivate))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not raise the source window for refresh capture.");
            return previous;
        }

        public static void RestoreWindowZOrder(IntPtr handle, IntPtr previous, bool wasTopmost)
        {
            if (!IsWindow(handle)) return;
            IntPtr insertAfter = HwndNotTopmost;
            if (wasTopmost) insertAfter = HwndTopmost;
            else if (previous != IntPtr.Zero && previous != handle && IsWindow(previous))
            {
                IntPtr previousStyle = IntPtr.Size == 8 ? GetWindowLongPtr64(previous, -20) : GetWindowLongPtr32(previous, -20);
                if ((previousStyle.ToInt64() & 0x00000008L) == 0) insertAfter = previous;
            }
            if (!SetWindowPos(handle, insertAfter, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoActivate))
            {
                if (!IsWindow(handle)) return;
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not restore the source window's z-order after refresh capture.");
            }
        }

        public static Bitmap CaptureWindowOnScreen(IntPtr handle, Rectangle bounds)
        {
            if (!IsWindowVisible(handle) || IsIconic(handle))
                throw new InvalidOperationException("The source window is not available for refresh capture.");
            bool wasTopmost;
            IntPtr previous = RaiseWindowWithoutActivate(handle, out wasTopmost);
            try
            {
                DwmFlush();
                Bitmap capture = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
                try
                {
                    CaptureScreen(capture, bounds);
                    return capture;
                }
                catch
                {
                    capture.Dispose();
                    throw;
                }
            }
            finally { RestoreWindowZOrder(handle, previous, wasTopmost); }
        }

        public static Bitmap ResizeCaptureToBounds(Bitmap capture, Size bounds)
        {
            if (capture == null) throw new ArgumentNullException("capture");
            if (bounds.Width < 1 || bounds.Height < 1)
                throw new ArgumentOutOfRangeException("bounds");
            if (capture.Size == bounds) return (Bitmap)capture.Clone();
            Bitmap resized = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
            try
            {
                using (Graphics graphics = Graphics.FromImage(resized))
                {
                    graphics.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                    graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                    graphics.DrawImage(capture, new Rectangle(Point.Empty, bounds));
                }
                return resized;
            }
            catch
            {
                resized.Dispose();
                throw;
            }
        }

        public static IntPtr CaptureWindowRegion(IntPtr handle, out bool hasRegion)
        {
            IntPtr region = CreateRectRgn(0, 0, 0, 0);
            if (region == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not allocate a region for live slicing.");
            int kind = GetWindowRgn(handle, region);
            if (kind == 0)
            {
                DeleteObject(region);
                hasRegion = false;
                return IntPtr.Zero;
            }
            hasRegion = true;
            return region;
        }

        public static void ApplyWindowPolygon(IntPtr handle, IList<PointF> polygon, Point origin, Size windowSize, IntPtr originalRegion, bool hasOriginalRegion)
        {
            POINT[] points = new POINT[polygon.Count];
            for (int i = 0; i < polygon.Count; i++)
                points[i] = new POINT { X = (int)Math.Round(polygon[i].X + origin.X), Y = (int)Math.Round(polygon[i].Y + origin.Y) };
            IntPtr sliceRegion = CreatePolygonRgn(points, points.Length, 1);
            if (sliceRegion == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not create the live window slice.");
            IntPtr region = CreateRectRgn(0, 0, Math.Max(1, windowSize.Width), Math.Max(1, windowSize.Height));
            if (region == IntPtr.Zero)
            {
                DeleteObject(sliceRegion);
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not allocate the live window region.");
            }

            if (hasOriginalRegion && CombineRgn(region, originalRegion, originalRegion, 5) == 0)
            {
                int error = Marshal.GetLastWin32Error();
                DeleteObject(sliceRegion);
                DeleteObject(region);
                throw new System.ComponentModel.Win32Exception(error, "Windows could not preserve the source window's existing shape.");
            }
            if (CombineRgn(region, region, sliceRegion, 1) == 0)
            {
                int error = Marshal.GetLastWin32Error();
                DeleteObject(sliceRegion);
                DeleteObject(region);
                throw new System.ComponentModel.Win32Exception(error, "Windows could not combine the live slice with the source window's shape.");
            }
            DeleteObject(sliceRegion);
            if (SetWindowRgn(handle, region, true) == 0)
            {
                int error = Marshal.GetLastWin32Error();
                DeleteObject(region);
                throw new System.ComponentModel.Win32Exception(error, "Windows could not apply the live window slice.");
            }
            RefreshNonClientFrame(handle);
        }

        public static void ApplyWindowPolygonExcludingShape(IntPtr handle, IList<PointF> polygon, IList<PointF> excludedShape, Point origin, Size windowSize, IntPtr originalRegion, bool hasOriginalRegion)
        {
            if (excludedShape == null || excludedShape.Count < 3)
                throw new ArgumentException("A closed shape is required for a live-window cutout.", "excludedShape");
            IntPtr polygonRegion = IntPtr.Zero;
            IntPtr excludedRegion = IntPtr.Zero;
            IntPtr region = IntPtr.Zero;
            try
            {
                POINT[] polygonPoints = new POINT[polygon.Count];
                for (int i = 0; i < polygon.Count; i++)
                    polygonPoints[i] = new POINT { X = (int)Math.Round(polygon[i].X + origin.X), Y = (int)Math.Round(polygon[i].Y + origin.Y) };
                polygonRegion = CreatePolygonRgn(polygonPoints, polygonPoints.Length, 1);
                if (polygonRegion == IntPtr.Zero)
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not create the live window remainder shape.");

                POINT[] excludedPoints = new POINT[excludedShape.Count];
                for (int i = 0; i < excludedShape.Count; i++)
                    excludedPoints[i] = new POINT { X = (int)Math.Round(excludedShape[i].X + origin.X), Y = (int)Math.Round(excludedShape[i].Y + origin.Y) };
                excludedRegion = CreatePolygonRgn(excludedPoints, excludedPoints.Length, 1);
                if (excludedRegion == IntPtr.Zero)
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not create the detached live shape.");

                region = CreateRectRgn(0, 0, Math.Max(1, windowSize.Width), Math.Max(1, windowSize.Height));
                if (region == IntPtr.Zero)
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not allocate the live window region.");
                if (hasOriginalRegion && CombineRgn(region, originalRegion, originalRegion, 5) == 0)
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not preserve the source window's existing shape.");
                if (CombineRgn(region, region, polygonRegion, 1) == 0)
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not combine the live window remainder shape.");
                if (CombineRgn(region, region, excludedRegion, 4) == 0)
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not subtract the detached shape from the live window.");
                if (SetWindowRgn(handle, region, true) == 0)
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not apply the live window shape cutout.");
                region = IntPtr.Zero;
                RefreshNonClientFrame(handle);
            }
            finally
            {
                if (polygonRegion != IntPtr.Zero) DeleteObject(polygonRegion);
                if (excludedRegion != IntPtr.Zero) DeleteObject(excludedRegion);
                if (region != IntPtr.Zero) DeleteObject(region);
            }
        }

        public static bool RestoreWindowRegion(IntPtr handle, IntPtr region)
        {
            if (SetWindowRgn(handle, region, true) == 0) return false;
            RefreshNonClientFrame(handle);
            return true;
        }

        private static void RefreshNonClientFrame(IntPtr handle)
        {
            if (!IsWindow(handle)) return;
            if (!SetWindowPos(handle, IntPtr.Zero, 0, 0, 0, 0,
                SwpNoMove | SwpNoSize | SwpNoZOrder | SwpNoActivate | SwpFrameChanged))
                System.Diagnostics.Trace.TraceWarning("Windows could not force a non-client redraw after changing a live window region: " +
                    new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error()).ToString());
        }

        public static bool RegionContainsPoint(IntPtr region, Point point)
        {
            return region != IntPtr.Zero && PtInRegion(region, point.X, point.Y);
        }

        public static IntPtr CloneGdiRegion(IntPtr source)
        {
            if (source == IntPtr.Zero) throw new ArgumentException("A source region is required.", "source");
            IntPtr copy = CreateRectRgn(0, 0, 0, 0);
            if (copy == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not allocate a copy of the source window region.");
            if (CombineRgn(copy, source, source, 5) == 0)
            {
                int error = Marshal.GetLastWin32Error();
                DeleteObject(copy);
                throw new System.ComponentModel.Win32Exception(error, "Windows could not copy the source window region.");
            }
            return copy;
        }

        public static bool DeleteGdiObject(IntPtr handle)
        {
            return handle == IntPtr.Zero || DeleteObject(handle);
        }

        public static bool RegionsEqual(IntPtr first, IntPtr second)
        {
            return EqualRgn(first, second);
        }

        public static bool IsWindowChildPoint(IntPtr parent, Point screenPoint, out IntPtr child, out Point clientPoint)
        {
            POINT nativePoint = new POINT { X = screenPoint.X, Y = screenPoint.Y };
            if (!ScreenToClient(parent, ref nativePoint)) { child = IntPtr.Zero; clientPoint = Point.Empty; return false; }
            clientPoint = new Point(nativePoint.X, nativePoint.Y);
            child = parent;
            for (int depth = 0; depth < 32; depth++)
            {
                POINT point = new POINT { X = clientPoint.X, Y = clientPoint.Y };
                IntPtr next = ChildWindowFromPointEx(child, point, 0x0001 | 0x0002);
                if (next == IntPtr.Zero || next == child) break;
                child = next;
                nativePoint = new POINT { X = screenPoint.X, Y = screenPoint.Y };
                if (!ScreenToClient(child, ref nativePoint)) return false;
                clientPoint = new Point(nativePoint.X, nativePoint.Y);
            }
            return true;
        }

        public static IntPtr FindInputWindowAtPoint(IntPtr sourceWindow, Point screenPoint)
        {
            IntPtr hit = WindowFromPoint(new POINT { X = screenPoint.X, Y = screenPoint.Y });
            if (hit == IntPtr.Zero) return IntPtr.Zero;
            IntPtr root = GetAncestor(hit, 2);
            if (root == IntPtr.Zero) root = hit;
            if (root == sourceWindow) return root;
            IntPtr owner = root;
            for (int depth = 0; depth < 32; depth++)
            {
                owner = GetWindow(owner, GwOwner);
                if (owner == IntPtr.Zero) break;
                if (owner == sourceWindow) return root;
            }
            return IntPtr.Zero;
        }

        public static bool IsStandardButton(IntPtr handle)
        {
            if (handle == IntPtr.Zero || !IsWindow(handle)) return false;
            StringBuilder className = new StringBuilder(32);
            if (GetClassName(handle, className, className.Capacity) == 0) return false;
            string value = className.ToString();
            return String.Equals(value, "Button", StringComparison.OrdinalIgnoreCase) ||
                value.IndexOf(".BUTTON.", StringComparison.OrdinalIgnoreCase) >= 0;
        }

        public static bool ClickStandardButton(IntPtr handle)
        {
            IntPtr result;
            return SendMessageTimeout(handle, 0x00F5, IntPtr.Zero, IntPtr.Zero, 0x0002, 650, out result) != IntPtr.Zero;
        }

        public static bool ClickStandardButtonWithMouse(IntPtr handle, Point clientPoint)
        {
            IntPtr result;
            int packed = ((clientPoint.Y & 0xFFFF) << 16) | (clientPoint.X & 0xFFFF);
            if (SendMessageTimeout(handle, 0x0200, IntPtr.Zero, new IntPtr(packed), 0x0002, 650, out result) == IntPtr.Zero)
                return false;
            if (SendMessageTimeout(handle, 0x0201, new IntPtr(0x0001), new IntPtr(packed), 0x0002, 650, out result) == IntPtr.Zero)
                return false;
            return SendMessageTimeout(handle, 0x0202, IntPtr.Zero, new IntPtr(packed), 0x0002, 650, out result) != IntPtr.Zero;
        }

        public static void HideWindow(IntPtr handle) { ShowWindow(handle, SwHide); }
        public static void ShowWindowWithoutActivate(IntPtr handle) { ShowWindow(handle, SwShowNoActivate); }
        public static void ShowWindowNormally(IntPtr handle) { ShowWindow(handle, SwShow); }
        public static bool IsPointOnWindow(IntPtr handle, Point point)
        {
            IntPtr hit = WindowFromPoint(new POINT { X = point.X, Y = point.Y });
            return hit == handle || GetAncestor(hit, 2) == handle;
        }
        public static bool SendCloseRequest(IntPtr handle)
        {
            IntPtr result;
            return SendMessageTimeout(handle, (uint)WmClose, IntPtr.Zero, IntPtr.Zero, 0x0002, 650, out result) != IntPtr.Zero;
        }

        public static int HitTestWindow(IntPtr handle, Point screenPoint)
        {
            IntPtr result;
            IntPtr packedPoint = new IntPtr(((screenPoint.Y & 0xFFFF) << 16) | (screenPoint.X & 0xFFFF));
            if (SendMessageTimeout(handle, 0x0084, IntPtr.Zero, packedPoint, 0x0002, 650, out result) == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not hit-test the source window frame.");
            return result.ToInt32();
        }

        public static bool TryGetFrameBounds(IntPtr handle, out Rectangle bounds)
        {
            RECT value;
            if (DwmGetWindowAttribute(handle, DwmwaExtendedFrameBounds, out value, Marshal.SizeOf(typeof(RECT))) == 0 && value.Right > value.Left && value.Bottom > value.Top)
            {
                bounds = Rectangle.FromLTRB(value.Left, value.Top, value.Right, value.Bottom);
                return true;
            }
            RECT fallback;
            if (GetWindowRect(handle, out fallback) && fallback.Right > fallback.Left && fallback.Bottom > fallback.Top)
            {
                bounds = Rectangle.FromLTRB(fallback.Left, fallback.Top, fallback.Right, fallback.Bottom);
                return true;
            }
            bounds = Rectangle.Empty;
            return false;
        }

        public static bool IsCloaked(IntPtr handle)
        {
            int value;
            return DwmGetWindowAttribute(handle, DwmwaCloaked, out value, sizeof(int)) == 0 && value != 0;
        }

        public static bool IsLayeredWindow(IntPtr handle)
        {
            IntPtr style = IntPtr.Size == 8 ? GetWindowLongPtr64(handle, -20) : GetWindowLongPtr32(handle, -20);
            return (((long)style) & 0x00080000L) != 0;
        }

        public static bool IsElevatedProcess(uint pid, out bool elevated, out string failure)
        {
            elevated = false;
            failure = null;
            IntPtr process = OpenProcess(ProcessQueryLimitedInformation, false, pid);
            if (process == IntPtr.Zero)
            {
                failure = "Windows denied access to that process (it may be protected).";
                return false;
            }
            try
            {
                IntPtr token;
                if (!OpenProcessToken(process, TokenQuery, out token))
                {
                    failure = "Windows denied access to that process token (it may be protected).";
                    return false;
                }
                try
                {
                    TOKEN_ELEVATION info;
                    int returned;
                    if (!GetTokenInformation(token, TokenElevation, out info, Marshal.SizeOf(typeof(TOKEN_ELEVATION)), out returned))
                    {
                        failure = "Windows could not report that process's security level.";
                        return false;
                    }
                    elevated = info.TokenIsElevated != 0;
                    return true;
                }
                finally { CloseHandle(token); }
            }
            finally { CloseHandle(process); }
        }

        public static bool IsCurrentProcessElevated()
        {
            IntPtr token;
            if (!OpenProcessToken(Process.GetCurrentProcess().Handle, TokenQuery, out token)) return false;
            try
            {
                TOKEN_ELEVATION info;
                int returned;
                return GetTokenInformation(token, TokenElevation, out info, Marshal.SizeOf(typeof(TOKEN_ELEVATION)), out returned) && info.TokenIsElevated != 0;
            }
            finally { CloseHandle(token); }
        }

        public static bool IsDesktopOrTaskbar(IntPtr handle)
        {
            StringBuilder name = new StringBuilder(128);
            GetClassName(handle, name, name.Capacity);
            string cls = name.ToString();
            return cls == "Progman" || cls == "WorkerW" || cls == "Shell_TrayWnd" || cls == "Shell_SecondaryTrayWnd";
        }

        public static bool IsCloseMessage(int message) { return message == WmHotkey; }
        public static bool IsKeyDown(Keys key) { return (GetAsyncKeyState((int)(key & Keys.KeyCode)) & unchecked((short)0x8000)) != 0; }
        public static bool IsHotkeyDown(HotkeySpec spec)
        {
            if (spec == null || !IsKeyDown(spec.Key)) return false;
            if ((spec.Modifiers & ModControl) != 0 && !IsKeyDown(Keys.ControlKey)) return false;
            if ((spec.Modifiers & ModAlt) != 0 && !IsKeyDown(Keys.Menu)) return false;
            if ((spec.Modifiers & ModShift) != 0 && !IsKeyDown(Keys.ShiftKey)) return false;
            return true;
        }
        public static int CloseMessage { get { return WmClose; } }
        public static int HotkeyMessage { get { return WmHotkey; } }
        public static int RestoreCommand { get { return SwRestore; } }
    }

    internal sealed class HotkeyHost : NativeWindow, IDisposable
    {
        private Action _callback;
        private bool _registered;
        private string _registeredText;

        public HotkeyHost(Action callback)
        {
            _callback = callback;
            CreateHandle(new CreateParams());
        }

        public bool Set(string text, out string error)
        {
            return SetCore(text, 1, ref _registered, ref _registeredText, out error);
        }

        public bool SetOptional(string text, out string error)
        {
            if (String.IsNullOrWhiteSpace(text))
            {
                Clear();
                error = null;
                return true;
            }
            return Set(text, out error);
        }

        public void Clear()
        {
            if (_registered) Native.UnregisterHotKey(Handle, 1);
            _registered = false;
            _registeredText = null;
        }

        public bool SetUnmodified(Keys key, out string error)
        {
            error = null;
            if (_registered)
            {
                Native.UnregisterHotKey(Handle, 1);
                _registered = false;
                _registeredText = null;
            }
            if (key == Keys.None || key == Keys.F12)
            {
                error = "The temporary keyboard command is invalid.";
                return false;
            }
            if (!Native.RegisterHotkey(Handle, 1, 0, key))
            {
                int code = Marshal.GetLastWin32Error();
                error = "Windows could not reserve " + key.ToString() + " while Precision Slice is open." + (code == 0 ? "" : " (Windows error " + code.ToString() + ")");
                return false;
            }
            _registered = true;
            _registeredText = key.ToString();
            return true;
        }

        private bool SetCore(string text, int id, ref bool registered, ref string registeredText, out string error)
        {
            error = null;
            string previous = registeredText;
            if (registered)
            {
                Native.UnregisterHotKey(Handle, id);
                registered = false;
                registeredText = null;
            }
            HotkeySpec spec;
            if (!HotkeySpec.TryParse(text, out spec))
            {
                Restore(id, previous, ref registered, ref registeredText);
                error = "The shortcut is invalid. Use Ctrl, Alt, or Shift with a key, or choose F1–F11 or F13–F24 by itself. Windows reserves F12 for debuggers.";
                return false;
            }
            if (!Native.RegisterHotkey(Handle, id, spec.Modifiers, spec.Key))
            {
                int code = Marshal.GetLastWin32Error();
                Restore(id, previous, ref registered, ref registeredText);
                error = "Windows could not register " + text + ". Another app may already use it. Choose a different shortcut." +
                    (previous == null ? "" : " The previous shortcut " + previous + " remains active if Windows allowed it to be restored.");
                if (code != 0) error += " (Windows error " + code.ToString() + ")";
                return false;
            }
            registered = true;
            registeredText = text;
            return true;
        }

        private void Restore(int id, string text, ref bool registered, ref string registeredText)
        {
            if (String.IsNullOrEmpty(text)) return;
            HotkeySpec previous;
            if (HotkeySpec.TryParse(text, out previous) && Native.RegisterHotkey(Handle, id, previous.Modifiers, previous.Key))
            {
                registered = true;
                registeredText = text;
            }
        }

        public string ActiveText { get { return _registeredText; } }
        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Native.HotkeyMessage && m.WParam.ToInt32() == 1)
            {
                if (_callback != null) _callback();
            }
            base.WndProc(ref m);
        }

        public void Dispose()
        {
            if (_registered) Native.UnregisterHotKey(Handle, 1);
            _registered = false;
            _callback = null;
            DestroyHandle();
        }
    }

    internal sealed class WindowTarget
    {
        public IntPtr Handle;
        public uint ProcessId;
        public string Title;
        public bool IsUtilityWarningDialog;
        public SliceForm Fragment;
        public SliceAnimation SnapshotOwner;
        public bool IsScreenCapture;
        public Rectangle ScreenBounds;
        public Bitmap ScreenImage;

        public static WindowTarget ForFragment(SliceForm fragment)
        {
            if (fragment == null || fragment.IsDisposed || !fragment.IsHandleCreated) return null;
            return new WindowTarget { Handle = fragment.Handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = "this fragment", Fragment = fragment };
        }

        public static WindowTarget ForWaitingSnapshot(SliceForm snapshot, SliceAnimation owner)
        {
            if (snapshot == null || snapshot.IsDisposed || !snapshot.IsHandleCreated || owner == null) return null;
            return new WindowTarget
            {
                Handle = snapshot.Handle,
                ProcessId = (uint)Process.GetCurrentProcess().Id,
                Title = "this snapshot",
                Fragment = snapshot,
                SnapshotOwner = owner
            };
        }

        public static WindowTarget ForScreenCapture(Rectangle bounds, int monitorIndex)
        {
            return new WindowTarget
            {
                Handle = new IntPtr(-1000 - monitorIndex),
                ProcessId = (uint)Process.GetCurrentProcess().Id,
                Title = "the current monitor",
                IsScreenCapture = true,
                ScreenBounds = bounds
            };
        }

        public static WindowTarget Read(IntPtr handle)
{
    if (handle == IntPtr.Zero || !Native.IsWindow(handle)) return null;

    uint pid;
    Native.GetWindowThreadProcessId(handle, out pid);
    if (pid == 0) return null;

    StringBuilder title = new StringBuilder(512);
    Native.GetWindowText(handle, title, title.Capacity);

    StringBuilder className = new StringBuilder(128);
    Native.GetClassName(handle, className, className.Capacity);

    bool utilityWarningDialog = IsOwnUtilityWarningDialog(
        pid, className.ToString(), title.ToString()
    );

    bool utilitySettingsWindow = IsOwnSettingsWindow(
        pid, title.ToString()
    );

    if (pid == (uint)Process.GetCurrentProcess().Id &&
        !utilityWarningDialog &&
        !utilitySettingsWindow)
        return null;

    return new WindowTarget
    {
        Handle = handle,
        ProcessId = pid,
        Title = title.Length == 0 ? "this window" : title.ToString(),
        IsUtilityWarningDialog = utilityWarningDialog
    };
}

internal static bool IsOwnSettingsWindow(uint processId, string title)
{
    return processId == (uint)Process.GetCurrentProcess().Id &&
        String.Equals(title, "Window Slice settings", StringComparison.Ordinal);
}

internal static bool IsOwnUtilityWarningDialog(uint processId, string className, string title)
{
    if (processId != (uint)Process.GetCurrentProcess().Id ||
        !String.Equals(className, "#32770", StringComparison.Ordinal))
        return false;

    return String.Equals(title, "Window Slice", StringComparison.Ordinal) ||
        String.Equals(title, "Shortcut", StringComparison.Ordinal);
}

        public bool IsStillSameWindow()
        {
            if (IsScreenCapture) return true;
            if (Fragment != null)
                return !Fragment.IsDisposed &&
                    (PersistentFragmentStore.Contains(Fragment) || (SnapshotOwner != null && SnapshotOwner.IsWaitingSnapshot(Fragment)));
            if (!Native.IsWindow(Handle)) return false;
            uint current;
            Native.GetWindowThreadProcessId(Handle, out current);
            return current == ProcessId;
        }
    }

    internal sealed class LiveWindowSliceSession
    {
        private readonly WindowTarget _target;
        private readonly Rectangle _sourceBounds;
        private readonly List<SliceForm> _detachedPieces = new List<SliceForm>();
        private readonly System.Windows.Forms.Timer _refreshTimer;
        private readonly SynchronizationContext _refreshContext;
        private readonly bool _refreshFragments;
        private readonly object _regionSync = new object();
        private WindowSlice.LiveCapture.LiveWindowCapture _liveCapture;
        private List<PointF> _remainingPolygon;
        private List<PointF> _excludedShape;
        private IntPtr _originalRegion;
        private bool _hadOriginalRegion;
        private bool _restored;
        private bool _restoring;
        private bool _inputFailureReported;
        private bool _refreshFailureReported;
        private bool _liveCaptureUnavailable;
        private int _refreshInProgress;

        public LiveWindowSliceSession(WindowTarget target, Rectangle sourceBounds)
            : this(target, sourceBounds, false)
        {
        }

        public LiveWindowSliceSession(WindowTarget target, Rectangle sourceBounds, bool refreshFragments)
        {
            if (target == null || target.Fragment != null || target.IsScreenCapture)
                throw new ArgumentException("Live slicing requires a top-level window.", "target");
            if (!target.IsStillSameWindow())
                throw new InvalidOperationException("The selected window is no longer available.");
            _target = target;
            _sourceBounds = sourceBounds;
            _originalRegion = Native.CaptureWindowRegion(target.Handle, out _hadOriginalRegion);
            _refreshFragments = refreshFragments;
            _refreshTimer = new System.Windows.Forms.Timer();
            _refreshTimer.Interval = refreshFragments ? 100 : 250;
            _refreshTimer.Tick += delegate
            {
                MonitorTargetWindow();
                if (!_restored && !_refreshFailureReported && _refreshFragments) RefreshDetachedPieces();
            };
            if (refreshFragments)
                _refreshContext = SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();
            PersistentFragmentStore.RegisterLiveSession(this);
            _refreshTimer.Start();
        }

        public void ApplyRemainingPolygon(IList<PointF> polygon)
        {
            ApplyRemainingPolygon(polygon, null);
        }

        public void ApplyRemainingPolygon(IList<PointF> polygon, IList<PointF> excludedShape)
        {
            lock (_regionSync)
            {
                if (_restored || !_target.IsStillSameWindow())
                    throw new InvalidOperationException("The source window is no longer available for live slicing.");
                Native.RECT windowBounds;
                if (!Native.GetWindowRect(_target.Handle, out windowBounds))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not locate the source window for live slicing.");
                Point regionOffset = new Point(_sourceBounds.X - windowBounds.Left, _sourceBounds.Y - windowBounds.Top);
                Size windowSize = new Size(windowBounds.Right - windowBounds.Left, windowBounds.Bottom - windowBounds.Top);
                if (excludedShape != null)
                    Native.ApplyWindowPolygonExcludingShape(_target.Handle, polygon, excludedShape, regionOffset, windowSize, _originalRegion, _hadOriginalRegion);
                else
                    Native.ApplyWindowPolygon(_target.Handle, polygon, regionOffset, windowSize, _originalRegion, _hadOriginalRegion);
                _remainingPolygon = polygon == null ? null : new List<PointF>(polygon);
                _excludedShape = excludedShape == null ? null : new List<PointF>(excludedShape);
            }
        }

        public void Attach(SliceForm piece, Rectangle originalPieceBounds, bool forwardInput)
        {
            if (piece == null || _restored) throw new InvalidOperationException("The live slice is no longer active.");
            if (_detachedPieces.Contains(piece)) return;
            _detachedPieces.Add(piece);
            piece.AttachLiveSliceSession(this, originalPieceBounds, forwardInput);
            if (_refreshFragments) RefreshDetachedPieces();
        }

        internal void MonitorTargetWindow()
        {
            if (!_restored && !_target.IsStillSameWindow()) Restore();
        }

        internal void CommitRemainingWindow()
        {
            if (_restored || _restoring) return;
            _restoring = true;
            try
            {
                if (_refreshTimer != null)
                {
                    _refreshTimer.Stop();
                    _refreshTimer.Dispose();
                }
                lock (_regionSync)
                {
                    if (_originalRegion != IntPtr.Zero)
                    {
                        Native.DeleteGdiObject(_originalRegion);
                        _originalRegion = IntPtr.Zero;
                    }
                    _restored = true;
                }
                DisposeLiveCaptureOnWorker();
                PersistentFragmentStore.UnregisterLiveSession(this);
                SliceForm[] pieces = _detachedPieces.ToArray();
                _detachedPieces.Clear();
                for (int i = 0; i < pieces.Length; i++)
                {
                    if (pieces[i] == null || pieces[i].IsDisposed) continue;
                    pieces[i].ClearLiveSliceSession(this);
                    PersistentFragmentStore.Remove(pieces[i]);
                    pieces[i].Close();
                }
            }
            finally { _restoring = false; }
        }

        private void RefreshDetachedPieces()
        {
            if (_restored || _refreshTimer == null) return;
            if (!_target.IsStillSameWindow())
            {
                Restore();
                return;
            }
            if (_remainingPolygon == null)
            {
                ReportRefreshFailure(new InvalidOperationException("The live window's remaining shape is unavailable."));
                return;
            }
            if (Interlocked.CompareExchange(ref _refreshInProgress, 1, 0) != 0) return;
            bool queued = ThreadPool.QueueUserWorkItem(delegate
            {
                Bitmap currentWindow = null;
                Exception failure = null;
                try
                {
                    lock (_regionSync)
                    {
                        if (!_restored && _target.IsStillSameWindow() &&
                            Native.IsWindowVisible(_target.Handle) && !Native.IsIconic(_target.Handle))
                        {
                            currentWindow = CaptureLiveWindow();
                            if (currentWindow == null)
                            {
                                List<IntPtr> visiblePieces = new List<IntPtr>();
                                for (int i = 0; i < _detachedPieces.Count; i++)
                                {
                                    SliceForm piece = _detachedPieces[i];
                                    if (piece == null || piece.IsDisposed || !piece.Visible || !piece.IsHandleCreated) continue;
                                    visiblePieces.Add(piece.Handle);
                                }
                                bool fullRegionApplied = false;
                                try
                                {
                                    for (int i = 0; i < visiblePieces.Count; i++)
                                        Native.HideWindow(visiblePieces[i]);
                                    IntPtr fullRegion = _hadOriginalRegion ? Native.CloneGdiRegion(_originalRegion) : IntPtr.Zero;
                                    if (!Native.RestoreWindowRegion(_target.Handle, fullRegion))
                                    {
                                        if (fullRegion != IntPtr.Zero) Native.DeleteGdiObject(fullRegion);
                                        throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not expose the source window for refresh capture.");
                                    }
                                    fullRegionApplied = true;
                                    currentWindow = Native.CaptureWindowOnScreen(_target.Handle, _sourceBounds);
                                }
                                catch
                                {
                                    if (currentWindow != null) { currentWindow.Dispose(); currentWindow = null; }
                                    throw;
                                }
                                finally
                                {
                                    try
                                    {
                                        if (fullRegionApplied && !_restored && _target.IsStillSameWindow())
                                            RestoreLiveWindowRegion();
                                    }
                                    finally
                                    {
                                        for (int i = 0; i < visiblePieces.Count; i++)
                                            if (Native.IsWindow(visiblePieces[i]))
                                                Native.ShowWindowWithoutActivate(visiblePieces[i]);
                                    }
                                }
                            }
                        }
                    }
                }
                catch (Exception ex) { failure = ex; }

                try
                {
                    _refreshContext.Post(delegate
                    {
                        try
                        {
                            if (_restored) return;
                            if (!_target.IsStillSameWindow())
                            {
                                Restore();
                                return;
                            }
                            if (failure != null)
                            {
                                ReportRefreshFailure(failure);
                                return;
                            }
                            if (currentWindow == null) return;
                            for (int i = 0; i < _detachedPieces.Count; i++)
                            {
                                SliceForm piece = _detachedPieces[i];
                                if (piece != null && !piece.IsDisposed)
                                    piece.RefreshFromLiveWindow(currentWindow, _sourceBounds.Location);
                            }
                        }
                        catch (Exception ex) { ReportRefreshFailure(ex); }
                        finally
                        {
                            if (currentWindow != null) currentWindow.Dispose();
                            Interlocked.Exchange(ref _refreshInProgress, 0);
                        }
                    }, null);
                }
                catch (Exception ex)
                {
                    if (currentWindow != null) currentWindow.Dispose();
                    Interlocked.Exchange(ref _refreshInProgress, 0);
                    System.Diagnostics.Trace.TraceError("Window Slice could not dispatch a live-fragment refresh: " + ex.ToString());
                }
            });
            if (!queued)
            {
                Interlocked.Exchange(ref _refreshInProgress, 0);
                ReportRefreshFailure(new InvalidOperationException("Windows could not schedule the fragment refresh task."));
            }
        }

        private Bitmap CaptureLiveWindow()
        {
            if (_liveCaptureUnavailable) return null;
            bool fullRegionApplied = false;
            try
            {
                if (_liveCapture == null)
                    _liveCapture = WindowSlice.LiveCapture.LiveWindowCapture.Create(_target.Handle);
                _liveCapture.DiscardPendingFrames();
                IntPtr fullRegion = _hadOriginalRegion ? Native.CloneGdiRegion(_originalRegion) : IntPtr.Zero;
                if (!Native.RestoreWindowRegion(_target.Handle, fullRegion))
                {
                    if (fullRegion != IntPtr.Zero) Native.DeleteGdiObject(fullRegion);
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not expose the source window for live capture.");
                }
                fullRegionApplied = true;
                Native.DwmFlush();
                Thread.Sleep(40);
                _liveCapture.DiscardPendingFrames();
                using (Bitmap frame = _liveCapture.Capture())
                    return Native.ResizeCaptureToBounds(frame, _sourceBounds.Size);
            }
            catch (Exception ex)
            {
                if (_liveCapture != null)
                {
                    _liveCapture.Dispose();
                    _liveCapture = null;
                }
                _liveCaptureUnavailable = true;
                System.Diagnostics.Trace.TraceWarning("Windows Graphics Capture is unavailable for live-fragment refresh; falling back to screen capture: " + ex.ToString());
                return null;
            }
            finally
            {
                if (fullRegionApplied && !_restored && _target.IsStillSameWindow())
                    RestoreLiveWindowRegion();
            }
        }

        private void RestoreLiveWindowRegion()
        {
            Native.RECT windowBounds;
            if (!Native.GetWindowRect(_target.Handle, out windowBounds))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not locate the source window after refresh.");
            Point regionOffset = new Point(_sourceBounds.X - windowBounds.Left, _sourceBounds.Y - windowBounds.Top);
            Size windowSize = new Size(windowBounds.Right - windowBounds.Left, windowBounds.Bottom - windowBounds.Top);
            if (_excludedShape != null)
                Native.ApplyWindowPolygonExcludingShape(_target.Handle, _remainingPolygon, _excludedShape, regionOffset, windowSize, _originalRegion, _hadOriginalRegion);
            else
                Native.ApplyWindowPolygon(_target.Handle, _remainingPolygon, regionOffset, windowSize, _originalRegion, _hadOriginalRegion);
        }

        private void ReportRefreshFailure(Exception ex)
        {
            if (_refreshFailureReported) return;
            _refreshFailureReported = true;
            MessageBox.Show("Window Slice could not refresh the detached fragments. They will keep their last image. Bring the source window to the front and retry; some apps may not refresh reliably.\r\n\r\n" + ex.Message, "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        public bool ForwardMouse(SliceForm piece, MouseEventArgs e, int message, int buttonState)
        {
            if (_restored || !_target.IsStillSameWindow() || piece == null) return false;
            if (message == 0) return false;
            Point cursor = System.Windows.Forms.Cursor.Position;
            Point originalPoint = piece.MapToOriginalScreen(cursor);
            IntPtr inputWindow = Native.FindInputWindowAtPoint(_target.Handle, originalPoint);
            if (inputWindow == IntPtr.Zero) inputWindow = _target.Handle;
            IntPtr child;
            Point clientPoint;
            if (!Native.IsWindowChildPoint(inputWindow, originalPoint, out child, out clientPoint))
            {
                inputWindow = _target.Handle;
                if (!Native.IsWindowChildPoint(inputWindow, originalPoint, out child, out clientPoint))
                {
                    ReportInputFailure();
                    return false;
                }
            }
            if (child == IntPtr.Zero) child = inputWindow;
            if ((message == 0x0201 || message == 0x0203) && Native.IsStandardButton(child))
            {
                piece.BeginLiveButtonClick(child);
                return true;
            }
            if (message == 0x0202)
            {
                IntPtr pendingButton = piece.TakeLiveButtonClick();
                if (pendingButton != IntPtr.Zero)
                {
                    if (pendingButton == child && Native.IsStandardButton(pendingButton))
                    {
                        bool clickFocusAvailable = Native.SetForegroundWindow(inputWindow) || Native.GetForegroundWindow() == inputWindow;
                        bool clicked = inputWindow == _target.Handle
                            ? Native.ClickStandardButton(pendingButton)
                            : Native.ClickStandardButtonWithMouse(pendingButton, clientPoint);
                        if (!clicked || !clickFocusAvailable) ReportInputFailure();
                        return clicked;
                    }
                    return false;
                }
            }
            bool sent;
            bool focusAvailable = true;
            if (message == 0x020A)
            {
                IntPtr wheel = new IntPtr(((e.Delta & 0xFFFF) << 16) | (buttonState & 0xFFFF));
                IntPtr screen = new IntPtr(((originalPoint.Y & 0xFFFF) << 16) | (originalPoint.X & 0xFFFF));
                sent = Native.PostMessage(child, message, wheel, screen);
            }
            else
            {
                if (!Native.IsWindow(child)) child = _target.Handle;
                if (message == 0x0201) buttonState |= 0x0001;
                else if (message == 0x0204) buttonState |= 0x0002;
                else if (message == 0x0207) buttonState |= 0x0010;
                if (message == 0x0201 || message == 0x0204 || message == 0x0207 || message == 0x020B)
                    focusAvailable = Native.SetForegroundWindow(inputWindow) || Native.GetForegroundWindow() == inputWindow;
                if (e.Button == MouseButtons.XButton1) buttonState |= 0x00010000;
                else if (e.Button == MouseButtons.XButton2) buttonState |= 0x00020000;
                int packed = ((clientPoint.Y & 0xFFFF) << 16) | (clientPoint.X & 0xFFFF);
                if (message == 0x0201 || message == 0x0204 || message == 0x0207 || message == 0x020B)
                    Native.PostMessage(child, 0x0200, new IntPtr(buttonState), new IntPtr(packed));
                sent = Native.PostMessage(child, message, new IntPtr(buttonState), new IntPtr(packed));
            }
            if (!sent || !focusAvailable) ReportInputFailure();
            return sent;
        }

        private void ReportInputFailure()
        {
            if (_inputFailureReported) return;
            _inputFailureReported = true;
            MessageBox.Show("Windows or the target app blocked input forwarding for this detached piece. Forwarding and keyboard focus are best-effort and may not work with every app.", "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }

        public void Restore()
        {
            if (_restored || _restoring) return;
            _restoring = true;
            try
            {
                if (_refreshTimer != null)
                    _refreshTimer.Stop();
                lock (_regionSync)
                {
                    if (_target.IsStillSameWindow())
                    {
                        if (!Native.RestoreWindowRegion(_target.Handle, _hadOriginalRegion ? _originalRegion : IntPtr.Zero))
                            throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not restore the source window's original shape.");
                        _originalRegion = IntPtr.Zero;
                    }
                    else if (_originalRegion != IntPtr.Zero)
                    {
                        Native.DeleteGdiObject(_originalRegion);
                        _originalRegion = IntPtr.Zero;
                    }
                    _restored = true;
                }
                if (_refreshTimer != null) _refreshTimer.Dispose();
                DisposeLiveCaptureOnWorker();
                PersistentFragmentStore.UnregisterLiveSession(this);
                SliceForm[] pieces = _detachedPieces.ToArray();
                _detachedPieces.Clear();
                for (int i = 0; i < pieces.Length; i++)
                {
                    if (pieces[i] == null || pieces[i].IsDisposed) continue;
                    pieces[i].ClearLiveSliceSession(this);
                    PersistentFragmentStore.Remove(pieces[i]);
                    pieces[i].Close();
                }
            }
            finally
            {
                _restoring = false;
                if (!_restored && _refreshTimer != null && !_refreshFailureReported) _refreshTimer.Start();
            }
        }

        private void DisposeLiveCaptureOnWorker()
        {
            WindowSlice.LiveCapture.LiveWindowCapture capture = _liveCapture;
            _liveCapture = null;
            if (capture == null) return;
            if (!ThreadPool.QueueUserWorkItem(delegate
            {
                try { capture.Dispose(); }
                catch (Exception ex) { System.Diagnostics.Trace.TraceError("Window Slice could not dispose its live capture session: " + ex.ToString()); }
            }))
                System.Diagnostics.Trace.TraceError("Window Slice could not schedule disposal of its live capture session.");
        }

        public void Detach(SliceForm piece)
        {
            _detachedPieces.Remove(piece);
            if (!_restoring && !_restored && _detachedPieces.Count == 0) Restore();
        }
    }

    internal sealed class WindowSelectionForm : Form
    {
        private readonly string _hotkeyText;
        private readonly Func<Rectangle, List<WindowTarget>> _scan;
        private Action<bool, Rectangle, List<WindowTarget>> _completed;
        private readonly System.Windows.Forms.Timer _timer = new System.Windows.Forms.Timer();
        private readonly Rectangle _virtualScreen;
        private readonly Stopwatch _scanClock = new Stopwatch();
        private List<WindowTarget> _targets = new List<WindowTarget>();
        private Point _start;
        private Point _current;
        private bool _dragging;
        private bool _hasDragArea;
        private bool _finished;
        private bool _dirty;

        public WindowSelectionForm(string hotkey, Func<Rectangle, List<WindowTarget>> scan, Action<bool, Rectangle, List<WindowTarget>> completed)
        {
            _hotkeyText = hotkey;
            _scan = scan;
            _completed = completed;
            _virtualScreen = SystemInformation.VirtualScreen;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            Bounds = _virtualScreen;
            TopMost = true;
            BackColor = Color.FromArgb(20, 24, 32);
            Opacity = 0.24;
            DoubleBuffered = true;
            Cursor = Cursors.Cross;
            _timer.Interval = 20;
            _timer.Tick += OnTimerTick;
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00000080 | 0x08000000;
                return cp;
            }
        }

        public void Begin()
        {
            Show();
            Native.PutTopmostWithoutActivate(Handle, Bounds);
            _timer.Start();
        }

        public void Cancel() { Complete(true); }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _timer.Stop();
                _timer.Dispose();
            }
            base.Dispose(disposing);
        }

        private void OnTimerTick(object sender, EventArgs e)
        {
            if (_finished) return;

            if (_dirty && (!_scanClock.IsRunning || _scanClock.ElapsedMilliseconds >= 50)) UpdateTargets();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Right)
            {
                Complete(true);
                return;
            }
            if (e.Button != MouseButtons.Left) return;
            _dragging = true;
            _hasDragArea = false;
            _start = PointToScreen(e.Location);
            _current = _start;
            _dirty = true;
            Capture = true;
            Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (!_dragging) return;
            _current = PointToScreen(e.Location);
            Rectangle area = GetSelectionBounds();
            _hasDragArea = IsValidSelectionArea(area);
            _dirty = true;
            Invalidate();
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (!_dragging || e.Button != MouseButtons.Left) return;
            _current = PointToScreen(e.Location);
            Rectangle area = GetSelectionBounds();
            _hasDragArea = IsValidSelectionArea(area);
            _dragging = false;
            Capture = false;
            _dirty = true;
            Invalidate();

            Complete(!_hasDragArea);
        }

        private Rectangle GetSelectionBounds()
        {
            return NormalizeSelectionBounds(_start, _current);
        }

        internal static Rectangle NormalizeSelectionBounds(Point start, Point end)
        {
            return Rectangle.FromLTRB(Math.Min(start.X, end.X), Math.Min(start.Y, end.Y), Math.Max(start.X, end.X), Math.Max(start.Y, end.Y));
        }

        internal static bool IsValidSelectionArea(Rectangle area) { return area.Width >= 12 && area.Height >= 12; }
        internal static bool IntersectsWindow(Rectangle area, Rectangle windowBounds) { return IsValidSelectionArea(area) && area.IntersectsWith(windowBounds); }

        private void UpdateTargets()
        {
            _scanClock.Restart();
            _dirty = false;
            if (!_hasDragArea) { _targets = new List<WindowTarget>(); return; }
            try { _targets = _scan == null ? new List<WindowTarget>() : _scan(GetSelectionBounds()); }
            catch { _targets = new List<WindowTarget>(); }
        }

        private void Complete(bool cancelled)
        {
            if (_finished) return;
            _finished = true;
            _timer.Stop();
            _timer.Tick -= OnTimerTick;
            _timer.Dispose();
            Capture = false;
            if (_hasDragArea && !cancelled) UpdateTargets();
            Rectangle area = _hasDragArea ? GetSelectionBounds() : Rectangle.Empty;
            List<WindowTarget> targets = _hasDragArea ? _targets : new List<WindowTarget>();
            Action<bool, Rectangle, List<WindowTarget>> callback = _completed;
            _completed = null;
            Hide();
            Close();
            if (callback != null) callback(cancelled, area, targets);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using (Pen windowPen = new Pen(Color.FromArgb(240, 255, 85, 65), 3.0f))
            using (Pen selectionPen = new Pen(Color.FromArgb(255, 110, 210, 255), 3.0f))
            using (SolidBrush selectionFill = new SolidBrush(Color.FromArgb(34, 45, 160, 230)))
            using (SolidBrush textBrush = new SolidBrush(Color.White))
            using (Font textFont = new Font("Segoe UI", 14.0f, FontStyle.Bold))
            using (Font smallFont = new Font("Segoe UI", 10.0f, FontStyle.Regular))
            {
                for (int i = 0; i < _targets.Count; i++)
                {
                    Rectangle bounds;
                    if (!Native.TryGetFrameBounds(_targets[i].Handle, out bounds)) continue;
                    bounds = Rectangle.Intersect(bounds, _virtualScreen);
                    bounds.Offset(-_virtualScreen.X, -_virtualScreen.Y);
                    if (bounds.Width > 1 && bounds.Height > 1) e.Graphics.DrawRectangle(windowPen, bounds.X, bounds.Y, bounds.Width - 1, bounds.Height - 1);
                }
                if (_dragging || _hasDragArea)
                {
                    Rectangle selection = GetSelectionBounds();
                    selection.Offset(-_virtualScreen.X, -_virtualScreen.Y);
                    if (selection.Width > 1 && selection.Height > 1)
                    {
                        e.Graphics.FillRectangle(selectionFill, selection);
                        e.Graphics.DrawRectangle(selectionPen, selection.X, selection.Y, selection.Width, selection.Height);
                    }
                }
                string instructions = "Selection (" + _hotkeyText + ") • drag and release to slice • left-click without dragging to exit • right-click to cancel";
                e.Graphics.DrawString(instructions, textFont, textBrush, 24.0f, 22.0f);
                if (_hasDragArea)
                    e.Graphics.DrawString(_targets.Count.ToString() + " window(s) selected", smallFont, textBrush, 26.0f, 52.0f);
            }
        }
    }

    internal enum PrecisionShapeMode
    {
        Line,
        Rectangle,
        Triangle,
        Circle,
        Freehand
    }

    internal sealed class PrecisionStroke
    {
        public PrecisionShapeMode Mode;
        public Point Start;
        public Point End;
        public bool WholeMonitor;
        public readonly List<PointF> Points = new List<PointF>();
    }

    internal sealed class PrecisionCutPlan
    {
        public WindowTarget Target;
        public Rectangle Bounds;
        public readonly List<SlashLine> ScreenLines = new List<SlashLine>();
        public readonly List<PointF[]> ScreenShapes = new List<PointF[]>();
    }

    internal sealed class SliceRequest
    {
        public WindowTarget Target;
        public List<SlashLine> ScreenLines;
        public List<PointF[]> ScreenShapes;

        public SliceRequest(WindowTarget target, List<SlashLine> screenLines, List<PointF[]> screenShapes)
        {
            Target = target;
            ScreenLines = screenLines;
            ScreenShapes = screenShapes;
        }
    }

    internal sealed class PrecisionSelectionForm : Form
    {
        private const int MaximumRecordedStrokes = 63;
        private const int MaximumFreehandPoints = 2048;
        private readonly string _hotkeyText;
        private readonly Func<Point, Point, bool, List<PrecisionCutPlan>> _resolveStroke;
        private readonly Func<PointF[], bool, List<PrecisionCutPlan>> _resolveShape;
        private Action<bool, List<PrecisionCutPlan>> _completed;
        private readonly Rectangle _virtualScreen;
        private readonly Color _slashColor;
        private readonly Color _outlineColor;
        private readonly float _thickness;
        private readonly bool _unlimitedPerformance;
        private readonly bool _liveWindowMode;
        private readonly List<PrecisionStroke> _strokes = new List<PrecisionStroke>();
        private readonly List<PointF> _drawingPoints = new List<PointF>();
        private readonly Dictionary<IntPtr, PrecisionCutPlan> _plans = new Dictionary<IntPtr, PrecisionCutPlan>();
        private readonly Stopwatch _previewClock = new Stopwatch();
        private readonly HotkeyHost _enterKey;
        private readonly HotkeyHost _undoKey;
        private readonly HotkeyHost _cancelKey;
        private readonly HotkeyHost _shapeKey;
        private List<PrecisionCutPlan> _previewPlans = new List<PrecisionCutPlan>();
        private Point _start;
        private Point _current;
        private bool _drawing;
        private bool _drawingWholeMonitor;
        private bool _finished;
        private PrecisionShapeMode _shapeMode = PrecisionShapeMode.Line;

        public PrecisionSelectionForm(string hotkey, Func<Point, Point, bool, List<PrecisionCutPlan>> resolveStroke, Func<PointF[], bool, List<PrecisionCutPlan>> resolveShape, string slashColor, string outlineColor, int thickness, bool unlimitedPerformance, bool liveWindowMode, Action<bool, List<PrecisionCutPlan>> completed)
        {
            _hotkeyText = hotkey;
            _resolveStroke = resolveStroke;
            _resolveShape = resolveShape;
            _completed = completed;
            _virtualScreen = SystemInformation.VirtualScreen;
            _slashColor = ColorTranslator.FromHtml(slashColor);
            _outlineColor = ColorTranslator.FromHtml(outlineColor);
            _thickness = Math.Max(1, thickness);
            _unlimitedPerformance = unlimitedPerformance;
            _liveWindowMode = liveWindowMode;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            Bounds = _virtualScreen;
            TopMost = true;
            BackColor = Color.FromArgb(20, 24, 32);
            Opacity = 0.30;
            DoubleBuffered = true;
            Cursor = Cursors.Cross;

            _enterKey = new HotkeyHost(delegate { QueueUiAction(Submit); });
            _undoKey = new HotkeyHost(delegate { QueueUiAction(UndoStroke); });
            _cancelKey = new HotkeyHost(delegate { QueueUiAction(Cancel); });
            _shapeKey = new HotkeyHost(delegate { QueueUiAction(CycleShapeMode); });
            try
            {
                string error;
                if (!_enterKey.SetUnmodified(Keys.Enter, out error)) throw new InvalidOperationException(error);
                if (!_undoKey.SetUnmodified(Keys.Back, out error)) throw new InvalidOperationException(error);
                if (!_cancelKey.SetUnmodified(Keys.Escape, out error)) throw new InvalidOperationException(error);
                if (!_shapeKey.SetUnmodified(Keys.Tab, out error)) throw new InvalidOperationException(error);
            }
            catch
            {
                _enterKey.Dispose();
                _undoKey.Dispose();
                _cancelKey.Dispose();
                _shapeKey.Dispose();
                throw;
            }
            _previewClock.Start();
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        private void QueueUiAction(Action action)
        {
            if (action == null || IsDisposed || !IsHandleCreated) return;
            try { BeginInvoke(new MethodInvoker(delegate { if (!_finished && !IsDisposed) action(); })); }
            catch { }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00000080 | 0x08000000;
                return cp;
            }
        }

        public void Begin()
        {
            Show();
            Native.PutTopmostWithoutActivate(Handle, Bounds);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _enterKey.Dispose();
                _undoKey.Dispose();
                _cancelKey.Dispose();
                _shapeKey.Dispose();
            }
            base.Dispose(disposing);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button == MouseButtons.Right)
            {
                UndoStroke();
                return;
            }
            if (e.Button != MouseButtons.Left || _drawing) return;
            if (_liveWindowMode && _shapeMode != PrecisionShapeMode.Line && CountShapeStrokes(_strokes) > 0)
            {
                MessageBox.Show(this, "Live-window Precision Slice supports at most one shape cutout. Press Backspace to undo it before drawing another shape; line cuts can still be added.", "Precision Slice", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            _drawing = true;
            _start = PointToScreen(e.Location);
            _current = _start;
            _drawingWholeMonitor = IsWholeMonitorMode(false);
            _drawingPoints.Clear();
            if (_shapeMode == PrecisionShapeMode.Freehand) _drawingPoints.Add(new PointF(_start.X, _start.Y));
            _previewPlans.Clear();
            _previewClock.Restart();
            Capture = true;
            Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (!_drawing) return;
            _current = PointToScreen(e.Location);
            _drawingWholeMonitor = IsWholeMonitorMode(_drawingWholeMonitor);
            if (_shapeMode == PrecisionShapeMode.Freehand) AddFreehandPoint(_drawingPoints, _current, _unlimitedPerformance);
            if (_previewClock.ElapsedMilliseconds >= 55)
            {
                _previewPlans = ResolveCurrent(_start, _current, _drawingWholeMonitor, _drawingPoints);
                _previewClock.Restart();
            }
            Invalidate();
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (!_drawing || e.Button != MouseButtons.Left) return;
            _current = PointToScreen(e.Location);
            _drawingWholeMonitor = IsWholeMonitorMode(_drawingWholeMonitor);
            if (_shapeMode == PrecisionShapeMode.Freehand) AddFreehandPoint(_drawingPoints, _current, _unlimitedPerformance);
            _drawing = false;
            Capture = false;
            double dx = _current.X - _start.X;
            double dy = _current.Y - _start.Y;
            bool validStroke = _shapeMode == PrecisionShapeMode.Freehand
                ? IsValidFreehandShape(_drawingPoints)
                : ((dx * dx) + (dy * dy) >= 16.0);
            if (validStroke)
            {
                if (!_unlimitedPerformance && _strokes.Count >= MaximumRecordedStrokes)
                {
                    MessageBox.Show(this, "Precision Slice has reached its 63-stroke safety limit. Press Enter to execute or Backspace to remove a stroke.", "Precision Slice", MessageBoxButtons.OK, MessageBoxIcon.Information);
                }
                else
                {
                    PrecisionStroke stroke = new PrecisionStroke { Mode = _shapeMode, Start = _start, End = _current, WholeMonitor = _drawingWholeMonitor };
                    stroke.Points.AddRange(_drawingPoints);
                    _strokes.Add(stroke);
                    RebuildPlans();
                }
            }
            _drawingPoints.Clear();
            _previewPlans.Clear();
            Invalidate();
        }

        private List<PrecisionCutPlan> Resolve(PrecisionStroke stroke)
        {
            try
            {
                if (stroke.Mode == PrecisionShapeMode.Line)
                    return _resolveStroke == null ? new List<PrecisionCutPlan>() : _resolveStroke(stroke.Start, stroke.End, stroke.WholeMonitor);
                PointF[] polygon = stroke.Mode == PrecisionShapeMode.Freehand
                    ? stroke.Points.ToArray()
                    : BuildShape(stroke.Mode, stroke.Start, stroke.End);
                return _resolveShape == null ? new List<PrecisionCutPlan>() : _resolveShape(polygon, stroke.WholeMonitor);
            }
            catch { return new List<PrecisionCutPlan>(); }
        }

        private List<PrecisionCutPlan> ResolveCurrent(Point start, Point end, bool wholeMonitor, IList<PointF> points)
        {
            PrecisionStroke stroke = new PrecisionStroke { Mode = _shapeMode, Start = start, End = end, WholeMonitor = wholeMonitor };
            if (_shapeMode == PrecisionShapeMode.Freehand && points != null) stroke.Points.AddRange(points);
            return Resolve(stroke);
        }

        private static bool AddFreehandPoint(List<PointF> points, Point point, bool unlimited)
        {
            if (points == null) return false;
            if (!unlimited && points.Count >= MaximumFreehandPoints) return false;
            PointF next = new PointF(point.X, point.Y);
            if (points.Count > 0)
            {
                PointF previous = points[points.Count - 1];
                float dx = next.X - previous.X;
                float dy = next.Y - previous.Y;
                if ((dx * dx) + (dy * dy) < 6.25f) return false;
            }
            points.Add(next);
            return true;
        }

        internal static double PolygonArea(IList<PointF> points)
        {
            if (points == null || points.Count < 3) return 0.0;
            double area = 0.0;
            for (int i = 0; i < points.Count; i++)
            {
                PointF current = points[i];
                PointF next = points[(i + 1) % points.Count];
                area += (current.X * next.Y) - (next.X * current.Y);
            }
            return Math.Abs(area) * 0.5;
        }

        internal static bool IsValidFreehandShape(IList<PointF> points)
        {
            return points != null && points.Count >= 3 && PolygonArea(points) >= 4.0;
        }

        internal static bool IsWholeMonitorMode(bool alreadyLatched, bool altDown)
        {
            return alreadyLatched || altDown;
        }

        private static bool IsWholeMonitorMode(bool alreadyLatched)
        {
            bool altDown = (Native.GetAsyncKeyState(0x12) & 0x8000) != 0 ||
                (Native.GetAsyncKeyState(0xA4) & 0x8000) != 0 ||
                (Native.GetAsyncKeyState(0xA5) & 0x8000) != 0 ||
                (Control.ModifierKeys & Keys.Alt) != 0;
            return IsWholeMonitorMode(alreadyLatched, altDown);
        }

        private void CycleShapeMode()
        {
            if (_finished || _drawing) return;
            _shapeMode = NextShapeMode(_shapeMode);
            Invalidate();
        }

        private void RebuildPlans()
        {
            _plans.Clear();
            for (int i = 0; i < _strokes.Count; i++)
            {
                List<PrecisionCutPlan> found = Resolve(_strokes[i]);
                for (int j = 0; j < found.Count; j++)
                {
                    PrecisionCutPlan candidate = found[j];
                    if (candidate == null || candidate.Target == null || (candidate.ScreenLines.Count == 0 && candidate.ScreenShapes.Count == 0)) continue;
                    PrecisionCutPlan existing;
                    if (!_plans.TryGetValue(candidate.Target.Handle, out existing))
                    {
                        existing = new PrecisionCutPlan { Target = candidate.Target, Bounds = candidate.Bounds };
                        _plans.Add(candidate.Target.Handle, existing);
                    }
                    existing.Bounds = candidate.Bounds;
                    existing.Target = candidate.Target;
                    existing.ScreenLines.AddRange(candidate.ScreenLines);
                    existing.ScreenShapes.AddRange(candidate.ScreenShapes);
                }
            }
        }

        private void UndoStroke()
        {
            if (_finished || _drawing || _strokes.Count == 0) return;
            _strokes.RemoveAt(_strokes.Count - 1);
            RebuildPlans();
            Invalidate();
        }

        internal static int CountShapeStrokes(IList<PrecisionStroke> strokes)
        {
            int count = 0;
            if (strokes == null) return count;
            for (int i = 0; i < strokes.Count; i++)
                if (strokes[i] != null && strokes[i].Mode != PrecisionShapeMode.Line) count++;
            return count;
        }

        private void Submit()
        {
            if (_finished || _drawing) return;
            if (_liveWindowMode && CountShapeStrokes(_strokes) > 1)
            {
                MessageBox.Show(this, "Live-window Precision Slice supports at most one shape cutout. Press Backspace to remove extra shapes, or use line cuts only.", "Precision Slice", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (_plans.Count == 0)
            {
                PrecisionCutPlan screenPlan = CreateWholeScreenPlan(_strokes, SystemInformation.VirtualScreen);
                if (screenPlan == null)
                {
                    MessageBox.Show(this, "The drawn cut did not intersect an eligible window or the screen.", "Precision Slice", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                _plans[screenPlan.Target.Handle] = screenPlan;
            }
            List<PrecisionCutPlan> result = new List<PrecisionCutPlan>();
            foreach (PrecisionCutPlan plan in _plans.Values)
            {
                PrecisionCutPlan copy = new PrecisionCutPlan { Target = plan.Target, Bounds = plan.Bounds };
                copy.ScreenLines.AddRange(plan.ScreenLines);
                copy.ScreenShapes.AddRange(plan.ScreenShapes);
                result.Add(copy);
            }
            bool captureOverlayHidden = false;
            try
            {
                for (int i = 0; i < result.Count; i++)
                {
                    WindowTarget target = result[i].Target;
                    if (target == null || !target.IsScreenCapture) continue;
                    if (!captureOverlayHidden)
                    {
                        Hide();
                        captureOverlayHidden = true;
                        if (Native.DwmFlush() != 0)
                            throw new InvalidOperationException("Windows could not finish hiding the Precision Slice overlay before the screen capture.");
                    }
                    target.ScreenImage = new Bitmap(target.ScreenBounds.Width, target.ScreenBounds.Height, PixelFormat.Format32bppArgb);
                    Native.CaptureScreen(target.ScreenImage, target.ScreenBounds);
                }
            }
            catch (Exception ex)
            {
                for (int i = 0; i < result.Count; i++)
                {
                    if (result[i].Target != null && result[i].Target.ScreenImage != null)
                    {
                        result[i].Target.ScreenImage.Dispose();
                        result[i].Target.ScreenImage = null;
                    }
                }
                if (captureOverlayHidden && !_finished && !IsDisposed)
                {
                    Show();
                    Native.PutTopmostWithoutActivate(Handle, Bounds);
                }
                MessageBox.Show(this, "The monitor could not be captured. No target was changed.\r\n\r\n" + ex.Message, "Precision Slice", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }
            Complete(false, result);
        }

        public void Cancel() { Complete(true, new List<PrecisionCutPlan>()); }

        private void Complete(bool cancelled, List<PrecisionCutPlan> plans)
        {
            if (_finished) return;
            _finished = true;
            Capture = false;
            Action<bool, List<PrecisionCutPlan>> callback = _completed;
            _completed = null;
            Hide();
            Close();
            if (callback != null) callback(cancelled, plans);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            Rectangle crop = new Rectangle(_virtualScreen.X, _virtualScreen.Y, _virtualScreen.Width, _virtualScreen.Height);
            using (Pen targetPen = new Pen(Color.FromArgb(245, 80, 220, 255), 3.0f))
            using (SolidBrush targetFill = new SolidBrush(Color.FromArgb(18, 70, 210, 255)))
            using (SolidBrush textBrush = new SolidBrush(Color.White))
            using (Font textFont = new Font("Segoe UI", 14.0f, FontStyle.Bold))
            using (Font smallFont = new Font("Segoe UI", 10.0f, FontStyle.Regular))
            {
                foreach (PrecisionCutPlan plan in _plans.Values)
                {
                    Rectangle bounds = Rectangle.Intersect(plan.Bounds, _virtualScreen);
                    bounds.Offset(-_virtualScreen.X, -_virtualScreen.Y);
                    if (bounds.Width > 1 && bounds.Height > 1)
                    {
                        e.Graphics.FillRectangle(targetFill, bounds);
                        e.Graphics.DrawRectangle(targetPen, bounds.X, bounds.Y, bounds.Width - 1, bounds.Height - 1);
                    }
                }
                for (int i = 0; i < _previewPlans.Count; i++)
                {
                    Rectangle bounds = Rectangle.Intersect(_previewPlans[i].Bounds, _virtualScreen);
                    bounds.Offset(-_virtualScreen.X, -_virtualScreen.Y);
                    if (bounds.Width > 1 && bounds.Height > 1) e.Graphics.DrawRectangle(targetPen, bounds.X, bounds.Y, bounds.Width - 1, bounds.Height - 1);
                }
                for (int i = 0; i < _strokes.Count; i++) DrawStroke(e.Graphics, crop, _strokes[i]);
                if (_drawing)
                {
                    PrecisionStroke currentStroke = new PrecisionStroke { Mode = _shapeMode, Start = _start, End = _current };
                    currentStroke.Points.AddRange(_drawingPoints);
                    DrawStroke(e.Graphics, crop, currentStroke);
                }

                e.Graphics.DrawString("Precision Slice (" + _hotkeyText + ")", textFont, textBrush, 24.0f, 20.0f);
                string shapeInstruction = _liveWindowMode
                    ? "Live window: max ONE shape cutout; line cuts are allowed  |  Tab: next shape"
                    : "Alt+drag: full-screen snapshot  |  Tab: next cut shape";
                e.Graphics.DrawString("Shape: " + _shapeMode.ToString() + "  |  " + shapeInstruction, smallFont, textBrush, 26.0f, 50.0f);
                e.Graphics.DrawString("Freehand: trace an outline  |  Shape cuts keep both pieces  |  Enter: execute  |  Backspace: undo  |  Esc: cancel", smallFont, textBrush, 26.0f, 68.0f);
                int lineCount = _strokes.Count + (_drawing ? 1 : 0);
                int windowCount = _plans.Count;
                if (_drawing)
                {
                    for (int i = 0; i < _previewPlans.Count; i++)
                        if (!_plans.ContainsKey(_previewPlans[i].Target.Handle)) windowCount++;
                }
                e.Graphics.DrawString(lineCount.ToString() + " cut(s)  |  " + windowCount.ToString() + " target(s) affected", smallFont, textBrush, 26.0f, 90.0f);
            }
        }

        private void DrawStroke(Graphics graphics, Rectangle crop, PrecisionStroke stroke)
        {
            if (stroke.Mode == PrecisionShapeMode.Line)
            {
                SlashForm.DrawSlashStroke(graphics, crop, new PointF(stroke.Start.X, stroke.Start.Y), new PointF(stroke.End.X, stroke.End.Y), 255, _slashColor, _outlineColor, _thickness);
                return;
            }
            PointF[] points = stroke.Mode == PrecisionShapeMode.Freehand
                ? stroke.Points.ToArray()
                : BuildShape(stroke.Mode, stroke.Start, stroke.End);
            if (points.Length < 2) return;
            for (int i = 0; i < points.Length; i++)
                SlashForm.DrawSlashStroke(graphics, crop, points[i], points[(i + 1) % points.Length], 255, _slashColor, _outlineColor, _thickness);
        }

        internal static PointF[] BuildShape(PrecisionShapeMode mode, Point start, Point end)
        {
            float left = Math.Min(start.X, end.X);
            float top = Math.Min(start.Y, end.Y);
            float right = Math.Max(start.X, end.X);
            float bottom = Math.Max(start.Y, end.Y);
            if (mode == PrecisionShapeMode.Rectangle)
                return new PointF[] { new PointF(left, top), new PointF(right, top), new PointF(right, bottom), new PointF(left, bottom) };
            if (mode == PrecisionShapeMode.Triangle)
                return new PointF[] { new PointF((left + right) * 0.5f, top), new PointF(right, bottom), new PointF(left, bottom) };
            if (mode == PrecisionShapeMode.Circle)
            {
                PointF[] points = new PointF[48];
                double centerX = (left + right) * 0.5;
                double centerY = (top + bottom) * 0.5;
                double radius = Math.Min(right - left, bottom - top) * 0.5;
                for (int i = 0; i < points.Length; i++)
                {
                    double angle = 2.0 * Math.PI * i / points.Length;
                    points[i] = new PointF((float)(centerX + Math.Cos(angle) * radius), (float)(centerY + Math.Sin(angle) * radius));
                }

                return points;
            }
            if (mode == PrecisionShapeMode.Freehand) return new PointF[] { new PointF(start.X, start.Y), new PointF(end.X, end.Y) };
            return new PointF[] { new PointF(start.X, start.Y), new PointF(end.X, end.Y) };
        }

        internal static PrecisionCutPlan CreateMonitorCutPlan(WindowTarget target, PointF[] shape)
        {
            if (target == null || !target.IsScreenCapture || shape == null) return null;
            List<PointF> clipped = SliceAnimation.ClipPolygonToRectangle(shape, target.ScreenBounds);
            if (clipped.Count < 3 || SliceAnimation.PolygonArea(clipped) < 4.0) return null;
            PrecisionCutPlan plan = new PrecisionCutPlan { Target = target, Bounds = target.ScreenBounds };
            plan.ScreenShapes.Add(clipped.ToArray());
            return plan;
        }

        internal static PrecisionCutPlan CreateMonitorLinePlan(WindowTarget target, Point start, Point end)
        {
            if (target == null || !target.IsScreenCapture) return null;
            SlashLine clipped;
            if (!TryClipLineToRectangle(new PointF(start.X, start.Y), new PointF(end.X, end.Y), target.ScreenBounds, out clipped)) return null;
            PrecisionCutPlan plan = new PrecisionCutPlan { Target = target, Bounds = target.ScreenBounds };
            plan.ScreenLines.Add(clipped);
            return plan;
        }

        internal static PrecisionCutPlan CreateWholeScreenPlan(IList<PrecisionStroke> strokes, Rectangle bounds)
        {
            if (strokes == null || strokes.Count == 0 || bounds.Width < 16 || bounds.Height < 16) return null;
            WindowSlice.WindowTarget target = WindowSlice.WindowTarget.ForScreenCapture(bounds, 0);
            PrecisionCutPlan plan = new PrecisionCutPlan { Target = target, Bounds = bounds };
            for (int i = 0; i < strokes.Count; i++)
            {
                PrecisionStroke stroke = strokes[i];
                if (stroke == null) continue;
                if (stroke.Mode == PrecisionShapeMode.Line)
                {
                    SlashLine clipped;
                    if (TryClipLineToRectangle(new PointF(stroke.Start.X, stroke.Start.Y), new PointF(stroke.End.X, stroke.End.Y), bounds, out clipped))
                        plan.ScreenLines.Add(clipped);
                }
                else
                {
                    PointF[] polygon = stroke.Mode == PrecisionShapeMode.Freehand
                        ? stroke.Points.ToArray()
                        : BuildShape(stroke.Mode, stroke.Start, stroke.End);
                    List<PointF> clipped = SliceAnimation.ClipPolygonToRectangle(polygon, bounds);
                    if (clipped.Count >= 3 && SliceAnimation.PolygonArea(clipped) >= 4.0)
                        plan.ScreenShapes.Add(clipped.ToArray());
                }
            }
            return plan.ScreenLines.Count == 0 && plan.ScreenShapes.Count == 0 ? null : plan;
        }

        internal static PrecisionShapeMode NextShapeMode(PrecisionShapeMode mode)
        {
            return (PrecisionShapeMode)(((int)mode + 1) % 5);
        }

        internal static bool TryClipLineToRectangle(PointF start, PointF end, Rectangle rectangle, out SlashLine clipped)
        {
            clipped = null;
            if (rectangle.Width <= 0 || rectangle.Height <= 0) return false;
            double x0 = start.X;
            double y0 = start.Y;
            double dx = end.X - start.X;
            double dy = end.Y - start.Y;
            double t0 = 0.0;
            double t1 = 1.0;
            double left = rectangle.Left;
            double right = rectangle.Right;
            double top = rectangle.Top;
            double bottom = rectangle.Bottom;
            if (!ClipTest(-dx, x0 - left, ref t0, ref t1) ||
                !ClipTest(dx, right - x0, ref t0, ref t1) ||
                !ClipTest(-dy, y0 - top, ref t0, ref t1) ||
                !ClipTest(dy, bottom - y0, ref t0, ref t1)) return false;
            PointF a = new PointF((float)(x0 + t0 * dx), (float)(y0 + t0 * dy));
            PointF b = new PointF((float)(x0 + t1 * dx), (float)(y0 + t1 * dy));
            double sx = b.X - a.X;
            double sy = b.Y - a.Y;
            if ((sx * sx) + (sy * sy) < 0.25) return false;
            clipped = new SlashLine(a, b);
            return true;
        }

        private static bool ClipTest(double p, double q, ref double t0, ref double t1)
        {
            if (Math.Abs(p) < 0.0000001) return q >= 0.0;
            double ratio = q / p;
            if (p < 0.0)
            {
                if (ratio > t1) return false;
                if (ratio > t0) t0 = ratio;
            }
            else
            {
                if (ratio < t0) return false;
                if (ratio < t1) t1 = ratio;
            }
            return true;
        }
    }


    internal sealed class FragmentMarqueeForm : Form
    {
        private readonly Rectangle _virtualScreen;
        private Point _start;
        private Point _current;

        public FragmentMarqueeForm()
        {
            _virtualScreen = SystemInformation.VirtualScreen;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            Bounds = _virtualScreen;
            TopMost = true;
            BackColor = Color.Magenta;
            TransparencyKey = Color.Magenta;
            DoubleBuffered = true;
            Cursor = Cursors.Cross;
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00000080 | 0x08000000;
                return cp;
            }
        }

        public void Begin(Point start, Point current)
        {
            _start = start;
            _current = current;
            Show();
            Native.PutTopmostWithoutActivate(Handle, Bounds);
            Capture = true;
            Invalidate();
        }

        public void UpdateSelection(Point current)
        {
            _current = current;
            Invalidate();
        }

        public Rectangle SelectionBounds
        {
            get { return WindowSelectionForm.NormalizeSelectionBounds(_start, _current); }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Rectangle selection = SelectionBounds;
            selection.Offset(-_virtualScreen.X, -_virtualScreen.Y);
            if (selection.Width < 1 || selection.Height < 1) return;
            using (SolidBrush fill = new SolidBrush(Color.FromArgb(42, 65, 155, 225)))
            using (Pen border = new Pen(Color.FromArgb(245, 65, 155, 225), 1.5f))
            using (Pen inner = new Pen(Color.FromArgb(220, 255, 255, 255), 1.0f))
            using (Font font = new Font("Segoe UI", 10.0f, FontStyle.Bold))
            using (SolidBrush text = new SolidBrush(Color.White))
            {
                border.DashStyle = System.Drawing.Drawing2D.DashStyle.Dash;
                e.Graphics.FillRectangle(fill, selection);
                e.Graphics.DrawRectangle(border, selection.X, selection.Y, selection.Width, selection.Height);
                e.Graphics.DrawRectangle(inner, selection.X + 2, selection.Y + 2, Math.Max(0, selection.Width - 4), Math.Max(0, selection.Height - 4));
                e.Graphics.DrawString("Release to delete selected fragments", font, text, selection.X + 8, selection.Y + 8);
            }
        }
    }

    internal static class LayeredWindowCapture
    {
        private const double CaptureSurfaceOpacity = 0.1;
        private const byte MinimumMatteChannel = 96;

        private sealed class ThumbnailHostForm : Form
        {
            public ThumbnailHostForm(Rectangle bounds, Color background)
            {
                FormBorderStyle = FormBorderStyle.None;
                ShowInTaskbar = false;
                StartPosition = FormStartPosition.Manual;
                Bounds = bounds;
                BackColor = background;
                TopMost = true;
                DoubleBuffered = true;
            }

            protected override bool ShowWithoutActivation { get { return true; } }

            protected override CreateParams CreateParams
            {
                get
                {
                    CreateParams cp = base.CreateParams;
                    cp.ExStyle |= 0x00000080 | 0x08000000;
                    return cp;
                }
            }
        }

        public static Bitmap Capture(IntPtr source, Rectangle bounds, Color slashColor)
        {
            if (source == IntPtr.Zero || bounds.Width < 1 || bounds.Height < 1) throw new InvalidOperationException("The layered window has invalid capture bounds.");
            Color secondMatteColor = CreateCaptureMatteColor(slashColor);
            IntPtr thumbnail = IntPtr.Zero;
            using (Bitmap originalScreen = CaptureScreen(bounds))
            using (ThumbnailHostForm host = new ThumbnailHostForm(bounds, Color.Black))
            {
                host.Opacity = CaptureSurfaceOpacity;
                host.Show();
                Native.PutTopmostWithoutActivate(host.Handle, bounds);
                Application.DoEvents();
                int result = Native.DwmRegisterThumbnail(host.Handle, source, out thumbnail);
                if (result != 0 || thumbnail == IntPtr.Zero) throw new InvalidOperationException("Windows could not create a Desktop Window Manager thumbnail for this transparent window. The original window was left untouched.");
                try
                {
                    Native.SIZE sourceSize;
                    if (Native.DwmQueryThumbnailSourceSize(thumbnail, out sourceSize) != 0 || sourceSize.cx < 1 || sourceSize.cy < 1)
                        throw new InvalidOperationException("Windows could not read the transparent window's thumbnail dimensions.");

                    Native.DWM_THUMBNAIL_PROPERTIES properties = new Native.DWM_THUMBNAIL_PROPERTIES();
                    properties.dwFlags = 0x00000001 | 0x00000004 | 0x00000008;
                    properties.rcDestination = new Native.RECT { Left = 0, Top = 0, Right = bounds.Width, Bottom = bounds.Height };
                    properties.opacity = 255;
                    properties.fVisible = true;
                    properties.fSourceClientAreaOnly = false;
                    if (Native.DwmUpdateThumbnailProperties(thumbnail, ref properties) != 0)
                        throw new InvalidOperationException("Windows could not display the transparent window in the capture surface.");

                    using (Bitmap black = CapturePass(host, bounds, Color.Black))
                    using (Bitmap secondMatte = CapturePass(host, bounds, secondMatteColor))
                    {
                        host.Hide();
                        Bitmap resultBitmap = RebuildAlpha(black, secondMatte, originalScreen, CaptureSurfaceOpacity, secondMatteColor);
                        if (!HasTransparency(resultBitmap))
                        {
                            return new Bitmap(resultBitmap);
                        }

                        return resultBitmap;
                    }
                }
                finally
                {
                    if (thumbnail != IntPtr.Zero) Native.DwmUnregisterThumbnail(thumbnail);
                }
            }
        }

        internal static Color CreateCaptureMatteColor(Color slashColor)
        {
            int maximum = Math.Max(slashColor.R, Math.Max(slashColor.G, slashColor.B));
            if (maximum == 0) return Color.FromArgb(MinimumMatteChannel, MinimumMatteChannel, MinimumMatteChannel);
            if (maximum >= MinimumMatteChannel) return Color.FromArgb(slashColor.R, slashColor.G, slashColor.B);
            double scale = (double)MinimumMatteChannel / maximum;
            return Color.FromArgb(
                (int)Math.Round(slashColor.R * scale),
                (int)Math.Round(slashColor.G * scale),
                (int)Math.Round(slashColor.B * scale));
        }

        private static Bitmap CaptureScreen(Rectangle bounds)
        {
            Bitmap image = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
            try
            {
                using (Graphics graphics = Graphics.FromImage(image))
                    graphics.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size, CopyPixelOperation.SourceCopy);
                return image;
            }
            catch
            {
                image.Dispose();
                throw;
            }
        }

        private static Bitmap CapturePass(ThumbnailHostForm host, Rectangle bounds, Color background)
        {
            host.BackColor = background;
            host.Invalidate(true);
            host.Update();
            Native.DwmFlush();
            Application.DoEvents();
            Native.DwmFlush();
            Bitmap image = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
            try
            {
                using (Graphics graphics = Graphics.FromImage(image))
                    graphics.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size, CopyPixelOperation.SourceCopy);
                return image;
            }
            catch
            {
                image.Dispose();
                throw;
            }
        }

        internal static Bitmap RebuildAlpha(Bitmap black, Bitmap secondMatte, Bitmap originalScreen, double opacity, Color matteColor)
        {
            if (black == null) throw new ArgumentNullException("black");
            if (secondMatte == null) throw new ArgumentNullException("secondMatte");
            if (originalScreen == null) throw new ArgumentNullException("originalScreen");
            if (black.Size != secondMatte.Size || black.Size != originalScreen.Size)
                throw new ArgumentException("All layered-window capture images must have matching dimensions.");
            if (opacity <= 0.0 || opacity > 1.0) throw new ArgumentOutOfRangeException("opacity");
            int matteChannelSum = matteColor.R + matteColor.G + matteColor.B;
            if (matteChannelSum == 0) throw new ArgumentOutOfRangeException("matteColor");
            int width = black.Width;
            int height = black.Height;
            Bitmap output = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            Rectangle rectangle = new Rectangle(0, 0, width, height);
            BitmapData blackData = null;
            BitmapData secondMatteData = null;
            BitmapData originalData = null;
            BitmapData outputData = null;
            try
            {
                blackData = black.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                secondMatteData = secondMatte.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                originalData = originalScreen.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                outputData = output.LockBits(rectangle, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                byte[] blackRow = new byte[width * 4];
                byte[] secondMatteRow = new byte[width * 4];
                byte[] originalRow = new byte[width * 4];
                byte[] outputRow = new byte[width * 4];
                double backgroundWeight = 1.0 - opacity;
                for (int y = 0; y < height; y++)
                {
                    Marshal.Copy(RowPointer(blackData, y, height), blackRow, 0, blackRow.Length);
                    Marshal.Copy(RowPointer(secondMatteData, y, height), secondMatteRow, 0, secondMatteRow.Length);
                    Marshal.Copy(RowPointer(originalData, y, height), originalRow, 0, originalRow.Length);
                    for (int x = 0; x < width; x++)
                    {
                        int i = x * 4;
                        double deltaB = secondMatteRow[i] - blackRow[i];
                        double deltaG = secondMatteRow[i + 1] - blackRow[i + 1];
                        double deltaR = secondMatteRow[i + 2] - blackRow[i + 2];
                        double sourceAlpha = 1.0 - ((deltaB + deltaG + deltaR) / (matteChannelSum * opacity));
                        sourceAlpha = Math.Max(0.0, Math.Min(1.0, sourceAlpha));
                        if (sourceAlpha < 0.02)
                        {
                            outputRow[i] = 0;
                            outputRow[i + 1] = 0;
                            outputRow[i + 2] = 0;
                            outputRow[i + 3] = 0;
                        }
                        else
                        {
                            double denominator = opacity * sourceAlpha;
                            outputRow[i] = ClampByte((blackRow[i] - backgroundWeight * originalRow[i]) / denominator);
                            outputRow[i + 1] = ClampByte((blackRow[i + 1] - backgroundWeight * originalRow[i + 1]) / denominator);
                            outputRow[i + 2] = ClampByte((blackRow[i + 2] - backgroundWeight * originalRow[i + 2]) / denominator);
                            outputRow[i + 3] = ClampByte(sourceAlpha * 255.0);
                        }
                    }
                    Marshal.Copy(outputRow, 0, RowPointer(outputData, y, height), outputRow.Length);
                }
                return output;
            }
            catch
            {
                output.Dispose();
                throw;
            }
            finally
            {
                if (blackData != null) black.UnlockBits(blackData);
                if (secondMatteData != null) secondMatte.UnlockBits(secondMatteData);
                if (originalData != null) originalScreen.UnlockBits(originalData);
                if (outputData != null) output.UnlockBits(outputData);
            }
        }

        private static IntPtr RowPointer(BitmapData data, int y, int height)
        {
            if (data.Stride >= 0) return IntPtr.Add(data.Scan0, y * data.Stride);
            return IntPtr.Add(data.Scan0, (height - 1 - y) * -data.Stride);
        }

        private static byte ClampByte(double value)
        {
            if (value < 0.0) return 0;
            if (value > 255.0) return 255;
            return (byte)Math.Round(value);
        }

        private static bool HasTransparency(Bitmap bitmap)
        {
            Rectangle rectangle = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
            BitmapData data = bitmap.LockBits(rectangle, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                byte[] row = new byte[bitmap.Width * 4];
                for (int y = 0; y < bitmap.Height; y++)
                {
                    Marshal.Copy(RowPointer(data, y, bitmap.Height), row, 0, row.Length);
                    for (int x = 0; x < bitmap.Width; x++)
                        if (row[x * 4 + 3] < 245) return true;
                }
                return false;
            }
            finally { bitmap.UnlockBits(data); }
        }
    }

    internal sealed class FragmentRotationKeyboardHook : IDisposable
    {
        private const int LowLevelKeyboardHook = 13;
        private const int KeyDownMessage = 0x0100;
        private const int SystemKeyDownMessage = 0x0104;
        private const int KeyUpMessage = 0x0101;
        private const int SystemKeyUpMessage = 0x0105;
        private readonly Native.HookProcedure _callback;
        private readonly bool[] _capturedKeys = new bool[4];
        private IntPtr _hook;

        [StructLayout(LayoutKind.Sequential)]
        private struct KeyboardHookData
        {
            public uint VirtualKey;
            public uint ScanCode;
            public uint Flags;
            public uint Time;
            public UIntPtr ExtraInfo;
        }

        public FragmentRotationKeyboardHook()
        {
            _callback = HandleKeyboard;
            _hook = Native.SetWindowsHookEx(LowLevelKeyboardHook, _callback, IntPtr.Zero, 0);
            if (_hook == IntPtr.Zero)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not enable fragment arrow-key rotation.");
        }

        private IntPtr HandleKeyboard(int code, IntPtr wParam, IntPtr lParam)
        {
            if (code >= 0)
            {
                int message = wParam.ToInt32();
                bool keyDown = message == KeyDownMessage || message == SystemKeyDownMessage;
                bool keyUp = message == KeyUpMessage || message == SystemKeyUpMessage;
                if (keyDown || keyUp)
                {
                    try
                    {
                        KeyboardHookData data = (KeyboardHookData)Marshal.PtrToStructure(lParam, typeof(KeyboardHookData));
                        int index = ArrowIndex(data.VirtualKey);
                        if (index >= 0)
                        {
                            if (keyUp && _capturedKeys[index])
                            {
                                _capturedKeys[index] = false;
                                return new IntPtr(1);
                            }
                            if (keyDown)
                            {
                                SliceForm fragment = PersistentFragmentStore.FragmentAt(System.Windows.Forms.Cursor.Position);
                                if (fragment != null && fragment.RotateByArrowKey((Keys)data.VirtualKey))
                                {
                                    _capturedKeys[index] = true;
                                    return new IntPtr(1);
                                }
                                _capturedKeys[index] = false;
                            }
                        }
                    }
                    catch { }
                }
            }
            return Native.CallNextHookEx(_hook, code, wParam, lParam);
        }

        private static int ArrowIndex(uint virtualKey)
        {
            if (virtualKey == (uint)Keys.Left) return 0;
            if (virtualKey == (uint)Keys.Right) return 1;
            if (virtualKey == (uint)Keys.Up) return 2;
            if (virtualKey == (uint)Keys.Down) return 3;
            return -1;
        }

        public void Dispose()
        {
            if (_hook == IntPtr.Zero) return;
            if (!Native.UnhookWindowsHookEx(_hook))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Windows could not disable fragment arrow-key rotation.");
            _hook = IntPtr.Zero;
        }
    }

    internal static class PersistentFragmentStore
    {
        private static readonly List<SliceForm> Fragments = new List<SliceForm>();
        private static readonly List<LiveWindowSliceSession> LiveSessions = new List<LiveWindowSliceSession>();
        public static bool RotationEnabled { get; private set; }
        private static readonly List<SliceForm> SuspendedFragments = new List<SliceForm>();
        private static readonly List<bool> SuspendedVisibility = new List<bool>();

        public static int Count { get { return Fragments.Count; } }

        public static void RegisterLiveSession(LiveWindowSliceSession session)
        {
            if (session != null && !LiveSessions.Contains(session)) LiveSessions.Add(session);
        }

        public static void UnregisterLiveSession(LiveWindowSliceSession session)
        {
            if (session != null) LiveSessions.Remove(session);
        }

        public static bool ContainsPoint(Point point)
        {
            for (int i = 0; i < Fragments.Count; i++)
            {
                SliceForm form = Fragments[i];
                if (form != null && !form.IsDisposed && form.Visible && form.ContentContainsPoint(point)) return true;
            }
            return false;
        }

        public static bool AnyIntersect(Rectangle area)
        {
            return CountIntersecting(area) > 0;
        }

        public static int CountIntersecting(Rectangle area)
        {
            int count = 0;
            for (int i = 0; i < Fragments.Count; i++)
            {
                SliceForm form = Fragments[i];
                if (form != null && !form.IsDisposed && form.Visible && area.IntersectsWith(form.Bounds)) count++;
            }
            return count;
        }

        public static int DeleteIntersecting(Rectangle area)
        {
            SliceForm[] snapshot = Fragments.ToArray();
            int deleted = 0;
            for (int i = 0; i < snapshot.Length; i++)
            {
                SliceForm form = snapshot[i];
                if (form == null || form.IsDisposed || !form.Visible || !area.IntersectsWith(form.Bounds)) continue;
                Remove(form);
                form.Close();
                deleted++;
            }
            return deleted;
        }

        public static bool Contains(SliceForm form)
        {
            return form != null && Fragments.Contains(form);
        }

        public static List<SliceForm> Snapshot()
        {
            return new List<SliceForm>(Fragments);
        }

        public static SliceForm FragmentAt(Point point)
        {
            for (int i = Fragments.Count - 1; i >= 0; i--)
            {
                SliceForm form = Fragments[i];
                if (form != null && !form.IsDisposed && form.Visible)
                    form.UpdateRotationHover(point);
                if (form != null && !form.IsDisposed && form.Visible && form.ContentContainsPoint(point)) return form;
            }
            return null;
        }

        public static void UpdateRotationHover(Point point)
        {
            for (int i = 0; i < Fragments.Count; i++)
            {
                SliceForm form = Fragments[i];
                if (form != null && !form.IsDisposed && form.Visible)
                    form.UpdateRotationHover(point);
            }
        }

        public static void Add(SliceForm form)
        {
            if (form != null && !Fragments.Contains(form)) Fragments.Add(form);
        }

        public static void SetRotationEnabled(bool enabled)
        {
            RotationEnabled = enabled;
            for (int i = 0; i < Fragments.Count; i++)
                if (Fragments[i] != null && !Fragments[i].IsDisposed)
                    Fragments[i].SetRotationEnabled(enabled);
        }

        public static void Remove(SliceForm form)
        {
            if (form != null)
            {
                Fragments.Remove(form);
                int index = SuspendedFragments.IndexOf(form);
                if (index >= 0)
                {
                    SuspendedFragments.RemoveAt(index);
                    SuspendedVisibility.RemoveAt(index);
                }
            }
        }

        public static void HideForCapture()
        {
            SuspendedFragments.Clear();
            SuspendedVisibility.Clear();
            for (int i = 0; i < Fragments.Count; i++)
            {
                SliceForm form = Fragments[i];
                if (form == null || form.IsDisposed) continue;
                bool wasVisible = form.Visible;
                SuspendedFragments.Add(form);
                SuspendedVisibility.Add(wasVisible);
                if (wasVisible) form.Hide();
            }
        }

        public static void RestoreAfterCapture()
        {
            for (int i = 0; i < SuspendedFragments.Count; i++)
            {
                SliceForm form = SuspendedFragments[i];
                if (form == null || form.IsDisposed || i >= SuspendedVisibility.Count || !SuspendedVisibility[i]) continue;
                form.Show();
                Native.PutTopmostWithoutActivate(form.Handle, form.Bounds);
            }
            SuspendedFragments.Clear();
            SuspendedVisibility.Clear();
        }

        public static void DisposeAll()
        {
            LiveWindowSliceSession[] sessions = LiveSessions.ToArray();
            for (int i = 0; i < sessions.Length; i++)
            {
                try { sessions[i].Restore(); }
                catch (Exception ex)
                {
                    MessageBox.Show("A live-sliced window could not be restored before exit.\r\n\r\n" + ex.Message, "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
            SliceForm[] snapshot = Fragments.ToArray();
            Fragments.Clear();
            SuspendedFragments.Clear();
            SuspendedVisibility.Clear();
            for (int i = 0; i < snapshot.Length; i++)
            {
                try
                {
                    if (snapshot[i] != null && !snapshot[i].IsDisposed) snapshot[i].Close();
                }
                catch
                {
                    try { if (snapshot[i] != null && !snapshot[i].IsDisposed) snapshot[i].Dispose(); } catch { }
                }
            }
        }
    }

    internal sealed class LayeredSurface : IDisposable
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct SurfaceHeader
        {
            public uint Size;
            public int Width;
            public int Height;
            public ushort Planes;
            public ushort BitCount;
            public uint Compression;
            public uint SizeImage;
            public int XPelsPerMeter;
            public int YPelsPerMeter;
            public uint ColorsUsed;
            public uint ColorsImportant;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SurfaceBlend
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct SurfacePoint { public int X; public int Y; }

        [StructLayout(LayoutKind.Sequential)]
        private struct SurfaceSize { public int Width; public int Height; }

        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateCompatibleDC(IntPtr hdc);
        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateDIBSection(IntPtr hdc, ref SurfaceHeader header, uint usage, out IntPtr bits, IntPtr section, uint offset);
        [DllImport("gdi32.dll")]
        private static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr obj);
        [DllImport("gdi32.dll")]
        private static extern bool DeleteDC(IntPtr hdc);
        [DllImport("user32.dll")]
        private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref SurfacePoint pptDst, ref SurfaceSize psize, IntPtr hdcSrc, ref SurfacePoint pptSrc, int crKey, ref SurfaceBlend pblend, int flags);

        private readonly int _width;
        private readonly int _height;
        private IntPtr _dc;
        private IntPtr _dib;
        private IntPtr _oldObject;
        private Bitmap _bitmap;
        private Graphics _graphics;

        public LayeredSurface(int width, int height)
        {
            _width = Math.Max(1, width);
            _height = Math.Max(1, height);
            SurfaceHeader header = new SurfaceHeader();
            header.Size = (uint)Marshal.SizeOf(typeof(SurfaceHeader));
            header.Width = _width;
            header.Height = -_height;
            header.Planes = 1;
            header.BitCount = 32;
            header.Compression = 0;
            IntPtr bits;
            _dc = CreateCompatibleDC(IntPtr.Zero);
            if (_dc == IntPtr.Zero) throw new InvalidOperationException("Windows could not create a drawing surface.");
            _dib = CreateDIBSection(IntPtr.Zero, ref header, 0, out bits, IntPtr.Zero, 0);
            if (_dib == IntPtr.Zero || bits == IntPtr.Zero)
            {
                DeleteDC(_dc);
                _dc = IntPtr.Zero;
                throw new InvalidOperationException("Windows could not allocate memory for a transparent window.");
            }
            _oldObject = SelectObject(_dc, _dib);
            _bitmap = new Bitmap(_width, _height, _width * 4, PixelFormat.Format32bppPArgb, bits);
            _graphics = Graphics.FromImage(_bitmap);
        }

        public Graphics Graphics { get { return _graphics; } }

        public void Update(IntPtr windowHandle, Point screenLocation, byte alpha)
        {
            SurfacePoint destination = new SurfacePoint();
            destination.X = screenLocation.X;
            destination.Y = screenLocation.Y;
            SurfacePoint source = new SurfacePoint();
            SurfaceSize size = new SurfaceSize();
            size.Width = _width;
            size.Height = _height;
            SurfaceBlend blend = new SurfaceBlend();
            blend.BlendOp = 0;
            blend.BlendFlags = 0;
            blend.SourceConstantAlpha = alpha;
            blend.AlphaFormat = 1;
            UpdateLayeredWindow(windowHandle, IntPtr.Zero, ref destination, ref size, _dc, ref source, 0, ref blend, 2);
        }

        public void Dispose()
        {
            if (_graphics != null) { _graphics.Dispose(); _graphics = null; }
            if (_bitmap != null) { _bitmap.Dispose(); _bitmap = null; }
            if (_dc != IntPtr.Zero)
            {
                if (_oldObject != IntPtr.Zero) SelectObject(_dc, _oldObject);
                DeleteDC(_dc);
                _dc = IntPtr.Zero;
            }
            if (_dib != IntPtr.Zero) { DeleteObject(_dib); _dib = IntPtr.Zero; }
        }
    }

    internal sealed class SliceForm : Form
    {
        private Bitmap _image;
        private LayeredSurface _surface;
        private double _opacity = 1.0;
        private byte[] _alphaMask;
        private bool _persistent;
        private bool _rotationEnabled;
        private bool _rotationHoverActive;
        private bool _dragging;
        private bool _liveClickPending;
        private MouseButtons _liveClickButton;
        private Point _dragStartCursor;
        private Rectangle _dragStartBounds;
        private ContextMenuStrip _fragmentMenu;
        private ToolStripMenuItem _liveModeItem;
        private Bitmap _backImage;
        private double _rotationX;
        private double _rotationY;
        private LiveWindowSliceSession _liveSliceSession;
        private Rectangle _liveOriginalBounds;
        private bool _forwardLiveInput;
        private bool _liveMoveMode;
        private IntPtr _liveButtonClickTarget;

        public SliceForm(Bitmap image, Rectangle initialBounds, PointF[] shape)
        {
            _image = image;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            TopMost = true;
            Bounds = initialBounds;
        }

        public double LayerOpacity
{
    get { return _opacity; }
    set
    {
        double clamped = Math.Max(0.0, Math.Min(1.0, value));
        if (Math.Abs(clamped - _opacity) < 0.0005) return;
        _opacity = clamped;
        PresentLayered(false);
    }
}
        public void MakePersistent()
        {
            MakePersistent(false);
        }

        public void MakePersistent(bool rotationEnabled)
        {
            if (_persistent || IsDisposed) return;
            _persistent = true;
            _rotationEnabled = rotationEnabled && PersistentFragmentStore.RotationEnabled;
            Cursor = Cursors.SizeAll;
            _fragmentMenu = new ContextMenuStrip();
            ToolStripMenuItem deleteItem = new ToolStripMenuItem("Delete");
            deleteItem.Click += delegate
            {
                PersistentFragmentStore.Remove(this);
                if (!IsDisposed) Close();
            };
            _fragmentMenu.Items.Add(deleteItem);
            ContextMenuStrip = _fragmentMenu;
            PersistentFragmentStore.Add(this);
        }

        public void SetRotationEnabled(bool enabled)
        {
            if (enabled && _liveSliceSession != null && _forwardLiveInput) enabled = false;
            if (_rotationEnabled == enabled) return;
            _rotationEnabled = enabled;
            if (!enabled)
            {
                _rotationX = 0.0;
                _rotationY = 0.0;
                _rotationHoverActive = false;
                if (_backImage != null) { _backImage.Dispose(); _backImage = null; }
                SetBoundsCentered(_image.Size);
            }
            PresentLayered(true);
        }

        public void AttachLiveSliceSession(LiveWindowSliceSession session, Rectangle originalBounds, bool forwardInput)
        {
            _liveSliceSession = session;
            _liveOriginalBounds = originalBounds;
            _forwardLiveInput = forwardInput;
            if (_fragmentMenu != null)
            {
                ToolStripMenuItem restoreItem = new ToolStripMenuItem("Restore original window");
                restoreItem.Click += delegate
                {
                    if (_liveSliceSession == null) return;
                    try { _liveSliceSession.Restore(); }
                    catch (Exception ex)
                    {
                        MessageBox.Show("The source window could not be restored.\r\n\r\n" + ex.Message, "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }
                };
                _fragmentMenu.Items.Add(new ToolStripSeparator());
                _fragmentMenu.Items.Add(restoreItem);
                _liveModeItem = new ToolStripMenuItem("Toggle Move Mode");
                _liveModeItem.Click += delegate { ToggleLiveMoveMode(); };
                _fragmentMenu.Items.Add(new ToolStripSeparator());
                _fragmentMenu.Items.Add(_liveModeItem);
            }
            if (_rotationEnabled && forwardInput) SetRotationEnabled(false);
        }

        internal void ToggleLiveMoveMode()
        {
            if (_liveSliceSession == null) return;
            _liveMoveMode = !_liveMoveMode;
            if (_liveModeItem != null)
                _liveModeItem.Text = _liveMoveMode ? "Toggle Live Mode" : "Toggle Move Mode";
        }

        public void ClearLiveSliceSession(LiveWindowSliceSession session)
        {
            if (!Object.ReferenceEquals(_liveSliceSession, session)) return;
            _liveSliceSession = null;
            _forwardLiveInput = false;
            _liveMoveMode = false;
            _liveButtonClickTarget = IntPtr.Zero;
        }

        internal void BeginLiveButtonClick(IntPtr button)
        {
            _liveButtonClickTarget = button;
        }

        internal IntPtr TakeLiveButtonClick()
        {
            IntPtr button = _liveButtonClickTarget;
            _liveButtonClickTarget = IntPtr.Zero;
            return button;
        }

        internal void RefreshFromLiveWindow(Bitmap currentWindow, Point windowOrigin)
        {
            if (_image == null || IsDisposed || currentWindow == null) return;
            Point sourceOffset = new Point(_liveOriginalBounds.X - windowOrigin.X, _liveOriginalBounds.Y - windowOrigin.Y);
            if (!CopyLivePixels(_image, currentWindow, sourceOffset)) return;
            if (_backImage != null) { _backImage.Dispose(); _backImage = null; }
            PresentLayered(true);
        }

        internal static bool CopyLivePixels(Bitmap destination, Bitmap source, Point sourceOffset)
        {
            if (destination == null) throw new ArgumentNullException("destination");
            if (source == null) throw new ArgumentNullException("source");
            Rectangle sourceBounds = new Rectangle(0, 0, source.Width, source.Height);
            Rectangle available = Rectangle.Intersect(
                new Rectangle(sourceOffset.X, sourceOffset.Y, destination.Width, destination.Height),
                sourceBounds);
            if (available.Width <= 0 || available.Height <= 0) return false;
            Rectangle destinationBounds = new Rectangle(
                available.X - sourceOffset.X,
                available.Y - sourceOffset.Y,
                available.Width,
                available.Height);
            BitmapData destinationData = null;
            BitmapData sourceData = null;
            try
            {
                destinationData = destination.LockBits(new Rectangle(0, 0, destination.Width, destination.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
                sourceData = source.LockBits(new Rectangle(0, 0, source.Width, source.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                int sampledPixels = 0;
                int transparentSourcePixels = 0;
                for (int y = 0; y < available.Height; y += 8)
                {
                    int sourceY = available.Y + y;
                    int destinationY = destinationBounds.Y + y;
                    IntPtr destinationPointer = IntPtr.Add(destinationData.Scan0, destinationY * destinationData.Stride + destinationBounds.X * 4);
                    IntPtr sourcePointer = IntPtr.Add(sourceData.Scan0, sourceY * sourceData.Stride + available.X * 4);
                    for (int x = 0; x < available.Width; x += 8)
                    {
                        int destinationAlpha = Marshal.ReadByte(destinationPointer, x * 4 + 3);
                        if (destinationAlpha == 0) continue;
                        sampledPixels++;
                        if (Marshal.ReadByte(sourcePointer, x * 4 + 3) == 0)
                            transparentSourcePixels++;
                    }
                }
                if (sampledPixels > 0 && transparentSourcePixels * 4 > sampledPixels * 3)
                    return false;
                byte[] destinationRow = new byte[available.Width * 4];
                byte[] sourceRow = new byte[available.Width * 4];
                for (int y = 0; y < available.Height; y++)
                {
                    int sourceY = available.Y + y;
                    int destinationY = destinationBounds.Y + y;
                    IntPtr destinationPointer = IntPtr.Add(destinationData.Scan0, destinationY * destinationData.Stride + destinationBounds.X * 4);
                    IntPtr sourcePointer = IntPtr.Add(sourceData.Scan0, sourceY * sourceData.Stride + available.X * 4);
                    Marshal.Copy(destinationPointer, destinationRow, 0, destinationRow.Length);
                    Marshal.Copy(sourcePointer, sourceRow, 0, sourceRow.Length);
                    for (int x = 0; x < available.Width; x++)
                    {
                        int destinationIndex = x * 4;
                        if (destinationRow[destinationIndex + 3] == 0) continue;
                        int sourceIndex = x * 4;
                        destinationRow[destinationIndex] = sourceRow[sourceIndex];
                        destinationRow[destinationIndex + 1] = sourceRow[sourceIndex + 1];
                        destinationRow[destinationIndex + 2] = sourceRow[sourceIndex + 2];
                    }
                    Marshal.Copy(destinationRow, 0, destinationPointer, destinationRow.Length);
                }
                return true;
            }
            finally
            {
                if (destinationData != null) destination.UnlockBits(destinationData);
                if (sourceData != null) source.UnlockBits(sourceData);
            }
        }

        public Point MapToOriginalScreen(Point screenPoint)
        {
            PointF imagePoint = ProjectedToImage(new PointF(screenPoint.X - Left, screenPoint.Y - Top));
            return new Point(
                _liveOriginalBounds.X + (int)Math.Round(imagePoint.X),
                _liveOriginalBounds.Y + (int)Math.Round(imagePoint.Y));
        }

        public bool RotateByArrowKey(Keys key)
        {
            if (!_persistent || !_rotationEnabled || _dragging || IsDisposed) return false;
            const double step = 12.0;
            if (key != Keys.Left && key != Keys.Right && key != Keys.Up && key != Keys.Down) return false;
            if (!_rotationHoverActive)
            {
                _rotationHoverActive = true;
                SetBoundsCentered(_image.Size);
            }
            if (key == Keys.Left) _rotationY -= step;
            else if (key == Keys.Right) _rotationY += step;
            else if (key == Keys.Up) _rotationX -= step;
            else if (key == Keys.Down) _rotationX += step;
            else return false;
            _rotationX = NormalizeAngle(_rotationX);
            _rotationY = NormalizeAngle(_rotationY);
            PresentLayered(true);
            return true;
        }

        public void UpdateRotationHover(Point cursor)
        {
            if (!_rotationHoverActive || _dragging || Bounds.Contains(cursor)) return;
            _rotationHoverActive = false;
            SetBoundsCentered(ProjectedSize(_image.Size, _rotationX, _rotationY));
            PresentLayered(true);
        }

        private void SetBoundsCentered(Size size)
        {
            int centerX = Left + Width / 2;
            int centerY = Top + Height / 2;
            Rectangle bounds = new Rectangle(centerX - size.Width / 2, centerY - size.Height / 2, size.Width, size.Height);
            if (Bounds != bounds) Bounds = bounds;
        }

        internal static double NormalizeAngle(double angle)
        {
            angle %= 360.0;
            if (angle < 0.0) angle += 360.0;
            return angle;
        }

        internal double RotationX { get { return _rotationX; } }
        internal double RotationY { get { return _rotationY; } }
        internal bool IsLiveDetachedPiece { get { return _liveSliceSession != null; } }
        internal bool IsLiveMoveMode { get { return _liveSliceSession != null && _liveMoveMode; } }

        internal static double RotationDeterminant(double rotationX, double rotationY)
        {
            double radiansX = rotationX * Math.PI / 180.0;
            double radiansY = rotationY * Math.PI / 180.0;
            return Math.Cos(radiansX) * Math.Cos(radiansY);
        }

        internal static Size ProjectedSize(Size imageSize, double rotationX, double rotationY)
        {
            double radiansX = rotationX * Math.PI / 180.0;
            double radiansY = rotationY * Math.PI / 180.0;
            double width = Math.Abs(Math.Cos(radiansY)) * imageSize.Width +
                Math.Abs(Math.Sin(radiansX) * Math.Sin(radiansY)) * imageSize.Height;
            double height = Math.Abs(Math.Cos(radiansX)) * imageSize.Height;
            return new Size(Math.Max(1, (int)Math.Ceiling(width)), Math.Max(1, (int)Math.Ceiling(height)));
        }

        public Bitmap CloneImage()
        {
            if (_image == null) throw new InvalidOperationException("This fragment no longer has an image.");
            Bitmap projected = new Bitmap(Width, Height, PixelFormat.Format32bppArgb);
            try
            {
                using (Graphics graphics = Graphics.FromImage(projected))
                {
                    graphics.Clear(Color.Transparent);
                    graphics.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                    DrawProjectedImage(graphics);
                }
                return projected;
            }
            catch
            {
                projected.Dispose();
                throw;
            }
        }

        private void EnsureAlphaMask()
        {
            if (_alphaMask != null || _image == null) return;
            int width = _image.Width;
            int height = _image.Height;
            byte[] mask = new byte[width * height];
            BitmapData data = _image.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                byte[] row = new byte[width * 4];
                for (int y = 0; y < height; y++)
                {
                    Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), row, 0, row.Length);
                    for (int x = 0; x < width; x++) mask[y * width + x] = row[x * 4 + 3];
                }
            }
            finally { _image.UnlockBits(data); }
            _alphaMask = mask;
        }

        private bool HasContentAt(int localX, int localY)
        {
            return _alphaMask != null && localX >= 0 && localY >= 0 && localX < _image.Width && localY < _image.Height && _alphaMask[localY * _image.Width + localX] > 12;
        }

        public bool ContentContainsPoint(Point screenPoint)
        {
            if (_image == null || IsDisposed || !Bounds.Contains(screenPoint)) return false;
            if (_rotationHoverActive) return true;
            EnsureAlphaMask();
            PointF local = ProjectedToImage(new PointF(screenPoint.X - Left, screenPoint.Y - Top));
            return HasContentAt((int)Math.Round(local.X), (int)Math.Round(local.Y));
        }

        private PointF ProjectedToImage(PointF projected)
        {
            double cosineX = Math.Cos(_rotationX * Math.PI / 180.0);
            double sineX = Math.Sin(_rotationX * Math.PI / 180.0);
            double cosineY = Math.Cos(_rotationY * Math.PI / 180.0);
            double sineY = Math.Sin(_rotationY * Math.PI / 180.0);
            double m11 = cosineY;
            double m21 = sineX * sineY;
            double m22 = cosineX;
            double determinant = (m11 * m22) - (m21 * 0.0);
            if (Math.Abs(determinant) < 0.0001)
                return new PointF(_image.Width * 0.5f, _image.Height * 0.5f);
            double centerX = _image.Width * 0.5;
            double centerY = _image.Height * 0.5;
            double x = projected.X - (Width * 0.5);
            double y = projected.Y - (Height * 0.5);
            return new PointF(
                (float)(centerX + ((m22 * x) / determinant) - ((m21 * y) / determinant)),
                (float)(centerY + (m11 * y / determinant)));
        }

        public bool ContentIntersects(Rectangle screenArea)
        {
            if (_image == null || IsDisposed) return false;
            Rectangle overlap = Rectangle.Intersect(screenArea, Bounds);
            if (overlap.Width < 1 || overlap.Height < 1) return false;
            EnsureAlphaMask();
            for (int y = overlap.Top; y < overlap.Bottom; y += 2)
                for (int x = overlap.Left; x < overlap.Right; x += 2)
                    if (HasContentAtProjected(x - Left, y - Top)) return true;
            return false;
        }

        public bool ContentTouchesLine(PointF start, PointF end)
        {
            if (_image == null || IsDisposed) return false;
            EnsureAlphaMask();
            double dx = end.X - start.X;
            double dy = end.Y - start.Y;
            int steps = (int)Math.Max(1.0, Math.Ceiling(Math.Sqrt(dx * dx + dy * dy) / 2.0));
            for (int i = 0; i <= steps; i++)
            {
                double t = (double)i / steps;
                int x = (int)Math.Round(start.X + dx * t) - Left;
                int y = (int)Math.Round(start.Y + dy * t) - Top;
                if (HasContentAtProjected(x, y)) return true;
            }
            return false;
        }

        private bool HasContentAtProjected(int x, int y)
        {
            PointF imagePoint = ProjectedToImage(new PointF(x, y));
            return HasContentAt((int)Math.Round(imagePoint.X), (int)Math.Round(imagePoint.Y));
        }

        private void PresentLayered(bool redraw)
        {
            if (_image == null || !IsHandleCreated || IsDisposed) return;
            if (_surface == null || redraw)
            {
                if (_surface != null) _surface.Dispose();
                _surface = new LayeredSurface(Width, Height);
                Graphics g = _surface.Graphics;
                g.Clear(Color.Transparent);
                g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                DrawProjectedImage(g);
            }
            _surface.Update(Handle, Location, (byte)Math.Round(_opacity * 255.0));
        }

        private void DrawProjectedImage(Graphics graphics)
        {
            bool backFacing = RotationDeterminant(_rotationX, _rotationY) < 0.0;
            Bitmap image = backFacing ? GetBackImage() : _image;
            if (_rotationX == 0.0 && _rotationY == 0.0)
            {
                graphics.DrawImage(image, new Rectangle(0, 0, _image.Width, _image.Height), 0, 0, _image.Width, _image.Height, GraphicsUnit.Pixel);
                return;
            }
            double radiansX = _rotationX * Math.PI / 180.0;
            double radiansY = _rotationY * Math.PI / 180.0;
            float m11 = (float)Math.Cos(radiansY);
            float m12 = 0.0f;
            float m21 = (float)(Math.Sin(radiansX) * Math.Sin(radiansY));
            float m22 = (float)Math.Cos(radiansX);
            float sourceCenterX = _image.Width * 0.5f;
            float sourceCenterY = _image.Height * 0.5f;
            float dx = Width * 0.5f - (m11 * sourceCenterX) - (m21 * sourceCenterY);
            float dy = Height * 0.5f - (m12 * sourceCenterX) - (m22 * sourceCenterY);
            using (System.Drawing.Drawing2D.Matrix transform = new System.Drawing.Drawing2D.Matrix(m11, m12, m21, m22, dx, dy))
            {
                graphics.Transform = transform;
                graphics.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                graphics.DrawImage(image, new Rectangle(0, 0, _image.Width, _image.Height), 0, 0, _image.Width, _image.Height, GraphicsUnit.Pixel);
                graphics.ResetTransform();
            }
        }

        private Bitmap GetBackImage()
        {
            if (_backImage != null) return _backImage;
            _backImage = new Bitmap(_image.Width, _image.Height, PixelFormat.Format32bppArgb);
            using (Graphics graphics = Graphics.FromImage(_backImage))
            using (ImageAttributes attributes = new ImageAttributes())
            {
                attributes.SetColorMatrix(CreateBackColorMatrix());
                graphics.DrawImage(_image, new Rectangle(0, 0, _image.Width, _image.Height), 0, 0, _image.Width, _image.Height, GraphicsUnit.Pixel, attributes);
            }
            return _backImage;
        }

        internal static ColorMatrix CreateBackColorMatrix()
        {
            const float saturation = 0.25f;
            const float desaturation = 1.0f - saturation;
            const float brightness = 0.65f;
            const float redLuminance = 0.30f;
            const float greenLuminance = 0.59f;
            const float blueLuminance = 0.11f;
            return new ColorMatrix(new float[][]
            {
                new float[] { brightness * (saturation + desaturation * redLuminance), brightness * desaturation * redLuminance, brightness * desaturation * redLuminance, 0, 0 },
                new float[] { brightness * desaturation * greenLuminance, brightness * (saturation + desaturation * greenLuminance), brightness * desaturation * greenLuminance, 0, 0 },
                new float[] { brightness * desaturation * blueLuminance, brightness * desaturation * blueLuminance, brightness * (saturation + desaturation * blueLuminance), 0, 0 },
                new float[] { 0, 0, 0, 1, 0 },
                new float[] { 0, 0, 0, 0, 1 }
            });
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00000080 | 0x08000000 | 0x00080000;
                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            PresentLayered(true);
        }

        protected override void OnPaintBackground(PaintEventArgs e) { }

        protected override void OnPaint(PaintEventArgs e) { }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (_liveSliceSession != null && _forwardLiveInput && !_liveMoveMode)
            {
                _liveSliceSession.ForwardMouse(this, e, MouseMessage(e.Button, true, e.Clicks), CurrentMouseButtonState());
                return;
            }
            if (_liveSliceSession != null && _persistent && !_liveMoveMode && e.Button == MouseButtons.Left)
            {
                _liveClickPending = true;
                _liveClickButton = e.Button;
                _dragStartCursor = System.Windows.Forms.Cursor.Position;
                _dragStartBounds = Bounds;
                Capture = true;
                return;
            }
            if (!_persistent || e.Button != MouseButtons.Left) return;
            _dragging = true;
            _dragStartCursor = System.Windows.Forms.Cursor.Position;
            _dragStartBounds = Bounds;
            Capture = true;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (_liveSliceSession != null && _forwardLiveInput && !_liveMoveMode)
            {
                _liveSliceSession.ForwardMouse(this, e, 0x0200, CurrentMouseButtonState());
                return;
            }
            if (_liveClickPending)
            {
                Point currentCursor = System.Windows.Forms.Cursor.Position;
                Size dragSize = SystemInformation.DragSize;
                if (Math.Abs(currentCursor.X - _dragStartCursor.X) < Math.Max(1, dragSize.Width / 2) &&
                    Math.Abs(currentCursor.Y - _dragStartCursor.Y) < Math.Max(1, dragSize.Height / 2))
                    return;
                _liveClickPending = false;
                _dragging = true;
            }
            if (!_persistent || !_dragging) return;
            Point cursor = System.Windows.Forms.Cursor.Position;
            Rectangle moved = _dragStartBounds;
            moved.Offset(cursor.X - _dragStartCursor.X, cursor.Y - _dragStartCursor.Y);
            if (moved != Bounds)
            {
                Bounds = moved;
                Native.PutTopmostWithoutActivate(Handle, moved);
            }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (_liveSliceSession != null && _forwardLiveInput && !_liveMoveMode)
            {
                _liveSliceSession.ForwardMouse(this, e, MouseMessage(e.Button, false, e.Clicks), CurrentMouseButtonState());
                return;
            }
            if (_liveClickPending && e.Button == _liveClickButton)
            {
                _liveClickPending = false;
                Capture = false;
                if (_liveSliceSession != null)
                {
                    _liveSliceSession.ForwardMouse(this, e, MouseMessage(e.Button, true, e.Clicks), CurrentMouseButtonState());
                    _liveSliceSession.ForwardMouse(this, e, MouseMessage(e.Button, false, e.Clicks), CurrentMouseButtonState());
                }
                return;
            }
            if (e.Button != MouseButtons.Left) return;
            _dragging = false;
            Capture = false;
            UpdateRotationHover(System.Windows.Forms.Cursor.Position);
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            base.OnMouseWheel(e);
            if (_liveSliceSession != null && _forwardLiveInput && !_liveMoveMode)
                _liveSliceSession.ForwardMouse(this, e, 0x020A, CurrentMouseButtonState());
        }

        private static int MouseMessage(MouseButtons button, bool down, int clicks)
        {
            if (button == MouseButtons.Left) return down ? (clicks > 1 ? 0x0203 : 0x0201) : 0x0202;
            if (button == MouseButtons.Right) return down ? (clicks > 1 ? 0x0206 : 0x0204) : 0x0205;
            if (button == MouseButtons.Middle) return down ? (clicks > 1 ? 0x0209 : 0x0207) : 0x0208;
            if (button == MouseButtons.XButton1 || button == MouseButtons.XButton2) return down ? 0x020B : 0x020C;
            return 0;
        }

        private static int CurrentMouseButtonState()
        {
            int state = 0;
            if (Native.IsKeyDown(Keys.LButton)) state |= 0x0001;
            if (Native.IsKeyDown(Keys.RButton)) state |= 0x0002;
            if (Native.IsKeyDown(Keys.MButton)) state |= 0x0010;
            if (Native.IsKeyDown(Keys.ShiftKey)) state |= 0x0004;
            if (Native.IsKeyDown(Keys.ControlKey)) state |= 0x0008;
            return state;
        }

        protected override void OnMouseCaptureChanged(EventArgs e)
        {
            base.OnMouseCaptureChanged(e);
            if (!Capture)
            {
                _dragging = false;
                _liveClickPending = false;
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_liveSliceSession != null)
                {
                    LiveWindowSliceSession session = _liveSliceSession;
                    _liveSliceSession = null;
                    session.Detach(this);
                }
                PersistentFragmentStore.Remove(this);
                if (_fragmentMenu != null) { _fragmentMenu.Dispose(); _fragmentMenu = null; }
                if (_surface != null) { _surface.Dispose(); _surface = null; }
                if (_image != null) { _image.Dispose(); _image = null; }
                if (_backImage != null) { _backImage.Dispose(); _backImage = null; }
            }
            base.Dispose(disposing);
        }
    }

    internal sealed class SlashLine
    {
        public readonly PointF Start;
        public readonly PointF End;

        public SlashLine(PointF start, PointF end)
        {
            Start = start;
            End = end;
        }
    }

    internal sealed class SlashForm : Form
    {
        private Bitmap _background;
        private double _progress;
        private readonly SlashLine[] _lines;
        private readonly Color _slashColor;
        private readonly Color _outlineColor;
        private readonly float _thickness;
        private double _overlayOpacity = 1.0;
        private LayeredSurface _surface;

        public SlashForm(Bitmap background, Rectangle bounds, SlashLine[] lines, Color slashColor, Color outlineColor, float thickness)
        {
            _background = background;
            _lines = lines;
            _slashColor = slashColor;
            _outlineColor = outlineColor;
            _thickness = thickness;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            TopMost = true;
            Bounds = bounds;
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00000080 | 0x08000000 | 0x00080000;
                return cp;
            }
        }

        public double Progress
        {
            set { _progress = Math.Max(0.0, Math.Min(1.0, value)); RenderLayered(); }
        }

        public double OverlayOpacity
        {
            set { _overlayOpacity = Math.Max(0.0, Math.Min(1.0, value)); RenderLayered(); }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            RenderLayered();
        }

        protected override void OnPaintBackground(PaintEventArgs e) { }

        protected override void OnPaint(PaintEventArgs e) { }

        private void RenderLayered()
        {
            if (_background == null || !IsHandleCreated || IsDisposed) return;
            if (_surface == null) _surface = new LayeredSurface(Width, Height);
            Graphics g = _surface.Graphics;
            g.Clear(Color.Transparent);
            g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
            g.DrawImage(_background, new Rectangle(0, 0, Width, Height), 0, 0, _background.Width, _background.Height, GraphicsUnit.Pixel);
            g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceOver;
            Rectangle crop = new Rectangle(0, 0, Width, Height);
            for (int i = 0; i < _lines.Length; i++)
            {
                PointF start = _lines[i].Start;
                PointF end = _lines[i].End;
                PointF tip = new PointF(start.X + (end.X - start.X) * (float)_progress, start.Y + (end.Y - start.Y) * (float)_progress);
                DrawSlashStroke(g, crop, start, tip, 255, _slashColor, _outlineColor, _thickness);
            }
            _surface.Update(Handle, Location, (byte)Math.Round(_overlayOpacity * 255.0));
        }


        internal static void DrawSlash(Graphics graphics, Size fullSize, Rectangle crop, bool vertical, double progress, int alpha, Color slashColor, Color outlineColor, float thickness)
        {
            if (progress <= 0.0 || alpha <= 0) return;
            progress = Math.Max(0.0, Math.Min(1.0, progress));
            PointF start;
            PointF tip;
            GetSlashPoints(fullSize, vertical, progress, out start, out tip);
            DrawSlashStroke(graphics, crop, start, tip, alpha, slashColor, outlineColor, thickness);
        }

        internal static void DrawSlashStroke(Graphics graphics, Rectangle crop, PointF start, PointF tip, int alpha, Color slashColor, Color outlineColor, float thickness)
        {
            if (alpha <= 0) return;
            graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            graphics.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
            start.X -= crop.X;
            start.Y -= crop.Y;
            tip.X -= crop.X;
            tip.Y -= crop.Y;
            float outlineWidth = Math.Max(1.0f, thickness);
            float coreWidth = Math.Max(1.0f, outlineWidth * 0.58f);
            DrawRoundedStroke(graphics, Color.FromArgb(ScaledAlpha(alpha, 0.09), outlineColor), outlineWidth * 2.2f, start, tip);
            DrawRoundedStroke(graphics, Color.FromArgb(ScaledAlpha(alpha, 0.18), outlineColor), outlineWidth * 1.65f, start, tip);
            DrawRoundedStroke(graphics, Color.FromArgb(ScaledAlpha(alpha, 0.35), outlineColor), outlineWidth * 1.25f, start, tip);
            DrawRoundedStroke(graphics, Color.FromArgb(alpha, outlineColor), outlineWidth, start, tip);
            DrawRoundedStroke(graphics, Color.FromArgb(alpha, slashColor), coreWidth, start, tip);
        }

        private static int ScaledAlpha(int alpha, double scale)
        {
            return Math.Max(0, Math.Min(255, (int)Math.Round(alpha * scale)));
        }

        private static void DrawRoundedStroke(Graphics graphics, Color color, float width, PointF start, PointF tip)
        {
            if (color.A == 0 || width <= 0.0f) return;
            using (Pen pen = new Pen(color, width))
            {
                pen.StartCap = System.Drawing.Drawing2D.LineCap.Round;
                pen.EndCap = System.Drawing.Drawing2D.LineCap.Round;
                graphics.DrawLine(pen, start, tip);
            }
        }

        internal static void GetSlashPoints(Size fullSize, bool vertical, double progress, out PointF start, out PointF tip)
        {
            progress = Math.Max(0.0, Math.Min(1.0, progress));
            if (vertical)
            {
                float x = fullSize.Width * 0.5f;
                float firstY = 0.0f;
                float lastY = fullSize.Height;
                start = new PointF(x, firstY);
                tip = new PointF(x, firstY + (lastY - firstY) * (float)progress);
            }
            else
            {
                float firstX = 0.0f;
                float lastX = fullSize.Width;
                float y = fullSize.Height * 0.5f;
                start = new PointF(firstX, y);
                tip = new PointF(firstX + (lastX - firstX) * (float)progress, y);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                if (_surface != null) { _surface.Dispose(); _surface = null; }
                if (_background != null) { _background.Dispose(); _background = null; }
            }
            base.Dispose(disposing);
        }
    }

    internal sealed class AudioClip
    {
        public readonly byte[] Data;
        public readonly ushort Channels;
        public readonly uint SampleRate;
        public readonly ushort BitsPerSample;
        public readonly ushort BlockAlign;

        public int DurationMilliseconds
        {
            get { return (int)Math.Ceiling(Data.Length * 1000.0 / ((double)SampleRate * BlockAlign)); }
        }

        private AudioClip(byte[] data, ushort channels, uint sampleRate, ushort bitsPerSample, ushort blockAlign)
        {
            Data = data;
            Channels = channels;
            SampleRate = sampleRate;
            BitsPerSample = bitsPerSample;
            BlockAlign = blockAlign;
        }

        public static AudioClip Load(string path)
        {
            byte[] file = File.ReadAllBytes(path);
            if (file.Length < 44 || ReadFourCc(file, 0) != "RIFF" || ReadFourCc(file, 8) != "WAVE")
                throw new InvalidDataException("This is not a valid RIFF/WAVE file.");

            bool foundFormat = false;
            bool foundData = false;
            ushort formatTag = 0;
            ushort channels = 0;
            uint sampleRate = 0;
            ushort bitsPerSample = 0;
            ushort blockAlign = 0;
            byte[] audioData = null;
            long offset = 12;
            while (offset + 8 <= file.Length)
            {
                string chunkName = ReadFourCc(file, (int)offset);
                uint chunkLength = BitConverter.ToUInt32(file, (int)offset + 4);
                long contentOffset = offset + 8;
                long nextOffset = contentOffset + chunkLength + (chunkLength & 1U);
                if (contentOffset + chunkLength > file.Length) throw new InvalidDataException("A WAV chunk extends beyond the end of the file.");
                if (chunkName == "fmt ")
                {
                    if (chunkLength < 16) throw new InvalidDataException("The WAV format chunk is incomplete.");
                    formatTag = BitConverter.ToUInt16(file, (int)contentOffset);
                    channels = BitConverter.ToUInt16(file, (int)contentOffset + 2);
                    sampleRate = BitConverter.ToUInt32(file, (int)contentOffset + 4);
                    blockAlign = BitConverter.ToUInt16(file, (int)contentOffset + 12);
                    bitsPerSample = BitConverter.ToUInt16(file, (int)contentOffset + 14);
                    foundFormat = true;
                }
                else if (chunkName == "data" && !foundData)
                {
                    audioData = new byte[chunkLength];
                    Buffer.BlockCopy(file, (int)contentOffset, audioData, 0, (int)chunkLength);
                    foundData = true;
                }
                if (nextOffset <= offset) throw new InvalidDataException("The WAV file contains an invalid chunk size.");
                offset = nextOffset;
            }

            int bytesPerSample = bitsPerSample / 8;
            if (!foundFormat || !foundData || formatTag != 1 || (channels != 1 && channels != 2) ||
                (bitsPerSample != 8 && bitsPerSample != 16 && bitsPerSample != 24 && bitsPerSample != 32) ||
                sampleRate < 8000 || sampleRate > 192000 || blockAlign != channels * bytesPerSample ||
                audioData == null || audioData.Length == 0 || audioData.Length % blockAlign != 0)
                throw new InvalidDataException("Window Slice supports PCM WAV audio with one or two channels and 8, 16, 24, or 32 bits per sample.");

            return new AudioClip(audioData, channels, sampleRate, bitsPerSample, blockAlign);
        }

        public byte[] ToWave(int sampleRate)
        {
            byte[] wave = new byte[44 + Data.Length];
            WriteFourCc(wave, 0, "RIFF");
            WriteUInt32(wave, 4, (uint)(wave.Length - 8));
            WriteFourCc(wave, 8, "WAVE");
            WriteFourCc(wave, 12, "fmt ");
            WriteUInt32(wave, 16, 16);
            WriteUInt16(wave, 20, 1);
            WriteUInt16(wave, 22, Channels);
            WriteUInt32(wave, 24, (uint)sampleRate);
            WriteUInt32(wave, 28, (uint)sampleRate * BlockAlign);
            WriteUInt16(wave, 32, BlockAlign);
            WriteUInt16(wave, 34, BitsPerSample);
            WriteFourCc(wave, 36, "data");
            WriteUInt32(wave, 40, (uint)Data.Length);
            Buffer.BlockCopy(Data, 0, wave, 44, Data.Length);
            return wave;
        }

        private static void WriteFourCc(byte[] bytes, int offset, string value)
        {
            byte[] ascii = Encoding.ASCII.GetBytes(value);
            Buffer.BlockCopy(ascii, 0, bytes, offset, 4);
        }

        private static void WriteUInt16(byte[] bytes, int offset, ushort value)
        {
            Buffer.BlockCopy(BitConverter.GetBytes(value), 0, bytes, offset, 2);
        }

        private static void WriteUInt32(byte[] bytes, int offset, uint value)
        {
            Buffer.BlockCopy(BitConverter.GetBytes(value), 0, bytes, offset, 4);
        }

        private static string ReadFourCc(byte[] bytes, int offset)
        {
            return Encoding.ASCII.GetString(bytes, offset, 4);
        }
    }

    internal static class WindowSliceMixer
    {
        private const uint WaveMapper = 0xFFFFFFFF;
        private const uint WaveHeaderDone = 0x00000001;
        private const int OutputRate = 44100;
        private const int BufferFrames = 662;      
        private const int BufferCount = 4;         
        private const int IdleShutdownMs = 3000;   

        [StructLayout(LayoutKind.Sequential)]
        private struct MixHeader
        {
            public IntPtr Data;
            public uint BufferLength;
            public uint BytesRecorded;
            public UIntPtr User;
            public uint Flags;
            public uint Loops;
            public IntPtr Next;
            public UIntPtr Reserved;
        }

        private sealed class Voice
        {
            public float[] Samples;   
            public int Frames;
            public double Position;   
            public double Step;       
        }

        [DllImport("winmm.dll", EntryPoint = "waveOutOpen")]
        private static extern uint WaveOutOpen(out IntPtr device, uint deviceId, ref WindowSliceAudio.WaveFormatEx format, IntPtr callback, IntPtr instance, uint flags);
        [DllImport("winmm.dll", EntryPoint = "waveOutPrepareHeader")]
        private static extern uint WaveOutPrepareHeader(IntPtr device, IntPtr header, uint headerSize);
        [DllImport("winmm.dll", EntryPoint = "waveOutWrite")]
        private static extern uint WaveOutWrite(IntPtr device, IntPtr header, uint headerSize);
        [DllImport("winmm.dll", EntryPoint = "waveOutUnprepareHeader")]
        private static extern uint WaveOutUnprepareHeader(IntPtr device, IntPtr header, uint headerSize);
        [DllImport("winmm.dll", EntryPoint = "waveOutReset")]
        private static extern uint WaveOutReset(IntPtr device);
        [DllImport("winmm.dll", EntryPoint = "waveOutClose")]
        private static extern uint WaveOutClose(IntPtr device);

        private static readonly object Sync = new object();
        private static readonly List<Voice> Voices = new List<Voice>();
        private static readonly Dictionary<AudioClip, float[]> Converted = new Dictionary<AudioClip, float[]>();
        private static bool _running;

        public static void Start(AudioClip clip, int playbackRate)
        {
            if (clip == null) throw new ArgumentNullException("clip");
            if (playbackRate < 8000 || playbackRate > 250000) throw new ArgumentOutOfRangeException("playbackRate");
            Voice voice = new Voice();
            lock (Sync)
            {
                float[] samples;
                if (!Converted.TryGetValue(clip, out samples))
                {
                    samples = ToStereoFloat(clip);
                    Converted[clip] = samples;
                }
                voice.Samples = samples;
                voice.Frames = samples.Length / 2;
                voice.Position = 0.0;
                voice.Step = (double)playbackRate / OutputRate;
                if (voice.Frames == 0) return;
                Voices.Add(voice);
                if (!_running)
                {
                    _running = true;
                    Thread thread = new Thread(Run);
                    thread.IsBackground = true;
                    thread.Priority = ThreadPriority.AboveNormal;
                    thread.Name = "WindowSliceMixer";
                    thread.Start();
                }
            }
        }

        private static float[] ToStereoFloat(AudioClip clip)
        {
            int bytesPerSample = clip.BitsPerSample / 8;
            int frames = clip.Data.Length / clip.BlockAlign;
            float[] output = new float[frames * 2];
            for (int f = 0; f < frames; f++)
            {
                float left = 0f, right = 0f;
                for (int c = 0; c < clip.Channels; c++)
                {
                    int offset = f * clip.BlockAlign + c * bytesPerSample;
                    float value;
                    switch (clip.BitsPerSample)
                    {
                        case 8: value = (clip.Data[offset] - 128) / 128f; break;
                        case 16: value = BitConverter.ToInt16(clip.Data, offset) / 32768f; break;
                        case 24: value = (((clip.Data[offset] << 8) | (clip.Data[offset + 1] << 16) | (clip.Data[offset + 2] << 24)) >> 8) / 8388608f; break;
                        default: value = BitConverter.ToInt32(clip.Data, offset) / 2147483648f; break;
                    }
                    if (c == 0) left = value; else right = value;
                }
                if (clip.Channels == 1) right = left;
                output[f * 2] = left;
                output[f * 2 + 1] = right;
            }
            return output;
        }

        internal static bool MixInto(short[] buffer)
        {
            bool any = false;
            float[] sum = new float[buffer.Length];
            lock (Sync)
            {
                for (int v = Voices.Count - 1; v >= 0; v--)
                {
                    Voice voice = Voices[v];
                    any = true;
                    for (int f = 0; f < buffer.Length / 2; f++)
                    {
                        int i0 = (int)voice.Position;
                        if (i0 >= voice.Frames - 1) { Voices.RemoveAt(v); break; }
                        float frac = (float)(voice.Position - i0);
                        int a = i0 * 2, b = a + 2;
                        sum[f * 2] += voice.Samples[a] + (voice.Samples[b] - voice.Samples[a]) * frac;
                        sum[f * 2 + 1] += voice.Samples[a + 1] + (voice.Samples[b + 1] - voice.Samples[a + 1]) * frac;
                        voice.Position += voice.Step;
                    }
                }
            }
            for (int i = 0; i < sum.Length; i++)
            {
                float s = sum[i];
                if (s > 1f) s = 1f; else if (s < -1f) s = -1f;
                buffer[i] = (short)(s * 32767f);
            }
            return any;
        }

        private static void Run()
        {
            IntPtr device = IntPtr.Zero;
            IntPtr[] headers = new IntPtr[BufferCount];
            GCHandle[] pins = new GCHandle[BufferCount];
            short[][] buffers = new short[BufferCount][];
            bool[] prepared = new bool[BufferCount];
            uint headerSize = (uint)Marshal.SizeOf(typeof(MixHeader));
            bool opened = false;
            try
            {
                WindowSliceAudio.WaveFormatEx format = new WindowSliceAudio.WaveFormatEx();
                format.FormatTag = 1;
                format.Channels = 2;
                format.SamplesPerSecond = OutputRate;
                format.BitsPerSample = 16;
                format.BlockAlign = 4;
                format.AverageBytesPerSecond = OutputRate * 4;
                format.ExtraSize = 0;
                uint result = WaveOutOpen(out device, WaveMapper, ref format, IntPtr.Zero, IntPtr.Zero, 0);
                if (result != 0) throw new InvalidOperationException("Windows could not open the audio device (waveOut error " + result.ToString(CultureInfo.InvariantCulture) + ").");
                opened = true;

                for (int i = 0; i < BufferCount; i++)
                {
                    buffers[i] = new short[BufferFrames * 2];
                    pins[i] = GCHandle.Alloc(buffers[i], GCHandleType.Pinned);
                    MixHeader header = new MixHeader();
                    header.Data = pins[i].AddrOfPinnedObject();
                    header.BufferLength = (uint)(buffers[i].Length * 2);
                    headers[i] = Marshal.AllocHGlobal((int)headerSize);
                    Marshal.StructureToPtr(header, headers[i], false);
                    result = WaveOutPrepareHeader(device, headers[i], headerSize);
                    if (result != 0) throw new InvalidOperationException("Windows could not prepare the audio buffer (waveOut error " + result.ToString(CultureInfo.InvariantCulture) + ").");
                    prepared[i] = true;
                    MixInto(buffers[i]);
                    result = WaveOutWrite(device, headers[i], headerSize);
                    if (result != 0) throw new InvalidOperationException("Windows could not start audio playback (waveOut error " + result.ToString(CultureInfo.InvariantCulture) + ").");
                }

                Stopwatch idle = Stopwatch.StartNew();
                int next = 0;
                while (true)
                {
                    MixHeader current = (MixHeader)Marshal.PtrToStructure(headers[next], typeof(MixHeader));
                    if ((current.Flags & WaveHeaderDone) == 0) { Thread.Sleep(2); continue; }
                    bool any = MixInto(buffers[next]);
                    if (any) idle.Restart();
                    else if (idle.ElapsedMilliseconds >= IdleShutdownMs)
                    {
                        lock (Sync)
                        {
                            if (Voices.Count == 0) { _running = false; break; }
                        }
                    }
                    result = WaveOutWrite(device, headers[next], headerSize);
                    if (result != 0) throw new InvalidOperationException("Windows could not continue audio playback (waveOut error " + result.ToString(CultureInfo.InvariantCulture) + ").");
                    next = (next + 1) % BufferCount;
                }
            }
            catch (Exception error)
            {
                lock (Sync) { Voices.Clear(); _running = false; }
                WindowSliceAudio.LogFailure(error, error);
            }
            finally
            {
                if (opened)
                {
                    try { WaveOutReset(device); } catch { }
                    for (int i = 0; i < BufferCount; i++)
                        if (prepared[i]) { try { WaveOutUnprepareHeader(device, headers[i], headerSize); } catch { } }
                    try { WaveOutClose(device); } catch { }
                }
                for (int i = 0; i < BufferCount; i++)
                {
                    if (headers[i] != IntPtr.Zero) Marshal.FreeHGlobal(headers[i]);
                    if (pins[i].IsAllocated) pins[i].Free();
                }
            }
        }
    }

    internal static class WindowSliceAudio
    {
        private const uint WaveMapper = 0xFFFFFFFF;
        private const uint WaveHeaderDone = 0x00000001;

        [StructLayout(LayoutKind.Sequential, Pack = 2)]
        internal struct WaveFormatEx
        {
            public ushort FormatTag;
            public ushort Channels;
            public uint SamplesPerSecond;
            public uint AverageBytesPerSecond;
            public ushort BlockAlign;
            public ushort BitsPerSample;
            public ushort ExtraSize;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct WaveHeader
        {
            public IntPtr Data;
            public uint BufferLength;
            public uint BytesRecorded;
            public UIntPtr User;
            public uint Flags;
            public uint Loops;
            public IntPtr Next;
            public UIntPtr Reserved;
        }

        [DllImport("winmm.dll", EntryPoint = "waveOutOpen")]
        private static extern uint WaveOutOpen(out IntPtr device, uint deviceId, ref WaveFormatEx format, IntPtr callback, IntPtr instance, uint flags);

        [DllImport("winmm.dll", EntryPoint = "waveOutPrepareHeader")]
        private static extern uint WaveOutPrepareHeader(IntPtr device, IntPtr header, uint headerSize);

        [DllImport("winmm.dll", EntryPoint = "waveOutWrite")]
        private static extern uint WaveOutWrite(IntPtr device, IntPtr header, uint headerSize);

        [DllImport("winmm.dll", EntryPoint = "waveOutUnprepareHeader")]
        private static extern uint WaveOutUnprepareHeader(IntPtr device, IntPtr header, uint headerSize);

        [DllImport("winmm.dll", EntryPoint = "waveOutReset")]
        private static extern uint WaveOutReset(IntPtr device);

        [DllImport("winmm.dll", EntryPoint = "waveOutClose")]
        private static extern uint WaveOutClose(IntPtr device);

        public static void Play(AudioClip clip, int sampleRate)
        {
            WindowSliceMixer.Start(clip, sampleRate);
        }

        internal static WaveFormatEx CreateWaveFormat(AudioClip clip, int sampleRate)
        {
            if (clip == null) throw new ArgumentNullException("clip");
            if (sampleRate < 8000 || sampleRate > 250000) throw new ArgumentOutOfRangeException("sampleRate");
            return new WaveFormatEx
            {
                FormatTag = 1,
                Channels = clip.Channels,
                SamplesPerSecond = (uint)sampleRate,
                AverageBytesPerSecond = (uint)sampleRate * clip.BlockAlign,
                BlockAlign = clip.BlockAlign,
                BitsPerSample = clip.BitsPerSample,
                ExtraSize = 0
            };
        }

        private static void ThrowOnWaveOutError(string action, uint result)
        {
            if (result != 0) throw new InvalidOperationException("Windows could not " + action + " (waveOut error " + result.ToString(CultureInfo.InvariantCulture) + ").");
        }

        public static void LogFailure(Exception pitchError, Exception playbackError)
        {
            try
            {
                string folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WindowSlice");
                Directory.CreateDirectory(folder);
                string details = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " Pitch playback: " + pitchError + Environment.NewLine + "Standard playback: " + playbackError + Environment.NewLine + Environment.NewLine;
                File.AppendAllText(Path.Combine(folder, "audio-error.log"), details, new UTF8Encoding(false));
            }
            catch { }
        }
    }

    internal sealed class SliceSoundPlayer
    {
        
        internal const double MinimumPitch = 0.80;
        internal const double MaximumPitch = 1.20;
        private readonly AudioClip[] _clips;
        private readonly AudioClip _prepareClip;
        private readonly AudioClip _disperseClip;
        private static readonly object RandomLock = new object();
        private static readonly Random Randomizer = new Random();

        public SliceSoundPlayer(string folder)
        {
            System.Collections.Generic.List<AudioClip> clips = new System.Collections.Generic.List<AudioClip>();
            string[] names = new string[] { "cut.wav", "cut2.wav" };
            for (int i = 0; i < names.Length; i++)
            {
                try
                {
                    string path = Path.Combine(folder, names[i]);
                    if (File.Exists(path)) clips.Add(AudioClip.Load(path));
                }
                catch { }
            }
            _clips = clips.ToArray();
            try
            {
                string preparePath = Path.Combine(folder, "prepare.wav");
                if (File.Exists(preparePath)) _prepareClip = AudioClip.Load(preparePath);
            }
            catch { _prepareClip = null; }
            try
            {
                string dispersePath = Path.Combine(folder, "slide.wav");
                if (File.Exists(dispersePath)) _disperseClip = AudioClip.Load(dispersePath);
            }
            catch { _disperseClip = null; }
        }

        public bool HasPrepareClip { get { return _prepareClip != null; } }
        public bool HasDisperseClip { get { return _disperseClip != null; } }

        public void PlayPrepare()
        {
            if (_prepareClip == null) return;
            AudioClip clip = _prepareClip;
            try
            {
                ThreadPool.QueueUserWorkItem(delegate(object state)
                {
                    try { WindowSliceAudio.Play(clip, (int)clip.SampleRate); }
                    catch (Exception playbackError) { WindowSliceAudio.LogFailure(playbackError, playbackError); }
                });
            }
            catch { }
        }

        public void PlayDisperse()
        {
            if (_disperseClip == null) return;
            AudioClip clip = _disperseClip;
            int sampleRate;
            lock (RandomLock)
            {
                double pitch = MinimumPitch + Randomizer.NextDouble() * (MaximumPitch - MinimumPitch);
                sampleRate = CalculatePlaybackRate((int)clip.SampleRate, pitch);
            }
            try
            {
                ThreadPool.QueueUserWorkItem(delegate(object state)
                {
                    try { WindowSliceAudio.Play(clip, sampleRate); }
                    catch (Exception pitchError)
                    {
                        try { WindowSliceAudio.Play(clip, (int)clip.SampleRate); }
                        catch (Exception playbackError) { WindowSliceAudio.LogFailure(pitchError, playbackError); }
                    }
                });
            }
            catch { }
        }

        public void PlayRandom()
        {
            if (_clips.Length == 0) return;
            AudioClip clip;
            int sampleRate;
            lock (RandomLock)
            {
                clip = _clips[Randomizer.Next(_clips.Length)];
                double pitch = MinimumPitch + Randomizer.NextDouble() * (MaximumPitch - MinimumPitch);
                sampleRate = CalculatePlaybackRate((int)clip.SampleRate, pitch);
            }
            try
            {
                ThreadPool.QueueUserWorkItem(delegate(object state)
                {
                    try { WindowSliceAudio.Play(clip, sampleRate); }
                    catch (Exception pitchError)
                    {
                        try { WindowSliceAudio.Play(clip, (int)clip.SampleRate); }
                        catch (Exception playbackError) { WindowSliceAudio.LogFailure(pitchError, playbackError); }
                    }
                });
            }
            catch { }
        }

        internal static int CalculatePlaybackRate(int sampleRate, double pitchFactor)
        {
            pitchFactor = Math.Max(MinimumPitch, Math.Min(MaximumPitch, pitchFactor));
            return (int)Math.Round(sampleRate * pitchFactor);
        }
    }

    internal sealed class ActiveWindowSliceGroup
    {
        public readonly uint ProcessId;
        public int ActiveCount;
        private bool _closeRequestClaimed;

        public ActiveWindowSliceGroup(uint processId) { ProcessId = processId; }

        public bool TryClaimCloseRequest()
        {
            if (_closeRequestClaimed) return false;
            _closeRequestClaimed = true;
            return true;
        }

        public void ReleaseCloseRequestClaim() { _closeRequestClaimed = false; }
    }

    internal sealed class SliceAnimation : IDisposable
    {
        private const int MaximumPieces = 256;
        private const long MaximumFragmentPixels = 48000000L;
        private static readonly object MultiSlashRandomLock = new object();
        private static readonly Random MultiSlashRandom = new Random();
        private readonly WindowTarget _target;
        private readonly ActiveWindowSliceGroup _targetGroup;
        private readonly SliceSoundPlayer _sounds;
        private readonly int _duration;
        private readonly int _distance;
        private readonly Color _slashColor;
        private readonly Color _outlineColor;
        private readonly float _slashThickness;
        private readonly bool _keepFragments;
        private readonly bool _unlimitedPerformance;
        private readonly bool _clickToDisperse;
        private readonly bool _rotateFragmentsWithArrowKeys;
        private readonly bool _keepWindowOpen;
        private readonly bool _interactiveDetachedPieces;
        private readonly bool _refreshLiveFragments;
        private readonly Rectangle _animationBounds;
        private readonly Action _finished;
        private readonly Stopwatch _watch = new Stopwatch();
        private readonly System.Windows.Forms.Timer _timer = new System.Windows.Forms.Timer();
        private readonly List<SliceForm> _pieces = new List<SliceForm>();
        private readonly List<Rectangle> _pieceBounds = new List<Rectangle>();
        private readonly List<PointF> _pieceDirections = new List<PointF>();
        private readonly List<SlashLine> _pendingLines = new List<SlashLine>();
        private readonly List<PointF[]> _pendingShapes = new List<PointF[]>();
        private SlashForm _slash;
        private SliceForm _waitingPreview;
        private Bitmap _waitingBaseImage;
        private bool _targetHidden;
        private bool _waitingForClick;
        private bool _leftMouseDownLastTick;
        private bool _sourceFragmentRemoved;
        private bool _closeRequestPosted;
        private bool _piecesWereShown;
        private bool _sliceSoundQueued;
        private bool _done;
        private int _attachedWindowPieceIndex = -1;
        private PointF[] _attachedWindowPolygon;
        private PointF[] _attachedWindowCutoutShape;
        private LiveWindowSliceSession _liveWindowSession;
        private bool _overlaysSuspended;
        private bool _slashWasVisibleWhenSuspended;
        private bool[] _pieceVisibilityWhenSuspended;

        public SliceAnimation(WindowTarget target, Bitmap image, Rectangle bounds, Settings settings, SliceSoundPlayer sounds, ActiveWindowSliceGroup targetGroup, Action finished)
            : this(target, image, bounds, settings, sounds, targetGroup, null, null, finished)
        {
        }

        public SliceAnimation(WindowTarget target, Bitmap image, Rectangle bounds, Settings settings, SliceSoundPlayer sounds, ActiveWindowSliceGroup targetGroup, IList<SlashLine> customLines, Action finished)
            : this(target, image, bounds, settings, sounds, targetGroup, customLines, null, finished)
        {
        }

        public SliceAnimation(WindowTarget target, Bitmap image, Rectangle bounds, Settings settings, SliceSoundPlayer sounds, ActiveWindowSliceGroup targetGroup, IList<SlashLine> customLines, IList<PointF[]> extractionShapes, Action finished)
        {
            if (target == null) throw new ArgumentNullException("target");
            if (target.Fragment != null && target.Fragment.IsLiveDetachedPiece)
                throw new InvalidOperationException("Restore the live source window before slicing one of its detached pieces.");
            _target = target;
            _targetGroup = targetGroup;
            _sounds = sounds;
            _finished = finished;
            _animationBounds = bounds;
            _duration = settings.DurationMs;
            _distance = settings.DistancePx;
            _slashColor = ColorTranslator.FromHtml(settings.SlashColor);
            _outlineColor = ColorTranslator.FromHtml(settings.OutlineColor);
            _slashThickness = settings.SlashThickness;
            _unlimitedPerformance = settings.UnlimitedPerformance;
            _clickToDisperse = settings.ClickToDisperse;
            _rotateFragmentsWithArrowKeys = settings.RotateFragmentsWithArrowKeys;
            _keepWindowOpen = ShouldKeepSourceWindowOpen(settings.KeepWindowsOpenAfterSlicing, target);
            _interactiveDetachedPieces = settings.DetachedPiecesInteractive;
            _refreshLiveFragments = settings.RefreshLiveFragments &&
                Settings.CanRefreshLiveFragments(_keepWindowOpen, settings.KeepFragments);
            if (_keepWindowOpen && extractionShapes != null && extractionShapes.Count > 0)
            {
                if (extractionShapes.Count != 1)
                    throw new InvalidOperationException("Live-window Precision Slice supports one shape cutout at a time.");
                _attachedWindowCutoutShape = (PointF[])extractionShapes[0].Clone();
            }
            _leftMouseDownLastTick = (Native.GetAsyncKeyState(0x01) & 0x8000) != 0;
            _keepFragments = ShouldKeepFragmentsForSlice(
                _keepWindowOpen,
                settings.KeepFragments,
                target.Fragment != null,
                extractionShapes != null && extractionShapes.Count > 0,
                settings.ClickToDisperse);
            try
            {
                List<SlashLine> lines = customLines == null ? BuildSlashLines(bounds.Size, settings) : new List<SlashLine>(customLines);
                _pendingLines.AddRange(lines);
                if (extractionShapes != null)
                    for (int shapeIndex = 0; shapeIndex < extractionShapes.Count; shapeIndex++)
                        _pendingShapes.Add((PointF[])extractionShapes[shapeIndex].Clone());
                if (lines.Count == 0 && (extractionShapes == null || extractionShapes.Count == 0)) throw new InvalidOperationException("No cutting line or shape intersects this window.");
                List<List<PointF>> polygons = lines.Count == 0
                    ? new List<List<PointF>> { new List<PointF> { new PointF(0, 0), new PointF(bounds.Width, 0), new PointF(bounds.Width, bounds.Height), new PointF(0, bounds.Height) } }
                    : BuildPolygons(bounds.Size, lines, _unlimitedPerformance);
                int attachedPolygonIndex = -1;
                if (_keepWindowOpen)
                {
                    attachedPolygonIndex = LargestPolygonIndex(polygons);
                    if (attachedPolygonIndex < 0)
                        throw new InvalidOperationException("The live window's remaining area could not be determined.");
                    _attachedWindowPolygon = polygons[attachedPolygonIndex].ToArray();
                }
                bool extractingShapes = extractionShapes != null && extractionShapes.Count > 0;
                int fragmentsPerPolygon = extractingShapes ? extractionShapes.Count + 1 : 1;
                if (!_unlimitedPerformance && extractingShapes && (long)polygons.Count * fragmentsPerPolygon > MaximumPieces)
                    throw new InvalidOperationException("This combination of line cuts and shape cutouts creates too many fragments. Reduce the number of cuts.");
                List<SlashLine> visualLines = new List<SlashLine>(lines);
                if (extractionShapes != null)
                {
                    for (int shapeIndex = 0; shapeIndex < extractionShapes.Count; shapeIndex++)
                    {
                        PointF[] shape = extractionShapes[shapeIndex];
                        for (int pointIndex = 0; pointIndex < shape.Length; pointIndex++)
                            visualLines.Add(new SlashLine(shape[pointIndex], shape[(pointIndex + 1) % shape.Length]));
                    }
                }
                long fragmentPixels = 0;
                for (int i = 0; i < polygons.Count; i++)
                {
                    Rectangle crop = GetPolygonBounds(polygons[i], bounds.Size);
                    if (!_unlimitedPerformance)
                    {
                        fragmentPixels += (long)crop.Width * crop.Height * fragmentsPerPolygon;
                        if (fragmentPixels > MaximumFragmentPixels)
                            throw new InvalidOperationException("This split creates too many large pieces to animate safely. Try fewer slashes or a smaller window.");
                    }
                    PointF[] localShape = TranslatePolygon(polygons[i], crop.X, crop.Y);
                    if (extractingShapes)
                    {
                        for (int selectedShape = 0; selectedShape < extractionShapes.Count; selectedShape++)
                        {
                            bool hasContent;
                            Bitmap fragment = CreatePieceBitmap(image, crop, polygons[i], visualLines, extractionShapes, selectedShape, _slashColor, _outlineColor, _slashThickness, out hasContent);
                            if (!hasContent) { fragment.Dispose(); continue; }
                            AddPiece(fragment, bounds, crop, localShape, GetPieceDirection(extractionShapes[selectedShape], bounds.Size));
                        }
                        bool remainderHasContent;
                        Bitmap remainder = CreatePieceBitmap(image, crop, polygons[i], visualLines, extractionShapes, -1, _slashColor, _outlineColor, _slashThickness, out remainderHasContent);
                        if (!remainderHasContent) remainder.Dispose();
                        else
                        {
                            AddPiece(remainder, bounds, crop, localShape, GetOppositeDirection(GetPieceDirection(extractionShapes[0], bounds.Size)));
                            if (_keepWindowOpen && i == attachedPolygonIndex) _attachedWindowPieceIndex = _pieces.Count - 1;
                        }
                    }
                    else
                    {
                        bool hasContent;
                        Bitmap fragment = CreatePieceBitmap(image, crop, polygons[i], visualLines, _slashColor, _outlineColor, _slashThickness, out hasContent);
                        if (!hasContent) { fragment.Dispose(); continue; }
                        AddPiece(fragment, bounds, crop, localShape, GetPieceDirection(polygons[i], bounds.Size));
                        if (i == attachedPolygonIndex) _attachedWindowPieceIndex = _pieces.Count - 1;
                    }
                }
                if (_keepWindowOpen && _attachedWindowPieceIndex < 0)
                    throw new InvalidOperationException("The remaining live window area has no visible pixels.");
                if (_clickToDisperse)
                {
                    _waitingBaseImage = new Bitmap(image);
                    Bitmap previewImage = CreateWaitingPreview(image);
                    try
                    {
                        PointF[] fullWindow = new PointF[] { new PointF(0, 0), new PointF(bounds.Width, 0), new PointF(bounds.Width, bounds.Height), new PointF(0, bounds.Height) };
                        _waitingPreview = new SliceForm(previewImage, bounds, fullWindow);
                        previewImage = null;
                    }
                    finally { if (previewImage != null) previewImage.Dispose(); }
                }
                _slash = new SlashForm(image, bounds, visualLines.ToArray(), _slashColor, _outlineColor, _slashThickness);
            }
            catch
            {
                DisposePieces();
                if (_slash != null) { _slash.Dispose(); _slash = null; }
                if (_waitingPreview != null) { _waitingPreview.Dispose(); _waitingPreview = null; }
                if (_waitingBaseImage != null) { _waitingBaseImage.Dispose(); _waitingBaseImage = null; }
                _timer.Dispose();
                throw;
            }
            _timer.Interval = 15;
            _timer.Tick += OnTick;
        }

        internal static List<SlashLine> BuildSlashLines(Size size, Settings settings)
        {
            List<SlashLine> lines = new List<SlashLine>();
            if (String.Equals(settings.Direction, "Vertical", StringComparison.OrdinalIgnoreCase) || String.Equals(settings.Direction, "Horizontal", StringComparison.OrdinalIgnoreCase))
            {
                PointF start;
                PointF end;
                SlashForm.GetSlashPoints(size, String.Equals(settings.Direction, "Vertical", StringComparison.OrdinalIgnoreCase), 1.0, out start, out end);
                lines.Add(new SlashLine(start, end));
                return lines;
            }
            if (String.Equals(settings.Direction, "Diagonal", StringComparison.OrdinalIgnoreCase))
            {
                lines.Add(new SlashLine(new PointF(0.0f, 0.0f), new PointF(size.Width, size.Height)));
                return lines;
            }
            int count = Math.Max(2, settings.UnlimitedPerformance ? settings.MultiSlashCount : Math.Min(25, settings.MultiSlashCount));
            PointF center = new PointF(size.Width * 0.5f, size.Height * 0.5f);
            bool randomPattern = String.Equals(settings.MultiPattern, "Random", StringComparison.OrdinalIgnoreCase);
            for (int i = 0; i < count; i++)
            {
                double angle;
                PointF through;
                if (randomPattern)
                {
                    lock (MultiSlashRandomLock)
                    {
                        angle = MultiSlashRandom.NextDouble() * Math.PI;
                        through = new PointF((float)(size.Width * (0.16 + MultiSlashRandom.NextDouble() * 0.68)),
                            (float)(size.Height * (0.16 + MultiSlashRandom.NextDouble() * 0.68)));
                    }
                }
                else { angle = Math.PI * i / count; through = center; }
                SlashLine line = GetBoundaryChord(size, through, new PointF((float)Math.Cos(angle), (float)Math.Sin(angle)));
                if (line != null) lines.Add(line);
            }
            return lines;
        }

        private static SlashLine GetBoundaryChord(Size size, PointF through, PointF direction)
        {
            List<PointF> hits = new List<PointF>();
            if (Math.Abs(direction.X) > 0.000001f)
            {
                AddBoundaryHit(hits, through, direction, 0.0f, true, size);
                AddBoundaryHit(hits, through, direction, size.Width, true, size);
            }
            if (Math.Abs(direction.Y) > 0.000001f)
            {
                AddBoundaryHit(hits, through, direction, 0.0f, false, size);
                AddBoundaryHit(hits, through, direction, size.Height, false, size);
            }
            if (hits.Count < 2) return new SlashLine(new PointF(0.0f, 0.0f), new PointF(size.Width, size.Height));
            PointF first = hits[0], second = hits[1];
            double farthest = -1.0;
            for (int i = 0; i < hits.Count; i++)
                for (int j = i + 1; j < hits.Count; j++)
                {
                    double dx = hits[i].X - hits[j].X, dy = hits[i].Y - hits[j].Y;
                    double distance = dx * dx + dy * dy;
                    if (distance > farthest) { farthest = distance; first = hits[i]; second = hits[j]; }
                }
            return new SlashLine(first, second);
        }

        private static void AddBoundaryHit(List<PointF> hits, PointF through, PointF direction, float edge, bool verticalEdge, Size size)
        {
            double t = verticalEdge ? (edge - through.X) / direction.X : (edge - through.Y) / direction.Y;
            double x = through.X + t * direction.X, y = through.Y + t * direction.Y;
            if (x < -0.01 || x > size.Width + 0.01 || y < -0.01 || y > size.Height + 0.01) return;
            PointF point = new PointF((float)Math.Max(0.0, Math.Min(size.Width, x)), (float)Math.Max(0.0, Math.Min(size.Height, y)));
            for (int i = 0; i < hits.Count; i++)
            {
                double dx = hits[i].X - point.X, dy = hits[i].Y - point.Y;
                if (dx * dx + dy * dy < 0.01) return;
            }
            hits.Add(point);
        }

        internal static List<List<PointF>> BuildPolygons(Size size, IList<SlashLine> lines)
        {
            return BuildPolygons(size, lines, false);
        }

        internal static List<List<PointF>> BuildPolygons(Size size, IList<SlashLine> lines, bool unlimitedPerformance)
        {
            int maximumPieces = unlimitedPerformance ? Int32.MaxValue : MaximumPieces;
            List<List<PointF>> polygons = new List<List<PointF>>();
            polygons.Add(new List<PointF> { new PointF(0, 0), new PointF(size.Width, 0), new PointF(size.Width, size.Height), new PointF(0, size.Height) });
            for (int lineIndex = 0; lineIndex < lines.Count; lineIndex++)
            {
                List<List<PointF>> next = new List<List<PointF>>();
                for (int polygonIndex = 0; polygonIndex < polygons.Count; polygonIndex++)
                {
                    List<PointF> positive = ClipPolygon(polygons[polygonIndex], lines[lineIndex], true);
                    List<PointF> negative = ClipPolygon(polygons[polygonIndex], lines[lineIndex], false);
                    if (positive.Count >= 3 && negative.Count >= 3 && PolygonArea(positive) > 0.5 && PolygonArea(negative) > 0.5)
                    { next.Add(positive); next.Add(negative); }
                    else next.Add(polygons[polygonIndex]);
                    if (next.Count > maximumPieces) throw new InvalidOperationException("This split creates too many pieces to animate safely. Reduce the slash count.");
                }
                polygons = next;
            }
            return polygons;
        }

        internal static List<PointF> ClipPolygonToRectangle(IList<PointF> polygon, Rectangle rectangle)
        {
            List<PointF> clipped = new List<PointF>(polygon);
            for (int edge = 0; edge < 4 && clipped.Count > 0; edge++)
            {
                List<PointF> output = new List<PointF>();
                PointF previous = clipped[clipped.Count - 1];
                bool previousInside = IsInsideRectangleEdge(previous, rectangle, edge);
                for (int i = 0; i < clipped.Count; i++)
                {
                    PointF current = clipped[i];
                    bool currentInside = IsInsideRectangleEdge(current, rectangle, edge);
                    if (currentInside)
                    {
                        if (!previousInside) output.Add(IntersectRectangleEdge(previous, current, rectangle, edge));
                        output.Add(current);
                    }
                    else if (previousInside) output.Add(IntersectRectangleEdge(previous, current, rectangle, edge));
                    previous = current;
                    previousInside = currentInside;
                }
                clipped = output;
            }
            return clipped;
        }

        private static bool IsInsideRectangleEdge(PointF point, Rectangle rectangle, int edge)
        {
            if (edge == 0) return point.X >= rectangle.Left;
            if (edge == 1) return point.X <= rectangle.Right;
            if (edge == 2) return point.Y >= rectangle.Top;
            return point.Y <= rectangle.Bottom;
        }

        private static PointF IntersectRectangleEdge(PointF start, PointF end, Rectangle rectangle, int edge)
        {
            if (edge < 2)
            {
                float x = edge == 0 ? rectangle.Left : rectangle.Right;
                float t = Math.Abs(end.X - start.X) < 0.0001f ? 0.0f : (x - start.X) / (end.X - start.X);
                return new PointF(x, start.Y + (end.Y - start.Y) * t);
            }
            float y = edge == 2 ? rectangle.Top : rectangle.Bottom;
            float fraction = Math.Abs(end.Y - start.Y) < 0.0001f ? 0.0f : (y - start.Y) / (end.Y - start.Y);
            return new PointF(start.X + (end.X - start.X) * fraction, y);
        }

        private static List<PointF> ClipPolygon(IList<PointF> polygon, SlashLine line, bool positive)
        {
            List<PointF> result = new List<PointF>();
            if (polygon.Count < 3) return result;
            PointF previous = polygon[polygon.Count - 1];
            double previousDistance = SignedLineDistance(previous, line, positive);
            bool previousInside = previousDistance >= -0.0001;
            for (int i = 0; i < polygon.Count; i++)
            {
                PointF current = polygon[i];
                double currentDistance = SignedLineDistance(current, line, positive);
                bool currentInside = currentDistance >= -0.0001;
                if (currentInside)
                {
                    if (!previousInside) result.Add(LineIntersection(previous, current, previousDistance, currentDistance));
                    result.Add(current);
                }
                else if (previousInside) result.Add(LineIntersection(previous, current, previousDistance, currentDistance));
                previous = current; previousDistance = currentDistance; previousInside = currentInside;
            }
            return result;
        }

        private static double SignedLineDistance(PointF point, SlashLine line, bool positive)
        {
            double cross = (line.End.X - line.Start.X) * (point.Y - line.Start.Y) - (line.End.Y - line.Start.Y) * (point.X - line.Start.X);
            return positive ? cross : -cross;
        }

        private static PointF LineIntersection(PointF a, PointF b, double distanceA, double distanceB)
        {
            double denominator = distanceA - distanceB;
            double t = Math.Abs(denominator) < 0.0000001 ? 0.5 : distanceA / denominator;
            t = Math.Max(0.0, Math.Min(1.0, t));
            return new PointF((float)(a.X + (b.X - a.X) * t), (float)(a.Y + (b.Y - a.Y) * t));
        }

        internal static double PolygonArea(IList<PointF> polygon)
        {
            double area = 0.0;
            for (int i = 0; i < polygon.Count; i++)
            {
                PointF a = polygon[i], b = polygon[(i + 1) % polygon.Count];
                area += a.X * b.Y - b.X * a.Y;
            }
            return Math.Abs(area) * 0.5;
        }

        internal static int LargestPolygonIndex(IList<List<PointF>> polygons)
        {
            int largestIndex = -1;
            double largestArea = -1.0;
            for (int i = 0; i < polygons.Count; i++)
            {
                double area = PolygonArea(polygons[i]);
                if (area > largestArea)
                {
                    largestIndex = i;
                    largestArea = area;
                }
            }
            return largestIndex;
        }

        private static PointF PolygonCentroid(IList<PointF> polygon)
        {
            double crossSum = 0.0, xSum = 0.0, ySum = 0.0;
            for (int i = 0; i < polygon.Count; i++)
            {
                PointF a = polygon[i], b = polygon[(i + 1) % polygon.Count];
                double cross = a.X * b.Y - b.X * a.Y;
                crossSum += cross; xSum += (a.X + b.X) * cross; ySum += (a.Y + b.Y) * cross;
            }
            if (Math.Abs(crossSum) < 0.0001) return polygon[0];
            return new PointF((float)(xSum / (3.0 * crossSum)), (float)(ySum / (3.0 * crossSum)));
        }

        private static Rectangle GetPolygonBounds(IList<PointF> polygon, Size size)
        {
            float left = size.Width, top = size.Height, right = 0, bottom = 0;
            for (int i = 0; i < polygon.Count; i++)
            { left = Math.Min(left, polygon[i].X); top = Math.Min(top, polygon[i].Y); right = Math.Max(right, polygon[i].X); bottom = Math.Max(bottom, polygon[i].Y); }
            int x = Math.Max(0, (int)Math.Floor(left)), y = Math.Max(0, (int)Math.Floor(top));
            int r = Math.Min(size.Width, (int)Math.Ceiling(right)), b = Math.Min(size.Height, (int)Math.Ceiling(bottom));
            if (r <= x) r = Math.Min(size.Width, x + 1);
            if (b <= y) b = Math.Min(size.Height, y + 1);
            return new Rectangle(x, y, r - x, b - y);
        }

        private static PointF[] TranslatePolygon(IList<PointF> polygon, int x, int y)
        {
            PointF[] translated = new PointF[polygon.Count];
            for (int i = 0; i < polygon.Count; i++) translated[i] = new PointF(polygon[i].X - x, polygon[i].Y - y);
            return translated;
        }

        private static Bitmap CreatePieceBitmap(Bitmap source, Rectangle crop, IList<PointF> polygon, IList<SlashLine> lines, Color slashColor, Color outlineColor, float thickness, out bool hasContent)
        {
            return CreatePieceBitmap(source, crop, polygon, lines, null, -1, slashColor, outlineColor, thickness, out hasContent);
        }

        internal static Bitmap CreateWaitingPreview(Bitmap source)
        {
            if (source == null) throw new ArgumentNullException("source");
            return new Bitmap(source);
        }

        internal static Bitmap CreatePieceBitmap(Bitmap source, Rectangle crop, IList<PointF> polygon, IList<SlashLine> lines, IList<PointF[]> extractionShapes, int selectedShapeIndex, Color slashColor, Color outlineColor, float thickness, out bool hasContent)
        {
            Bitmap result = new Bitmap(crop.Width, crop.Height, PixelFormat.Format32bppArgb);
            try
            {
                using (Graphics graphics = Graphics.FromImage(result))
                using (System.Drawing.Drawing2D.GraphicsPath path = new System.Drawing.Drawing2D.GraphicsPath())
                {
                    path.AddPolygon(TranslatePolygon(polygon, crop.X, crop.Y));
                    graphics.Clear(Color.Transparent);
                    graphics.SetClip(path, System.Drawing.Drawing2D.CombineMode.Replace);
                    if (extractionShapes != null && extractionShapes.Count > 0)
                    {
                        using (Region selection = new Region())
                        {
                            selection.MakeEmpty();
                            for (int i = 0; i < extractionShapes.Count; i++)
                            {
                                if (selectedShapeIndex >= 0 && selectedShapeIndex != i) continue;
                                using (System.Drawing.Drawing2D.GraphicsPath selectedPath = new System.Drawing.Drawing2D.GraphicsPath())
                                {
                                    selectedPath.AddPolygon(TranslatePolygon(extractionShapes[i], crop.X, crop.Y));
                                    selection.Union(selectedPath);
                                }
                            }
                            graphics.SetClip(selection, selectedShapeIndex >= 0
                                ? System.Drawing.Drawing2D.CombineMode.Intersect
                                : System.Drawing.Drawing2D.CombineMode.Exclude);
                        }
                    }
                    graphics.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                    graphics.DrawImage(source, new Rectangle(0, 0, crop.Width, crop.Height), crop, GraphicsUnit.Pixel);
                    graphics.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceOver;
                    using (Pen depthEdge = new Pen(Color.FromArgb(48, 8, 10, 16), Math.Max(4.0f, Math.Min(8.0f, thickness * 0.35f))))
                    using (Pen bevelLight = new Pen(Color.FromArgb(36, Color.White), 1.0f))
                    {
                        depthEdge.LineJoin = System.Drawing.Drawing2D.LineJoin.Round;
                        bevelLight.LineJoin = System.Drawing.Drawing2D.LineJoin.Round;
                        graphics.DrawPath(depthEdge, path);
                        graphics.DrawPath(bevelLight, path);
                    }
                    for (int i = 0; i < lines.Count; i++) SlashForm.DrawSlashStroke(graphics, crop, lines[i].Start, lines[i].End, 255, slashColor, outlineColor, thickness);
                }
                hasContent = LimitAlphaToSource(result, source, crop);
                return result;
            }
            catch { result.Dispose(); throw; }
        }

        private void AddPiece(Bitmap image, Rectangle bounds, Rectangle crop, PointF[] localShape, PointF direction)
        {
            try
            {
                Rectangle screenBounds = new Rectangle(bounds.X + crop.X, bounds.Y + crop.Y, crop.Width, crop.Height);
                SliceForm form = new SliceForm(image, screenBounds, localShape);
                image = null;
                _pieces.Add(form);
                _pieceBounds.Add(screenBounds);
                _pieceDirections.Add(direction);
            }
            finally { if (image != null) image.Dispose(); }
        }

        private static PointF GetOppositeDirection(PointF direction)
        {
            return new PointF(-direction.X, -direction.Y);
        }

        private static bool LimitAlphaToSource(Bitmap result, Bitmap source, Rectangle crop)
        {
            bool any = false;
            BitmapData resultData = null;
            BitmapData sourceData = null;
            try
            {
                resultData = result.LockBits(new Rectangle(0, 0, result.Width, result.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
                sourceData = source.LockBits(crop, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                byte[] resultRow = new byte[result.Width * 4];
                byte[] sourceRow = new byte[result.Width * 4];
                for (int y = 0; y < result.Height; y++)
                {
                    IntPtr resultPointer = IntPtr.Add(resultData.Scan0, y * resultData.Stride);
                    Marshal.Copy(resultPointer, resultRow, 0, resultRow.Length);
                    Marshal.Copy(IntPtr.Add(sourceData.Scan0, y * sourceData.Stride), sourceRow, 0, sourceRow.Length);
                    bool changed = false;
                    for (int x = 0; x < result.Width; x++)
                    {
                        int a = x * 4 + 3;
                        if (resultRow[a] > sourceRow[a]) { resultRow[a] = sourceRow[a]; changed = true; }
                        if (resultRow[a] > 12) any = true;
                    }
                    if (changed) Marshal.Copy(resultRow, 0, resultPointer, resultRow.Length);
                }
            }
            finally
            {
                if (resultData != null) result.UnlockBits(resultData);
                if (sourceData != null) source.UnlockBits(sourceData);
            }
            return any;
        }

        private static PointF GetPieceDirection(IList<PointF> polygon, Size size)
        {
            PointF centroid = PolygonCentroid(polygon);
            double dx = centroid.X - size.Width * 0.5, dy = centroid.Y - size.Height * 0.5;
            double length = Math.Sqrt(dx * dx + dy * dy);
            if (length < 0.001)
            {
                dx = polygon[0].X - size.Width * 0.5; dy = polygon[0].Y - size.Height * 0.5;
                length = Math.Sqrt(dx * dx + dy * dy);
            }
            return length < 0.001 ? new PointF(0, -1) : new PointF((float)(dx / length), (float)(dy / length));
        }

        private void DisposePieces()
        {
            for (int i = 0; i < _pieces.Count; i++) if (_pieces[i] != null) { _pieces[i].Close(); _pieces[i].Dispose(); }
            _pieces.Clear(); _pieceBounds.Clear(); _pieceDirections.Clear();
        }

        internal static void CalculateHalves(Rectangle bounds, bool vertical, out Rectangle first, out Rectangle second)
        {
            if (vertical)
            {
                int firstWidth = bounds.Width / 2;
                first = new Rectangle(bounds.Left, bounds.Top, firstWidth, bounds.Height);
                second = new Rectangle(bounds.Left + firstWidth, bounds.Top, bounds.Width - firstWidth, bounds.Height);
            }
            else
            {
                int firstHeight = bounds.Height / 2;
                first = new Rectangle(bounds.Left, bounds.Top, bounds.Width, firstHeight);
                second = new Rectangle(bounds.Left, bounds.Top + firstHeight, bounds.Width, bounds.Height - firstHeight);
            }
        }

        public void Start()
        {
            BeginSlash();
            _timer.Start();
        }

        public SliceForm WaitingSnapshot
        {
            get { return _waitingForClick && _waitingPreview != null && !_waitingPreview.IsDisposed && _waitingPreview.Visible ? _waitingPreview : null; }
        }

        public bool IsWaitingSnapshot(SliceForm snapshot)
        {
            return !_done && _waitingForClick && snapshot != null &&
                Object.ReferenceEquals(_waitingPreview, snapshot) && !snapshot.IsDisposed && snapshot.Visible;
        }

        public Bitmap CloneWaitingBaseImage()
        {
            if (_done || !_waitingForClick || _waitingBaseImage == null)
                throw new InvalidOperationException("The waiting snapshot is no longer available.");
            return new Bitmap(_waitingBaseImage);
        }

        public void AppendPendingCuts(List<SlashLine> lines, List<PointF[]> shapes)
        {
            if (_done || !_waitingForClick) throw new InvalidOperationException("The waiting snapshot is no longer available.");
            if (lines != null) lines.AddRange(_pendingLines);
            if (shapes != null)
                for (int i = 0; i < _pendingShapes.Count; i++)
                    shapes.Add((PointF[])_pendingShapes[i].Clone());
        }

        public void ConsumeWaitingSnapshot()
        {
            if (_done || !_waitingForClick) return;
            _done = true;
            _waitingForClick = false;
            _timer.Stop();
            _timer.Tick -= OnTick;
            _timer.Dispose();
            _watch.Stop();
            if (_slash != null) { _slash.Close(); _slash.Dispose(); _slash = null; }
            if (_waitingPreview != null) { _waitingPreview.Close(); _waitingPreview.Dispose(); _waitingPreview = null; }
            if (_waitingBaseImage != null) { _waitingBaseImage.Dispose(); _waitingBaseImage = null; }
            DisposePieces();
            if (_finished != null) _finished();
        }

        public void HideForCapture()
        {
            if (_done || _overlaysSuspended) return;
            _overlaysSuspended = true;
            _slashWasVisibleWhenSuspended = _slash != null && _slash.Visible;
            if (_slashWasVisibleWhenSuspended) _slash.Hide();
            _pieceVisibilityWhenSuspended = new bool[_pieces.Count];
            for (int i = 0; i < _pieces.Count; i++)
            {
                _pieceVisibilityWhenSuspended[i] = _pieces[i].Visible;
                if (_pieceVisibilityWhenSuspended[i]) _pieces[i].Hide();
            }
            if (_waitingPreview != null && _waitingPreview.Visible) _waitingPreview.Hide();
        }

        public void RestoreAfterCapture()
        {
            if (!_overlaysSuspended || _done) return;
            if (_slashWasVisibleWhenSuspended && _slash != null)
            {
                _slash.Show();
                Native.PutTopmostWithoutActivate(_slash.Handle, _slash.Bounds);
            }
            if (_pieceVisibilityWhenSuspended != null)
            {
                for (int i = 0; i < _pieces.Count && i < _pieceVisibilityWhenSuspended.Length; i++)
                    if (_pieceVisibilityWhenSuspended[i])
                    {
                        _pieces[i].Show();
                        Native.PutTopmostWithoutActivate(_pieces[i].Handle, _pieces[i].Bounds);
                    }
                    if (_waitingForClick && _waitingPreview != null)
                    {
                        _waitingPreview.Show();
                        Native.PutTopmostWithoutActivate(_waitingPreview.Handle, _waitingPreview.Bounds);
                    }
            }
            _pieceVisibilityWhenSuspended = null;
            _slashWasVisibleWhenSuspended = false;
            _overlaysSuspended = false;
        }

        private void BeginSlash()
{
    _slash.Show();
    Native.PutTopmostWithoutActivate(_slash.Handle, _slash.Bounds);

    if (!_clickToDisperse && _target != null && _target.Fragment != null && !_target.Fragment.IsDisposed) _target.Fragment.Hide();

    _sounds.PlayPrepare();

    QueueSliceSound();

    _watch.Restart();
}

        private void QueueSliceSound()
        {
    if (_sliceSoundQueued) return;
    _sliceSoundQueued = true;
    ThreadPool.QueueUserWorkItem(delegate
    {
        try
        {
            Thread.Sleep(800);
            _sounds.PlayRandom();
        }
        catch { }
    });
        }

        private void ShowHalves()
        {
            if (_keepWindowOpen) PrepareLiveWindow();
            for (int i = 0; i < _pieces.Count; i++)
            {
                if (_keepWindowOpen && i == _attachedWindowPieceIndex) continue;
                _pieces[i].Show();
                Native.PutTopmostWithoutActivate(_pieces[i].Handle, _pieceBounds[i]);
            }
            if (!_keepWindowOpen) CloseTargetForSlice();
            if (_slash != null) { _slash.Close(); _slash.Dispose(); _slash = null; }
            _piecesWereShown = true;
            _watch.Restart();
        }

        private void PrepareLiveWindow()
        {
            if (!_keepWindowOpen || _liveWindowSession != null) return;
            _liveWindowSession = new LiveWindowSliceSession(_target, _animationBounds, _refreshLiveFragments);
            try { _liveWindowSession.ApplyRemainingPolygon(_attachedWindowPolygon, _attachedWindowCutoutShape); }
            catch
            {
                _liveWindowSession.Restore();
                _liveWindowSession = null;
                throw;
            }
        }

        private void ShowWaitingPreviewAndCloseTarget()
        {
            if (_waitingPreview == null) throw new InvalidOperationException("The stationary window preview could not be created.");
            _waitingPreview.Show();
            Native.PutTopmostWithoutActivate(_waitingPreview.Handle, _waitingPreview.Bounds);
            if (!_keepWindowOpen) CloseTargetForSlice();
            if (_slash != null) { _slash.Close(); _slash.Dispose(); _slash = null; }
            _watch.Restart();
        }

        private void BeginDispersal()
        {
            _sounds.PlayDisperse();
            if (_keepWindowOpen) PrepareLiveWindow();
            for (int i = 0; i < _pieces.Count; i++)
            {
                if (_keepWindowOpen && i == _attachedWindowPieceIndex) continue;
                _pieces[i].Show();
                Native.PutTopmostWithoutActivate(_pieces[i].Handle, _pieceBounds[i]);
            }
            if (_waitingPreview != null)
            {
                _waitingPreview.Close();
                _waitingPreview.Dispose();
                _waitingPreview = null;
            }
            _piecesWereShown = true;
            _waitingForClick = false;
            _watch.Restart();
        }

        private void CloseTargetForSlice()
        {
            if (_target.IsScreenCapture) return;
            if (_target.Fragment != null) RemoveSourceFragment();
            bool ownsCloseRequest = _target.Fragment == null && (_targetGroup == null || _targetGroup.TryClaimCloseRequest());
            if (!ownsCloseRequest) return;
            try
            {
                if (_target.IsStillSameWindow())
                {
                    Native.HideWindow(_target.Handle);
                    _targetHidden = !Native.IsWindowVisible(_target.Handle);
                    if (!_targetHidden) throw new InvalidOperationException("Windows did not hide the original window for the animation.");
                    if (!Native.PostMessage(_target.Handle, Native.CloseMessage, IntPtr.Zero, IntPtr.Zero))
                        throw new InvalidOperationException("Windows did not accept the close request, so the original window was left open.");
                    _closeRequestPosted = true;
                }
                else if (_targetGroup != null) _targetGroup.ReleaseCloseRequestClaim();
            }
            catch
            {
                if (_targetGroup != null && !_closeRequestPosted) _targetGroup.ReleaseCloseRequestClaim();
                throw;
            }
        }

        private void OnTick(object sender, EventArgs e)
        {
            try
            {
                if (_waitingForClick)
                {
                    bool leftMouseDown = (Native.GetAsyncKeyState(0x01) & 0x8000) != 0;
                    Point cursor = System.Windows.Forms.Cursor.Position;
                    bool clickedInsideTarget = leftMouseDown && !_leftMouseDownLastTick &&
                        _animationBounds.Contains(cursor);
                    _leftMouseDownLastTick = leftMouseDown;
                    if (ShouldBeginDispersal(_clickToDisperse, true, clickedInsideTarget))
                    {
                        BeginDispersal();
                        return;
                    }
                    return;
                }
                if (_slash != null)
                {
                    long slashElapsed = _watch.ElapsedMilliseconds;
                    const int slashDrawDuration = 210;
                    const int slashFadeDuration = 240;
                    _slash.Progress = Math.Min(1.0, (double)slashElapsed / slashDrawDuration);
                    if (_clickToDisperse)
                    {
                        _slash.OverlayOpacity = SlashOverlayOpacity(slashElapsed, slashDrawDuration, slashFadeDuration);
                        if (slashElapsed >= slashDrawDuration + slashFadeDuration)
                        {
                            ShowWaitingPreviewAndCloseTarget();
                            _waitingForClick = true;
                            _leftMouseDownLastTick = (Native.GetAsyncKeyState(0x01) & 0x8000) != 0;
                        }
                    }
                    else if (slashElapsed >= 340)
                        ShowHalves();
                    return;
                }
                double progress = Math.Min(1.0, (double)_watch.ElapsedMilliseconds / _duration);
                double eased = 1.0 - Math.Pow(1.0 - progress, 3.0);
                double opacity = _keepFragments ? 1.0 : FadeOpacity(progress);
                for (int i = 0; i < _pieces.Count; i++)
                {
                    if (_keepWindowOpen && i == _attachedWindowPieceIndex) continue;
                    Rectangle moved = _pieceBounds[i];
                    moved.X += (int)Math.Round(_distance * eased * _pieceDirections[i].X);
                    moved.Y += (int)Math.Round(_distance * eased * _pieceDirections[i].Y);
                    _pieces[i].Bounds = moved;
                    _pieces[i].LayerOpacity = opacity;
                    Native.PutTopmostWithoutActivate(_pieces[i].Handle, moved);
                }
                if (progress >= 1.0) Finish(true);
            }
            catch (Exception ex)
            {
                Finish(false);
                string status = _closeRequestPosted ? "The animation stopped after its normal close request was sent. The application may already be closing." : "The animation stopped, so the window was left open.";
                MessageBox.Show(status + "\r\n\r\n" + ex.Message, "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        internal static double FadeOpacity(double progress)
        {
            progress = Math.Max(0.0, Math.Min(1.0, progress));
            return 1.0 - progress;
        }

        internal static double SlashOverlayOpacity(long elapsedMilliseconds, int drawDuration, int fadeDuration)
        {
            if (elapsedMilliseconds <= drawDuration) return 1.0;
            if (fadeDuration <= 0 || elapsedMilliseconds >= (long)drawDuration + fadeDuration) return 0.0;
            return 1.0 - (double)(elapsedMilliseconds - drawDuration) / fadeDuration;
        }

        internal static bool ShouldBeginDispersal(bool clickToDisperse, bool slashFinished, bool clickedInsideTarget)
        {
            return !clickToDisperse || (slashFinished && clickedInsideTarget);
        }

        public bool DisperseSnapshot()
        {
            if (_done || !_waitingForClick) return false;
            BeginDispersal();
            return true;
        }

        internal static bool ShouldSendCloseRequest(bool animationCompleted, bool requestAlreadyPosted)
        {
            return animationCompleted && !requestAlreadyPosted;
        }

        internal static bool ShouldRetainFragments(bool keepFragments, bool animationCompleted, bool piecesWereShown)
        {
            return keepFragments && animationCompleted && piecesWereShown;
        }

        internal static bool ShouldKeepFragments(bool keepFragments, bool slicingFragment, bool extractingShape, bool clickToDisperse)
        {
            return keepFragments || slicingFragment || extractingShape || clickToDisperse;
        }

        internal static bool ShouldKeepFragmentsForSlice(bool keepWindowOpen, bool keepFragments, bool slicingFragment, bool extractingShape, bool clickToDisperse)
        {
            return keepWindowOpen
                ? keepFragments
                : ShouldKeepFragments(keepFragments, slicingFragment, extractingShape, clickToDisperse);
        }

        internal static bool ShouldKeepSourceWindowOpen(bool enabled, WindowTarget target)
        {
            return enabled && target != null && target.Fragment == null && !target.IsScreenCapture;
        }

        internal static bool ShouldCommitLiveWindow(bool keepWindowOpen, bool keepFragments, bool animationCompleted, bool piecesWereShown)
        {
            return keepWindowOpen && !keepFragments && animationCompleted && piecesWereShown;
        }

        private void RetainPieces()
        {
            for (int i = 0; i < _pieces.Count; i++)
            {
                SliceForm piece = _pieces[i];
                if (piece == null || piece.IsDisposed) continue;
                if (_keepWindowOpen && i == _attachedWindowPieceIndex)
                {
                    piece.Close();
                    piece.Dispose();
                    continue;
                }
                piece.LayerOpacity = 1.0;
                piece.MakePersistent(_rotateFragmentsWithArrowKeys);
                if (_liveWindowSession != null)
                    _liveWindowSession.Attach(piece, _pieceBounds[i], _interactiveDetachedPieces);
            }
            if (_liveWindowSession != null) _liveWindowSession = null;
            _pieces.Clear();
            _pieceBounds.Clear();
            _pieceDirections.Clear();
        }

        private void RemoveSourceFragment()
        {
            SliceForm source = _target.Fragment;
            if (source == null || source.IsDisposed) return;
            _sourceFragmentRemoved = true;
            PersistentFragmentStore.Remove(source);
            source.Close();
        }

        private bool RestoreTarget()
        {
            if (_target != null && _target.IsScreenCapture) return true;
            if (_target != null && _target.Fragment != null)
            {
                SliceForm source = _target.Fragment;
                if (!_sourceFragmentRemoved && !source.IsDisposed && !source.Visible)
                {
                    source.Show();
                    Native.PutTopmostWithoutActivate(source.Handle, source.Bounds);
                }
                return true;
            }
            if (!_targetHidden) return true;
            if (!_target.IsStillSameWindow()) { _targetHidden = false; return true; }
            Native.ShowWindowWithoutActivate(_target.Handle);
            if (!Native.IsWindowVisible(_target.Handle)) Native.ShowWindowNormally(_target.Handle);
            bool visible = Native.IsWindowVisible(_target.Handle);
            _targetHidden = !visible;
            return visible;
        }

        private void Finish(bool closeWindow)
        {
            if (_done) return;
            string liveRestoreError = null;
            _done = true;
            _timer.Stop();
            _timer.Tick -= OnTick;
            _timer.Dispose();
            _watch.Stop();
            if (_slash != null) { _slash.Close(); _slash.Dispose(); _slash = null; }
            if (_waitingPreview != null) { _waitingPreview.Close(); _waitingPreview.Dispose(); _waitingPreview = null; }
            if (_waitingBaseImage != null) { _waitingBaseImage.Dispose(); _waitingBaseImage = null; }
            bool retainPieces = ShouldRetainFragments(_keepFragments, closeWindow, _piecesWereShown);
            if (retainPieces) RetainPieces();
            else
            {
                if (_liveWindowSession != null)
                {
                    try
                    {
                        if (ShouldCommitLiveWindow(_keepWindowOpen, _keepFragments, closeWindow, _piecesWereShown))
                            _liveWindowSession.CommitRemainingWindow();
                        else
                            _liveWindowSession.Restore();
                        _liveWindowSession = null;
                    }
                    catch (Exception ex) { liveRestoreError = ex.Message; }
                }
                DisposePieces();
            }
            if (!_keepWindowOpen && _target != null && !_target.IsScreenCapture && _target.Fragment == null && ShouldSendCloseRequest(closeWindow, _closeRequestPosted) && _target.IsStillSameWindow() && (_targetGroup == null || _targetGroup.TryClaimCloseRequest()))
            {
                bool closeSent = _targetHidden ? Native.SendCloseRequest(_target.Handle) : Native.PostMessage(_target.Handle, Native.CloseMessage, IntPtr.Zero, IntPtr.Zero);
                if (!closeSent && _targetGroup != null) _targetGroup.ReleaseCloseRequestClaim();
            }
            bool restored = _target == null || RestoreTarget();
            if (!restored)
                MessageBox.Show("Window Slice could not restore the original window after the animation. Use Alt+Tab to locate it.", "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            if (liveRestoreError != null)
                MessageBox.Show("A live-sliced window could not be restored. Its recovery remains registered and will be retried when Window Slice exits.\r\n\r\n" + liveRestoreError, "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Error);
            if (_finished != null) _finished();
        }

        public void Dispose() { Finish(false); }
    }

    internal sealed class SettingsForm : Form
    {
        private readonly TextBox _quickHotkey;
        private readonly TextBox _selectionHotkey;
        private readonly TextBox _precisionHotkey;
        private readonly TextBox _disperseSnapshotsHotkey;
        private readonly Button _quickCapture;
        private readonly Button _selectionCapture;
        private readonly Button _precisionCapture;
        private readonly Button _disperseSnapshotsCapture;
        private readonly ComboBox _direction;
        private readonly NumericUpDown _multiCount;
        private readonly ComboBox _multiPattern;
        private readonly NumericUpDown _duration;
        private readonly NumericUpDown _distance;
        private readonly Button _slashColorButton;
        private readonly Button _outlineColorButton;
        private readonly NumericUpDown _slashThickness;
        private readonly CheckBox _confirm;
        private readonly CheckBox _repeatSlices;
        private readonly CheckBox _keepFragments;
        private readonly CheckBox _sliceFragments;
        private readonly CheckBox _unlimitedPerformance;
        private readonly CheckBox _clickToDisperse;
        private readonly CheckBox _rotateFragments;
        private readonly CheckBox _keepWindowsOpen;
        private readonly CheckBox _interactiveDetachedPieces;
        private readonly CheckBox _refreshLiveFragments;
        private Color _slashColor;
        private Color _outlineColor;
        private TextBox _capturingBox;
        private Button _capturingButton;
        public Settings Result;

        public SettingsForm(Settings current)
        {
            Text = "Window Slice settings";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterScreen;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = true;
            ClientSize = new Size(720, 696);
            current.Normalize();
            _slashColor = ColorTranslator.FromHtml(current.SlashColor);
            _outlineColor = ColorTranslator.FromHtml(current.OutlineColor);

            TableLayoutPanel layout = new TableLayoutPanel();
            layout.Dock = DockStyle.Fill;
            layout.Padding = new Padding(14);
            layout.ColumnCount = 2;
            layout.RowCount = 18;
            layout.AutoScroll = false;
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190));
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            for (int i = 0; i < 13; i++) layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 184));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 74));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 68));

            _quickHotkey = CreateHotkeyBox(current.QuickSliceHotkey);
            _quickCapture = CreateCaptureButton();
            _quickCapture.Click += delegate { BeginCapture(_quickHotkey, _quickCapture); };
            AddLabel(layout, "Quick Slice shortcut", 0);
            layout.Controls.Add(CreateHotkeyPanel(_quickHotkey, _quickCapture), 1, 0);

            _selectionHotkey = CreateHotkeyBox(current.SelectionHotkey);
            _selectionCapture = CreateCaptureButton();
            _selectionCapture.Click += delegate { BeginCapture(_selectionHotkey, _selectionCapture); };
            AddLabel(layout, "Multi-Select shortcut", 1);
            layout.Controls.Add(CreateHotkeyPanel(_selectionHotkey, _selectionCapture), 1, 1);

            _precisionHotkey = CreateHotkeyBox(current.PrecisionHotkey);
            _precisionCapture = CreateCaptureButton();
            _precisionCapture.Click += delegate { BeginCapture(_precisionHotkey, _precisionCapture); };
            AddLabel(layout, "Precision Slice shortcut", 2);
            layout.Controls.Add(CreateHotkeyPanel(_precisionHotkey, _precisionCapture), 1, 2);

            _direction = new ComboBox();
            _direction.DropDownStyle = ComboBoxStyle.DropDownList;
            _direction.Items.AddRange(new object[] { "Vertical (left and right)", "Horizontal (top and bottom)", "Diagonal (corner to corner)", "Multi-slash" });
            if (String.Equals(current.Direction, "Horizontal", StringComparison.OrdinalIgnoreCase)) _direction.SelectedIndex = 1;
            else if (String.Equals(current.Direction, "Diagonal", StringComparison.OrdinalIgnoreCase)) _direction.SelectedIndex = 2;
            else if (String.Equals(current.Direction, "MultiSlash", StringComparison.OrdinalIgnoreCase)) _direction.SelectedIndex = 3;
            else _direction.SelectedIndex = 0;
            _direction.Dock = DockStyle.Fill;
            AddLabel(layout, "Split direction", 3);
            layout.Controls.Add(_direction, 1, 3);

            _multiCount = NumberBox(current.UnlimitedPerformance ? Int32.MinValue : 2,
                current.UnlimitedPerformance ? Int32.MaxValue : Math.Max(25, current.MultiSlashCount), 1, current.MultiSlashCount);
            AddLabel(layout, "Number of slashes", 4);
            layout.Controls.Add(_multiCount, 1, 4);

            _multiPattern = new ComboBox();
            _multiPattern.DropDownStyle = ComboBoxStyle.DropDownList;
            _multiPattern.Items.AddRange(new object[] { "Radial (through center)", "Random directions" });
            _multiPattern.SelectedIndex = String.Equals(current.MultiPattern, "Random", StringComparison.OrdinalIgnoreCase) ? 1 : 0;
            _multiPattern.Dock = DockStyle.Fill;
            AddLabel(layout, "Multi-slash layout", 5);
            layout.Controls.Add(_multiPattern, 1, 5);
            _direction.SelectedIndexChanged += delegate
            {
                bool multi = _direction.SelectedIndex == 3;
                _multiCount.Enabled = multi;
                _multiPattern.Enabled = multi;
            };
            _multiCount.Enabled = _direction.SelectedIndex == 3;
            _multiPattern.Enabled = _direction.SelectedIndex == 3;

            _duration = NumberBox(current.UnlimitedPerformance ? Int32.MinValue : 1,
                current.UnlimitedPerformance ? Int32.MaxValue : Math.Max(6000, current.DurationMs), 50, current.DurationMs);
            AddLabel(layout, "Animation duration (ms)", 6);
            layout.Controls.Add(_duration, 1, 6);

            _distance = NumberBox(current.UnlimitedPerformance ? Int32.MinValue : 0,
                current.UnlimitedPerformance ? Int32.MaxValue : Math.Max(600, current.DistancePx), 10, current.DistancePx);
            AddLabel(layout, "Travel distance (px)", 7);
            layout.Controls.Add(_distance, 1, 7);

            _slashColorButton = CreateColorButton(_slashColor);
            _slashColorButton.Click += delegate { ChooseColor(true); };
            AddLabel(layout, "Slash color", 8);
            layout.Controls.Add(_slashColorButton, 1, 8);

            _outlineColorButton = CreateColorButton(_outlineColor);
            _outlineColorButton.Click += delegate { ChooseColor(false); };
            AddLabel(layout, "Outline color", 9);
            layout.Controls.Add(_outlineColorButton, 1, 9);

            _slashThickness = NumberBox(current.UnlimitedPerformance ? Int32.MinValue : 1,
                current.UnlimitedPerformance ? Int32.MaxValue : Math.Max(40, current.SlashThickness), 1, current.SlashThickness);
            AddLabel(layout, "Slash thickness (px)", 10);
            layout.Controls.Add(_slashThickness, 1, 10);

            _confirm = new CheckBox();
            _confirm.Text = "Ask before sending the close request";
            _confirm.Checked = current.ConfirmBeforeClose;
            _confirm.Dock = DockStyle.Fill;
            AddLabel(layout, "Window safety", 11);
            layout.Controls.Add(_confirm, 1, 11);

            _repeatSlices = new CheckBox();
            _repeatSlices.Text = "Allow slicing the same window again while it animates";
            _repeatSlices.Checked = current.AllowRepeatedSlices;
            _repeatSlices.Dock = DockStyle.Fill;
            AddLabel(layout, "Repeated slices", 12);
            layout.Controls.Add(_repeatSlices, 1, 12);

            _keepFragments = new CheckBox();
            _keepFragments.Text = "Keep fragments draggable";
            _keepFragments.Checked = current.KeepFragments;
            _keepFragments.Dock = DockStyle.Fill;
            _rotateFragments = new CheckBox();
            _rotateFragments.Text = "Rotate fragments with arrow keys";
            _rotateFragments.Checked = current.RotateFragmentsWithArrowKeys;
            _rotateFragments.Dock = DockStyle.Fill;
            _keepWindowsOpen = new CheckBox();
            _keepWindowsOpen.Text = "Keep source window open and sliced";
            _keepWindowsOpen.Checked = current.KeepWindowsOpenAfterSlicing;
            _keepWindowsOpen.Dock = DockStyle.Fill;
            _interactiveDetachedPieces = new CheckBox();
            _interactiveDetachedPieces.Text = "Forward mouse movement/wheel; use source for keyboard";
            _interactiveDetachedPieces.Checked = current.DetachedPiecesInteractive;
            _interactiveDetachedPieces.Enabled = _keepWindowsOpen.Checked;
            _refreshLiveFragments = new CheckBox();
            _refreshLiveFragments.Text = "Refresh detached fragments from live window (work in progress)";
            _refreshLiveFragments.Checked = current.RefreshLiveFragments;
            _refreshLiveFragments.Enabled = Settings.CanRefreshLiveFragments(_keepWindowsOpen.Checked, _keepFragments.Checked);
            Action updateRefreshAvailability = delegate
            {
                if (_keepFragments.Checked) _refreshLiveFragments.Checked = false;
                _refreshLiveFragments.Enabled = Settings.CanRefreshLiveFragments(_keepWindowsOpen.Checked, _keepFragments.Checked);
            };
            _keepFragments.CheckedChanged += delegate { updateRefreshAvailability(); };
            _keepWindowsOpen.CheckedChanged += delegate
            {
                if (_keepWindowsOpen.Checked &&
                    MessageBox.Show(this,
                        "Live slicing changes the source window's visible region. Right-click a detached piece to restore the full window. Do not force-close Window Slice while a live slice is active.\r\n\r\nEnable live slicing? (THIS IS HIGHLY WORK IN PROGRESS!)",
                        "Live window safety", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
                {
                    _keepWindowsOpen.Checked = false;
                    return;
                }
                _interactiveDetachedPieces.Enabled = _keepWindowsOpen.Checked;
                updateRefreshAvailability();
                _confirm.Enabled = !_keepWindowsOpen.Checked;
            };
            _confirm.Enabled = !_keepWindowsOpen.Checked;
            TableLayoutPanel persistentOptions = new TableLayoutPanel();
            persistentOptions.Dock = DockStyle.Top;
            persistentOptions.Height = 135;
            persistentOptions.RowCount = 5;
            persistentOptions.ColumnCount = 1;
            persistentOptions.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            for (int i = 0; i < 5; i++) persistentOptions.RowStyles.Add(new RowStyle(SizeType.Absolute, 27));
            persistentOptions.Controls.Add(_keepFragments, 0, 0);
            persistentOptions.Controls.Add(_rotateFragments, 0, 1);
            persistentOptions.Controls.Add(_keepWindowsOpen, 0, 2);
            persistentOptions.Controls.Add(_interactiveDetachedPieces, 0, 3);
            persistentOptions.Controls.Add(_refreshLiveFragments, 0, 4);
            Panel persistentPanel = new Panel();
            persistentPanel.Dock = DockStyle.Fill;
            persistentPanel.Controls.Add(persistentOptions);
            Label persistentWarning = new Label();
            persistentWarning.Text = "Live windows support at most one precision shape cutout per window; line cuts are allowed. Refresh is work in progress and may flicker or fail for some apps.";
            persistentWarning.ForeColor = Color.Firebrick;
            persistentWarning.Dock = DockStyle.Bottom;
            persistentWarning.Height = 46;
            persistentWarning.AutoSize = false;
            persistentPanel.Controls.Add(persistentWarning);
            AddLabel(layout, "Persistent fragments", 13);
            layout.Controls.Add(persistentPanel, 1, 13);

            _sliceFragments = new CheckBox();
            _sliceFragments.Text = "Allow slicing persistent fragments";
            _sliceFragments.Checked = current.FragmentsCanBeSliced;
            _sliceFragments.Dock = DockStyle.Fill;
            AddLabel(layout, "Fragments can be sliced", 14);
            layout.Controls.Add(_sliceFragments, 1, 14);

            Button removeFragments = new Button();
            removeFragments.Text = "Remove all fragments";
            removeFragments.Dock = DockStyle.Left;
            removeFragments.Width = 190;
            removeFragments.Enabled = PersistentFragmentStore.Count > 0;
            removeFragments.Click += delegate
            {
                PersistentFragmentStore.DisposeAll();
                removeFragments.Enabled = false;
            };
            AddLabel(layout, "Fragment cleanup", 15);
            layout.Controls.Add(removeFragments, 1, 15);

            _clickToDisperse = new CheckBox();
            _clickToDisperse.Text = "Close after the slash; wait for a click to disperse fragments";
            _clickToDisperse.Checked = current.ClickToDisperse;
            _clickToDisperse.Dock = DockStyle.Fill;
            _disperseSnapshotsHotkey = CreateHotkeyBox(current.DisperseSnapshotsHotkey);
            _disperseSnapshotsCapture = CreateCaptureButton();
            _disperseSnapshotsCapture.Click += delegate { BeginCapture(_disperseSnapshotsHotkey, _disperseSnapshotsCapture); };
            Panel dispersePanel = new Panel();
            dispersePanel.Dock = DockStyle.Fill;
            _clickToDisperse.Dock = DockStyle.Top;
            Panel disperseHotkeyPanel = CreateHotkeyPanel(_disperseSnapshotsHotkey, _disperseSnapshotsCapture);
            disperseHotkeyPanel.Dock = DockStyle.Bottom;
            disperseHotkeyPanel.Height = 28;
            Label disperseHotkeyLabel = new Label();
            disperseHotkeyLabel.Text = "Shortcut (optional):";
            disperseHotkeyLabel.Dock = DockStyle.Left;
            disperseHotkeyLabel.Width = 110;
            _disperseSnapshotsHotkey.Width = 125;
            dispersePanel.Controls.Add(disperseHotkeyLabel);
            dispersePanel.Controls.Add(disperseHotkeyPanel);
            dispersePanel.Controls.Add(_clickToDisperse);
            AddLabel(layout, "Click to disperse", 16);
            layout.Controls.Add(dispersePanel, 1, 16);

            _unlimitedPerformance = new CheckBox();
            _unlimitedPerformance.Text = "Remove slicing and animation limits";
            _unlimitedPerformance.Checked = current.UnlimitedPerformance;
            _unlimitedPerformance.Dock = DockStyle.Top;
            Panel performancePanel = new Panel();
            performancePanel.Dock = DockStyle.Fill;
            performancePanel.Controls.Add(_unlimitedPerformance);
            Label performanceWarning = new Label();
            performanceWarning.Text = "WARNING: high slash counts, large windows, or many simultaneous slices can exhaust memory, freeze Windows, or crash this app.";
            performanceWarning.ForeColor = Color.Firebrick;
            performanceWarning.Dock = DockStyle.Bottom;
            performanceWarning.Height = 34;
            performanceWarning.AutoSize = false;
            performancePanel.Controls.Add(performanceWarning);
            AddLabel(layout, "Performance", 17);
            layout.Controls.Add(performancePanel, 1, 17);
            _unlimitedPerformance.CheckedChanged += delegate
            {
                if (_unlimitedPerformance.Checked &&
                    MessageBox.Show(this, "Removing these limits can exhaust memory, freeze Windows, or crash Window Slice. Continue?", "Performance warning", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
                {
                    _unlimitedPerformance.Checked = false;
                    return;
                }
                UpdatePerformanceLimits();
            };
            UpdatePerformanceLimits();

            TabControl pages = new TabControl();
            pages.Dock = DockStyle.Fill;
            TabPage shortcutsPage = new TabPage("Shortcuts");
            TabPage cutsPage = new TabPage("Cut layout");
            TabPage animationPage = new TabPage("Animation and safety");
            TabPage fragmentsPage = new TabPage("Fragments and extras");
            shortcutsPage.AutoScroll = true;
            cutsPage.AutoScroll = true;
            animationPage.AutoScroll = true;
            fragmentsPage.AutoScroll = true;
            shortcutsPage.Controls.Add(CreateSettingsPage(layout, 0, new int[] { 60, 60, 60 }));
            cutsPage.Controls.Add(CreateSettingsPage(layout, 3, new int[] { 60, 60, 60 }));
            animationPage.Controls.Add(CreateSettingsPage(layout, 6, new int[] { 54, 54, 54, 54, 54, 54, 54 }));
            fragmentsPage.Controls.Add(CreateSettingsPage(layout, 13, new int[] { 196, 54, 54, 74, 68 }));
            pages.TabPages.Add(shortcutsPage);
            pages.TabPages.Add(cutsPage);
            pages.TabPages.Add(animationPage);
            pages.TabPages.Add(fragmentsPage);

            FlowLayoutPanel navigation = new FlowLayoutPanel();
            navigation.Dock = DockStyle.Left;
            navigation.FlowDirection = FlowDirection.LeftToRight;
            navigation.WrapContents = false;
            navigation.Width = 220;
            Button previous = new Button();
            previous.Text = "Back";
            previous.Width = 85;
            previous.Enabled = false;
            Button next = new Button();
            next.Text = "Next";
            next.Width = 85;
            navigation.Controls.Add(previous);
            navigation.Controls.Add(next);

            FlowLayoutPanel buttons = new FlowLayoutPanel();
            buttons.Dock = DockStyle.Right;
            buttons.FlowDirection = FlowDirection.RightToLeft;
            buttons.WrapContents = false;
            buttons.Width = 190;
            Button save = new Button();
            save.Text = "Save";
            save.Width = 85;
            save.DialogResult = DialogResult.OK;
            save.Click += SaveClicked;
            Button cancel = new Button();
            cancel.Text = "Cancel";
            cancel.Width = 85;
            cancel.DialogResult = DialogResult.Cancel;
            buttons.Controls.Add(save);
            buttons.Controls.Add(cancel);

            Label pageIndicator = new Label();
            pageIndicator.Dock = DockStyle.Fill;
            pageIndicator.TextAlign = ContentAlignment.MiddleCenter;
            pageIndicator.Text = "Page 1 of 3";
            previous.Click += delegate
            {
                if (pages.SelectedIndex > 0) pages.SelectedIndex--;
            };
            next.Click += delegate
            {
                if (pages.SelectedIndex < pages.TabPages.Count - 1) pages.SelectedIndex++;
            };
            pages.SelectedIndexChanged += delegate
            {
                previous.Enabled = pages.SelectedIndex > 0;
                next.Enabled = pages.SelectedIndex < pages.TabPages.Count - 1;
                pageIndicator.Text = "Page " + (pages.SelectedIndex + 1).ToString() + " of " + pages.TabPages.Count.ToString();
            };

            Panel footer = new Panel();
            footer.Dock = DockStyle.Bottom;
            footer.Height = 56;
            footer.Padding = new Padding(14, 4, 14, 4);
            footer.Controls.Add(pageIndicator);
            footer.Controls.Add(buttons);
            footer.Controls.Add(navigation);
            AcceptButton = save;
            CancelButton = cancel;
            Controls.Add(pages);
            Controls.Add(footer);
            footer.BringToFront();
        }

        private static TableLayoutPanel CreateSettingsPage(TableLayoutPanel source, int firstRow, int[] rowHeights)
        {
            TableLayoutPanel page = new TableLayoutPanel();
            page.Dock = DockStyle.Top;
            page.Padding = new Padding(14);
            page.ColumnCount = 2;
            page.RowCount = rowHeights.Length;
            page.AutoSize = true;
            page.AutoSizeMode = AutoSizeMode.GrowAndShrink;
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190));
            page.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            for (int row = 0; row < rowHeights.Length; row++)
                page.RowStyles.Add(new RowStyle(SizeType.Absolute, rowHeights[row]));

            Control[] controls = new Control[source.Controls.Count];
            source.Controls.CopyTo(controls, 0);
            for (int i = 0; i < controls.Length; i++)
            {
                TableLayoutPanelCellPosition position = source.GetPositionFromControl(controls[i]);
                if (position.Row < firstRow || position.Row >= firstRow + rowHeights.Length) continue;
                int columnSpan = source.GetColumnSpan(controls[i]);
                source.Controls.Remove(controls[i]);
                page.Controls.Add(controls[i], position.Column, position.Row - firstRow);
                if (columnSpan > 1) page.SetColumnSpan(controls[i], columnSpan);
            }
            return page;
        }

        private TextBox CreateHotkeyBox(string value)
        {
            TextBox box = new TextBox();
            box.ReadOnly = true;
            box.Dock = DockStyle.Left;
            box.Width = 190;
            box.Text = value;
            box.KeyDown += CaptureKeyDown;
            return box;
        }

        private static Button CreateCaptureButton()
        {
            Button button = new Button();
            button.Text = "Change...";
            button.Dock = DockStyle.Right;
            button.Width = 86;
            return button;
        }

        private static Panel CreateHotkeyPanel(TextBox box, Button button)
        {
            Panel panel = new Panel();
            panel.Dock = DockStyle.Fill;
            panel.Controls.Add(box);
            panel.Controls.Add(button);
            return panel;
        }

        private void BeginCapture(TextBox box, Button button)
        {
            if (_capturingButton != null) _capturingButton.Text = "Change...";
            _capturingBox = box;
            _capturingButton = button;
            _capturingButton.Text = "Press keys";
            _capturingBox.Focus();
        }

        private static Button CreateColorButton(Color color)
        {
            Button button = new Button();
            button.Dock = DockStyle.Left;
            button.Width = 150;
            button.FlatStyle = FlatStyle.Flat;
            button.UseVisualStyleBackColor = false;
            button.FlatAppearance.BorderColor = SystemColors.ControlDark;
            UpdateColorButton(button, color);
            return button;
        }

        private static void UpdateColorButton(Button button, Color color)
        {
            button.BackColor = color;
            button.ForeColor = color.GetBrightness() > 0.55f ? Color.Black : Color.White;
            button.Text = FormatHexColor(color);
        }

        private void ChooseColor(bool slash)
        {
            using (ColorDialog dialog = new ColorDialog())
            {
                dialog.FullOpen = true;
                dialog.AnyColor = true;
                dialog.Color = slash ? _slashColor : _outlineColor;
                if (dialog.ShowDialog(this) != DialogResult.OK) return;
                if (slash)
                {
                    _slashColor = dialog.Color;
                    UpdateColorButton(_slashColorButton, _slashColor);
                }
                else
                {
                    _outlineColor = dialog.Color;
                    UpdateColorButton(_outlineColorButton, _outlineColor);
                }
            }
        }

        private static string FormatHexColor(Color color)
        {
            return String.Format(CultureInfo.InvariantCulture, "#{0:X2}{1:X2}{2:X2}", color.R, color.G, color.B);
        }

        private static NumericUpDown NumberBox(int min, int max, int step, int value)
        {
            NumericUpDown box = new NumericUpDown();
            box.Minimum = min; box.Maximum = max; box.Increment = step; box.Value = Math.Max(min, Math.Min(max, value));
            box.Dock = DockStyle.Left; box.Width = 120;
            return box;
        }

        private void UpdatePerformanceLimits()
        {
            SetNumberBoxLimits(_multiCount, _unlimitedPerformance.Checked ? Int32.MinValue : 2, _unlimitedPerformance.Checked ? Int32.MaxValue : 25);
            SetNumberBoxLimits(_duration, _unlimitedPerformance.Checked ? Int32.MinValue : 150, _unlimitedPerformance.Checked ? Int32.MaxValue : 6000);
            SetNumberBoxLimits(_distance, _unlimitedPerformance.Checked ? Int32.MinValue : 0, _unlimitedPerformance.Checked ? Int32.MaxValue : 600);
            SetNumberBoxLimits(_slashThickness, _unlimitedPerformance.Checked ? Int32.MinValue : 1, _unlimitedPerformance.Checked ? Int32.MaxValue : 40);
        }

        private static void SetNumberBoxLimits(NumericUpDown box, int minimum, int maximum)
        {
            box.Maximum = maximum;
            box.Minimum = minimum;
            if (box.Value < minimum) box.Value = minimum;
            else if (box.Value > maximum) box.Value = maximum;
        }

        private static void AddLabel(TableLayoutPanel layout, string text, int row)
        {
            Label label = new Label();
            label.Text = text; label.Dock = DockStyle.Fill; label.TextAlign = ContentAlignment.MiddleLeft;
            layout.Controls.Add(label, 0, row);
        }

        private void CaptureKeyDown(object sender, KeyEventArgs e)
        {
            if (_capturingBox == null || !Object.ReferenceEquals(sender, _capturingBox)) return;
            e.SuppressKeyPress = true;
            e.Handled = true;
            if (Object.ReferenceEquals(_capturingBox, _disperseSnapshotsHotkey) && (e.KeyCode == Keys.Back || e.KeyCode == Keys.Delete))
            {
                _capturingBox.Text = String.Empty;
                _capturingBox = null;
                if (_capturingButton != null) _capturingButton.Text = "Change...";
                _capturingButton = null;
                return;
            }
            if (e.KeyCode == Keys.ControlKey || e.KeyCode == Keys.ShiftKey || e.KeyCode == Keys.Menu) return;
            string value = HotkeySpec.Format(e.KeyCode, e.Modifiers);
            HotkeySpec parsed;
            if (!HotkeySpec.TryParse(value, out parsed))
            {
                MessageBox.Show(this, "Use Ctrl, Alt, or Shift with a key, or choose F1-F11 or F13-F24 by itself. Windows reserves F12, and the Windows key is not supported.", "Shortcut", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            _capturingBox.Text = value;
            _capturingBox = null;
            if (_capturingButton != null) _capturingButton.Text = "Change...";
            _capturingButton = null;
        }

        private void SaveClicked(object sender, EventArgs e)
        {
            HotkeySpec quick;
            HotkeySpec selection;
            HotkeySpec precision;
            HotkeySpec disperseSnapshots;
            if (!HotkeySpec.TryParse(_quickHotkey.Text, out quick) || !HotkeySpec.TryParse(_selectionHotkey.Text, out selection) || !HotkeySpec.TryParse(_precisionHotkey.Text, out precision))
            {
                MessageBox.Show(this, "Choose three valid shortcuts before saving.", "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                DialogResult = DialogResult.None;
                return;
            }
            if (SameHotkey(quick, selection) || SameHotkey(quick, precision) || SameHotkey(selection, precision))
            {
                MessageBox.Show(this, "The three shortcuts must be different. Choose a unique shortcut for each mode.", "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                DialogResult = DialogResult.None;
                return;
            }
            if (!String.IsNullOrWhiteSpace(_disperseSnapshotsHotkey.Text) &&
                (!HotkeySpec.TryParse(_disperseSnapshotsHotkey.Text, out disperseSnapshots) ||
                 SameHotkey(quick, disperseSnapshots) || SameHotkey(selection, disperseSnapshots) ||
                 SameHotkey(precision, disperseSnapshots)))
            {
                MessageBox.Show(this, "The optional disperse shortcut must be valid and different from the other shortcuts.", "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                DialogResult = DialogResult.None;
                return;
            }
            Result = new Settings();
            Result.QuickSliceHotkey = _quickHotkey.Text;
            Result.SelectionHotkey = _selectionHotkey.Text;
            Result.PrecisionHotkey = _precisionHotkey.Text;
            Result.DisperseSnapshotsHotkey = _disperseSnapshotsHotkey.Text;
            Result.Hotkey = Result.QuickSliceHotkey;
            Result.Direction = _direction.SelectedIndex == 1 ? "Horizontal" : _direction.SelectedIndex == 2 ? "Diagonal" : _direction.SelectedIndex == 3 ? "MultiSlash" : "Vertical";
            Result.MultiSlashCount = Decimal.ToInt32(_multiCount.Value);
            Result.MultiPattern = _multiPattern.SelectedIndex == 1 ? "Random" : "Radial";
            Result.DurationMs = Decimal.ToInt32(_duration.Value);
            Result.DistancePx = Decimal.ToInt32(_distance.Value);
            Result.SlashColor = FormatHexColor(_slashColor);
            Result.OutlineColor = FormatHexColor(_outlineColor);
            Result.SlashThickness = Decimal.ToInt32(_slashThickness.Value);
            Result.ConfirmBeforeClose = _confirm.Checked;
            Result.AllowRepeatedSlices = _repeatSlices.Checked;
            Result.KeepFragments = _keepFragments.Checked;
            Result.FragmentsCanBeSliced = _sliceFragments.Checked;
            Result.UnlimitedPerformance = _unlimitedPerformance.Checked;
            Result.ClickToDisperse = _clickToDisperse.Checked;
            Result.RotateFragmentsWithArrowKeys = _rotateFragments.Checked;
            Result.KeepWindowsOpenAfterSlicing = _keepWindowsOpen.Checked;
            Result.DetachedPiecesInteractive = _interactiveDetachedPieces.Checked;
            Result.RefreshLiveFragments = _refreshLiveFragments.Checked;
            Result.Normalize();
        }

        private static bool SameHotkey(HotkeySpec left, HotkeySpec right)
        {
            return left != null && right != null && left.Modifiers == right.Modifiers && left.Key == right.Key;
        }
    }

    internal sealed class TrayApplicationContext : ApplicationContext
    {
        private const int MaximumConcurrentAnimations = 6;
        private Settings _settings;
        private readonly string _configPath;
        private readonly SliceSoundPlayer _sounds;
        private readonly NotifyIcon _icon;
        private readonly HotkeyHost _quickHotkey;
        private readonly HotkeyHost _selectionHotkey;
        private readonly HotkeyHost _precisionHotkey;
        private readonly HotkeyHost _disperseSnapshotsHotkey;
        private FragmentRotationKeyboardHook _fragmentRotationHook;
        private readonly Dictionary<IntPtr, ActiveWindowSliceGroup> _activeTargets = new Dictionary<IntPtr, ActiveWindowSliceGroup>();
        private readonly List<SliceAnimation> _animations = new List<SliceAnimation>();
        private readonly System.Windows.Forms.Timer _fragmentSelectionTimer = new System.Windows.Forms.Timer();
        private bool _fragmentMouseButtonDown;
        private bool _fragmentMarqueeArmed;
        private bool _fragmentMarqueeActive;
        private Point _fragmentDragStart;
        private FragmentMarqueeForm _fragmentMarquee;
        private WindowSelectionForm _selection;
        private PrecisionSelectionForm _precisionSelection;
        private Queue<SliceRequest> _batchQueue;
        private List<string> _batchErrors;
        private int _activeAnimationCount;
        private bool _batchActive;
        private bool _pumpingBatch;
        private bool _collectBatchErrors;
        private bool _disposed;

        public TrayApplicationContext(Settings settings, string configPath, bool showSettings, string soundFolder)
        {
            _settings = settings;
            _configPath = configPath;
            _sounds = new SliceSoundPlayer(soundFolder);
            _icon = new NotifyIcon();
            _icon.Icon = SystemIcons.Application;
            _icon.Text = "Window Slice";
            _icon.Visible = true;
            _icon.DoubleClick += delegate { OpenSettings(); };
            ContextMenuStrip menu = new ContextMenuStrip();
            menu.Items.Add("Slice active window", null, delegate { SliceActiveWindow(); });
            menu.Items.Add("Settings…", null, delegate { OpenSettings(); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Exit", null, delegate { ExitThread(); });
            _icon.ContextMenuStrip = menu;
            _quickHotkey = new HotkeyHost(BeginQuickSliceAction);
            _selectionHotkey = new HotkeyHost(BeginSelectionAction);
            _precisionHotkey = new HotkeyHost(BeginPrecisionAction);
            _disperseSnapshotsHotkey = new HotkeyHost(DisperseWaitingSnapshots);
            _fragmentSelectionTimer.Interval = 15;
            _fragmentSelectionTimer.Tick += MonitorFragmentMarquee;
            _fragmentSelectionTimer.Start();
            List<string> hotkeyErrors = RegisterConfiguredHotkeys();
            UpdateIconText();
            if (hotkeyErrors.Count > 0)
                MessageBox.Show(String.Join("\r\n\r\n", hotkeyErrors.ToArray()) + "\r\n\r\nOpen Settings from the tray icon to choose different shortcuts.", "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Information);
            if (showSettings)
            {
                System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
                timer.Interval = 250;
                timer.Tick += delegate { timer.Stop(); timer.Dispose(); OpenSettings(); };
                timer.Start();
            }
        }

        private void OpenSettings()
        {
            using (SettingsForm form = new SettingsForm(_settings))
            {
                if (form.ShowDialog() != DialogResult.OK || form.Result == null) return;
                try { ConfigStore.Save(_configPath, form.Result); }
                catch (Exception ex)
                {
                    MessageBox.Show("The settings could not be saved, so the current settings are still active.\r\n\r\n" + ex.Message, "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }
                _settings = form.Result;
                List<string> hotkeyErrors = RegisterConfiguredHotkeys();
                UpdateIconText();
                if (hotkeyErrors.Count > 0)
                    MessageBox.Show(String.Join("\r\n\r\n", hotkeyErrors.ToArray()) + "\r\n\r\nThe settings were saved. Choose different shortcuts in Settings.", "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private List<string> RegisterConfiguredHotkeys()
        {
            List<string> errors = new List<string>();
            if (!_settings.RotateFragmentsWithArrowKeys && _fragmentRotationHook != null)
            {
                try
                {
                    _fragmentRotationHook.Dispose();
                    _fragmentRotationHook = null;
                }
                catch (Exception ex) { errors.Add("Fragment rotation: " + ex.Message); }
            }
            if (!_settings.RotateFragmentsWithArrowKeys)
                PersistentFragmentStore.SetRotationEnabled(false);
            _quickHotkey.Clear();
            _selectionHotkey.Clear();
            _precisionHotkey.Clear();
            _disperseSnapshotsHotkey.Clear();
            string error;
            if (!_quickHotkey.Set(_settings.QuickSliceHotkey, out error)) errors.Add("Quick Slice: " + error);
            if (!_selectionHotkey.Set(_settings.SelectionHotkey, out error)) errors.Add("Multi-Select: " + error);
            if (!_precisionHotkey.Set(_settings.PrecisionHotkey, out error)) errors.Add("Precision Slice: " + error);
            if (!_disperseSnapshotsHotkey.SetOptional(_settings.DisperseSnapshotsHotkey, out error)) errors.Add("Disperse snapshots: " + error);
            if (_settings.RotateFragmentsWithArrowKeys && _fragmentRotationHook == null)
            {
                try
                {
                    _fragmentRotationHook = new FragmentRotationKeyboardHook();
                    PersistentFragmentStore.SetRotationEnabled(true);
                }
                catch (Exception ex)
                {
                    errors.Add("Fragment rotation: " + ex.Message);
                }
            }
            else if (_settings.RotateFragmentsWithArrowKeys)
                PersistentFragmentStore.SetRotationEnabled(true);
            return errors;
        }

        private void DisperseWaitingSnapshots()
        {
            for (int i = 0; i < _animations.Count; i++)
                _animations[i].DisperseSnapshot();
        }

        private List<WindowTarget> GetWaitingSnapshotTargets()
        {
            List<WindowTarget> targets = new List<WindowTarget>();
            for (int i = 0; i < _animations.Count; i++)
            {
                SliceAnimation animation = _animations[i];
                if (animation == null) continue;
                WindowTarget target = WindowTarget.ForWaitingSnapshot(animation.WaitingSnapshot, animation);
                if (target != null) targets.Add(target);
            }
            return targets;
        }

        private WindowTarget WaitingSnapshotAt(Point point)
        {
            List<WindowTarget> targets = GetWaitingSnapshotTargets();
            for (int i = targets.Count - 1; i >= 0; i--)
                if (targets[i].Fragment.ContentContainsPoint(point)) return targets[i];
            return null;
        }

        private void UpdateIconText()
        {
            string text = "Window Slice | Quick " + _quickHotkey.ActiveText + " | Select " + _selectionHotkey.ActiveText + " | Precision " + _precisionHotkey.ActiveText;
            _icon.Text = text.Length > 63 ? text.Substring(0, 63) : text;
        }

        private void MonitorFragmentMarquee(object sender, EventArgs e)
        {
            if (_disposed) return;
            bool leftDown = (Native.GetAsyncKeyState(0x01) & 0x8000) != 0;
            Point cursor = System.Windows.Forms.Cursor.Position;
            PersistentFragmentStore.UpdateRotationHover(cursor);

            if (leftDown && !_fragmentMouseButtonDown)
            {
                _fragmentMouseButtonDown = true;
                _fragmentDragStart = cursor;
                _fragmentMarqueeActive = false;
                _fragmentMarqueeArmed = _settings.KeepFragments && PersistentFragmentStore.Count > 0 &&
                    _selection == null && _precisionSelection == null && !PersistentFragmentStore.ContainsPoint(cursor);
            }

            if (leftDown && _fragmentMarqueeArmed)
            {
                Rectangle area = WindowSelectionForm.NormalizeSelectionBounds(_fragmentDragStart, cursor);
                if (!_fragmentMarqueeActive && (area.Width >= 8 || area.Height >= 8) && PersistentFragmentStore.AnyIntersect(area))
                {
                    try
                    {
                        _fragmentMarquee = new FragmentMarqueeForm();
                        _fragmentMarquee.Begin(_fragmentDragStart, cursor);
                        _fragmentMarqueeActive = true;
                    }
                    catch
                    {
                        if (_fragmentMarquee != null) { _fragmentMarquee.Dispose(); _fragmentMarquee = null; }
                        _fragmentMarqueeArmed = false;
                    }
                }
                if (_fragmentMarqueeActive && _fragmentMarquee != null && !_fragmentMarquee.IsDisposed)
                    _fragmentMarquee.UpdateSelection(cursor);
            }

            if (!leftDown && _fragmentMouseButtonDown)
            {
                if (_fragmentMarqueeActive)
                {
                    Rectangle area = WindowSelectionForm.NormalizeSelectionBounds(_fragmentDragStart, cursor);
                    if (_fragmentMarquee != null)
                    {
                        _fragmentMarquee.Capture = false;
                        _fragmentMarquee.Close();
                        _fragmentMarquee.Dispose();
                        _fragmentMarquee = null;
                    }
                    PersistentFragmentStore.DeleteIntersecting(area);
                }
                _fragmentMouseButtonDown = false;
                _fragmentMarqueeArmed = false;
                _fragmentMarqueeActive = false;
            }
        }

        private void BeginQuickSliceAction()
        {
            if (_selection != null || _precisionSelection != null) return;
            SliceActiveWindow();
        }

        private void BeginSelectionAction()
        {
            if (_selection != null || _precisionSelection != null) return;
            BeginSelectionOverlay();
        }

        private void BeginPrecisionAction()
        {
            if (_selection != null || _precisionSelection != null) return;
            BeginPrecisionOverlay();
        }

        private void BeginSelectionOverlay()
        {
            try
            {
                _selection = new WindowSelectionForm(_settings.SelectionHotkey, FindSelectionTargets, delegate(bool cancelled, Rectangle area, List<WindowTarget> targets)
                {
                    _selection = null;
                    if (cancelled || area.IsEmpty) return;
                    BeginSelectionBatch(targets);
                });
                _selection.Begin();
            }
            catch (Exception ex)
            {
                if (_selection != null) { _selection.Dispose(); _selection = null; }
                ShowProblem("The multi-selection overlay could not start. No window was changed.\r\n\r\n" + ex.Message);
            }
        }

        private void BeginPrecisionOverlay()
        {
            try
            {
                _precisionSelection = new PrecisionSelectionForm(_settings.PrecisionHotkey, FindPrecisionTargets, FindPrecisionShapeTargets, _settings.SlashColor, _settings.OutlineColor, _settings.SlashThickness, _settings.UnlimitedPerformance, _settings.KeepWindowsOpenAfterSlicing, delegate(bool cancelled, List<PrecisionCutPlan> plans)
                {
                    _precisionSelection = null;
                    if (cancelled) return;
                    BeginPrecisionBatch(plans);
                });
                _precisionSelection.Begin();
            }
            catch (Exception ex)
            {
                if (_precisionSelection != null) { _precisionSelection.Dispose(); _precisionSelection = null; }
                ShowProblem("The Precision Slice overlay could not start. No window was changed.\r\n\r\n" + ex.Message);
            }
        }

        private void SliceActiveWindow()
        {
            WindowTarget waitingSnapshot = WaitingSnapshotAt(System.Windows.Forms.Cursor.Position);
            if (waitingSnapshot != null)
            {
                SliceTarget(waitingSnapshot, false);
                return;
            }
            if (_settings.FragmentsCanBeSliced)
            {
                SliceForm underCursor = PersistentFragmentStore.FragmentAt(System.Windows.Forms.Cursor.Position);
                if (underCursor != null)
                {
                    SliceTarget(WindowTarget.ForFragment(underCursor), false);
                    return;
                }
            }
            SliceTarget(WindowTarget.Read(Native.GetForegroundWindow()), true);
        }

        private List<WindowTarget> FindSelectionTargets(Rectangle area)
        {
            List<WindowTarget> targets = new List<WindowTarget>();
            if (!WindowSelectionForm.IsValidSelectionArea(area)) return targets;
            Rectangle virtualScreen = SystemInformation.VirtualScreen;
            Native.EnumWindows(delegate(IntPtr handle, IntPtr lParam)
            {
                try
                {
                    if (!Native.IsWindowVisible(handle) || Native.IsIconic(handle) || Native.IsCloaked(handle) || Native.IsDesktopOrTaskbar(handle)) return true;
                    WindowTarget candidate = WindowTarget.Read(handle);
if (candidate == null) return true;

try
{
    Process proc = Process.GetProcessById((int)candidate.ProcessId);

    if (String.Equals(
            proc.ProcessName,
            "CursorDriftTrail",
            StringComparison.OrdinalIgnoreCase))
    {
        return true;
    }
}
catch
{
}

                    Rectangle bounds;
                    if (!Native.TryGetFrameBounds(handle, out bounds)) return true;
                    bounds = Rectangle.Intersect(bounds, virtualScreen);
                    if (bounds.Width < 16 || bounds.Height < 16 || !WindowSelectionForm.IntersectsWindow(area, bounds)) return true;
                    targets.Add(candidate);
                }
                catch { }
                return true;
            }, IntPtr.Zero);
            if (_settings.FragmentsCanBeSliced)
            {
                List<SliceForm> fragments = PersistentFragmentStore.Snapshot();
                for (int i = 0; i < fragments.Count; i++)
                {
                    SliceForm fragment = fragments[i];
                    if (fragment == null || fragment.IsDisposed || !fragment.Visible || !fragment.ContentIntersects(area)) continue;
                    WindowTarget fragmentTarget = WindowTarget.ForFragment(fragment);
                    if (fragmentTarget != null) targets.Add(fragmentTarget);
                }
            }
            List<WindowTarget> waitingSnapshots = GetWaitingSnapshotTargets();
            for (int i = 0; i < waitingSnapshots.Count; i++)
                if (waitingSnapshots[i].Fragment.ContentIntersects(area)) targets.Add(waitingSnapshots[i]);
            return targets;
        }

        private List<PrecisionCutPlan> FindPrecisionTargets(Point start, Point end, bool wholeMonitor)
        {
            List<PrecisionCutPlan> plans = new List<PrecisionCutPlan>();
            Rectangle virtualScreen = SystemInformation.VirtualScreen;
            if (wholeMonitor)
            {
                WindowTarget monitor = ScreenCaptureTargetAt(start);
                if (monitor == null) return plans;
                PrecisionCutPlan monitorPlan = PrecisionSelectionForm.CreateMonitorLinePlan(monitor, start, end);
                if (monitorPlan != null) plans.Add(monitorPlan);
                return plans;
            }
            Native.EnumWindows(delegate(IntPtr handle, IntPtr lParam)
            {
                try
                {
                    if (!Native.IsWindowVisible(handle) || Native.IsIconic(handle) || Native.IsCloaked(handle) || Native.IsDesktopOrTaskbar(handle)) return true;
                    WindowTarget candidate = WindowTarget.Read(handle);
                    if (candidate == null) return true;
                    try
                    {
                        Process proc = Process.GetProcessById((int)candidate.ProcessId);
                        if (String.Equals(proc.ProcessName, "CursorDriftTrail", StringComparison.OrdinalIgnoreCase)) return true;
                    }
                    catch { }
                    Rectangle bounds;
                    if (!Native.TryGetFrameBounds(handle, out bounds)) return true;
                    bounds = Rectangle.Intersect(bounds, virtualScreen);
                    if (bounds.Width < 16 || bounds.Height < 16) return true;
                    SlashLine clipped;
                    if (!PrecisionSelectionForm.TryClipLineToRectangle(new PointF(start.X, start.Y), new PointF(end.X, end.Y), bounds, out clipped)) return true;
                    PrecisionCutPlan plan = new PrecisionCutPlan { Target = candidate, Bounds = bounds };
                    plan.ScreenLines.Add(clipped);
                    plans.Add(plan);
                }
                catch { }
                return true;
            }, IntPtr.Zero);
            if (_settings.FragmentsCanBeSliced)
            {
                List<SliceForm> fragments = PersistentFragmentStore.Snapshot();
                for (int i = 0; i < fragments.Count; i++)
                {
                    SliceForm fragment = fragments[i];
                    if (fragment == null || fragment.IsDisposed || !fragment.Visible) continue;
                    Rectangle fragmentBounds = fragment.Bounds;
                    SlashLine fragmentLine;
                    if (!PrecisionSelectionForm.TryClipLineToRectangle(new PointF(start.X, start.Y), new PointF(end.X, end.Y), fragmentBounds, out fragmentLine)) continue;
                    if (!fragment.ContentTouchesLine(fragmentLine.Start, fragmentLine.End)) continue;
                    WindowTarget fragmentTarget = WindowTarget.ForFragment(fragment);
                    if (fragmentTarget == null) continue;
                    PrecisionCutPlan fragmentPlan = new PrecisionCutPlan { Target = fragmentTarget, Bounds = fragmentBounds };
                    fragmentPlan.ScreenLines.Add(fragmentLine);
                    plans.Add(fragmentPlan);
                }
            }
            List<WindowTarget> waitingSnapshots = GetWaitingSnapshotTargets();
            for (int i = 0; i < waitingSnapshots.Count; i++)
            {
                SliceForm snapshot = waitingSnapshots[i].Fragment;
                SlashLine snapshotLine;
                if (!PrecisionSelectionForm.TryClipLineToRectangle(new PointF(start.X, start.Y), new PointF(end.X, end.Y), snapshot.Bounds, out snapshotLine)) continue;
                if (!snapshot.ContentTouchesLine(snapshotLine.Start, snapshotLine.End)) continue;
                PrecisionCutPlan snapshotPlan = new PrecisionCutPlan { Target = waitingSnapshots[i], Bounds = snapshot.Bounds };
                snapshotPlan.ScreenLines.Add(snapshotLine);
                plans.Add(snapshotPlan);
            }
            return plans;
        }

        private List<PrecisionCutPlan> FindPrecisionShapeTargets(PointF[] shape, bool wholeMonitor)
        {
            List<PrecisionCutPlan> plans = new List<PrecisionCutPlan>();
            if (shape == null || shape.Length < 3) return plans;
            if (wholeMonitor)
            {
                PointF center = PointF.Empty;
                for (int i = 0; i < shape.Length; i++)
                {
                    center.X += shape[i].X;
                    center.Y += shape[i].Y;
                }
                center.X /= shape.Length;
                center.Y /= shape.Length;
                WindowTarget monitor = ScreenCaptureTargetAt(Point.Round(center));
                PrecisionCutPlan monitorPlan = PrecisionSelectionForm.CreateMonitorCutPlan(monitor, shape);
                if (monitorPlan != null) plans.Add(monitorPlan);
                return plans;
            }
            Rectangle virtualScreen = SystemInformation.VirtualScreen;
            Native.EnumWindows(delegate(IntPtr handle, IntPtr lParam)
            {
                try
                {
                    if (!Native.IsWindowVisible(handle) || Native.IsIconic(handle) || Native.IsCloaked(handle) || Native.IsDesktopOrTaskbar(handle)) return true;
                    WindowTarget candidate = WindowTarget.Read(handle);
                    if (candidate == null) return true;
                    try
                    {
                        Process proc = Process.GetProcessById((int)candidate.ProcessId);
                        if (String.Equals(proc.ProcessName, "CursorDriftTrail", StringComparison.OrdinalIgnoreCase)) return true;
                    }
                    catch { }
                    Rectangle bounds;
                    if (!Native.TryGetFrameBounds(handle, out bounds)) return true;
                    bounds = Rectangle.Intersect(bounds, virtualScreen);
                    if (bounds.Width < 16 || bounds.Height < 16) return true;
                    List<PointF> clipped = SliceAnimation.ClipPolygonToRectangle(shape, bounds);
                    if (clipped.Count < 3 || SliceAnimation.PolygonArea(clipped) < 4.0) return true;
                    PrecisionCutPlan plan = new PrecisionCutPlan { Target = candidate, Bounds = bounds };
                    plan.ScreenShapes.Add(clipped.ToArray());
                    plans.Add(plan);
                }
                catch { }
                return true;
            }, IntPtr.Zero);
            if (_settings.FragmentsCanBeSliced)
            {
                List<SliceForm> fragments = PersistentFragmentStore.Snapshot();
                for (int i = 0; i < fragments.Count; i++)
                {
                    SliceForm fragment = fragments[i];
                    if (fragment == null || fragment.IsDisposed || !fragment.Visible) continue;
                    Rectangle fragmentBounds = fragment.Bounds;
                    List<PointF> clipped = SliceAnimation.ClipPolygonToRectangle(shape, fragmentBounds);
                    if (clipped.Count < 3 || SliceAnimation.PolygonArea(clipped) < 4.0) continue;
                    WindowTarget fragmentTarget = WindowTarget.ForFragment(fragment);
                    if (fragmentTarget == null) continue;
                    PrecisionCutPlan plan = new PrecisionCutPlan { Target = fragmentTarget, Bounds = fragmentBounds };
                    plan.ScreenShapes.Add(clipped.ToArray());
                    plans.Add(plan);
                }
            }
            List<WindowTarget> waitingSnapshots = GetWaitingSnapshotTargets();
            for (int i = 0; i < waitingSnapshots.Count; i++)
            {
                SliceForm snapshot = waitingSnapshots[i].Fragment;
                List<PointF> clipped = SliceAnimation.ClipPolygonToRectangle(shape, snapshot.Bounds);
                if (clipped.Count < 3 || SliceAnimation.PolygonArea(clipped) < 4.0) continue;
                PrecisionCutPlan plan = new PrecisionCutPlan { Target = waitingSnapshots[i], Bounds = snapshot.Bounds };
                plan.ScreenShapes.Add(clipped.ToArray());
                plans.Add(plan);
            }
            return plans;
        }

        private static WindowTarget ScreenCaptureTargetAt(Point point)
        {
            Rectangle bounds = SystemInformation.VirtualScreen;
            return bounds.Contains(point) ? WindowTarget.ForScreenCapture(bounds, 0) : null;
        }

        private void BeginSelectionBatch(List<WindowTarget> targets)
        {
            if (targets == null || targets.Count == 0)
            {
                ShowProblem("No eligible application windows intersected the selection area.");
                return;
            }
            const int maximumSelection = 64;
            if (!_settings.UnlimitedPerformance && targets.Count > maximumSelection)
            {
                targets = targets.GetRange(0, maximumSelection);
                ShowProblem("The selection included more than 64 windows, so only the first 64 will be processed.");
            }
            bool needsConfirmation = _settings.ConfirmBeforeClose && !_settings.KeepWindowsOpenAfterSlicing;
            if (needsConfirmation)
            {
                bool onlyUtilityNotices = true;
                for (int i = 0; i < targets.Count; i++) if (!targets[i].IsUtilityWarningDialog && targets[i].Fragment == null) { onlyUtilityNotices = false; break; }
                needsConfirmation = !onlyUtilityNotices;
            }
            if (needsConfirmation)
            {
                string prompt = "Slice " + targets.Count.ToString() + " selected window(s)? " +
                    (_settings.KeepWindowsOpenAfterSlicing
                        ? "Each source window stays open with its largest piece attached; detached pieces remain on screen. "
                        : _settings.ClickToDisperse
                        ? "Each window receives a normal close request as its slash fades; then left-click its stationary fragments to disperse them. "
                        : "Each will receive a normal close request as its split begins. ") +
                    "Save unsaved work first; apps may show their own prompts. The effects run four at a time.";
                if (MessageBox.Show(prompt, "Window Slice", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes) return;
            }
            if (_batchQueue == null) _batchQueue = new Queue<SliceRequest>();
            if (_batchErrors == null) _batchErrors = new List<string>();
            for (int i = 0; i < targets.Count; i++) _batchQueue.Enqueue(new SliceRequest(targets[i], null, null));
            _batchActive = true;
            PumpBatchQueue();
        }

        private static void DisposeScreenImages(IList<PrecisionCutPlan> plans)
        {
            if (plans == null) return;
            for (int i = 0; i < plans.Count; i++)
                if (plans[i] != null) DisposeScreenImage(plans[i].Target);
        }

        private static void DisposeScreenImage(WindowTarget target)
        {
            if (target == null || target.ScreenImage == null) return;
            target.ScreenImage.Dispose();
            target.ScreenImage = null;
        }

        private void BeginPrecisionBatch(List<PrecisionCutPlan> plans)
        {
            if (plans == null || plans.Count == 0)
            {
                ShowProblem("No eligible application windows intersected the drawn cuts or shapes.");
                return;
            }
            const int maximumSelection = 64;
            if (!_settings.UnlimitedPerformance && plans.Count > maximumSelection)
            {
                for (int i = maximumSelection; i < plans.Count; i++)
                    DisposeScreenImage(plans[i].Target);
                plans = plans.GetRange(0, maximumSelection);
                ShowProblem("The drawn cuts intersected more than 64 windows, so only the first 64 will be processed.");
            }
            if (_settings.KeepWindowsOpenAfterSlicing)
            {
                for (int i = 0; i < plans.Count; i++)
                {
                    if (!plans[i].Target.IsScreenCapture && plans[i].Target.Fragment == null && plans[i].ScreenShapes.Count > 1)
                    {
                        DisposeScreenImages(plans);
                        ShowProblem("Keep Windows Open supports at most one precision shape cutout per window. The selected windows were left unchanged.");
                        return;
                    }
                }
            }
            int totalLines = 0;
            int totalShapes = 0;
            for (int i = 0; i < plans.Count; i++) totalLines += plans[i].ScreenLines.Count;
            for (int i = 0; i < plans.Count; i++) totalShapes += plans[i].ScreenShapes.Count;
            bool needsConfirmation = _settings.ConfirmBeforeClose && !_settings.KeepWindowsOpenAfterSlicing;
            if (needsConfirmation)
            {
                bool onlyUtilityNotices = true;
                for (int i = 0; i < plans.Count; i++)
                    if (!plans[i].Target.IsScreenCapture && !plans[i].Target.IsUtilityWarningDialog && plans[i].Target.Fragment == null)
                    {
                        onlyUtilityNotices = false;
                        break;
                    }
                needsConfirmation = !onlyUtilityNotices;
            }
            if (needsConfirmation)
            {
                string prompt = "Precision Slice will apply " + totalLines.ToString() + " line cut(s) and " + totalShapes.ToString() + " shape cutout(s) across " + plans.Count.ToString() + " target(s). Monitor snapshots do not close the desktop. Shape cutouts leave the selected shape and the remainder as persistent fragments. " +
                    (_settings.KeepWindowsOpenAfterSlicing
                        ? "Source windows stay open with their largest piece attached; detached pieces remain on screen. "
                        : _settings.ClickToDisperse
                        ? "Each window receives a normal close request as its slash fades; then left-click its stationary fragments to disperse them. "
                        : "Each selected window will receive a normal close request as its split begins. ") +
                    "Save unsaved work first; apps may show their own prompts. Continue?";
                if (MessageBox.Show(prompt, "Precision Slice", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes)
                {
                    DisposeScreenImages(plans);
                    return;
                }
            }
            if (_batchQueue == null) _batchQueue = new Queue<SliceRequest>();
            if (_batchErrors == null) _batchErrors = new List<string>();
            for (int i = 0; i < plans.Count; i++)
            {
                List<SlashLine> screenLines = new List<SlashLine>(plans[i].ScreenLines);
                List<PointF[]> screenShapes = new List<PointF[]>(plans[i].ScreenShapes);
                _batchQueue.Enqueue(new SliceRequest(plans[i].Target, screenLines, screenShapes));
            }
            _batchActive = true;
            PumpBatchQueue();
        }

        private void PumpBatchQueue()
        {
            if (!_batchActive || _pumpingBatch) return;
            _pumpingBatch = true;
            try
            {
                while (_batchQueue != null && _batchQueue.Count > 0 &&
                    (_settings.UnlimitedPerformance || _activeAnimationCount < MaximumConcurrentAnimations))
                {
                    SliceRequest next = _batchQueue.Dequeue();
                    _collectBatchErrors = true;
                    try { SliceTarget(next.Target, false, next.ScreenLines, next.ScreenShapes); }
                    finally { _collectBatchErrors = false; }
                }
            }
            finally { _pumpingBatch = false; }
            CompleteBatchIfIdle();
        }

        private void CompleteBatchIfIdle()
        {
            if (!_batchActive || _pumpingBatch || (_batchQueue != null && _batchQueue.Count > 0) || _activeAnimationCount > 0) return;
            List<string> errors = _batchErrors;
            _batchQueue = null;
            _batchErrors = null;
            _batchActive = false;
            if (errors == null || errors.Count == 0) return;
            StringBuilder summary = new StringBuilder("Some selected windows could not be sliced:");
            int count = Math.Min(5, errors.Count);
            for (int i = 0; i < count; i++) summary.Append(Environment.NewLine).Append("• ").Append(errors[i]);
            if (errors.Count > count) summary.Append(Environment.NewLine).Append("• And ").Append((errors.Count - count).ToString()).Append(" more.");
            MessageBox.Show(summary.ToString(), "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void SliceTarget(WindowTarget target, bool askConfirmation)
        {
            SliceTarget(target, askConfirmation, null, null);
        }

        private void SliceTarget(WindowTarget target, bool askConfirmation, IList<SlashLine> screenLines)
        {
            SliceTarget(target, askConfirmation, screenLines, null);
        }

        private void SliceTarget(WindowTarget target, bool askConfirmation, IList<SlashLine> screenLines, IList<PointF[]> screenShapes)
        {
            try { SliceTargetCore(target, askConfirmation, screenLines, screenShapes); }
            finally
            {
                if (target != null && target.ScreenImage != null)
                {
                    target.ScreenImage.Dispose();
                    target.ScreenImage = null;
                }
            }
        }

        private void SliceTargetCore(WindowTarget target, bool askConfirmation, IList<SlashLine> screenLines, IList<PointF[]> screenShapes)
        {
            if (target == null)
            {
                ShowProblem("There is no eligible foreground window to slice.");
                return;
            }
            IntPtr handle = target.Handle;
            ActiveWindowSliceGroup targetGroup;
            if (_activeTargets.TryGetValue(target.Handle, out targetGroup) && targetGroup.ProcessId != target.ProcessId)
            {
                _activeTargets.Remove(target.Handle);
                targetGroup = null;
            }
            if (targetGroup != null && !_settings.AllowRepeatedSlices)
            {
                ShowProblem("That window is already being sliced. Enable repeated slicing in Settings to slice it again before the current effect ends.");
                return;
            }
            if (!_settings.UnlimitedPerformance && _activeAnimationCount >= MaximumConcurrentAnimations)
            {
                ShowProblem("Six slice animations are already running. Try again when one finishes.");
                return;
            }

            if (targetGroup == null)
            {
                targetGroup = new ActiveWindowSliceGroup(target.ProcessId);
                _activeTargets[target.Handle] = targetGroup;
            }
            targetGroup.ActiveCount++;
            _activeAnimationCount++;
            bool reservationReleased = false;
            Action releaseReservation = delegate
            {
                if (reservationReleased) return;
                reservationReleased = true;
                ReleaseTarget(target, targetGroup);
            };
            bool reservationTransferredToAnimation = false;
            try
            {
                if (!target.IsScreenCapture && (!Native.IsWindowVisible(handle) || Native.IsIconic(handle) || Native.IsCloaked(handle) || Native.IsDesktopOrTaskbar(handle)))
                {
                    ShowProblem("That window is minimized, hidden, or part of the Windows desktop. Bring a normal application window to the front and try again.");
                    return;
                }
                bool targetElevated = false;
                string accessFailure = null;
                if (!target.IsScreenCapture && !Native.IsElevatedProcess(target.ProcessId, out targetElevated, out accessFailure))
                {
                    ShowProblem(accessFailure + " Window Slice left it untouched.");
                    return;
                }
                if (!target.IsScreenCapture && targetElevated && !Native.IsCurrentProcessElevated())
                {
                    ShowProblem("That application is running as administrator. Windows does not allow this unelevated utility to close it, so nothing was changed.");
                    return;
                }

                if (askConfirmation && _settings.ConfirmBeforeClose && !_settings.KeepWindowsOpenAfterSlicing && !target.IsScreenCapture && !target.IsUtilityWarningDialog && target.Fragment == null)
                {
                    string confirmation = _settings.ClickToDisperse
                        ? "Slice “" + target.Title + "”? It will receive a normal close request as the slash fades. Then left-click its stationary fragments to disperse them. Save unsaved work first. The application may show its own save prompt."
                        : "Slice “" + target.Title + "”? After the animation, Window Slice will send a normal close request. Save unsaved work first. The application may show its own save prompt.";
                    DialogResult answer = MessageBox.Show(confirmation, "Window Slice", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2);
                    if (answer != DialogResult.Yes) return;
                    if (!target.IsStillSameWindow()) { ShowProblem("The original window changed or closed during confirmation. Nothing was animated."); return; }
                    Native.ShowWindow(target.Handle, Native.RestoreCommand);
                    Native.SetForegroundWindow(target.Handle);
                    Thread.Sleep(80);
                    if (Native.GetForegroundWindow() != target.Handle)
                    {
                        ShowProblem("Windows did not return focus to the selected window after confirmation. Nothing was animated.");
                        return;
                    }
                }

                Rectangle bounds;
                if (target.IsScreenCapture) bounds = target.ScreenBounds;
                else if (target.Fragment != null) bounds = target.Fragment.Bounds;
                else if (!Native.TryGetFrameBounds(target.Handle, out bounds)) { ShowProblem("Windows could not read that window's screen bounds."); return; }
                Rectangle virtualScreen = SystemInformation.VirtualScreen;
                bounds = Rectangle.Intersect(bounds, virtualScreen);
                if (bounds.Width < 16 || bounds.Height < 16) { ShowProblem("At least 16 pixels of the window must be visible in both directions to animate it safely."); return; }
                long pixelCount = (long)bounds.Width * (long)bounds.Height;
                if (!_settings.UnlimitedPerformance && pixelCount > 16000000L) { ShowProblem("That window is unusually large. The capture limit is 16 million pixels to protect memory."); return; }
                if (!target.IsStillSameWindow()) { ShowProblem("The selected window closed before it could be captured."); return; }

                Bitmap capture = null;
                SliceAnimation animation = null;
                try
                {
                    try
                    {
                        if (!target.IsScreenCapture && target.Fragment == null) SuspendAnimationsForCapture();
                        if (target.IsScreenCapture)
                        {
                            if (target.ScreenImage == null) throw new InvalidOperationException("The selected monitor snapshot was not captured.");
                            capture = target.ScreenImage;
                            target.ScreenImage = null;
                        }
                        else if (target.Fragment != null)
                        {
                            capture = target.SnapshotOwner == null
                                ? target.Fragment.CloneImage()
                                : target.SnapshotOwner.CloneWaitingBaseImage();
                            bounds = target.Fragment.Bounds;
                        }
                        else if (Native.IsLayeredWindow(handle))
                        {
try
{
    capture = LayeredWindowCapture.Capture(handle, bounds, ColorTranslator.FromHtml(_settings.SlashColor));
}
catch
{
    Thread.Sleep(20);
    capture = LayeredWindowCapture.Capture(handle, bounds, ColorTranslator.FromHtml(_settings.SlashColor));
}
                        }
                        else
                        {
                            capture = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
                            using (Graphics graphics = Graphics.FromImage(capture))
                                graphics.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size, CopyPixelOperation.SourceCopy);
                        }
                    }
                    finally { if (!target.IsScreenCapture) ResumeAnimationsAfterCapture(); }
                    if (!target.IsStillSameWindow()) { ShowProblem("The selected window changed during capture. It was left open."); return; }
                    List<SlashLine> localLines = null;
                    List<PointF[]> localShapes = null;
                    if (screenLines != null)
                    {
                        localLines = new List<SlashLine>();
                        for (int i = 0; i < screenLines.Count; i++)
                        {
                            SlashLine clipped;
                            if (!PrecisionSelectionForm.TryClipLineToRectangle(screenLines[i].Start, screenLines[i].End, bounds, out clipped)) continue;
                            localLines.Add(new SlashLine(
                                new PointF(clipped.Start.X - bounds.X, clipped.Start.Y - bounds.Y),
                                new PointF(clipped.End.X - bounds.X, clipped.End.Y - bounds.Y)));
                        }
                        if (screenLines.Count > 0 && localLines.Count == 0) { ShowProblem("The drawn cutting line no longer intersects the selected window. It was left open."); return; }
                    }
                    if (screenShapes != null && screenShapes.Count > 0)
                    {
                        localShapes = new List<PointF[]>();
                        for (int i = 0; i < screenShapes.Count; i++)
                        {
                            PointF[] localShape = new PointF[screenShapes[i].Length];
                            for (int j = 0; j < localShape.Length; j++)
                                localShape[j] = new PointF(screenShapes[i][j].X - bounds.X, screenShapes[i][j].Y - bounds.Y);
                            localShapes.Add(localShape);
                        }
                    }
                    if (target.SnapshotOwner != null)
                    {
                        if (localLines == null) localLines = SliceAnimation.BuildSlashLines(bounds.Size, _settings);
                        if (localShapes == null) localShapes = new List<PointF[]>();
                        target.SnapshotOwner.AppendPendingCuts(localLines, localShapes);
                    }
                    Action animationFinished = delegate
                    {
                        releaseReservation();
                        if (animation != null) _animations.Remove(animation);
                        if (_batchActive) PumpBatchQueue();
                    };
                    animation = localLines == null
                        ? new SliceAnimation(target, capture, bounds, _settings, _sounds, targetGroup, animationFinished)
                        : new SliceAnimation(target, capture, bounds, _settings, _sounds, targetGroup, localLines, localShapes, animationFinished);
                    _animations.Add(animation);
                    capture = null; 
                    animation.Start();
                    if (target.SnapshotOwner != null) target.SnapshotOwner.ConsumeWaitingSnapshot();
                    reservationTransferredToAnimation = true;
                }
                catch (Exception ex)
                {
                    if (animation != null) animation.Dispose();
                    ShowProblem("The window could not be captured or animated, so no close request was sent.\r\n\r\n" + ex.Message);
                }
                finally { if (capture != null) capture.Dispose(); }
            }
            finally
            {
                if (!reservationTransferredToAnimation) releaseReservation();
            }
        }

        private void ReleaseTarget(WindowTarget target, ActiveWindowSliceGroup group)
        {
            if (target == null || group == null) return;
            if (group.ActiveCount > 0) group.ActiveCount--;
            if (_activeAnimationCount > 0) _activeAnimationCount--;
            ActiveWindowSliceGroup current;
            if (group.ActiveCount == 0 && _activeTargets.TryGetValue(target.Handle, out current) && Object.ReferenceEquals(current, group))
                _activeTargets.Remove(target.Handle);
        }

        private void SuspendAnimationsForCapture()
        {
            for (int i = 0; i < _animations.Count; i++) _animations[i].HideForCapture();
            PersistentFragmentStore.HideForCapture();
        }

        private void ResumeAnimationsAfterCapture()
        {
            for (int i = 0; i < _animations.Count; i++) _animations[i].RestoreAfterCapture();
            PersistentFragmentStore.RestoreAfterCapture();
        }

        private void ShowProblem(string text)
        {
            if (_collectBatchErrors)
            {
                if (_batchErrors == null) _batchErrors = new List<string>();
                _batchErrors.Add(text);
                return;
            }
            MessageBox.Show(text, "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        protected override void ExitThreadCore()
        {
            if (_disposed) { base.ExitThreadCore(); return; }
            _disposed = true;
            if (_selection != null) { _selection.Cancel(); _selection = null; }
            if (_precisionSelection != null) { _precisionSelection.Cancel(); _precisionSelection = null; }
            _fragmentSelectionTimer.Stop();
            _fragmentSelectionTimer.Tick -= MonitorFragmentMarquee;
            _fragmentSelectionTimer.Dispose();
            if (_fragmentMarquee != null) { _fragmentMarquee.Capture = false; _fragmentMarquee.Close(); _fragmentMarquee.Dispose(); _fragmentMarquee = null; }
            _quickHotkey.Dispose();
            _selectionHotkey.Dispose();
            _precisionHotkey.Dispose();
            _disperseSnapshotsHotkey.Dispose();
            if (_fragmentRotationHook != null)
            {
                try { _fragmentRotationHook.Dispose(); }
                catch (Exception ex) { MessageBox.Show("Fragment rotation could not be disabled cleanly.\r\n\r\n" + ex.Message, "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
                _fragmentRotationHook = null;
            }
            PersistentFragmentStore.DisposeAll();
            _icon.Visible = false;
            _icon.Dispose();
            base.ExitThreadCore();
        }
    }

    internal static class ConfigStore
    {
        public static Settings Load(string path)
        {
            Settings settings = new Settings();
            if (File.Exists(path))
            {
                try
                {
                    JavaScriptSerializer serializer = new JavaScriptSerializer();
                    Settings loaded = serializer.Deserialize<Settings>(File.ReadAllText(path, Encoding.UTF8));
                    if (loaded != null) settings = loaded;
                }
                catch {  }
            }
            settings.Normalize();
            return settings;
        }

        public static void Save(string path, Settings settings)
        {
            string directory = Path.GetDirectoryName(path);
            Directory.CreateDirectory(directory);
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            File.WriteAllText(path, serializer.Serialize(settings), new UTF8Encoding(false));
        }
    }

    public static class Program
    {
        public static int Run(string scriptPath, bool configure, bool selfTest)
        {
            if (selfTest) return RunSelfTests(scriptPath);
            try
            {
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Native.SetProcessDPIAware();
                string sid = System.Security.Principal.WindowsIdentity.GetCurrent().User.Value;
                bool created;
                using (Mutex mutex = new Mutex(true, "Local\\WindowSlice-" + sid, out created))
                {
                    if (!created)
                    {
                        MessageBox.Show("Window Slice is already running. Open Settings or Exit from its notification-area icon.", "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Information);
                        return 0;
                    }
                    string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WindowSlice");
                    string path = Path.Combine(root, "settings.json");
                    bool firstRun = !File.Exists(path);
                    Settings settings = ConfigStore.Load(path);
                    Application.ThreadException += delegate(object sender, System.Threading.ThreadExceptionEventArgs e)
                    {
                        MessageBox.Show("Window Slice encountered an error and kept the target window open.\r\n\r\n" + e.Exception.Message, "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    };
                    string soundFolder = Path.GetDirectoryName(Path.GetFullPath(scriptPath));
                    Application.Run(new TrayApplicationContext(settings, path, configure || firstRun, soundFolder));
                }
                return 0;
            }
            catch (Exception ex)
            {
                string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WindowSlice");
                try { Directory.CreateDirectory(root); File.WriteAllText(Path.Combine(root, "startup-error.log"), ex.ToString()); } catch { }
                MessageBox.Show("Window Slice could not start. Details were saved in your LocalAppData\\WindowSlice folder.\r\n\r\n" + ex.Message, "Window Slice", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        private static int RunSelfTests(string scriptPath)
        {
            int failures = 0;
            HotkeySpec a;
            HotkeySpec b;
            HotkeySpec c;
            HotkeySpec d;
            HotkeySpec e;
            HotkeySpec f;
            HotkeySpec g;
            HotkeySpec h;
            Check("parses Ctrl+Alt+Q", HotkeySpec.TryParse("Ctrl+Alt+Q", out a), ref failures);
            Check("parses the default active-window shortcut", HotkeySpec.TryParse("Ctrl+Alt+Q", out f), ref failures);
            Check("parses Shift+F11", HotkeySpec.TryParse("Shift+F11", out b), ref failures);
            Check("parses an unmodified F8 shortcut", HotkeySpec.TryParse("F8", out g) && g.Modifiers == 0 && g.Key == Keys.F8, ref failures);
            Check("parses unmodified F1 and F24 shortcuts", HotkeySpec.TryParse("F1", out h) && h.Modifiers == 0 && h.Key == Keys.F1 && HotkeySpec.TryParse("F24", out h) && h.Modifiers == 0 && h.Key == Keys.F24, ref failures);
            Check("rejects Windows-reserved F12", !HotkeySpec.TryParse("F12", out h) && !HotkeySpec.TryParse("Shift+F12", out h), ref failures);
            Check("rejects a bare letter shortcut", !HotkeySpec.TryParse("Q", out c), ref failures);
            Check("rejects Windows-key shortcuts", !HotkeySpec.TryParse("Win+Q", out d), ref failures);
            Check("rejects duplicate keys", !HotkeySpec.TryParse("Ctrl+Q+W", out e), ref failures);
            Rectangle selectionBounds = WindowSelectionForm.NormalizeSelectionBounds(new Point(100, 100), new Point(20, 40));
            Check("normalizes a reverse-direction drag selection", selectionBounds == new Rectangle(20, 40, 80, 60), ref failures);
            Check("selection includes intersecting windows and excludes outside or tiny areas", WindowSelectionForm.IntersectsWindow(selectionBounds, new Rectangle(0, 50, 30, 30)) && !WindowSelectionForm.IntersectsWindow(selectionBounds, new Rectangle(101, 40, 20, 20)) && !WindowSelectionForm.IntersectsWindow(new Rectangle(0, 0, 11, 20), new Rectangle(0, 0, 100, 100)), ref failures);
            SlashLine clippedLine;
            bool clipForward = PrecisionSelectionForm.TryClipLineToRectangle(new PointF(-10, 40), new PointF(110, 40), new Rectangle(0, 0, 100, 80), out clippedLine);
            Check("clips a precise stroke to the window while preserving its direction", clipForward && Math.Abs(clippedLine.Start.X) < 0.01 && Math.Abs(clippedLine.End.X - 100) < 0.01 && Math.Abs(clippedLine.Start.Y - 40) < 0.01 && Math.Abs(clippedLine.End.Y - 40) < 0.01, ref failures);
            bool clipReverse = PrecisionSelectionForm.TryClipLineToRectangle(new PointF(110, 20), new PointF(-10, 60), new Rectangle(0, 0, 100, 80), out clippedLine);
            Check("preserves reverse-direction strokes through a window", clipReverse && clippedLine.Start.X > clippedLine.End.X && clippedLine.Start.Y < clippedLine.End.Y, ref failures);
            bool selectionOverlay = false;
            try
            {
                using (WindowSelectionForm form = new WindowSelectionForm("F8", delegate(Rectangle area) { return new List<WindowTarget>(); }, delegate(bool cancelled, Rectangle area, List<WindowTarget> targets) { }))
                    selectionOverlay = form.Bounds == SystemInformation.VirtualScreen && form.TopMost && !form.ShowInTaskbar && form.Opacity > 0.0 && form.Opacity < 1.0;
            }
            catch { selectionOverlay = false; }
            Check("creates a dimmed topmost selection overlay across the virtual screen", selectionOverlay, ref failures);
            PointF slashStart;
            PointF slashEnd;
            SlashForm.GetSlashPoints(new Size(100, 80), true, 1.0, out slashStart, out slashEnd);
            Check("vertical slash spans the full top-to-bottom edge", slashStart.X == slashEnd.X && slashStart.Y == 0.0f && slashEnd.Y == 80.0f, ref failures);
            SlashForm.GetSlashPoints(new Size(100, 80), false, 1.0, out slashStart, out slashEnd);
            Check("horizontal slash spans the full left-to-right edge", slashStart.Y == slashEnd.Y && slashStart.X == 0.0f && slashEnd.X == 100.0f, ref failures);
            Size geometrySize = new Size(100, 80);
            PointF[] rectangleCutout = PrecisionSelectionForm.BuildShape(PrecisionShapeMode.Rectangle, new Point(20, 30), new Point(60, 50));
            PointF[] triangleCutout = PrecisionSelectionForm.BuildShape(PrecisionShapeMode.Triangle, new Point(20, 30), new Point(60, 50));
            PointF[] circleCutout = PrecisionSelectionForm.BuildShape(PrecisionShapeMode.Circle, new Point(20, 30), new Point(60, 50));
            PointF[] freehandCutout = new PointF[] { new PointF(10, 10), new PointF(30, 10), new PointF(25, 30), new PointF(15, 25) };
            Check("cycles from line through rectangle, triangle, circle, and freehand modes", PrecisionSelectionForm.NextShapeMode(PrecisionShapeMode.Line) == PrecisionShapeMode.Rectangle && PrecisionSelectionForm.NextShapeMode(PrecisionShapeMode.Rectangle) == PrecisionShapeMode.Triangle && PrecisionSelectionForm.NextShapeMode(PrecisionShapeMode.Triangle) == PrecisionShapeMode.Circle && PrecisionSelectionForm.NextShapeMode(PrecisionShapeMode.Circle) == PrecisionShapeMode.Freehand && PrecisionSelectionForm.NextShapeMode(PrecisionShapeMode.Freehand) == PrecisionShapeMode.Line, ref failures);
            Check("counts shape strokes separately from live-window line cuts", PrecisionSelectionForm.CountShapeStrokes(new PrecisionStroke[] { new PrecisionStroke { Mode = PrecisionShapeMode.Line }, new PrecisionStroke { Mode = PrecisionShapeMode.Circle } }) == 1, ref failures);
            Check("builds rectangle, triangle, and smooth circle cutout shapes", rectangleCutout.Length == 4 && Math.Abs(SliceAnimation.PolygonArea(rectangleCutout) - 800.0) < 0.01 && triangleCutout.Length == 3 && Math.Abs(SliceAnimation.PolygonArea(triangleCutout) - 400.0) < 0.01 && circleCutout.Length == 48 && SliceAnimation.PolygonArea(circleCutout) > 310.0 && SliceAnimation.PolygonArea(circleCutout) < 315.0, ref failures);
            Check("accepts a closed freehand outline and rejects degenerate outlines", PrecisionSelectionForm.IsValidFreehandShape(freehandCutout) && Math.Abs(PrecisionSelectionForm.PolygonArea(freehandCutout) - 262.5) < 0.01 && !PrecisionSelectionForm.IsValidFreehandShape(new PointF[] { new PointF(1, 1), new PointF(2, 2) }), ref failures);
            PrecisionCutPlan freehandScreenPlan = PrecisionSelectionForm.CreateWholeScreenPlan(
                new List<PrecisionStroke> { new PrecisionStroke { Mode = PrecisionShapeMode.Freehand, Points = { new PointF(10, 10), new PointF(30, 10), new PointF(25, 30), new PointF(15, 25) } } },
                new Rectangle(0, 0, 50, 50));
            Check("applies freehand outlines as polygon cutouts on a screen snapshot", freehandScreenPlan != null && freehandScreenPlan.ScreenShapes.Count == 1 && Math.Abs(SliceAnimation.PolygonArea(freehandScreenPlan.ScreenShapes[0]) - 262.5) < 0.01, ref failures);
            List<PointF> clippedShape = SliceAnimation.ClipPolygonToRectangle(new PointF[] { new PointF(-5, -5), new PointF(15, -5), new PointF(15, 15), new PointF(-5, 15) }, new Rectangle(0, 0, 10, 10));
            Check("clips shape cutouts to the target window bounds", clippedShape.Count == 4 && Math.Abs(SliceAnimation.PolygonArea(clippedShape) - 100.0) < 0.01, ref failures);
            WindowTarget monitorTarget = WindowTarget.ForScreenCapture(new Rectangle(100, 50, 100, 100), 0);
            Check("restricts live-window mode to real source windows", SliceAnimation.ShouldKeepSourceWindowOpen(true, new WindowTarget { Handle = new IntPtr(1) }) && !SliceAnimation.ShouldKeepSourceWindowOpen(true, monitorTarget) && !SliceAnimation.ShouldKeepSourceWindowOpen(false, new WindowTarget { Handle = new IntPtr(1) }), ref failures);
            PrecisionCutPlan monitorLinePlan = PrecisionSelectionForm.CreateMonitorLinePlan(monitorTarget, new Point(50, 100), new Point(250, 100));
            PrecisionCutPlan monitorShapePlan = PrecisionSelectionForm.CreateMonitorCutPlan(monitorTarget, new PointF[] { new PointF(80, 80), new PointF(220, 80), new PointF(220, 180), new PointF(80, 180) });
            PrecisionCutPlan screenFallbackPlan = PrecisionSelectionForm.CreateWholeScreenPlan(
                new List<PrecisionStroke> { new PrecisionStroke { Mode = PrecisionShapeMode.Line, Start = new Point(-100, 100), End = new Point(300, 100) } },
                new Rectangle(0, 0, 200, 150));
            Check("latches monitor mode if Alt is pressed at any point during a drag", PrecisionSelectionForm.IsWholeMonitorMode(false, true) && PrecisionSelectionForm.IsWholeMonitorMode(true, false) && !PrecisionSelectionForm.IsWholeMonitorMode(false, false), ref failures);
            Check("routes monitor cuts to the selected display bounds without requiring a window handle", monitorTarget.IsScreenCapture && monitorTarget.IsStillSameWindow() && monitorLinePlan != null && monitorLinePlan.Bounds == monitorTarget.ScreenBounds && monitorLinePlan.ScreenLines.Count == 1 && Math.Abs(monitorLinePlan.ScreenLines[0].Start.X - 100.0f) < 0.01f && Math.Abs(monitorLinePlan.ScreenLines[0].End.X - 200.0f) < 0.01f && monitorShapePlan != null && Math.Abs(SliceAnimation.PolygonArea(monitorShapePlan.ScreenShapes[0]) - 7000.0) < 0.01, ref failures);
            Check("falls back to a full-screen snapshot when a precision stroke hits no eligible window", screenFallbackPlan != null && screenFallbackPlan.Target.IsScreenCapture && screenFallbackPlan.Bounds == new Rectangle(0, 0, 200, 150) && screenFallbackPlan.ScreenLines.Count == 1 && Math.Abs(screenFallbackPlan.ScreenLines[0].Start.X) < 0.01f && Math.Abs(screenFallbackPlan.ScreenLines[0].End.X - 200.0f) < 0.01f, ref failures);
            bool screenCapturePixelsOpaque = false;
            using (Bitmap capturePixel = new Bitmap(1, 1, PixelFormat.Format32bppArgb))
            {
                capturePixel.SetPixel(0, 0, Color.FromArgb(0, 20, 40, 60));
                Native.MakeBitmapOpaque(capturePixel);
                screenCapturePixelsOpaque = capturePixel.GetPixel(0, 0).A == 255 &&
                    (Native.ScreenCaptureBltOperation & 0x40000000U) != 0 &&
                    (Native.ScreenCaptureBltOperation & 0x00CC0020U) == 0x00CC0020U;
            }
            Check("captures layered desktop pixels and makes the screen snapshot fully opaque", screenCapturePixelsOpaque, ref failures);
            Check("projects fragment rotations and identifies the desaturated back side", Math.Abs(SliceForm.NormalizeAngle(-12.0) - 348.0) < 0.001 && SliceForm.RotationDeterminant(0.0, 0.0) > 0.99 && SliceForm.RotationDeterminant(0.0, 180.0) < -0.99 && Math.Abs(SliceForm.RotationDeterminant(90.0, 0.0)) < 0.001, ref failures);
            bool backImageRetainsMutedColor = false;
            using (Bitmap frontPixel = new Bitmap(1, 1, PixelFormat.Format32bppArgb))
            using (Bitmap backPixel = new Bitmap(1, 1, PixelFormat.Format32bppArgb))
            using (Graphics graphics = Graphics.FromImage(backPixel))
            using (ImageAttributes attributes = new ImageAttributes())
            {
                frontPixel.SetPixel(0, 0, Color.FromArgb(255, 240, 64, 32));
                attributes.SetColorMatrix(SliceForm.CreateBackColorMatrix());
                graphics.DrawImage(frontPixel, new Rectangle(0, 0, 1, 1), 0, 0, 1, 1, GraphicsUnit.Pixel, attributes);
                Color original = frontPixel.GetPixel(0, 0);
                Color back = backPixel.GetPixel(0, 0);
                backImageRetainsMutedColor = back.A == original.A &&
                    back.R > back.G && back.G > back.B &&
                    back.R - back.B < original.R - original.B;

                frontPixel.SetPixel(0, 0, Color.White);
                graphics.DrawImage(frontPixel, new Rectangle(0, 0, 1, 1), 0, 0, 1, 1, GraphicsUnit.Pixel, attributes);
                Color whiteBack = backPixel.GetPixel(0, 0);
                backImageRetainsMutedColor = backImageRetainsMutedColor &&
                    whiteBack.R >= 150 && whiteBack.R <= 180 &&
                    Math.Abs(whiteBack.R - whiteBack.G) <= 1 &&
                    Math.Abs(whiteBack.G - whiteBack.B) <= 1;
            }
            Check("renders fragment backs with muted color and turns white into gray", backImageRetainsMutedColor, ref failures);
            bool liveFragmentPixelsRefresh = false;
            using (Bitmap fragmentPixels = new Bitmap(2, 1, PixelFormat.Format32bppArgb))
            using (Bitmap currentPixels = new Bitmap(2, 1, PixelFormat.Format32bppArgb))
            {
                fragmentPixels.SetPixel(0, 0, Color.FromArgb(128, 10, 20, 30));
                fragmentPixels.SetPixel(1, 0, Color.Transparent);
                currentPixels.SetPixel(0, 0, Color.FromArgb(255, 200, 100, 50));
                currentPixels.SetPixel(1, 0, Color.FromArgb(255, 1, 2, 3));
                bool copied = SliceForm.CopyLivePixels(fragmentPixels, currentPixels, Point.Empty);
                Color updated = fragmentPixels.GetPixel(0, 0);
                Color transparent = fragmentPixels.GetPixel(1, 0);
                liveFragmentPixelsRefresh = copied && updated.A == 128 && updated.R == 200 && updated.G == 100 && updated.B == 50 && transparent.A == 0;
            }
            Check("refreshes detached fragment pixels without changing their shape mask", liveFragmentPixelsRefresh, ref failures);
            bool liveFragmentSkipsTransparentCapture = false;
            using (Bitmap fragmentPixels = new Bitmap(2, 1, PixelFormat.Format32bppArgb))
            using (Bitmap transparentPixels = new Bitmap(2, 1, PixelFormat.Format32bppArgb))
            {
                fragmentPixels.SetPixel(0, 0, Color.FromArgb(255, 40, 80, 120));
                bool copied = SliceForm.CopyLivePixels(fragmentPixels, transparentPixels, Point.Empty);
                Color retained = fragmentPixels.GetPixel(0, 0);
                liveFragmentSkipsTransparentCapture = !copied &&
                    retained.A == 255 && retained.R == 40 && retained.G == 80 && retained.B == 120;
            }
            Check("keeps the previous fragment image when a capture frame is transparent", liveFragmentSkipsTransparentCapture, ref failures);
            bool shapeMasksPartitionContent = false;
            using (Bitmap shapeSource = new Bitmap(20, 20, PixelFormat.Format32bppArgb))
            using (Graphics shapeGraphics = Graphics.FromImage(shapeSource))
            {
                shapeGraphics.Clear(Color.FromArgb(255, 40, 100, 180));
                PointF[] wholeWindow = new PointF[] { new PointF(0, 0), new PointF(20, 0), new PointF(20, 20), new PointF(0, 20) };
                PointF[] selectedRegion = new PointF[] { new PointF(5, 5), new PointF(15, 5), new PointF(15, 15), new PointF(5, 15) };
            PointF[] secondSelectedRegion = new PointF[] { new PointF(1, 1), new PointF(6, 1), new PointF(6, 6), new PointF(1, 6) };
            List<PointF[]> cutoutShapes = new List<PointF[]> { selectedRegion, secondSelectedRegion };
            bool selectedHasContent;
            bool secondSelectedHasContent;
            bool remainderHasContent;
            using (Bitmap selectedPiece = SliceAnimation.CreatePieceBitmap(shapeSource, new Rectangle(0, 0, 20, 20), wholeWindow, new List<SlashLine>(), cutoutShapes, 0, Color.Black, Color.Red, 3.0f, out selectedHasContent))
            using (Bitmap secondSelectedPiece = SliceAnimation.CreatePieceBitmap(shapeSource, new Rectangle(0, 0, 20, 20), wholeWindow, new List<SlashLine>(), cutoutShapes, 1, Color.Black, Color.Red, 3.0f, out secondSelectedHasContent))
            using (Bitmap remainderPiece = SliceAnimation.CreatePieceBitmap(shapeSource, new Rectangle(0, 0, 20, 20), wholeWindow, new List<SlashLine>(), cutoutShapes, -1, Color.Black, Color.Red, 3.0f, out remainderHasContent))
                shapeMasksPartitionContent = selectedHasContent && secondSelectedHasContent && remainderHasContent &&
                    selectedPiece.GetPixel(10, 10).A > 240 && selectedPiece.GetPixel(3, 3).A < 10 &&
                    secondSelectedPiece.GetPixel(3, 3).A > 240 && secondSelectedPiece.GetPixel(10, 10).A < 10 &&
                    remainderPiece.GetPixel(10, 10).A < 10 && remainderPiece.GetPixel(3, 3).A < 10 &&
                    remainderPiece.GetPixel(18, 18).A > 240;
            }
            Check("creates independent shape fragments and a separate remainder mask", shapeMasksPartitionContent, ref failures);
            bool waitingPreviewPreservesBase = false;
            using (Bitmap cleanSnapshot = new Bitmap(20, 20, PixelFormat.Format32bppArgb))
            using (Bitmap waitingSnapshot = SliceAnimation.CreateWaitingPreview(cleanSnapshot))
            {
                waitingPreviewPreservesBase = cleanSnapshot.GetPixel(10, 10).ToArgb() == waitingSnapshot.GetPixel(10, 10).ToArgb() &&
                    cleanSnapshot.GetPixel(2, 2).ToArgb() == waitingSnapshot.GetPixel(2, 2).ToArgb();
            }
            Check("keeps pending slash marks completely invisible in the waiting snapshot", waitingPreviewPreservesBase, ref failures);
            Settings diagonalSettings = new Settings { Direction = "Diagonal" };
            List<SlashLine> diagonalLines = SliceAnimation.BuildSlashLines(geometrySize, diagonalSettings);
            List<List<PointF>> diagonalPieces = SliceAnimation.BuildPolygons(geometrySize, diagonalLines);
            double diagonalArea = 0.0;
            for (int i = 0; i < diagonalPieces.Count; i++) diagonalArea += SliceAnimation.PolygonArea(diagonalPieces[i]);
            Check("diagonal slash creates two pieces and preserves the window area", diagonalLines.Count == 1 && diagonalPieces.Count == 2 && Math.Abs(diagonalArea - 8000.0) < 0.01, ref failures);
            Check("keeps the largest polygon attached to the live source window", SliceAnimation.LargestPolygonIndex(diagonalPieces) == 0 && Math.Abs(SliceAnimation.PolygonArea(diagonalPieces[0]) - SliceAnimation.PolygonArea(diagonalPieces[1])) < 0.01, ref failures);
            bool liveWindowRestoresItsOriginalRegion = false;
            IntPtr capturedOriginalRegion = IntPtr.Zero;
            IntPtr capturedRestoredRegion = IntPtr.Zero;
            try
            {
                using (Form sourceWindow = new Form())
                {
                    sourceWindow.Bounds = new Rectangle(80, 90, 100, 80);
                    IntPtr handle = sourceWindow.Handle;
                    Native.ApplyWindowPolygon(handle,
                        new PointF[] { new PointF(0, 0), new PointF(100, 0), new PointF(80, 80), new PointF(20, 80) },
                        Point.Empty, sourceWindow.Size, IntPtr.Zero, false);
                    bool hadOriginal;
                    capturedOriginalRegion = Native.CaptureWindowRegion(handle, out hadOriginal);
                    WindowTarget target = new WindowTarget { Handle = handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = "live-window self-test" };
                    LiveWindowSliceSession session = new LiveWindowSliceSession(target, sourceWindow.Bounds);
                    session.ApplyRemainingPolygon(new PointF[] { new PointF(0, 0), new PointF(50, 0), new PointF(50, 80), new PointF(0, 80) });
                    session.Restore();
                    bool hadRestored;
                    capturedRestoredRegion = Native.CaptureWindowRegion(handle, out hadRestored);
                    liveWindowRestoresItsOriginalRegion = hadOriginal && hadRestored &&
                        Native.RegionsEqual(capturedOriginalRegion, capturedRestoredRegion);
                }
            }
            catch { liveWindowRestoresItsOriginalRegion = false; }
            finally
            {
                Native.DeleteGdiObject(capturedOriginalRegion);
                Native.DeleteGdiObject(capturedRestoredRegion);
            }
            Check("restores a live-sliced window's pre-existing shape", liveWindowRestoresItsOriginalRegion, ref failures);
            bool liveWindowRemovesTemporaryRegion = false;
            try
            {
                using (Form sourceWindow = new Form())
                {
                    sourceWindow.Bounds = new Rectangle(80, 90, 100, 80);
                    IntPtr handle = sourceWindow.Handle;
                    WindowTarget target = new WindowTarget { Handle = handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = "live-window self-test" };
                    LiveWindowSliceSession session = new LiveWindowSliceSession(target, sourceWindow.Bounds);
                    session.ApplyRemainingPolygon(new PointF[] { new PointF(0, 0), new PointF(50, 0), new PointF(50, 80), new PointF(0, 80) });
                    session.Restore();
                    bool hasRestoredRegion;
                    IntPtr restoredRegion = Native.CaptureWindowRegion(handle, out hasRestoredRegion);
                    Native.DeleteGdiObject(restoredRegion);
                    liveWindowRemovesTemporaryRegion = !hasRestoredRegion;
                }
            }
            catch { liveWindowRemovesTemporaryRegion = false; }
            Check("removes its temporary region when restoring a normally rectangular window", liveWindowRemovesTemporaryRegion, ref failures);
            bool liveWindowCommitKeepsOnlyRemainingRegion = false;
            try
            {
                using (Form sourceWindow = new Form())
                {
                    sourceWindow.Bounds = new Rectangle(80, 90, 100, 80);
                    sourceWindow.Show();
                    Application.DoEvents();
                    WindowTarget target = new WindowTarget { Handle = sourceWindow.Handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = "live-window commit self-test" };
                    LiveWindowSliceSession session = new LiveWindowSliceSession(target, sourceWindow.Bounds);
                    session.ApplyRemainingPolygon(new PointF[] { new PointF(0, 0), new PointF(50, 0), new PointF(50, 80), new PointF(0, 80) });
                    session.CommitRemainingWindow();
                    bool hasCommittedRegion;
                    IntPtr committedRegion = Native.CaptureWindowRegion(sourceWindow.Handle, out hasCommittedRegion);
                    try
                    {
                        liveWindowCommitKeepsOnlyRemainingRegion = hasCommittedRegion &&
                            Native.RegionContainsPoint(committedRegion, new Point(25, 40)) &&
                            !Native.RegionContainsPoint(committedRegion, new Point(75, 40));
                    }
                    finally { Native.DeleteGdiObject(committedRegion); }
                }
            }
            catch { liveWindowCommitKeepsOnlyRemainingRegion = false; }
            Check("keeps the live-window cut when fragments are not retained", liveWindowCommitKeepsOnlyRemainingRegion, ref failures);
            bool liveWindowKeepsUncutPopupCloseButton = false;
            try
            {
                using (Form popup = new Form())
                {
                    popup.FormBorderStyle = FormBorderStyle.SizableToolWindow;
                    popup.Text = "live-window popup frame self-test";
                    popup.Bounds = new Rectangle(80, 90, 260, 180);
                    popup.Show();
                    Application.DoEvents();
                    Rectangle popupBounds;
                    Native.RECT nativeBounds;
                    if (Native.TryGetFrameBounds(popup.Handle, out popupBounds) &&
                        Native.GetWindowRect(popup.Handle, out nativeBounds))
                    {
                        WindowTarget target = new WindowTarget { Handle = popup.Handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = popup.Text };
                        LiveWindowSliceSession session = new LiveWindowSliceSession(target, popupBounds);
                        session.ApplyRemainingPolygon(new PointF[]
                        {
                            new PointF(0, 0),
                            new PointF(popupBounds.Width, 0),
                            new PointF(popupBounds.Width, 48),
                            new PointF(0, 48)
                        });
                        int hit = Native.HitTestWindow(popup.Handle, new Point(nativeBounds.Right - 14, nativeBounds.Top + 12));
                        liveWindowKeepsUncutPopupCloseButton = hit == 20;
                        session.Restore();
                    }
                }
            }
            catch { liveWindowKeepsUncutPopupCloseButton = false; }
            Check("keeps an uncut popup close button hit-testable", liveWindowKeepsUncutPopupCloseButton, ref failures);
            bool liveWindowExcludesPrecisionShapeAndRestoresRegion = false;
            IntPtr capturedCutoutRegion = IntPtr.Zero;
            try
            {
                using (Form sourceWindow = new Form())
                {
                    sourceWindow.FormBorderStyle = FormBorderStyle.None;
                    sourceWindow.Bounds = new Rectangle(80, 90, 100, 80);
                    IntPtr handle = sourceWindow.Handle;
                    WindowTarget target = new WindowTarget { Handle = handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = "live-window shape self-test" };
                    LiveWindowSliceSession session = new LiveWindowSliceSession(target, sourceWindow.Bounds);
                    try
                    {
                        session.ApplyRemainingPolygon(
                            new PointF[] { new PointF(0, 0), new PointF(100, 0), new PointF(100, 80), new PointF(0, 80) },
                            new PointF[] { new PointF(25, 20), new PointF(75, 20), new PointF(75, 60), new PointF(25, 60) });
                        bool hadCutoutRegion;
                        capturedCutoutRegion = Native.CaptureWindowRegion(handle, out hadCutoutRegion);
                        bool keepsRemainder = Native.RegionContainsPoint(capturedCutoutRegion, new Point(10, 10)) &&
                            Native.RegionContainsPoint(capturedCutoutRegion, new Point(90, 70));
                        bool excludesDetachedShape = !Native.RegionContainsPoint(capturedCutoutRegion, new Point(50, 40));
                        session.Restore();
                        bool hadRestoredRegion;
                        IntPtr restoredRegion = Native.CaptureWindowRegion(handle, out hadRestoredRegion);
                        Native.DeleteGdiObject(restoredRegion);
                        liveWindowExcludesPrecisionShapeAndRestoresRegion = hadCutoutRegion && keepsRemainder &&
                            excludesDetachedShape && !hadRestoredRegion;
                    }
                    finally
                    {
                        session.Restore();
                    }
                }
            }
            catch { liveWindowExcludesPrecisionShapeAndRestoresRegion = false; }
            finally { Native.DeleteGdiObject(capturedCutoutRegion); }
            Check("cuts one precision shape out of a live window and restores its original region", liveWindowExcludesPrecisionShapeAndRestoresRegion, ref failures);
            bool liveFragmentMapsClicksToSource = false;
            try
            {
                using (Form sourceWindow = new Form())
                {
                    sourceWindow.Bounds = new Rectangle(80, 90, 100, 80);
                    IntPtr handle = sourceWindow.Handle;
                    WindowTarget target = new WindowTarget { Handle = handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = "live-window click self-test" };
                    LiveWindowSliceSession session = new LiveWindowSliceSession(target, sourceWindow.Bounds);
                    using (SliceForm piece = new SliceForm(
                        new Bitmap(20, 20, PixelFormat.Format32bppArgb),
                        new Rectangle(100, 110, 20, 20),
                        new PointF[] { new PointF(0, 0), new PointF(20, 0), new PointF(20, 20), new PointF(0, 20) }))
                    {
                        session.Attach(piece, new Rectangle(100, 110, 20, 20), false);
                        liveFragmentMapsClicksToSource = piece.MapToOriginalScreen(new Point(105, 115)) == new Point(105, 115);
                        session.Restore();
                    }
                }
            }
            catch { liveFragmentMapsClicksToSource = false; }
            Check("maps detached live-fragment clicks back to their original source location", liveFragmentMapsClicksToSource, ref failures);
            bool liveFragmentClicksOkButton = false;
            Point savedCursorPosition = System.Windows.Forms.Cursor.Position;
            try
            {
                using (Form sourceWindow = new Form())
                {
                    sourceWindow.FormBorderStyle = FormBorderStyle.None;
                    sourceWindow.Bounds = new Rectangle(80, 90, 220, 140);
                    Button okButton = new Button { Text = "OK", Bounds = new Rectangle(80, 80, 80, 30) };
                    sourceWindow.Controls.Add(okButton);
                    sourceWindow.Show();
                    Application.DoEvents();
                    int clickCount = 0;
                    okButton.Click += delegate { clickCount++; };
                    WindowTarget target = new WindowTarget { Handle = sourceWindow.Handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = "live-window button self-test" };
                    LiveWindowSliceSession session = new LiveWindowSliceSession(target, sourceWindow.Bounds);
                    using (SliceForm piece = new SliceForm(
                        new Bitmap(sourceWindow.Bounds.Width, sourceWindow.Bounds.Height, PixelFormat.Format32bppArgb),
                        sourceWindow.Bounds,
                        new PointF[] { new PointF(0, 0), new PointF(sourceWindow.Width, 0), new PointF(sourceWindow.Width, sourceWindow.Height), new PointF(0, sourceWindow.Height) }))
                    {
                        session.Attach(piece, sourceWindow.Bounds, true);
                        Point buttonCenter = okButton.PointToScreen(new Point(okButton.Width / 2, okButton.Height / 2));
                        System.Windows.Forms.Cursor.Position = buttonCenter;
                        MouseEventArgs click = new MouseEventArgs(MouseButtons.Left, 1, 0, 0, 0);
                        bool downForwarded = session.ForwardMouse(piece, click, 0x0201, 0);
                        bool upForwarded = session.ForwardMouse(piece, click, 0x0202, 0);
                        liveFragmentClicksOkButton = downForwarded && upForwarded && clickCount == 1;
                        session.Restore();
                    }
                }
            }
            catch { liveFragmentClicksOkButton = false; }
            finally { System.Windows.Forms.Cursor.Position = savedCursorPosition; }
            Check("forwards a live-fragment click to a standard OK button", liveFragmentClicksOkButton, ref failures);
            bool liveFragmentClicksPopupButton = false;
            savedCursorPosition = System.Windows.Forms.Cursor.Position;
            try
            {
                using (Form sourceWindow = new Form())
                using (Form popup = new Form())
                {
                    sourceWindow.FormBorderStyle = FormBorderStyle.None;
                    sourceWindow.Bounds = new Rectangle(80, 90, 220, 140);
                    popup.FormBorderStyle = FormBorderStyle.None;
                    popup.StartPosition = FormStartPosition.Manual;
                    popup.Bounds = new Rectangle(80, 90, 220, 140);
                    Button okButton = new Button { Text = "OK", Bounds = new Rectangle(80, 80, 80, 30) };
                    popup.Controls.Add(okButton);
                    sourceWindow.Show();
                    popup.Show(sourceWindow);
                    Application.DoEvents();
                    int clickCount = 0;
                    okButton.Click += delegate { clickCount++; };
                    sourceWindow.Activate();
                    Application.DoEvents();
                    WindowTarget target = new WindowTarget { Handle = sourceWindow.Handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = "live-window popup button self-test" };
                    LiveWindowSliceSession session = new LiveWindowSliceSession(target, sourceWindow.Bounds);
                    using (SliceForm piece = new SliceForm(
                        new Bitmap(sourceWindow.Bounds.Width, sourceWindow.Bounds.Height, PixelFormat.Format32bppArgb),
                        sourceWindow.Bounds,
                        new PointF[] { new PointF(0, 0), new PointF(sourceWindow.Width, 0), new PointF(sourceWindow.Width, sourceWindow.Height), new PointF(0, sourceWindow.Height) }))
                    {
                        session.Attach(piece, sourceWindow.Bounds, true);
                        Point buttonCenter = okButton.PointToScreen(new Point(okButton.Width / 2, okButton.Height / 2));
                        System.Windows.Forms.Cursor.Position = buttonCenter;
                        MouseEventArgs click = new MouseEventArgs(MouseButtons.Left, 1, 0, 0, 0);
                        bool downForwarded = session.ForwardMouse(piece, click, 0x0201, 0);
                        bool upForwarded = session.ForwardMouse(piece, click, 0x0202, 0);
                        liveFragmentClicksPopupButton = downForwarded && upForwarded && clickCount == 1;
                        session.Restore();
                    }
                }
            }
            catch { liveFragmentClicksPopupButton = false; }
            finally { System.Windows.Forms.Cursor.Position = savedCursorPosition; }
            Check("forwards a live-fragment click to an inactive popup button", liveFragmentClicksPopupButton, ref failures);
            bool liveRefreshCaptureExcludesOverlappingWindows = false;
            bool liveRefreshCaptureUpdatesFromSource = false;
            bool liveCaptureHonorsSourceRegion = false;
            try
            {
                using (Form sourceWindow = new Form())
                using (Form overlayWindow = new Form())
                {
                    sourceWindow.FormBorderStyle = FormBorderStyle.None;
                    sourceWindow.BackColor = Color.Red;
                    sourceWindow.Bounds = new Rectangle(80, 90, 100, 80);
                    overlayWindow.FormBorderStyle = FormBorderStyle.None;
                    overlayWindow.BackColor = Color.Blue;
                    overlayWindow.Bounds = sourceWindow.Bounds;
                    sourceWindow.Show();
                    overlayWindow.Show();
                    overlayWindow.TopMost = true;
                    Application.DoEvents();
                    Native.ApplyWindowPolygon(
                        sourceWindow.Handle,
                        new PointF[] { new PointF(50, 0), new PointF(100, 0), new PointF(100, 80), new PointF(50, 80) },
                        Point.Empty,
                        sourceWindow.Size,
                        IntPtr.Zero,
                        false);
                    using (WindowSlice.LiveCapture.LiveWindowCapture liveCapture = WindowSlice.LiveCapture.LiveWindowCapture.Create(sourceWindow.Handle, true))
                    {
                        using (Bitmap clippedCapture = liveCapture.Capture())
                            liveCaptureHonorsSourceRegion = clippedCapture.GetPixel(20, 20).ToArgb() != Color.Red.ToArgb();
                        liveCapture.DiscardPendingFrames();
                        Native.RestoreWindowRegion(sourceWindow.Handle, IntPtr.Zero);
                        Native.DwmFlush();
                        for (int attempt = 0; attempt < 4 && !liveRefreshCaptureExcludesOverlappingWindows; attempt++)
                        {
                            Thread.Sleep(80);
                            using (Bitmap capture = liveCapture.Capture())
                                liveRefreshCaptureExcludesOverlappingWindows = capture.GetPixel(20, 20).ToArgb() == Color.Red.ToArgb();
                        }
                        sourceWindow.BackColor = Color.Lime;
                        Application.DoEvents();
                        for (int attempt = 0; attempt < 4 && !liveRefreshCaptureUpdatesFromSource; attempt++)
                        {
                            Thread.Sleep(80);
                            using (Bitmap capture = liveCapture.Capture())
                                liveRefreshCaptureUpdatesFromSource = capture.GetPixel(20, 20).ToArgb() == Color.Lime.ToArgb();
                        }
                    }
                }
            }
            catch
            {
                liveRefreshCaptureExcludesOverlappingWindows = false;
                liveRefreshCaptureUpdatesFromSource = false;
                liveCaptureHonorsSourceRegion = false;
            }
            Check("Windows Graphics Capture respects the source window's current region", liveCaptureHonorsSourceRegion, ref failures);
            Check("captures live refresh pixels from the source without overlapping window pixels", liveRefreshCaptureExcludesOverlappingWindows, ref failures);
            Check("updates live refresh pixels when the source window changes", liveRefreshCaptureUpdatesFromSource, ref failures);
            bool liveFragmentsDisappearWhenSourceCloses = false;
            try
            {
                using (Form sourceWindow = new Form())
                {
                    sourceWindow.Bounds = new Rectangle(80, 90, 100, 80);
                    WindowTarget target = new WindowTarget { Handle = sourceWindow.Handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = "live-window close self-test" };
                    LiveWindowSliceSession session = new LiveWindowSliceSession(target, sourceWindow.Bounds);
                    using (SliceForm piece = new SliceForm(
                        new Bitmap(20, 20, PixelFormat.Format32bppArgb),
                        new Rectangle(100, 110, 20, 20),
                        new PointF[] { new PointF(0, 0), new PointF(20, 0), new PointF(20, 20), new PointF(0, 20) }))
                    {
                        piece.MakePersistent();
                        session.Attach(piece, new Rectangle(100, 110, 20, 20), true);
                        sourceWindow.Close();
                        session.MonitorTargetWindow();
                        liveFragmentsDisappearWhenSourceCloses =
                            !PersistentFragmentStore.Contains(piece) && !piece.IsLiveDetachedPiece;
                    }
                }
            }
            catch { liveFragmentsDisappearWhenSourceCloses = false; }
            Check("removes live fragments when the source window closes", liveFragmentsDisappearWhenSourceCloses, ref failures);
            bool liveFragmentsDisappearWhenOKClosesSource = false;
            try
            {
                using (Form ownerWindow = new Form())
                using (Form sourceWindow = new Form())
                using (SliceForm piece = new SliceForm(
                    new Bitmap(20, 20, PixelFormat.Format32bppArgb),
                    new Rectangle(100, 110, 20, 20),
                    new PointF[] { new PointF(0, 0), new PointF(20, 0), new PointF(20, 20), new PointF(0, 20) }))
                {
                    ownerWindow.Bounds = new Rectangle(80, 90, 300, 180);
                    sourceWindow.Bounds = new Rectangle(80, 90, 100, 80);
                    Button okButton = new Button { Text = "OK", Bounds = new Rectangle(10, 10, 60, 25) };
                    sourceWindow.Controls.Add(okButton);
                    okButton.Click += delegate { sourceWindow.Close(); };
                    ownerWindow.Show();
                    sourceWindow.Show(ownerWindow);
                    Application.DoEvents();
                    WindowTarget target = new WindowTarget { Handle = sourceWindow.Handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = "live-window OK close self-test" };
                    LiveWindowSliceSession session = new LiveWindowSliceSession(target, sourceWindow.Bounds);
                    piece.MakePersistent();
                    session.Attach(piece, new Rectangle(100, 110, 20, 20), true);
                    Point buttonCenter = okButton.PointToScreen(new Point(okButton.Width / 2, okButton.Height / 2));
                    Point popupTestSavedCursor = System.Windows.Forms.Cursor.Position;
                    System.Windows.Forms.Cursor.Position = buttonCenter;
                    MouseEventArgs click = new MouseEventArgs(MouseButtons.Left, 1, 0, 0, 0);
                    bool downForwarded = session.ForwardMouse(piece, click, 0x0201, 0);
                    bool upForwarded = session.ForwardMouse(piece, click, 0x0202, 0);
                    session.MonitorTargetWindow();
                    liveFragmentsDisappearWhenOKClosesSource = downForwarded && upForwarded &&
                        !sourceWindow.IsHandleCreated && !PersistentFragmentStore.Contains(piece) && !piece.IsLiveDetachedPiece;
                    System.Windows.Forms.Cursor.Position = popupTestSavedCursor;
                }
            }
            catch { liveFragmentsDisappearWhenOKClosesSource = false; }
            Check("removes live fragments when an OK button closes their source window", liveFragmentsDisappearWhenOKClosesSource, ref failures);
            bool closedWindowZOrderRestoreIsIgnored = false;
            try
            {
                Native.RestoreWindowZOrder(new IntPtr(123456), IntPtr.Zero, false);
                closedWindowZOrderRestoreIsIgnored = true;
            }
            catch { closedWindowZOrderRestoreIsIgnored = false; }
            Check("ignores z-order restoration after the source window has closed", closedWindowZOrderRestoreIsIgnored, ref failures);
            bool liveFragmentMoveModeToggles = false;
            try
            {
                using (Form sourceWindow = new Form())
                {
                    sourceWindow.Bounds = new Rectangle(80, 90, 100, 80);
                    WindowTarget target = new WindowTarget { Handle = sourceWindow.Handle, ProcessId = (uint)Process.GetCurrentProcess().Id, Title = "live-window move-mode self-test" };
                    LiveWindowSliceSession session = new LiveWindowSliceSession(target, sourceWindow.Bounds);
                    using (SliceForm piece = new SliceForm(
                        new Bitmap(20, 20, PixelFormat.Format32bppArgb),
                        new Rectangle(100, 110, 20, 20),
                        new PointF[] { new PointF(0, 0), new PointF(20, 0), new PointF(20, 20), new PointF(0, 20) }))
                    {
                        piece.MakePersistent();
                        session.Attach(piece, new Rectangle(100, 110, 20, 20), true);
                        ToolStripMenuItem moveModeItem = piece.ContextMenuStrip.Items[4] as ToolStripMenuItem;
                        bool startsInLiveMode = moveModeItem != null && moveModeItem.Text == "Toggle Move Mode" && !piece.IsLiveMoveMode;
                        if (moveModeItem != null) moveModeItem.PerformClick();
                        bool entersMoveMode = moveModeItem != null && moveModeItem.Text == "Toggle Live Mode" && piece.IsLiveMoveMode;
                        if (moveModeItem != null) moveModeItem.PerformClick();
                        liveFragmentMoveModeToggles = startsInLiveMode && entersMoveMode &&
                            moveModeItem != null && moveModeItem.Text == "Toggle Move Mode" && !piece.IsLiveMoveMode;
                        session.Restore();
                    }
                }
            }
            catch { liveFragmentMoveModeToggles = false; }
            Check("toggles live fragments between input forwarding and move mode", liveFragmentMoveModeToggles, ref failures);
            List<SlashLine> preciseLines = new List<SlashLine> { new SlashLine(new PointF(25, 0), new PointF(75, 80)), new SlashLine(new PointF(80, 0), new PointF(20, 80)) };
            List<List<PointF>> precisePieces = SliceAnimation.BuildPolygons(geometrySize, preciseLines);
            double preciseArea = 0.0;
            for (int i = 0; i < precisePieces.Count; i++) preciseArea += SliceAnimation.PolygonArea(precisePieces[i]);
            Check("multiple precise angled cuts split polygons and preserve the full window area", precisePieces.Count >= 3 && Math.Abs(preciseArea - 8000.0) < 0.01, ref failures);
            Settings radialSettings = new Settings { Direction = "MultiSlash", MultiSlashCount = 4, MultiPattern = "Radial" };
            List<SlashLine> radialLines = SliceAnimation.BuildSlashLines(geometrySize, radialSettings);
            List<List<PointF>> radialPieces = SliceAnimation.BuildPolygons(geometrySize, radialLines);
            double radialArea = 0.0;
            for (int i = 0; i < radialPieces.Count; i++) radialArea += SliceAnimation.PolygonArea(radialPieces[i]);
            Check("four radial slashes create eight pieces and preserve the window area", radialLines.Count == 4 && radialPieces.Count == 8 && Math.Abs(radialArea - 8000.0) < 0.01, ref failures);
            Settings randomSettings = new Settings { Direction = "MultiSlash", MultiSlashCount = 5, MultiPattern = "Random" };
            List<SlashLine> randomLines = SliceAnimation.BuildSlashLines(geometrySize, randomSettings);
            List<List<PointF>> randomPieces = SliceAnimation.BuildPolygons(geometrySize, randomLines);
            double randomArea = 0.0;
            for (int i = 0; i < randomPieces.Count; i++) randomArea += SliceAnimation.PolygonArea(randomPieces[i]);
            Check("random multi-slashes create extra pieces and preserve the window area", randomLines.Count == 5 && randomPieces.Count >= 6 && Math.Abs(randomArea - 8000.0) < 0.01, ref failures);
            Settings maximumSettings = new Settings { Direction = "MultiSlash", MultiSlashCount = 10, MultiPattern = "Random" };
            List<SlashLine> maximumLines = SliceAnimation.BuildSlashLines(geometrySize, maximumSettings);
            List<List<PointF>> maximumPieces = SliceAnimation.BuildPolygons(geometrySize, maximumLines);
            double maximumArea = 0.0;
            for (int i = 0; i < maximumPieces.Count; i++) maximumArea += SliceAnimation.PolygonArea(maximumPieces[i]);
            Check("maximum random slash count stays within the piece cap", maximumLines.Count == 10 && maximumPieces.Count >= 11 && maximumPieces.Count <= 56 && Math.Abs(maximumArea - 8000.0) < 0.01, ref failures);
            Settings performanceSettings = new Settings { Direction = "MultiSlash", MultiSlashCount = 140, MultiPattern = "Radial", DurationMs = 7000, DistancePx = 0, SlashThickness = 99, UnlimitedPerformance = true };
            performanceSettings.Normalize();
            List<SlashLine> performanceLines = SliceAnimation.BuildSlashLines(geometrySize, performanceSettings);
            List<List<PointF>> performancePieces = SliceAnimation.BuildPolygons(geometrySize, performanceLines, true);
            Check("performance mode removes slash, duration, and thickness limits", performanceSettings.MultiSlashCount == 140 && performanceSettings.DurationMs == 7000 && performanceSettings.DistancePx == 0 && performanceSettings.SlashThickness == 99 && performanceLines.Count == 140 && performancePieces.Count > 256, ref failures);
            Settings unboundedSettings = new Settings { Direction = "MultiSlash", MultiSlashCount = 0, MultiPattern = "Random", DurationMs = 0, DistancePx = -7, SlashThickness = -3, UnlimitedPerformance = true };
            unboundedSettings.Normalize();
            Check("performance mode preserves zero and negative slicing settings", unboundedSettings.MultiSlashCount == 0 && unboundedSettings.DurationMs == 0 && unboundedSettings.DistancePx == -7 && unboundedSettings.SlashThickness == -3 && unboundedSettings.MultiPattern == "Random", ref failures);
            bool unboundedSettingsUi = false;
            try
            {
                using (SettingsForm form = new SettingsForm(unboundedSettings))
                {
                    TabControl pages = null;
                    foreach (Control child in form.Controls)
                        if (child is TabControl) pages = child as TabControl;
                    TableLayoutPanel cuts = pages == null || pages.TabPages.Count < 2 || pages.TabPages[1].Controls.Count == 0 ? null : pages.TabPages[1].Controls[0] as TableLayoutPanel;
                    TableLayoutPanel animation = pages == null || pages.TabPages.Count < 3 || pages.TabPages[2].Controls.Count == 0 ? null : pages.TabPages[2].Controls[0] as TableLayoutPanel;
                    NumericUpDown count = cuts == null ? null : cuts.GetControlFromPosition(1, 1) as NumericUpDown;
                    NumericUpDown duration = animation == null ? null : animation.GetControlFromPosition(1, 0) as NumericUpDown;
                    NumericUpDown distance = animation == null ? null : animation.GetControlFromPosition(1, 1) as NumericUpDown;
                    NumericUpDown thickness = animation == null ? null : animation.GetControlFromPosition(1, 4) as NumericUpDown;
                    unboundedSettingsUi = count != null && count.Minimum == Int32.MinValue && count.Maximum == Int32.MaxValue && count.Value == 0 &&
                        duration != null && duration.Minimum == Int32.MinValue && duration.Maximum == Int32.MaxValue && duration.Value == 0 &&
                        distance != null && distance.Minimum == Int32.MinValue && distance.Maximum == Int32.MaxValue && distance.Value == -7 &&
                        thickness != null && thickness.Minimum == Int32.MinValue && thickness.Maximum == Int32.MaxValue && thickness.Value == -3;
                }
            }
            catch { unboundedSettingsUi = false; }
            Check("unlimited settings controls accept signed values across their full integer range", unboundedSettingsUi, ref failures);
            Settings zeroDistanceSettings = new Settings { DistancePx = 0 };
            zeroDistanceSettings.Normalize();
            Check("allows zero travel distance without performance mode", zeroDistanceSettings.DistancePx == 0, ref failures);
            Check("waits for a click inside the target until the slash has faded", !SliceAnimation.ShouldBeginDispersal(true, false, true) && !SliceAnimation.ShouldBeginDispersal(true, true, false) && SliceAnimation.ShouldBeginDispersal(true, true, true) && SliceAnimation.ShouldBeginDispersal(false, false, false), ref failures);
            Check("fades the slash overlay after drawing its complete path", SliceAnimation.SlashOverlayOpacity(100, 210, 240) == 1.0 && Math.Abs(SliceAnimation.SlashOverlayOpacity(330, 210, 240) - 0.5) < 0.001 && SliceAnimation.SlashOverlayOpacity(450, 210, 240) == 0.0, ref failures);
            Rectangle first;
            Rectangle second;
            Rectangle oddWidth = new Rectangle(10, 20, 101, 80);
            SliceAnimation.CalculateHalves(oddWidth, true, out first, out second);
            Check("vertical split preserves odd-width edge pixels", first.X == 10 && first.Width == 50 && second.X == 60 && second.Width == 51 && first.Width + second.Width == oddWidth.Width, ref failures);
            Rectangle oddHeight = new Rectangle(10, 20, 100, 81);
            SliceAnimation.CalculateHalves(oddHeight, false, out first, out second);
            Check("horizontal split preserves odd-height edge pixels", first.Y == 20 && first.Height == 40 && second.Y == 60 && second.Height == 41 && first.Height + second.Height == oddHeight.Height, ref failures);
            Check("halves fade smoothly to transparent", SliceAnimation.FadeOpacity(0.0) == 1.0 && SliceAnimation.FadeOpacity(0.5) == 0.5 && SliceAnimation.FadeOpacity(1.0) == 0.0, ref failures);
            Check("does not send the normal close request twice", SliceAnimation.ShouldSendCloseRequest(true, false) && !SliceAnimation.ShouldSendCloseRequest(true, true) && !SliceAnimation.ShouldSendCloseRequest(false, false), ref failures);
            Check("retains fragments only after a completed animation has displayed its pieces", SliceAnimation.ShouldRetainFragments(true, true, true) && !SliceAnimation.ShouldRetainFragments(true, false, true) && !SliceAnimation.ShouldRetainFragments(true, true, false) && !SliceAnimation.ShouldRetainFragments(false, true, true), ref failures);
            Check("commits the sliced live window when fragments are disabled", SliceAnimation.ShouldCommitLiveWindow(true, false, true, true) && !SliceAnimation.ShouldCommitLiveWindow(true, true, true, true) && !SliceAnimation.ShouldCommitLiveWindow(true, false, false, true) && !SliceAnimation.ShouldCommitLiveWindow(false, false, true, true), ref failures);
            Check("honors Keep Fragments off for live windows, including cutouts and click-to-disperse", !SliceAnimation.ShouldKeepFragmentsForSlice(true, false, false, true, false) && !SliceAnimation.ShouldKeepFragmentsForSlice(true, false, false, false, true) && SliceAnimation.ShouldKeepFragmentsForSlice(true, true, false, false, false), ref failures);
            Check("shape cutouts and click-to-disperse retain fragments when Keep Fragments is off", SliceAnimation.ShouldKeepFragments(false, false, true, false) && SliceAnimation.ShouldKeepFragments(true, false, false, false) && SliceAnimation.ShouldKeepFragments(false, false, false, true) && !SliceAnimation.ShouldKeepFragments(false, false, false, false), ref failures);
            ActiveWindowSliceGroup closeGroup = new ActiveWindowSliceGroup(123);
            bool firstCloseClaim = closeGroup.TryClaimCloseRequest();
            bool duplicateCloseClaim = closeGroup.TryClaimCloseRequest();
            closeGroup.ReleaseCloseRequestClaim();
            bool retryCloseClaim = closeGroup.TryClaimCloseRequest();
            Check("overlapping slices coordinate a single close request", firstCloseClaim && !duplicateCloseClaim && retryCloseClaim, ref failures);
            bool styleRendered = false;
            using (Bitmap styleImage = new Bitmap(100, 80, PixelFormat.Format32bppArgb))
            using (Graphics styleGraphics = Graphics.FromImage(styleImage))
            {
                Color slashColor = Color.FromArgb(17, 34, 51);
                Color outlineColor = Color.FromArgb(221, 238, 255);
                styleGraphics.Clear(Color.Transparent);
                SlashForm.DrawSlash(styleGraphics, styleImage.Size, new Rectangle(0, 0, 100, 80), true, 1.0, 255, slashColor, outlineColor, 12.0f);
                Color corePixel = styleImage.GetPixel(50, 40);
                Color outlinePixel = styleImage.GetPixel(45, 40);
                styleRendered = corePixel.R == slashColor.R && corePixel.G == slashColor.G && corePixel.B == slashColor.B && outlinePixel.R == outlineColor.R && outlinePixel.G == outlineColor.G && outlinePixel.B == outlineColor.B;
                int nearGlowAlpha = styleImage.GetPixel(56, 40).A;
                int farGlowAlpha = styleImage.GetPixel(61, 40).A;
                styleRendered = styleRendered && nearGlowAlpha > farGlowAlpha && farGlowAlpha > 0;
            }
            Check("draws selected colors with a soft fading outline glow", styleRendered, ref failures);
            bool layeredAlphaReconstruction = false;
            Color captureSlashColor = Color.FromArgb(8, 8, 11);
            Color secondMatteColor = LayeredWindowCapture.CreateCaptureMatteColor(captureSlashColor);
            using (Bitmap originalScreen = new Bitmap(3, 1, PixelFormat.Format32bppArgb))
            using (Bitmap blackMatte = new Bitmap(3, 1, PixelFormat.Format32bppArgb))
            using (Bitmap secondMatte = new Bitmap(3, 1, PixelFormat.Format32bppArgb))
            {
                double captureOpacity = 0.1;
                Color[] sourcePixels = new Color[] { Color.FromArgb(40, 100, 180), Color.FromArgb(15, 25, 35), Color.FromArgb(220, 90, 30) };
                Color[] backdropPixels = new Color[] { Color.FromArgb(10, 30, 60), Color.FromArgb(190, 125, 55), Color.FromArgb(20, 140, 230) };
                double[] sourceAlphas = new double[] { 1.0, 0.0, 0.5 };
                for (int x = 0; x < sourcePixels.Length; x++)
                {
                    Color sourcePixel = sourcePixels[x];
                    Color backdropPixel = backdropPixels[x];
                    double alpha = sourceAlphas[x];
                    Color originalPixel = Color.FromArgb(
                        CompositeCaptureChannel(sourcePixel.R, backdropPixel.R, alpha),
                        CompositeCaptureChannel(sourcePixel.G, backdropPixel.G, alpha),
                        CompositeCaptureChannel(sourcePixel.B, backdropPixel.B, alpha));
                    originalScreen.SetPixel(x, 0, originalPixel);
                    blackMatte.SetPixel(x, 0, CompositeCapturePixel(originalPixel, sourcePixel, Color.Black, alpha, captureOpacity));
                    secondMatte.SetPixel(x, 0, CompositeCapturePixel(originalPixel, sourcePixel, secondMatteColor, alpha, captureOpacity));
                }
                using (Bitmap reconstructed = LayeredWindowCapture.RebuildAlpha(blackMatte, secondMatte, originalScreen, captureOpacity, secondMatteColor))
                {
                    Color opaque = reconstructed.GetPixel(0, 0);
                    Color transparent = reconstructed.GetPixel(1, 0);
                    Color translucent = reconstructed.GetPixel(2, 0);
                    layeredAlphaReconstruction = opaque.A > 245 && Math.Abs(opaque.R - sourcePixels[0].R) < 10 &&
                        transparent.A < 3 && translucent.A >= 120 && translucent.A <= 136 &&
                        Math.Abs(translucent.R - sourcePixels[2].R) < 20 &&
                        Math.Abs(translucent.G - sourcePixels[2].G) < 20 &&
                        Math.Abs(translucent.B - sourcePixels[2].B) < 20;
                }
            }
            Check("uses a sufficiently visible tint derived from the slash color", secondMatteColor == Color.FromArgb(70, 70, 96), ref failures);
            Check("reconstructs layered-window transparency using the slash-color matte", layeredAlphaReconstruction, ref failures);
            Settings normalized = new Settings { Hotkey = "bad", Direction = "invalid", MultiSlashCount = 99, MultiPattern = "bad", DurationMs = 7000, DistancePx = 900, SlashColor = "not-a-color", OutlineColor = "#12aabb", SlashThickness = 99 };
            normalized.Normalize();
            Check("normalizes invalid settings to safe window-slicing limits", HotkeySpec.TryParse(normalized.QuickSliceHotkey, out a) && HotkeySpec.TryParse(normalized.SelectionHotkey, out b) && HotkeySpec.TryParse(normalized.PrecisionHotkey, out c) && normalized.Direction == "Vertical" && normalized.MultiSlashCount == 25 && normalized.MultiPattern == "Radial" && normalized.DurationMs == 6000 && normalized.DistancePx == 600 && normalized.SlashColor == "#08080B" && normalized.OutlineColor == "#12AABB" && normalized.SlashThickness == 40 && normalized.ConfirmBeforeClose, ref failures);
            Settings detachedInputWithoutLiveWindow = new Settings { DetachedPiecesInteractive = true, RefreshLiveFragments = true };
            detachedInputWithoutLiveWindow.Normalize();
            Check("disables live fragment options unless source windows stay open", !detachedInputWithoutLiveWindow.DetachedPiecesInteractive && !detachedInputWithoutLiveWindow.RefreshLiveFragments, ref failures);
            Settings refreshWithKeptFragments = new Settings { KeepWindowsOpenAfterSlicing = true, KeepFragments = true, RefreshLiveFragments = true };
            refreshWithKeptFragments.Normalize();
            Check("disables live refresh whenever fragments are retained", !refreshWithKeptFragments.RefreshLiveFragments && !Settings.CanRefreshLiveFragments(true, true) && Settings.CanRefreshLiveFragments(true, false) && !Settings.CanRefreshLiveFragments(false, false), ref failures);
            Check("recognizes only Window Slice's standard warning dialogs as self-targets", WindowTarget.IsOwnUtilityWarningDialog((uint)Process.GetCurrentProcess().Id, "#32770", "Window Slice") && WindowTarget.IsOwnUtilityWarningDialog((uint)Process.GetCurrentProcess().Id, "#32770", "Shortcut") && !WindowTarget.IsOwnUtilityWarningDialog((uint)Process.GetCurrentProcess().Id, "#32770", "Color") && !WindowTarget.IsOwnUtilityWarningDialog(0, "#32770", "Window Slice") && !WindowTarget.IsOwnUtilityWarningDialog((uint)Process.GetCurrentProcess().Id, "WindowsForms10.Window.8.app.0.141b42a_r9_ad1", "Window Slice"), ref failures);
            Check("allows slicing the settings window but keeps other own-process windows excluded", WindowTarget.IsOwnSettingsWindow((uint)Process.GetCurrentProcess().Id, "Window Slice settings") && !WindowTarget.IsOwnSettingsWindow(0, "Window Slice settings") && !WindowTarget.IsOwnSettingsWindow((uint)Process.GetCurrentProcess().Id, "Window Slice"), ref failures);
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            Settings roundTrip = serializer.Deserialize<Settings>(serializer.Serialize(new Settings { QuickSliceHotkey = "Ctrl+Alt+1", SelectionHotkey = "F8", PrecisionHotkey = "Ctrl+Shift+F8", DisperseSnapshotsHotkey = "Ctrl+Alt+D", Hotkey = "Ctrl+Alt+1", Direction = "MultiSlash", MultiSlashCount = 8, MultiPattern = "Random", DurationMs = 850, DistancePx = 240, SlashColor = "#123456", OutlineColor = "#ABCDEF", SlashThickness = 27, ConfirmBeforeClose = false, AllowRepeatedSlices = true, KeepFragments = true, UnlimitedPerformance = true, ClickToDisperse = true, RotateFragmentsWithArrowKeys = true, KeepWindowsOpenAfterSlicing = true, DetachedPiecesInteractive = true, RefreshLiveFragments = true }));
            roundTrip.Normalize();
            Check("normalizes live fragment refresh off when fragments are retained", roundTrip != null && roundTrip.KeepFragments && !roundTrip.RefreshLiveFragments, ref failures);
            Check("serializes all fragment and live-window settings", roundTrip != null && roundTrip.QuickSliceHotkey == "Ctrl+Alt+1" && roundTrip.SelectionHotkey == "F8" && roundTrip.PrecisionHotkey == "Ctrl+Shift+F8" && roundTrip.DisperseSnapshotsHotkey == "Ctrl+Alt+D" && roundTrip.Direction == "MultiSlash" && roundTrip.MultiSlashCount == 8 && roundTrip.MultiPattern == "Random" && roundTrip.DurationMs == 850 && roundTrip.DistancePx == 240 && roundTrip.SlashColor == "#123456" && roundTrip.OutlineColor == "#ABCDEF" && roundTrip.SlashThickness == 27 && !roundTrip.ConfirmBeforeClose && roundTrip.AllowRepeatedSlices && roundTrip.KeepFragments && roundTrip.UnlimitedPerformance && roundTrip.ClickToDisperse && roundTrip.RotateFragmentsWithArrowKeys && roundTrip.KeepWindowsOpenAfterSlicing && roundTrip.DetachedPiecesInteractive && !roundTrip.RefreshLiveFragments, ref failures);
            Settings duplicateDisperseShortcut = new Settings { QuickSliceHotkey = "Ctrl+Alt+1", SelectionHotkey = "F8", PrecisionHotkey = "Ctrl+Shift+F8", DisperseSnapshotsHotkey = "F8" };
            duplicateDisperseShortcut.Normalize();
            Check("disables an optional disperse shortcut that conflicts with a main shortcut", String.IsNullOrEmpty(duplicateDisperseShortcut.DisperseSnapshotsHotkey), ref failures);
            bool settingsUi = false;
            try
            {
                using (SettingsForm form = new SettingsForm(new Settings
                {
                    KeepWindowsOpenAfterSlicing = true,
                    KeepFragments = true,
                    RefreshLiveFragments = true
                }))
                {
                    TabControl pages = null;
                    Panel footer = null;
                    foreach (Control child in form.Controls)
                    {
                        if (child is TabControl) pages = child as TabControl;
                        if (child is Panel && (child as Panel).Dock == DockStyle.Bottom) footer = child as Panel;
                    }
                    TableLayoutPanel shortcuts = pages == null || pages.TabPages.Count < 4 || pages.TabPages[0].Controls.Count == 0 ? null : pages.TabPages[0].Controls[0] as TableLayoutPanel;
                    TableLayoutPanel cuts = pages == null || pages.TabPages.Count < 4 || pages.TabPages[1].Controls.Count == 0 ? null : pages.TabPages[1].Controls[0] as TableLayoutPanel;
                    TableLayoutPanel animation = pages == null || pages.TabPages.Count < 4 || pages.TabPages[2].Controls.Count == 0 ? null : pages.TabPages[2].Controls[0] as TableLayoutPanel;
                    TableLayoutPanel fragments = pages == null || pages.TabPages.Count < 4 || pages.TabPages[3].Controls.Count == 0 ? null : pages.TabPages[3].Controls[0] as TableLayoutPanel;
                    Control quick = shortcuts == null ? null : shortcuts.GetControlFromPosition(1, 0);
                    Control selection = shortcuts == null ? null : shortcuts.GetControlFromPosition(1, 1);
                    Control precision = shortcuts == null ? null : shortcuts.GetControlFromPosition(1, 2);
                    NumericUpDown duration = animation == null ? null : animation.GetControlFromPosition(1, 0) as NumericUpDown;
                    Panel persistent = fragments == null ? null : fragments.GetControlFromPosition(1, 0) as Panel;
                    TableLayoutPanel persistentOptions = null;
                    if (persistent != null)
                        foreach (Control child in persistent.Controls)
                            if (child is TableLayoutPanel) persistentOptions = child as TableLayoutPanel;
                    NumericUpDown distance = animation == null ? null : animation.GetControlFromPosition(1, 1) as NumericUpDown;
                    Panel dispersePanel = fragments == null ? null : fragments.GetControlFromPosition(1, 3) as Panel;
                    CheckBox clickToDisperse = null;
                    bool hasOptionalDisperseShortcut = false;
                    if (dispersePanel != null)
                        foreach (Control child in dispersePanel.Controls)
                        {
                            if (child is CheckBox) clickToDisperse = child as CheckBox;
                            if (child is Panel && (child as Panel).Controls.Count == 2) hasOptionalDisperseShortcut = true;
                        }
                    bool hasRotationOption = false;
                    if (persistentOptions != null)
                        foreach (Control child in persistentOptions.Controls)
                            if (child is CheckBox && (child as CheckBox).Text == "Rotate fragments with arrow keys") hasRotationOption = true;
                    bool hasLiveWindowOption = false;
                    bool hasInteractivePieceOption = false;
                    bool hasRefreshPieceOption = false;
                    bool refreshDisabledWhenKeepingFragments = false;
                    if (persistentOptions != null)
                        foreach (Control child in persistentOptions.Controls)
                            if (child is CheckBox)
                            {
                                if ((child as CheckBox).Text == "Keep source window open and sliced") hasLiveWindowOption = true;
                                if ((child as CheckBox).Text == "Forward mouse movement/wheel; use source for keyboard") hasInteractivePieceOption = true;
                                if ((child as CheckBox).Text == "Refresh detached fragments from live window (work in progress)")
                                {
                                    hasRefreshPieceOption = true;
                                    refreshDisabledWhenKeepingFragments =
                                        !(child as CheckBox).Enabled && !(child as CheckBox).Checked;
                                }
                            }
                    bool hasBackNext = false;
                    Button backButton = null;
                    Button nextButton = null;
                    if (footer != null)
                        foreach (Control child in footer.Controls)
                            if (child is FlowLayoutPanel)
                                foreach (Control button in child.Controls)
                                    if (button is Button)
                                    {
                                        if (((Button)button).Text == "Back") { backButton = (Button)button; hasBackNext = true; }
                                        if (((Button)button).Text == "Next") nextButton = (Button)button;
                                    }
                    bool pageLayoutsValid = shortcuts != null && shortcuts.RowCount == 3 && shortcuts.AutoSize && pages.TabPages[0].AutoScroll && cuts != null && cuts.RowCount == 3 && cuts.AutoSize && pages.TabPages[1].AutoScroll && animation != null && animation.RowCount == 7 && animation.AutoSize && pages.TabPages[2].AutoScroll && fragments != null && fragments.RowCount == 5 && fragments.AutoSize && pages.TabPages[3].AutoScroll && pages.TabPages.Count == 4;
                    if (pageLayoutsValid)
                    {
                        TableLayoutPanel[] allPages = new TableLayoutPanel[] { shortcuts, cuts, animation, fragments };
                        for (int pageIndex = 0; pageIndex < allPages.Length; pageIndex++)
                            for (int row = 0; row < allPages[pageIndex].RowCount; row++)
                                pageLayoutsValid = pageLayoutsValid && allPages[pageIndex].GetControlFromPosition(0, row) != null &&
                                    allPages[pageIndex].GetControlFromPosition(1, row) != null;
                    }
                    settingsUi = form.ClientSize.Width == 720 && form.ClientSize.Height == 696 && pageLayoutsValid && quick is Panel && selection is Panel && precision is Panel && cuts.GetControlFromPosition(1, 0) is ComboBox && cuts.GetControlFromPosition(1, 1) is NumericUpDown && cuts.GetControlFromPosition(1, 2) is ComboBox && duration != null && duration.Maximum == 6000 && distance != null && distance.Minimum == 0 && animation.GetControlFromPosition(1, 6) is CheckBox && persistent != null && persistent.Controls.Count == 2 && persistentOptions != null && persistentOptions.Controls.Count == 5 && hasRotationOption && hasLiveWindowOption && hasInteractivePieceOption && hasRefreshPieceOption && refreshDisabledWhenKeepingFragments && clickToDisperse != null && !clickToDisperse.Checked && hasOptionalDisperseShortcut && fragments.GetControlFromPosition(1, 4) is Panel && footer != null && hasBackNext;
                    settingsUi = settingsUi && backButton != null && nextButton != null &&
                        !backButton.Enabled && nextButton.Enabled;
                }
            }
            catch { settingsUi = false; }
            Check("builds settings for the active-window effect", settingsUi, ref failures);
            bool persistentFragmentUi = false;
            try
            {
                Bitmap fragmentImage = new Bitmap(12, 12, PixelFormat.Format32bppArgb);
                using (SliceForm fragment = new SliceForm(fragmentImage, new Rectangle(10, 10, 12, 12), new PointF[] { new PointF(0, 0), new PointF(12, 0), new PointF(12, 12), new PointF(0, 12) }))
                {
                    fragment.MakePersistent();
                    persistentFragmentUi = fragment.ContextMenuStrip != null && fragment.ContextMenuStrip.Items.Count == 1 && fragment.ContextMenuStrip.Items[0].Text == "Delete" && fragment.Cursor == Cursors.SizeAll && PersistentFragmentStore.Count == 1;
                }
                persistentFragmentUi = persistentFragmentUi && PersistentFragmentStore.Count == 0;
            }
            catch { persistentFragmentUi = false; }
            Check("creates persistent draggable fragments with a right-click Delete menu and cleans them up", persistentFragmentUi, ref failures);
            bool arrowKeyRotation = false;
            try
            {
                PersistentFragmentStore.SetRotationEnabled(true);
                Bitmap fragmentImage = new Bitmap(12, 12, PixelFormat.Format32bppArgb);
                using (SliceForm fragment = new SliceForm(fragmentImage, new Rectangle(10, 10, 12, 12), new PointF[] { new PointF(0, 0), new PointF(12, 0), new PointF(12, 12), new PointF(0, 12) }))
                {
                    fragment.MakePersistent(true);
                    arrowKeyRotation = fragment.RotateByArrowKey(Keys.Right) && fragment.RotateByArrowKey(Keys.Up) &&
                        Math.Abs(fragment.RotationY - 12.0) < 0.01 && Math.Abs(fragment.RotationX - 348.0) < 0.01 &&
                        SliceForm.RotationDeterminant(fragment.RotationX, fragment.RotationY) > 0.0;
                }
            }
            catch { arrowKeyRotation = false; }
            finally { PersistentFragmentStore.SetRotationEnabled(false); }
            Check("rotates persistent fragments with arrow-key input", arrowKeyRotation, ref failures);
            bool rotationHitboxStaysFixedUntilPointerLeaves = false;
            bool settledFragmentUsesProjectedBounds = false;
            try
            {
                PersistentFragmentStore.SetRotationEnabled(true);
                Bitmap fragmentImage = new Bitmap(12, 12, PixelFormat.Format32bppArgb);
                using (Graphics graphics = Graphics.FromImage(fragmentImage)) graphics.Clear(Color.White);
                using (SliceForm fragment = new SliceForm(fragmentImage, new Rectangle(10, 10, 12, 12), new PointF[] { new PointF(0, 0), new PointF(12, 0), new PointF(12, 12), new PointF(0, 12) }))
                {
                    fragment.MakePersistent(true);
                    bool rotated = true;
                    for (int i = 0; i < 6; i++) rotated = fragment.RotateByArrowKey(Keys.Right) && rotated;
                    rotationHitboxStaysFixedUntilPointerLeaves = rotated &&
                        fragment.Bounds.Size == new Size(12, 12) &&
                        fragment.ContentContainsPoint(new Point(19, 16));
                    fragment.UpdateRotationHover(new Point(100, 100));
                    Size expectedSize = SliceForm.ProjectedSize(new Size(12, 12), 0.0, 72.0);
                    using (Bitmap projected = fragment.CloneImage())
                        settledFragmentUsesProjectedBounds = fragment.Bounds.Size == expectedSize &&
                            projected.Size == expectedSize &&
                            fragment.ContentContainsPoint(new Point(fragment.Left + fragment.Width / 2, fragment.Top + fragment.Height / 2));
                }
            }
            catch
            {
                rotationHitboxStaysFixedUntilPointerLeaves = false;
                settledFragmentUsesProjectedBounds = false;
            }
            finally { PersistentFragmentStore.SetRotationEnabled(false); }
            Check("keeps the original fragment hitbox while rotating under the pointer", rotationHitboxStaysFixedUntilPointerLeaves, ref failures);
            Check("resizes settled fragments to their projected rotation bounds", settledFragmentUsesProjectedBounds, ref failures);
            Settings legacy = serializer.Deserialize<Settings>("{\"Hotkey\":\"F8\",\"DesktopItemHotkey\":\"Ctrl+Q\",\"ConfirmDesktopItemDelete\":false}");
            legacy.Normalize();
            Check("migrates the existing shortcut to Multi-Select and supplies separate Quick and Precision shortcuts", legacy.SelectionHotkey == "F8" && legacy.QuickSliceHotkey == "Ctrl+Alt+Q" && legacy.PrecisionHotkey == "Ctrl+Shift+F8" && legacy.ConfirmBeforeClose && legacy.Direction == "Vertical" && legacy.MultiSlashCount == 6 && legacy.MultiPattern == "Radial" && legacy.SlashColor == "#08080B" && legacy.OutlineColor == "#E6182A" && legacy.SlashThickness == 18 && !legacy.KeepFragments, ref failures);
            string testFolder = Path.GetDirectoryName(Path.GetFullPath(scriptPath));
            bool cutLoaded = false;
            bool cut2Loaded = false;
            bool prepareLoaded = false;
            bool disperseLoaded = false;
            try
            {
                AudioClip cut = AudioClip.Load(Path.Combine(testFolder, "cut.wav"));
                cutLoaded = cut.Data.Length > 0 && cut.SampleRate > 0;
            }
            catch { }
            try
            {
                AudioClip cut2 = AudioClip.Load(Path.Combine(testFolder, "cut2.wav"));
                cut2Loaded = cut2.Data.Length > 0 && cut2.SampleRate > 0;
            }
            catch { }
            try
            {
                AudioClip prepare = AudioClip.Load(Path.Combine(testFolder, "prepare.wav"));
                prepareLoaded = prepare.Data.Length > 0 && prepare.DurationMilliseconds > 0 && new SliceSoundPlayer(testFolder).HasPrepareClip;
            }
            catch { }
            try
            {
                AudioClip slide = AudioClip.Load(Path.Combine(testFolder, "slide.wav"));
                disperseLoaded = slide.Data.Length > 0 && slide.DurationMilliseconds > 0 && new SliceSoundPlayer(testFolder).HasDisperseClip;
            }
            catch { }
            Check("loads the cut.wav sound", cutLoaded, ref failures);
            Check("loads the cut2.wav sound", cut2Loaded, ref failures);
            Check("loads the prepare.wav sound and reads its duration", prepareLoaded, ref failures);
            Check("loads the slide.wav disperse sound", disperseLoaded, ref failures);
            Check("keeps randomized pitch within its configured range", SliceSoundPlayer.CalculatePlaybackRate(44100, SliceSoundPlayer.MinimumPitch) == (int)Math.Round(44100 * SliceSoundPlayer.MinimumPitch) && SliceSoundPlayer.CalculatePlaybackRate(44100, SliceSoundPlayer.MaximumPitch) == (int)Math.Round(44100 * SliceSoundPlayer.MaximumPitch) && SliceSoundPlayer.CalculatePlaybackRate(44100, 0.5) == (int)Math.Round(44100 * SliceSoundPlayer.MinimumPitch) && SliceSoundPlayer.CalculatePlaybackRate(44100, 2.0) == (int)Math.Round(44100 * SliceSoundPlayer.MaximumPitch), ref failures);
            bool pitchedWaveValid = false;
            try
            {
                AudioClip clip = AudioClip.Load(Path.Combine(testFolder, "cut.wav"));
                int rate = SliceSoundPlayer.CalculatePlaybackRate((int)clip.SampleRate, 1.05);
                byte[] wave = clip.ToWave(rate);
                pitchedWaveValid = wave.Length == clip.Data.Length + 44 && BitConverter.ToUInt32(wave, 24) == (uint)rate && BitConverter.ToUInt32(wave, 28) == (uint)rate * clip.BlockAlign && Encoding.ASCII.GetString(wave, 0, 4) == "RIFF";
            }
            catch { }
            Check("builds a pitch-adjusted WAV for Windows playback", pitchedWaveValid, ref failures);
            bool concurrentAudioFormatValid = false;
            try
            {
                AudioClip prepare = AudioClip.Load(Path.Combine(testFolder, "prepare.wav"));
                WindowSliceAudio.WaveFormatEx outputFormat = WindowSliceAudio.CreateWaveFormat(prepare, (int)prepare.SampleRate);
                concurrentAudioFormatValid = Marshal.SizeOf(typeof(WindowSliceAudio.WaveFormatEx)) == 18 && outputFormat.FormatTag == 1 && outputFormat.Channels == prepare.Channels && outputFormat.SamplesPerSecond == prepare.SampleRate && outputFormat.AverageBytesPerSecond == prepare.SampleRate * prepare.BlockAlign && outputFormat.BlockAlign == prepare.BlockAlign && outputFormat.BitsPerSample == prepare.BitsPerSample;
            }
            catch { }
            Check("builds a native PCM format for overlapping Windows audio", concurrentAudioFormatValid, ref failures);
            string tempPath = Path.Combine(testFolder, ".WindowSlice-selftest-" + Guid.NewGuid().ToString("N") + ".json");
            bool fileCheck = false;
            string fileError = null;
            try
            {
                Settings stored = new Settings { QuickSliceHotkey = "Ctrl+Alt+1", SelectionHotkey = "F8", PrecisionHotkey = "Ctrl+Shift+F8", DisperseSnapshotsHotkey = "Ctrl+Alt+D", Hotkey = "Ctrl+Alt+1", Direction = "MultiSlash", MultiSlashCount = 7, MultiPattern = "Random", DurationMs = 850, DistancePx = 240, SlashColor = "#235689", OutlineColor = "#FEDCBA", SlashThickness = 32, ConfirmBeforeClose = false, AllowRepeatedSlices = true, KeepFragments = false, ClickToDisperse = true, KeepWindowsOpenAfterSlicing = true, DetachedPiecesInteractive = true, RefreshLiveFragments = true };
                ConfigStore.Save(tempPath, stored);
                stored.DurationMs = 950;
                ConfigStore.Save(tempPath, stored);
                Settings restored = ConfigStore.Load(tempPath);
                fileCheck = restored.QuickSliceHotkey == "Ctrl+Alt+1" && restored.SelectionHotkey == "F8" && restored.PrecisionHotkey == "Ctrl+Shift+F8" && restored.DisperseSnapshotsHotkey == "Ctrl+Alt+D" && restored.Direction == "MultiSlash" && restored.MultiSlashCount == 7 && restored.MultiPattern == "Random" && restored.DurationMs == 950 && restored.DistancePx == 240 && restored.SlashColor == "#235689" && restored.OutlineColor == "#FEDCBA" && restored.SlashThickness == 32 && !restored.ConfirmBeforeClose && restored.AllowRepeatedSlices && !restored.KeepFragments && restored.ClickToDisperse && restored.KeepWindowsOpenAfterSlicing && restored.DetachedPiecesInteractive && restored.RefreshLiveFragments;
            }
            catch (Exception ex) { fileCheck = false; fileError = ex.Message; }
            finally
            {
                try { if (File.Exists(tempPath)) File.Delete(tempPath); } catch { }
            }
            Check("writes, overwrites, and reloads a settings file", fileCheck, ref failures);
            if (fileError != null) Console.WriteLine("  " + fileError);
            Console.WriteLine(failures == 0 ? "All self-checks passed." : failures + " self-check(s) failed.");
            return failures == 0 ? 0 : 1;
        }

        private static void Check(string label, bool pass, ref int failures)
        {
            Console.WriteLine((pass ? "PASS " : "FAIL ") + label);
            if (!pass) failures++;
        }

        private static Color CompositeCapturePixel(Color originalScreen, Color source, Color matte, double alpha, double opacity)
        {
            double sourceWeight = opacity * alpha;
            double matteWeight = opacity * (1.0 - alpha);
            double originalWeight = 1.0 - opacity;
            return Color.FromArgb(
                ClampByte(source.R * sourceWeight + matte.R * matteWeight + originalScreen.R * originalWeight),
                ClampByte(source.G * sourceWeight + matte.G * matteWeight + originalScreen.G * originalWeight),
                ClampByte(source.B * sourceWeight + matte.B * matteWeight + originalScreen.B * originalWeight));
        }

        private static int CompositeCaptureChannel(byte foreground, byte background, double foregroundOpacity)
        {
            return ClampByte(foreground * foregroundOpacity + background * (1.0 - foregroundOpacity));
        }

        private static int ClampByte(double value)
        {
            if (value < 0.0) return 0;
            if (value > 255.0) return 255;
            return (int)Math.Round(value);
        }
    }
}
'@

try {
    if ($SelfTest) { Write-Host 'Compiling Windows UI components...' }
    $liveCapturePath = Join-Path $PSScriptRoot 'WindowSlice.LiveCapture.v2.dll'
    if (-not (Test-Path -LiteralPath $liveCapturePath -PathType Leaf)) {
        throw "The live-capture component is missing: $liveCapturePath"
    }
    [Reflection.Assembly]::LoadFrom($liveCapturePath) | Out-Null
    Add-Type -TypeDefinition $source -ReferencedAssemblies @('System.dll', 'System.Windows.Forms', 'System.Drawing', 'System.Web.Extensions', $liveCapturePath) -ErrorAction Stop
    if ($SelfTest) { Write-Host 'Compilation passed; running checks...' }
    $exitCode = [WindowSlice.Program]::Run($PSCommandPath, [bool]$Configure, [bool]$SelfTest)
    if ($SelfTest) { exit $exitCode }
} catch {
    if ($SelfTest) {
        Write-Error $_
        exit 1
    }
    $root = Join-Path $env:LOCALAPPDATA 'WindowSlice'
    try {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $_ | Out-String | Set-Content -LiteralPath (Join-Path $root 'startup-error.log') -Encoding UTF8
    } catch { }
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show("Window Slice could not start. Details were saved in your LocalAppData\WindowSlice folder.`r`n`r`n$($_.Exception.Message)", 'Window Slice', 'OK', 'Error') | Out-Null
    } catch {
        Write-Error $_
    }
    exit 1
}