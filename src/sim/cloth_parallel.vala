namespace Singularity.Apps.Atelier {

    public delegate void RangeFunc (int start, int end);

    public class SpinBarrier {
        private int parties;
        private int count;
        private int gen;

        public SpinBarrier (int parties) {
            this.parties = parties;
        }

        public void wait () {
            int g = AtomicInt.get (ref gen);
            if (AtomicInt.add (ref count, 1) == parties - 1) {
                AtomicInt.set (ref count, 0);
                AtomicInt.inc (ref gen);
                return;
            }
            int spins = 0;
            while (AtomicInt.get (ref gen) == g) {
                if (++spins > 256) Thread.yield ();
            }
        }
    }

    public class WorkPool {
        private class Worker {
            public WorkPool pool;
            public int index;

            public Worker (WorkPool pool, int index) {
                this.pool = pool;
                this.index = index;
            }

            public void* run () {
                pool.loop (index);
                return null;
            }
        }

        public int size { get; private set; }
        public int limit { get; set; }
        private Mutex mutex = Mutex ();
        private Cond start_cond = Cond ();
        private Cond done_cond = Cond ();
        private int generation;
        private int pending;
        private bool stopping;
        private unowned RangeFunc? job;
        private int job_n;
        private int job_workers = 1;
        private Gee.ArrayList<Worker> workers = new Gee.ArrayList<Worker> ();
        private Thread<void*>[] threads = {};
        private static WorkPool? shared;

        public WorkPool (int size) {
            this.size = int.max (1, size);
            this.limit = this.size;
            for (int i = 1; i < this.size; i++) {
                var w = new Worker (this, i);
                workers.add (w);
                threads += new Thread<void*> ("atelier-sim", w.run);
            }
        }

        public static WorkPool get_default () {
            if (shared == null) {
                int n = (int) get_num_processors ();
                string? env = Environment.get_variable ("ATELIER_SIM_THREADS");
                if (env != null) n = int.parse (env);
                shared = new WorkPool (n.clamp (1, 16));
            }
            return shared;
        }

        private void chunk (int index, int n, int workers, out int start, out int end) {
            if (index >= workers) {
                start = 0;
                end = 0;
                return;
            }
            start = (int) ((int64) n * index / workers);
            end = (int) ((int64) n * (index + 1) / workers);
        }

        internal void loop (int index) {
            int seen = 0;
            while (true) {
                mutex.lock ();
                while (generation == seen && !stopping) start_cond.wait (mutex);
                if (stopping) {
                    mutex.unlock ();
                    return;
                }
                seen = generation;
                unowned RangeFunc f = job;
                int n = job_n;
                int workers = job_workers;
                mutex.unlock ();
                int s, e;
                chunk (index, n, workers, out s, out e);
                if (s < e) f (s, e);
                mutex.lock ();
                pending--;
                if (pending == 0) done_cond.signal ();
                mutex.unlock ();
            }
        }

        public void run (int n, RangeFunc f, int grain = 256) {
            int workers = int.min (int.min (size, limit), n / int.max (1, grain));
            if (workers <= 1) {
                if (n > 0) f (0, n);
                return;
            }
            mutex.lock ();
            job = f;
            job_n = n;
            job_workers = workers;
            pending = size - 1;
            generation++;
            start_cond.broadcast ();
            mutex.unlock ();
            int s, e;
            chunk (0, n, workers, out s, out e);
            if (s < e) f (s, e);
            mutex.lock ();
            while (pending > 0) done_cond.wait (mutex);
            job = null;
            mutex.unlock ();
        }
    }

    public class ParallelXpbdSolver : ClothSolver {
        public double gravity = -9810;
        public int iterations = 5;
        public bool self_collision = true;
        public WorkPool pool;
        public double min_separation = 0;
        private int[] order = {};
        private int[] sew_order = {};
        private bool[] near_seam = {};
        private int[] color_start = {};
        private int colored_m = -1;
        private double[] cx = {};
        private double[] cy = {};
        private double[] cz = {};
        private int[] cc = {};
        public int contacts;

        public ParallelXpbdSolver (WorkPool? pool = null) {
            this.pool = pool ?? WorkPool.get_default ();
        }

        public override string name {
            get { return "parallel-xpbd"; }
        }

        private void color_constraints (ClothState s) {
            int m = s.m;
            var colors = new int[m];
            var used = new uint64[s.n];
            int ncolors = 0;
            int sews = 0;
            for (int c = 0; c < m; c++) if (s.kind[c] == 2) sews++;
            sew_order = new int[sews];
            sews = 0;
            for (int c = 0; c < m; c++) {
                if (s.kind[c] == 2) {
                    sew_order[sews++] = c;
                    colors[c] = -1;
                    continue;
                }
                uint64 mask = used[s.ca[c]] | used[s.cb[c]];
                int col = 0;
                while (col < 64 && (mask & ((uint64) 1 << col)) != 0) col++;
                if (col >= 64) col = 63;
                colors[c] = col;
                used[s.ca[c]] |= (uint64) 1 << col;
                used[s.cb[c]] |= (uint64) 1 << col;
                ncolors = int.max (ncolors, col + 1);
            }
            color_start = new int[ncolors + 1];
            for (int c = 0; c < m; c++) if (colors[c] >= 0) color_start[colors[c] + 1]++;
            for (int k = 0; k < ncolors; k++) color_start[k + 1] += color_start[k];
            var fill = new int[ncolors];
            order = new int[color_start[ncolors] + sews];
            for (int c = 0; c < m; c++) if (colors[c] >= 0) order[color_start[colors[c]] + fill[colors[c]]++] = c;
            for (int k = 0; k < sews; k++) order[color_start[ncolors] + k] = sew_order[k];
            mark_seams (s);
            colored_m = m;
        }

        public int color_count () {
            return color_start.length - 1;
        }

        private void solve_range (ClothState s, int from, int to, double h2) {
            for (int k = from; k < to; k++) {
                int c = order[k];
                int a = s.ca[c], b = s.cb[c];
                double wa = s.w[a], wb = s.w[b];
                double ws = wa + wb;
                if (ws == 0) continue;
                double dx = s.x[a] - s.x[b], dy = s.y[a] - s.y[b], dz = s.z[a] - s.z[b];
                double len = Math.sqrt (dx * dx + dy * dy + dz * dz);
                if (len < 1e-9) continue;
                double comp = s.compliance[c];
                if (s.kind[c] == 2) comp *= s.sew_scale;
                double alpha = comp / h2;
                double cval = len - s.rest[c];
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

        private int[] bucket_start = {};
        private int[] bucket_tris = {};
        private const int BUCKETS = 1 << 15;

        private static uint bucket_of (int ix, int iy, int iz) {
            uint h = (uint) ix * 73856093u ^ (uint) iy * 19349663u ^ (uint) iz * 83492791u;
            return h & (BUCKETS - 1);
        }

        private void build_tri_hash (ClothState s, double cell, double pad) {
            var counts = new int[BUCKETS + 1];
            var span = new int[s.nt * 6];
            for (int pass = 0; pass < 2; pass++) {
                if (pass == 1) {
                    for (int k = 0; k < BUCKETS; k++) counts[k + 1] += counts[k];
                    bucket_start = counts;
                    bucket_tris = new int[counts[BUCKETS]];
                    counts = new int[BUCKETS];
                }
                for (int t = 0; t < s.nt; t++) {
                    int x0, x1, y0, y1, z0, z1;
                    if (pass == 0) {
                        int a = s.tris[t * 3], b = s.tris[t * 3 + 1], c = s.tris[t * 3 + 2];
                        x0 = (int) Math.floor ((double.min (s.x[a], double.min (s.x[b], s.x[c])) - pad) / cell);
                        x1 = (int) Math.floor ((double.max (s.x[a], double.max (s.x[b], s.x[c])) + pad) / cell);
                        y0 = (int) Math.floor ((double.min (s.y[a], double.min (s.y[b], s.y[c])) - pad) / cell);
                        y1 = (int) Math.floor ((double.max (s.y[a], double.max (s.y[b], s.y[c])) + pad) / cell);
                        z0 = (int) Math.floor ((double.min (s.z[a], double.min (s.z[b], s.z[c])) - pad) / cell);
                        z1 = (int) Math.floor ((double.max (s.z[a], double.max (s.z[b], s.z[c])) + pad) / cell);
                        span[t * 6] = x0; span[t * 6 + 1] = x1; span[t * 6 + 2] = y0; span[t * 6 + 3] = y1; span[t * 6 + 4] = z0; span[t * 6 + 5] = z1;
                    } else {
                        x0 = span[t * 6]; x1 = span[t * 6 + 1]; y0 = span[t * 6 + 2]; y1 = span[t * 6 + 3]; z0 = span[t * 6 + 4]; z1 = span[t * 6 + 5];
                    }
                    if ((x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1) > 27) continue;
                    for (int ix = x0; ix <= x1; ix++) for (int iy = y0; iy <= y1; iy++) for (int iz = z0; iz <= z1; iz++) {
                        uint k = bucket_of (ix, iy, iz);
                        if (pass == 0) counts[k + 1]++;
                        else bucket_tris[bucket_start[k] + counts[k]++] = t;
                    }
                }
            }
        }

        private static Vec3 closest_on_triangle (Vec3 p, Vec3 a, Vec3 b, Vec3 c) {
            var ab = b.sub (a);
            var ac = c.sub (a);
            var ap = p.sub (a);
            double d1 = ab.dot (ap), d2 = ac.dot (ap);
            if (d1 <= 0 && d2 <= 0) return a;
            var bp = p.sub (b);
            double d3 = ab.dot (bp), d4 = ac.dot (bp);
            if (d3 >= 0 && d4 <= d3) return b;
            double vc = d1 * d4 - d3 * d2;
            if (vc <= 0 && d1 >= 0 && d3 <= 0) return a.add (ab.scale (d1 / (d1 - d3)));
            var cp = p.sub (c);
            double d5 = ab.dot (cp), d6 = ac.dot (cp);
            if (d6 >= 0 && d5 <= d6) return c;
            double vb = d5 * d2 - d1 * d6;
            if (vb <= 0 && d2 >= 0 && d6 <= 0) return a.add (ac.scale (d2 / (d2 - d6)));
            double va = d3 * d6 - d5 * d4;
            if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) return b.add (c.sub (b).scale ((d4 - d3) / ((d4 - d3) + (d5 - d6))));
            double denom = 1 / (va + vb + vc);
            return a.add (ab.scale (vb * denom)).add (ac.scale (vc * denom));
        }

        private void mark_seams (ClothState s) {
            near_seam = new bool[s.n];
            var sewn = new bool[s.n];
            foreach (int c in sew_order) {
                sewn[s.ca[c]] = true;
                sewn[s.cb[c]] = true;
            }
            double r2 = (s.spacing * 2.5) * (s.spacing * 2.5);
            bool grouped = s.group.length == s.n;
            for (int j = 0; j < s.n; j++) {
                if (!sewn[j]) continue;
                for (int i = 0; i < s.n; i++) {
                    if (near_seam[i]) continue;
                    if (grouped && s.group[i] != s.group[j]) continue;
                    double du = s.u[i] - s.u[j], dv = s.v[i] - s.v[j];
                    if (du * du + dv * dv < r2) near_seam[i] = true;
                }
            }
        }

        private bool neighbor (ClothState s, int i, int j) {
            if (i == j) return true;
            if (near_seam.length == s.n && near_seam[i] && near_seam[j]) return true;
            if (s.group.length != s.n) return false;
            if (s.group[i] != s.group[j]) return false;
            double du = s.u[i] - s.u[j], dv = s.v[i] - s.v[j];
            return du * du + dv * dv < (s.spacing * 2.5) * (s.spacing * 2.5);
        }

        private void self_collide_range (ClothState s, int from, int to, double cell, double d, double reach) {
            for (int i = from; i < to; i++) {
                cx[i] = 0;
                cy[i] = 0;
                cz[i] = 0;
                cc[i] = 0;
                if (s.w[i] == 0) continue;
                var p = Vec3 (s.x[i], s.y[i], s.z[i]);
                uint k = bucket_of ((int) Math.floor (p.x / cell), (int) Math.floor (p.y / cell), (int) Math.floor (p.z / cell));
                var pp = Vec3 (s.px[i], s.py[i], s.pz[i]);
                for (int e = bucket_start[k]; e < bucket_start[k + 1]; e++) {
                    int t = bucket_tris[e];
                    int a = s.tris[t * 3], b = s.tris[t * 3 + 1], c = s.tris[t * 3 + 2];
                    if (neighbor (s, i, a) || neighbor (s, i, b) || neighbor (s, i, c)) continue;
                    var va = Vec3 (s.x[a], s.y[a], s.z[a]);
                    var vb = Vec3 (s.x[b], s.y[b], s.z[b]);
                    var vc = Vec3 (s.x[c], s.y[c], s.z[c]);
                    var q = closest_on_triangle (p, va, vb, vc);
                    var diff = p.sub (q);
                    double dist = diff.length ();
                    if (dist >= reach) continue;
                    var nrm = vb.sub (va).cross (vc.sub (va));
                    double nl = nrm.length ();
                    if (nl < 1e-12) continue;
                    nrm = nrm.scale (1 / nl);
                    var pa = Vec3 (s.px[a], s.py[a], s.pz[a]);
                    var pn = Vec3 (s.px[b], s.py[b], s.pz[b]).sub (pa).cross (Vec3 (s.px[c], s.py[c], s.pz[c]).sub (pa));
                    double side_prev = pp.sub (pa).dot (pn);
                    double side_now = p.sub (va).dot (nrm);
                    bool crossed = side_prev != 0 && ((side_prev > 0) != (side_now > 0));
                    if (!crossed && dist >= d) continue;
                    var proj = p.sub (nrm.scale (side_now));
                    double off_face = closest_on_triangle (proj, va, vb, vc).distance (proj);
                    if (crossed && off_face > d) continue;
                    Vec3 dir;
                    double push;
                    if (!crossed && off_face > 1e-6 * double.max (1, s.spacing)) {
                        if (dist < 1e-9) continue;
                        dir = diff.scale (1 / dist);
                        push = d - dist;
                    } else {
                        dir = side_prev >= 0 ? nrm : nrm.scale (-1);
                        if (side_prev == 0) dir = diff.dot (nrm) >= 0 ? nrm : nrm.scale (-1);
                        push = d - p.sub (va).dot (dir);
                    }
                    if (push <= 0) continue;
                    cx[i] += dir.x * push;
                    cy[i] += dir.y * push;
                    cz[i] += dir.z * push;
                    cc[i]++;
                }
            }
        }

        public int team_grain = 1024;

        private void solve_team (ClothState s, double h2, int rounds) {
            int team = int.min (int.min (pool.size, pool.limit), s.m / int.max (1, team_grain));
            if (team <= 1) {
                for (int r = 0; r < rounds; r++) solve_colors (s, h2);
                return;
            }
            var barrier = new SpinBarrier (team);
            int ncol = color_count ();
            int sew_base = color_start[ncol];
            pool.run (team, (w, w_end) => {
                for (int r = 0; r < rounds; r++) {
                    for (int col = 0; col < ncol; col++) {
                        int base_k = color_start[col];
                        int count = color_start[col + 1] - base_k;
                        int a = (int) ((int64) count * w / team);
                        int b = (int) ((int64) count * (w + 1) / team);
                        if (a < b) solve_range (s, base_k + a, base_k + b, h2);
                        barrier.wait ();
                    }
                    if (w == 0) solve_range (s, sew_base, sew_base + sew_order.length, h2);
                    barrier.wait ();
                }
            }, 1);
        }

        private int collide_once (ClothState s, double cell, double sep, double reach) {
            build_tri_hash (s, cell, reach);
            pool.run (s.n, (a, b) => self_collide_range (s, a, b, cell, sep, reach), 32);
            int touched = 0;
            for (int i = 0; i < s.n; i++) {
                if (cc[i] == 0) continue;
                touched++;
                s.x[i] += cx[i] / cc[i];
                s.y[i] += cy[i] / cc[i];
                s.z[i] += cz[i] / cc[i];
            }
            return touched;
        }

        private void solve_colors (ClothState s, double h2) {
            for (int col = 0; col < color_count (); col++) {
                int base_k = color_start[col];
                int count = color_start[col + 1] - base_k;
                pool.run (count, (a, b) => solve_range (s, base_k + a, base_k + b, h2));
            }
            int sew_base = color_start[color_count ()];
            solve_range (s, sew_base, sew_base + sew_order.length, h2);
        }

        public bool adaptive = true;
        public int tune_period = 64;
        public int workers { get; private set; }
        private int steps;
        private int64 time_one;
        private int64 time_all;

        public override void step (ClothState s, AvatarCollider? collider, double dt, int substeps) {
            if (!adaptive || pool.size <= 1) {
                pool.limit = pool.size;
                workers = pool.size;
                step_once (s, collider, dt, substeps);
                return;
            }
            int phase = steps++ % tune_period;
            bool trial_one = phase < 2;
            bool trial_all = phase >= 2 && phase < 4;
            pool.limit = trial_one ? 1 : (trial_all ? pool.size : int.max (1, workers));
            int64 start = get_monotonic_time ();
            step_once (s, collider, dt, substeps);
            int64 spent = get_monotonic_time () - start;
            if (phase == 0) time_one = 0;
            if (trial_one) time_one += spent;
            if (phase == 2) time_all = 0;
            if (trial_all) time_all += spent;
            if (phase == 3) workers = time_all < time_one ? pool.size : 1;
        }

        private void step_once (ClothState s, AvatarCollider? collider, double dt, int substeps) {
            if (colored_m != s.m) color_constraints (s);
            if (cx.length < s.n) {
                cx = new double[s.n];
                cy = new double[s.n];
                cz = new double[s.n];
                cc = new int[s.n];
            }
            double h = dt / int.max (1, substeps);
            double h2 = h * h;
            double gs = gravity * gravity_scale;
            double sep = min_separation > 0 ? min_separation : 0;
            if (sep == 0) {
                double th = 0;
                for (int i = 0; i < s.n; i++) th = double.max (th, s.thickness[i]);
                sep = th * 2;
            }
            min_separation = sep;
            double cell = double.max (sep * 2, s.spacing * 1.5);
            contacts = 0;
            for (int sub = 0; sub < substeps; sub++) {
                pool.run (s.n, (a, b) => {
                    for (int i = a; i < b; i++) {
                        s.px[i] = s.x[i];
                        s.py[i] = s.y[i];
                        s.pz[i] = s.z[i];
                        if (s.w[i] == 0) continue;
                        s.vy[i] += gs * h;
                        s.x[i] += s.vx[i] * h;
                        s.y[i] += s.vy[i] * h;
                        s.z[i] += s.vz[i] * h;
                    }
                });
                pool.run (s.m, (a, b) => {
                    for (int c = a; c < b; c++) s.lambda[c] = 0;
                });
                solve_team (s, h2, iterations);
                if (self_collision && collide_layers && s.nt > 0) {
                    double reach = double.max (sep, s.spacing * 0.75);
                    int touched = collide_once (s, cell, sep, reach);
                    if (touched > 0) {
                        solve_team (s, h2, 1);
                        touched += collide_once (s, cell, sep, reach);
                    }
                    contacts += touched;
                }
                if (collider != null) {
                    pool.run (s.n, (a, b) => {
                        for (int pass = 0; pass < 3; pass++) {
                            for (int i = a; i < b; i++) {
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
                    });
                }
                double keep = 1 - s.damping;
                pool.run (s.n, (a, b) => {
                    for (int i = a; i < b; i++) {
                        s.vx[i] = (s.x[i] - s.px[i]) / h * keep;
                        s.vy[i] = (s.y[i] - s.py[i]) / h * keep;
                        s.vz[i] = (s.z[i] - s.pz[i]) / h * keep;
                    }
                });
            }
        }
    }
}
