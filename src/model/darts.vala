using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public errordomain PatternOpError {
        INVALID
    }

    public class DartTools {
        private static int index_of (Piece piece, string id) {
            for (int i = 0; i < piece.nodes.size; i++) if (!piece.nodes[i].is_curve && piece.nodes[i].ref_id == id) return i;
            return -1;
        }

        public static string angle_formula (Pattern pattern, string apex, string leg1, string leg2) {
            var a = pattern.find_point (apex);
            var l1 = pattern.find_point (leg1);
            var l2 = pattern.find_point (leg2);
            return "AngleLine_%s_%s - AngleLine_%s_%s".printf (a.name, l1.name, a.name, l2.name);
        }

        private static string rotated_point (Pattern pattern, string src, string apex, string angle, Gee.HashMap<string, string> made) {
            if (made.has_key (src)) return made[src];
            var sp = pattern.find_point (src);
            var r = pattern.add_point (PointKind.ROTATE, sp.name + "r");
            r.a = src;
            r.b = apex;
            r.fangle = angle;
            made[src] = r.id;
            return r.id;
        }

        private static string rotated_curve (Pattern pattern, string src, string apex, string angle, Gee.HashMap<string, string> made) {
            if (made.has_key (src)) return made[src];
            var c = pattern.find_curve (src);
            string[] ids = {};
            foreach (var k in c.knots) ids += rotated_point (pattern, k.point, apex, angle, made);
            var nc = pattern.add_curve (ids, c.kind);
            nc.name = c.name + "_r";
            nc.tension = c.tension;
            for (int i = 0; i < c.knots.size; i++) {
                var k = c.knots[i];
                var nk = nc.knots[i];
                nk.len_in = k.len_in;
                nk.len_out = k.len_out;
                nk.angle_in = k.angle_in != "" ? "(%s) + (%s)".printf (k.angle_in, angle) : "";
                nk.angle_out = k.angle_out != "" ? "(%s) + (%s)".printf (k.angle_out, angle) : "";
            }
            made[src] = nc.id;
            return nc.id;
        }

        public static void transfer (Pattern pattern, Piece piece, string apex, string leg1, string leg2, string target) throws PatternOpError {
            int n = piece.nodes.size;
            int i1 = index_of (piece, leg1);
            int ia = index_of (piece, apex);
            int i2 = index_of (piece, leg2);
            int ix = index_of (piece, target);
            if (i1 < 0 || ia < 0 || i2 < 0 || ix < 0) throw new PatternOpError.INVALID (_("The dart and the new position must be points of the piece outline"));
            if ((i1 + 1) % n != ia || (ia + 1) % n != i2) throw new PatternOpError.INVALID (_("The dart legs must be next to the apex in the outline"));
            if (ix == i1 || ix == ia || ix == i2) throw new PatternOpError.INVALID (_("Choose a new position away from the dart"));
            string angle = angle_formula (pattern, apex, leg1, leg2);
            var made = new Gee.HashMap<string, string> ();
            var seq = new Gee.ArrayList<PieceNode> ();
            int k = (i2 + 1) % n;
            while (k != ia) {
                seq.add (piece.nodes[k]);
                k = (k + 1) % n;
            }
            int px = seq.index_of (piece.nodes[ix]);
            var result = new Gee.ArrayList<PieceNode> ();
            for (int j = 0; j <= px; j++) {
                var node = seq[j];
                var nn = new PieceNode (node.is_curve ? rotated_curve (pattern, node.ref_id, apex, angle, made) : rotated_point (pattern, node.ref_id, apex, angle, made), node.is_curve);
                nn.reverse = node.reverse;
                nn.sa_after = node.sa_after;
                nn.corner = node.corner;
                nn.notch = node.notch;
                nn.notch_type = node.notch_type;
                result.add (nn);
            }
            result.add (new PieceNode (apex));
            for (int j = px; j < seq.size; j++) {
                if (seq[j].ref_id == leg1 && !seq[j].is_curve && j == seq.size - 1) {
                    result.add (seq[j]);
                    continue;
                }
                result.add (seq[j]);
            }
            piece.nodes.clear ();
            piece.nodes.add_all (result);
        }

        public static void insert_pleat (Pattern pattern, Piece piece, string a, string b, string depth, string kind, bool flip) throws PatternOpError {
            int n = piece.nodes.size;
            int ia = index_of (piece, a);
            int ib = index_of (piece, b);
            if (ia < 0 || ib < 0) throw new PatternOpError.INVALID (_("The pleat line must join two points of the piece outline"));
            var pa = pattern.find_point (a);
            var pb = pattern.find_point (b);
            string spread = kind == "box" ? "4 * (%s)".printf (depth) : "2 * (%s)".printf (depth);
            string ang = "AngleLine_%s_%s %s 90".printf (pa.name, pb.name, flip ? "+" : "-");
            string dx = "(%s) * cosD(%s)".printf (spread, ang);
            string dy = "-(%s) * sinD(%s)".printf (spread, ang);
            var moved = new Gee.HashMap<string, string> ();
            var result = new Gee.ArrayList<PieceNode> ();
            int k = (ib + 1) % n;
            while (true) {
                result.add (piece.nodes[k]);
                if (k == ia) break;
                k = (k + 1) % n;
            }
            k = ia;
            while (true) {
                var node = piece.nodes[k];
                if (!node.is_curve) {
                    var sp = pattern.find_point (node.ref_id);
                    var q = pattern.add_point (PointKind.OFFSET, sp.name + "p");
                    q.a = node.ref_id;
                    q.fx = dx;
                    q.fy = dy;
                    moved[node.ref_id] = q.id;
                    var nn = new PieceNode (q.id);
                    nn.sa_after = node.sa_after;
                    nn.notch = node.notch;
                    result.add (nn);
                } else {
                    var c = pattern.find_curve (node.ref_id);
                    string[] ids = {};
                    foreach (var kn in c.knots) {
                        if (!moved.has_key (kn.point)) {
                            var sp = pattern.find_point (kn.point);
                            var q = pattern.add_point (PointKind.OFFSET, sp.name + "p");
                            q.a = kn.point;
                            q.fx = dx;
                            q.fy = dy;
                            moved[kn.point] = q.id;
                        }
                        ids += moved[kn.point];
                    }
                    var nc = pattern.add_curve (ids, c.kind);
                    nc.name = c.name + "_p";
                    for (int i = 0; i < c.knots.size; i++) {
                        nc.knots[i].angle_in = c.knots[i].angle_in;
                        nc.knots[i].len_in = c.knots[i].len_in;
                        nc.knots[i].angle_out = c.knots[i].angle_out;
                        nc.knots[i].len_out = c.knots[i].len_out;
                    }
                    var nn = new PieceNode (nc.id, true);
                    nn.reverse = node.reverse;
                    result.add (nn);
                }
                if (k == ib) break;
                k = (k + 1) % n;
            }
            result.add (piece.nodes[ib]);
            piece.nodes.clear ();
            piece.nodes.add_all (result);
            var fold = new InternalLine ();
            fold.kind = "fold";
            var ma = pattern.add_point (PointKind.MIDPOINT, pa.name + "f");
            ma.a = a;
            ma.b = moved[a];
            var mb = pattern.add_point (PointKind.MIDPOINT, pb.name + "f");
            mb.a = b;
            mb.b = moved[b];
            fold.refs.add (ma.id);
            fold.refs.add (mb.id);
            piece.internals.add (fold);
            var edge1 = new InternalLine ();
            edge1.kind = "placement";
            edge1.refs.add (a);
            edge1.refs.add (b);
            piece.internals.add (edge1);
            var edge2 = new InternalLine ();
            edge2.kind = "placement";
            edge2.refs.add (moved[a]);
            edge2.refs.add (moved[b]);
            piece.internals.add (edge2);
        }

        public static double dart_angle (PatternResult r, Pattern pattern, string apex, string leg1, string leg2) {
            if (!r.points.has_key (apex) || !r.points.has_key (leg1) || !r.points.has_key (leg2)) return 0;
            double a1 = Evaluator.angle_deg (r.points[apex], r.points[leg1]);
            double a2 = Evaluator.angle_deg (r.points[apex], r.points[leg2]);
            double d = a1 - a2;
            while (d > 180) d -= 360;
            while (d < -180) d += 360;
            return d;
        }
    }
}
