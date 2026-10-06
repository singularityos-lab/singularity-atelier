using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class GradeRule {
        public int number;
        public string name = "";
        public Gee.HashMap<string, Point?> steps = new Gee.HashMap<string, Point?> ();

        public GradeRule (int number) {
            this.number = number;
        }

        public Point step (string size) {
            return steps.has_key (size) ? steps[size] : Point (0, 0);
        }

        public void set_step (string size, double dx, double dy) {
            steps[size] = Point (dx, dy);
        }

        public void set_uniform (MeasurementTable table, double dx, double dy) {
            foreach (var s in table.sizes) steps[s] = Point (dx, dy);
        }
    }

    public class GradeRuleTable {
        public Gee.ArrayList<GradeRule> rules = new Gee.ArrayList<GradeRule> ();

        public GradeRule? find (int number) {
            foreach (var r in rules) if (r.number == number) return r;
            return null;
        }

        public GradeRule ensure (int number) {
            var r = find (number);
            if (r == null) {
                r = new GradeRule (number);
                rules.add (r);
            }
            return r;
        }

        public int next_number () {
            int n = 1;
            foreach (var r in rules) n = int.max (n, r.number + 1);
            return n;
        }

        public Point delta (int number, string size, MeasurementTable table) {
            var r = find (number);
            if (r == null) return Point (0, 0);
            int idx = table.size_index (size);
            int base_idx = table.base_index ();
            if (idx < 0) return Point (0, 0);
            double dx = 0, dy = 0;
            if (idx > base_idx) {
                for (int i = base_idx + 1; i <= idx; i++) {
                    var s = r.step (table.sizes[i]);
                    dx += s.x;
                    dy += s.y;
                }
            } else if (idx < base_idx) {
                for (int i = idx + 1; i <= base_idx; i++) {
                    var s = r.step (table.sizes[i]);
                    dx -= s.x;
                    dy -= s.y;
                }
            }
            return Point (dx, dy);
        }
    }

    public class Grading {
        public static Gee.HashMap<string, PatternResult> nest (Pattern pattern, Gee.List<string>? sizes = null) {
            var map = new Gee.HashMap<string, PatternResult> ();
            var list = sizes ?? pattern.all_sizes ();
            foreach (var s in list) map[s] = pattern.evaluate (s);
            return map;
        }

        public static Gee.HashMap<string, PatternResult> nest_by_measurements (Pattern pattern) {
            string saved = pattern.grading;
            pattern.grading = "measurements";
            var map = nest (pattern);
            pattern.grading = saved;
            return map;
        }

        public static Point anchor_offset (PieceGeometry base_geom, PieceGeometry graded, string anchor) {
            if (anchor == "none") return Point (0, 0);
            if (anchor == "grain" && base_geom.has_grain && graded.has_grain) {
                return Point (base_geom.grain_a.x - graded.grain_a.x, base_geom.grain_a.y - graded.grain_a.y);
            }
            var bb = base_geom.bounds ();
            var gb = graded.bounds ();
            if (anchor == "center") return Point (bb.cx () - gb.cx (), bb.cy () - gb.cy ());
            return Point (bb.x - gb.x, bb.y - gb.y);
        }

        public static void derive_rules (Pattern pattern, Gee.Map<string, PatternResult> by_size) {
            var table = pattern.table;
            foreach (var p in pattern.points) {
                bool moves = false;
                for (int i = 1; i < table.sizes.size; i++) {
                    var prev = by_size[table.sizes[i - 1]];
                    var cur = by_size[table.sizes[i]];
                    if (prev == null || cur == null || !prev.points.has_key (p.id) || !cur.points.has_key (p.id)) continue;
                    var a = prev.points[p.id];
                    var b = cur.points[p.id];
                    if (a.distance (b) > 1e-6) moves = true;
                }
                if (!moves) continue;
                int number = p.rule != 0 ? p.rule : pattern.rules.next_number ();
                var rule = pattern.rules.ensure (number);
                rule.name = p.name;
                for (int i = 1; i < table.sizes.size; i++) {
                    var prev = by_size[table.sizes[i - 1]];
                    var cur = by_size[table.sizes[i]];
                    if (prev == null || cur == null || !prev.points.has_key (p.id) || !cur.points.has_key (p.id)) continue;
                    var a = prev.points[p.id];
                    var b = cur.points[p.id];
                    rule.set_step (table.sizes[i], b.x - a.x, b.y - a.y);
                }
                p.rule = number;
            }
        }
    }
}
