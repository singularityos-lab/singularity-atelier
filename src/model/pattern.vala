using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public enum PointKind {
        BASE,
        END_LINE,
        ALONG_LINE,
        NORMAL,
        MIDPOINT,
        INTERSECT,
        ALONG_CURVE,
        FOOT,
        ROTATE,
        OFFSET,
        BISECTOR,
        CIRCLE_LINE,
        XY,
        LINE_AXIS,
        CURVE_AXIS,
        CIRCLE_CONTACT;

        public string to_id () {
            switch (this) {
                case END_LINE: return "end-line";
                case ALONG_LINE: return "along-line";
                case NORMAL: return "normal";
                case MIDPOINT: return "midpoint";
                case INTERSECT: return "intersect";
                case ALONG_CURVE: return "along-curve";
                case FOOT: return "foot";
                case ROTATE: return "rotate";
                case OFFSET: return "offset";
                case BISECTOR: return "bisector";
                case CIRCLE_LINE: return "circle-line";
                case XY: return "xy";
                case LINE_AXIS: return "line-axis";
                case CURVE_AXIS: return "curve-axis";
                case CIRCLE_CONTACT: return "circle-contact";
                default: return "base";
            }
        }

        public static PointKind from_id (string? id) {
            switch (id) {
                case "end-line": return END_LINE;
                case "along-line": return ALONG_LINE;
                case "normal": return NORMAL;
                case "midpoint": return MIDPOINT;
                case "intersect": return INTERSECT;
                case "along-curve": return ALONG_CURVE;
                case "foot": return FOOT;
                case "rotate": return ROTATE;
                case "offset": return OFFSET;
                case "bisector": return BISECTOR;
                case "circle-line": return CIRCLE_LINE;
                case "xy": return XY;
                case "line-axis": return LINE_AXIS;
                case "curve-axis": return CURVE_AXIS;
                case "circle-contact": return CIRCLE_CONTACT;
                default: return BASE;
            }
        }

        public string label () {
            switch (this) {
                case END_LINE: return _("Length and Angle");
                case ALONG_LINE: return _("Along a Line");
                case NORMAL: return _("Perpendicular");
                case MIDPOINT: return _("Midpoint");
                case INTERSECT: return _("Intersection of Lines");
                case ALONG_CURVE: return _("Along a Curve");
                case FOOT: return _("Foot of Perpendicular");
                case ROTATE: return _("Rotated Point");
                case OFFSET: return _("Moved Point");
                case BISECTOR: return _("Bisector");
                case CIRCLE_LINE: return _("Distance from a Point on a Line");
                case XY: return _("X of One Point, Y of Another");
                case LINE_AXIS: return _("Line and Axis");
                case CURVE_AXIS: return _("Curve and Axis");
                case CIRCLE_CONTACT: return _("Circle and Line");
                default: return _("Base Point");
            }
        }
    }

    public class PatternPoint {
        public string id;
        public string name;
        public PointKind kind = PointKind.BASE;
        public string a = "";
        public string b = "";
        public string c = "";
        public string d = "";
        public string fx = "0";
        public string fy = "0";
        public string flength = "0";
        public string fangle = "0";
        public int rule;
        public double label_dx = 2;
        public double label_dy = -2;
        public bool hidden;

        public PatternPoint (string id, string name) {
            this.id = id;
            this.name = name;
        }

        public string[] refs () {
            string[] r = {};
            foreach (var s in new string[] { a, b, c, d }) if (s != "") r += s;
            return r;
        }
    }

    public class CurveKnot {
        public string point;
        public string angle_in = "";
        public string len_in = "";
        public string angle_out = "";
        public string len_out = "";

        public CurveKnot (string point) {
            this.point = point;
        }
    }

    public enum CurveKind {
        LINE,
        PATH,
        AUTO,
        SEGMENT
    }

    public class PatternCurve {
        public string id;
        public string name;
        public CurveKind kind = CurveKind.PATH;
        public Gee.ArrayList<CurveKnot> knots = new Gee.ArrayList<CurveKnot> ();
        public string tension = "1";
        public string parent = "";
        public string target_length = "";

        public PatternCurve (string id, string name) {
            this.id = id;
            this.name = name;
        }
    }

    public class PieceNode {
        public string ref_id;
        public bool is_curve;
        public bool reverse;
        public string sa_after = "";
        public CornerStyle corner = CornerStyle.INTERSECT;
        public bool notch;
        public string notch_type = "slit";

        public PieceNode (string ref_id, bool is_curve = false) {
            this.ref_id = ref_id;
            this.is_curve = is_curve;
        }
    }

    public class ExtraNotch {
        public int edge;
        public double distance;
        public string type = "slit";

        public ExtraNotch (int edge, double distance) {
            this.edge = edge;
            this.distance = distance;
        }
    }

    public class DrillHole {
        public string point = "";
        public double dx;
        public double dy;
        public double diameter = 3;
    }

    public class InternalLine {
        public Gee.ArrayList<string> refs = new Gee.ArrayList<string> ();
        public string kind = "line";
    }

    public class FixedGeometry {
        public Point[] seam = {};
        public Point[] cut = {};
        public Gee.ArrayList<FixedNotch> notches = new Gee.ArrayList<FixedNotch> ();
        public Gee.ArrayList<Point?> drills = new Gee.ArrayList<Point?> ();
        public Gee.ArrayList<PointList> internals = new Gee.ArrayList<PointList> ();
        public Point grain_a = Point (0, 0);
        public Point grain_b = Point (0, 0);
        public bool has_grain;

        public FixedGeometry copy () {
            var g = new FixedGeometry ();
            g.seam = seam;
            g.cut = cut;
            foreach (var n in notches) g.notches.add (new FixedNotch (n.at, n.angle, n.type, n.length));
            foreach (var d in drills) g.drills.add (d);
            foreach (var i in internals) g.internals.add (new PointList (i.pts));
            g.grain_a = grain_a;
            g.grain_b = grain_b;
            g.has_grain = has_grain;
            return g;
        }

        public void translate (double dx, double dy) {
            seam = shift (seam, dx, dy);
            cut = shift (cut, dx, dy);
            foreach (var n in notches) n.at = Point (n.at.x + dx, n.at.y + dy);
            for (int i = 0; i < drills.size; i++) drills[i] = Point (drills[i].x + dx, drills[i].y + dy);
            foreach (var l in internals) l.pts = shift (l.pts, dx, dy);
            grain_a = Point (grain_a.x + dx, grain_a.y + dy);
            grain_b = Point (grain_b.x + dx, grain_b.y + dy);
        }

        private static Point[] shift (Point[] pts, double dx, double dy) {
            Point[] r = new Point[pts.length];
            for (int i = 0; i < pts.length; i++) r[i] = Point (pts[i].x + dx, pts[i].y + dy);
            return r;
        }
    }

    public class FixedNotch {
        public Point at;
        public double angle;
        public string type;
        public double length;

        public FixedNotch (Point at, double angle, string type = "slit", double length = 6) {
            this.at = at;
            this.angle = angle;
            this.type = type;
            this.length = length;
        }
    }

    public class PointList {
        public Point[] pts;

        public PointList (Point[] pts) {
            this.pts = pts;
        }
    }

    public class Piece {
        public string id;
        public string name;
        public string code = "";
        public string material = "fabric";
        public int quantity = 1;
        public bool pair;
        public bool on_fold;
        public int fold_edge = -1;
        public string seam_allowance = "1";
        public bool built_in;
        public Gee.ArrayList<PieceNode> nodes = new Gee.ArrayList<PieceNode> ();
        public Gee.ArrayList<ExtraNotch> extra_notches = new Gee.ArrayList<ExtraNotch> ();
        public Gee.ArrayList<DrillHole> drills = new Gee.ArrayList<DrillHole> ();
        public Gee.ArrayList<InternalLine> internals = new Gee.ArrayList<InternalLine> ();
        public string grain_a = "";
        public string grain_b = "";
        public double grain_angle = 90;
        public int grain_arrows;
        public string label = "{name}\n{size}\n{cut}";
        public double place_x;
        public double place_y;
        public double rotation;
        public bool flipped;
        public string placement = "front";
        public string leather_turn = "";
        public string leather_skive = "";
        public double thickness;
        public FixedGeometry? fixed;
        public Gee.HashMap<string, FixedGeometry> fixed_sizes = new Gee.HashMap<string, FixedGeometry> ();

        public Piece (string id, string name) {
            this.id = id;
            this.name = name;
        }

        public bool is_fixed () {
            return fixed != null;
        }
    }

    public class Increment {
        public string name;
        public string formula;
        public string description = "";

        public Increment (string name, string formula) {
            this.name = name;
            this.formula = formula;
        }
    }

    public class NotchGeometry {
        public Point seam_at;
        public Point cut_at;
        public double angle;
        public string type;
        public double length = 6;
        public double width = 3;
    }

    public class PieceGeometry {
        public Piece piece;
        public Point[] seam = {};
        public Point[] cut = {};
        public Gee.ArrayList<PointList> edges = new Gee.ArrayList<PointList> ();
        public Gee.ArrayList<NotchGeometry> notches = new Gee.ArrayList<NotchGeometry> ();
        public Gee.ArrayList<Point?> drills = new Gee.ArrayList<Point?> ();
        public Gee.ArrayList<double?> drill_sizes = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<PointList> internals = new Gee.ArrayList<PointList> ();
        public Point grain_a;
        public Point grain_b;
        public bool has_grain;
        public string error = "";

        public PieceGeometry (Piece piece) {
            this.piece = piece;
        }

        public Rect bounds () {
            var r = Rect.empty ();
            foreach (var p in (cut.length > 0 ? cut : seam)) r = r.include (p.x, p.y);
            return r;
        }

        public double area () {
            return Polyline.signed_area (cut.length > 0 ? cut : seam).abs ();
        }

        public Point center () {
            var b = bounds ();
            return Point (b.cx (), b.cy ());
        }

        public Cairo.Matrix placement_matrix () {
            var c = center ();
            var m = Cairo.Matrix.identity ();
            m.translate (piece.place_x, piece.place_y);
            m.translate (c.x, c.y);
            m.rotate (piece.rotation * Math.PI / 180);
            if (piece.flipped) m.scale (-1, 1);
            m.translate (-c.x, -c.y);
            return m;
        }

        public PieceGeometry transformed (Cairo.Matrix m) {
            var g = new PieceGeometry (piece);
            g.seam = xf (seam, m);
            g.cut = xf (cut, m);
            foreach (var e in edges) g.edges.add (new PointList (xf (e.pts, m)));
            foreach (var n in notches) {
                var nn = new NotchGeometry ();
                nn.seam_at = xp (n.seam_at, m);
                nn.cut_at = xp (n.cut_at, m);
                double dx = Math.cos (n.angle), dy = Math.sin (n.angle);
                m.transform_distance (ref dx, ref dy);
                nn.angle = Math.atan2 (dy, dx);
                nn.type = n.type;
                nn.length = n.length;
                nn.width = n.width;
                g.notches.add (nn);
            }
            foreach (var d in drills) g.drills.add (xp (d, m));
            g.drill_sizes.add_all (drill_sizes);
            foreach (var l in internals) g.internals.add (new PointList (xf (l.pts, m)));
            g.grain_a = xp (grain_a, m);
            g.grain_b = xp (grain_b, m);
            g.has_grain = has_grain;
            g.error = error;
            return g;
        }

        private static Point xp (Point p, Cairo.Matrix m) {
            double x = p.x, y = p.y;
            m.transform_point (ref x, ref y);
            return Point (x, y);
        }

        private static Point[] xf (Point[] pts, Cairo.Matrix m) {
            Point[] r = new Point[pts.length];
            for (int i = 0; i < pts.length; i++) r[i] = xp (pts[i], m);
            return r;
        }

        public double edge_length (int i) {
            if (i < 0 || i >= edges.size) return 0;
            return Polyline.length (edges[i].pts);
        }
    }

    public class PatternResult {
        public string size;
        public Gee.HashMap<string, Point?> points = new Gee.HashMap<string, Point?> ();
        public Gee.HashMap<string, Gee.ArrayList<Bezier?>> curves = new Gee.HashMap<string, Gee.ArrayList<Bezier?>> ();
        public Gee.HashMap<string, string> errors = new Gee.HashMap<string, string> ();
        public Gee.ArrayList<PieceGeometry> pieces = new Gee.ArrayList<PieceGeometry> ();

        public PieceGeometry? piece (string id) {
            foreach (var p in pieces) if (p.piece.id == id) return p;
            return null;
        }
    }

    public class Pattern {
        public string unit = "cm";
        public MeasurementTable table;
        public Gee.ArrayList<Increment> increments = new Gee.ArrayList<Increment> ();
        public Gee.ArrayList<PatternPoint> points = new Gee.ArrayList<PatternPoint> ();
        public Gee.ArrayList<PatternCurve> curves = new Gee.ArrayList<PatternCurve> ();
        public Gee.ArrayList<Piece> pieces = new Gee.ArrayList<Piece> ();
        public GradeRuleTable rules = new GradeRuleTable ();
        public string grading = "measurements";
        public string active_size = "";
        private int next_id = 1;

        public Pattern () {
            table = MeasurementTable.standard_women ();
            active_size = table.base_size;
        }

        public double unit_mm () {
            switch (unit) {
                case "mm": return 1;
                case "inch": case "in": return 25.4;
                default: return 10;
            }
        }

        public string new_id (string prefix) {
            while (true) {
                string id = "%s%d".printf (prefix, next_id++);
                if (find_point (id) == null && find_curve (id) == null && find_piece (id) == null) return id;
            }
        }

        public void bump_ids (string id) {
            int i = 0;
            while (i < id.length && !id[i].isdigit ()) i++;
            int n = int.parse (id.substring (i));
            if (n >= next_id) next_id = n + 1;
        }

        public PatternPoint? find_point (string id) {
            foreach (var p in points) if (p.id == id) return p;
            return null;
        }

        public PatternPoint? point_by_name (string name) {
            foreach (var p in points) if (p.name == name) return p;
            return null;
        }

        public PatternCurve? find_curve (string id) {
            foreach (var c in curves) if (c.id == id) return c;
            return null;
        }

        public PatternCurve? curve_by_name (string name) {
            foreach (var c in curves) if (c.name == name) return c;
            return null;
        }

        public Piece? find_piece (string id) {
            foreach (var p in pieces) if (p.id == id) return p;
            return null;
        }

        public string next_point_name () {
            int i = 0;
            while (true) {
                string n = "";
                int k = i;
                do {
                    n = ((char) ('A' + k % 26)).to_string () + n;
                    k = k / 26 - 1;
                } while (k >= 0);
                if (point_by_name (n) == null) return n;
                i++;
            }
        }

        public PatternPoint add_point (PointKind kind, string? name = null) {
            var p = new PatternPoint (new_id ("p"), name ?? next_point_name ());
            p.kind = kind;
            points.add (p);
            return p;
        }

        public PatternCurve add_curve (string[] point_ids, CurveKind kind = CurveKind.AUTO) {
            string nm = "Spl";
            foreach (var pid in point_ids) {
                var pp = find_point (pid);
                nm += "_" + (pp != null ? pp.name : pid);
            }
            var c = new PatternCurve (new_id ("c"), nm);
            c.kind = kind;
            foreach (var pid in point_ids) c.knots.add (new CurveKnot (pid));
            curves.add (c);
            return c;
        }

        public Gee.List<string> dependents_of (string id) {
            var r = new Gee.ArrayList<string> ();
            var set = new Gee.HashSet<string> ();
            set.add (id);
            bool grew = true;
            while (grew) {
                grew = false;
                foreach (var p in points) {
                    if (set.contains (p.id)) continue;
                    foreach (var rf in p.refs ()) {
                        if (set.contains (rf)) {
                            set.add (p.id);
                            r.add (p.id);
                            grew = true;
                            break;
                        }
                    }
                }
                foreach (var c in curves) {
                    if (set.contains (c.id)) continue;
                    if (c.parent != "" && set.contains (c.parent)) {
                        set.add (c.id);
                        r.add (c.id);
                        grew = true;
                        continue;
                    }
                    foreach (var k in c.knots) {
                        if (set.contains (k.point)) {
                            set.add (c.id);
                            r.add (c.id);
                            grew = true;
                            break;
                        }
                    }
                }
            }
            return r;
        }

        public PatternResult evaluate (string? size = null) {
            var ev = new Evaluator (this, size ?? (active_size != "" ? active_size : table.base_size));
            return ev.run ();
        }

        public double eval_formula (string formula, string size) throws ExprError {
            var ev = new Evaluator (this, size);
            ev.run ();
            return ev.formula (formula);
        }

        public Gee.List<string> all_sizes () {
            var r = new Gee.ArrayList<string> ();
            if (table.sizes.size > 0) r.add_all (table.sizes);
            else r.add (table.base_size != "" ? table.base_size : "base");
            return r;
        }
    }

    public class Evaluator {
        private Pattern pattern;
        private string size;
        private PatternResult result;
        private double um;
        public bool ignore_rules;

        public Evaluator (Pattern pattern, string size) {
            this.pattern = pattern;
            this.size = size;
            um = pattern.unit_mm ();
        }

        public bool lookup (string raw, out double v) {
            v = 0;
            string name = raw;
            foreach (var inc in pattern.increments) {
                if (inc.name == name || "#" + inc.name == name || inc.name == "#" + name) {
                    try {
                        v = Expr.evaluate (inc.formula, (n, out o) => lookup (n, out o));
                        return true;
                    } catch (ExprError e) {
                        return false;
                    }
                }
            }
            string mname = name.has_prefix ("@") || name.has_prefix ("#") ? name.substring (1) : name;
            if (pattern.table.lookup (mname, pattern.grading == "rules" ? pattern.table.base_size : size, out v)) {
                v /= um;
                return true;
            }
            if (name.has_prefix ("Line_")) {
                Point a, b;
                if (two_points (name.substring (5), out a, out b)) {
                    v = a.distance (b) / um;
                    return true;
                }
            }
            if (name.has_prefix ("AngleLine_")) {
                Point a, b;
                if (two_points (name.substring (10), out a, out b)) {
                    v = angle_deg (a, b);
                    return true;
                }
            }
            {
                string cn = name.has_prefix ("Length_") ? name.substring (7) : name;
                var c = pattern.curve_by_name (cn);
                if (c == null && cn.has_prefix ("Spl_")) c = pattern.curve_by_name ("SplPath_" + cn.substring (4));
                if (c == null && cn.has_prefix ("SplPath_")) c = pattern.curve_by_name ("Spl_" + cn.substring (8));
                if (c != null && result.curves.has_key (c.id)) {
                    double l = 0;
                    foreach (var bz in result.curves[c.id]) l += bz.length ();
                    v = l / um;
                    return true;
                }
            }
            return false;
        }

        private bool two_points (string rest, out Point a, out Point b) {
            a = Point (0, 0);
            b = Point (0, 0);
            var parts = rest.split ("_");
            for (int cut = 1; cut < parts.length; cut++) {
                string n1 = string.joinv ("_", parts[0:cut]);
                string n2 = string.joinv ("_", parts[cut:parts.length]);
                var p1 = pattern.point_by_name (n1);
                var p2 = pattern.point_by_name (n2);
                if (p1 != null && p2 != null && result.points.has_key (p1.id) && result.points.has_key (p2.id)) {
                    a = result.points[p1.id];
                    b = result.points[p2.id];
                    return true;
                }
            }
            return false;
        }

        public static double angle_deg (Point a, Point b) {
            double ang = Math.atan2 (-(b.y - a.y), b.x - a.x) * 180 / Math.PI;
            if (ang < 0) ang += 360;
            return ang;
        }

        public static Point polar (Point from, double length_mm, double angle_deg) {
            double r = angle_deg * Math.PI / 180;
            return Point (from.x + length_mm * Math.cos (r), from.y - length_mm * Math.sin (r));
        }

        public double formula (string text) throws ExprError {
            return eval (text);
        }

        private double eval (string formula) throws ExprError {
            return Expr.evaluate (formula, (n, out o) => lookup (n, out o));
        }

        private Point pt (string id) throws ExprError {
            if (!result.points.has_key (id)) {
                var p = pattern.find_point (id);
                throw new ExprError.UNKNOWN ("Point \"%s\" is not available".printf (p != null ? p.name : id));
            }
            return result.points[id];
        }

        public PatternResult run () {
            result = new PatternResult ();
            result.size = size;
            PatternResult? base_result = null;
            if (!ignore_rules && pattern.grading == "rules" && size != pattern.table.base_size) {
                var be = new Evaluator (pattern, pattern.table.base_size);
                be.ignore_rules = true;
                base_result = be.run ();
            }
            var pending_curves = new Gee.ArrayList<PatternCurve> ();
            pending_curves.add_all (pattern.curves);
            foreach (var p in pattern.points) {
                try {
                    if (base_result != null) {
                        if (base_result.points.has_key (p.id)) {
                            var at = base_result.points[p.id];
                            var dlt = pattern.rules.delta (p.rule, size, pattern.table);
                            result.points[p.id] = Point (at.x + dlt.x, at.y + dlt.y);
                        } else if (base_result.errors.has_key (p.id)) {
                            result.errors[p.id] = base_result.errors[p.id];
                        }
                    } else {
                        result.points[p.id] = compute (p);
                    }
                } catch (ExprError e) {
                    result.errors[p.id] = e.message;
                }
                var done = new Gee.ArrayList<PatternCurve> ();
                foreach (var c in pending_curves) {
                    bool ready = true;
                    foreach (var k in c.knots) if (!result.points.has_key (k.point)) ready = false;
                    if (c.kind == CurveKind.SEGMENT && !result.curves.has_key (c.parent)) ready = false;
                    if (ready) {
                        try {
                            result.curves[c.id] = build_curve (c);
                        } catch (ExprError e) {
                            result.errors[c.id] = e.message;
                        }
                        done.add (c);
                    }
                }
                pending_curves.remove_all (done);
            }
            foreach (var c in pending_curves) result.errors[c.id] = _("Curve points are missing");
            foreach (var piece in pattern.pieces) result.pieces.add (build_piece (piece));
            return result;
        }

        private Point compute (PatternPoint p) throws ExprError {
            switch (p.kind) {
                case PointKind.BASE:
                    return Point (eval (p.fx) * um, eval (p.fy) * um);
                case PointKind.END_LINE:
                    return polar (pt (p.a), eval (p.flength) * um, eval (p.fangle));
                case PointKind.ALONG_LINE: {
                    var a = pt (p.a);
                    var b = pt (p.b);
                    double ang = angle_deg (a, b);
                    return polar (a, eval (p.flength) * um, ang);
                }
                case PointKind.NORMAL: {
                    var a = pt (p.a);
                    var b = pt (p.b);
                    double ang = angle_deg (a, b) + 90 + eval (p.fangle);
                    return polar (a, eval (p.flength) * um, ang);
                }
                case PointKind.MIDPOINT: {
                    var a = pt (p.a);
                    var b = pt (p.b);
                    return Point ((a.x + b.x) / 2, (a.y + b.y) / 2);
                }
                case PointKind.INTERSECT: {
                    Point hit;
                    double t, u;
                    if (!Polyline.segment_intersection (pt (p.a), pt (p.b), pt (p.c), pt (p.d), out hit, out t, out u)) throw new ExprError.MATH ("The lines are parallel");
                    return hit;
                }
                case PointKind.ALONG_CURVE: {
                    if (!result.curves.has_key (p.a)) throw new ExprError.UNKNOWN ("The curve is not available");
                    double len = eval (p.flength) * um;
                    var segs = result.curves[p.a];
                    foreach (var bz in segs) {
                        double l = bz.length ();
                        if (len <= l) return bz.at (bz.t_at_length (len));
                        len -= l;
                    }
                    return segs.size > 0 ? segs[segs.size - 1].p3 : Point (0, 0);
                }
                case PointKind.FOOT: {
                    var a = pt (p.a);
                    var b = pt (p.b);
                    var c = pt (p.c);
                    double dx = b.x - a.x, dy = b.y - a.y;
                    double l2 = dx * dx + dy * dy;
                    if (l2 < 1e-12) return a;
                    double t = ((c.x - a.x) * dx + (c.y - a.y) * dy) / l2;
                    return Point (a.x + dx * t, a.y + dy * t);
                }
                case PointKind.ROTATE: {
                    var a = pt (p.a);
                    var o = pt (p.b);
                    double r = -eval (p.fangle) * Math.PI / 180;
                    double cs = Math.cos (r), sn = Math.sin (r);
                    double dx = a.x - o.x, dy = a.y - o.y;
                    return Point (o.x + dx * cs - dy * sn, o.y + dx * sn + dy * cs);
                }
                case PointKind.OFFSET: {
                    var a = pt (p.a);
                    return Point (a.x + eval (p.fx) * um, a.y + eval (p.fy) * um);
                }
                case PointKind.BISECTOR: {
                    var a = pt (p.a);
                    var v = pt (p.b);
                    var c = pt (p.c);
                    double a1 = angle_deg (v, a), a2 = angle_deg (v, c);
                    double diff = a2 - a1;
                    while (diff < 0) diff += 360;
                    double bis = a1 + diff / 2;
                    if (diff > 180) bis += 180;
                    return polar (v, eval (p.flength) * um, bis);
                }
                case PointKind.XY:
                    return Point (pt (p.a).x, pt (p.b).y);
                case PointKind.LINE_AXIS: {
                    var base_pt = pt (p.c);
                    var axis_end = polar (base_pt, 1000, eval (p.fangle));
                    Point hit;
                    double t, u;
                    if (!Polyline.segment_intersection (pt (p.a), pt (p.b), base_pt, axis_end, out hit, out t, out u)) throw new ExprError.MATH ("The line and the axis are parallel");
                    return hit;
                }
                case PointKind.CURVE_AXIS: {
                    var base_pt = pt (p.a);
                    if (!result.curves.has_key (p.b)) throw new ExprError.UNKNOWN ("The curve is not available");
                    double ang = eval (p.fangle);
                    var far_a = polar (base_pt, -100000, ang);
                    var far_b = polar (base_pt, 100000, ang);
                    Point best = base_pt;
                    double bd = double.INFINITY;
                    bool found = false;
                    foreach (var bz in result.curves[p.b]) {
                        var f = bz.flatten (0.05);
                        for (int i = 1; i < f.length; i++) {
                            Point hit;
                            double t, u;
                            if (Polyline.segment_intersection (far_a, far_b, f[i - 1], f[i], out hit, out t, out u) && u >= -1e-9 && u <= 1 + 1e-9) {
                                double dd = hit.distance (base_pt);
                                if (dd < bd) {
                                    bd = dd;
                                    best = hit;
                                    found = true;
                                }
                            }
                        }
                    }
                    if (!found) throw new ExprError.MATH ("The axis does not cross the curve");
                    return best;
                }
                case PointKind.CIRCLE_CONTACT: {
                    var a = pt (p.a);
                    var b = pt (p.b);
                    var c = pt (p.c);
                    double r = eval (p.flength) * um;
                    double dx = b.x - a.x, dy = b.y - a.y;
                    double fx = a.x - c.x, fy = a.y - c.y;
                    double qa = dx * dx + dy * dy;
                    double qb = 2 * (fx * dx + fy * dy);
                    double qc = fx * fx + fy * fy - r * r;
                    double disc = qb * qb - 4 * qa * qc;
                    if (qa < 1e-12 || disc < 0) throw new ExprError.MATH ("The circle does not reach the line");
                    double t1 = (-qb + Math.sqrt (disc)) / (2 * qa);
                    double t2 = (-qb - Math.sqrt (disc)) / (2 * qa);
                    var h1 = Point (a.x + dx * t1, a.y + dy * t1);
                    var h2 = Point (a.x + dx * t2, a.y + dy * t2);
                    return h1.distance (a) < h2.distance (a) ? h1 : h2;
                }
                case PointKind.CIRCLE_LINE: {
                    var a = pt (p.a);
                    var b = pt (p.b);
                    var c = pt (p.c);
                    double r = eval (p.flength) * um;
                    double dx = b.x - a.x, dy = b.y - a.y;
                    double fx = a.x - c.x, fy = a.y - c.y;
                    double qa = dx * dx + dy * dy;
                    double qb = 2 * (fx * dx + fy * dy);
                    double qc = fx * fx + fy * fy - r * r;
                    double disc = qb * qb - 4 * qa * qc;
                    if (qa < 1e-12 || disc < 0) throw new ExprError.MATH ("The circle does not reach the line");
                    double t = (-qb + Math.sqrt (disc)) / (2 * qa);
                    return Point (a.x + dx * t, a.y + dy * t);
                }
            }
            return Point (0, 0);
        }

        private Gee.ArrayList<Bezier?> build_curve (PatternCurve c) throws ExprError {
            var segs = new Gee.ArrayList<Bezier?> ();
            int n = c.knots.size;
            if (n < 2) return segs;
            Point[] pts = new Point[n];
            for (int i = 0; i < n; i++) pts[i] = pt (c.knots[i].point);
            if (c.kind == CurveKind.LINE) {
                for (int i = 0; i < n - 1; i++) segs.add (Bezier.line (pts[i], pts[i + 1]));
                return segs;
            }
            if (c.kind == CurveKind.SEGMENT) {
                if (!result.curves.has_key (c.parent)) throw new ExprError.UNKNOWN ("The parent curve is not available");
                return sub_curve (result.curves[c.parent], pts[0], pts[n - 1]);
            }
            double tension = c.tension != "" ? eval (c.tension) : 1;
            for (int i = 0; i < n - 1; i++) {
                var k0 = c.knots[i];
                var k1 = c.knots[i + 1];
                var p0 = pts[i];
                var p3 = pts[i + 1];
                Point p1, p2;
                double chord = p0.distance (p3);
                if (k0.angle_out != "" && k0.len_out != "") {
                    p1 = polar (p0, eval (k0.len_out) * um, eval (k0.angle_out));
                } else {
                    var prev = i > 0 ? pts[i - 1] : p0;
                    double tx = p3.x - prev.x, ty = p3.y - prev.y;
                    double tl = Math.hypot (tx, ty);
                    if (i == 0 || tl < 1e-9) {
                        p1 = Bezier.lerp (p0, p3, 1.0 / 3);
                    } else {
                        p1 = Point (p0.x + tx / tl * chord / 3 * tension, p0.y + ty / tl * chord / 3 * tension);
                    }
                }
                if (k1.angle_in != "" && k1.len_in != "") {
                    p2 = polar (p3, eval (k1.len_in) * um, eval (k1.angle_in));
                } else {
                    var next = i + 2 < n ? pts[i + 2] : p3;
                    double tx = next.x - p0.x, ty = next.y - p0.y;
                    double tl = Math.hypot (tx, ty);
                    if (i + 2 >= n || tl < 1e-9) {
                        p2 = Bezier.lerp (p0, p3, 2.0 / 3);
                    } else {
                        p2 = Point (p3.x - tx / tl * chord / 3 * tension, p3.y - ty / tl * chord / 3 * tension);
                    }
                }
                segs.add (Bezier (p0, p1, p2, p3));
            }
            if (c.target_length != "") return fit_length (segs, eval (c.target_length) * um);
            return segs;
        }

        public static double chain_length (Gee.List<Bezier?> segs) {
            double l = 0;
            foreach (var bz in segs) l += bz.length ();
            return l;
        }

        private static Gee.ArrayList<Bezier?> scaled (Gee.List<Bezier?> segs, double k) {
            var r = new Gee.ArrayList<Bezier?> ();
            foreach (var bz in segs) {
                r.add (Bezier (bz.p0, Point (bz.p0.x + (bz.p1.x - bz.p0.x) * k, bz.p0.y + (bz.p1.y - bz.p0.y) * k),
                    Point (bz.p3.x + (bz.p2.x - bz.p3.x) * k, bz.p3.y + (bz.p2.y - bz.p3.y) * k), bz.p3));
            }
            return r;
        }

        public static Gee.ArrayList<Bezier?> fit_length (Gee.List<Bezier?> segs, double target) throws ExprError {
            double chord = 0;
            foreach (var bz in segs) chord += bz.p0.distance (bz.p3);
            if (target < chord - 1e-6) throw new ExprError.MATH ("The curve cannot be shorter than its chord");
            double lo = 0, hi = 1;
            while (chain_length (scaled (segs, hi)) < target && hi < 64) hi *= 2;
            if (chain_length (scaled (segs, hi)) < target) throw new ExprError.MATH ("The curve cannot reach that length");
            for (int i = 0; i < 50; i++) {
                double mid = (lo + hi) / 2;
                if (chain_length (scaled (segs, mid)) < target) lo = mid;
                else hi = mid;
            }
            return scaled (segs, (lo + hi) / 2);
        }

        public static double chain_param (Gee.List<Bezier?> chain, Point p) {
            double best = double.INFINITY;
            double param = 0;
            for (int i = 0; i < chain.size; i++) {
                double t = chain[i].nearest_t (p.x, p.y);
                double d = chain[i].at (t).distance (p);
                if (d < best) {
                    best = d;
                    param = i + t;
                }
            }
            return param;
        }

        public static Gee.ArrayList<Bezier?> sub_curve (Gee.List<Bezier?> chain, Point from, Point to) {
            var out_segs = new Gee.ArrayList<Bezier?> ();
            double a = chain_param (chain, from);
            double b = chain_param (chain, to);
            bool rev = a > b;
            if (rev) {
                double tmp = a;
                a = b;
                b = tmp;
            }
            int ia = int.min ((int) Math.floor (a), chain.size - 1);
            int ib = int.min ((int) Math.floor (b), chain.size - 1);
            for (int i = ia; i <= ib; i++) {
                double t0 = i == ia ? a - ia : 0;
                double t1 = i == ib ? b - ib : 1;
                if (t1 - t0 < 1e-9) continue;
                out_segs.add (chain[i].sub (t0, t1));
            }
            if (out_segs.size > 0) {
                var first = out_segs[0];
                first.p0 = rev ? to : from;
                out_segs[0] = first;
                var last = out_segs[out_segs.size - 1];
                last.p3 = rev ? from : to;
                out_segs[out_segs.size - 1] = last;
            }
            if (rev) {
                var r = new Gee.ArrayList<Bezier?> ();
                for (int i = out_segs.size - 1; i >= 0; i--) r.add (out_segs[i].reversed ());
                return r;
            }
            return out_segs;
        }

        private Point[] curve_points (string id, bool reverse) {
            Point[] pts = {};
            if (!result.curves.has_key (id)) return pts;
            foreach (var bz in result.curves[id]) {
                var f = bz.flatten (0.2);
                for (int i = (pts.length == 0 ? 0 : 1); i < f.length; i++) pts += f[i];
            }
            return reverse ? Polyline.reversed (pts) : pts;
        }

        private PieceGeometry build_piece (Piece piece) {
            var g = new PieceGeometry (piece);
            if (piece.is_fixed ()) {
                var fg = piece.fixed_sizes.has_key (size) ? piece.fixed_sizes[size] : piece.fixed;
                g.seam = fg.seam;
                g.cut = fg.cut.length > 0 ? fg.cut : fg.seam;
                foreach (var n in fg.notches) {
                    var ng = new NotchGeometry ();
                    ng.cut_at = n.at;
                    ng.seam_at = n.at;
                    ng.angle = n.angle;
                    ng.type = n.type;
                    ng.length = n.length;
                    g.notches.add (ng);
                }
                foreach (var d in fg.drills) {
                    g.drills.add (d);
                    g.drill_sizes.add (3);
                }
                foreach (var l in fg.internals) g.internals.add (new PointList (l.pts));
                g.grain_a = fg.grain_a;
                g.grain_b = fg.grain_b;
                g.has_grain = fg.has_grain;
                g.edges.add (new PointList (g.seam));
                return g;
            }
            var edges = new Gee.ArrayList<OffsetEdge> ();
            var edge_nodes = new Gee.ArrayList<int> ();
            Point[] seam = {};
            double default_sa = 0;
            try {
                default_sa = piece.built_in ? 0 : eval (piece.seam_allowance) * um;
            } catch (ExprError e) {
                g.error = e.message;
            }
            int n = piece.nodes.size;
            if (n < 2) {
                g.error = _("A piece needs at least two points or curves");
                return g;
            }
            var node_pts = new Gee.ArrayList<PointList> ();
            Point? last = null;
            for (int i = 0; i < n; i++) {
                var node = piece.nodes[i];
                Point[] pts = {};
                if (node.is_curve) {
                    pts = curve_points (node.ref_id, node.reverse);
                    if (pts.length > 1 && last != null && !node.reverse) {
                        var rev = Polyline.reversed (pts);
                        if (rev[0].distance (last) + 1e-6 < pts[0].distance (last)) pts = rev;
                    }
                } else if (result.points.has_key (node.ref_id)) {
                    pts = { result.points[node.ref_id] };
                }
                if (pts.length == 0) {
                    g.error = _("Some parts of the piece are not available");
                    return g;
                }
                node_pts.add (new PointList (pts));
                last = pts[pts.length - 1];
            }
            for (int i = 0; i < n; i++) {
                var cur = node_pts[i].pts;
                var next = node_pts[(i + 1) % n].pts;
                var node = piece.nodes[i];
                double w = default_sa;
                if (node.sa_after != "" && !piece.built_in) {
                    try {
                        w = eval (node.sa_after) * um;
                    } catch (ExprError e) {
                        g.error = e.message;
                    }
                }
                if (node.is_curve && cur.length > 1) {
                    var ce = new OffsetEdge (cur, w);
                    ce.end_corner = node.corner;
                    edges.add (ce);
                    edge_nodes.add (i);
                }
                var a = cur[cur.length - 1];
                var b = next[0];
                if (a.distance (b) > 1e-6) {
                    var le = new OffsetEdge ({ a, b }, w);
                    le.end_corner = piece.nodes[(i + 1) % n].corner;
                    edges.add (le);
                    edge_nodes.add (i);
                } else if (edges.size > 0) {
                    edges[edges.size - 1].end_corner = piece.nodes[(i + 1) % n].corner;
                }
            }
            foreach (var e in edges) {
                for (int k = 0; k < e.pts.length - 1; k++) seam += e.pts[k];
                g.edges.add (new PointList (e.pts));
            }
            g.seam = seam;
            if (piece.on_fold && piece.fold_edge >= 0 && piece.fold_edge < edges.size) edges[piece.fold_edge].width = 0;
            g.cut = default_sa > 0 || has_any_width (edges) ? Offset.closed (edges) : seam;
            double sign = Polyline.signed_area (seam) >= 0 ? 1 : -1;
            for (int i = 0; i < n; i++) {
                var node = piece.nodes[i];
                if (!node.notch) continue;
                var at = node_pts[i].pts[0];
                add_notch (g, at, node.notch_type, sign);
            }
            foreach (var xn in piece.extra_notches) {
                if (xn.edge < 0 || xn.edge >= g.edges.size) continue;
                double ang;
                var at = Polyline.at_length (g.edges[xn.edge].pts, xn.distance, out ang);
                add_notch (g, at, xn.type, sign);
            }
            foreach (var d in piece.drills) {
                if (!result.points.has_key (d.point)) continue;
                var p = result.points[d.point];
                g.drills.add (Point (p.x + d.dx, p.y + d.dy));
                g.drill_sizes.add (d.diameter);
            }
            foreach (var il in piece.internals) {
                Point[] pts = {};
                foreach (var r in il.refs) {
                    if (result.points.has_key (r)) pts += result.points[r];
                    else if (result.curves.has_key (r)) foreach (var q in curve_points (r, false)) pts += q;
                }
                if (pts.length > 1) g.internals.add (new PointList (pts));
            }
            if (piece.grain_a != "" && piece.grain_b != "" && result.points.has_key (piece.grain_a) && result.points.has_key (piece.grain_b)) {
                g.grain_a = result.points[piece.grain_a];
                g.grain_b = result.points[piece.grain_b];
                g.has_grain = true;
            } else if (seam.length > 2) {
                var b = g.bounds ();
                double len = double.min (b.w, b.h) * 0.6;
                var c = Point (b.cx (), b.cy ());
                g.grain_a = polar (c, len / 2, piece.grain_angle + 180);
                g.grain_b = polar (c, len / 2, piece.grain_angle);
                g.has_grain = true;
            }
            return g;
        }

        private static bool has_any_width (Gee.List<OffsetEdge> edges) {
            foreach (var e in edges) if (e.width > 0) return true;
            return false;
        }

        private void add_notch (PieceGeometry g, Point at, string type, double sign) {
            int best = -1;
            double bd = double.INFINITY;
            for (int i = 0; i < g.seam.length; i++) {
                double d = g.seam[i].distance (at);
                if (d < bd) {
                    bd = d;
                    best = i;
                }
            }
            if (best < 0) return;
            var prev = g.seam[(best - 1 + g.seam.length) % g.seam.length];
            var next = g.seam[(best + 1) % g.seam.length];
            double tx = next.x - prev.x, ty = next.y - prev.y;
            double out_ang = Math.atan2 (-tx * sign, ty * sign);
            var ng = new NotchGeometry ();
            ng.seam_at = at;
            ng.type = type;
            ng.angle = out_ang + Math.PI;
            Point hit = at;
            double far = 0;
            double ox = Math.cos (out_ang), oy = Math.sin (out_ang);
            var probe_end = Point (at.x + ox * 500, at.y + oy * 500);
            double best_t = double.INFINITY;
            for (int i = 0; i < g.cut.length; i++) {
                Point h;
                double t, u;
                var c0 = g.cut[i];
                var c1 = g.cut[(i + 1) % g.cut.length];
                if (Polyline.segment_intersection (at, probe_end, c0, c1, out h, out t, out u) && t >= -1e-6 && u >= -1e-6 && u <= 1 + 1e-6 && t < best_t) {
                    best_t = t;
                    hit = h;
                }
            }
            far = best_t;
            ng.cut_at = far.is_infinity () != 0 ? at : hit;
            g.notches.add (ng);
        }
    }
}
