using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace CursorDriftTrail
{
    internal static class Program
    {
        [STAThread]
        private static void Main()
        {
            NativeMethods.SetProcessDPIAware();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            TrailSettings settings;
            try
            {
                settings = TrailSettings.Load();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not load Cursor Drift Trail settings.\n\n" +
                    ex.Message, "Cursor Drift Trail",
                    MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
            Application.Run(new TrailContext(settings));
        }
    }

    internal sealed class TrailContext : ApplicationContext
    {
        private readonly OverlayForm overlay;
        private readonly NotifyIcon trayIcon;
        private readonly ToolStripMenuItem toggleItem;

        public TrailContext(TrailSettings settings)
        {
            overlay = new OverlayForm(settings);
            overlay.Show();

            ContextMenuStrip menu = new ContextMenuStrip();
            toggleItem = new ToolStripMenuItem("Pause trail");
            toggleItem.Click += ToggleTrail;
            menu.Items.Add(toggleItem);
            ToolStripMenuItem settingsItem =
                new ToolStripMenuItem("Settings...");
            settingsItem.Click += OpenSettings;
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(settingsItem);
            menu.Items.Add(new ToolStripSeparator());
            ToolStripMenuItem exitItem = new ToolStripMenuItem("Exit");
            exitItem.Click += ExitApp;
            menu.Items.Add(exitItem);

            trayIcon = new NotifyIcon();
            trayIcon.Icon = SystemIcons.Application;
            trayIcon.Text = "Cursor Drift Trail";
            trayIcon.ContextMenuStrip = menu;
            trayIcon.Visible = true;
        }

        private void OpenSettings(object sender, EventArgs e)
        {
            using (SettingsForm form = new SettingsForm(overlay.Settings))
            {
                if (form.ShowDialog() == DialogResult.OK)
                    overlay.ApplySettings();
            }
        }

        private sealed class SettingsForm : Form
        {
            private readonly TrailSettings settings;
            private readonly NumericUpDown trailCountBox;
            private readonly NumericUpDown lifetimeBox;
            private readonly NumericUpDown speedBox;
            private readonly NumericUpDown opacityBox;
            private readonly NumericUpDown spawnBox;
            private readonly NumericUpDown offsetBox;
            private readonly NumericUpDown spacingBox;
            private readonly NumericUpDown fpsBox;
            private readonly CheckBox driftBox;

            public SettingsForm(TrailSettings settings)
            {
                this.settings = settings;

                Text = "Cursor Trail Settings";
                FormBorderStyle = FormBorderStyle.FixedDialog;
                StartPosition = FormStartPosition.CenterScreen;
                ClientSize = new Size(340, 370);
                MaximizeBox = false;
                MinimizeBox = false;
                ShowInTaskbar = false;

                trailCountBox = AddNumber("Maximum trail copies", 15, 1, 500, 1,
                    1, settings.MaximumTrailCount);
                lifetimeBox = AddNumber("Lifetime (seconds)", 50, 0.01M, 10, 0.01M,
                    2, (decimal)settings.GhostLifetimeSeconds);
                lifetimeBox.KeyPress += LifetimeBoxKeyPress;
                speedBox = AddNumber("Drift speed (pixels/second)", 85, 0, 500, 1,
                    0, (decimal)settings.DriftSpeedPixelsPerSecond);
                opacityBox = AddNumber("Opacity", 120, 0.01M, 1, 0.05M,
                    2, (decimal)settings.InitialOpacity);
                spawnBox = AddNumber("Spawn interval (seconds)", 155, 0.005M, 1, 0.005M,
                    3, (decimal)settings.SpawnIntervalSeconds);
                spacingBox = AddNumber("Minimum center spacing (pixels)", 190, 0, 500, 1,
                    0, (decimal)settings.TrailSpacingPixels);
                offsetBox = AddNumber("Cursor offset (pixels)", 225, 0, 100, 1,
                    0, (decimal)settings.SpawnOffsetPixels);
                fpsBox = AddNumber("Animation frame rate (FPS)", 260, 1, 120, 1,
                    0, settings.FramesPerSecond);

                driftBox = new CheckBox
                {
                    Text = "Enable drift",
                    Left = 12,
                    Top = 295,
                    AutoSize = true,
                    Checked = settings.EnableDrift
                };
                Controls.Add(driftBox);

                Button saveButton = new Button
                {
                    Text = "Save",
                    Width = 80,
                    Left = 158,
                    Top = 328
                };
                saveButton.Click += SaveClicked;
                Controls.Add(saveButton);

                Button cancelButton = new Button
                {
                    Text = "Cancel",
                    Width = 80,
                    Left = 244,
                    Top = 328,
                    DialogResult = DialogResult.Cancel
                };
                Controls.Add(cancelButton);
                AcceptButton = saveButton;
                CancelButton = cancelButton;
            }

            private NumericUpDown AddNumber(string labelText, int top,
                decimal minimum, decimal maximum, decimal increment,
                int decimalPlaces, decimal value)
            {
                Label label = new Label
                {
                    Text = labelText,
                    Left = 12,
                    Top = top + 4,
                    Width = 205,
                    Height = 20
                };
                NumericUpDown number = new NumericUpDown
                {
                    Left = 225,
                    Top = top,
                    Width = 100,
                    Minimum = minimum,
                    Maximum = maximum,
                    Increment = increment,
                    DecimalPlaces = decimalPlaces,
                    Value = value
                };
                Controls.Add(label);
                Controls.Add(number);
                return number;
            }

            private void SaveClicked(object sender, EventArgs e)
            {
                decimal lifetime;
                if (!TryReadLifetime(out lifetime))
                {
                    MessageBox.Show(this, "Enter a lifetime between 0.01 and 10 seconds.",
                        "Invalid lifetime", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    lifetimeBox.Focus();
                    return;
                }

                TrailSettings updated = new TrailSettings();
                updated.MaximumTrailCount = (int)trailCountBox.Value;
                updated.GhostLifetimeSeconds = (double)lifetime;
                updated.DriftSpeedPixelsPerSecond = (double)speedBox.Value;
                updated.InitialOpacity = (double)opacityBox.Value;
                updated.SpawnIntervalSeconds = (double)spawnBox.Value;
                updated.TrailSpacingPixels = (double)spacingBox.Value;
                updated.SpawnOffsetPixels = (double)offsetBox.Value;
                updated.FramesPerSecond = (int)fpsBox.Value;
                updated.EnableDrift = driftBox.Checked;

                try
                {
                    updated.Save();
                    settings.CopyFrom(updated);
                    DialogResult = DialogResult.OK;
                    Close();
                }
                catch (Exception ex)
                {
                    MessageBox.Show(this, "Could not save settings.\n\n" + ex.Message,
                        "Cursor Drift Trail", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }

            private static void LifetimeBoxKeyPress(object sender, KeyPressEventArgs e)
            {
                string decimalSeparator =
                    CultureInfo.CurrentCulture.NumberFormat.NumberDecimalSeparator;
                if (decimalSeparator.Length == 1 &&
                    (e.KeyChar == '.' || e.KeyChar == ',') &&
                    e.KeyChar != decimalSeparator[0])
                    e.KeyChar = decimalSeparator[0];
            }

            private bool TryReadLifetime(out decimal lifetime)
            {
                string text = lifetimeBox.Text.Trim();
                string decimalSeparator =
                    CultureInfo.CurrentCulture.NumberFormat.NumberDecimalSeparator;
                string alternateSeparator = decimalSeparator == "." ? "," : ".";
                if (text.Contains(alternateSeparator))
                    text = text.Replace(alternateSeparator, decimalSeparator);

                return Decimal.TryParse(text,
                    NumberStyles.AllowDecimalPoint | NumberStyles.AllowLeadingSign,
                    CultureInfo.CurrentCulture, out lifetime) &&
                    lifetime >= lifetimeBox.Minimum &&
                    lifetime <= lifetimeBox.Maximum;
            }
        }

        private void ToggleTrail(object sender, EventArgs e)
        {
            overlay.EnabledTrail = !overlay.EnabledTrail;
            toggleItem.Text = overlay.EnabledTrail ? "Pause trail" : "Resume trail";
        }

        private void ExitApp(object sender, EventArgs e)
        {
            trayIcon.Visible = false;
            trayIcon.Dispose();
            overlay.Dispose();
            ExitThread();
        }
    }

    internal sealed class TrailSettings
    {
        private const string RegistryPath = @"Software\CursorDriftTrail";

        public int MaximumTrailCount = 100;
        public double SpawnIntervalSeconds = 0.020;
        public double GhostLifetimeSeconds = 1.30;
        public double DriftSpeedPixelsPerSecond = 92.0;
        public double InitialOpacity = 0.38;
        public double SpawnOffsetPixels = 9.0;
        public double TrailSpacingPixels = 0.0;
        public int FramesPerSecond = 60;
        public bool EnableDrift = true;

        public static TrailSettings Load()
        {
            TrailSettings settings = new TrailSettings();
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(RegistryPath, false))
            {
                if (key == null)
                    return settings;

                settings.MaximumTrailCount = ReadInt(key, "MaximumTrailCount",
                    settings.MaximumTrailCount, 1, 500);
                settings.GhostLifetimeSeconds = ReadDouble(key, "GhostLifetimeSeconds",
                    settings.GhostLifetimeSeconds, 0.01, 10.0);
                settings.DriftSpeedPixelsPerSecond = ReadDouble(key,
                    "DriftSpeedPixelsPerSecond", settings.DriftSpeedPixelsPerSecond, 0.0, 500.0);
                settings.InitialOpacity = ReadDouble(key, "InitialOpacity",
                    settings.InitialOpacity, 0.01, 1.0);
                settings.SpawnIntervalSeconds = ReadDouble(key, "SpawnIntervalSeconds",
                    settings.SpawnIntervalSeconds, 0.005, 1.0);
                settings.TrailSpacingPixels = ReadDouble(key, "TrailSpacingPixels",
                    settings.TrailSpacingPixels, 0.0, 500.0);
                settings.SpawnOffsetPixels = ReadDouble(key, "SpawnOffsetPixels",
                    settings.SpawnOffsetPixels, 0.0, 100.0);
                settings.FramesPerSecond = ReadInt(key, "FramesPerSecond",
                    settings.FramesPerSecond, 1, 120);
                settings.EnableDrift = ReadBool(key, "EnableDrift", settings.EnableDrift);
            }
            return settings;
        }

        public void Save()
        {
            using (RegistryKey key = Registry.CurrentUser.CreateSubKey(RegistryPath))
            {
                if (key == null)
                    throw new InvalidOperationException("The settings registry key could not be created.");

                key.SetValue("MaximumTrailCount", MaximumTrailCount.ToString(CultureInfo.InvariantCulture));
                key.SetValue("GhostLifetimeSeconds", GhostLifetimeSeconds.ToString("R", CultureInfo.InvariantCulture));
                key.SetValue("DriftSpeedPixelsPerSecond", DriftSpeedPixelsPerSecond.ToString("R", CultureInfo.InvariantCulture));
                key.SetValue("InitialOpacity", InitialOpacity.ToString("R", CultureInfo.InvariantCulture));
                key.SetValue("SpawnIntervalSeconds", SpawnIntervalSeconds.ToString("R", CultureInfo.InvariantCulture));
                key.SetValue("TrailSpacingPixels", TrailSpacingPixels.ToString("R", CultureInfo.InvariantCulture));
                key.SetValue("SpawnOffsetPixels", SpawnOffsetPixels.ToString("R", CultureInfo.InvariantCulture));
                key.SetValue("FramesPerSecond", FramesPerSecond.ToString(CultureInfo.InvariantCulture));
                key.SetValue("EnableDrift", EnableDrift.ToString());
                key.Flush();
            }
        }

        public void CopyFrom(TrailSettings other)
        {
            MaximumTrailCount = other.MaximumTrailCount;
            GhostLifetimeSeconds = other.GhostLifetimeSeconds;
            DriftSpeedPixelsPerSecond = other.DriftSpeedPixelsPerSecond;
            InitialOpacity = other.InitialOpacity;
            SpawnIntervalSeconds = other.SpawnIntervalSeconds;
            TrailSpacingPixels = other.TrailSpacingPixels;
            SpawnOffsetPixels = other.SpawnOffsetPixels;
            FramesPerSecond = other.FramesPerSecond;
            EnableDrift = other.EnableDrift;
        }

        private static int ReadInt(RegistryKey key, string name, int defaultValue,
            int minimum, int maximum)
        {
            object value = key.GetValue(name);
            if (value == null)
                return defaultValue;

            int result;
            if (!Int32.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture),
                NumberStyles.Integer, CultureInfo.InvariantCulture, out result) ||
                result < minimum || result > maximum)
                throw new InvalidDataException("The saved value for " + name + " is invalid.");
            return result;
        }

        private static double ReadDouble(RegistryKey key, string name, double defaultValue,
            double minimum, double maximum)
        {
            object value = key.GetValue(name);
            if (value == null)
                return defaultValue;

            double result;
            if (!Double.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture),
                NumberStyles.Float, CultureInfo.InvariantCulture, out result) ||
                Double.IsNaN(result) || Double.IsInfinity(result) ||
                result < minimum || result > maximum)
                throw new InvalidDataException("The saved value for " + name + " is invalid.");
            return result;
        }

        private static bool ReadBool(RegistryKey key, string name, bool defaultValue)
        {
            object value = key.GetValue(name);
            if (value == null)
                return defaultValue;

            bool result;
            if (!Boolean.TryParse(Convert.ToString(value, CultureInfo.InvariantCulture), out result))
                throw new InvalidDataException("The saved value for " + name + " is invalid.");
            return result;
        }
    }

    internal sealed class OverlayForm : Form
    {
        private const int CursorShowing = 1;
        private const int IconDrawNormal = 3;
        private const int BlendSourceOver = 0;
        private const int BlendAlpha = 1;
        private const int UpdateLayeredAlpha = 2;
        private const int DibRgbColors = 0;
        private const int BiRgb = 0;
        private const int SmCxCursor = 13;
        private const int SmCyCursor = 14;
        private const int SwpNoActivate = 0x0010;
        private const int SwpShowWindow = 0x0040;
        private const double VerticalSnapSlope = 0.17632698070846498;
        private static readonly IntPtr HwndTopmost = new IntPtr(-1);

        private readonly Timer timer;
        private readonly Stopwatch clock;
        private readonly List<Ghost> ghosts;
        private readonly TrailSettings settings;
        private Bitmap cachedCursorImage;
        private IntPtr cachedCursorHandle;
        private int cachedHotspotX;
        private int cachedHotspotY;
        private int cachedTargetWidth;
        private int cachedTargetHeight;
        private int configuredCursorBaseSize;
        private double nextSizeRefresh;
        private Point lastCursorPosition;
        private bool haveLastPosition;
        private double directionX = -1.0;
        private double directionY = 0.0;
        private double lastSpawnTime;
        private double lastTickTime;
        private bool enabledTrail = true;

        public TrailSettings Settings
        {
            get { return settings; }
        }

        public bool EnabledTrail
        {
            get { return enabledTrail; }
            set
            {
                enabledTrail = value;
                if (!enabledTrail)
                {
                    ClearGhosts();
                    Hide();
                }
                else
                {
                    Show();
                }
            }
        }

        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x00080000; // WS_EX_LAYERED
                cp.ExStyle |= 0x00000020; // WS_EX_TRANSPARENT (mouse click-through)
                cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
                cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
                return cp;
            }
        }

        public OverlayForm(TrailSettings settings)
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            Size = new Size(1, 1);
            TopMost = true;
            clock = Stopwatch.StartNew();
            ghosts = new List<Ghost>();
            this.settings = settings;

            timer = new Timer();
            timer.Interval = GetTimerInterval(settings.FramesPerSecond);
            timer.Tick += Tick;
            timer.Start();
        }

        public void ApplySettings()
        {
            timer.Interval = GetTimerInterval(settings.FramesPerSecond);
            while (ghosts.Count > settings.MaximumTrailCount)
            {
                ghosts[0].Image.Dispose();
                ghosts.RemoveAt(0);
            }
        }

        private static int GetTimerInterval(int framesPerSecond)
        {
            return Math.Max(1, (int)Math.Round(1000.0 / framesPerSecond));
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            NativeMethods.SetWindowPos(Handle, HwndTopmost, 0, 0, 1, 1,
                SwpNoActivate | SwpShowWindow);
        }

        private void Tick(object sender, EventArgs e)
        {
            if (!enabledTrail)
                return;

            double now = clock.Elapsed.TotalSeconds;
            double delta = lastTickTime == 0.0 ? timer.Interval / 1000.0 : now - lastTickTime;
            if (delta > 0.10)
                delta = 0.10;
            lastTickTime = now;

            NativeMethods.CURSORINFO cursorInfo = new NativeMethods.CURSORINFO();
            cursorInfo.cbSize = Marshal.SizeOf(typeof(NativeMethods.CURSORINFO));
            if (!NativeMethods.GetCursorInfo(ref cursorInfo) ||
                (cursorInfo.flags & CursorShowing) == 0 || cursorInfo.hCursor == IntPtr.Zero)
            {
                RemoveExpiredGhosts(now);
                Render(now);
                return;
            }

            int targetWidth = NativeMethods.GetSystemMetrics(SmCxCursor);
            int targetHeight = NativeMethods.GetSystemMetrics(SmCyCursor);
            if (targetWidth <= 0) targetWidth = cachedCursorImage == null ? 32 : cachedCursorImage.Width;
            if (targetHeight <= 0) targetHeight = cachedCursorImage == null ? 32 : cachedCursorImage.Height;
            if (now >= nextSizeRefresh)
            {
                configuredCursorBaseSize = ReadConfiguredCursorBaseSize();
                nextSizeRefresh = now + 0.5;
            }
            if (configuredCursorBaseSize > 0)
            {
                targetWidth = Math.Max(targetWidth, configuredCursorBaseSize);
                targetHeight = Math.Max(targetHeight, configuredCursorBaseSize);
            }
            if (cursorInfo.hCursor != cachedCursorHandle || cachedCursorImage == null ||
                targetWidth != cachedTargetWidth || targetHeight != cachedTargetHeight)
                CacheCursor(cursorInfo.hCursor, targetWidth, targetHeight);

            if (cachedCursorImage == null)
            {
                RemoveExpiredGhosts(now);
                Render(now);
                return;
            }

            Point current = new Point(cursorInfo.ptScreenPos.X, cursorInfo.ptScreenPos.Y);
            if (haveLastPosition)
            {
                double dx = current.X - lastCursorPosition.X;
                double dy = current.Y - lastCursorPosition.Y;
                double length = Math.Sqrt(dx * dx + dy * dy);
                if (length >= 2.0)
                {
                    if (Math.Abs(dx) <= Math.Abs(dy) * VerticalSnapSlope)
                    {
                        directionX = 0.0;
                        directionY = dy > 0.0 ? -1.0 : 1.0;
                    }
                    else
                    {
                        directionX = -dx / length;
                        directionY = -dy / length;
                    }
                }
            }
            lastCursorPosition = current;
            haveLastPosition = true;
            if (now - lastSpawnTime >= settings.SpawnIntervalSeconds &&
                ghosts.Count < settings.MaximumTrailCount &&
                ghosts.Count < settings.MaximumTrailCount &&
                IsSpacedFromExistingGhosts(
                    current.X + directionX * settings.SpawnOffsetPixels,
                    current.Y + directionY * settings.SpawnOffsetPixels))
            {
                // The first ghost begins just behind the live pointer; later ghosts drift
                // along the same heading, including while the pointer is stationary.
                Bitmap snapshot = new Bitmap(cachedCursorImage);
                ghosts.Add(new Ghost(snapshot, cachedHotspotX, cachedHotspotY,
                    current.X + directionX * settings.SpawnOffsetPixels,
                    current.Y + directionY * settings.SpawnOffsetPixels,
                    directionX, directionY, now));
                lastSpawnTime = now;
            }

            for (int i = 0; i < ghosts.Count; i++)
            {
                Ghost ghost = ghosts[i];
                if (settings.EnableDrift)
                {
                    ghost.X += ghost.DirectionX *
                        settings.DriftSpeedPixelsPerSecond * delta;
                    ghost.Y += ghost.DirectionY *
                        settings.DriftSpeedPixelsPerSecond * delta;
                }
            }

            RemoveExpiredGhosts(now);
            Render(now);
        }

        private bool IsSpacedFromExistingGhosts(double candidateX, double candidateY)
        {
            double minimumSpacing = settings.TrailSpacingPixels;
            if (minimumSpacing <= 0.0)
                return true;

            double candidateCenterX = candidateX - cachedHotspotX + cachedCursorImage.Width / 2.0;
            double candidateCenterY = candidateY - cachedHotspotY + cachedCursorImage.Height / 2.0;
            double minimumSpacingSquared = minimumSpacing * minimumSpacing;

            for (int i = 0; i < ghosts.Count; i++)
            {
                Ghost ghost = ghosts[i];
                double ghostCenterX = ghost.X - ghost.HotspotX + ghost.Image.Width / 2.0;
                double ghostCenterY = ghost.Y - ghost.HotspotY + ghost.Image.Height / 2.0;
                double dx = candidateCenterX - ghostCenterX;
                double dy = candidateCenterY - ghostCenterY;
                if (dx * dx + dy * dy < minimumSpacingSquared)
                    return false;
            }

            return true;
        }

        private void CacheCursor(IntPtr handle, int targetWidth, int targetHeight)
        {
            NativeMethods.ICONINFO iconInfo;
            if (!NativeMethods.GetIconInfo(handle, out iconInfo))
                return;

            Bitmap replacement = null;
            try
            {
                int width = 0;
                int height = 0;
                NativeMethods.BITMAP bitmapInfo;
                if (iconInfo.hbmColor != IntPtr.Zero &&
                    NativeMethods.GetObject(iconInfo.hbmColor, Marshal.SizeOf(typeof(NativeMethods.BITMAP)), out bitmapInfo) != 0)
                {
                    width = bitmapInfo.bmWidth;
                    height = bitmapInfo.bmHeight;
                }
                else if (iconInfo.hbmMask != IntPtr.Zero &&
                    NativeMethods.GetObject(iconInfo.hbmMask, Marshal.SizeOf(typeof(NativeMethods.BITMAP)), out bitmapInfo) != 0)
                {
                    width = bitmapInfo.bmWidth;
                    height = bitmapInfo.bmHeight / 2;
                }

                if (width <= 0 || height <= 0 || width > 512 || height > 512)
                    return;

                int targetNominalSize = Math.Max(targetWidth, targetHeight);
                double scale = (double)targetNominalSize / Math.Max(width, height);
                int drawWidth = Math.Max(1, Math.Min((int)Math.Round(width * scale), 512));
                int drawHeight = Math.Max(1, Math.Min((int)Math.Round(height * scale), 512));
                replacement = new Bitmap(drawWidth, drawHeight, PixelFormat.Format32bppArgb);
                using (Graphics graphics = Graphics.FromImage(replacement))
                {
                    graphics.Clear(Color.Transparent);
                    IntPtr hdc = graphics.GetHdc();
                    try
                    {
                        NativeMethods.DrawIconEx(hdc, 0, 0, handle, drawWidth, drawHeight,
                            0, IntPtr.Zero, IconDrawNormal);
                    }
                    finally
                    {
                        graphics.ReleaseHdc(hdc);
                    }
                }

                if (cachedCursorImage != null)
                    cachedCursorImage.Dispose();
                cachedCursorImage = replacement;
                replacement = null;
                cachedCursorHandle = handle;
                cachedHotspotX = (int)Math.Round((double)iconInfo.xHotspot * scale);
                cachedHotspotY = (int)Math.Round((double)iconInfo.yHotspot * scale);
                cachedTargetWidth = targetWidth;
                cachedTargetHeight = targetHeight;
            }
            finally
            {
                if (replacement != null)
                    replacement.Dispose();
                if (iconInfo.hbmColor != IntPtr.Zero)
                    NativeMethods.DeleteObject(iconInfo.hbmColor);
                if (iconInfo.hbmMask != IntPtr.Zero)
                    NativeMethods.DeleteObject(iconInfo.hbmMask);
            }
        }

        private int ReadConfiguredCursorBaseSize()
        {
            try
            {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Control Panel\Cursors", false))
                {
                    if (key != null)
                    {
                        object value = key.GetValue("CursorBaseSize");
                        int size;
                        if (value != null && Int32.TryParse(Convert.ToString(value), out size) &&
                            size >= 16 && size <= 512)
                            return size;
                    }
                }
            }
            catch
            {
            }
            return 0;
        }

        private void RemoveExpiredGhosts(double now)
        {
            for (int i = ghosts.Count - 1; i >= 0; i--)
            {
                if (now - ghosts[i].BornAt >= settings.GhostLifetimeSeconds)
                {
                    ghosts[i].Image.Dispose();
                    ghosts.RemoveAt(i);
                }
            }
        }

        private void ClearGhosts()
        {
            for (int i = 0; i < ghosts.Count; i++)
                ghosts[i].Image.Dispose();
            ghosts.Clear();
        }

        private void Render(double now)
        {
            if (ghosts.Count == 0)
            {
                Hide();
                return;
            }

            int minX = Int32.MaxValue;
            int minY = Int32.MaxValue;
            int maxX = Int32.MinValue;
            int maxY = Int32.MinValue;
            for (int i = 0; i < ghosts.Count; i++)
            {
                Ghost ghost = ghosts[i];
                int x = (int)Math.Floor(ghost.X - ghost.HotspotX);
                int y = (int)Math.Floor(ghost.Y - ghost.HotspotY);
                minX = Math.Min(minX, x);
                minY = Math.Min(minY, y);
                maxX = Math.Max(maxX, x + ghost.Image.Width);
                maxY = Math.Max(maxY, y + ghost.Image.Height);
            }

            int width = maxX - minX;
            int height = maxY - minY;
            if (width <= 0 || height <= 0 || width > 4096 || height > 4096)
                return;

            using (Bitmap frame = new Bitmap(width, height, PixelFormat.Format32bppPArgb))
            using (Graphics graphics = Graphics.FromImage(frame))
            {
                graphics.CompositingMode = CompositingMode.SourceOver;
                graphics.CompositingQuality = CompositingQuality.HighSpeed;
                graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
                graphics.PixelOffsetMode = PixelOffsetMode.HighSpeed;
                graphics.Clear(Color.Transparent);

                for (int i = 0; i < ghosts.Count; i++)
                {
                    Ghost ghost = ghosts[i];
                    double age = now - ghost.BornAt;
                    double remaining = 1.0 - age / settings.GhostLifetimeSeconds;
                    if (remaining <= 0.0)
                        continue;
                    float opacity = (float)(settings.InitialOpacity * remaining * remaining);
                    using (ImageAttributes attributes = new ImageAttributes())
                    {
                        ColorMatrix matrix = new ColorMatrix();
                        matrix.Matrix33 = opacity;
                        attributes.SetColorMatrix(matrix, ColorMatrixFlag.Default,
                            ColorAdjustType.Bitmap);
                        int x = (int)Math.Round(ghost.X - ghost.HotspotX) - minX;
                        int y = (int)Math.Round(ghost.Y - ghost.HotspotY) - minY;
                        graphics.DrawImage(ghost.Image,
                            new Rectangle(x, y, ghost.Image.Width, ghost.Image.Height),
                            0, 0, ghost.Image.Width, ghost.Image.Height,
                            GraphicsUnit.Pixel, attributes);
                    }
                }

                Present(frame, minX, minY);
            }
        }

        private void Present(Bitmap frame, int screenX, int screenY)
        {
            IntPtr screenDc = NativeMethods.GetDC(IntPtr.Zero);
            IntPtr memoryDc = IntPtr.Zero;
            IntPtr bitmap = IntPtr.Zero;
            IntPtr oldBitmap = IntPtr.Zero;
            IntPtr bits = IntPtr.Zero;
            BitmapData data = null;
            try
            {
                memoryDc = NativeMethods.CreateCompatibleDC(screenDc);
                NativeMethods.BITMAPINFO bitmapInfo = new NativeMethods.BITMAPINFO();
                bitmapInfo.bmiHeader.biSize = Marshal.SizeOf(typeof(NativeMethods.BITMAPINFOHEADER));
                bitmapInfo.bmiHeader.biWidth = frame.Width;
                bitmapInfo.bmiHeader.biHeight = -frame.Height;
                bitmapInfo.bmiHeader.biPlanes = 1;
                bitmapInfo.bmiHeader.biBitCount = 32;
                bitmapInfo.bmiHeader.biCompression = BiRgb;
                bitmap = NativeMethods.CreateDIBSection(screenDc, ref bitmapInfo,
                    DibRgbColors, out bits, IntPtr.Zero, 0);
                if (memoryDc == IntPtr.Zero || bitmap == IntPtr.Zero || bits == IntPtr.Zero)
                    return;

                oldBitmap = NativeMethods.SelectObject(memoryDc, bitmap);
                Rectangle rect = new Rectangle(0, 0, frame.Width, frame.Height);
                data = frame.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
                int rowBytes = frame.Width * 4;
                byte[] row = new byte[rowBytes];
                for (int y = 0; y < frame.Height; y++)
                {
                    IntPtr source = data.Stride >= 0
                        ? IntPtr.Add(data.Scan0, y * data.Stride)
                        : IntPtr.Add(data.Scan0, (frame.Height - 1 - y) * -data.Stride);
                    Marshal.Copy(source, row, 0, rowBytes);
                    Marshal.Copy(row, 0, IntPtr.Add(bits, y * rowBytes), rowBytes);
                }
                frame.UnlockBits(data);
                data = null;

                NativeMethods.POINT destination = new NativeMethods.POINT(screenX, screenY);
                NativeMethods.POINT sourcePoint = new NativeMethods.POINT(0, 0);
                NativeMethods.SIZE size = new NativeMethods.SIZE(frame.Width, frame.Height);
                NativeMethods.BLENDFUNCTION blend = new NativeMethods.BLENDFUNCTION();
                blend.BlendOp = BlendSourceOver;
                blend.BlendFlags = 0;
                blend.SourceConstantAlpha = 255;
                blend.AlphaFormat = BlendAlpha;
                NativeMethods.UpdateLayeredWindow(Handle, screenDc, ref destination,
                    ref size, memoryDc, ref sourcePoint, 0, ref blend, UpdateLayeredAlpha);
                NativeMethods.SetWindowPos(Handle, HwndTopmost, screenX, screenY,
                    frame.Width, frame.Height, SwpNoActivate | SwpShowWindow);
            }
            finally
            {
                if (data != null)
                    frame.UnlockBits(data);
                if (oldBitmap != IntPtr.Zero && memoryDc != IntPtr.Zero)
                    NativeMethods.SelectObject(memoryDc, oldBitmap);
                if (bitmap != IntPtr.Zero)
                    NativeMethods.DeleteObject(bitmap);
                if (memoryDc != IntPtr.Zero)
                    NativeMethods.DeleteDC(memoryDc);
                if (screenDc != IntPtr.Zero)
                    NativeMethods.ReleaseDC(IntPtr.Zero, screenDc);
            }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                timer.Stop();
                timer.Dispose();
                ClearGhosts();
                if (cachedCursorImage != null)
                {
                    cachedCursorImage.Dispose();
                    cachedCursorImage = null;
                }
            }
            base.Dispose(disposing);
        }
    }

    internal sealed class Ghost
    {
        public readonly Bitmap Image;
        public readonly int HotspotX;
        public readonly int HotspotY;
        public readonly double DirectionX;
        public readonly double DirectionY;
        public readonly double BornAt;
        public double X;
        public double Y;

        public Ghost(Bitmap image, int hotspotX, int hotspotY, double x, double y,
            double directionX, double directionY, double bornAt)
        {
            Image = image;
            HotspotX = hotspotX;
            HotspotY = hotspotY;
            X = x;
            Y = y;
            DirectionX = directionX;
            DirectionY = directionY;
            BornAt = bornAt;
        }
    }

    internal static class NativeMethods
    {
        [StructLayout(LayoutKind.Sequential)]
        internal struct POINT
        {
            public int X;
            public int Y;
            public POINT(int x, int y) { X = x; Y = y; }
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct SIZE
        {
            public int cx;
            public int cy;
            public SIZE(int width, int height) { cx = width; cy = height; }
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct CURSORINFO
        {
            public int cbSize;
            public int flags;
            public IntPtr hCursor;
            public POINT ptScreenPos;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct ICONINFO
        {
            [MarshalAs(UnmanagedType.Bool)] public bool fIcon;
            public uint xHotspot;
            public uint yHotspot;
            public IntPtr hbmMask;
            public IntPtr hbmColor;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct BITMAP
        {
            public int bmType;
            public int bmWidth;
            public int bmHeight;
            public int bmWidthBytes;
            public ushort bmPlanes;
            public ushort bmBitsPixel;
            public IntPtr bmBits;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct BITMAPINFOHEADER
        {
            public int biSize;
            public int biWidth;
            public int biHeight;
            public short biPlanes;
            public short biBitCount;
            public int biCompression;
            public int biSizeImage;
            public int biXPelsPerMeter;
            public int biYPelsPerMeter;
            public int biClrUsed;
            public int biClrImportant;
        }

        [StructLayout(LayoutKind.Sequential)]
        internal struct BITMAPINFO
        {
            public BITMAPINFOHEADER bmiHeader;
            public int bmiColors;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        internal struct BLENDFUNCTION
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetCursorInfo(ref CURSORINFO pci);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool GetIconInfo(IntPtr hIcon, out ICONINFO piconinfo);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool DrawIconEx(IntPtr hdc, int xLeft, int yTop,
            IntPtr hIcon, int cxWidth, int cyWidth, uint istepIfAniCur,
            IntPtr hbrFlickerFreeDraw, int diFlags);

        [DllImport("user32.dll")]
        internal static extern IntPtr GetDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        internal static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool UpdateLayeredWindow(IntPtr hWnd, IntPtr hdcDst,
            ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc,
            int crKey, ref BLENDFUNCTION pblend, int dwFlags);

        [DllImport("user32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int x, int y, int cx, int cy, int uFlags);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool SetProcessDPIAware();

        [DllImport("user32.dll")]
        internal static extern int GetSystemMetrics(int nIndex);

        [DllImport("gdi32.dll", SetLastError = true)]
        internal static extern IntPtr CreateCompatibleDC(IntPtr hdc);

        [DllImport("gdi32.dll", SetLastError = true)]
        internal static extern IntPtr CreateDIBSection(IntPtr hdc, ref BITMAPINFO pbmi,
            uint usage, out IntPtr ppvBits, IntPtr hSection, uint offset);

        [DllImport("gdi32.dll", SetLastError = true)]
        internal static extern IntPtr SelectObject(IntPtr hdc, IntPtr hObject);

        [DllImport("gdi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool DeleteObject(IntPtr hObject);

        [DllImport("gdi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        internal static extern bool DeleteDC(IntPtr hdc);

        [DllImport("gdi32.dll", EntryPoint = "GetObjectW", SetLastError = true)]
        internal static extern int GetObject(IntPtr h, int c, out BITMAP bitmap);
    }
}
