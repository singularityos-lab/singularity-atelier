using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class Hpgl {
        public const double UNITS_PER_MM = 40.0;

        public class Options {
            public bool cut_line = true;
            public bool seam_line = true;
            public bool labels = true;
            public bool internals = true;
            public double paper_width_mm = 914;
            public double gap = 20;
        }

        private static string coord (double v) {
            return ((int) Math.round (v * UNITS_PER_MM)).to_string ();
        }

        private static void path (StringBuilder sb, Point[] pts, bool closed, double ox, double oy) {
            if (pts.length < 2) return;
            sb.append ("PU%s,%s;".printf (coord (pts[0].x + ox), coord (oy - pts[0].y)));
            var parts = new Gee.ArrayList<string> ();
            for (int i = 1; i < pts.length; i++) parts.add ("%s,%s".printf (coord (pts[i].x + ox), coord (oy - pts[i].y)));
            if (closed) parts.add ("%s,%s".printf (coord (pts[0].x + ox), coord (oy - pts[0].y)));
            sb.append ("PD%s;\n".printf (string.joinv (",", parts.to_array ())));
        }

        public static string export (PatternResult result, Options o) {
            var sb = new StringBuilder ();
            sb.append ("IN;\nSP1;\nDI1,0;\nSI0.25,0.35;\n");
            double x = o.gap, y = o.gap, row_h = 0;
            foreach (var g in result.pieces) {
                var outline = g.cut.length > 0 ? g.cut : g.seam;
                if (outline.length < 3) continue;
                var b = g.bounds ();
                if (y + b.h > o.paper_width_mm && y > o.gap) {
                    y = o.gap;
                    x += row_h + o.gap;
                    row_h = 0;
                }
                double ox = x - b.x;
                double oy = y + b.h + b.y;
                if (o.cut_line) path (sb, outline, true, ox, oy);
                if (o.seam_line && g.seam.length > 2 && g.cut.length > 0 && !g.piece.built_in) {
                    sb.append ("SP2;\n");
                    path (sb, g.seam, true, ox, oy);
                    sb.append ("SP1;\n");
                }
                foreach (var n in g.notches) {
                    var a = n.cut_at;
                    var e = Point (a.x + Math.cos (n.angle) * n.length, a.y + Math.sin (n.angle) * n.length);
                    path (sb, { a, e }, false, ox, oy);
                }
                if (o.internals) {
                    foreach (var il in g.internals) path (sb, il.pts, false, ox, oy);
                    if (g.has_grain) path (sb, { g.grain_a, g.grain_b }, false, ox, oy);
                    foreach (var d in g.drills) {
                        path (sb, { Point (d.x - 2, d.y - 2), Point (d.x + 2, d.y + 2) }, false, ox, oy);
                        path (sb, { Point (d.x - 2, d.y + 2), Point (d.x + 2, d.y - 2) }, false, ox, oy);
                    }
                }
                if (o.labels) {
                    var c = g.center ();
                    sb.append ("PU%s,%s;LB%s %s%c;\n".printf (coord (c.x + ox - 20), coord (oy - c.y), clean (g.piece.name), clean (result.size), (char) 3));
                }
                y += b.h + o.gap;
                row_h = double.max (row_h, b.w);
            }
            sb.append ("PU0,0;SP0;\n");
            return sb.str;
        }

        private static string clean (string s) {
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) {
                if (c < 32 || c > 126 || c == ';') continue;
                sb.append_unichar (c);
            }
            return sb.str;
        }

        public static Gee.ArrayList<PointList> parse_paths (string text, out Gee.ArrayList<string> labels) {
            var paths = new Gee.ArrayList<PointList> ();
            labels = new Gee.ArrayList<string> ();
            Point[] cur = {};
            double px = 0, py = 0;
            foreach (var raw in text.replace ("\n", "").split (";")) {
                string cmd = raw.strip ();
                if (cmd.length < 2) continue;
                string op = cmd.substring (0, 2);
                string args = cmd.substring (2);
                if (op == "LB") {
                    labels.add (args.replace (((char) 3).to_string (), ""));
                    continue;
                }
                if (op != "PU" && op != "PD") continue;
                var nums = args.split (",");
                if (op == "PU") {
                    if (cur.length > 1) paths.add (new PointList (cur));
                    cur = {};
                    for (int i = 0; i + 1 < nums.length; i += 2) {
                        px = double.parse (nums[i]) / UNITS_PER_MM;
                        py = double.parse (nums[i + 1]) / UNITS_PER_MM;
                    }
                    cur += Point (px, py);
                } else {
                    for (int i = 0; i + 1 < nums.length; i += 2) {
                        px = double.parse (nums[i]) / UNITS_PER_MM;
                        py = double.parse (nums[i + 1]) / UNITS_PER_MM;
                        cur += Point (px, py);
                    }
                }
            }
            if (cur.length > 1) paths.add (new PointList (cur));
            return paths;
        }
    }
}
