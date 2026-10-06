using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public enum SymmetryMode {
        NONE,
        VERTICAL,
        HORIZONTAL,
        BOTH,
        RADIAL;

        public string to_id () {
            switch (this) {
                case VERTICAL: return "vertical";
                case HORIZONTAL: return "horizontal";
                case BOTH: return "both";
                case RADIAL: return "radial";
                default: return "none";
            }
        }

        public static SymmetryMode from_id (string? id) {
            switch (id) {
                case "vertical": return VERTICAL;
                case "horizontal": return HORIZONTAL;
                case "both": return BOTH;
                case "radial": return RADIAL;
                default: return NONE;
            }
        }
    }

    public class Guides {
        public bool ruler_on;
        public Point ruler_a = Point (100, 300);
        public Point ruler_b = Point (500, 300);
        public bool ellipse_on;
        public Point ellipse_center = Point (300, 300);
        public double ellipse_rx = 160;
        public double ellipse_ry = 80;
        public double ellipse_angle;
        public bool curve_on;
        public string curve_template = "french-1";
        public Point curve_pos = Point (300, 300);
        public double curve_scale = 1;
        public double curve_angle;
        public PathData? custom_curve;
        public int perspective;
        public Point horizon_a = Point (0, 250);
        public Point vp1 = Point (-200, 250);
        public Point vp2 = Point (900, 250);
        public Point vp3 = Point (350, 2000);
        public SymmetryMode symmetry = SymmetryMode.NONE;
        public Point symmetry_center = Point (350, 350);
        public int radial_count = 6;
        public double snap_distance = 24;
        public bool snap_enabled = true;

        public PathData? curve_path () {
            PathData p;
            if (curve_template == "custom" && custom_curve != null) {
                p = custom_curve.copy ();
            } else {
                p = FrenchCurves.template (curve_template);
            }
            var m = Cairo.Matrix.identity ();
            m.translate (curve_pos.x, curve_pos.y);
            m.rotate (curve_angle * Math.PI / 180);
            m.scale (curve_scale, curve_scale);
            p.transform (m);
            return p;
        }

        public bool any_snap () {
            return snap_enabled && (ruler_on || ellipse_on || curve_on || perspective > 0);
        }

        public string? pick_guide (Point start, Point dir_hint, double scale) {
            double tol = snap_distance / double.max (scale, 1e-6);
            if (ruler_on && PathData.segment_distance (extend (ruler_a, ruler_b, -1e5), extend (ruler_a, ruler_b, 1e5), start.x, start.y) < tol) return "ruler";
            if (ellipse_on && (ellipse_distance (start) < tol)) return "ellipse";
            if (curve_on) {
                var cp = curve_path ();
                if (cp != null && cp.distance_to (start.x, start.y) < tol) return "curve";
            }
            if (perspective > 0) return "perspective";
            return null;
        }

        private static Point extend (Point a, Point b, double t) {
            double dx = b.x - a.x, dy = b.y - a.y;
            double l = Math.hypot (dx, dy);
            if (l < 1e-9) return a;
            return Point (a.x + dx / l * t, a.y + dy / l * t);
        }

        private Point to_ellipse_local (Point p) {
            double r = -ellipse_angle * Math.PI / 180;
            double dx = p.x - ellipse_center.x, dy = p.y - ellipse_center.y;
            return Point (dx * Math.cos (r) - dy * Math.sin (r), dx * Math.sin (r) + dy * Math.cos (r));
        }

        private Point from_ellipse_local (Point p) {
            double r = ellipse_angle * Math.PI / 180;
            return Point (ellipse_center.x + p.x * Math.cos (r) - p.y * Math.sin (r), ellipse_center.y + p.x * Math.sin (r) + p.y * Math.cos (r));
        }

        public double ellipse_distance (Point p) {
            var q = project_ellipse (p);
            return q.distance (p);
        }

        public Point project_ellipse (Point p) {
            var l = to_ellipse_local (p);
            double ang = Math.atan2 (l.y * ellipse_rx, l.x * ellipse_ry);
            for (int i = 0; i < 6; i++) {
                double c = Math.cos (ang), s = Math.sin (ang);
                double ex = ellipse_rx * c, ey = ellipse_ry * s;
                double dx = -ellipse_rx * s, dy = ellipse_ry * c;
                double ddx = -ellipse_rx * c, ddy = -ellipse_ry * s;
                double f = (ex - l.x) * dx + (ey - l.y) * dy;
                double df = dx * dx + dy * dy + (ex - l.x) * ddx + (ey - l.y) * ddy;
                if (df.abs () < 1e-12) break;
                ang -= f / df;
            }
            return from_ellipse_local (Point (ellipse_rx * Math.cos (ang), ellipse_ry * Math.sin (ang)));
        }

        public Point project_line (Point a, Point b, Point p) {
            double dx = b.x - a.x, dy = b.y - a.y;
            double l2 = dx * dx + dy * dy;
            if (l2 < 1e-12) return a;
            double t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2;
            return Point (a.x + dx * t, a.y + dy * t);
        }

        public Point project_path (PathData path, Point p) {
            var best = p;
            double bd = double.INFINITY;
            foreach (var poly in path.flatten (0.3)) {
                int n = poly.pts.length;
                int lim = poly.closed ? n : n - 1;
                for (int i = 0; i < lim; i++) {
                    var q = project_line (poly.pts[i], poly.pts[(i + 1) % n], p);
                    double dx = poly.pts[(i + 1) % n].x - poly.pts[i].x, dy = poly.pts[(i + 1) % n].y - poly.pts[i].y;
                    double l2 = dx * dx + dy * dy;
                    double t = l2 > 0 ? ((p.x - poly.pts[i].x) * dx + (p.y - poly.pts[i].y) * dy) / l2 : 0;
                    if (t < 0) q = poly.pts[i];
                    else if (t > 1) q = poly.pts[(i + 1) % n];
                    double d = q.distance (p);
                    if (d < bd) {
                        bd = d;
                        best = q;
                    }
                }
            }
            return best;
        }

        public Point[] vanishing_points () {
            Point[] v = {};
            if (perspective >= 1) v += vp1;
            if (perspective >= 2) v += vp2;
            if (perspective >= 3) v += vp3;
            return v;
        }

        public void perspective_axis (Point start, Point probe, out Point a, out Point b) {
            double dx = probe.x - start.x, dy = probe.y - start.y;
            double dl = Math.hypot (dx, dy);
            a = start;
            b = Point (start.x + 1, start.y);
            double best = -1;
            Point[] candidates = {};
            foreach (var v in vanishing_points ()) candidates += v;
            if (perspective == 1) {
                candidates += Point (start.x + 1000, start.y);
                candidates += Point (start.x, start.y + 1000);
            } else if (perspective == 2) {
                candidates += Point (start.x, start.y + 1000);
            }
            foreach (var c in candidates) {
                double cx = c.x - start.x, cy = c.y - start.y;
                double cl = Math.hypot (cx, cy);
                if (cl < 1e-9 || dl < 1e-9) continue;
                double score = ((cx * dx + cy * dy) / (cl * dl)).abs ();
                if (score > best) {
                    best = score;
                    b = c;
                }
            }
        }

        public Gee.ArrayList<Cairo.Matrix?> symmetry_transforms () {
            var list = new Gee.ArrayList<Cairo.Matrix?> ();
            double cx = symmetry_center.x, cy = symmetry_center.y;
            switch (symmetry) {
                case SymmetryMode.VERTICAL:
                    list.add (Cairo.Matrix (-1, 0, 0, 1, 2 * cx, 0));
                    break;
                case SymmetryMode.HORIZONTAL:
                    list.add (Cairo.Matrix (1, 0, 0, -1, 0, 2 * cy));
                    break;
                case SymmetryMode.BOTH:
                    list.add (Cairo.Matrix (-1, 0, 0, 1, 2 * cx, 0));
                    list.add (Cairo.Matrix (1, 0, 0, -1, 0, 2 * cy));
                    list.add (Cairo.Matrix (-1, 0, 0, -1, 2 * cx, 2 * cy));
                    break;
                case SymmetryMode.RADIAL: {
                    int n = int.max (2, radial_count);
                    for (int i = 1; i < n; i++) {
                        var m = Cairo.Matrix.identity ();
                        m.translate (cx, cy);
                        m.rotate (2 * Math.PI * i / n);
                        m.translate (-cx, -cy);
                        list.add (m);
                    }
                    break;
                }
                default:
                    break;
            }
            return list;
        }
    }

    public class GuideSnapper {
        private Guides guides;
        private string? mode;
        private Point start;
        private Point axis_a;
        private Point axis_b;
        private bool axis_ready;
        private double scale;
        private Gee.ArrayList<Point?> early = new Gee.ArrayList<Point?> ();

        public GuideSnapper (Guides guides, Point start, double scale) {
            this.guides = guides;
            this.start = start;
            this.scale = scale;
            mode = guides.snap_enabled ? guides.pick_guide (start, start, scale) : null;
        }

        public bool active {
            get { return mode != null; }
        }

        public Point apply (Point p) {
            if (mode == null) return p;
            switch (mode) {
                case "ruler":
                    return guides.project_line (guides.ruler_a, guides.ruler_b, p);
                case "ellipse":
                    return guides.project_ellipse (p);
                case "curve": {
                    var cp = guides.curve_path ();
                    return cp != null ? guides.project_path (cp, p) : p;
                }
                case "perspective":
                    if (!axis_ready) {
                        early.add (p);
                        if (p.distance (start) < 6 / double.max (scale, 1e-6)) return start;
                        guides.perspective_axis (start, p, out axis_a, out axis_b);
                        axis_ready = true;
                    }
                    return guides.project_line (axis_a, axis_b, p);
            }
            return p;
        }
    }

    namespace FrenchCurves {
        public const string[] IDS = { "french-1", "french-2", "hip-curve", "armhole", "sleeve-cap" };

        public string label (string id) {
            switch (id) {
                case "french-1": return _("French Curve");
                case "french-2": return _("Small French Curve");
                case "hip-curve": return _("Hip Curve");
                case "armhole": return _("Armhole Curve");
                case "sleeve-cap": return _("Sleeve Cap Curve");
                case "custom": return _("Custom Curve");
            }
            return id;
        }

        public PathData template (string id) {
            switch (id) {
                case "french-2":
                    return PathData.parse_svg ("M0 0 C30 -40 90 -60 130 -30 C160 -8 150 40 110 50 C80 58 60 40 70 20");
                case "hip-curve":
                    return PathData.parse_svg ("M0 0 C80 -4 180 -20 260 -60 C300 -80 330 -110 350 -150");
                case "armhole":
                    return PathData.parse_svg ("M0 0 C0 60 20 110 70 130 C100 142 130 140 150 130");
                case "sleeve-cap":
                    return PathData.parse_svg ("M0 0 C40 -10 70 -80 130 -90 C190 -80 220 -10 260 0");
                default:
                    return PathData.parse_svg ("M0 0 C20 -60 80 -110 160 -100 C230 -90 260 -30 230 20 C210 55 160 70 120 50 C90 35 80 10 100 -10");
            }
        }
    }

    public enum ShapeGuess {
        NONE,
        LINE,
        ARC,
        ELLIPSE
    }

    public class StrokeRecognizer {
        public static ShapeGuess guess (Point[] pts, out Point[] result) {
            result = pts;
            if (pts.length < 4) return ShapeGuess.NONE;
            double len = Polyline.length (pts);
            if (len < 8) return ShapeGuess.NONE;
            var a = pts[0];
            var b = pts[pts.length - 1];
            double chord = a.distance (b);
            double maxd = 0;
            foreach (var p in pts) maxd = double.max (maxd, PathData.segment_distance (a, b, p.x, p.y));
            if (chord > len * 0.9 && maxd < double.max (2, chord * 0.035)) {
                result = { a, b };
                return ShapeGuess.LINE;
            }
            if (chord < len * 0.15) {
                var r = Rect.empty ();
                foreach (var p in pts) r = r.include (p.x, p.y);
                double cx = r.cx (), cy = r.cy (), rx = r.w / 2, ry = r.h / 2;
                double err = 0;
                foreach (var p in pts) {
                    double nx = (p.x - cx) / double.max (rx, 1e-6), ny = (p.y - cy) / double.max (ry, 1e-6);
                    err += (Math.hypot (nx, ny) - 1).abs ();
                }
                err /= pts.length;
                if (err < 0.12) {
                    Point[] e = {};
                    for (int i = 0; i <= 72; i++) {
                        double t = 2 * Math.PI * i / 72;
                        e += Point (cx + rx * Math.cos (t), cy + ry * Math.sin (t));
                    }
                    result = e;
                    return ShapeGuess.ELLIPSE;
                }
                return ShapeGuess.NONE;
            }
            var m = pts[pts.length / 2];
            Point center;
            double radius;
            if (circle3 (a, m, b, out center, out radius) && radius < len * 4) {
                double err = 0;
                foreach (var p in pts) err += (p.distance (center) - radius).abs ();
                err /= pts.length;
                if (err < double.max (1.5, radius * 0.04)) {
                    double a0 = Math.atan2 (a.y - center.y, a.x - center.x);
                    double am = Math.atan2 (m.y - center.y, m.x - center.x);
                    double a1 = Math.atan2 (b.y - center.y, b.x - center.x);
                    double sweep = norm (a1 - a0);
                    double half = norm (am - a0);
                    if ((sweep > 0) != (half > 0) || half.abs () > sweep.abs ()) sweep = sweep > 0 ? sweep - 2 * Math.PI : sweep + 2 * Math.PI;
                    Point[] arc = {};
                    int steps = int.max (8, (int) (sweep.abs () * radius / 3));
                    steps = int.min (steps, 240);
                    for (int i = 0; i <= steps; i++) {
                        double t = a0 + sweep * i / steps;
                        arc += Point (center.x + radius * Math.cos (t), center.y + radius * Math.sin (t));
                    }
                    result = arc;
                    return ShapeGuess.ARC;
                }
            }
            return ShapeGuess.NONE;
        }

        private static double norm (double a) {
            while (a > Math.PI) a -= 2 * Math.PI;
            while (a < -Math.PI) a += 2 * Math.PI;
            return a;
        }

        public static bool circle3 (Point a, Point b, Point c, out Point center, out double radius) {
            center = Point (0, 0);
            radius = 0;
            double d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y));
            if (d.abs () < 1e-9) return false;
            double a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y;
            double ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d;
            double uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d;
            center = Point (ux, uy);
            radius = center.distance (a);
            return true;
        }

        public static Point[] predictive (Point[] pts, double tolerance) {
            if (pts.length < 3) return pts;
            var fit = CurveFit.fit (Polyline.simplify (pts, tolerance * 0.5), tolerance);
            Point[] out_pts = {};
            foreach (var bz in fit) {
                var f = bz.flatten (0.3);
                for (int i = (out_pts.length == 0 ? 0 : 1); i < f.length; i++) out_pts += f[i];
            }
            return out_pts;
        }

        public static Point[] resample_to (Point[] shape, int count) {
            if (shape.length < 2) return shape;
            return Polyline.resample (shape, Polyline.length (shape) / int.max (1, count));
        }
    }
}
