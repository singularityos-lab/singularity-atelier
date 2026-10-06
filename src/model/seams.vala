using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class SeamCheck {
        public string piece_a;
        public int edge_a;
        public string piece_b;
        public int edge_b;
        public double length_a;
        public double length_b;
        public double ease;
        public Gee.ArrayList<double?> notches_a = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<double?> notches_b = new Gee.ArrayList<double?> ();

        public double difference () {
            return length_a - length_b;
        }

        public double ease_percent () {
            return length_b > 0 ? (length_a - length_b) / length_b * 100 : 0;
        }

        public bool matches (double tolerance) {
            return (difference () - ease).abs () <= tolerance;
        }

        public double notch_mismatch () {
            double worst = 0;
            int n = int.min (notches_a.size, notches_b.size);
            for (int i = 0; i < n; i++) worst = double.max (worst, (notches_a[i] - notches_b[i]).abs ());
            return worst;
        }
    }

    public class Seams {
        public static SeamCheck? walk (PatternResult r, SeamPair pair) {
            var ga = r.piece (pair.piece_a);
            var gb = r.piece (pair.piece_b);
            if (ga == null || gb == null) return null;
            if (pair.edge_a < 0 || pair.edge_a >= ga.edges.size || pair.edge_b < 0 || pair.edge_b >= gb.edges.size) return null;
            var c = new SeamCheck ();
            c.piece_a = pair.piece_a;
            c.edge_a = pair.edge_a;
            c.piece_b = pair.piece_b;
            c.edge_b = pair.edge_b;
            c.ease = pair.ease;
            var ea = ga.edges[pair.edge_a].pts;
            var eb = gb.edges[pair.edge_b].pts;
            if (pair.reverse_b) eb = Polyline.reversed (eb);
            c.length_a = Polyline.length (ea);
            c.length_b = Polyline.length (eb);
            foreach (var n in ga.notches) {
                double d = position_on (ea, n.seam_at);
                if (d >= 0) c.notches_a.add (d);
            }
            foreach (var n in gb.notches) {
                double d = position_on (eb, n.seam_at);
                if (d >= 0) c.notches_b.add (d);
            }
            c.notches_a.sort ((x, y) => x < y ? -1 : (x > y ? 1 : 0));
            c.notches_b.sort ((x, y) => x < y ? -1 : (x > y ? 1 : 0));
            return c;
        }

        public static double position_on (Point[] pts, Point p, double tolerance = 0.5) {
            double acc = 0;
            for (int i = 1; i < pts.length; i++) {
                var a = pts[i - 1];
                var b = pts[i];
                double d = PathData.segment_distance (a, b, p.x, p.y);
                double seg = a.distance (b);
                if (d <= tolerance) {
                    double dx = b.x - a.x, dy = b.y - a.y;
                    double t = seg > 0 ? ((p.x - a.x) * dx + (p.y - a.y) * dy) / (seg * seg) : 0;
                    return acc + t.clamp (0, 1) * seg;
                }
                acc += seg;
            }
            return -1;
        }

        public static Cairo.Matrix walk_transform (Point[] edge_a, Point[] edge_b, double s) {
            double ang_a, ang_b;
            var pa = Polyline.at_length (edge_a, s, out ang_a);
            var pb = Polyline.at_length (edge_b, s, out ang_b);
            var m = Cairo.Matrix.identity ();
            m.translate (pa.x, pa.y);
            m.rotate (ang_a - ang_b);
            m.translate (-pb.x, -pb.y);
            return m;
        }

        public static Gee.ArrayList<SeamPair> guess_pairs (PatternResult r, double tolerance = 3) {
            var list = new Gee.ArrayList<SeamPair> ();
            for (int i = 0; i < r.pieces.size; i++) {
                var ga = r.pieces[i];
                for (int ea = 0; ea < ga.edges.size; ea++) {
                    if (ga.piece.on_fold && ga.piece.fold_edge == ea) continue;
                    double la = ga.edge_length (ea);
                    if (la < 20) continue;
                    for (int j = i + 1; j < r.pieces.size; j++) {
                        var gb = r.pieces[j];
                        for (int eb = 0; eb < gb.edges.size; eb++) {
                            if (gb.piece.on_fold && gb.piece.fold_edge == eb) continue;
                            double lb = gb.edge_length (eb);
                            if ((la - lb).abs () <= tolerance && edge_kind (ga, ea) == edge_kind (gb, eb)) {
                                bool used = false;
                                foreach (var p in list) if ((p.piece_a == ga.piece.id && p.edge_a == ea) || (p.piece_b == gb.piece.id && p.edge_b == eb)) used = true;
                                if (!used) list.add (new SeamPair (ga.piece.id, ea, gb.piece.id, eb));
                            }
                        }
                    }
                }
            }
            return list;
        }

        private static int edge_kind (PieceGeometry g, int e) {
            return g.edges[e].pts.length > 2 ? 1 : 0;
        }
    }
}
