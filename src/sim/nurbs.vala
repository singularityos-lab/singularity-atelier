namespace Singularity.Apps.Atelier {

    public class NurbsCurve {
        public int degree;
        public Gee.ArrayList<Vec3?> ctrl = new Gee.ArrayList<Vec3?> ();
        public Gee.ArrayList<double?> weights = new Gee.ArrayList<double?> ();
        public double[] knots = {};

        public NurbsCurve (int degree) {
            this.degree = degree;
        }

        public static NurbsCurve through (Gee.List<Vec3?> pts, int degree = 3) {
            var c = new NurbsCurve (int.min (degree, pts.size - 1));
            foreach (var p in pts) {
                c.ctrl.add (p);
                c.weights.add (1.0);
            }
            c.clamp_uniform ();
            return c;
        }

        public void clamp_uniform () {
            int n = ctrl.size;
            int m = n + degree + 1;
            knots = new double[m];
            for (int i = 0; i < m; i++) {
                if (i <= degree) knots[i] = 0;
                else if (i >= n) knots[i] = 1;
                else knots[i] = (double) (i - degree) / (n - degree);
            }
        }

        public static NurbsCurve circle (Vec3 center, double r, Vec3 u, Vec3 v) {
            var c = new NurbsCurve (2);
            double w = Math.sqrt (0.5);
            double[,] pts = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 }, { 1, 0 } };
            for (int i = 0; i < 9; i++) {
                c.ctrl.add (center.add (u.scale (pts[i, 0] * r)).add (v.scale (pts[i, 1] * r)));
                c.weights.add (i % 2 == 1 ? w : 1.0);
            }
            c.knots = { 0, 0, 0, 0.25, 0.25, 0.5, 0.5, 0.75, 0.75, 1, 1, 1 };
            return c;
        }

        private int span (double t) {
            int n = ctrl.size - 1;
            if (t >= knots[n + 1]) return n;
            if (t <= knots[degree]) return degree;
            int lo = degree, hi = n + 1;
            int mid = (lo + hi) / 2;
            while (t < knots[mid] || t >= knots[mid + 1]) {
                if (t < knots[mid]) hi = mid;
                else lo = mid;
                mid = (lo + hi) / 2;
            }
            return mid;
        }

        public Vec3 eval (double t) {
            t = t.clamp (0, 1);
            int k = span (t);
            var d = new double[degree + 1, 4];
            for (int j = 0; j <= degree; j++) {
                int i = k - degree + j;
                var p = ctrl[i];
                double w = weights[i];
                d[j, 0] = p.x * w;
                d[j, 1] = p.y * w;
                d[j, 2] = p.z * w;
                d[j, 3] = w;
            }
            for (int r = 1; r <= degree; r++) {
                for (int j = degree; j >= r; j--) {
                    int i = k - degree + j;
                    double den = knots[i + degree - r + 1] - knots[i];
                    double a = den.abs () < 1e-12 ? 0 : (t - knots[i]) / den;
                    for (int c = 0; c < 4; c++) d[j, c] = (1 - a) * d[j - 1, c] + a * d[j, c];
                }
            }
            double wt = d[degree, 3];
            return Vec3 (d[degree, 0] / wt, d[degree, 1] / wt, d[degree, 2] / wt);
        }

        public Vec3 derivative (double t, double h = 1e-4) {
            double a = (t - h).clamp (0, 1), b = (t + h).clamp (0, 1);
            return eval (b).sub (eval (a)).scale (1 / (b - a));
        }

        public double curvature (double t, double h = 1e-3) {
            double a = (t - h).clamp (0, 1), b = (t + h).clamp (0, 1);
            double m = (a + b) / 2;
            var p0 = eval (a);
            var p1 = eval (m);
            var p2 = eval (b);
            double la = p0.distance (p1), lb = p1.distance (p2), lc = p0.distance (p2);
            if (la < 1e-12 || lb < 1e-12 || lc < 1e-12) return 0;
            double area = p1.sub (p0).cross (p2.sub (p0)).length () / 2;
            return 4 * area / (la * lb * lc);
        }

        public Gee.ArrayList<Vec3?> sample (int n) {
            var r = new Gee.ArrayList<Vec3?> ();
            for (int i = 0; i <= n; i++) r.add (eval ((double) i / n));
            return r;
        }

        public double length (int n = 400) {
            double l = 0;
            var prev = eval (0);
            for (int i = 1; i <= n; i++) {
                var p = eval ((double) i / n);
                l += p.distance (prev);
                prev = p;
            }
            return l;
        }

        public Mesh comb (int n, double scale) {
            var m = new Mesh ();
            m.name = "curvature comb";
            for (int i = 0; i <= n; i++) {
                double t = (double) i / n;
                var p = eval (t);
                var d = derivative (t).normalized ();
                var p2 = eval ((t + 0.01).clamp (0, 1));
                var p0 = eval ((t - 0.01).clamp (0, 1));
                var bend = p2.add (p0).scale (0.5).sub (p);
                var nrm = bend.sub (d.scale (bend.dot (d)));
                if (nrm.length () < 1e-12) nrm = Vec3 (0, 0, 0);
                else nrm = nrm.normalized ();
                double k = curvature (t);
                m.vertices.add (p);
                m.vertices.add (p.sub (nrm.scale (k * scale)));
                m.add_line (m.vertices.size - 2, m.vertices.size - 1);
            }
            return m;
        }
    }

    public enum Continuity {
        NONE,
        G0,
        G1,
        G2;

        public string label () {
            switch (this) {
                case G0: return _("Touching (G0)");
                case G1: return _("Tangent (G1)");
                case G2: return _("Curvature Continuous (G2)");
                default: return _("Not Connected");
            }
        }
    }

    public class ContinuityCheck {
        public static Continuity between (NurbsCurve a, NurbsCurve b, double pos_tol = 0.05, double ang_tol = 0.5, double curv_tol = 0.05) {
            var pa = a.eval (1);
            var pb = b.eval (0);
            if (pa.distance (pb) > pos_tol) return Continuity.NONE;
            var ta = a.derivative (1).normalized ();
            var tb = b.derivative (0).normalized ();
            double ang = Math.acos (ta.dot (tb).clamp (-1, 1)) * 180 / Math.PI;
            if (ang > ang_tol) return Continuity.G0;
            double ka = a.curvature (1 - 1e-3), kb = b.curvature (1e-3);
            double ref_k = double.max (double.max (ka, kb), 1e-9);
            if ((ka - kb).abs () / ref_k > curv_tol && (ka - kb).abs () > 1e-6) return Continuity.G1;
            return Continuity.G2;
        }
    }

    public class NurbsSurface {
        public string name = "";
        public int degree_u;
        public int degree_v;
        public int count_u;
        public int count_v;
        public Vec3[] ctrl = {};
        public double[] weights = {};
        public double[] knots_u = {};
        public double[] knots_v = {};

        public NurbsSurface (int degree_u, int degree_v, int count_u, int count_v) {
            this.degree_u = degree_u;
            this.degree_v = degree_v;
            this.count_u = count_u;
            this.count_v = count_v;
            ctrl = new Vec3[count_u * count_v];
            weights = new double[count_u * count_v];
            for (int i = 0; i < weights.length; i++) weights[i] = 1;
        }

        public Vec3 point (int i, int j) {
            return ctrl[i * count_v + j];
        }

        public double weight (int i, int j) {
            return weights[i * count_v + j];
        }

        public void set_point (int i, int j, Vec3 p, double w = 1) {
            ctrl[i * count_v + j] = p;
            weights[i * count_v + j] = w;
        }

        public static double[] clamped_knots (int count, int degree) {
            int m = count + degree + 1;
            var k = new double[m];
            for (int i = 0; i < m; i++) {
                if (i <= degree) k[i] = 0;
                else if (i >= count) k[i] = 1;
                else k[i] = (double) (i - degree) / (count - degree);
            }
            return k;
        }

        public static int find_span (double[] knots, int degree, int count, double t) {
            int n = count - 1;
            if (t >= knots[n + 1]) return n;
            if (t <= knots[degree]) return degree;
            int lo = degree, hi = n + 1;
            int mid = (lo + hi) / 2;
            while (t < knots[mid] || t >= knots[mid + 1]) {
                if (t < knots[mid]) hi = mid;
                else lo = mid;
                mid = (lo + hi) / 2;
            }
            return mid;
        }

        public static double[] basis (double[] knots, int degree, int span, double t) {
            var nb = new double[degree + 1];
            var left = new double[degree + 1];
            var right = new double[degree + 1];
            nb[0] = 1;
            for (int j = 1; j <= degree; j++) {
                left[j] = t - knots[span + 1 - j];
                right[j] = knots[span + j] - t;
                double saved = 0;
                for (int r = 0; r < j; r++) {
                    double den = right[r + 1] + left[j - r];
                    double tmp = den.abs () < 1e-14 ? 0 : nb[r] / den;
                    nb[r] = saved + right[r + 1] * tmp;
                    saved = left[j - r] * tmp;
                }
                nb[j] = saved;
            }
            return nb;
        }

        public Vec3 eval (double u, double v) {
            u = u.clamp (knots_u[degree_u], knots_u[count_u]);
            v = v.clamp (knots_v[degree_v], knots_v[count_v]);
            int su = find_span (knots_u, degree_u, count_u, u);
            int sv = find_span (knots_v, degree_v, count_v, v);
            var bu = basis (knots_u, degree_u, su, u);
            var bv = basis (knots_v, degree_v, sv, v);
            double x = 0, y = 0, z = 0, w = 0;
            for (int a = 0; a <= degree_u; a++) {
                int i = su - degree_u + a;
                for (int b = 0; b <= degree_v; b++) {
                    int j = sv - degree_v + b;
                    double f = bu[a] * bv[b] * weight (i, j);
                    var p = point (i, j);
                    x += p.x * f;
                    y += p.y * f;
                    z += p.z * f;
                    w += f;
                }
            }
            return Vec3 (x / w, y / w, z / w);
        }

        public bool is_rational () {
            foreach (var w in weights) if ((w - 1).abs () > 1e-12) return true;
            return false;
        }

        public Mesh to_mesh (int steps_u = 48, int steps_v = 32) {
            var m = new Mesh ();
            m.name = name != "" ? name : "surface";
            double u0 = knots_u[degree_u], u1 = knots_u[count_u];
            double v0 = knots_v[degree_v], v1 = knots_v[count_v];
            for (int a = 0; a <= steps_u; a++) {
                for (int b = 0; b <= steps_v; b++) {
                    double u = u0 + (u1 - u0) * a / steps_u, v = v0 + (v1 - v0) * b / steps_v;
                    m.add_vertex (eval (u, v));
                    m.uvs.add ((double) a / steps_u);
                    m.uvs.add ((double) b / steps_v);
                }
            }
            int row = steps_v + 1;
            for (int a = 0; a < steps_u; a++) {
                for (int b = 0; b < steps_v; b++) {
                    int p0 = a * row + b, p1 = (a + 1) * row + b;
                    m.add_triangle (p0, p1, p0 + 1);
                    m.add_triangle (p0 + 1, p1, p1 + 1);
                }
            }
            m.compute_normals ();
            return m;
        }

        public static NurbsSurface revolve (NurbsCurve profile) {
            var circle = NurbsCurve.circle (Vec3 (0, 0, 0), 1, Vec3 (1, 0, 0), Vec3 (0, 0, 1));
            int nv = profile.ctrl.size;
            var s = new NurbsSurface (2, profile.degree, circle.ctrl.size, nv);
            s.knots_u = circle.knots;
            s.knots_v = profile.knots;
            for (int i = 0; i < circle.ctrl.size; i++) {
                var c = circle.ctrl[i];
                for (int j = 0; j < nv; j++) {
                    var p = profile.ctrl[j];
                    double r = p.x;
                    s.set_point (i, j, Vec3 (c.x * r, p.y, c.z * r), circle.weights[i] * profile.weights[j]);
                }
            }
            s.name = "revolve";
            return s;
        }

        public static NurbsSurface extrude (NurbsCurve profile, Vec3 offset) {
            int nu = profile.ctrl.size;
            var s = new NurbsSurface (profile.degree, 1, nu, 2);
            s.knots_u = profile.knots;
            s.knots_v = { 0, 0, 1, 1 };
            for (int i = 0; i < nu; i++) {
                s.set_point (i, 0, profile.ctrl[i], profile.weights[i]);
                s.set_point (i, 1, profile.ctrl[i].add (offset), profile.weights[i]);
            }
            s.name = "extrude";
            return s;
        }

        public static NurbsSurface? loft (Gee.List<NurbsCurve> sections) {
            if (sections.size < 2) return null;
            int nu = sections[0].ctrl.size;
            int deg = sections[0].degree;
            foreach (var c in sections) if (c.ctrl.size != nu || c.degree != deg) return null;
            int nv = sections.size;
            int dv = int.min (3, nv - 1);
            var s = new NurbsSurface (deg, dv, nu, nv);
            s.knots_u = sections[0].knots;
            s.knots_v = clamped_knots (nv, dv);
            for (int j = 0; j < nv; j++) for (int i = 0; i < nu; i++) s.set_point (i, j, sections[j].ctrl[i], sections[j].weights[i]);
            s.name = "loft";
            return s;
        }

        public static NurbsSurface sweep_circle (NurbsCurve path, double radius) {
            var circle = NurbsCurve.circle (Vec3 (0, 0, 0), radius, Vec3 (1, 0, 0), Vec3 (0, 1, 0));
            int nv = path.ctrl.size;
            var s = new NurbsSurface (2, path.degree, circle.ctrl.size, nv);
            s.knots_u = circle.knots;
            s.knots_v = path.knots;
            var up = Vec3 (0, 1, 0);
            for (int j = 0; j < nv; j++) {
                var t = j + 1 < nv ? path.ctrl[j + 1].sub (path.ctrl[j]) : path.ctrl[j].sub (path.ctrl[j - 1]);
                if (j > 0 && j + 1 < nv) t = path.ctrl[j + 1].sub (path.ctrl[j - 1]);
                t = t.normalized ();
                var nrm = up.sub (t.scale (up.dot (t)));
                if (nrm.length () < 1e-6) nrm = t.any_perpendicular ();
                nrm = nrm.normalized ();
                var bin = t.cross (nrm).normalized ();
                for (int i = 0; i < circle.ctrl.size; i++) {
                    var c = circle.ctrl[i];
                    s.set_point (i, j, path.ctrl[j].add (bin.scale (c.x)).add (nrm.scale (c.y)), circle.weights[i] * path.weights[j]);
                }
            }
            s.name = "sweep";
            return s;
        }
    }
}
