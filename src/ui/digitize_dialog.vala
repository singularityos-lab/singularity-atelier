using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class DigitizeDialog : AppDialog {
        private AtelierWindow win;
        private Digitizer dig;
        private DrawingArea area;
        private ActionRow hint;
        private Point[]? outline;
        private Point[] outline_photo = {};
        private SpinButton ref_w;
        private SpinButton ref_h;
        private SpinButton sa;
        private Entry name;
        private Button add;
        private double scale = 1;
        private double ox;
        private double oy;

        public DigitizeDialog (AtelierWindow win, Cairo.ImageSurface photo) {
            base (win.application, true, false);
            this.win = win;
            dig = new Digitizer (photo);
            set_title (_("Pattern from Photo"));
            transient_for = win;
            set_default_size (980, 720);
            var box = new Box (Orientation.HORIZONTAL, 12);
            box.margin_start = 18;
            box.margin_end = 18;
            area = new DrawingArea ();
            area.hexpand = true;
            area.vexpand = true;
            area.set_draw_func (draw);
            var click = new GestureClick ();
            click.pressed.connect ((n, x, y) => clicked (x, y));
            area.add_controller (click);
            box.append (area);
            var side = new Box (Orientation.VERTICAL, 12);
            side.set_size_request (300, -1);
            var sg = new PreferencesGroup (_("Tracing"));
            hint = new ActionRow (_("Mark the Reference"), "");
            var reset = new Button.with_label (_("Mark Again"));
            reset.valign = Align.CENTER;
            reset.clicked.connect (() => {
                dig.markers = {};
                outline = null;
                update ();
            });
            hint.add_suffix (reset);
            sg.add_row (hint);
            side.append (sg);
            var g = new PreferencesGroup (_("Reference"), _("A rectangle of known size in the photo, such as a sheet of paper or a cutting mat"));
            ref_w = Dialogs.spin_row (g, _("Width"), 10, 3000, 1, 297, 0, _("Millimetres"));
            ref_h = Dialogs.spin_row (g, _("Height"), 10, 3000, 1, 210, 0, _("Millimetres"));
            side.append (g);
            var pg = new PreferencesGroup (_("Piece"));
            name = Dialogs.entry_row (pg, _("Name"), _("Traced Piece"));
            sa = Dialogs.spin_row (pg, _("Seam Allowance"), 0, 50, 0.5, 0, 1, _("Millimetres, zero when the paper includes it"));
            side.append (pg);
            box.append (side);
            content_box.append (box);
            var bb = new Box (Orientation.HORIZONTAL, 8);
            bb.halign = Align.END;
            bb.margin_end = 18;
            bb.margin_bottom = 18;
            bb.margin_top = 8;
            bb.append (add_cancel_button (_("Cancel")));
            add = new Button.with_label (_("Add Piece"));
            add.add_css_class ("suggested-action");
            add.clicked.connect (() => add_piece ());
            bb.append (add);
            content_box.append (bb);
            update ();
        }

        private void update () {
            int n = dig.markers.length;
            hint.title = n < 4 ? _("Mark the Reference") : (outline == null ? _("Trace the Piece") : _("Piece Traced"));
            if (n < 4) hint.subtitle = _("Click the %s corner of the reference rectangle.").printf (n == 0 ? _("top left") : (n == 1 ? _("top right") : (n == 2 ? _("bottom right") : _("bottom left"))));
            else if (outline == null) hint.subtitle = _("Click inside the pattern piece to trace it.");
            else hint.subtitle = _("%s by %s mm. Click another spot to trace again.").printf (PathData.fmt (bounds_mm ().w, 0), PathData.fmt (bounds_mm ().h, 0));
            add.sensitive = outline != null;
            area.queue_draw ();
        }

        private Rect bounds_mm () {
            var r = Rect.empty ();
            if (outline != null) foreach (var p in outline) r = r.include (p.x, p.y);
            return r;
        }

        private void draw (DrawingArea a, Cairo.Context cr, int w, int h) {
            double pw = dig.photo.get_width (), ph = dig.photo.get_height ();
            scale = double.min (w / pw, h / ph);
            ox = (w - pw * scale) / 2;
            oy = (h - ph * scale) / 2;
            cr.save ();
            cr.translate (ox, oy);
            cr.scale (scale, scale);
            cr.set_source_surface (dig.photo, 0, 0);
            cr.paint ();
            cr.restore ();
            cr.set_source_rgba (0.1, 0.45, 0.9, 1);
            cr.set_line_width (2);
            for (int i = 0; i < dig.markers.length; i++) {
                var m = dig.markers[i];
                cr.arc (ox + m.x * scale, oy + m.y * scale, 6, 0, 2 * Math.PI);
                cr.stroke ();
                if (i > 0) {
                    var p = dig.markers[i - 1];
                    cr.move_to (ox + p.x * scale, oy + p.y * scale);
                    cr.line_to (ox + m.x * scale, oy + m.y * scale);
                    cr.stroke ();
                }
            }
            if (outline_photo.length > 2) {
                cr.move_to (ox + outline_photo[0].x * scale, oy + outline_photo[0].y * scale);
                foreach (var p in outline_photo) cr.line_to (ox + p.x * scale, oy + p.y * scale);
                cr.close_path ();
                cr.set_source_rgba (0.95, 0.45, 0.1, 0.25);
                cr.fill_preserve ();
                cr.set_source_rgba (0.95, 0.45, 0.1, 1);
                cr.set_line_width (2);
                cr.stroke ();
            }
        }

        private void clicked (double x, double y) {
            var p = Point ((x - ox) / scale, (y - oy) / scale);
            if (dig.markers.length < 4) {
                Point[] m = dig.markers;
                m += p;
                dig.markers = m;
                update ();
                return;
            }
            dig.ref_width = ref_w.value;
            dig.ref_height = ref_h.value;
            string err;
            outline = dig.outline_at (dig.photo_to_mm (p), out err);
            outline_photo = {};
            if (outline == null) {
                win.add_toast (new Toast (err));
            } else {
                var inv = Digitizer.homography ({ Point (0, 0), Point (dig.ref_width, 0), Point (dig.ref_width, dig.ref_height), Point (0, dig.ref_height) }, dig.markers);
                foreach (var q in outline) outline_photo += Digitizer.apply (inv, q);
            }
            update ();
        }

        private void add_piece () {
            if (outline == null || win.project == null) return;
            win.history.checkpoint ();
            var pattern = win.project.pattern;
            var b = bounds_mm ();
            Point[] shifted = new Point[outline.length];
            for (int i = 0; i < outline.length; i++) shifted[i] = Point (outline[i].x - b.x, outline[i].y - b.y);
            var pc = Solid.fixed_piece (pattern, name.text.strip () != "" ? name.text.strip () : _("Traced Piece"), shifted, sa.value);
            var r0 = PatternRenderer.pieces_bounds (pattern.evaluate (), true);
            pc.place_x = r0.is_empty () ? 0 : r0.x2 () + 50;
            win.project.touch ("pattern");
            win.show_workspace ("pattern");
            win.refresh_all ();
            close_dialog ();
        }
    }
}
