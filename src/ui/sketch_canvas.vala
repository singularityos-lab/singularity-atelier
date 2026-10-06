using Gtk;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class SketchCanvas : ZoomCanvas {
        public Project project;
        public History history;
        public string tool { get; set; default = "brush"; }
        public Brush brush;
        public Rgba color = Rgba (0.12, 0.12, 0.14, 1);
        public Rgba color2 = Rgba (1, 1, 1, 1);
        public SketchLayer? layer;
        public double stabilizer = 0.35;
        public bool hold_to_shape = true;
        public int hold_delay = 600;
        public bool predictive;
        public bool touch_drawing;
        public double fill_tolerance = 0.3;
        public double liquify_radius = 30;
        public Gee.HashSet<Stroke> selection = new Gee.HashSet<Stroke> ();
        public signal void selection_changed ();
        public signal void color_picked (Rgba c);
        public signal void layers_changed ();

        private Stroke? live;
        private Smoother? smoother;
        private GuideSnapper? snapper;
        private uint hold_id;
        private ShapeGuess held = ShapeGuess.NONE;
        private Point held_start;
        private Point last_doc;
        private double start_time;
        private string drag_mode = "";
        private Point drag_start;
        private Gee.HashMap<Stroke, Stroke> drag_orig = new Gee.HashMap<Stroke, Stroke> ();
        private Point[] lasso = {};
        private Stroke? edit_stroke;
        private int edit_index = -1;
        private string guide_handle = "";
        private int corner_index = -1;
        private Point[] quad = {};
        private Rect sel_box;
        private FillRegion? gradient_live;

        public SketchCanvas (Project project, History history) {
            this.project = project;
            this.history = history;
            brush = project.sketch.brushes[0].copy ();
            layer = first_stroke_layer ();
            start_time = get_monotonic_time () / 1e6;
        }

        public SketchLayer? first_stroke_layer () {
            for (int i = project.sketch.layers.size - 1; i >= 0; i--) if (project.sketch.layers[i].kind == LayerKind.STROKES) return project.sketch.layers[i];
            return project.sketch.layers.size > 0 ? project.sketch.layers[0] : null;
        }

        public void reset_project (Project p) {
            project = p;
            if (layer == null || project.sketch.find_layer (layer.id) == null) layer = first_stroke_layer ();
            else layer = project.sketch.find_layer (layer.id);
            selection.clear ();
            queue_draw ();
        }

        public override string status_text () {
            return layer != null ? layer.name : "";
        }

        protected override bool touch_draws () {
            return touch_drawing;
        }

        protected override void draw_background (Cairo.Context cr, int w, int h) {
            paint_pasteboard (cr, 0.86);
        }

        protected override void draw_content (Cairo.Context cr) {
            var vis = visible_doc ();
            project.sketch.paper.apply (cr);
            cr.rectangle (vis.x, vis.y, vis.w, vis.h);
            cr.fill ();
            SketchRenderer.draw (cr, project.sketch, live, layer, false);
            if (gradient_live != null) {
                cr.new_path ();
                gradient_live.path.to_cairo (cr);
                gradient_live.set_source (cr);
                cr.fill ();
            }
            SketchRenderer.draw_guides (cr, project.sketch.guides, zoom, vis);
            if (live != null && project.sketch.guides.symmetry != SymmetryMode.NONE) {
                foreach (var m in project.sketch.guides.symmetry_transforms ()) {
                    var c = live.copy ();
                    c.transform (m);
                    cr.save ();
                    cr.push_group ();
                    SketchRenderer.draw_stroke (cr, c);
                    cr.pop_group_to_source ();
                    cr.paint_with_alpha (0.6);
                    cr.restore ();
                }
            }
            if (selection.size > 0) draw_selection (cr);
            if (lasso.length > 1) {
                cr.new_path ();
                PatternRenderer.poly (cr, lasso, false);
                cr.set_source_rgba (0.1, 0.45, 0.9, 0.9);
                cr.set_line_width (1 / zoom);
                cr.set_dash ({ 4 / zoom, 3 / zoom }, 0);
                cr.stroke ();
                cr.set_dash (null, 0);
            }
            if (tool == "edit" && edit_stroke != null) {
                cr.set_source_rgba (0.95, 0.45, 0.1, 0.9);
                foreach (var s in edit_stroke.samples) {
                    cr.arc (s.x, s.y, 2.5 / zoom, 0, 2 * Math.PI);
                    cr.fill ();
                }
            }
        }

        protected override void draw_overlay (Cairo.Context cr, int w, int h) {
            if (tool == "brush" || tool == "eraser" || tool == "liquify") {
                double r = tool == "liquify" ? liquify_radius : (tool == "eraser" ? eraser_brush ().size : brush.size) / 2;
                cr.arc (pointer_x, pointer_y, double.max (2, r * zoom), 0, 2 * Math.PI);
                cr.set_source_rgba (0, 0, 0, 0.5);
                cr.set_line_width (1);
                cr.stroke ();
            }
        }

        private void draw_selection (Cairo.Context cr) {
            var b = Rect.empty ();
            foreach (var s in selection) b = b.union (s.bounds ());
            if (b.is_empty ()) return;
            sel_box = b;
            cr.save ();
            cr.set_line_width (1.2 / zoom);
            cr.set_source_rgba (0.1, 0.45, 0.9, 0.9);
            cr.set_dash ({ 5 / zoom, 3 / zoom }, 0);
            cr.rectangle (b.x, b.y, b.w, b.h);
            cr.stroke ();
            cr.set_dash (null, 0);
            foreach (var c in corners (b)) {
                cr.rectangle (c.x - 4 / zoom, c.y - 4 / zoom, 8 / zoom, 8 / zoom);
                cr.set_source_rgba (1, 1, 1, 1);
                cr.fill_preserve ();
                cr.set_source_rgba (0.1, 0.45, 0.9, 1);
                cr.stroke ();
            }
            var rh = rotate_handle (b);
            cr.arc (rh.x, rh.y, 5 / zoom, 0, 2 * Math.PI);
            cr.stroke ();
            cr.restore ();
        }

        private Point[] corners (Rect b) {
            return { Point (b.x, b.y), Point (b.x2 (), b.y), Point (b.x2 (), b.y2 ()), Point (b.x, b.y2 ()) };
        }

        private Point rotate_handle (Rect b) {
            return Point (b.cx (), b.y - 24 / zoom);
        }

        public Brush eraser_brush () {
            return project.sketch.find_brush ("eraser") ?? new Brush ("eraser", _("Eraser"), BrushKind.ERASER);
        }

        private bool layer_editable () {
            return layer != null && !layer.locked && layer.visible && (layer.kind == LayerKind.STROKES || layer.kind == LayerKind.UNDERLAY || layer.kind == LayerKind.IMAGE);
        }

        protected override void press (Point p, uint button, Gdk.ModifierType mods, StrokeSample s) {
            last_doc = p;
            drag_start = p;
            if (button == Gdk.BUTTON_SECONDARY) return;
            if (guide_press (p)) return;
            switch (tool) {
                case "brush":
                case "eraser":
                case "tape":
                    start_stroke (s);
                    break;
                case "select":
                    select_press (p, mods);
                    break;
                case "edit":
                    edit_press (p);
                    break;
                case "liquify":
                    if (!layer_editable ()) return;
                    history.checkpoint ();
                    break;
                case "fill":
                    bucket (p);
                    break;
                case "gradient":
                    gradient_press (p);
                    break;
                case "picker":
                    pick_color (p);
                    break;
                case "text":
                    break;
            }
        }

        protected override void move (Point p, Gdk.ModifierType mods, StrokeSample s) {
            if (guide_handle != "") {
                guide_move (p);
                return;
            }
            switch (tool) {
                case "brush":
                case "eraser":
                    extend_stroke (s);
                    break;
                case "tape":
                    tape_update (s);
                    break;
                case "select":
                    select_move (p, mods);
                    break;
                case "edit":
                    edit_move (p);
                    break;
                case "liquify":
                    liquify (p);
                    break;
                case "gradient":
                    gradient_move (p);
                    break;
            }
            last_doc = p;
        }

        protected override void release (Point p, Gdk.ModifierType mods) {
            if (guide_handle != "") {
                guide_handle = "";
                return;
            }
            switch (tool) {
                case "brush":
                case "eraser":
                case "tape":
                    finish_stroke ();
                    break;
                case "select":
                    select_release (p, mods);
                    break;
                case "edit":
                    edit_stroke = edit_index >= 0 ? edit_stroke : null;
                    edit_index = -1;
                    break;
                case "gradient":
                    gradient_release ();
                    break;
            }
            queue_draw ();
        }

        protected override void hover (Point p) {
            if (tool == "brush" || tool == "eraser" || tool == "liquify") queue_draw ();
        }

        private void start_stroke (StrokeSample s) {
            if (!layer_editable () || layer.kind != LayerKind.STROKES) {
                layer_needed ();
                return;
            }
            var b = tool == "eraser" ? eraser_brush () : brush;
            live = new Stroke.from_brush (b, color);
            if (tool == "tape") {
                tape_dir = Point (0, 0);
                live.pressure_size = false;
                live.smooth_curve = true;
            }
            live.started = get_monotonic_time () / 1e6 - start_time;
            smoother = stabilizer > 0.01 ? new Smoother (stabilizer) : null;
            snapper = new GuideSnapper (project.sketch.guides, Point (s.x, s.y), zoom);
            held = ShapeGuess.NONE;
            var first = s;
            if (snapper.active) {
                var q = snapper.apply (Point (s.x, s.y));
                first.x = q.x;
                first.y = q.y;
            }
            live.samples.add (first);
            held_start = Point (first.x, first.y);
            arm_hold ();
            queue_draw ();
        }

        public signal void layer_needed ();

        private void arm_hold () {
            if (hold_id != 0) Source.remove (hold_id);
            hold_id = 0;
            if (!hold_to_shape || live == null || tool == "tape") return;
            hold_id = Timeout.add (hold_delay, () => {
                hold_id = 0;
                shape_live ();
                return Source.REMOVE;
            });
        }

        private void shape_live () {
            if (live == null || held != ShapeGuess.NONE || snapper.active) return;
            var pts = live.centers ();
            Point[] shaped;
            var g = StrokeRecognizer.guess (pts, out shaped);
            if (g == ShapeGuess.NONE) return;
            held = g;
            double p = 0;
            foreach (var smp in live.samples) p += smp.pressure;
            p /= live.samples.size;
            live.samples.clear ();
            var res = g == ShapeGuess.LINE ? shaped : StrokeRecognizer.resample_to (shaped, int.max (8, pts.length));
            foreach (var q in res) live.samples.add (StrokeSample (q.x, q.y, p));
            live.smooth_curve = g != ShapeGuess.LINE;
            queue_draw ();
        }

        private void extend_stroke (StrokeSample s) {
            if (live == null) return;
            if (held == ShapeGuess.LINE) {
                var last = live.samples[live.samples.size - 1];
                last.x = s.x;
                last.y = s.y;
                live.samples[live.samples.size - 1] = last;
                queue_draw ();
                return;
            }
            if (held != ShapeGuess.NONE) return;
            var o = smoother != null ? smoother.push (s) : s;
            if (snapper != null && snapper.active) {
                var q = snapper.apply (Point (o.x, o.y));
                o.x = q.x;
                o.y = q.y;
            }
            var prev = live.samples[live.samples.size - 1];
            if (Math.hypot (o.x - prev.x, o.y - prev.y) < 0.6 / zoom) return;
            live.samples.add (o);
            arm_hold ();
            queue_draw ();
        }

        private Point tape_dir = Point (0, 0);

        private void tape_update (StrokeSample s) {
            if (live == null) return;
            var a = live.samples[0];
            double dx = s.x - a.x, dy = s.y - a.y;
            double len = Math.hypot (dx, dy);
            if (tape_dir.x == 0 && tape_dir.y == 0 && len > 12 / zoom) tape_dir = Point (dx / len, dy / len);
            var dir = tape_dir.x == 0 && tape_dir.y == 0 ? Point (dx / double.max (len, 1e-6), dy / double.max (len, 1e-6)) : tape_dir;
            var ctrl = Point (a.x + dir.x * len / 2, a.y + dir.y * len / 2);
            live.samples.clear ();
            live.samples.add (a);
            int n = int.max (2, (int) (len / 3));
            for (int i = 1; i <= n; i++) {
                double t = (double) i / n;
                double u = 1 - t;
                live.samples.add (StrokeSample (u * u * a.x + 2 * u * t * ctrl.x + t * t * s.x, u * u * a.y + 2 * u * t * ctrl.y + t * t * s.y, 1));
            }
            queue_draw ();
        }

        public void finish_stroke () {
            if (hold_id != 0) Source.remove (hold_id);
            hold_id = 0;
            if (live == null) return;
            var st = live;
            live = null;
            if (st.samples.size == 1) {
                var s0 = st.samples[0];
                st.samples.add (StrokeSample (s0.x + 0.01, s0.y, s0.pressure));
            }
            if (predictive && held == ShapeGuess.NONE && (snapper == null || !snapper.active) && st.kind != BrushKind.ERASER) {
                var pts = StrokeRecognizer.predictive (st.centers (), 1.2);
                if (pts.length >= 2) {
                    var old = st.samples;
                    st.samples = new Gee.ArrayList<StrokeSample?> ();
                    double total = Polyline.length (pts);
                    double acc = 0;
                    for (int i = 0; i < pts.length; i++) {
                        if (i > 0) acc += pts[i].distance (pts[i - 1]);
                        int k = total > 0 ? (int) ((old.size - 1) * acc / total) : 0;
                        var src = old[k.clamp (0, old.size - 1)];
                        st.samples.add (StrokeSample (pts[i].x, pts[i].y, src.pressure, src.tilt_x, src.tilt_y, src.time));
                    }
                }
            }
            history.checkpoint ();
            layer.strokes.add (st);
            var sk = project.sketch;
            if (sk.record_timelapse) sk.timelapse.add (new TimelapseEvent (layer.id, layer.strokes.size - 1, st.started));
            foreach (var m in sk.guides.symmetry_transforms ()) {
                var c = st.copy ();
                c.transform (m);
                layer.strokes.add (c);
                if (sk.record_timelapse) sk.timelapse.add (new TimelapseEvent (layer.id, layer.strokes.size - 1, st.started));
            }
            project.touch ("sketch");
            queue_draw ();
        }

        private bool guide_press (Point p) {
            var g = project.sketch.guides;
            double tol = 9 / zoom;
            guide_handle = "";
            if (tool != "guide") return false;
            if (g.ruler_on) {
                if (p.distance (g.ruler_a) < tol) guide_handle = "ruler_a";
                else if (p.distance (g.ruler_b) < tol) guide_handle = "ruler_b";
            }
            if (guide_handle == "" && g.ellipse_on) {
                double r = g.ellipse_angle * Math.PI / 180;
                if (p.distance (g.ellipse_center) < tol) guide_handle = "ellipse_c";
                else if (p.distance (Point (g.ellipse_center.x + g.ellipse_rx * Math.cos (r), g.ellipse_center.y + g.ellipse_rx * Math.sin (r))) < tol) guide_handle = "ellipse_rx";
                else if (p.distance (Point (g.ellipse_center.x - g.ellipse_ry * Math.sin (r), g.ellipse_center.y + g.ellipse_ry * Math.cos (r))) < tol) guide_handle = "ellipse_ry";
            }
            if (guide_handle == "" && g.curve_on && p.distance (g.curve_pos) < tol * 2) guide_handle = "curve";
            if (guide_handle == "" && g.perspective > 0) {
                if (p.distance (g.vp1) < tol * 2) guide_handle = "vp1";
                else if (g.perspective >= 2 && p.distance (g.vp2) < tol * 2) guide_handle = "vp2";
                else if (g.perspective >= 3 && p.distance (g.vp3) < tol * 2) guide_handle = "vp3";
            }
            if (guide_handle == "" && g.symmetry != SymmetryMode.NONE && p.distance (g.symmetry_center) < tol) guide_handle = "sym";
            if (guide_handle == "" && g.curve_on) {
                var cp = g.curve_path ();
                if (cp != null && cp.contains (p.x, p.y)) guide_handle = "curve_rotate";
            }
            return guide_handle != "";
        }

        private void guide_move (Point p) {
            var g = project.sketch.guides;
            double dx = p.x - last_doc.x, dy = p.y - last_doc.y;
            switch (guide_handle) {
                case "ruler_a": g.ruler_a = p; break;
                case "ruler_b": g.ruler_b = p; break;
                case "ellipse_c": g.ellipse_center = p; break;
                case "ellipse_rx": {
                    g.ellipse_rx = double.max (4, p.distance (g.ellipse_center));
                    g.ellipse_angle = Math.atan2 (p.y - g.ellipse_center.y, p.x - g.ellipse_center.x) * 180 / Math.PI;
                    break;
                }
                case "ellipse_ry": g.ellipse_ry = double.max (4, p.distance (g.ellipse_center)); break;
                case "curve": g.curve_pos = Point (g.curve_pos.x + dx, g.curve_pos.y + dy); break;
                case "curve_rotate": {
                    double a0 = Math.atan2 (last_doc.y - g.curve_pos.y, last_doc.x - g.curve_pos.x);
                    double a1 = Math.atan2 (p.y - g.curve_pos.y, p.x - g.curve_pos.x);
                    g.curve_angle += (a1 - a0) * 180 / Math.PI;
                    break;
                }
                case "vp1":
                    g.vp1 = p;
                    g.vp2 = Point (g.vp2.x, p.y);
                    break;
                case "vp2":
                    g.vp2 = p;
                    g.vp1 = Point (g.vp1.x, p.y);
                    break;
                case "vp3": g.vp3 = p; break;
                case "sym": g.symmetry_center = p; break;
            }
            last_doc = p;
            project.touch ("guides");
            queue_draw ();
        }

        private Stroke? stroke_at (Point p) {
            if (layer == null) return null;
            Stroke? best = null;
            double bd = 8 / zoom;
            foreach (var s in layer.strokes) {
                double d = s.distance_to (p.x, p.y) - s.size / 2;
                if (d < bd) {
                    bd = d;
                    best = s;
                }
            }
            return best;
        }

        private Cairo.Matrix image_orig;

        private void select_press (Point p, Gdk.ModifierType mods) {
            drag_mode = "";
            if (layer != null && layer.kind == LayerKind.IMAGE && !layer.locked && layer.image () != null) {
                var b = layer.bounds ();
                var cs = corners (b);
                history.checkpoint ();
                image_orig = layer.image_matrix;
                quad = cs;
                drag_mode = "image-move";
                for (int i = 0; i < 4; i++) {
                    if (p.distance (cs[i]) < 12 / zoom) {
                        drag_mode = "image-scale";
                        corner_index = i;
                    }
                }
                return;
            }
            if (selection.size > 0 && !sel_box.is_empty ()) {
                var cs = corners (sel_box);
                for (int i = 0; i < 4; i++) {
                    if (p.distance (cs[i]) < 9 / zoom) {
                        drag_mode = (mods & Gdk.ModifierType.CONTROL_MASK) != 0 ? "distort" : "scale";
                        corner_index = i;
                        quad = cs;
                    }
                }
                if (drag_mode == "" && p.distance (rotate_handle (sel_box)) < 9 / zoom) drag_mode = "rotate";
                if (drag_mode == "" && sel_box.contains (p.x, p.y)) drag_mode = "move";
            }
            if (drag_mode != "") {
                history.checkpoint ();
                drag_orig.clear ();
                foreach (var s in selection) drag_orig[s] = s.copy ();
                return;
            }
            var hit = stroke_at (p);
            if (hit != null) {
                if ((mods & Gdk.ModifierType.SHIFT_MASK) == 0) selection.clear ();
                selection.add (hit);
                drag_mode = "move";
                history.checkpoint ();
                drag_orig.clear ();
                foreach (var s in selection) drag_orig[s] = s.copy ();
                selection_changed ();
                queue_draw ();
                return;
            }
            if ((mods & Gdk.ModifierType.SHIFT_MASK) == 0) selection.clear ();
            lasso = { p };
            drag_mode = "lasso";
            selection_changed ();
        }

        private void apply_to_selection (owned TransformPoint fn) {
            foreach (var e in drag_orig.entries) {
                var dst = e.key;
                var src = e.value;
                for (int i = 0; i < src.samples.size && i < dst.samples.size; i++) {
                    var smp = src.samples[i];
                    var q = fn (Point (smp.x, smp.y));
                    smp.x = q.x;
                    smp.y = q.y;
                    dst.samples[i] = smp;
                }
            }
        }

        private delegate Point TransformPoint (Point p);

        private void select_move (Point p, Gdk.ModifierType mods) {
            switch (drag_mode) {
                case "image-move": {
                    var m = image_orig;
                    var t = Cairo.Matrix.identity ();
                    t.translate (p.x - drag_start.x, p.y - drag_start.y);
                    var r = Cairo.Matrix.identity ();
                    r.multiply (m, t);
                    layer.image_matrix = r;
                    break;
                }
                case "image-scale": {
                    var anchor = quad[(corner_index + 2) % 4];
                    var orig = quad[corner_index];
                    double k = double.max (0.02, p.distance (anchor) / double.max (1e-6, orig.distance (anchor)));
                    var t = Cairo.Matrix.identity ();
                    t.translate (anchor.x, anchor.y);
                    t.scale (k, k);
                    t.translate (-anchor.x, -anchor.y);
                    var r = Cairo.Matrix.identity ();
                    r.multiply (image_orig, t);
                    layer.image_matrix = r;
                    break;
                }
                case "lasso":
                    lasso += p;
                    break;
                case "move": {
                    double dx = p.x - drag_start.x, dy = p.y - drag_start.y;
                    apply_to_selection ((q) => Point (q.x + dx, q.y + dy));
                    break;
                }
                case "scale": {
                    var anchor = quad[(corner_index + 2) % 4];
                    var orig = quad[corner_index];
                    double sx = (p.x - anchor.x) / double.max (1e-6, (orig.x - anchor.x).abs ()) * (orig.x >= anchor.x ? 1 : -1);
                    double sy = (p.y - anchor.y) / double.max (1e-6, (orig.y - anchor.y).abs ()) * (orig.y >= anchor.y ? 1 : -1);
                    if ((mods & Gdk.ModifierType.SHIFT_MASK) != 0) {
                        double k = double.max (sx.abs (), sy.abs ());
                        sx = sx < 0 ? -k : k;
                        sy = sy < 0 ? -k : k;
                    }
                    apply_to_selection ((q) => Point (anchor.x + (q.x - anchor.x) * sx, anchor.y + (q.y - anchor.y) * sy));
                    break;
                }
                case "rotate": {
                    double cx = sel_box.cx (), cy = sel_box.cy ();
                    double a = Math.atan2 (p.y - cy, p.x - cx) - Math.atan2 (drag_start.y - cy, drag_start.x - cx);
                    double c = Math.cos (a), s = Math.sin (a);
                    apply_to_selection ((q) => Point (cx + (q.x - cx) * c - (q.y - cy) * s, cy + (q.x - cx) * s + (q.y - cy) * c));
                    break;
                }
                case "distort": {
                    Point[] target = quad;
                    target[corner_index] = p;
                    var src_box = Rect.from_points (quad[0].x, quad[0].y, quad[2].x, quad[2].y);
                    apply_to_selection ((q) => Perspective.map_rect_to_quad (src_box, target, q));
                    break;
                }
            }
            queue_draw ();
        }

        private void select_release (Point p, Gdk.ModifierType mods) {
            if (drag_mode == "lasso" && lasso.length > 2 && layer != null) {
                var poly = new PathData ();
                poly.add_polygon (lasso, true);
                foreach (var s in layer.strokes) {
                    int inside = 0;
                    foreach (var smp in s.samples) if (poly.contains (smp.x, smp.y)) inside++;
                    if (inside > s.samples.size / 2) selection.add (s);
                }
                selection_changed ();
            }
            if (drag_mode != "" && drag_mode != "lasso") project.touch ("sketch");
            lasso = {};
            drag_mode = "";
        }

        public void delete_selection () {
            if (selection.size == 0 || layer == null) return;
            history.checkpoint ();
            foreach (var l in project.sketch.all_layers ()) l.strokes.remove_all (selection);
            selection.clear ();
            project.touch ("sketch");
            selection_changed ();
            queue_draw ();
        }

        public void recolor_selection (Rgba c) {
            if (selection.size == 0) return;
            history.checkpoint ();
            foreach (var s in selection) s.color = c;
            project.touch ("sketch");
            queue_draw ();
        }

        public void smooth_selection () {
            if (selection.size == 0) return;
            history.checkpoint ();
            foreach (var s in selection) {
                var pts = StrokeRecognizer.predictive (s.centers (), 1.5);
                if (pts.length < 2) continue;
                var old = s.samples;
                s.samples = new Gee.ArrayList<StrokeSample?> ();
                for (int i = 0; i < pts.length; i++) {
                    var src = old[(int) ((double) i / double.max (1, pts.length - 1) * (old.size - 1))];
                    s.samples.add (StrokeSample (pts[i].x, pts[i].y, src.pressure, src.tilt_x, src.tilt_y, src.time));
                }
            }
            project.touch ("sketch");
            queue_draw ();
        }

        private void edit_press (Point p) {
            edit_index = -1;
            if (edit_stroke != null) {
                for (int i = 0; i < edit_stroke.samples.size; i++) {
                    var s = edit_stroke.samples[i];
                    if (Math.hypot (s.x - p.x, s.y - p.y) < 7 / zoom) {
                        edit_index = i;
                        history.checkpoint ();
                        drag_orig.clear ();
                        drag_orig[edit_stroke] = edit_stroke.copy ();
                        return;
                    }
                }
            }
            edit_stroke = stroke_at (p);
            queue_draw ();
        }

        private void edit_move (Point p) {
            if (edit_stroke == null || edit_index < 0 || !drag_orig.has_key (edit_stroke)) return;
            var orig = drag_orig[edit_stroke];
            double dx = p.x - drag_start.x, dy = p.y - drag_start.y;
            int n = orig.samples.size;
            int reach = int.max (2, n / 6);
            for (int i = 0; i < n; i++) {
                int d = (i - edit_index).abs ();
                if (d > reach) continue;
                double w = 0.5 + 0.5 * Math.cos (Math.PI * d / (reach + 1));
                var s = orig.samples[i];
                s.x += dx * w;
                s.y += dy * w;
                edit_stroke.samples[i] = s;
            }
            project.touch ("sketch");
            queue_draw ();
        }

        private void liquify (Point p) {
            if (!layer_editable ()) return;
            double dx = p.x - last_doc.x, dy = p.y - last_doc.y;
            double r = liquify_radius;
            foreach (var st in layer.strokes) {
                for (int i = 0; i < st.samples.size; i++) {
                    var s = st.samples[i];
                    double d = Math.hypot (s.x - p.x, s.y - p.y);
                    if (d > r) continue;
                    double w = 1 - d / r;
                    w = w * w;
                    s.x += dx * w;
                    s.y += dy * w;
                    st.samples[i] = s;
                }
            }
            project.touch ("sketch");
            queue_draw ();
        }

        private void bucket (Point p) {
            if (!layer_editable () || layer.kind != LayerKind.STROKES) return;
            var path = RegionFill.region (project.sketch, layer, p, fill_tolerance, 1 / double.max (zoom, 0.25));
            if (path == null) {
                bucket_failed ();
                return;
            }
            history.checkpoint ();
            var f = new FillRegion ();
            f.path = path;
            f.color = color;
            layer.fills.add (f);
            project.touch ("sketch");
            queue_draw ();
        }

        public signal void bucket_failed ();

        private void gradient_press (Point p) {
            if (!layer_editable ()) return;
            var path = RegionFill.region (project.sketch, layer, p, fill_tolerance, 1 / double.max (zoom, 0.25));
            gradient_live = new FillRegion ();
            if (path == null) {
                var v = visible_doc ();
                gradient_live.path = new PathData.rect (v.x, v.y, v.w, v.h);
            } else {
                gradient_live.path = path;
            }
            gradient_live.mode = "linear";
            gradient_live.color = color;
            gradient_live.color2 = color2;
            gradient_live.x1 = p.x;
            gradient_live.y1 = p.y;
            gradient_live.x2 = p.x + 1;
            gradient_live.y2 = p.y;
        }

        public bool radial_gradient;

        private void gradient_move (Point p) {
            if (gradient_live == null) return;
            gradient_live.x2 = p.x;
            gradient_live.y2 = p.y;
            gradient_live.mode = radial_gradient ? "radial" : "linear";
            queue_draw ();
        }

        private void gradient_release () {
            if (gradient_live == null) return;
            history.checkpoint ();
            layer.fills.add (gradient_live);
            gradient_live = null;
            project.touch ("sketch");
        }

        private void pick_color (Point p) {
            var img = new Cairo.ImageSurface (Cairo.Format.ARGB32, 1, 1);
            var cr = new Cairo.Context (img);
            cr.translate (-p.x, -p.y);
            SketchRenderer.draw (cr, project.sketch);
            img.flush ();
            unowned uint8[] d = img.get_data ();
            var c = Rgba (d[2] / 255.0, d[1] / 255.0, d[0] / 255.0, 1);
            color = c;
            color_picked (c);
        }

        protected override bool key_pressed (uint keyval, Gdk.ModifierType state) {
            if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.BackSpace) {
                delete_selection ();
                return true;
            }
            if (keyval == Gdk.Key.bracketleft) {
                brush.size = double.max (0.2, brush.size / 1.2);
                queue_draw ();
                return true;
            }
            if (keyval == Gdk.Key.bracketright) {
                brush.size = double.min (400, brush.size * 1.2);
                queue_draw ();
                return true;
            }
            return false;
        }

        public void add_reference (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            var pb = new Gdk.Pixbuf.from_file (path);
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, pb.width, pb.height);
            var cr = new Cairo.Context (surf);
            Gdk.cairo_set_source_pixbuf (cr, pb, 0, 0);
            cr.paint ();
            history.checkpoint ();
            var l = new SketchLayer (project.sketch.new_id (), Path.get_basename (path), LayerKind.IMAGE);
            l.image_data = new Bytes (OraFormat.png_bytes (surf));
            l.image_name = Path.get_basename (path);
            l.opacity = 0.5;
            l.locked = true;
            var v = visible_doc ();
            double sc = double.min (v.w * 0.8 / pb.width, v.h * 0.8 / pb.height);
            var m = Cairo.Matrix.identity ();
            m.translate (v.cx () - pb.width * sc / 2, v.cy () - pb.height * sc / 2);
            m.scale (sc, sc);
            l.image_matrix = m;
            project.sketch.layers.insert (0, l);
            project.touch ("layers");
            layers_changed ();
            queue_draw ();
        }

        public void add_vehicle_underlay (string kind) {
            history.checkpoint ();
            var l = new SketchLayer (project.sketch.new_id (), VehicleTemplate.label (kind), LayerKind.UNDERLAY);
            l.underlay = "vehicle:" + kind;
            var v = visible_doc ();
            var t = VehicleTemplate.preset (kind);
            double sc = v.w * 0.7 / t.length;
            l.underlay_params["scale"] = sc;
            l.underlay_params["x"] = v.cx () - t.length * sc / 2;
            l.underlay_params["y"] = v.cy () + t.height * sc / 2;
            l.locked = true;
            project.sketch.layers.insert (0, l);
            project.touch ("layers");
            layers_changed ();
            queue_draw ();
        }

        public void fit_all () {
            var b = project.sketch.bounds ();
            if (b.is_empty ()) b = Rect (0, 0, 800, 600);
            fit (b.inflate (40));
        }
    }
}
