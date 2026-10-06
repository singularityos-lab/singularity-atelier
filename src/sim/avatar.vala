namespace Singularity.Apps.Atelier {

    public class BodyDims {
        public double height = 1680;
        public double bust = 880;
        public double waist = 700;
        public double hip = 960;
        public double neck = 350;
        public double across_back = 350;
        public double shoulder = 125;
        public double arm = 600;
        public double upper_arm = 280;
        public double wrist = 160;
        public double inseam = 780;
        public double thigh = 560;
        public double knee = 370;
        public double ankle = 230;
        public double head = 560;
        public double back_waist = 410;
        public double waist_hip = 200;
        public double crotch = 270;
        public double bust_height = 260;

        public static BodyDims from_table (MeasurementTable table, string size) {
            var d = new BodyDims ();
            if (table.gender == "male") {
                d.height = 1800; d.bust = 1000; d.waist = 880; d.hip = 1020; d.neck = 400; d.across_back = 400;
                d.shoulder = 150; d.arm = 640; d.upper_arm = 320; d.wrist = 180; d.inseam = 820; d.thigh = 580;
                d.knee = 400; d.ankle = 250; d.head = 580; d.back_waist = 460; d.crotch = 270; d.bust_height = 250;
            }
            d.height = get (table, size, "height", d.height);
            d.bust = get (table, size, "bust_circ", d.bust);
            d.waist = get (table, size, "waist_circ", d.waist);
            d.hip = get (table, size, "hip_circ", d.hip);
            d.neck = get (table, size, "neck_circ", d.neck);
            d.across_back = get (table, size, "across_back", d.across_back);
            d.shoulder = get (table, size, "shoulder_length", d.shoulder);
            d.arm = get (table, size, "arm_length", d.arm);
            d.upper_arm = get (table, size, "upper_arm_circ", d.upper_arm);
            d.wrist = get (table, size, "wrist_circ", d.wrist);
            d.inseam = get (table, size, "inseam", d.inseam);
            d.thigh = get (table, size, "thigh_circ", d.thigh);
            d.knee = get (table, size, "knee_circ", d.knee);
            d.ankle = get (table, size, "ankle_circ", d.ankle);
            d.head = get (table, size, "head_circ", d.head);
            d.back_waist = get (table, size, "back_waist_length", d.back_waist);
            d.waist_hip = get (table, size, "waist_to_hip", d.waist_hip);
            d.crotch = get (table, size, "crotch_depth", d.crotch);
            d.bust_height = get (table, size, "bust_height", d.bust_height);
            return d;
        }

        private static double get (MeasurementTable t, string size, string name, double fallback) {
            double v;
            if (t.lookup (name, size, out v) && v > 0) return v;
            return fallback;
        }

        public double y_neck () {
            return height * 0.845;
        }

        public double y_shoulder () {
            return y_neck () - 45;
        }

        public double y_bust () {
            return double.max (y_waist () + 60, y_neck () - bust_height);
        }

        public double y_waist () {
            return y_neck () - back_waist;
        }

        public double y_hip () {
            return y_waist () - waist_hip;
        }

        public double y_crotch () {
            return double.min (inseam, y_hip () - 40);
        }

        public double y_knee () {
            return double.min (height * 0.285, y_crotch () - 120);
        }

        public double y_ankle () {
            return height * 0.045;
        }
    }

    public struct Section {
        public double y;
        public double a;
        public double b;
        public double cz;

        public Section (double y, double a, double b, double cz) {
            this.y = y;
            this.a = a;
            this.b = b;
            this.cz = cz;
        }
    }

    public class Limb {
        public Vec3 start;
        public Vec3 end;
        public double r0;
        public double r1;

        public Limb (Vec3 start, Vec3 end, double r0, double r1) {
            this.start = start;
            this.end = end;
            this.r0 = r0;
            this.r1 = r1;
        }

        public double distance (Vec3 p, out Vec3 normal) {
            var ax = end.sub (start);
            double l2 = ax.dot (ax);
            double t = l2 > 0 ? (p.sub (start).dot (ax) / l2).clamp (0, 1) : 0;
            var c = start.add (ax.scale (t));
            var d = p.sub (c);
            double len = d.length ();
            normal = len > 1e-9 ? d.scale (1 / len) : ax.any_perpendicular ();
            return len - (r0 + (r1 - r0) * t);
        }
    }

    public class AvatarModel {
        public BodyDims dims;
        public string pose;
        public Gee.ArrayList<Section?> torso = new Gee.ArrayList<Section?> ();
        public Gee.ArrayList<Limb> limbs = new Gee.ArrayList<Limb> ();
        public Vec3 head_center;
        public Vec3 head_radii;
        public double torso_bottom;
        public double torso_top;
        public Vec3 shoulder_left;
        public Vec3 shoulder_right;
        public Vec3 wrist_left;
        public Vec3 wrist_right;
        public Mesh torso_mesh;
        public Mesh mesh;

        public static double ellipse_perimeter (double a, double b) {
            double h = Math.pow ((a - b) / (a + b), 2);
            return Math.PI * (a + b) * (1 + 3 * h / (10 + Math.sqrt (4 - 3 * h)));
        }

        public static void from_girth (double girth, double aspect, out double a, out double b) {
            a = girth / ellipse_perimeter (1, aspect);
            b = a * aspect;
        }

        public Section section_at (double y) {
            int n = torso.size;
            if (y <= torso[0].y) return torso[0];
            if (y >= torso[n - 1].y) return torso[n - 1];
            int i = 0;
            while (i < n - 2 && torso[i + 1].y < y) i++;
            var p1 = torso[i];
            var p2 = torso[i + 1];
            var p0 = torso[int.max (0, i - 1)];
            var p3 = torso[int.min (n - 1, i + 2)];
            double t = (y - p1.y) / double.max (1e-9, p2.y - p1.y);
            return Section (y, cr (p0.a, p1.a, p2.a, p3.a, t), cr (p0.b, p1.b, p2.b, p3.b, t), cr (p0.cz, p1.cz, p2.cz, p3.cz, t));
        }

        private static double cr (double p0, double p1, double p2, double p3, double t) {
            double v = 0.5 * (2 * p1 + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t);
            double lo = double.min (p1, p2), hi = double.max (p1, p2);
            double pad = (hi - lo) * 0.15;
            return v.clamp (lo - pad, hi + pad);
        }
    }

    public class Avatar {
        public static Mesh build (MeasurementTable table, string size, string pose = "a-pose") {
            return model (table, size, pose).mesh;
        }

        public static AvatarModel model (MeasurementTable table, string size, string pose = "a-pose") {
            return from_dims (BodyDims.from_table (table, size), pose);
        }

        public static AvatarModel from_dims (BodyDims d, string pose) {
            var m = new AvatarModel ();
            m.dims = d;
            m.pose = pose;
            double a, b;
            double yc = d.y_crotch (), yh = d.y_hip (), yw = d.y_waist (), yb = d.y_bust (), ys = d.y_shoulder (), yn = d.y_neck ();
            AvatarModel.from_girth (d.hip * 0.9, 0.72, out a, out b);
            m.torso.add (Section (yc, a, b, -5));
            AvatarModel.from_girth (d.hip, 0.72, out a, out b);
            m.torso.add (Section (yh, a, b, -8));
            AvatarModel.from_girth (d.waist, 0.74, out a, out b);
            m.torso.add (Section (yw, a, b, 0));
            AvatarModel.from_girth (d.bust, 0.72, out a, out b);
            m.torso.add (Section (yb, a, b, 8));
            double yu = yb + (ys - yb) * 0.45;
            AvatarModel.from_girth (d.bust * 0.96, 0.66, out a, out b);
            m.torso.add (Section (yu, a, b, 2));
            double sa = d.across_back / 2 + 18;
            m.torso.add (Section (ys - 18, sa, sa * 0.5, -6));
            m.torso.add (Section (ys + 8, sa - 12, sa * 0.36, -10));
            AvatarModel.from_girth (d.neck * 0.9, 0.88, out a, out b);
            m.torso.add (Section (yn, a, b, -18));
            AvatarModel.from_girth (d.neck * 0.92, 0.9, out a, out b);
            m.torso.add (Section (yn + 75, a, b, -8));
            m.torso_bottom = yc;
            m.torso_top = yn + 75;

            double head_bottom = yn + 60;
            double head_h = d.height - head_bottom;
            AvatarModel.from_girth (d.head, 1.18, out a, out b);
            m.head_center = Vec3 (0, head_bottom + head_h / 2, 5);
            m.head_radii = Vec3 (a, head_h / 2, b);

            double ang = pose == "t-pose" ? 88.0 : 42.0;
            double rad = ang * Math.PI / 180;
            double r_ua = d.upper_arm / (2 * Math.PI);
            double r_wr = d.wrist / (2 * Math.PI);
            double r_el = (r_ua + r_wr) / 2 * 0.95;
            for (int side = -1; side <= 1; side += 2) {
                var sh = Vec3 (side * (d.across_back / 2 + 8), ys - 40, -4);
                var dir = Vec3 (side * Math.sin (rad), -Math.cos (rad), 0);
                var el = sh.add (dir.scale (d.arm * 0.46));
                var wr = sh.add (dir.scale (d.arm));
                var hand = wr.add (dir.scale (d.height * 0.1));
                m.limbs.add (new Limb (sh, el, r_ua, r_el));
                m.limbs.add (new Limb (el, wr, r_el, r_wr));
                m.limbs.add (new Limb (wr, hand, r_wr * 1.05, r_wr * 0.75));
                if (side < 0) {
                    m.shoulder_left = sh;
                    m.wrist_left = wr;
                } else {
                    m.shoulder_right = sh;
                    m.wrist_right = wr;
                }
                AvatarModel.from_girth (d.hip, 0.72, out a, out b);
                double r_th = d.thigh / (2 * Math.PI);
                double r_kn = d.knee / (2 * Math.PI);
                double r_an = d.ankle / (2 * Math.PI);
                double lx = side * double.max (a * 0.46, r_th * 0.95);
                var hip_j = Vec3 (lx, yc + r_th * 0.6, -4);
                var knee = Vec3 (lx * 0.85, d.y_knee (), 0);
                var ankle = Vec3 (lx * 0.8, d.y_ankle () + r_an, 0);
                var toe = Vec3 (lx * 0.8, r_an * 0.8, d.height * 0.14);
                m.limbs.add (new Limb (hip_j, knee, r_th, r_kn));
                m.limbs.add (new Limb (knee, ankle, r_kn, r_an));
                m.limbs.add (new Limb (ankle.add (Vec3 (0, -r_an * 0.4, -r_an)), toe, r_an * 1.05, r_an * 0.8));
            }
            build_mesh (m);
            return m;
        }

        private static void build_mesh (AvatarModel m) {
            int seg = 48;
            var torso = new Mesh ();
            torso.name = "torso";
            var ys = new Gee.ArrayList<double?> ();
            for (double y = m.torso_bottom; y < m.torso_top; y += 20) ys.add (y);
            foreach (var s in m.torso) ys.add (s.y);
            ys.add (m.torso_top);
            ys.sort ((x, y) => x < y ? -1 : (x > y ? 1 : 0));
            var uniq = new Gee.ArrayList<double?> ();
            foreach (var y in ys) if (uniq.size == 0 || y - uniq[uniq.size - 1] > 0.5) uniq.add (y);
            foreach (var y in uniq) {
                var s = m.section_at (y);
                for (int k = 0; k < seg; k++) {
                    double t = 2 * Math.PI * k / seg;
                    torso.add_vertex (Vec3 (s.a * Math.cos (t), y, s.cz + s.b * Math.sin (t)));
                }
            }
            int rings = uniq.size;
            for (int r = 0; r < rings - 1; r++) {
                for (int k = 0; k < seg; k++) {
                    int a0 = r * seg + k, a1 = r * seg + (k + 1) % seg;
                    int b0 = a0 + seg, b1 = a1 + seg;
                    torso.add_triangle (a0, b0, a1);
                    torso.add_triangle (a1, b0, b1);
                }
            }
            var s0 = m.section_at (m.torso_bottom);
            int bottom = torso.add_vertex (Vec3 (0, m.torso_bottom - 10, s0.cz));
            for (int k = 0; k < seg; k++) torso.add_triangle (bottom, k, (k + 1) % seg);
            var st = m.section_at (m.torso_top);
            int top = torso.add_vertex (Vec3 (0, m.torso_top, st.cz));
            int last = (rings - 1) * seg;
            for (int k = 0; k < seg; k++) torso.add_triangle (top, last + (k + 1) % seg, last + k);
            torso.compute_normals ();
            m.torso_mesh = torso;

            var all = torso.copy ();
            all.name = "avatar";
            all.append (ellipsoid (m.head_center, m.head_radii, 24, 16));
            foreach (var l in m.limbs) {
                all.append (tube (l.start, l.end, l.r0, l.r1, 20, 6));
                all.append (ellipsoid (l.start, Vec3 (l.r0, l.r0, l.r0), 12, 8));
                all.append (ellipsoid (l.end, Vec3 (l.r1, l.r1, l.r1), 12, 8));
            }
            all.compute_normals ();
            all.color = Rgba (0.82, 0.8, 0.78, 1);
            all.roughness = 0.6;
            all.material = "avatar";
            m.mesh = all;
        }

        public static Mesh ellipsoid (Vec3 c, Vec3 r, int slices, int stacks) {
            var m = new Mesh ();
            for (int i = 0; i <= stacks; i++) {
                double phi = Math.PI * i / stacks - Math.PI / 2;
                for (int j = 0; j < slices; j++) {
                    double th = 2 * Math.PI * j / slices;
                    m.add_vertex (Vec3 (c.x + r.x * Math.cos (phi) * Math.cos (th), c.y + r.y * Math.sin (phi), c.z + r.z * Math.cos (phi) * Math.sin (th)));
                }
            }
            for (int i = 0; i < stacks; i++) {
                for (int j = 0; j < slices; j++) {
                    int a0 = i * slices + j, a1 = i * slices + (j + 1) % slices;
                    m.add_triangle (a0, a1, a0 + slices);
                    m.add_triangle (a1, a1 + slices, a0 + slices);
                }
            }
            m.compute_normals ();
            return m;
        }

        public static Mesh tube (Vec3 a, Vec3 b, double r0, double r1, int slices, int rings) {
            var m = new Mesh ();
            var ax = b.sub (a).normalized ();
            var u = ax.any_perpendicular ();
            var w = ax.cross (u).normalized ();
            for (int i = 0; i <= rings; i++) {
                double t = (double) i / rings;
                var c = a.lerp (b, t);
                double r = r0 + (r1 - r0) * t;
                for (int j = 0; j < slices; j++) {
                    double th = 2 * Math.PI * j / slices;
                    m.add_vertex (c.add (u.scale (r * Math.cos (th))).add (w.scale (r * Math.sin (th))));
                }
            }
            for (int i = 0; i < rings; i++) {
                for (int j = 0; j < slices; j++) {
                    int a0 = i * slices + j, a1 = i * slices + (j + 1) % slices;
                    m.add_triangle (a0, a1, a0 + slices);
                    m.add_triangle (a1, a1 + slices, a0 + slices);
                }
            }
            m.compute_normals ();
            return m;
        }
    }

    public class AvatarCollider {
        private AvatarModel model;
        private double y0;
        private double step = 2;
        private double[] ta = {};
        private double[] tb = {};
        private double[] tcz = {};
        private double[] ls = {};
        private int nl;
        private double hx;
        private double hy;
        private double hz;
        private double hrx;
        private double hry;
        private double hrz;
        private double bottom;
        private double top;

        public AvatarCollider (AvatarModel model) {
            this.model = model;
            bottom = model.torso_bottom;
            top = model.torso_top;
            y0 = bottom;
            int n = (int) Math.ceil ((top - bottom) / step) + 1;
            ta = new double[n];
            tb = new double[n];
            tcz = new double[n];
            for (int i = 0; i < n; i++) {
                var sec = model.section_at (y0 + i * step);
                ta[i] = sec.a;
                tb[i] = sec.b;
                tcz[i] = sec.cz;
            }
            nl = model.limbs.size;
            ls = new double[nl * 12];
            for (int i = 0; i < nl; i++) {
                var l = model.limbs[i];
                var ax = l.end.sub (l.start);
                var mid = l.start.add (l.end).scale (0.5);
                double[] v = { l.start.x, l.start.y, l.start.z, ax.x, ax.y, ax.z, ax.dot (ax), l.r0, l.r1, mid.x, mid.y, mid.z };
                for (int k = 0; k < 12; k++) ls[i * 12 + k] = v[k];
            }
            hx = model.head_center.x;
            hy = model.head_center.y;
            hz = model.head_center.z;
            hrx = model.head_radii.x;
            hry = model.head_radii.y;
            hrz = model.head_radii.z;
        }

        public double distance (Vec3 p, out Vec3 normal) {
            double nx, ny, nz;
            double best = torso_distance (p.x, p.y, p.z, out nx, out ny, out nz);
            for (int i = 0; i < nl; i++) {
                int o = i * 12;
                double r1 = ls[o + 8], r0 = ls[o + 7];
                double mx = p.x - ls[o + 9], my = p.y - ls[o + 10], mz = p.z - ls[o + 11];
                double half = Math.sqrt (ls[o + 6]) / 2;
                double quick = Math.sqrt (mx * mx + my * my + mz * mz) - half - double.max (r0, r1);
                if (quick > best) continue;
                double dx = p.x - ls[o], dy = p.y - ls[o + 1], dz = p.z - ls[o + 2];
                double l2 = ls[o + 6];
                double t = l2 > 0 ? ((dx * ls[o + 3] + dy * ls[o + 4] + dz * ls[o + 5]) / l2).clamp (0, 1) : 0;
                double qx = dx - ls[o + 3] * t, qy = dy - ls[o + 4] * t, qz = dz - ls[o + 5] * t;
                double len = Math.sqrt (qx * qx + qy * qy + qz * qz);
                double d = len - (r0 + (r1 - r0) * t);
                if (d < best) {
                    best = d;
                    if (len > 1e-9) {
                        nx = qx / len;
                        ny = qy / len;
                        nz = qz / len;
                    } else {
                        nx = 1;
                        ny = 0;
                        nz = 0;
                    }
                }
            }
            double qx = p.x - hx, qy = p.y - hy, qz = p.z - hz;
            double k0 = Math.sqrt ((qx / hrx) * (qx / hrx) + (qy / hry) * (qy / hry) + (qz / hrz) * (qz / hrz));
            double gx = qx / (hrx * hrx), gy = qy / (hry * hry), gz = qz / (hrz * hrz);
            double k1 = Math.sqrt (gx * gx + gy * gy + gz * gz);
            double hd = k1 > 1e-12 ? k0 * (k0 - 1) / k1 : -hrx;
            if (hd < best) {
                best = hd;
                nx = gx / k1;
                ny = gy / k1;
                nz = gz / k1;
            }
            normal = Vec3 (nx, ny, nz);
            return best;
        }

        private double torso_distance (double x, double y, double z, out double nx, out double ny, out double nz) {
            double fi = ((y - y0) / step).clamp (0, ta.length - 1);
            int i = (int) fi;
            int j = int.min (i + 1, ta.length - 1);
            double f = fi - i;
            double a = ta[i] + (ta[j] - ta[i]) * f;
            double b = tb[i] + (tb[j] - tb[i]) * f;
            double cz = tcz[i] + (tcz[j] - tcz[i]) * f;
            double dx = x, dz = z - cz;
            double k0 = Math.sqrt ((dx / a) * (dx / a) + (dz / b) * (dz / b));
            double gx = dx / (a * a), gz = dz / (b * b);
            double k1 = Math.sqrt (gx * gx + gz * gz);
            double d = k1 > 1e-12 ? k0 * (k0 - 1) / k1 : -double.min (a, b);
            if (k1 > 1e-12) {
                nx = gx / k1;
                ny = 0;
                nz = gz / k1;
            } else {
                nx = 0;
                ny = 0;
                nz = 1;
            }
            double below = bottom - y;
            double above = y - top;
            if (below > d && below >= above) {
                nx = 0;
                ny = -1;
                nz = 0;
                return below;
            }
            if (above > d) {
                nx = 0;
                ny = 1;
                nz = 0;
                return above;
            }
            return d;
        }
    }
}
