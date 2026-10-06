using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public struct Rgba {
        public double r;
        public double g;
        public double b;
        public double a;

        public Rgba (double r, double g, double b, double a = 1) {
            this.r = r;
            this.g = g;
            this.b = b;
            this.a = a;
        }

        public static Rgba parse (string? s, Rgba fallback = Rgba (0, 0, 0, 1)) {
            if (s == null) return fallback;
            string t = s.strip ();
            if (t.has_prefix ("#")) t = t.substring (1);
            if (t.length != 6 && t.length != 8) return fallback;
            uint v = 0;
            for (int i = 0; i < t.length; i++) {
                char c = t[i];
                int d = c.isdigit () ? c - '0' : (c.tolower () >= 'a' && c.tolower () <= 'f' ? c.tolower () - 'a' + 10 : -1);
                if (d < 0) return fallback;
                v = v * 16 + d;
            }
            if (t.length == 6) return Rgba (((v >> 16) & 255) / 255.0, ((v >> 8) & 255) / 255.0, (v & 255) / 255.0, 1);
            return Rgba (((v >> 24) & 255) / 255.0, ((v >> 16) & 255) / 255.0, ((v >> 8) & 255) / 255.0, (v & 255) / 255.0);
        }

        public string to_hex (bool alpha = false) {
            int ri = (int) Math.round (r.clamp (0, 1) * 255);
            int gi = (int) Math.round (g.clamp (0, 1) * 255);
            int bi = (int) Math.round (b.clamp (0, 1) * 255);
            if (!alpha || a >= 0.999) return "#%02x%02x%02x".printf (ri, gi, bi);
            return "#%02x%02x%02x%02x".printf (ri, gi, bi, (int) Math.round (a.clamp (0, 1) * 255));
        }

        public void apply (Cairo.Context cr, double alpha = 1) {
            cr.set_source_rgba (r, g, b, a * alpha);
        }
    }

    public enum BrushKind {
        PENCIL,
        INK,
        MARKER,
        AIRBRUSH,
        TECHNICAL,
        ERASER;

        public string to_id () {
            switch (this) {
                case INK: return "ink";
                case MARKER: return "marker";
                case AIRBRUSH: return "airbrush";
                case TECHNICAL: return "technical";
                case ERASER: return "eraser";
                default: return "pencil";
            }
        }

        public static BrushKind from_id (string? id) {
            switch (id) {
                case "ink": return INK;
                case "marker": return MARKER;
                case "airbrush": return AIRBRUSH;
                case "technical": return TECHNICAL;
                case "eraser": return ERASER;
                default: return PENCIL;
            }
        }
    }

    public class Brush {
        public string id;
        public string name;
        public BrushKind kind = BrushKind.PENCIL;
        public double size = 2;
        public double min_size = 0.2;
        public double opacity = 1;
        public double hardness = 0.9;
        public double spacing = 0.15;
        public ResponseCurve pressure_curve = new ResponseCurve ();
        public bool pressure_size = true;
        public bool pressure_opacity;
        public double tilt_size;
        public double velocity_thin;
        public double texture;
        public double flow = 1;

        public Brush (string id, string name, BrushKind kind) {
            this.id = id;
            this.name = name;
            this.kind = kind;
        }

        public Brush copy () {
            var b = new Brush (id, name, kind);
            b.size = size;
            b.min_size = min_size;
            b.opacity = opacity;
            b.hardness = hardness;
            b.spacing = spacing;
            b.pressure_curve = pressure_curve.copy ();
            b.pressure_size = pressure_size;
            b.pressure_opacity = pressure_opacity;
            b.tilt_size = tilt_size;
            b.velocity_thin = velocity_thin;
            b.texture = texture;
            b.flow = flow;
            return b;
        }

        public double width_for (StrokeSample s, double speed) {
            double p = pressure_curve.map (s.pressure);
            double w = pressure_size ? min_size + (size - min_size) * p : size;
            if (tilt_size > 0) w *= 1 + tilt_size * s.tilt () * 2;
            if (velocity_thin > 0) w *= 1 - velocity_thin * (speed / (speed + 400)).clamp (0, 0.8);
            return double.max (w, 0.05);
        }

        public double alpha_for (StrokeSample s) {
            double p = pressure_curve.map (s.pressure);
            return opacity * (pressure_opacity ? 0.15 + 0.85 * p : 1);
        }

        public static Gee.ArrayList<Brush> presets () {
            var l = new Gee.ArrayList<Brush> ();
            var pencil = new Brush ("pencil", _("Pencil"), BrushKind.PENCIL);
            pencil.size = 1.2;
            pencil.min_size = 0.3;
            pencil.opacity = 0.85;
            pencil.pressure_opacity = true;
            pencil.tilt_size = 1.5;
            pencil.texture = 0.35;
            l.add (pencil);
            var ink = new Brush ("ink", _("Ink Pen"), BrushKind.INK);
            ink.size = 1.6;
            ink.min_size = 0.25;
            ink.velocity_thin = 0.4;
            ink.pressure_curve = new ResponseCurve (0.3, 0.1, 0.7, 0.9);
            l.add (ink);
            var tech = new Brush ("technical", _("Technical Pen"), BrushKind.TECHNICAL);
            tech.size = 0.5;
            tech.min_size = 0.5;
            tech.pressure_size = false;
            l.add (tech);
            var marker = new Brush ("marker", _("Design Marker"), BrushKind.MARKER);
            marker.size = 8;
            marker.min_size = 6;
            marker.opacity = 0.35;
            marker.hardness = 0.95;
            marker.tilt_size = 0.6;
            l.add (marker);
            var copic = new Brush ("marker-fine", _("Fine Marker"), BrushKind.MARKER);
            copic.size = 3;
            copic.min_size = 1.5;
            copic.opacity = 0.45;
            l.add (copic);
            var chisel = new Brush ("marker-chisel", _("Chisel Marker"), BrushKind.MARKER);
            chisel.size = 14;
            chisel.min_size = 4;
            chisel.opacity = 0.3;
            chisel.tilt_size = 1.4;
            chisel.pressure_size = false;
            l.add (chisel);
            var brushm = new Brush ("marker-brush", _("Brush Marker"), BrushKind.MARKER);
            brushm.size = 9;
            brushm.min_size = 0.8;
            brushm.opacity = 0.4;
            brushm.pressure_curve = new ResponseCurve (0.4, 0.1, 0.8, 0.7);
            l.add (brushm);
            var air = new Brush ("airbrush", _("Airbrush"), BrushKind.AIRBRUSH);
            air.size = 24;
            air.min_size = 8;
            air.opacity = 0.18;
            air.hardness = 0.1;
            air.pressure_opacity = true;
            l.add (air);
            var eraser = new Brush ("eraser", _("Eraser"), BrushKind.ERASER);
            eraser.size = 6;
            eraser.min_size = 2;
            l.add (eraser);
            return l;
        }
    }

    public class Stroke {
        public string brush_id = "pencil";
        public BrushKind kind = BrushKind.PENCIL;
        public Rgba color = Rgba (0.1, 0.1, 0.12, 1);
        public double size = 2;
        public double min_size = 0.2;
        public double opacity = 1;
        public double hardness = 0.9;
        public double texture;
        public ResponseCurve pressure_curve = new ResponseCurve ();
        public bool pressure_size = true;
        public bool pressure_opacity;
        public double tilt_size;
        public double velocity_thin;
        public Gee.ArrayList<StrokeSample?> samples = new Gee.ArrayList<StrokeSample?> ();
        public bool smooth_curve = true;
        public double started;

        public Stroke.from_brush (Brush b, Rgba color) {
            brush_id = b.id;
            kind = b.kind;
            this.color = color;
            size = b.size;
            min_size = b.min_size;
            opacity = b.opacity;
            hardness = b.hardness;
            texture = b.texture;
            pressure_curve = b.pressure_curve.copy ();
            pressure_size = b.pressure_size;
            pressure_opacity = b.pressure_opacity;
            tilt_size = b.tilt_size;
            velocity_thin = b.velocity_thin;
        }

        public Stroke () {
        }

        public Brush as_brush () {
            var b = new Brush (brush_id, brush_id, kind);
            b.size = size;
            b.min_size = min_size;
            b.opacity = opacity;
            b.hardness = hardness;
            b.texture = texture;
            b.pressure_curve = pressure_curve;
            b.pressure_size = pressure_size;
            b.pressure_opacity = pressure_opacity;
            b.tilt_size = tilt_size;
            b.velocity_thin = velocity_thin;
            return b;
        }

        public Stroke copy () {
            var s = new Stroke ();
            s.brush_id = brush_id;
            s.kind = kind;
            s.color = color;
            s.size = size;
            s.min_size = min_size;
            s.opacity = opacity;
            s.hardness = hardness;
            s.texture = texture;
            s.pressure_curve = pressure_curve.copy ();
            s.pressure_size = pressure_size;
            s.pressure_opacity = pressure_opacity;
            s.tilt_size = tilt_size;
            s.velocity_thin = velocity_thin;
            s.smooth_curve = smooth_curve;
            s.started = started;
            foreach (var p in samples) s.samples.add (p);
            return s;
        }

        public Rect bounds () {
            var r = Rect.empty ();
            foreach (var p in samples) r = r.include (p.x, p.y);
            return r.is_empty () ? r : r.inflate (size);
        }

        public void transform (Cairo.Matrix m) {
            for (int i = 0; i < samples.size; i++) {
                var s = samples[i];
                m.transform_point (ref s.x, ref s.y);
                samples[i] = s;
            }
            double sx = 1, sy = 0;
            m.transform_distance (ref sx, ref sy);
            double k = Math.hypot (sx, sy);
            size *= k;
            min_size *= k;
        }

        public Point[] centers () {
            Point[] pts = new Point[samples.size];
            for (int i = 0; i < samples.size; i++) pts[i] = Point (samples[i].x, samples[i].y);
            return pts;
        }

        public double distance_to (double x, double y) {
            double best = double.INFINITY;
            for (int i = 0; i < samples.size; i++) {
                var a = samples[i];
                if (i == 0) best = Math.hypot (a.x - x, a.y - y);
                if (i + 1 < samples.size) {
                    var b = samples[i + 1];
                    best = double.min (best, PathData.segment_distance (Point (a.x, a.y), Point (b.x, b.y), x, y));
                }
            }
            return best;
        }

        public void outline (out Point[] centers_out, out double[] widths, out double[] alphas) {
            var b = as_brush ();
            int n = samples.size;
            Point[] raw = new Point[n];
            double[] w = new double[n];
            double[] al = new double[n];
            for (int i = 0; i < n; i++) {
                var s = samples[i];
                double speed = 0;
                if (i > 0) {
                    var p = samples[i - 1];
                    double dt = s.time - p.time;
                    if (dt > 1e-4) speed = Math.hypot (s.x - p.x, s.y - p.y) / dt;
                }
                raw[i] = Point (s.x, s.y);
                w[i] = b.width_for (s, speed);
                al[i] = b.alpha_for (s);
            }
            if (smooth_curve && n > 3) {
                Point[] sm = {};
                double[] sw = {};
                double[] sa = {};
                for (int i = 0; i < n - 1; i++) {
                    var p0 = raw[int.max (0, i - 1)];
                    var p1 = raw[i];
                    var p2 = raw[i + 1];
                    var p3 = raw[int.min (n - 1, i + 2)];
                    var bz = Bezier (p1, Point (p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6),
                        Point (p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6), p2);
                    int steps = int.max (1, (int) (p1.distance (p2) / 1.5));
                    steps = int.min (steps, 12);
                    for (int k = (i == 0 ? 0 : 1); k <= steps; k++) {
                        double t = (double) k / steps;
                        sm += bz.at (t);
                        sw += w[i] + (w[i + 1] - w[i]) * t;
                        sa += al[i] + (al[i + 1] - al[i]) * t;
                    }
                }
                centers_out = sm;
                widths = sw;
                alphas = sa;
                return;
            }
            centers_out = raw;
            widths = w;
            alphas = al;
        }
    }

    public class FillRegion {
        public PathData path = new PathData ();
        public string mode = "solid";
        public Rgba color = Rgba (0.8, 0.8, 0.8, 1);
        public Rgba color2 = Rgba (1, 1, 1, 1);
        public double x1;
        public double y1;
        public double x2;
        public double y2;
        public double opacity = 1;

        public FillRegion copy () {
            var f = new FillRegion ();
            f.path = path.copy ();
            f.mode = mode;
            f.color = color;
            f.color2 = color2;
            f.x1 = x1;
            f.y1 = y1;
            f.x2 = x2;
            f.y2 = y2;
            f.opacity = opacity;
            return f;
        }

        public void set_source (Cairo.Context cr) {
            if (mode == "linear" || mode == "radial") {
                Cairo.Pattern pat;
                if (mode == "linear") pat = new Cairo.Pattern.linear (x1, y1, x2, y2);
                else pat = new Cairo.Pattern.radial (x1, y1, 0, x1, y1, Math.hypot (x2 - x1, y2 - y1));
                pat.add_color_stop_rgba (0, color.r, color.g, color.b, color.a * opacity);
                pat.add_color_stop_rgba (1, color2.r, color2.g, color2.b, color2.a * opacity);
                cr.set_source (pat);
            } else {
                color.apply (cr, opacity);
            }
        }
    }

    public enum LayerKind {
        STROKES,
        IMAGE,
        GROUP,
        UNDERLAY
    }

    public class SketchLayer {
        public string id;
        public string name;
        public LayerKind kind = LayerKind.STROKES;
        public bool visible = true;
        public bool locked;
        public double opacity = 1;
        public string blend = "normal";
        public Gee.ArrayList<Stroke> strokes = new Gee.ArrayList<Stroke> ();
        public Gee.ArrayList<FillRegion> fills = new Gee.ArrayList<FillRegion> ();
        public Gee.ArrayList<SketchLayer> children = new Gee.ArrayList<SketchLayer> ();
        public string image_name = "";
        public Bytes? image_data;
        public Cairo.ImageSurface? image_cache;
        public Cairo.Matrix image_matrix = Cairo.Matrix.identity ();
        public string underlay = "";
        public Gee.HashMap<string, double?> underlay_params = new Gee.HashMap<string, double?> ();

        public SketchLayer (string id, string name, LayerKind kind = LayerKind.STROKES) {
            this.id = id;
            this.name = name;
            this.kind = kind;
        }

        public Cairo.ImageSurface? image () {
            if (image_cache == null && image_data != null) image_cache = load_png (image_data);
            return image_cache;
        }

        public static Cairo.ImageSurface? load_png (Bytes data) {
            try {
                var stream = new MemoryInputStream.from_bytes (data);
                var pb = new Gdk.Pixbuf.from_stream (stream);
                var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, pb.width, pb.height);
                var cr = new Cairo.Context (surf);
                Gdk.cairo_set_source_pixbuf (cr, pb, 0, 0);
                cr.paint ();
                return surf;
            } catch (Error e) {
                return null;
            }
        }

        public Rect bounds () {
            var r = Rect.empty ();
            foreach (var s in strokes) r = r.union (s.bounds ());
            foreach (var f in fills) r = r.union (f.path.bounds ());
            foreach (var c in children) r = r.union (c.bounds ());
            if (kind == LayerKind.IMAGE && image () != null) {
                var img = image ();
                double[] xs = { 0, img.get_width () };
                double[] ys = { 0, img.get_height () };
                foreach (var x in xs) foreach (var y in ys) {
                    double tx = x, ty = y;
                    image_matrix.transform_point (ref tx, ref ty);
                    r = r.include (tx, ty);
                }
            }
            return r;
        }
    }

    public class Sketch {
        public Gee.ArrayList<SketchLayer> layers = new Gee.ArrayList<SketchLayer> ();
        public Gee.ArrayList<Brush> brushes = Brush.presets ();
        public Rgba paper = Rgba (1, 1, 1, 1);
        public Guides guides = new Guides ();
        public Gee.ArrayList<TimelapseEvent> timelapse = new Gee.ArrayList<TimelapseEvent> ();
        public bool record_timelapse = true;
        private int next_id = 1;

        public Sketch () {
            layers.add (new SketchLayer (new_id (), _("Layer 1")));
        }

        public string new_id () {
            while (true) {
                string id = "l%d".printf (next_id++);
                if (find_layer (id) == null) return id;
            }
        }

        public SketchLayer? find_layer (string id) {
            foreach (var l in all_layers ()) if (l.id == id) return l;
            return null;
        }

        public Gee.List<SketchLayer> all_layers () {
            var r = new Gee.ArrayList<SketchLayer> ();
            foreach (var l in layers) collect (l, r);
            return r;
        }

        private void collect (SketchLayer l, Gee.List<SketchLayer> r) {
            r.add (l);
            foreach (var c in l.children) collect (c, r);
        }

        public Brush? find_brush (string id) {
            foreach (var b in brushes) if (b.id == id) return b;
            return null;
        }

        public Rect bounds () {
            var r = Rect.empty ();
            foreach (var l in layers) if (l.visible) r = r.union (l.bounds ());
            return r;
        }
    }

    public class TimelapseEvent {
        public string layer;
        public int stroke_index;
        public double time;

        public TimelapseEvent (string layer, int stroke_index, double time) {
            this.layer = layer;
            this.stroke_index = stroke_index;
            this.time = time;
        }
    }
}
