if (-not ('MediaCleanExport.ThemedButton' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
namespace MediaCleanExport {
    public class ThemedProgressBar : ProgressBar {
        public Color TrackColor { get; set; }
        public Color FillColor { get; set; }
        public ThemedProgressBar() {
            TrackColor = Color.LightGray;
            FillColor = Color.RoyalBlue;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }
        protected override void OnPaint(PaintEventArgs e) {
            e.Graphics.Clear(TrackColor);
            double fraction = Maximum == Minimum ? 0 : (double)(Value - Minimum) / (Maximum - Minimum);
            using (Brush brush = new SolidBrush(FillColor))
                e.Graphics.FillRectangle(brush, 0, 0, (int)(Width * fraction), Height);
        }
    }
    public class ThemedButton : Button {
        public Color BorderColor { get; set; }
        public Color HoverColor { get; set; }
        public Color DisabledTextColor { get; set; }
        private bool hovered;
        public ThemedButton() {
            BorderColor = Color.SlateGray;
            HoverColor = Color.LightSteelBlue;
            DisabledTextColor = Color.SlateGray;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }
        protected override void OnMouseEnter(EventArgs e) { hovered = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovered = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnEnabledChanged(EventArgs e) { Invalidate(); base.OnEnabledChanged(e); }
        protected override void OnPaint(PaintEventArgs e) {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            e.Graphics.Clear(Parent == null ? BackColor : Parent.BackColor);
            Rectangle rect = new Rectangle(0, 0, Width - 1, Height - 1);
            const int d = 12;
            using (GraphicsPath path = new GraphicsPath()) {
                path.AddArc(rect.Left, rect.Top, d, d, 180, 90);
                path.AddArc(rect.Right - d, rect.Top, d, d, 270, 90);
                path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
                path.AddArc(rect.Left, rect.Bottom - d, d, d, 90, 90);
                path.CloseFigure();
                using (Brush brush = new SolidBrush(hovered && Enabled ? HoverColor : BackColor))
                    e.Graphics.FillPath(brush, path);
                using (Pen pen = new Pen(BorderColor)) e.Graphics.DrawPath(pen, path);
            }
            TextRenderer.DrawText(e.Graphics, Text, Font, rect,
                Enabled ? ForeColor : DisabledTextColor,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            if (Focused && ShowFocusCues) ControlPaint.DrawFocusRectangle(e.Graphics, Rectangle.Inflate(rect, -5, -5));
        }
    }
}
'@
}
