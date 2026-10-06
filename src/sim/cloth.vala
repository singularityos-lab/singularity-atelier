using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class ClothMesher {
        public static void triangulate (Point[] boundary, Point[] interior, out int[] tris) {
            Point[] pts = {};
            foreach (var p in boundary) pts += p;
            foreach (var p in interior) pts += p;
            int n = pts.length;
            var r = Rect.empty ();
            foreach (var p in pts) r = r.include (p.x, p.y);
            double span = double.max (r.w, r.h) * 20 + 100;
            double cx = r.cx (), cy = r.cy ();
            Point[] all = pts;
            all += Point (cx - span, cy - span);
            all += Point (cx + span, cy - span);
            all += Point (cx, cy + span);
            var tri = new Gee.ArrayList<int> ();
            tri.add (n);
            tri.add (n + 1);
            tri.add (n + 2);
            var circ = new Gee.ArrayList<double?> ();
            add_circ (all, circ, n, n + 1, n + 2);
            for (int i = 0; i < n; i++) {
                var p = all[i];
                var bad = new Gee.ArrayList<int> ();
                for (int t = 0; t < tri.size / 3; t++) {
                    double ccx = circ[t * 3], ccy = circ[t * 3 + 1], rr = circ[t * 3 + 2];
                    double dx = p.x - ccx, dy = p.y - ccy;
                    if (dx * dx + dy * dy < rr) bad.add (t);
                }
                var edges = new Gee.HashMap<string, int> ();
                var edge_a = new Gee.ArrayList<int> ();
                var edge_b = new Gee.ArrayList<int> ();
                foreach (var t in bad) {
                    for (int e = 0; e < 3; e++) {
                        int a = tri[t * 3 + e], b = tri[t * 3 + (e + 1) % 3];
                        string key = a < b ? "%d:%d".printf (a, b) : "%d:%d".printf (b, a);
                        if (edges.has_key (key)) edges[key] = edges[key] + 1;
                        else {
                            edges[key] = 1;
                            edge_a.add (a);
                            edge_b.add (b);
                        }
                    }
                }
                for (int k = bad.size - 1; k >= 0; k--) {
                    int t = bad[k];
                    int last = tri.size / 3 - 1;
                    if (t != last) {
                        for (int j = 0; j < 3; j++) {
                            tri[t * 3 + j] = tri[last * 3 + j];
                            circ[t * 3 + j] = circ[last * 3 + j];
                        }
                    }
                    for (int j = 0; j < 3; j++) {
                        tri.remove_at (tri.size - 1);
                        circ.remove_at (circ.size - 1);
                    }
                }
                for (int k = 0; k < edge_a.size; k++) {
                    int a = edge_a[k], b = edge_b[k];
                    string key = a < b ? "%d:%d".printf (a, b) : "%d:%d".printf (b, a);
                    if (edges[key] != 1) continue;
                    tri.add (a);
                    tri.add (b);
                    tri.add (i);
                    add_circ (all, circ, a, b, i);
                }
            }
            int[] result = {};
            for (int t = 0; t < tri.size / 3; t++) {
                int a = tri[t * 3], b = tri[t * 3 + 1], c = tri[t * 3 + 2];
                if (a >= n || b >= n || c >= n) continue;
                var pa = all[a];
                var pb = all[b];
                var pc = all[c];
                var cen = Point ((pa.x + pb.x + pc.x) / 3, (pa.y + pb.y + pc.y) / 3);
                if (!inside (boundary, cen)) continue;
                if (!mid_ok (boundary, pa, pb) || !mid_ok (boundary, pb, pc) || !mid_ok (boundary, pc, pa)) continue;
                double area = (pb.x - pa.x) * (pc.y - pa.y) - (pb.y - pa.y) * (pc.x - pa.x);
                if (area.abs () < 1e-6) continue;
                if (area < 0) {
                    result += a;
                    result += c;
                    result += b;
                } else {
                    result += a;
                    result += b;
                    result += c;
                }
            }
            tris = result;
        }

        private static bool mid_ok (Point[] ring, Point a, Point b) {
            var m = Point ((a.x + b.x) / 2, (a.y + b.y) / 2);
            if (inside (ring, m)) return true;
            return boundary_distance (ring, m) < 1e-3 * (1 + a.distance (b));
        }

        private static void add_circ (Point[] p, Gee.ArrayList<double?> circ, int ia, int ib, int ic) {
            var a = p[ia];
            var b = p[ib];
            var c = p[ic];
            double d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y));
            if (d.abs () < 1e-12) {
                circ.add (0);
                circ.add (0);
                circ.add (double.INFINITY);
                return;
            }
            double a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, c2 = c.x * c.x + c.y * c.y;
            double ux = (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d;
            double uy = (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d;
            circ.add (ux);
            circ.add (uy);
            circ.add ((a.x - ux) * (a.x - ux) + (a.y - uy) * (a.y - uy));
        }

        public static bool inside (Point[] ring, Point p) {
            bool c = false;
            int n = ring.length;
            for (int i = 0, j = n - 1; i < n; j = i++) {
                if (((ring[i].y > p.y) != (ring[j].y > p.y)) && (p.x < (ring[j].x - ring[i].x) * (p.y - ring[i].y) / (ring[j].y - ring[i].y) + ring[i].x)) c = !c;
            }
            return c;
        }

        public static double boundary_distance (Point[] ring, Point p) {
            double best = double.INFINITY;
            for (int i = 0; i < ring.length; i++) best = double.min (best, PathData.segment_distance (ring[i], ring[(i + 1) % ring.length], p.x, p.y));
            return best;
        }

        public static Point[] lattice (Point[] ring, double h) {
            var r = Rect.empty ();
            foreach (var p in ring) r = r.include (p.x, p.y);
            Point[] pts = {};
            double dy = h * Math.sqrt (3) / 2;
            int row = 0;
            for (double y = r.y + dy / 2; y < r.y2 (); y += dy, row++) {
                for (double x = r.x + (row % 2 == 0 ? h / 2 : h); x < r.x2 (); x += h) {
                    var p = Point (x, y);
                    if (inside (ring, p) && boundary_distance (ring, p) > h * 0.55) pts += p;
                }
            }
            return pts;
        }

        public static Point[] resample_edge (Point[] pts, double h) {
            double len = Polyline.length (pts);
            int segs = int.max (1, (int) Math.round (len / h));
            Point[] out_pts = {};
            for (int i = 0; i <= segs; i++) {
                double ang;
                out_pts += Polyline.at_length (pts, len * i / segs, out ang);
            }
            return out_pts;
        }
    }

    public class ClothEdge {
        public int source_edge;
        public bool mirrored;
        public int[] chain;
        public bool straight;
        public bool hem;
        public bool fold;
        public bool armhole;
        public bool cap;

        public ClothEdge (int source_edge, bool mirrored, int[] chain) {
            this.source_edge = source_edge;
            this.mirrored = mirrored;
            this.chain = chain;
        }
    }

    public class ClothInstance {
        public string piece_id;
        public string placement;
        public int copy;
        public int first;
        public int count;
        public Gee.ArrayList<ClothEdge> edges = new Gee.ArrayList<ClothEdge> ();
        public FabricPreset fabric;
    }

    public class ClothState {
        public int n;
        public double[] x = {};
        public double[] y = {};
        public double[] z = {};
        public double[] px = {};
        public double[] py = {};
        public double[] pz = {};
        public double[] vx = {};
        public double[] vy = {};
        public double[] vz = {};
        public double[] w = {};
        public double[] u = {};
        public double[] v = {};
        public double[] friction = {};
        public double[] thickness = {};
        public int[] tris = {};
        public int[] ca = {};
        public int[] cb = {};
        public double[] rest = {};
        public double[] compliance = {};
        public int[] kind = {};
        public double[] lambda = {};
        public double sew_scale = 1;
        public double damping = 0.02;
        public int[] group = {};
        public double spacing = 18;

        public int m;
        public int nt;

        private void grow_particles () {
            int cap = int.max (64, x.length * 2);
            x.resize (cap);
            y.resize (cap);
            z.resize (cap);
            px.resize (cap);
            py.resize (cap);
            pz.resize (cap);
            vx.resize (cap);
            vy.resize (cap);
            vz.resize (cap);
            w.resize (cap);
            u.resize (cap);
            v.resize (cap);
            friction.resize (cap);
            thickness.resize (cap);
        }

        private void grow_constraints () {
            int cap = int.max (64, ca.length * 2);
            ca.resize (cap);
            cb.resize (cap);
            rest.resize (cap);
            compliance.resize (cap);
            kind.resize (cap);
            lambda.resize (cap);
        }

        public int add_particle (Vec3 p, double uu, double vv, double mass, double fr, double th) {
            if (n >= x.length) grow_particles ();
            x[n] = p.x;
            y[n] = p.y;
            z[n] = p.z;
            px[n] = p.x;
            py[n] = p.y;
            pz[n] = p.z;
            vx[n] = 0;
            vy[n] = 0;
            vz[n] = 0;
            w[n] = mass > 0 ? 1 / mass : 0;
            u[n] = uu;
            v[n] = vv;
            friction[n] = fr;
            thickness[n] = th;
            return n++;
        }

        public void add_constraint (int a, int b, double r, double comp, int k) {
            if (m >= ca.length) grow_constraints ();
            ca[m] = a;
            cb[m] = b;
            rest[m] = r;
            compliance[m] = comp;
            kind[m] = k;
            lambda[m] = 0;
            m++;
        }

        public void add_tri (int a, int b, int c) {
            if (nt * 3 + 3 > tris.length) tris.resize (int.max (192, tris.length * 2));
            tris[nt * 3] = a;
            tris[nt * 3 + 1] = b;
            tris[nt * 3 + 2] = c;
            nt++;
        }

        public Vec3 pos (int i) {
            return Vec3 (x[i], y[i], z[i]);
        }

        public void set_pos (int i, Vec3 p) {
            x[i] = p.x;
            y[i] = p.y;
            z[i] = p.z;
        }
    }

    public abstract class ClothSolver {
        public double gravity_scale = 1;
        public bool collide_layers = true;
        public abstract string name { get; }
        public abstract void step (ClothState s, AvatarCollider? collider, double dt, int substeps);
    }

    public class CpuXpbdSolver : ClothSolver {
        public double gravity = -9810;
        public int iterations = 4;

        public override string name {
            get { return "cpu-xpbd"; }
        }

        public override void step (ClothState s, AvatarCollider? collider, double dt, int substeps) {
            double h = dt / int.max (1, substeps);
            for (int sub = 0; sub < substeps; sub++) {
                for (int i = 0; i < s.n; i++) {
                    s.px[i] = s.x[i];
                    s.py[i] = s.y[i];
                    s.pz[i] = s.z[i];
                    if (s.w[i] == 0) continue;
                    s.vy[i] += gravity * gravity_scale * h;
                    s.x[i] += s.vx[i] * h;
                    s.y[i] += s.vy[i] * h;
                    s.z[i] += s.vz[i] * h;
                }
                for (int c = 0; c < s.m; c++) s.lambda[c] = 0;
                double h2 = h * h;
                int m = s.m;
                for (int it = 0; it < iterations; it++) {
                    for (int c = 0; c < m; c++) {
                        int a = s.ca[c], b = s.cb[c];
                        double wa = s.w[a], wb = s.w[b];
                        double ws = wa + wb;
                        if (ws == 0) continue;
                        double dx = s.x[a] - s.x[b], dy = s.y[a] - s.y[b], dz = s.z[a] - s.z[b];
                        double len = Math.sqrt (dx * dx + dy * dy + dz * dz);
                        double comp = s.compliance[c];
                        if (s.kind[c] == 2) comp *= s.sew_scale;
                        double alpha = comp / h2;
                        double cval = len - s.rest[c];
                        if (s.kind[c] == 2 && len < 1e-9) continue;
                        if (len < 1e-9) continue;
                        double dl = (-cval - alpha * s.lambda[c]) / (ws + alpha);
                        s.lambda[c] += dl;
                        double nx = dx / len, ny = dy / len, nz = dz / len;
                        s.x[a] += nx * dl * wa;
                        s.y[a] += ny * dl * wa;
                        s.z[a] += nz * dl * wa;
                        s.x[b] -= nx * dl * wb;
                        s.y[b] -= ny * dl * wb;
                        s.z[b] -= nz * dl * wb;
                    }
                }
                if (collider != null) {
                    for (int pass = 0; pass < 3; pass++)
                    for (int i = 0; i < s.n; i++) {
                        if (s.w[i] == 0) continue;
                        var p = Vec3 (s.x[i], s.y[i], s.z[i]);
                        Vec3 nrm;
                        double d = collider.distance (p, out nrm);
                        double th = s.thickness[i];
                        if (d < th) {
                            p = p.add (nrm.scale (th - d));
                            var prev = Vec3 (s.px[i], s.py[i], s.pz[i]);
                            var delta = p.sub (prev);
                            var tang = delta.sub (nrm.scale (delta.dot (nrm)));
                            p = p.sub (tang.scale (s.friction[i].clamp (0, 1)));
                            s.x[i] = p.x;
                            s.y[i] = p.y;
                            s.z[i] = p.z;
                        }
                    }
                }
                double keep = 1 - s.damping;
                for (int i = 0; i < s.n; i++) {
                    s.vx[i] = (s.x[i] - s.px[i]) / h * keep;
                    s.vy[i] = (s.y[i] - s.py[i]) / h * keep;
                    s.vz[i] = (s.z[i] - s.pz[i]) / h * keep;
                }
            }
        }
    }

    public class GarmentSim {
        public ClothState state = new ClothState ();
        public ClothSolver solver = new ParallelXpbdSolver ();
        public AvatarModel avatar;
        public AvatarCollider collider;
        public Gee.ArrayList<ClothInstance> instances = new Gee.ArrayList<ClothInstance> ();
        public Gee.ArrayList<int> sew_a = new Gee.ArrayList<int> ();
        public Gee.ArrayList<int> sew_b = new Gee.ArrayList<int> ();
        public int frame;
        public int substeps = 10;
        public double dt = 1.0 / 60;
        public double spacing = 18;
        public int sew_frames = 60;
        private GarmentSettings settings;
        private string size;
        private double wrap_radius;

        public GarmentSim (PatternResult result, GarmentSettings settings, MeasurementTable table, string size) {
            this.settings = settings;
            this.size = size;
            spacing = ((double) settings.resolution).clamp (6, 60);
            avatar = Avatar.model (table, size, settings.pose);
            collider = new AvatarCollider (avatar);
            build (result);
        }

        public void set_avatar (MeasurementTable table, string new_size, string pose) {
            size = new_size;
            avatar = Avatar.model (table, new_size, pose);
            collider = new AvatarCollider (avatar);
        }

        public void rebuild (PatternResult result) {
            var old_state = state;
            var old_instances = instances;
            state = new ClothState ();
            instances = new Gee.ArrayList<ClothInstance> ();
            sew_a.clear ();
            sew_b.clear ();
            build (result);
            foreach (var inst in instances) {
                ClothInstance? prev = null;
                foreach (var o in old_instances) if (o.piece_id == inst.piece_id && o.copy == inst.copy) prev = o;
                if (prev == null) continue;
                for (int i = inst.first; i < inst.first + inst.count; i++) {
                    int best = -1;
                    double bd = double.INFINITY;
                    for (int j = prev.first; j < prev.first + prev.count; j++) {
                        double d = Math.hypot (old_state.u[j] - state.u[i], old_state.v[j] - state.v[i]);
                        if (d < bd) {
                            bd = d;
                            best = j;
                        }
                    }
                    if (best >= 0) {
                        state.x[i] = old_state.x[best];
                        state.y[i] = old_state.y[best];
                        state.z[i] = old_state.z[best];
                    }
                }
            }
            frame = sew_frames;
            state.sew_scale = 1;
        }

        private static Point mirror_point (Point p, Point a, Point b) {
            double dx = b.x - a.x, dy = b.y - a.y;
            double l2 = dx * dx + dy * dy;
            if (l2 < 1e-12) return p;
            double t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2;
            var f = Point (a.x + dx * t, a.y + dy * t);
            return Point (2 * f.x - p.x, 2 * f.y - p.y);
        }

        private void build (PatternResult result) {
            double front_w = 0, back_w = 0;
            foreach (var g in result.pieces) {
                if (g.seam.length < 3) continue;
                var b = g.bounds ();
                double wdt = g.piece.on_fold ? b.w * 2 : b.w;
                if (g.piece.placement == "back") back_w += wdt;
                else if (g.piece.placement != "sleeve") front_w += wdt;
            }
            double max_half = 0;
            foreach (var s in avatar.torso) max_half = double.max (max_half, double.max (s.a, s.b + s.cz.abs ()));
            wrap_radius = double.max ((front_w + back_w) / (2 * Math.PI), max_half + 30);
            foreach (var g in result.pieces) {
                if (g.seam.length < 3 || g.edges.size == 0) continue;
                int copies = g.piece.placement == "sleeve" || (g.piece.pair && !g.piece.on_fold) ? 2 : 1;
                for (int c = 0; c < copies; c++) add_instance (g, c);
            }
            sew (result);
            state.group = new int[state.n];
            for (int k = 0; k < instances.size; k++) {
                var inst = instances[k];
                for (int i = inst.first; i < inst.first + inst.count && i < state.n; i++) state.group[i] = k;
            }
            state.spacing = spacing;
        }

        private void add_instance (PieceGeometry g, int copy) {
            var inst = new ClothInstance ();
            inst.piece_id = g.piece.id;
            inst.placement = g.piece.placement;
            inst.copy = copy;
            inst.fabric = FabricPreset.find (settings.piece_fabrics.has_key (g.piece.id) ? settings.piece_fabrics[g.piece.id] : settings.fabric_preset);
            int ne = g.edges.size;
            bool unfold = g.piece.on_fold && g.piece.fold_edge >= 0 && g.piece.fold_edge < ne && ne > 1;
            var ring = new Gee.ArrayList<Point?> ();
            var chains = new Gee.ArrayList<ClothEdge> ();
            var local_chains = new Gee.ArrayList<Gee.ArrayList<int>> ();
            int f = unfold ? g.piece.fold_edge : -1;
            Point fa = Point (0, 0), fb = Point (0, 0);
            if (unfold) {
                var fe = g.edges[f].pts;
                fa = fe[0];
                fb = fe[fe.length - 1];
            }
            var order = new Gee.ArrayList<int> ();
            if (unfold) for (int k = 1; k < ne; k++) order.add ((f + k) % ne);
            else for (int k = 0; k < ne; k++) order.add (k);
            foreach (var ei in order) {
                var pts = ClothMesher.resample_edge (g.edges[ei].pts, spacing);
                var chain = new Gee.ArrayList<int> ();
                for (int k = 0; k < pts.length; k++) {
                    if (k == 0 && ring.size > 0) {
                        chain.add (ring.size - 1);
                        continue;
                    }
                    ring.add (pts[k]);
                    chain.add (ring.size - 1);
                }
                var ce = new ClothEdge (ei, false, {});
                chains.add (ce);
                local_chains.add (chain);
            }
            if (unfold) {
                int prev_first = -1;
                for (int k = order.size - 1; k >= 0; k--) {
                    var src = local_chains[k];
                    var chain = new Gee.ArrayList<int> ();
                    for (int j = src.size - 1; j >= 0; j--) {
                        int idx = src[j];
                        var mp = mirror_point (ring[idx], fa, fb);
                        int use = -1;
                        if (j == src.size - 1) use = k == order.size - 1 ? src[j] : prev_first;
                        else if (j == 0 && k == 0) use = local_chains[0][0];
                        if (use < 0) {
                            ring.add (mp);
                            use = ring.size - 1;
                        }
                        chain.insert (0, use);
                    }
                    prev_first = chain[0];
                    var ce = new ClothEdge (order[k], true, {});
                    chains.add (ce);
                    local_chains.add (chain);
                }
            } else {
                var last = local_chains[local_chains.size - 1];
                if (ring.size > 1 && ring[ring.size - 1].distance (ring[0]) < 1e-6) {
                    ring.remove_at (ring.size - 1);
                    last[last.size - 1] = 0;
                }
            }
            Point[] boundary = new Point[ring.size];
            for (int i = 0; i < ring.size; i++) boundary[i] = ring[i];
            if (Polyline.signed_area (boundary).abs () < 1) return;
            var interior = ClothMesher.lattice (boundary, spacing);
            int[] tris;
            ClothMesher.triangulate (boundary, interior, out tris);
            Point[] pts2d = {};
            foreach (var p in boundary) pts2d += p;
            foreach (var p in interior) pts2d += p;
            var r = Rect.empty ();
            foreach (var p in pts2d) r = r.include (p.x, p.y);
            double cx = unfold ? (fa.x + fb.x) / 2 : r.cx ();
            double area = Polyline.signed_area (boundary).abs ();
            double mass = inst.fabric.density * area * 1e-6 / pts2d.length;
            inst.first = state.n;
            inst.count = pts2d.length;
            foreach (var p in pts2d) {
                var q = copy == 1 ? Point (2 * cx - p.x, p.y) : p;
                state.add_particle (place (g, q, cx, r, copy), p.x, p.y, mass, inst.fabric.friction * 0.12, 1.5 + inst.fabric.thickness);
            }
            var edge_keys = new Gee.HashMap<string, int> ();
            var tri_of_edge = new Gee.HashMap<string, int> ();
            for (int t = 0; t + 2 < tris.length; t += 3) {
                state.add_tri (inst.first + tris[t], inst.first + (copy == 1 ? tris[t + 2] : tris[t + 1]), inst.first + (copy == 1 ? tris[t + 1] : tris[t + 2]));
                for (int e = 0; e < 3; e++) {
                    int a = tris[t + e], b = tris[t + (e + 1) % 3];
                    int opp = tris[t + (e + 2) % 3];
                    string key = a < b ? "%d:%d".printf (a, b) : "%d:%d".printf (b, a);
                    if (!edge_keys.has_key (key)) {
                        edge_keys[key] = 1;
                        tri_of_edge[key] = opp;
                        state.add_constraint (inst.first + a, inst.first + b, pts2d[a].distance (pts2d[b]), inst.fabric.stretch_compliance, 0);
                    } else {
                        int o = tri_of_edge[key];
                        state.add_constraint (inst.first + o, inst.first + opp, pts2d[o].distance (pts2d[opp]), inst.fabric.bend_compliance, 1);
                    }
                }
            }
            for (int k = 0; k < chains.size; k++) {
                var ce = chains[k];
                var lc = local_chains[k];
                int[] arr = new int[lc.size];
                for (int j = 0; j < lc.size; j++) arr[j] = inst.first + lc[j];
                ce.chain = arr;
                var src = g.edges[ce.source_edge].pts;
                ce.straight = src.length <= 2;
                inst.edges.add (ce);
            }
            classify (g, inst);
            instances.add (inst);
        }

        private void classify (PieceGeometry g, ClothInstance inst) {
            var b = Rect.empty ();
            foreach (var q in g.seam) b = b.include (q.x, q.y);
            double best_curve = -1;
            ClothEdge? cap = null;
            double best_outer = -1;
            foreach (var ce in inst.edges) {
                var src = g.edges[ce.source_edge].pts;
                var a = src[0];
                var z = src[src.length - 1];
                var mid = Point ((a.x + z.x) / 2, (a.y + z.y) / 2);
                ce.hem = ce.straight && mid.y > b.y2 () - b.h * 0.06 && (z.y - a.y).abs () < 0.35 * (z.x - a.x).abs () + 1;
                if (!ce.straight) {
                    double len = Polyline.length (src);
                    if (inst.placement == "sleeve" && len > best_curve) {
                        best_curve = len;
                        cap = ce;
                    }
                }
            }
            if (cap != null) {
                foreach (var ce in inst.edges) if (ce.source_edge == cap.source_edge) ce.cap = true;
            }
            if (inst.placement != "sleeve") {
                int arm_edge = -1;
                foreach (var ce in inst.edges) {
                    if (ce.straight || ce.mirrored) continue;
                    var src = g.edges[ce.source_edge].pts;
                    double outer = 0;
                    foreach (var p in src) outer += (p.x - (g.piece.on_fold && g.piece.fold_edge >= 0 ? g.edges[g.piece.fold_edge].pts[0].x : b.cx ())).abs ();
                    outer /= src.length;
                    if (outer > best_outer) {
                        best_outer = outer;
                        arm_edge = ce.source_edge;
                    }
                }
                if (arm_edge >= 0) foreach (var ce in inst.edges) if (ce.source_edge == arm_edge) ce.armhole = true;
            }
        }

        private Vec3 place (PieceGeometry g, Point p, double cx, Rect bounds, int copy) {
            string pl = g.piece.placement;
            var d = avatar.dims;
            if (pl == "sleeve") {
                var sh = copy == 0 ? avatar.shoulder_right : avatar.shoulder_left;
                var wr = copy == 0 ? avatar.wrist_right : avatar.wrist_left;
                var axis = wr.sub (sh).normalized ();
                var up = Vec3 (0, 1, 0);
                var uu = up.sub (axis.scale (up.dot (axis))).normalized ();
                var ww = axis.cross (uu).normalized ();
                if (copy == 1) ww = ww.neg ();
                double radius = double.max (bounds.w / (2 * Math.PI), d.upper_arm / (2 * Math.PI) + 25);
                double phi = (p.x - bounds.cx ()) / radius;
                double s = (p.y - bounds.y) - bounds.h * 0.25;
                return sh.add (axis.scale (s)).add (uu.scale (radius * Math.cos (phi))).add (ww.scale (radius * Math.sin (phi)));
            }
            double top = d.y_neck () + 25;
            double theta = (p.x - cx) / wrap_radius;
            double y3 = top - (p.y - bounds.y);
            if (pl == "back") theta = Math.PI - theta;
            return Vec3 (wrap_radius * Math.sin (theta), y3, -4 + wrap_radius * Math.cos (theta));
        }

        private void sew (PatternResult result) {
            if (settings.seams.size > 0) {
                foreach (var pair in settings.seams) {
                    var la = chains_for (pair.piece_a, pair.edge_a);
                    var lb = chains_for (pair.piece_b, pair.edge_b);
                    var used = new Gee.HashSet<ClothEdge> ();
                    foreach (var ea in la) {
                        ClothEdge? best = null;
                        double bd = double.INFINITY;
                        foreach (var eb in lb) {
                            if (used.contains (eb) || eb == ea) continue;
                            double dd = chain_mid (ea).distance (chain_mid (eb));
                            if (dd < bd) {
                                bd = dd;
                                best = eb;
                            }
                        }
                        if (best != null) {
                            used.add (best);
                            used.add (ea);
                            join (ea.chain, best.chain);
                        }
                    }
                }
                return;
            }
            var guessed = Seams.guess_pairs (result);
            foreach (var pair in guessed) {
                var la = chains_for (pair.piece_a, pair.edge_a);
                var lb = chains_for (pair.piece_b, pair.edge_b);
                foreach (var ea in la) {
                    if (!ea.straight || ea.hem) continue;
                    foreach (var eb in lb) {
                        if (!eb.straight || eb.hem || eb.mirrored != ea.mirrored) continue;
                        join (ea.chain, eb.chain);
                    }
                }
            }
            foreach (var inst in instances) {
                if (inst.placement != "sleeve") continue;
                var sides = new Gee.ArrayList<ClothEdge> ();
                ClothEdge? cap = null;
                foreach (var ce in inst.edges) {
                    if (ce.cap) cap = ce;
                    else if (ce.straight && !ce.hem) sides.add (ce);
                }
                if (sides.size == 2) join (sides[0].chain, sides[1].chain);
                if (cap == null) continue;
                int top = 0;
                for (int i = 1; i < cap.chain.length; i++) if (state.y[cap.chain[i]] > state.y[cap.chain[top]]) top = i;
                int[] h1 = cap.chain[0:top + 1];
                int[] h2 = cap.chain[top:cap.chain.length];
                var armholes = new Gee.ArrayList<ClothEdge> ();
                foreach (var o in instances) if (o.placement != "sleeve") foreach (var ce in o.edges) if (ce.armhole) armholes.add (ce);
                var taken = new Gee.HashSet<ClothEdge> ();
                sew_half (h1, armholes, taken);
                sew_half (h2, armholes, taken);
            }
        }

        private void sew_half (int[] half, Gee.List<ClothEdge> armholes, Gee.Set<ClothEdge> taken) {
            if (half.length < 2) return;
            var hm = chain_mid_arr (half);
            ClothEdge? best = null;
            double bd = double.INFINITY;
            foreach (var ah in armholes) {
                if (taken.contains (ah)) continue;
                double dd = chain_mid (ah).distance (hm);
                if (dd < bd) {
                    bd = dd;
                    best = ah;
                }
            }
            if (best == null || bd > wrap_radius * 2.5) return;
            taken.add (best);
            int[] a = half;
            if (state.y[a[0]] > state.y[a[a.length - 1]]) a = reversed (a);
            int[] b = best.chain;
            if (state.y[b[0]] > state.y[b[b.length - 1]]) b = reversed (b);
            join_ordered (a, b);
        }

        private static int[] reversed (int[] a) {
            int[] r = new int[a.length];
            for (int i = 0; i < a.length; i++) r[i] = a[a.length - 1 - i];
            return r;
        }

        private Gee.ArrayList<ClothEdge> chains_for (string piece, int edge) {
            var l = new Gee.ArrayList<ClothEdge> ();
            foreach (var inst in instances) if (inst.piece_id == piece) foreach (var ce in inst.edges) if (ce.source_edge == edge) l.add (ce);
            return l;
        }

        private Vec3 chain_mid (ClothEdge e) {
            return chain_mid_arr (e.chain);
        }

        private Vec3 chain_mid_arr (int[] c) {
            return state.pos (c[c.length / 2]);
        }

        private void join (int[] a, int[] b) {
            double direct = state.pos (a[0]).distance (state.pos (b[0])) + state.pos (a[a.length - 1]).distance (state.pos (b[b.length - 1]));
            double crossed = state.pos (a[0]).distance (state.pos (b[b.length - 1])) + state.pos (a[a.length - 1]).distance (state.pos (b[0]));
            join_ordered (a, crossed < direct ? reversed (b) : b);
        }

        private double[] fractions (int[] c) {
            var f = new double[c.length];
            double total = 0;
            for (int i = 1; i < c.length; i++) {
                total += Math.hypot (state.u[c[i]] - state.u[c[i - 1]], state.v[c[i]] - state.v[c[i - 1]]);
                f[i] = total;
            }
            for (int i = 0; i < c.length; i++) f[i] = total > 0 ? f[i] / total : 0;
            return f;
        }

        private void join_ordered (int[] a, int[] b) {
            if (a.length < 1 || b.length < 1) return;
            var fa = fractions (a);
            var fb = fractions (b);
            var seen = new Gee.HashSet<string> ();
            int k = int.max (a.length, b.length);
            for (int i = 0; i < k; i++) {
                double t = k > 1 ? (double) i / (k - 1) : 0;
                int ia = nearest (fa, t), ib = nearest (fb, t);
                int pa = a[ia], pb = b[ib];
                if (pa == pb) continue;
                string key = "%d:%d".printf (pa, pb);
                if (seen.contains (key)) continue;
                seen.add (key);
                state.add_constraint (pa, pb, 0, 1e-7, 2);
                sew_a.add (pa);
                sew_b.add (pb);
            }
        }

        private static int nearest (double[] f, double t) {
            int best = 0;
            for (int i = 1; i < f.length; i++) if ((f[i] - t).abs () < (f[best] - t).abs ()) best = i;
            return best;
        }

        public void step (int substeps) {
            if (sew_frames > 0) state.sew_scale = frame < sew_frames ? Math.pow (10, 7 * (1 - (double) frame / sew_frames)) : 1;
            bool sewing = frame < sew_frames;
            state.damping = sewing ? 0.2 : 0.03;
            solver.gravity_scale = sewing ? 0 : double.min (1, (frame - sew_frames + 1) / 20.0);
            solver.collide_layers = !sewing;
            solver.step (state, collider, dt, substeps);
            frame++;
        }

        public void run (int frames) {
            for (int i = 0; i < frames; i++) step (substeps);
        }

        public double max_sew_gap () {
            double m = 0;
            for (int i = 0; i < sew_a.size; i++) m = double.max (m, state.pos (sew_a[i]).distance (state.pos (sew_b[i])));
            return m;
        }

        public double mean_sew_gap () {
            if (sew_a.size == 0) return 0;
            double t = 0;
            for (int i = 0; i < sew_a.size; i++) t += state.pos (sew_a[i]).distance (state.pos (sew_b[i]));
            return t / sew_a.size;
        }

        public double min_collider_distance () {
            double m = double.INFINITY;
            for (int i = 0; i < state.n; i++) {
                Vec3 nrm;
                m = double.min (m, collider.distance (state.pos (i), out nrm));
            }
            return m;
        }

        public double[] strain_map () {
            var sum = new double[state.n];
            var cnt = new int[state.n];
            for (int c = 0; c < state.m; c++) {
                if (state.kind[c] != 0 || state.rest[c] <= 0) continue;
                int a = state.ca[c], b = state.cb[c];
                double s = state.pos (a).distance (state.pos (b)) / state.rest[c] - 1;
                sum[a] += s;
                sum[b] += s;
                cnt[a]++;
                cnt[b]++;
            }
            for (int i = 0; i < state.n; i++) if (cnt[i] > 0) sum[i] /= cnt[i];
            return sum;
        }

        public double[] distance_map () {
            var d = new double[state.n];
            for (int i = 0; i < state.n; i++) {
                Vec3 nrm;
                d[i] = collider.distance (state.pos (i), out nrm);
            }
            return d;
        }

        public double max_stretch () {
            double m = 0;
            for (int c = 0; c < state.m; c++) {
                if (state.kind[c] != 0 || state.rest[c] <= 0) continue;
                m = double.max (m, state.pos (state.ca[c]).distance (state.pos (state.cb[c])) / state.rest[c] - 1);
            }
            return m;
        }

        public Mesh garment_mesh (string map = "strain") {
            var m = new Mesh ();
            m.name = "garment";
            for (int i = 0; i < state.n; i++) {
                m.vertices.add (state.pos (i));
                m.uvs.add (state.u[i] / 1000);
                m.uvs.add (state.v[i] / 1000);
            }
            for (int t = 0; t < state.nt * 3; t++) m.triangles.add (state.tris[t]);
            var values = map == "distance" ? distance_map () : strain_map ();
            foreach (var v in values) m.scalars.add (v);
            m.compute_normals ();
            var fab = instances.size > 0 ? instances[0].fabric : FabricPreset.find (settings.fabric_preset);
            m.color = fab.color;
            m.roughness = fab.roughness;
            m.metallic = fab.metallic;
            m.material = fab.id;
            return m;
        }

        public Gee.ArrayList<Mesh> piece_meshes () {
            var list = new Gee.ArrayList<Mesh> ();
            foreach (var inst in instances) {
                var m = new Mesh ();
                m.name = inst.piece_id;
                for (int i = inst.first; i < inst.first + inst.count; i++) {
                    m.vertices.add (state.pos (i));
                    m.uvs.add (state.u[i] / 1000);
                    m.uvs.add (state.v[i] / 1000);
                }
                for (int t = 0; t + 2 < state.nt * 3; t += 3) {
                    int a = state.tris[t];
                    if (a < inst.first || a >= inst.first + inst.count) continue;
                    m.add_triangle (a - inst.first, state.tris[t + 1] - inst.first, state.tris[t + 2] - inst.first);
                }
                m.compute_normals ();
                m.color = inst.fabric.color;
                m.roughness = inst.fabric.roughness;
                m.material = inst.fabric.id;
                list.add (m);
            }
            return list;
        }
    }
}
