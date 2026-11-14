using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class EdgeChain {
        public int edge;
        public int side;
        public int[] index = {};
        public double[] t = {};
        public bool straight;
        public bool hem;
        public double length;

        public Vec3 point_at (GarmentSim sim, double at) {
            int n = index.length;
            if (n == 0) return Vec3.zero ();
            if (at <= t[0]) return sim.particle (index[0]);
            for (int i = 0; i + 1 < n; i++) {
                if (at <= t[i + 1]) {
                    double k = (at - t[i]) / double.max (1e-9, t[i + 1] - t[i]);
                    return sim.particle (index[i]).lerp (sim.particle (index[i + 1]), k);
                }
            }
            return sim.particle (index[n - 1]);
        }
    }

    public class ClothPiece {
        public string piece_id;
        public string name;
        public string placement;
        public int copy;
        public int first;
        public int count;
        public FabricPreset fabric;
        public int fabric_index;
        public Gee.ArrayList<EdgeChain> chains = new Gee.ArrayList<EdgeChain> ();
        public Scene.Mesh mesh = new Scene.Mesh ();
        public double area;

        public EdgeChain? chain (int edge, int side) {
            foreach (var c in chains) if (c.edge == edge && c.side == side) return c;
            return null;
        }
    }

    private class Wrap {
        public double rx;
        public double rz;
        public double cz;
        private double[] arc = new double[513];

        public Wrap (double rx, double rz, double cz, double need) {
            this.cz = cz;
            for (int pass = 0; pass < 2; pass++) {
                this.rx = rx;
                this.rz = rz;
                arc[0] = 0;
                double px = 0, pz = rz;
                for (int i = 1; i <= 512; i++) {
                    double a = Math.PI * i / 512;
                    double x = rx * Math.sin (a), z = rz * Math.cos (a);
                    arc[i] = arc[i - 1] + Math.hypot (x - px, z - pz);
                    px = x;
                    pz = z;
                }
                if (arc[512] >= need || pass == 1) break;
                double k = need / arc[512];
                rx *= k;
                rz *= k;
            }
        }

        public double half () {
            return arc[512];
        }

        public void at (double s, bool back, out double x, out double z) {
            double a = s.abs ().clamp (0, arc[512]);
            int lo = 0, hi = 512;
            while (hi - lo > 1) {
                int mid = (lo + hi) / 2;
                if (arc[mid] <= a) lo = mid;
                else hi = mid;
            }
            double k = (a - arc[lo]) / double.max (1e-9, arc[hi] - arc[lo]);
            double ang = Math.PI * (lo + k) / 512;
            if (back) ang = Math.PI - ang;
            x = rx * Math.sin (ang) * (s < 0 ? -1 : 1);
            z = cz + rz * Math.cos (ang);
        }
    }

    public class GarmentSim {
        public Gee.ArrayList<ClothPiece> pieces = new Gee.ArrayList<ClothPiece> ();
        public Body body;
        public int frame;
        public int substeps = 14;
        public double spacing = 18;
        public string map = "material";
        private AtCore.Cloth cloth = new AtCore.Cloth ();
        private AtCore.Sdf? sdf;
        private GarmentSettings settings;
        private Mutex guard = Mutex ();
        private float[] scratch = {};
        private Wrap lower;
        private Wrap leg;
        private Wrap limb;
        private double leg_center;
        private int[] stitch_i = {};
        private int[] stitch_j = {};
        private int[] stitch_k = {};
        private float[] stitch_w = {};
        private int[] stitch_seam = {};
        private int current_seam;

        public GarmentSim (PatternResult result, GarmentSettings settings, Body body) {
            this.settings = settings;
            this.body = body;
            spacing = ((double) settings.resolution).clamp (4, 60);
            build_collider ();
            build (result);
        }

        private void build_collider () {
            var m = body.mesh;
            sdf = AtCore.Sdf.build (m.positions, m.vertex_count, m.triangles, m.triangles.length, 8, 70);
            cloth.set_collider (sdf, (float) (2 + spacing * 0.13));
        }

        public void set_body (Body next) {
            guard.lock ();
            body = next;
            cloth.set_collider (null, 0);
            build_collider ();
            guard.unlock ();
        }

        public Vec3 particle (int i) {
            unowned float[] x = cloth.positions ();
            return Vec3 (x[i * 3], x[i * 3 + 1], x[i * 3 + 2]);
        }

        public int particle_count () {
            return cloth.count ();
        }

        public int triangle_count () {
            return cloth.triangle_count ();
        }

        public static AtCore.Fabric physical (FabricPreset f) {
            var c = AtCore.Fabric ();
            c.stretch_u = (float) f.stretch_weft;
            c.stretch_v = (float) f.stretch_warp;
            c.shear = (float) f.shear;
            c.bend_u = (float) f.bend_weft;
            c.bend_v = (float) f.bend_warp;
            c.density = (float) f.density;
            c.friction = (float) f.friction;
            c.thickness = (float) f.thickness;
            c.damping = (float) f.damping;
            c.shrink_u = (float) f.shrink_weft;
            c.shrink_v = (float) f.shrink_warp;
            return c;
        }

        private FabricPreset fabric_of (Piece p) {
            return settings.fabric_for (p.id);
        }

        private void build (PatternResult result) {
            double front = 0, back = 0, low_front = 0, low_back = 0;
            foreach (var g in result.pieces) {
                if (g.seam.length < 3) continue;
                var b = g.bounds ();
                double w = g.piece.on_fold || g.piece.pair ? b.w * 2 : b.w;
                if (g.piece.placement == "back") back += w;
                else if (g.piece.placement == "front") front += w;
                else if (g.piece.placement == "skirt-back") low_back += w;
                else if (g.piece.placement == "skirt-front") low_front += w;
            }
            var m = body.measures;
            double depth = m.bust / Math.PI * 0.42 + 55;
            double width = body.joint ("upperarm01.L").distance (body.joint ("upperarm01.R")) / 2 + 45;
            double cz = (body.joint ("spine02").z + body.joint ("spine04").z) / 2;
            var wrap = new Wrap (width, depth, cz, double.max (front, back) / 2 + 20);
            double hx, hz, hrx, hrz;
            body.extent (m.y_hip, out hx, out hz, out hrx, out hrz);
            lower = new Wrap (hrx + 40, hrz + 40, hz, double.max (low_front, low_back) / 2 + 20);
            double outer = hrx + 40, inner = 12;
            leg = new Wrap ((outer - inner) / 2, hrz + 40, hz, 0);
            leg_center = (outer + inner) / 2;
            limb = new Wrap (m.thigh / (2 * Math.PI) + 30, m.thigh / (2 * Math.PI) + 30, 0, 0);
            foreach (var g in result.pieces) {
                if (g.seam.length < 3 || g.edges.size == 0) continue;
                int copies = g.piece.placement == "sleeve" || (g.piece.pair && !g.piece.on_fold) ? 2 : 1;
                for (int c = 0; c < copies; c++) add_piece (g, c, wrap);
            }
            cloth.finalize ();
            cloth.separate (3);
            if (settings.seams.size == 0) settings.seams.add_all (auto_seams (result));
            apply_seams ();
            scratch = new float[cloth.count ()];
            sync ();
        }

        private static Point[] resample (Point[] pts, double h) {
            double len = Polyline.length (pts);
            int segs = int.max (1, (int) Math.round (len / h));
            Point[] o = new Point[segs + 1];
            for (int i = 0; i <= segs; i++) {
                double ang;
                o[i] = Polyline.at_length (pts, len * i / segs, out ang);
            }
            return o;
        }

        private static Point mirror (Point p, Point a, Point b) {
            double dx = b.x - a.x, dy = b.y - a.y;
            double l2 = dx * dx + dy * dy;
            if (l2 < 1e-12) return p;
            double t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2;
            return Point (2 * (a.x + dx * t) - p.x, 2 * (a.y + dy * t) - p.y);
        }

        private void add_piece (PieceGeometry g, int copy, Wrap wrap) {
            var piece = new ClothPiece ();
            piece.piece_id = g.piece.id;
            piece.name = g.piece.name;
            piece.placement = g.piece.placement;
            piece.copy = copy;
            piece.fabric = fabric_of (g.piece);
            int ne = g.edges.size;
            bool unfold = g.piece.on_fold && g.piece.fold_edge >= 0 && g.piece.fold_edge < ne && ne > 1;
            int fold = unfold ? g.piece.fold_edge : -1;
            var order = new int[unfold ? ne - 1 : ne];
            for (int k = 0; k < order.length; k++) order[k] = unfold ? (fold + 1 + k) % ne : k;

            Point[] ring = {};
            var half = new Gee.ArrayList<EdgeChain> ();
            for (int k = 0; k < order.length; k++) {
                var src = g.edges[order[k]].pts;
                var pts = resample (src, spacing);
                var ch = new EdgeChain ();
                ch.edge = order[k];
                ch.side = copy;
                ch.straight = src.length <= 2;
                ch.length = Polyline.length (src);
                ch.index = new int[pts.length];
                ch.t = new double[pts.length];
                for (int j = 0; j < pts.length; j++) {
                    ch.t[j] = (double) j / (pts.length - 1);
                    if (j == 0 && ring.length > 0) {
                        ch.index[j] = ring.length - 1;
                        continue;
                    }
                    if (j == pts.length - 1 && k == order.length - 1 && !unfold) {
                        ch.index[j] = 0;
                        continue;
                    }
                    ring += pts[j];
                    ch.index[j] = ring.length - 1;
                }
                half.add (ch);
            }
            int h = ring.length;
            if (h < 3) return;
            if (unfold) {
                var fe = g.edges[fold].pts;
                Point fa = fe[0], fb = fe[fe.length - 1];
                for (int k = h - 2; k >= 1; k--) ring += mirror (ring[k], fa, fb);
                foreach (var ch in half) {
                    var mc = new EdgeChain ();
                    mc.edge = ch.edge;
                    mc.side = 1;
                    mc.straight = ch.straight;
                    mc.length = ch.length;
                    mc.t = ch.t;
                    mc.index = new int[ch.index.length];
                    for (int j = 0; j < ch.index.length; j++) {
                        int o = ch.index[j];
                        mc.index[j] = o == 0 || o == h - 1 ? o : h + (h - 2 - o);
                    }
                    piece.chains.add (mc);
                }
            }
            foreach (var ch in half) piece.chains.add (ch);
            mark_hems (g, piece);

            int nb = ring.length;
            var flat = new double[nb * 2];
            for (int i = 0; i < nb; i++) {
                flat[i * 2] = ring[i].x;
                flat[i * 2 + 1] = ring[i].y;
            }
            double* pp;
            int* tt;
            int np, nt;
            AtCore.triangulate (flat, nb, null, 0, spacing, out pp, out np, out tt, out nt);
            if (nt == 0) {
                AtCore.free (pp);
                AtCore.free (tt);
                return;
            }
            var bounds = Rect.empty ();
            for (int i = 0; i < nb; i++) bounds = bounds.include (ring[i].x, ring[i].y);
            double center = bounds.cx ();
            if (unfold) {
                var fe = g.edges[fold].pts;
                center = (fe[0].x + fe[fe.length - 1].x) / 2;
            } else if (g.piece.pair && piece.placement != "sleeve" && !piece.placement.has_prefix ("leg-")) {
                center = bounds.x;
            }
            int index = pieces.size;
            piece.first = cloth.count ();
            piece.count = np;
            piece.fabric_index = cloth.add_fabric (physical (piece.fabric));
            var mesh = piece.mesh;
            mesh.name = piece.name;
            mesh.positions = new float[np * 3];
            mesh.uvs = new float[np * 2];
            mesh.scalars = new float[np];
            for (int i = 0; i < np; i++) {
                double u = pp[i * 2], v = pp[i * 2 + 1];
                var at = place (piece, u, v, center, bounds, wrap);
                cloth.add_particle ((float) at.x, (float) at.y, (float) at.z, (float) u, (float) v, index);
                mesh.uvs[i * 2] = (float) u;
                mesh.uvs[i * 2 + 1] = (float) v;
            }
            mesh.triangles = new uint[nt * 3];
            double area = 0;
            for (int t = 0; t < nt; t++) {
                int a = tt[t * 3], b = tt[t * 3 + 1], c = tt[t * 3 + 2];
                cloth.add_triangle (piece.first + a, piece.first + b, piece.first + c, piece.fabric_index);
                mesh.triangles[t * 3] = a;
                mesh.triangles[t * 3 + 1] = b;
                mesh.triangles[t * 3 + 2] = c;
                area += ((pp[b * 2] - pp[a * 2]) * (pp[c * 2 + 1] - pp[a * 2 + 1]) - (pp[b * 2 + 1] - pp[a * 2 + 1]) * (pp[c * 2] - pp[a * 2])).abs () / 2;
            }
            piece.area = area;
            AtCore.free (pp);
            AtCore.free (tt);
            foreach (var ch in piece.chains) for (int j = 0; j < ch.index.length; j++) ch.index[j] += piece.first;
            pieces.add (piece);
            orient (piece);
            apply_material (piece);
        }

        private void mark_hems (PieceGeometry g, ClothPiece piece) {
            var b = Rect.empty ();
            foreach (var q in g.seam) b = b.include (q.x, q.y);
            foreach (var ch in piece.chains) {
                var src = g.edges[ch.edge].pts;
                var a = src[0];
                var z = src[src.length - 1];
                double mid = (a.y + z.y) / 2;
                ch.hem = ch.straight && mid > b.y2 () - b.h * 0.06 && (z.y - a.y).abs () < 0.35 * (z.x - a.x).abs () + 1;
            }
        }

        private Vec3 place (ClothPiece piece, double u, double v, double center, Rect bounds, Wrap wrap) {
            var m = body.measures;
            if (piece.placement == "sleeve") {
                string sfx = piece.copy == 0 ? ".L" : ".R";
                var sh = body.joint ("upperarm01" + sfx);
                var wr = body.joint ("wrist" + sfx);
                var axis = wr.sub (sh).normalized ();
                var up = Vec3 (0, 1, 0);
                var uu = up.sub (axis.scale (up.dot (axis))).normalized ();
                var ww = axis.cross (uu).normalized ();
                if (piece.copy == 1) ww = ww.neg ();
                double radius = double.max (bounds.w / (2 * Math.PI) * 1.04, m.upper_arm / (2 * Math.PI) + 7);
                double phi = (u - bounds.cx ()) / radius;
                double s = (v - bounds.y) + 40;
                return sh.add (axis.scale (s)).add (uu.scale (radius * Math.cos (phi))).add (ww.scale (radius * Math.sin (phi)));
            }
            double s = u - center;
            if (piece.copy == 1) s = -s;
            double x, z;
            if (piece.placement.has_prefix ("leg-")) {
                double side = piece.copy == 1 ? -1 : 1;
                double y3 = m.y_waist + 25 - (v - bounds.y);
                bool rear = piece.placement == "leg-back";
                leg.at ((u - bounds.cx ()) * side, rear, out x, out z);
                x += leg_center * side;
                double k = ((m.y_crotch - y3) / 160).clamp (0, 1);
                if (k > 0) {
                    string sfx = side > 0 ? ".L" : ".R";
                    var hip = body.joint ("upperleg01" + sfx);
                    var knee = body.joint ("lowerleg01" + sfx);
                    var ankle = body.joint ("foot" + sfx);
                    Vec3 axis = y3 > knee.y ? hip.lerp (knee, ((hip.y - y3) / double.max (1, hip.y - knee.y)).clamp (0, 1)) : knee.lerp (ankle, ((knee.y - y3) / double.max (1, knee.y - ankle.y)).clamp (0, 1));
                    double lx, lz;
                    limb.at ((u - bounds.cx ()) * side, rear, out lx, out lz);
                    x += (axis.x + lx - x) * k;
                    z += (axis.z + lz - z) * k;
                }
                return Vec3 (x, y3, z);
            }
            if (piece.placement.has_prefix ("skirt-")) {
                lower.at (s, piece.placement == "skirt-back", out x, out z);
                return Vec3 (x, m.y_waist + 25 - (v - bounds.y), z);
            }
            wrap.at (s, piece.placement == "back", out x, out z);
            return Vec3 (x, m.y_neck + 38 - (v - bounds.y), z);
        }

        private void orient (ClothPiece piece) {
            unowned float[] x = cloth.positions ();
            var mesh = piece.mesh;
            double cz = (body.joint ("spine02").z + body.joint ("spine04").z) / 2;
            double score = 0;
            for (int t = 0; t + 2 < mesh.triangles.length; t += 3) {
                int a = (piece.first + (int) mesh.triangles[t]) * 3, b = (piece.first + (int) mesh.triangles[t + 1]) * 3, c = (piece.first + (int) mesh.triangles[t + 2]) * 3;
                var pa = Vec3 (x[a], x[a + 1], x[a + 2]);
                var n = Vec3 (x[b], x[b + 1], x[b + 2]).sub (pa).cross (Vec3 (x[c], x[c + 1], x[c + 2]).sub (pa));
                Vec3 outward;
                if (piece.placement == "sleeve") {
                    string sfx = piece.copy == 0 ? ".L" : ".R";
                    var sh = body.joint ("upperarm01" + sfx);
                    var axis = body.joint ("wrist" + sfx).sub (sh).normalized ();
                    var d = pa.sub (sh);
                    outward = d.sub (axis.scale (d.dot (axis)));
                } else if (piece.placement.has_prefix ("leg-")) {
                    outward = Vec3 (pa.x - leg_center * (piece.copy == 1 ? -1 : 1), 0, pa.z - cz);
                } else {
                    outward = Vec3 (pa.x, 0, pa.z - cz);
                }
                score += n.dot (outward);
            }
            if (score >= 0) return;
            for (int t = 0; t + 2 < mesh.triangles.length; t += 3) {
                uint k = mesh.triangles[t + 1];
                mesh.triangles[t + 1] = mesh.triangles[t + 2];
                mesh.triangles[t + 2] = k;
            }
        }

        public void apply_material (ClothPiece piece) {
            var f = piece.fabric;
            var mat = piece.mesh.material;
            mat.color = Gdk.RGBA () { red = (float) f.color.r, green = (float) f.color.g, blue = (float) f.color.b, alpha = 1 };
            mat.back_color = Gdk.RGBA () { red = (float) (f.color.r * 0.78), green = (float) (f.color.g * 0.78), blue = (float) (f.color.b * 0.80), alpha = 1 };
            mat.roughness = f.roughness;
            mat.metallic = f.metallic;
            mat.sheen = f.sheen;
            mat.weave = f.weave;
            mat.weave_scale = f.weave_scale;
            mat.texture = f.image ();
            mat.texture_size = f.texture_size;
            if (mat.texture != null) mat.color = Gdk.RGBA () { red = 1, green = 1, blue = 1, alpha = 1 };
            mat.double_sided = true;
        }

        private EdgeChain? find_chain (string piece_id, int edge, int side) {
            foreach (var p in pieces) {
                if (p.piece_id != piece_id) continue;
                var c = p.chain (edge, side);
                if (c != null) return c;
            }
            return null;
        }

        private void join (EdgeChain a, double a0, double a1, EdgeChain b, double b0, double b1, bool reverse) {
            for (int dir = 0; dir < 2; dir++) {
                var from = dir == 0 ? a : b;
                var to = dir == 0 ? b : a;
                double f0 = dir == 0 ? a0 : b0, f1 = dir == 0 ? a1 : b1;
                double t0 = dir == 0 ? b0 : a0, t1 = dir == 0 ? b1 : a1;
                double lo = double.min (f0, f1), hi = double.max (f0, f1);
                for (int i = 0; i < from.index.length; i++) {
                    double t = from.t[i];
                    if (t < lo - 1e-6 || t > hi + 1e-6) continue;
                    double k = (t - f0) / (f1 - f0);
                    if (reverse) k = 1 - k;
                    double at = t0 + (t1 - t0) * k;
                    int n = to.index.length;
                    int seg = 0;
                    while (seg < n - 2 && to.t[seg + 1] < at) seg++;
                    double w = ((at - to.t[seg]) / double.max (1e-9, to.t[seg + 1] - to.t[seg])).clamp (0, 1);
                    if (from.index[i] == to.index[seg] || from.index[i] == to.index[seg + 1]) continue;
                    cloth.add_seam (from.index[i], to.index[seg], to.index[seg + 1], (float) w, 0);
                    stitch_i += from.index[i];
                    stitch_j += to.index[seg];
                    stitch_k += to.index[seg + 1];
                    stitch_w += (float) w;
                    stitch_seam += current_seam;
                }
            }
        }

        public void apply_seams () {
            cloth.clear_seams ();
            stitch_i = {};
            stitch_j = {};
            stitch_k = {};
            stitch_w = {};
            stitch_seam = {};
            current_seam = -1;
            foreach (var sp in settings.seams) {
                current_seam++;
                if (sp.piece_a == sp.piece_b && sp.edge_a == sp.edge_b) {
                    var a = find_chain (sp.piece_a, sp.edge_a, 0);
                    var b = find_chain (sp.piece_b, sp.edge_b, 1);
                    if (a != null && b != null) join (a, sp.a0, sp.a1, b, sp.b0, sp.b1, false);
                    continue;
                }
                for (int side = 0; side < 2; side++) {
                    var a = find_chain (sp.piece_a, sp.edge_a, side);
                    var b = find_chain (sp.piece_b, sp.edge_b, side);
                    if (a == null || b == null) continue;
                    join (a, sp.a0, sp.a1, b, sp.b0, sp.b1, sp.reverse_b);
                }
            }
        }

        private double span_cost (EdgeChain a, double a0, double a1, EdgeChain b, double b0, double b1, bool reverse) {
            double sum = 0;
            for (int i = 0; i <= 8; i++) {
                double k = i / 8.0;
                var pa = a.point_at (this, a0 + (a1 - a0) * k);
                var pb = b.point_at (this, b0 + (b1 - b0) * (reverse ? 1 - k : k));
                sum += pa.distance (pb);
            }
            return sum / 9;
        }

        public Gee.ArrayList<SeamPair> auto_seams (PatternResult result) {
            var list = new Gee.ArrayList<SeamPair> ();
            foreach (var pair in Seams.guess_pairs (result)) {
                var a = find_chain (pair.piece_a, pair.edge_a, 0) ?? find_chain (pair.piece_a, pair.edge_a, 1);
                var b = find_chain (pair.piece_b, pair.edge_b, 0) ?? find_chain (pair.piece_b, pair.edge_b, 1);
                if (a == null || b == null || !a.straight || !b.straight || a.hem || b.hem) continue;
                if (a.side != b.side) continue;
                var sp = new SeamPair (pair.piece_a, pair.edge_a, pair.piece_b, pair.edge_b);
                sp.reverse_b = span_cost (a, 0, 1, b, 0, 1, true) < span_cost (a, 0, 1, b, 0, 1, false);
                list.add (sp);
            }
            foreach (var sleeve in pieces) {
                if (sleeve.placement != "sleeve" || sleeve.copy != 0) continue;
                EdgeChain? cap = null;
                var sides = new Gee.ArrayList<EdgeChain> ();
                foreach (var ch in sleeve.chains) {
                    if (!ch.straight && (cap == null || ch.length > cap.length)) cap = ch;
                    if (ch.straight && !ch.hem) sides.add (ch);
                }
                if (sides.size >= 2) {
                    EdgeChain? best_a = null, best_b = null;
                    double best = double.INFINITY;
                    for (int i = 0; i < sides.size; i++) for (int j = i + 1; j < sides.size; j++) {
                        double d = (sides[i].length - sides[j].length).abs ();
                        if (d < best) {
                            best = d;
                            best_a = sides[i];
                            best_b = sides[j];
                        }
                    }
                    if (best_a != null && best < 0.08 * best_a.length + 5) {
                        var sp = new SeamPair (sleeve.piece_id, best_a.edge, sleeve.piece_id, best_b.edge);
                        sp.reverse_b = true;
                        list.add (sp);
                    }
                }
                if (cap == null) continue;
                var holes = new Gee.ArrayList<ClothPiece> ();
                var hole_chain = new Gee.ArrayList<EdgeChain> ();
                foreach (var p in pieces) {
                    if (p.placement == "sleeve") continue;
                    EdgeChain? arm = null;
                    double outer = -1;
                    foreach (var ch in p.chains) {
                        if (ch.straight || ch.side != 0) continue;
                        double off = 0;
                        for (int i = 0; i < ch.index.length; i++) off += particle (ch.index[i]).x.abs ();
                        off /= ch.index.length;
                        if (off > outer) {
                            outer = off;
                            arm = ch;
                        }
                    }
                    if (arm != null) {
                        holes.add (p);
                        hole_chain.add (arm);
                    }
                }
                if (holes.size == 0) continue;
                double total = 0;
                foreach (var hc in hole_chain) total += hc.length;
                bool cap_front_first = cap.point_at (this, 0.25).z > cap.point_at (this, 0.75).z;
                var ordered = new Gee.ArrayList<int> ();
                for (int i = 0; i < holes.size; i++) ordered.add (i);
                ordered.sort ((p, q) => {
                    double zp = hole_chain[p].point_at (this, 0.5).z, zq = hole_chain[q].point_at (this, 0.5).z;
                    return zp > zq ? -1 : (zp < zq ? 1 : 0);
                });
                if (!cap_front_first) {
                    var rev = new Gee.ArrayList<int> ();
                    for (int i = ordered.size - 1; i >= 0; i--) rev.add (ordered[i]);
                    ordered = rev;
                }
                double at = 0;
                foreach (int hi in ordered) {
                    double share = hole_chain[hi].length / total;
                    var sp = new SeamPair (sleeve.piece_id, cap.edge, holes[hi].piece_id, hole_chain[hi].edge);
                    sp.a0 = at;
                    sp.a1 = at + share;
                    at += share;
                    sp.reverse_b = span_cost (cap, sp.a0, sp.a1, hole_chain[hi], 0, 1, true) < span_cost (cap, sp.a0, sp.a1, hole_chain[hi], 0, 1, false);
                    list.add (sp);
                }
            }
            return list;
        }

        public void reseam () {
            guard.lock ();
            apply_seams ();
            frame = 0;
            guard.unlock ();
        }

        public void auto_sew (PatternResult result) {
            guard.lock ();
            settings.seams.clear ();
            settings.seams.add_all (auto_seams (result));
            apply_seams ();
            frame = 0;
            guard.unlock ();
        }

        public int stitch_count () {
            return stitch_i.length;
        }

        public int stitch (int n, out Vec3 from, out Vec3 to) {
            from = particle (stitch_i[n]);
            to = particle (stitch_j[n]).lerp (particle (stitch_k[n]), stitch_w[n]);
            return stitch_seam[n];
        }

        public double[] seam_gaps () {
            var worst = new double[settings.seams.size];
            for (int n = 0; n < stitch_i.length; n++) {
                Vec3 a, b;
                int s = stitch (n, out a, out b);
                worst[s] = double.max (worst[s], a.distance (b));
            }
            return worst;
        }

        public void step () {
            guard.lock ();
            double gap = frame < 300 ? cloth.seam_gap () : 0;
            cloth.set_gravity ((float) (9810 * ((30 - gap) / 22).clamp (0, 1)));
            cloth.step (1.0f / 60, substeps);
            frame++;
            guard.unlock ();
        }

        public void run (int frames) {
            for (int i = 0; i < frames; i++) step ();
            sync ();
        }

        public void sync () {
            guard.lock ();
            unowned float[] x = cloth.positions ();
            bool strain = map == "strain", distance = map == "distance";
            if (strain) cloth.strain (scratch);
            else if (distance) cloth.distance (scratch);
            foreach (var p in pieces) {
                Memory.copy (p.mesh.positions, &x[p.first * 3], p.count * 3 * sizeof (float));
                if (strain || distance) Memory.copy (p.mesh.scalars, &scratch[p.first], p.count * sizeof (float));
            }
            guard.unlock ();
            foreach (var p in pieces) {
                p.mesh.compute_normals ();
                p.mesh.touch_positions ();
            }
        }

        public void set_fabric (ClothPiece piece, FabricPreset f) {
            guard.lock ();
            piece.fabric = f;
            cloth.set_fabric (piece.fabric_index, physical (f));
            guard.unlock ();
            apply_material (piece);
        }

        public void grab (ClothPiece piece, int local_vertex, Vec3 at, double radius) {
            guard.lock ();
            cloth.grab (piece.first + local_vertex, (float) at.x, (float) at.y, (float) at.z, (float) radius);
            guard.unlock ();
        }

        public void grab_move (Vec3 at) {
            guard.lock ();
            cloth.grab_move ((float) at.x, (float) at.y, (float) at.z);
            guard.unlock ();
        }

        public void release () {
            guard.lock ();
            cloth.release ();
            guard.unlock ();
        }

        public void pin (ClothPiece piece, int local_vertex, bool pinned) {
            guard.lock ();
            cloth.pin (piece.first + local_vertex, pinned ? 1 : 0);
            guard.unlock ();
        }

        public double max_sew_gap () {
            return cloth.seam_gap ();
        }

        public double motion () {
            return cloth.kinetic ();
        }

        public double max_stretch () {
            cloth.strain (scratch);
            double worst = 0;
            for (int i = 0; i < scratch.length; i++) if (scratch[i] > worst) worst = scratch[i];
            return worst;
        }

        public double min_body_distance () {
            cloth.distance (scratch);
            double best = double.INFINITY;
            for (int i = 0; i < scratch.length; i++) if (scratch[i] < best) best = scratch[i];
            return best;
        }

        public Gee.ArrayList<Mesh> export_meshes () {
            var list = new Gee.ArrayList<Mesh> ();
            list.add (Mesh.from_scene (body.mesh));
            foreach (var p in pieces) list.add (Mesh.from_scene (p.mesh));
            return list;
        }
    }
}
