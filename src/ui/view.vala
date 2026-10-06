using Gtk;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public abstract class ZoomCanvas : DrawingArea {
        public double zoom = 1;
        public double pan_x = 40;
        public double pan_y = 40;
        public double rotation;
        public bool allow_rotation = true;
        public signal void view_changed ();
        public signal void drawn ();
        protected double pointer_x;
        protected double pointer_y;
        private double pan_start_x;
        private double pan_start_y;
        private double zoom_start;
        private double rot_start;
        private Point pinch_doc;
        private bool space_down;
        private bool panning;

        protected ZoomCanvas () {
            hexpand = true;
            vexpand = true;
            focusable = true;
            can_focus = true;
            set_draw_func (on_draw);
            var scroll = new EventControllerScroll (EventControllerScrollFlags.BOTH_AXES);
            scroll.scroll.connect ((dx, dy) => {
                var st = scroll.get_current_event_state ();
                if ((st & Gdk.ModifierType.CONTROL_MASK) != 0) {
                    zoom_at (pointer_x, pointer_y, dy < 0 ? 1.15 : 1 / 1.15);
                } else if ((st & Gdk.ModifierType.SHIFT_MASK) != 0) {
                    pan_x -= dy * 30;
                    changed_view ();
                } else {
                    pan_x -= dx * 30;
                    pan_y -= dy * 30;
                    changed_view ();
                }
                return true;
            });
            add_controller (scroll);
            var motion = new EventControllerMotion ();
            motion.motion.connect ((x, y) => {
                pointer_x = x;
                pointer_y = y;
                hover (to_doc (x, y));
            });
            add_controller (motion);
            var mid = new GestureDrag ();
            mid.button = Gdk.BUTTON_MIDDLE;
            mid.drag_begin.connect ((x, y) => {
                pan_start_x = pan_x;
                pan_start_y = pan_y;
            });
            mid.drag_update.connect ((dx, dy) => {
                pan_x = pan_start_x + dx;
                pan_y = pan_start_y + dy;
                changed_view ();
            });
            add_controller (mid);
            var zg = new GestureZoom ();
            zg.begin.connect ((seq) => {
                zoom_start = zoom;
                pan_start_x = pan_x;
                pan_start_y = pan_y;
                double cx, cy;
                zg.get_bounding_box_center (out cx, out cy);
                pinch_doc = to_doc (cx, cy);
            });
            zg.scale_changed.connect ((s) => {
                double cx, cy;
                zg.get_bounding_box_center (out cx, out cy);
                zoom = (zoom_start * s).clamp (0.02, 64);
                var now = from_doc (pinch_doc.x, pinch_doc.y);
                pan_x += cx - now.x;
                pan_y += cy - now.y;
                changed_view ();
            });
            add_controller (zg);
            var rg = new GestureRotate ();
            rg.begin.connect ((seq) => rot_start = rotation);
            rg.angle_changed.connect ((angle, delta) => {
                if (!allow_rotation) return;
                double cx, cy;
                rg.get_bounding_box_center (out cx, out cy);
                var d = to_doc (cx, cy);
                rotation = rot_start + delta * 180 / Math.PI;
                var now = from_doc (d.x, d.y);
                pan_x += cx - now.x;
                pan_y += cy - now.y;
                changed_view ();
            });
            add_controller (rg);
            rg.group (zg);
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((kv, code, st) => {
                if (kv == Gdk.Key.space) {
                    space_down = true;
                    return true;
                }
                return key_pressed (kv, st);
            });
            keys.key_released.connect ((kv, code, st) => {
                if (kv == Gdk.Key.space) space_down = false;
            });
            add_controller (keys);
            var drag = new GestureDrag ();
            drag.button = 0;
            drag.drag_begin.connect ((x, y) => {
                grab_focus ();
                var ev = drag.get_current_event ();
                uint b = drag.get_current_button ();
                if (b == Gdk.BUTTON_MIDDLE) {
                    drag.set_state (EventSequenceState.DENIED);
                    return;
                }
                if (space_down) {
                    panning = true;
                    pan_start_x = pan_x;
                    pan_start_y = pan_y;
                    return;
                }
                panning = false;
                var dev = ev != null ? ev.get_device () : null;
                bool touch = dev != null && dev.source == Gdk.InputSource.TOUCHSCREEN;
                if (touch && !touch_draws ()) {
                    panning = true;
                    pan_start_x = pan_x;
                    pan_start_y = pan_y;
                    return;
                }
                press (to_doc (x, y), b, ev != null ? ev.get_modifier_state () : 0, read_sample (ev, x, y));
            });
            drag.drag_update.connect ((dx, dy) => {
                double sx, sy;
                drag.get_start_point (out sx, out sy);
                if (panning) {
                    pan_x = pan_start_x + dx;
                    pan_y = pan_start_y + dy;
                    changed_view ();
                    return;
                }
                var ev = drag.get_current_event ();
                move (to_doc (sx + dx, sy + dy), ev != null ? ev.get_modifier_state () : 0, read_sample (ev, sx + dx, sy + dy));
            });
            drag.drag_end.connect ((dx, dy) => {
                double sx, sy;
                drag.get_start_point (out sx, out sy);
                if (panning) {
                    panning = false;
                    return;
                }
                var ev = drag.get_current_event ();
                release (to_doc (sx + dx, sy + dy), ev != null ? ev.get_modifier_state () : 0);
            });
            add_controller (drag);
            var ctx = new GestureClick ();
            ctx.button = Gdk.BUTTON_SECONDARY;
            ctx.pressed.connect ((n, x, y) => context_menu (to_doc (x, y), x, y));
            add_controller (ctx);
        }

        protected virtual bool touch_draws () {
            return false;
        }

        private StrokeSample read_sample (Gdk.Event? ev, double x, double y) {
            var d = to_doc (x, y);
            double p = 1, tx = 0, ty = 0;
            if (ev != null) {
                double v;
                if (ev.get_axis (Gdk.AxisUse.PRESSURE, out v)) p = v;
                if (ev.get_axis (Gdk.AxisUse.XTILT, out v)) tx = v;
                if (ev.get_axis (Gdk.AxisUse.YTILT, out v)) ty = v;
                var dev = ev.get_device ();
                if (dev != null && dev.source == Gdk.InputSource.MOUSE) p = 0.65;
            }
            return StrokeSample (d.x, d.y, p.clamp (0, 1), tx, ty, (ev != null ? ev.get_time () : 0) / 1000.0);
        }

        protected void changed_view () {
            queue_draw ();
            view_changed ();
        }

        public Cairo.Matrix view_matrix () {
            var m = Cairo.Matrix.identity ();
            m.translate (pan_x, pan_y);
            m.rotate (rotation * Math.PI / 180);
            m.scale (zoom, zoom);
            return m;
        }

        public Point to_doc (double x, double y) {
            var m = view_matrix ();
            m.invert ();
            m.transform_point (ref x, ref y);
            return Point (x, y);
        }

        public Point from_doc (double x, double y) {
            var m = view_matrix ();
            m.transform_point (ref x, ref y);
            return Point (x, y);
        }

        public void zoom_at (double sx, double sy, double factor) {
            var d = to_doc (sx, sy);
            zoom = (zoom * factor).clamp (0.02, 64);
            var now = from_doc (d.x, d.y);
            pan_x += sx - now.x;
            pan_y += sy - now.y;
            changed_view ();
        }

        public void zoom_in () {
            zoom_at (get_width () / 2.0, get_height () / 2.0, 1.25);
        }

        public void zoom_out () {
            zoom_at (get_width () / 2.0, get_height () / 2.0, 0.8);
        }

        public void fit (Rect r) {
            if (r.is_empty () || get_width () <= 0) return;
            rotation = 0;
            double w = get_width (), h = get_height ();
            zoom = double.min ((w - 60) / double.max (r.w, 1), (h - 60) / double.max (r.h, 1)).clamp (0.02, 64);
            pan_x = w / 2 - r.cx () * zoom;
            pan_y = h / 2 - r.cy () * zoom;
            changed_view ();
        }

        public Rect visible_doc () {
            var a = to_doc (0, 0);
            var b = to_doc (get_width (), get_height ());
            var c = to_doc (get_width (), 0);
            var d = to_doc (0, get_height ());
            var r = Rect.empty ();
            foreach (var p in new Point[] { a, b, c, d }) r = r.include (p.x, p.y);
            return r;
        }

        private void on_draw (DrawingArea area, Cairo.Context cr, int w, int h) {
            draw_background (cr, w, h);
            cr.save ();
            cr.transform (view_matrix ());
            draw_content (cr);
            cr.restore ();
            draw_overlay (cr, w, h);
            drawn ();
        }

        public virtual string status_text () {
            return "";
        }

        protected bool dark_theme () {
            var fg = get_color ();
            return fg.red * 0.3 + fg.green * 0.59 + fg.blue * 0.11 > 0.5;
        }

        protected void paint_pasteboard (Cairo.Context cr, double light) {
            if (dark_theme ()) cr.set_source_rgb (0.17, 0.17, 0.18);
            else cr.set_source_rgb (light, light, light + 0.01);
            cr.paint ();
        }

        protected virtual void draw_background (Cairo.Context cr, int w, int h) {
            paint_pasteboard (cr, 0.93);
        }

        protected abstract void draw_content (Cairo.Context cr);

        protected virtual void draw_overlay (Cairo.Context cr, int w, int h) {
        }

        protected virtual void press (Point p, uint button, Gdk.ModifierType mods, StrokeSample s) {
        }

        protected virtual void move (Point p, Gdk.ModifierType mods, StrokeSample s) {
        }

        protected virtual void release (Point p, Gdk.ModifierType mods) {
        }

        protected virtual void hover (Point p) {
        }

        protected virtual void context_menu (Point p, double x, double y) {
        }

        protected virtual bool key_pressed (uint keyval, Gdk.ModifierType state) {
            return false;
        }

        public static void draw_grid (Cairo.Context cr, Rect view, double step, double zoom, bool dark) {
            while (step * zoom < 12) step *= 5;
            double x0 = Math.floor (view.x / step) * step, y0 = Math.floor (view.y / step) * step;
            cr.save ();
            cr.set_line_width (1 / zoom);
            if (dark) cr.set_source_rgba (1, 1, 1, 0.06);
            else cr.set_source_rgba (0, 0, 0, 0.06);
            for (double x = x0; x <= view.x2 (); x += step) {
                cr.move_to (x, view.y);
                cr.line_to (x, view.y2 ());
            }
            for (double y = y0; y <= view.y2 (); y += step) {
                cr.move_to (view.x, y);
                cr.line_to (view.x2 (), y);
            }
            cr.stroke ();
            cr.restore ();
        }
    }
}
