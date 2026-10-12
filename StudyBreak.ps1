<#
.SYNOPSIS
    NightWatch Study Break (v4.0) - premium WinForms/GDI+ interface.
.DESCRIPTION
    1. Asks how long the break should last BEFORE enabling it.
    2. Enables the break with an explicit expiry time and a boot-session stamp.
    3. The break auto-disables itself once the duration elapses, so there is no
       need to click again to turn it off.
    4. Clicking the button WHILE a break is running offers to end it early, with
       a live countdown of how much of the break is left.
    5. State lives only in C:\ProgramData\NightWatch\break_state.json.
       Nothing is written to the Desktop.

    The interface is drawn with custom GDI+ controls (namespace NW, injected via
    Add-Type) layered on the TableLayoutPanel layout engine, so the auto-sizing
    rows that prevent overlap on high-DPI displays are preserved.

    Each dialog is built by a New-*Form function that returns the form plus the
    controls a caller needs to update. -SelfTest renders those same functions to
    PNG, so the preview can never drift from what actually ships.

    The break_state.json contract is unchanged, so IdleMistakeDetector.ps1 keeps
    working exactly as before:
        Active, Timestamp, Mode, DurationMinutes, ExpiresAt, BootUptimeMs

.PARAMETER SelfTest
    Render each dialog to a PNG and exit, without interaction.
.PARAMETER Capture
    Show each dialog and photograph the real screen instead of using
    DrawToBitmap, then exit. Transparent controls composite differently in a
    live window than they do under WM_PRINT, so -SelfTest can pass while the
    dialog shows a black block on screen. Run this before trusting a change
    that touches backgrounds or the timing card.
.PARAMETER OutDir
    Destination folder for -SelfTest output. Defaults to %TEMP%.
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [switch]$Capture,
    [string]$OutDir = $env:TEMP
)

$dataDir = "C:\ProgramData\NightWatch"
if (-not (Test-Path $dataDir)) {
    try { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null } catch {}
}
$stateFile = Join-Path $dataDir "break_state.json"

# Boot-session fingerprint: uptime in ms. Resets on restart/shutdown,
# keeps growing across sleep/hibernate.
$bootUptimeMs = [long][Environment]::TickCount

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null
[System.Windows.Forms.Application]::EnableVisualStyles()

# ==================================================================
# Custom-drawn control library
# ==================================================================
if (-not ('NW.Theme' -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing, System.Windows.Forms -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;
using System.Runtime.InteropServices;

namespace NW
{
    public static class Theme
    {
        public static readonly Color BgDeep      = Color.FromArgb(11, 15, 23);
        public static readonly Color Bg          = Color.FromArgb(15, 20, 31);
        public static readonly Color Surface     = Color.FromArgb(22, 28, 42);
        public static readonly Color Border      = Color.FromArgb(40, 51, 76);
        public static readonly Color BorderSoft  = Color.FromArgb(31, 39, 57);
        public static readonly Color Text        = Color.FromArgb(238, 242, 248);
        public static readonly Color TextMuted   = Color.FromArgb(148, 163, 184);
        public static readonly Color TextDim     = Color.FromArgb(104, 120, 143);
        public static readonly Color Cyan        = Color.FromArgb(34, 211, 238);
        public static readonly Color Blue        = Color.FromArgb(59, 130, 246);
        public static readonly Color Violet      = Color.FromArgb(139, 92, 246);
        public static readonly Color Danger      = Color.FromArgb(248, 113, 113);
        public static readonly Color Success     = Color.FromArgb(52, 211, 153);

        public static bool Animations = true;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool SystemParametersInfo(uint a, uint b, ref bool c, uint d);

        public static void DetectReducedMotion()
        {
            try {
                bool on = true;
                // SPI_GETCLIENTAREAANIMATION
                if (SystemParametersInfo(0x1042, 0, ref on, 0)) Animations = on;
            } catch { Animations = true; }
        }

        public static void Setup(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
        }

        public static GraphicsPath Rounded(Rectangle r, int radius)
        {
            var p = new GraphicsPath();
            if (r.Width <= 0 || r.Height <= 0) { p.AddRectangle(r); return p; }
            int d = radius * 2;
            if (d > Math.Min(r.Width, r.Height)) d = Math.Min(r.Width, r.Height);
            p.AddArc(r.X,          r.Y,          d, d, 180, 90);
            p.AddArc(r.Right - d,  r.Y,          d, d, 270, 90);
            p.AddArc(r.Right - d,  r.Bottom - d, d, d,   0, 90);
            p.AddArc(r.X,          r.Bottom - d, d, d,  90, 90);
            p.CloseFigure();
            return p;
        }

        public static StringFormat Center()
        {
            return new StringFormat {
                Alignment = StringAlignment.Center,
                LineAlignment = StringAlignment.Center,
                FormatFlags = StringFormatFlags.NoWrap
            };
        }

        /// <summary>Layered low-alpha strokes approximate a soft glow cheaply.</summary>
        public static void Glow(Graphics g, GraphicsPath path, Color c, int radius, int strength)
        {
            if (strength <= 0) return;
            for (int i = 0; i < 3; i++)
            {
                int a = Math.Max(1, (int)(strength * (0.16 / (i + 1))));
                float w = radius + (float)(i + 1) * 2.2f;
                using (var pen = new Pen(Color.FromArgb(a, c), w) {
                    StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
                    g.DrawPath(pen, path);
            }
        }

        public static Font Ui(float size, FontStyle style)
        {
            return new Font("Segoe UI", size, style, GraphicsUnit.Point);
        }

        public static Font UiSemibold(float size)
        {
            try { return new Font("Segoe UI Semibold", size, FontStyle.Regular, GraphicsUnit.Point); }
            catch { return new Font("Segoe UI", size, FontStyle.Bold, GraphicsUnit.Point); }
        }

        /// <summary>Monospaced digits so timers do not jitter as they change.</summary>
        public static Font Num(float size, FontStyle style)
        {
            return new Font("Consolas", size, style, GraphicsUnit.Point);
        }
    }

    /// <summary>
    /// Base for NW controls that sit on a solid parent surface.
    ///
    /// BackColor = Transparent only works when WinForms can ask the parent to
    /// repaint this control's rectangle. On a live composited window that
    /// repaint is not guaranteed, and when it is skipped the control's own
    /// back buffer is simply left untouched - which is black. It showed up as
    /// a black block behind the countdown ring, and it is intermittent: the
    /// same build captured clean on one run and broken on the next.
    ///
    /// -SelfTest cannot catch it, because DrawToBitmap (WM_PRINT) always takes
    /// the working path. Only -Capture, a real screen grab, can.
    ///
    /// So these controls never depend on that machinery at paint time: each
    /// paints its own background from BackFill.
    /// </summary>
    public abstract class SurfaceControl : Control
    {
        /// <summary>
        /// Colour painted behind this control; empty means paint nothing.
        /// It must match whatever the control sits on, otherwise a rounded
        /// corner shows up as a square edge.
        /// </summary>
        public Color BackFill = Color.Empty;

        protected SurfaceControl()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw |
                     ControlStyles.SupportsTransparentBackColor, true);
            // Without SupportsTransparentBackColor this assignment throws and
            // every NW control fails to construct, taking its whole dialog
            // with it. Keep the flag even though BackFill now does the work.
            BackColor = Color.Transparent;
        }

        /// <summary>
        /// Paint the background. Every derived OnPaint must call this first:
        /// AllPaintingInWmPaint suppresses WM_ERASEBKGND, so overriding
        /// OnPaintBackground would never run.
        /// </summary>
        protected void PaintBack(Graphics g)
        {
            if (BackFill.IsEmpty) return;
            var r = ClientRectangle;
            if (r.Width <= 0 || r.Height <= 0) return;
            using (var b = new SolidBrush(BackFill)) g.FillRectangle(b, r);
        }
    }

    /// <summary>Rounded surface with a subtle sheen and hairline border.</summary>
    public class Card : SurfaceControl
    {
        public int Radius = 16;
        public Color Fill = Theme.Surface;
        public Color BorderColor = Theme.BorderSoft;
        public int GlowStrength = 0;
        public Color GlowColor = Theme.Cyan;

        public Card()
        {
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Setup(g);
            PaintBack(g);
            var r = new Rectangle(0, 0, Width - 1, Height - 1);
            using (var p = Theme.Rounded(r, Radius))
            {
                if (GlowStrength > 0) Theme.Glow(g, p, GlowColor, Radius, GlowStrength);
                using (var b = new SolidBrush(Fill)) g.FillPath(b, p);
                // No top-half sheen gradient: the ring and the labels sitting on
                // the card paint a flat Fill, so a gradient underneath would
                // show a seam along the edge of anything painted over it. The
                // glow and the border already carry the depth.
                using (var pen = new Pen(BorderColor, 1f)) g.DrawPath(pen, p);
            }
        }
    }

    /// <summary>Header strip: gradient, one restrained bloom, hairline base.</summary>
    public class HeaderBand : Control
    {
        public HeaderBand()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.BgDeep;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Setup(g);
            var r = new Rectangle(0, 0, Width, Height);
            using (var lg = new LinearGradientBrush(r, Theme.BgDeep, Theme.Bg, LinearGradientMode.Vertical))
                g.FillRectangle(lg, r);

            for (int i = 4; i >= 1; i--)
            {
                int rr = 46 * i;
                using (var b = new SolidBrush(Color.FromArgb(6, Theme.Cyan)))
                    g.FillEllipse(b, -rr / 2, -rr / 3, rr, rr);
            }
            using (var b2 = new SolidBrush(Color.FromArgb(5, Theme.Violet)))
                g.FillEllipse(b2, Width - 90, -30, 140, 140);

            using (var pen = new Pen(Theme.BorderSoft, 1f))
                g.DrawLine(pen, 0, Height - 1, Width, Height - 1);
        }
    }

    /// <summary>Crescent moon + pause bars: the NightWatch mark, drawn not shipped as a bitmap.</summary>
    public class Emblem : SurfaceControl
    {
        public Color Tint = Theme.Cyan;
        public Emblem() { }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Setup(g);
            // The mark sits on HeaderBand's vertical BgDeep->Bg gradient and
            // spans the band's full height, so it repaints that same gradient
            // instead of asking the band to repaint it. A flat fill would show
            // a visible seam along the bottom of the mark.
            using (var band = new LinearGradientBrush(
                       new Rectangle(0, 0, Width, Height),
                       Theme.BgDeep, Theme.Bg, LinearGradientMode.Vertical))
                g.FillRectangle(band, new Rectangle(0, 0, Width, Height));

            float s = Math.Min(Width, Height);
            if (s < 4) return;
            var box = new RectangleF((Width - s) / 2f, (Height - s) / 2f, s, s);

            // Crescent = circle minus an offset circle (alternate fill).
            var moon = new GraphicsPath();
            moon.AddEllipse(box);
            var cut = new GraphicsPath();
            float k = s * 0.26f;
            cut.AddEllipse(box.X + k, box.Y - k * 0.62f, s, s);
            moon.FillMode = FillMode.Alternate;
            moon.AddPath(cut, true);

            using (var lg = new LinearGradientBrush(box, Theme.Cyan, Theme.Violet, LinearGradientMode.Vertical))
                g.FillPath(lg, moon);

            float bw = Math.Max(1.5f, s * 0.10f);
            float bh = s * 0.44f;
            float gap = s * 0.14f;
            float by = box.Y + (s - bh) / 2f;
            float bx = box.X + (s - (bw * 2 + gap)) / 2f;
            using (var b = new SolidBrush(Color.FromArgb(235, 245, 250)))
            {
                g.FillRectangle(b, bx, by, bw, bh);
                g.FillRectangle(b, bx + bw + gap, by, bw, bh);
            }
        }
    }

    public enum BtnVariant { Ghost, Primary, Danger }

    /// <summary>
    /// Owner-drawn button: rounded, animated hover/press, optional selected state.
    /// Implements IButtonControl so Form.AcceptButton / CancelButton work, which
    /// is what gives the dialogs their Enter / Escape behaviour.
    /// </summary>
    public class NWButton : SurfaceControl, IButtonControl
    {
        private float _hover, _press, _focus;
        private bool _hovering, _pressing;
        private Timer _anim;

        public DialogResult DialogResult { get; set; }

        public void NotifyDefault(bool value) { }

        // Control does not provide PerformClick (only Button does), so the
        // interface member has to be implemented for AcceptButton/CancelButton.
        public void PerformClick()
        {
            if (!Enabled || !Visible) return;
            OnClick(EventArgs.Empty);
        }

        private bool _selected;
        public bool Selected {
            get { return _selected; }
            // Must be a property, not a field: a field assignment does not
            // invalidate, so the chip would keep its old look until some
            // unrelated repaint happened to redraw it.
            set { if (_selected != value) { _selected = value; Invalidate(); } }
        }
        public BtnVariant Variant = BtnVariant.Ghost;
        public Color Accent = Theme.Cyan;
        public int Radius = 10;
        public int Symbol = 0;              // 0 none, 1 minus, 2 plus, 3 check
        public bool SymbolOnly = false;
        public string Caption = "";

        public NWButton()
        {
            SetStyle(ControlStyles.Selectable, true);
            SetStyle(ControlStyles.StandardDoubleClick, false);
            ForeColor = Theme.Text;
            Cursor = Cursors.Hand;
            TabStop = true;
            AccessibleRole = AccessibleRole.PushButton;
            _anim = new Timer();
            // 33ms ~= 30fps. Hover tints and a sweeping arc do not need 60fps,
            // and each tick invalidates the control, so this is the single
            // biggest lever on how busy the UI feels.
            _anim.Interval = Theme.Animations ? 33 : 120;
            _anim.Tick += delegate {
                float dh = (_hovering ? 1f : 0f) - _hover;
                float dp = (_pressing ? 1f : 0f) - _press;
                float df = (Focused ? 1f : 0f) - _focus;
                if (Math.Abs(dh) < .01f && Math.Abs(dp) < .01f && Math.Abs(df) < .01f) { _anim.Stop(); return; }
                float k = Theme.Animations ? 0.30f : 1f;
                _hover += dh * k; _press += dp * k; _focus += df * k;
                Invalidate();
            };
        }

        private void Kick()
        {
            if (!Theme.Animations) {
                _hover = _hovering ? 1f : 0f;
                _press = _pressing ? 1f : 0f;
                _focus = Focused ? 1f : 0f;
                Invalidate(); return;
            }
            if (!_anim.Enabled) _anim.Start();
        }

        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hovering = true;  Kick(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hovering = false; _pressing = false; Kick(); }
        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); _pressing = true;  Focus(); Kick(); }
        protected override void OnMouseUp(MouseEventArgs e)   { base.OnMouseUp(e);   _pressing = false; Kick(); }
        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Kick(); Invalidate(); }
        protected override void OnLostFocus(EventArgs e){ base.OnLostFocus(e); Kick(); Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e){ base.OnEnabledChanged(e); Invalidate(); }

        protected override bool IsInputKey(Keys k)
        {
            return k == Keys.Space || k == Keys.Enter || base.IsInputKey(k);
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { _pressing = true; Kick(); e.Handled = true; }
            base.OnKeyDown(e);
        }

        protected override void OnKeyUp(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter)
            {
                _pressing = false; Kick();
                if (Enabled && Focused) PerformClick();
                e.Handled = true;
            }
            base.OnKeyUp(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Setup(g);
            PaintBack(g);
            var r = new Rectangle(0, 0, Width - 1, Height - 1);

            Color fill, edge, txt;
            bool emphasis = false;

            if (Variant == BtnVariant.Primary)
            {
                fill = Blend(Color.FromArgb(20, 130, 240), Theme.Cyan, (int)(_hover * 70));
                edge = Theme.Cyan; txt = Color.White; emphasis = true;
            }
            else if (Variant == BtnVariant.Danger)
            {
                fill = Blend(Color.FromArgb(56, 22, 28), Theme.Danger, (int)(_hover * 60));
                edge = Theme.Danger; txt = Theme.Danger; emphasis = true;
            }
            else if (Selected)
            {
                fill = Blend(Color.FromArgb(17, 44, 66), Theme.Cyan, (int)(_hover * 40));
                edge = Theme.Cyan; txt = Theme.Text; emphasis = true;
            }
            else
            {
                fill = Blend(Theme.Surface, Color.White, (int)(_hover * 10));
                edge = Theme.Border;
                txt = Blend(Theme.TextMuted, Theme.Text, (int)(_hover * 160));
            }

            if (_press > 0f)
            {
                fill = Blend(fill, Color.Black, (int)(_press * 45));
                txt  = Blend(txt, Color.White, (int)(_press * 60));
            }

            if (!Enabled)
            {
                fill = Blend(Theme.Surface, Theme.Bg, 140);
                edge = Theme.BorderSoft;
                txt  = Theme.TextDim;
                emphasis = false;
            }

            using (var p = Theme.Rounded(r, Radius))
            {
                if (emphasis) Theme.Glow(g, p, Variant == BtnVariant.Primary ? Theme.Blue : edge, Radius, Enabled ? 90 : 0);
                using (var b = new SolidBrush(fill)) g.FillPath(b, p);
                using (var pen = new Pen(edge, emphasis ? 1.4f : 1f)) g.DrawPath(pen, p);
            }

            // Keyboard focus ring: doubled inset so it reads on any fill.
            if (_focus > 0f)
            {
                var fr = new Rectangle(2, 2, Math.Max(1, r.Width - 4), Math.Max(1, r.Height - 4));
                using (var p2 = Theme.Rounded(fr, Math.Max(2, Radius - 2)))
                using (var pen = new Pen(Color.FromArgb((int)(210 * _focus), Theme.Cyan), 1.6f))
                    g.DrawPath(pen, p2);
            }

            if (SymbolOnly) { DrawSymbol(g, r, txt); return; }

            using (var font = Theme.UiSemibold(9.75f))
            using (var b = new SolidBrush(txt))
            using (var fmt = Theme.Center())
                g.DrawString(Caption, font, b, r, fmt);
        }

        private void DrawSymbol(Graphics g, Rectangle r, Color txt)
        {
            float cx = r.X + r.Width / 2f, cy = r.Y + r.Height / 2f;
            float s = Math.Min(r.Width, r.Height) * 0.2f;
            using (var pen = new Pen(txt, 2f) {
                StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
            {
                if (Symbol == 1) g.DrawLine(pen, cx - s, cy, cx + s, cy);
                if (Symbol == 2)
                {
                    g.DrawLine(pen, cx - s, cy, cx + s, cy);
                    g.DrawLine(pen, cx, cy - s, cx, cy + s);
                }
                if (Symbol == 3)
                    g.DrawLines(pen, new PointF[] {
                        new PointF(cx - s, cy), new PointF(cx - s * 0.25f, cy + s * 0.8f), new PointF(cx + s, cy - s * 0.9f) });
            }
        }

        public static Color Blend(Color a, Color b, int amount)
        {
            if (amount <= 0) return a;
            if (amount >= 255) return b;
            return Color.FromArgb(
                a.A + (b.R - a.A) * amount / 255,
                a.R + (b.R - a.R) * amount / 255,
                a.G + (b.G - a.G) * amount / 255,
                a.B + (b.B - a.B) * amount / 255);
        }
    }

    /// <summary>Circular timer with glow and a tabular centre readout.</summary>
    public class Ring : SurfaceControl
    {
        private double _value, _shown;
        private Timer _anim;

        public double Value {
            get { return _value; }
            set { _value = Math.Max(0, Math.Min(1, value)); Kick(); }
        }
        public string CenterBig = "";
        public string CenterSmall = "";
        public Color Accent = Theme.Cyan;
        public Color Track = Theme.BorderSoft;
        public float Thickness = 7f;

        public Ring()
        {
            _anim = new Timer();
            _anim.Interval = Theme.Animations ? 33 : 100;
            _anim.Tick += delegate {
                double d = _value - _shown;
                if (Math.Abs(d) < 0.002) { _anim.Stop(); return; }
                _shown += d * (Theme.Animations ? 0.25 : 1.0);
                Invalidate();
            };
        }

        private void Kick()
        {
            if (!Theme.Animations) { _shown = _value; Invalidate(); return; }
            if (!_anim.Enabled) _anim.Start();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Setup(g);
            PaintBack(g);
            float pad = Thickness + 3f;
            float d = Math.Min(Width, Height) - pad * 2f;
            if (d <= 8) return;
            var box = new RectangleF((Width - d) / 2f, (Height - d) / 2f, d, d);

            using (var pen = new Pen(Track, Thickness) {
                StartCap = LineCap.Round, EndCap = LineCap.Round })
                g.DrawEllipse(pen, box);

            double frac = _shown;
            if (frac > 0.0001)
            {
                float sweep = (float)(360.0 * frac);
                using (var glow = new Pen(Color.FromArgb(38, Accent), Thickness + 7f) {
                    StartCap = LineCap.Round, EndCap = LineCap.Round })
                    g.DrawArc(glow, box, -90f, sweep);
                using (var glow2 = new Pen(Color.FromArgb(70, Accent), Thickness + 3f) {
                    StartCap = LineCap.Round, EndCap = LineCap.Round })
                    g.DrawArc(glow2, box, -90f, sweep);
                using (var pen = new Pen(Accent, Thickness) {
                    StartCap = LineCap.Round, EndCap = LineCap.Round })
                    g.DrawArc(pen, box, -90f, sweep);

                if (frac < 0.999)
                {
                    double ang = (-90f + sweep) * Math.PI / 180.0;
                    float hx = box.X + box.Width / 2f + (float)(Math.Cos(ang) * d / 2.0);
                    float hy = box.Y + box.Height / 2f + (float)(Math.Sin(ang) * d / 2.0);
                    using (var b = new SolidBrush(Color.FromArgb(230, 250, 253)))
                        g.FillEllipse(b, hx - 2.4f, hy - 2.4f, 4.8f, 4.8f);
                }
            }

            if (CenterBig != "")
            {
                using (var fb = Theme.Num(17f, FontStyle.Bold))
                using (var b = new SolidBrush(Theme.Text))
                using (var fmt = Theme.Center())
                    g.DrawString(CenterBig, fb, b,
                        new RectangleF(box.X, box.Y + d * 0.22f, d, d * 0.34f), fmt);

                if (CenterSmall != "")
                {
                    using (var fs = Theme.Ui(7.5f, FontStyle.Regular))
                    using (var b = new SolidBrush(Theme.TextDim))
                    using (var fmt = Theme.Center())
                        g.DrawString(CenterSmall, fs, b,
                            new RectangleF(box.X, box.Y + d * 0.55f, d, d * 0.20f), fmt);
                }
            }
        }
    }
}
'@ | Out-Null
}

[NW.Theme]::DetectReducedMotion()

# ==================================================================
# Layout constants
# ==================================================================
$script:FORM_W = 468
$script:BTN_H  = 42
$script:RADIUS = 12

# ==================================================================
# Layout helpers
# ==================================================================
function New-BaseForm {
    param([string]$Title, [int]$Height)
    $f = New-Object System.Windows.Forms.Form
    $f.Text = $Title
    $f.ClientSize = New-Object System.Drawing.Size($script:FORM_W, $Height)
    $f.StartPosition = "CenterScreen"
    $f.FormBorderStyle = "FixedDialog"
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.TopMost = $true
    $f.BackColor = [NW.Theme]::Bg
    $f.ForeColor = [NW.Theme]::Text
    # Critical: without this, Windows rescales every coordinate on a
    # non-100% DPI display and controls end up overlapping or misaligned.
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $f.ShowInTaskbar = $false
    return $f
}

function New-Grid {
    param([int]$Cols = 1, [int]$Rows = 0)
    $t = New-Object System.Windows.Forms.TableLayoutPanel
    $t.Dock = "Fill"
    $t.ColumnCount = $Cols
    $t.RowCount = $Rows
    $t.BackColor = [System.Drawing.Color]::Transparent
    $t.Margin = New-Object System.Windows.Forms.Padding(0)
    for ($i = 0; $i -lt $Cols; $i++) {
        $t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, [single](100 / $Cols)))) | Out-Null
    }
    return $t
}

function Add-Row {
    param($Stack, [string]$Type = "Auto", $Value = 0)
    switch ($Type) {
        "Abs"  { $Stack.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, [single]$Value))) | Out-Null }
        "Fill" { $Stack.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null }
        default{ $Stack.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null }
    }
    $Stack.RowCount = $Stack.RowStyles.Count
    return $Stack.RowCount - 1
}

function Add-Col {
    param($Grid, [string]$Type = "Abs", $Value = 0)
    switch ($Type) {
        "Abs"  { $Grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, [single]$Value))) | Out-Null }
        "Fill" { $Grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null }
        default{ $Grid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize))) | Out-Null }
    }
    return $Grid.ColumnStyles.Count - 1
}

# Vertical text stack: AutoSize rows only (spacing comes from label margins),
# with Percent-100 spacers top and bottom so the block sits centred.
function New-VStack {
    param($ParentGrid, [int]$Col = 0)
    $t = New-Grid 1
    $ParentGrid.Controls.Add($t, $Col, 0) | Out-Null
    [void](Add-Row $t "Fill")
    return $t
}

function New-Label {
    param($Text, [float]$Size, $Color, [bool]$Bold = $false, [int]$BottomMargin = 0, [int]$WrapWidth = 0)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $style = if ($Bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $l.Font = New-Object System.Drawing.Font("Segoe UI", $Size, $style)
    $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.AutoSize = $true
    $l.Dock = "Fill"
    $l.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
    $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, $BottomMargin)
    # Without an upper bound an AutoSize label runs off the edge of its
    # column and gets clipped. Wrapping keeps every line inside the card.
    if ($WrapWidth -gt 0) {
        $l.MaximumSize = New-Object System.Drawing.Size($WrapWidth, 0)
    }
    return $l
}

function Add-Text {
    param($Stack, $Text, [float]$Size, $Color, [bool]$Bold = $false, [int]$BottomMargin = 0, [int]$WrapWidth = 0)
    $r = Add-Row $Stack
    $Stack.Controls.Add((New-Label $Text $Size $Color $Bold $BottomMargin $WrapWidth), 0, $r) | Out-Null
}

function Add-Accent {
    param($Stack, $Text, [float]$Size = 11.5, $Color = $null, [int]$BottomMargin = 0, [int]$WrapWidth = 0)
    if (-not $Color) { $Color = [NW.Theme]::Cyan }
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Font = [NW.Theme]::UiSemibold($Size)
    $l.ForeColor = $Color
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.AutoSize = $true
    $l.Dock = "Fill"
    $l.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
    $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, $BottomMargin)
    if ($WrapWidth -gt 0) {
        $l.MaximumSize = New-Object System.Drawing.Size($WrapWidth, 0)
    }
    $r = Add-Row $Stack
    $Stack.Controls.Add($l, 0, $r) | Out-Null
    return $l
}

function New-NWButton {
    param(
        [string]$Caption,
        [string]$Variant = "Ghost",
        $Accent = $null,
        [int]$Symbol = 0,
        [switch]$SymbolOnly,
        [int]$MarginRight = 0,
        [int]$MarginLeft = 0
    )
    $b = New-Object NW.NWButton
    $b.Dock = "Fill"
    $b.Caption = $Caption
    $b.Variant = [NW.BtnVariant]::$Variant
    $b.Symbol = $Symbol
    $b.SymbolOnly = [bool]$SymbolOnly
    $b.Radius = $script:RADIUS
    if ($Accent) { $b.Accent = $Accent }
    $b.Font = [NW.Theme]::UiSemibold(9.75)
    $b.Margin = New-Object System.Windows.Forms.Padding($MarginLeft, 0, $MarginRight, 0)
    # Buttons sit on transparent grids over Theme.Bg. Paint that background
    # ourselves so the rounded corners never fall back to a black block.
    $b.BackFill = [NW.Theme]::Bg
    return $b
}

function New-Header {
    param($Parent, [string]$Chip, $ChipColor)

    $band = New-Object NW.HeaderBand
    $band.Dock = "Fill"
    $band.Margin = New-Object System.Windows.Forms.Padding(0)

    $inner = New-Grid 3
    $inner.ColumnStyles.Clear()
    [void](Add-Col $inner "Abs" 42)
    [void](Add-Col $inner "Fill")
    [void](Add-Col $inner "Abs" 124)
    $inner.Margin = New-Object System.Windows.Forms.Padding(22, 0, 22, 0)
    $r = Add-Row $inner "Fill"

    $em = New-Object NW.Emblem
    $em.Dock = "Fill"
    $em.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)
    $em.AccessibleName = "NightWatch"

    $txt = New-Object System.Windows.Forms.TableLayoutPanel
    $txt.Dock = "Fill"
    $txt.ColumnCount = 1
    $txt.RowCount = 2
    $txt.BackColor = [System.Drawing.Color]::Transparent
    $txt.Margin = New-Object System.Windows.Forms.Padding(0)
    [void]$txt.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$txt.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 60)))
    [void]$txt.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 40)))

    $t1 = New-Object System.Windows.Forms.Label
    $t1.Text = "NIGHTWATCH"
    $t1.Font = [NW.Theme]::UiSemibold(13)
    $t1.ForeColor = [NW.Theme]::Text
    $t1.BackColor = [System.Drawing.Color]::Transparent
    $t1.AutoSize = $false
    $t1.Dock = "Fill"
    $t1.TextAlign = [System.Drawing.ContentAlignment]::BottomLeft
    $t1.Margin = New-Object System.Windows.Forms.Padding(0)

    $t2 = New-Object System.Windows.Forms.Label
    $t2.Text = "study-break sentinel"
    $t2.Font = [NW.Theme]::Ui(8.5, [System.Drawing.FontStyle]::Regular)
    $t2.ForeColor = [NW.Theme]::TextDim
    $t2.BackColor = [System.Drawing.Color]::Transparent
    $t2.AutoSize = $false
    $t2.Dock = "Fill"
    $t2.TextAlign = [System.Drawing.ContentAlignment]::TopLeft
    $t2.Margin = New-Object System.Windows.Forms.Padding(0)

    $txt.Controls.Add($t1, 0, 0) | Out-Null
    $txt.Controls.Add($t2, 0, 1) | Out-Null
    $inner.Controls.Add($em, 0, 0) | Out-Null
    $inner.Controls.Add($txt, 1, 0) | Out-Null

    if ($Chip) {
        $chipLbl = New-Object System.Windows.Forms.Label
        $chipLbl.Text = $Chip
        $chipLbl.Font = [NW.Theme]::UiSemibold(8)
        $chipLbl.ForeColor = $ChipColor
        $chipLbl.BackColor = [System.Drawing.Color]::Transparent
        $chipLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
        $chipLbl.Dock = "Fill"
        $chipLbl.AutoSize = $false
        $chipLbl.Margin = New-Object System.Windows.Forms.Padding(0)
        $inner.Controls.Add($chipLbl, 2, 0) | Out-Null
    }

    $band.Controls.Add($inner) | Out-Null
    $Parent.Controls.Add($band, 0, $r) | Out-Null
    return $band
}

# ==================================================================
# The timing card: ring on the left, kicker/time/relative/footnote on the
# right. One implementation, reused by every dialog, so the six call sites
# cannot drift apart.
# ==================================================================
function New-TimingCard {
    param(
        [string]$Kicker,
        [string]$TimeText,
        [string]$RelText,
        [string]$FootText,
        $Tint,
        [string]$RingBig,
        [string]$RingSmall,
        [double]$RingValue = 1.0,
        [int]$Height = 128
    )

    $card = New-Object NW.Card
    $card.Dock = "Fill"
    $card.Radius = 16
    $card.Margin = New-Object System.Windows.Forms.Padding(0)
    $card.GlowStrength = 120
    $card.GlowColor = $Tint
    # The card has rounded corners, so the area outside them has to be painted
    # with whatever is behind the card (Theme.Bg) or the corners go square and
    # black. The timing card always sits on a Theme.Bg panel.
    $card.BackFill = [NW.Theme]::Bg

    $grid = New-Grid 2
    $grid.ColumnStyles.Clear()
    [void](Add-Col $grid "Abs" 106)
    [void](Add-Col $grid "Fill")
    # Opaque, not transparent: a transparent child forces WinForms to repaint
    # every ancestor's background into it on every invalidate, which is
    # measurably slower (see the paint profiling in the PR).
    $grid.BackColor = [NW.Theme]::Surface
    $grid.Margin = New-Object System.Windows.Forms.Padding(18, 15, 18, 15)
    [void](Add-Row $grid "Fill")

    $ring = New-Object NW.Ring
    $ring.Dock = "Fill"
    $ring.Margin = New-Object System.Windows.Forms.Padding(0, 0, 16, 0)
    $ring.Accent = $Tint
    $ring.Thickness = 7
    # Paint the card's own surface behind the ring. Relying on the ring's
    # transparent background instead produced an intermittent black block
    # behind the countdown on a live window.
    $ring.BackFill = $card.Fill
    $ring.CenterBig = $RingBig
    $ring.CenterSmall = $RingSmall
    $ring.Value = $RingValue
    $ring.AccessibleName = "Duration timer"

    $txt = New-VStack $grid 1
    # Leave room for the ring column, the card padding and a little slack, so
    # the footnote wraps instead of running under the card edge on wide-DPI
    # setups where the point-sized fonts render larger.
    $wrapW = $script:FORM_W - 44 - 106 - 16 - 36 - 8
    Add-Text $txt $Kicker 8 ([NW.Theme]::TextDim) $true 5 $wrapW
    $timeLbl = Add-Accent $txt $TimeText 15 $Tint 3 $wrapW
    Add-Text $txt $RelText 9 ([NW.Theme]::TextMuted) $false 0 $wrapW
    Add-Text $txt $FootText 8.5 ([NW.Theme]::TextDim) $false 0 $wrapW
    [void](Add-Row $txt "Fill")

    $grid.Controls.Add($ring, 0, 0) | Out-Null
    $card.Controls.Add($grid) | Out-Null

    # Script-visible handles so callers can drive the live countdown.
    $card | Add-Member -NotePropertyName Ring -NotePropertyValue $ring -Force
    $card | Add-Member -NotePropertyName TimeLabel -NotePropertyValue $timeLbl -Force
    return $card
}

# ==================================================================
# Picker helpers - script scope on purpose.
#
# WinForms runs these handlers long after New-PickerForm has returned, so
# its local scope is gone. A handler that touches a local ($errLabel,
# $btnStart, $card) gets $null and throws, and a helper *function* declared
# inside the function cannot be resolved at all. Both failure modes are
# silent unless you look: the caption sticks on the old value, the primary
# button stays enabled over invalid input, and the clock timer throws once
# a second. Hence: state in $script:Pk, functions declared here.
# ==================================================================
function Sync-Timing {
    param([int]$Minutes, [bool]$Custom)
    $end = $script:BaseTime.AddMinutes($Minutes)
    $tint = if ($Custom) { [NW.Theme]::Blue } else { [NW.Theme]::Cyan }
    $script:Pk.Card.Ring.CenterBig = [string]$Minutes
    $script:Pk.Card.Ring.Value = [Math]::Max(0.06, [Math]::Min(1.0, [double]($Minutes / 120.0)))
    $script:Pk.Card.Ring.Accent = $tint
    $script:Pk.Card.GlowColor = $tint
    $script:Pk.Card.TimeLabel.Text = $end.ToString("HH:mm:ss")
    $script:Pk.Card.TimeLabel.ForeColor = $tint
}

function Sync-Action {
    param([int]$Minutes)
    $script:Pk.Start.Caption = if ($Minutes -eq 1) { "Start 1-minute break" } else { "Start $Minutes-minute break" }
    $script:Pk.Start.Enabled = ($Minutes -ge 1 -and $Minutes -le 1440)
}

function Sync-Picker {
    param([int]$Minutes, [bool]$Custom)
    Sync-Timing -Minutes $Minutes -Custom $Custom
    Sync-Action -Minutes $Minutes
}

function Set-Custom {
    param([int]$Delta)
    $cur = 0
    [void][int]::TryParse($script:Pk.Num.Text, [ref]$cur)
    $next = $cur + $Delta
    if ($next -lt 1) { $next = 1 }
    if ($next -gt 1440) { $next = 1440 }
    $script:Pk.Num.Text = [string]$next
}

# ==================================================================
# Duration picker
# ==================================================================
function New-PickerForm {
    $form = New-BaseForm -Title "NightWatch - Study Break" -Height 528
    $outer = New-Grid 1
    $outer.BackColor = [NW.Theme]::Bg
    $form.Controls.Add($outer) | Out-Null

    [void](Add-Row $outer "Abs" 70)
    New-Header $outer "STANDBY" ([NW.Theme]::TextDim) | Out-Null

    $pad = New-Grid 1
    $pad.BackColor = [NW.Theme]::Bg
    $pad.Padding = New-Object System.Windows.Forms.Padding(22, 18, 22, 16)
    [void](Add-Row $outer "Fill")
    $outer.Controls.Add($pad, 0, 1) | Out-Null

    # Title
    $r = Add-Row $pad
    $title = New-Object System.Windows.Forms.Label
    $title.Text = "How long is your break?"
    $title.Font = [NW.Theme]::UiSemibold(13.5)
    $title.ForeColor = [NW.Theme]::Text
    $title.BackColor = [System.Drawing.Color]::Transparent
    $title.AutoSize = $true
    $title.Dock = "Fill"
    $title.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 5)
    $pad.Controls.Add($title, 0, $r) | Out-Null

    $r = Add-Row $pad
    $pad.Controls.Add((New-Label "Auto-shutdown pauses for exactly this long, then re-arms by itself." 8.75 ([NW.Theme]::TextDim) $false 0), 0, $r) | Out-Null
    $r = Add-Row $pad "Abs" 16

    # Timing card
    $card = New-TimingCard -Kicker "PROTECTION PAUSED" -TimeText "22:21:24" `
        -RelText "30 minutes from now" -FootText "Re-arms automatically when the break ends" `
        -Tint ([NW.Theme]::Cyan) -RingBig "30" -RingSmall "MINUTES" -RingValue 0.25
    $r = Add-Row $pad "Abs" 128
    $pad.Controls.Add($card, 0, $r) | Out-Null

    # Presets
    $r = Add-Row $pad "Abs" 16
    $presets = @(15, 30, 40, 60)
    $presetRow = New-Grid $presets.Count
    $presetRow.RowStyles.Clear()
    [void](Add-Row $presetRow "Fill")
    $r = Add-Row $pad "Abs" 44
    $pad.Controls.Add($presetRow, 0, $r) | Out-Null

    $presetButtons = @()
    for ($i = 0; $i -lt $presets.Count; $i++) {
        $b = New-NWButton -Caption "$($presets[$i]) min" -MarginLeft $(if ($i -eq 0) { 0 } else { 8 })
        $b.Tag = $presets[$i]
        $b.Selected = ($presets[$i] -eq 30)
        $b.AccessibleName = "Take a $($presets[$i]) minute study break"
        $presetButtons += $b
        $presetRow.Controls.Add($b, $i, 0) | Out-Null
    }

    # Custom duration
    $r = Add-Row $pad "Abs" 18
    $orLbl = New-Label "OR SET A CUSTOM DURATION" 8 ([NW.Theme]::TextDim) $true 0
    $pad.Controls.Add($orLbl, 0, $r) | Out-Null

    $r = Add-Row $pad "Abs" 40
    $customRow = New-Grid 3
    $customRow.ColumnStyles.Clear()
    [void](Add-Col $customRow "Abs" 40)
    [void](Add-Col $customRow "Fill")
    [void](Add-Col $customRow "Abs" 40)
    [void](Add-Row $customRow "Fill")
    $pad.Controls.Add($customRow, 0, $r) | Out-Null

    $btnMinus = New-NWButton -Variant "Ghost" -Symbol 1 -SymbolOnly -MarginRight 8
    $btnMinus.AccessibleName = "Decrease duration by one minute"
    $field = New-Object NW.Card
    $field.Dock = "Fill"
    $field.Radius = 10
    $field.Margin = New-Object System.Windows.Forms.Padding(0)

    $num = New-Object System.Windows.Forms.TextBox
    $num.Dock = "Fill"
    $num.Text = "30"
    $num.TextAlign = [System.Windows.Forms.HorizontalAlignment]::Center
    $num.Font = [NW.Theme]::Num(11.5, [System.Drawing.FontStyle]::Regular)
    $num.ForeColor = [NW.Theme]::Text
    # TextBox cannot be transparent; match the card fill behind it.
    $num.BackColor = [NW.Theme]::Surface
    $num.BorderStyle = "None"
    $num.MaxLength = 6
    $num.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
    $num.AccessibleName = "Custom break duration in minutes, from 1 to 1440"
    $field.Controls.Add($num) | Out-Null

    $btnPlus = New-NWButton -Variant "Ghost" -Symbol 2 -SymbolOnly -MarginLeft 8
    $btnPlus.AccessibleName = "Increase duration by one minute"

    $customRow.Controls.Add($btnMinus, 0, 0) | Out-Null
    $customRow.Controls.Add($field, 1, 0) | Out-Null
    $customRow.Controls.Add($btnPlus, 2, 0) | Out-Null

    $r = Add-Row $pad "Abs" 20
    $errLabel = New-Label "" 8.5 ([NW.Theme]::Danger) $false 0
    $pad.Controls.Add($errLabel, 0, $r) | Out-Null

    # Footer
    [void](Add-Row $pad "Fill")
    $r = Add-Row $pad "Abs" $script:BTN_H
    $actionRow = New-Grid 2
    $actionRow.ColumnStyles.Clear()
    [void](Add-Col $actionRow "Abs" 96)
    [void](Add-Col $actionRow "Fill")
    [void](Add-Row $actionRow "Fill")
    $pad.Controls.Add($actionRow, 0, $r) | Out-Null

    $btnCancel = New-NWButton -Caption "Cancel" -MarginRight 8
    $btnStart = New-NWButton -Caption "Start 30-minute break" -Variant "Primary" -Accent ([NW.Theme]::Cyan)
    $btnStart.Font = [NW.Theme]::UiSemibold(10)
    $btnStart.AccessibleName = "Start the study break"
    $actionRow.Controls.Add($btnCancel, 0, 0) | Out-Null
    $actionRow.Controls.Add($btnStart, 1, 0) | Out-Null

    # --- selection wiring ---
    $script:ChosenMinutes = 30
    $script:UsingCustom = $false
    $script:BaseTime = Get-Date

    # ------------------------------------------------------------------
    # SCOPING
    #
    # WinForms invokes these handlers long after New-PickerForm has returned,
    # at which point its local scope is gone. A handler that references a
    # local ($errLabel, $btnStart, Sync-Picker) resolves to $null and throws.
    # That is not cosmetic: it silently left the caption stuck on the last
    # preset, left the primary button enabled over invalid input, and threw
    # every second from the clock timer - which is what made the window feel
    # frozen. Everything a handler needs therefore lives in script scope.
    # ------------------------------------------------------------------
    $script:Pk = @{
        Card    = $card
        Num     = $num
        Err     = $errLabel
        Start   = $btnStart
        Presets = $presetButtons
        Form    = $form
    }

    # NO GetNewClosure() here. A closure gets its own scope, so $script:Pk
    # inside it resolves to null and every control access throws - while a
    # plain function call like Sync-Picker still works, which makes the
    # failure look partial and random. $this.Tag carries the preset value
    # instead, since WinForms binds $this to the sender.
    foreach ($b in $presetButtons) {
        $b.Add_Click({
            $val = [int]$this.Tag
            $script:ChosenMinutes = $val
            $script:UsingCustom = $false
            $script:Pk.Num.Text = [string]$val
            $script:Pk.Err.Text = ""
            foreach ($pb in $script:Pk.Presets) { $pb.Selected = ([int]$pb.Tag -eq $val) }
            Sync-Picker -Minutes $val -Custom $false
        })
    }

    $btnMinus.Add_Click({ Set-Custom -Delta -1 })
    $btnPlus.Add_Click({ Set-Custom -Delta 1 })

    # Live validation: never silently accept an out-of-range value.
    $num.Add_TextChanged({
        $v = 0
        $ok = [int]::TryParse($script:Pk.Num.Text, [ref]$v) -and $v -ge 1 -and $v -le 1440
        $script:UsingCustom = $true
        foreach ($pb in $script:Pk.Presets) { $pb.Selected = $false }
        if (-not $ok) {
            if ([string]::IsNullOrWhiteSpace($script:Pk.Num.Text)) {
                $script:Pk.Err.Text = ""
            } else {
                $script:Pk.Err.Text = "Enter a whole number from 1 to 1440."
            }
            $script:Pk.Start.Enabled = $false
            return
        }
        $script:Pk.Err.Text = ""
        $script:ChosenMinutes = $v
        Sync-Picker -Minutes $v -Custom $true
    })

    $btnCancel.Add_Click({ $script:ChosenMinutes = 0; $script:Pk.Form.Close() })

    $btnStart.Add_Click({
        $v = 0
        if (-not [int]::TryParse($script:Pk.Num.Text, [ref]$v) -or $v -lt 1 -or $v -gt 1440) {
            $script:Pk.Err.Text = "Enter a whole number from 1 to 1440."
            $script:Pk.Num.Focus()
            return
        }
        $script:ChosenMinutes = $v
        $script:Pk.Form.Close()
    })

    # Keep the on-screen end time honest against the wall clock.
    # Timing only - never touch the action state or the ring value here, or
    # this timer would restart the ring animation every second.
    $clock = New-Object System.Windows.Forms.Timer
    $clock.Interval = 1000
    $clock.Add_Tick({
        $script:BaseTime = Get-Date
        Sync-Timing -Minutes ([int]$script:ChosenMinutes) -Custom $script:UsingCustom
    })

    $form.AcceptButton = $btnStart
    $form.CancelButton = $btnCancel
    $script:Pk.Form = $form

    Sync-Picker -Minutes 30 -Custom $false
    $form | Add-Member -NotePropertyName Clock -NotePropertyValue $clock -Force
    # Exposed so -SelfCheck can drive the real controls instead of guessing.
    $form | Add-Member -NotePropertyName Presets -NotePropertyValue $presetButtons -Force
    $form | Add-Member -NotePropertyName StartButton -NotePropertyValue $btnStart -Force
    $form | Add-Member -NotePropertyName NumBox -NotePropertyValue $num -Force
    $form | Add-Member -NotePropertyName ErrLabel -NotePropertyValue $errLabel -Force
    $form | Add-Member -NotePropertyName Card -NotePropertyValue $card -Force
    return $form
}

# ==================================================================
# Active break (live countdown)
# ==================================================================
function New-ActiveForm {
    param([DateTime]$ExpiresAt, [int]$TotalMinutes)

    $form = New-BaseForm -Title "NightWatch" -Height 340
    $outer = New-Grid 1
    $outer.BackColor = [NW.Theme]::Bg
    $form.Controls.Add($outer) | Out-Null

    [void](Add-Row $outer "Abs" 70)
    New-Header $outer "BREAK ACTIVE" ([NW.Theme]::Success) | Out-Null

    $pad = New-Grid 1
    $pad.BackColor = [NW.Theme]::Bg
    $pad.Padding = New-Object System.Windows.Forms.Padding(22, 18, 22, 18)
    [void](Add-Row $outer "Fill")
    $outer.Controls.Add($pad, 0, 1) | Out-Null

    $r = Add-Row $pad
    $h = New-Object System.Windows.Forms.Label
    $h.Text = "You're on a break"
    $h.Font = [NW.Theme]::UiSemibold(13.5)
    $h.ForeColor = [NW.Theme]::Text
    $h.BackColor = [System.Drawing.Color]::Transparent
    $h.AutoSize = $true
    $h.Dock = "Fill"
    $h.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
    $pad.Controls.Add($h, 0, $r) | Out-Null

    $total = [Math]::Max(1, $TotalMinutes)
    $card = New-TimingCard -Kicker "BREAK ENDS AT" -TimeText $ExpiresAt.ToString("HH:mm:ss") `
        -RelText "of a $total minute break" -FootText "Auto-shutdown stays paused until then" `
        -Tint ([NW.Theme]::Success) -RingBig "0" -RingSmall "MIN LEFT" -RingValue 1.0
    $r = Add-Row $pad "Abs" 128
    $pad.Controls.Add($card, 0, $r) | Out-Null

    [void](Add-Row $pad "Fill")
    $r = Add-Row $pad "Abs" $script:BTN_H
    $split = New-Grid 2
    [void](Add-Row $split "Fill")
    $pad.Controls.Add($split, 0, $r) | Out-Null

    $btnKeep = New-NWButton -Caption "Keep break" -MarginRight 8
    $btnEnd  = New-NWButton -Caption "End break now" -Variant "Danger" -Accent ([NW.Theme]::Danger) -MarginLeft 8
    $split.Controls.Add($btnKeep, 0, 0) | Out-Null
    $split.Controls.Add($btnEnd, 1, 0) | Out-Null

    $script:EndNow = $false
    $script:Act = @{ Card = $card; Form = $form }
    $btnKeep.Add_Click({ $script:EndNow = $false; $script:Act.Form.Close() })
    $btnEnd.Add_Click({  $script:EndNow = $true;  $script:Act.Form.Close() })

    $script:endInstant = $ExpiresAt
$script:totalM = $total

    # One update routine, invoked once up front and then on every tick, so the
    # first painted frame already shows the real remaining time.
    $update = {
        $left = $script:endInstant - (Get-Date)
        if ($left.TotalSeconds -lt 0) { $left = [TimeSpan]::Zero }
        $mins = [int][Math]::Ceiling($left.TotalMinutes)
        if ($mins -lt 0) { $mins = 0 }
        $script:Act.Card.Ring.CenterBig = [string]$mins
        # NOTE: 0.0/1.0 must stay doubles. PowerShell resolves [Math]::Min(1, x)
        # to Min(int,int) and rounds x to an int, pinning the ring at full.
        $frac = $left.TotalMinutes / $script:totalM
        $script:Act.Card.Ring.Value = [Math]::Max(0.0, [Math]::Min(1.0, [double]$frac))
        $script:Act.Card.TimeLabel.Text = $script:endInstant.ToString("HH:mm:ss")
    }

    # Same scoping trap as the picker: this timer outlives the function, so
    # the card must live in script scope or every tick would throw.

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250
    $timer.Add_Tick($update)
    & $update

    $form.AcceptButton = $btnKeep
    $form.CancelButton = $btnKeep
    $form | Add-Member -NotePropertyName Timer -NotePropertyValue $timer -Force
    $form | Add-Member -NotePropertyName KeepButton -NotePropertyValue $btnKeep -Force
    $form | Add-Member -NotePropertyName Card -NotePropertyValue $card -Force
    return $form
}

# ==================================================================
# Status card (break started / protection re-armed)
# ==================================================================
function New-StatusForm {
    param(
        [string]$Kicker,
        [string]$Headline,
        [string]$Detail,
        [string]$TimeLine,
        [string]$FootNote,
        $Tint,
        [string]$RingBig,
        [string]$ButtonText
    )

    $form = New-BaseForm -Title "NightWatch" -Height 316
    $outer = New-Grid 1
    $outer.BackColor = [NW.Theme]::Bg
    $form.Controls.Add($outer) | Out-Null

    [void](Add-Row $outer "Abs" 70)
    New-Header $outer $Kicker $Tint | Out-Null

    $pad = New-Grid 1
    $pad.BackColor = [NW.Theme]::Bg
    $pad.Padding = New-Object System.Windows.Forms.Padding(22, 20, 22, 20)
    [void](Add-Row $outer "Fill")
    $outer.Controls.Add($pad, 0, 1) | Out-Null

    $r = Add-Row $pad "Abs" 20
    $hl = New-Object System.Windows.Forms.Label
    $hl.Text = $Headline
    $hl.Font = [NW.Theme]::UiSemibold(13.5)
    $hl.ForeColor = [NW.Theme]::Text
    $hl.BackColor = [System.Drawing.Color]::Transparent
    $hl.AutoSize = $true
    $hl.Dock = "Fill"
    $hl.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
    $pad.Controls.Add($hl, 0, $r) | Out-Null

    $r = Add-Row $pad "Abs" 132
    $card = New-TimingCard -Kicker "AUTO-OFF AT" -TimeText $TimeLine -RelText $Detail `
        -FootText $FootNote -Tint $Tint -RingBig $RingBig -RingSmall "MIN" -RingValue 1.0 -Height 132
    $pad.Controls.Add($card, 0, $r) | Out-Null

    [void](Add-Row $pad "Fill")
    $r = Add-Row $pad "Abs" $script:BTN_H
    $btn = New-NWButton -Caption $ButtonText -Variant "Primary" -Accent $Tint
    $btn.Font = [NW.Theme]::UiSemibold(10)
    # $form is a local of this function, and by the time the click lands that
    # scope is gone: { $form.Close() } resolves $form to $null, throws
    # "You cannot call a method on a null-valued expression", and the window
    # never closes. Verified against WinForms, not assumed. This matches how
    # New-PickerForm and New-ActiveForm already reach their form.
    $script:St = $form
    $btn.Add_Click({ $script:St.Close() })
    $pad.Controls.Add($btn, 0, $r) | Out-Null

    $form.AcceptButton = $btn
    $form.CancelButton = $btn
    return $form
}

# ==================================================================
# -SelfTest: render the real dialogs to PNG
# ==================================================================
function Invoke-SelfTest {
    $dir = if ($OutDir) { $OutDir } else { $env:TEMP }
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    function Dump($form, $name) {
        $form.StartPosition = "Manual"
        $form.Location = New-Object System.Drawing.Point(0, 0)
        $form.TopMost = $false
        $form.ShowInTaskbar = $false
        $form.Show()
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 500
        [System.Windows.Forms.Application]::DoEvents()
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $p = Join-Path $dir $name
        $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        # Stop any timer before disposal. A live timer would keep firing into
        # script-scope state that the NEXT form has already taken over.
        foreach ($m in $form.PSObject.Members) {
            if ($m.Name -eq "Clock" -or $m.Name -eq "Timer") {
                $t = $form.($m.Name)
                if ($t) { try { $t.Stop(); $t.Dispose() } catch {} }
            }
        }
        $form.Hide()
        $form.Dispose()
        Write-Host "wrote $p"
    }

    $f1 = New-PickerForm
    Dump $f1 "nw-picker.png"

    # --- behavioural self-check on the real controls -------------------
    $f1c = New-PickerForm
    $f1c.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $script:SelfCheckFails = 0
    function Check($name, [bool]$cond, $detail = "") {
        if ($cond) { Write-Host "[PASS] $name" -ForegroundColor Green }
        else { Write-Host "[FAIL] $name - $detail" -ForegroundColor Red; $script:SelfCheckFails++ }
    }

    $b60 = $f1c.Presets | Where-Object { [int]$_.Tag -eq 60 }
    $b30 = $f1c.Presets | Where-Object { [int]$_.Tag -eq 30 }
    $b60.PerformClick()
    Check "click 60 -> caption updates" ($f1c.StartButton.Caption -eq "Start 60-minute break") "got '$($f1c.StartButton.Caption)'"
    Check "click 60 -> chip becomes selected" ($b60.Selected -and -not $b30.Selected) "60=$($b60.Selected) 30=$($b30.Selected)"
    Check "click 60 -> field follows" ($f1c.NumBox.Text -eq "60") "got '$($f1c.NumBox.Text)'"

    $f1c.NumBox.Text = "6000"
    [System.Windows.Forms.Application]::DoEvents()
    Check "invalid 6000 -> button disabled" (-not $f1c.StartButton.Enabled) "button still enabled"
    Check "invalid 6000 -> error shown" ($f1c.ErrLabel.Text.Length -gt 0) "no error text"

    # The regression that made this feel broken: the 1s clock used to rewrite
    # Enabled/Caption and silently re-enable the button over bad input.
    Start-Sleep -Milliseconds 1400
    [System.Windows.Forms.Application]::DoEvents()
    Check "still disabled after a clock tick" (-not $f1c.StartButton.Enabled) "clock tick re-enabled it"

    $f1c.NumBox.Text = "45"
    [System.Windows.Forms.Application]::DoEvents()
    Check "valid 45 -> re-enabled" ($f1c.StartButton.Enabled) "still disabled"
    Check "valid 45 -> caption updates" ($f1c.StartButton.Caption -eq "Start 45-minute break") "got '$($f1c.StartButton.Caption)'"
    Check "valid 45 -> chips cleared" (-not ($f1c.Presets | Where-Object { $_.Selected } | Measure-Object).Count) "a chip is still selected"

    $f1c.NumBox.Text = "1440"
    [System.Windows.Forms.Application]::DoEvents()
    Check "1440 accepted" ($f1c.StartButton.Enabled -and $f1c.StartButton.Caption -eq "Start 1440-minute break") "got '$($f1c.StartButton.Caption)'"
    $f1c.NumBox.Text = "0"
    [System.Windows.Forms.Application]::DoEvents()
    Check "0 rejected" (-not $f1c.StartButton.Enabled) "0 was accepted"

    Write-Host ""
    Write-Host "Self-check: $($script:SelfCheckFails) failure(s)" -ForegroundColor $(if ($script:SelfCheckFails -eq 0) { "Green" } else { "Red" })
    $f1c.Clock.Stop()
    $f1c.Close()
    $f1c.Dispose()

    # --- active-break form: the 250ms timer must survive the function ---
    $f2c = New-ActiveForm -ExpiresAt ((Get-Date).AddMinutes(18)) -TotalMinutes 30
    $f2c.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $firstBig = $f2c.Card.Ring.CenterBig
    $f2c.Timer.Start()
    Start-Sleep -Milliseconds 1600
    [System.Windows.Forms.Application]::DoEvents()
    Check "active ring shows minutes left" ([int]$f2c.Card.Ring.CenterBig -ge 15 -and [int]$f2c.Card.Ring.CenterBig -le 18) "got '$($f2c.Card.Ring.CenterBig)' (was '$firstBig')"
    Check "active ring fraction is partial" ($f2c.Card.Ring.Value -gt 0.4 -and $f2c.Card.Ring.Value -lt 0.8) "got $($f2c.Card.Ring.Value)"
    Check "active clock still ticking" ($f2c.Card.TimeLabel.Text -match '^\d\d:\d\d:\d\d$') "got '$($f2c.Card.TimeLabel.Text)'"

    $script:EndNow = $false
    $f2c.KeepButton.PerformClick()
    Check "Keep break -> does not end it" (-not $script:EndNow) "EndNow=$script:EndNow"
    $f2c.Timer.Stop()
    $f2c.Close()
    $f2c.Dispose()

    Write-Host ""
    Write-Host "Self-check total: $($script:SelfCheckFails) failure(s)" -ForegroundColor $(if ($script:SelfCheckFails -eq 0) { "Green" } else { "Red" })

    $f2 = New-ActiveForm -ExpiresAt ((Get-Date).AddMinutes(18)) -TotalMinutes 30
    Dump $f2 "nw-active.png"

    $f3 = New-StatusForm -Kicker "PAUSED" -Headline "Break activated" `
        -Detail "Auto-shutdown is paused." -TimeLine ((Get-Date).AddMinutes(45).ToString("HH:mm:ss")) `
        -FootNote "It turns itself off - no need to click again." `
        -Tint ([NW.Theme]::Cyan) -RingBig "45" -ButtonText "Got it"
    Dump $f3 "nw-activated.png"
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

# -Capture shows each dialog for real and photographs the screen. DrawToBitmap
# goes through WM_PRINT, which renders transparent controls by asking the parent
# to repaint; a live composited window does not always get that repaint, so a
# control can pass -SelfTest and still show as a black block on screen. This
# is the only check that sees the real thing.
if ($Capture) {
    $dir = if ($OutDir) { $OutDir } else { $env:TEMP }
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    function Grab($form, $name) {
        $form.StartPosition = "CenterScreen"
        $form.ShowInTaskbar = $false
        $form.Show()
        $form.Activate()
        # Let layout settle and every animation timer finish before shooting,
        # otherwise the capture races the first paint.
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 1200
        [System.Windows.Forms.Application]::DoEvents()

        $r = $form.Bounds
        $bmp = New-Object System.Drawing.Bitmap($r.Width, $r.Height)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($r.X, $r.Y, 0, 0, $bmp.Size)
        $g.Dispose()
        $p = Join-Path $dir $name
        $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()

        # Stop any timer before disposal, or it keeps firing into script scope.
        foreach ($m in $form.PSObject.Members) {
            if ($m.Name -eq "Clock" -or $m.Name -eq "Timer") {
                $t = $form.($m.Name)
                if ($t) { try { $t.Stop(); $t.Dispose() } catch {} }
            }
        }
        $form.Close()
        $form.Dispose()
        Write-Host "captured $p"
    }

    Grab (New-PickerForm) "cap-picker.png"
    Grab (New-ActiveForm -ExpiresAt ((Get-Date).AddMinutes(18)) -TotalMinutes 30) "cap-active.png"
    Grab (New-StatusForm -Kicker "PAUSED" -Headline "Break activated" `
        -Detail "Auto-shutdown is paused." -TimeLine ((Get-Date).AddMinutes(30).ToString("HH:mm:ss")) `
        -FootNote "It turns itself off - no need to click again." `
        -Tint ([NW.Theme]::Cyan) -RingBig "30" -ButtonText "Got it") "cap-activated.png"
    exit 0
}

# ==================================================================
# State read (SAME validity rules as the detector)
# ==================================================================
$isActive = $false
$expiresAt = $null
$durationMinutes = 0

if (Test-Path $stateFile) {
    try {
        $json = Get-Content $stateFile -Raw | ConvertFrom-Json
        $isActive = [bool]$json.Active
        if ($isActive) {
            $valid = $true
            if ($null -eq $json.BootUptimeMs -or [long]$json.BootUptimeMs -gt $bootUptimeMs) {
                $valid = $false
            }
            if ($valid -and $json.ExpiresAt) {
                try {
                    if ((Get-Date) -gt ([DateTime]$json.ExpiresAt)) { $valid = $false }
                } catch { $valid = $false }
            }
            $isActive = $valid
            if ($isActive) {
                if ($json.DurationMinutes) { $durationMinutes = [int]$json.DurationMinutes }
                if ($json.ExpiresAt) { try { $expiresAt = [DateTime]$json.ExpiresAt } catch {} }
            }
        }
    } catch {}
}

function Save-Inactive {
    $state = @{
        Active = $false
        Timestamp = (Get-Date).ToString("o")
        Mode = "Working"
    } | ConvertTo-Json
    try {
        Set-Content -Path $stateFile -Value $state -Force
    } catch {}
}

# ==================================================================
# BREAK ALREADY RUNNING -> offer to end it early
# ==================================================================
if ($isActive) {
    if (-not $expiresAt) { $expiresAt = (Get-Date).AddMinutes($durationMinutes) }

    $dlg = New-ActiveForm -ExpiresAt $expiresAt -TotalMinutes $durationMinutes
    $dlg.Timer.Start()
    $dlg.ShowDialog() | Out-Null
    $dlg.Timer.Stop()
    $dlg.Timer.Dispose()
    $dlg.Dispose()

    if ($script:EndNow) {
        Save-Inactive
        try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}
        $s = New-StatusForm -Kicker "PROTECTION ARMED" -Headline "Break ended early" `
            -Detail "Idle shutdown protection is armed." `
            -TimeLine ((Get-Date).AddMinutes(30).ToString("HH:mm:ss")) `
            -FootNote "30 minutes of no activity will shut the PC down again." `
            -Tint ([NW.Theme]::Success) -RingBig "30" -ButtonText "Back to studying"
        $s.ShowDialog() | Out-Null
        $s.Dispose()
    }
    exit 0
}

# ==================================================================
# DURATION PICKER
# ==================================================================
$form = New-PickerForm
$form.Clock.Start()
$form.ShowDialog() | Out-Null
$form.Clock.Stop()
$form.Clock.Dispose()
$form.Dispose()

$minutes = [int]$script:ChosenMinutes
if ($minutes -lt 1 -or $minutes -gt 1440) {
    exit 0
}

# ==================================================================
# Enable the break with an explicit expiry and boot fingerprint
# (state contract unchanged - IdleMistakeDetector.ps1 reads this)
# ==================================================================
$now = Get-Date
$expiresAt = $now.AddMinutes($minutes)

$state = @{
    Active = $true
    Timestamp = $now.ToString("o")
    Mode = "OnBreak"
    DurationMinutes = $minutes
    ExpiresAt = $expiresAt.ToString("o")
    BootUptimeMs = $bootUptimeMs
} | ConvertTo-Json
Set-Content -Path $stateFile -Value $state -Force

try { [System.Media.SystemSounds]::Asterisk.Play() } catch {}

$done = New-StatusForm -Kicker "PAUSED" -Headline "Break activated" `
    -Detail "Auto-shutdown is paused." `
    -TimeLine $expiresAt.ToString("HH:mm:ss") `
    -FootNote "It turns itself off - no need to click again." `
    -Tint ([NW.Theme]::Cyan) -RingBig ([string]$minutes) -ButtonText "Got it"
$done.ShowDialog() | Out-Null
$done.Dispose()