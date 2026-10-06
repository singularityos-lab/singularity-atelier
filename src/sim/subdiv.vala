namespace Singularity.Apps.Atelier {

    public class PlaneCurve {
        public string plane = "xy";
        public double offset;
        public Gee.ArrayList<double?> points = new Gee.ArrayList<double?> ();
        public bool closed;
        public NurbsCurve? exact;

        public PlaneCurve (string plane, double offset) {
            this.plane = plane;
            this.offset = offset;
        }

        public void add (double a, double b) {
            points.add (a);
            points.add (b);
        }

        public int count () {
            return points.size / 2;
        }

        public Vec3 point3d (int i) {
            return to3d (plane, offset, points[i * 2], points[i * 2 + 1]);
        }

        public NurbsCurve to_nurbs_2d (int max_points, bool sampled = false) {
            if (exact != null && !sampled) return exact;
            int n = count ();
            var list = new Gee.ArrayList<Vec3?> ();
            int want = sampled ? max_points : int.min (n, max_points);
            for (int i = 0; i < want; i++) {
                double t = want == 1 ? 0 : (double) i / (want - 1) * (n - 1);
                int k = int.min ((int) Math.floor (t), n - 1);
                int k2 = int.min (k + 1, n - 1);
                double f = t - k;
                list.add (Vec3 (points[k * 2] * (1 - f) + points[k2 * 2] * f, points[k * 2 + 1] * (1 - f) + points[k2 * 2 + 1] * f, 0));
            }
            return NurbsCurve.through (list, 3);
        }

        public NurbsCurve to_nurbs (int max_points, bool sampled = false) {
            var flat = to_nurbs_2d (max_points, sampled);
            var c = new NurbsCurve (flat.degree);
            foreach (var p in flat.ctrl) c.ctrl.add (to3d (plane, offset, p.x, p.y));
            foreach (var w in flat.weights) c.weights.add (w);
            c.knots = flat.knots;
            return c;
        }

        public Vec3 normal () {
            return to3d (plane, 1, 0, 0).sub (to3d (plane, 0, 0, 0));
        }

        public static Vec3 to3d (string plane, double offset, double a, double b) {
            switch (plane) {
                case "yz": return Vec3 (offset, b, a);
                case "xz": return Vec3 (a, offset, b);
                default: return Vec3 (a, b, offset);
            }
        }
    }

    public class ProductModel {
        public Mesh cage = new Mesh ();
        public Gee.ArrayList<Gee.ArrayList<int>> faces = new Gee.ArrayList<Gee.ArrayList<int>> ();
        public Gee.HashSet<string> creases = new Gee.HashSet<string> ();
        public int levels = 2;
        public string material = "plastic";
        public Gee.ArrayList<PlaneCurve> sketches = new Gee.ArrayList<PlaneCurve> ();
        public Gee.ArrayList<Mesh> surfaces = new Gee.ArrayList<Mesh> ();
        public Gee.ArrayList<NurbsSurface> nurbs = new Gee.ArrayList<NurbsSurface> ();

        public Gee.ArrayList<NurbsCurve> curves () {
            var list = new Gee.ArrayList<NurbsCurve> ();
            foreach (var c in sketches) if (c.count () >= 2 || c.exact != null) list.add (c.to_nurbs (60));
            return list;
        }

        public const string[] MATERIALS = { "leather", "metal", "plastic", "paint", "fabric" };

        public static string material_label (string id) {
            switch (id) {
                case "leather": return _("Leather");
                case "metal": return _("Brushed Metal");
                case "paint": return _("Car Paint");
                case "fabric": return _("Fabric");
                default: return _("Plastic");
            }
        }

        public static void apply_material (Mesh m, string id) {
            m.material = id;
            switch (id) {
                case "leather":
                    m.color = Rgba (0.42, 0.25, 0.14, 1);
                    m.roughness = 0.5;
                    m.metallic = 0;
                    break;
                case "metal":
                    m.color = Rgba (0.78, 0.78, 0.8, 1);
                    m.roughness = 0.3;
                    m.metallic = 1;
                    break;
                case "paint":
                    m.color = Rgba (0.7, 0.08, 0.1, 1);
                    m.roughness = 0.12;
                    m.metallic = 0.3;
                    break;
                case "fabric":
                    m.color = Rgba (0.3, 0.36, 0.48, 1);
                    m.roughness = 0.95;
                    m.metallic = 0;
                    break;
                default:
                    m.color = Rgba (0.9, 0.9, 0.88, 1);
                    m.roughness = 0.4;
                    m.metallic = 0;
                    break;
            }
        }

        public bool is_empty () {
            return faces.size == 0;
        }

        public void clear () {
            cage = new Mesh ();
            faces.clear ();
            creases.clear ();
        }

        public static string edge_key (int a, int b) {
            return a < b ? "%d:%d".printf (a, b) : "%d:%d".printf (b, a);
        }

        private void add_face (int[] idx) {
            var f = new Gee.ArrayList<int> ();
            foreach (var i in idx) f.add (i);
            faces.add (f);
        }

        public void make_cube (double size) {
            clear ();
            double h = size / 2;
            for (int i = 0; i < 8; i++) cage.add_vertex (Vec3 ((i & 1) != 0 ? h : -h, (i & 2) != 0 ? h : -h, (i & 4) != 0 ? h : -h));
            add_face ({ 0, 2, 3, 1 });
            add_face ({ 4, 5, 7, 6 });
            add_face ({ 0, 1, 5, 4 });
            add_face ({ 2, 6, 7, 3 });
            add_face ({ 0, 4, 6, 2 });
            add_face ({ 1, 3, 7, 5 });
        }

        public void make_cylinder (double radius, double height, int segments) {
            clear ();
            segments = int.max (3, segments);
            for (int ring = 0; ring < 2; ring++) {
                for (int i = 0; i < segments; i++) {
                    double a = 2 * Math.PI * i / segments;
                    cage.add_vertex (Vec3 (radius * Math.cos (a), ring == 0 ? -height / 2 : height / 2, radius * Math.sin (a)));
                }
            }
            for (int i = 0; i < segments; i++) {
                int j = (i + 1) % segments;
                add_face ({ i, j, segments + j, segments + i });
            }
            int[] bottom = {};
            int[] top = {};
            for (int i = segments - 1; i >= 0; i--) bottom += i;
            for (int i = 0; i < segments; i++) top += segments + i;
            add_face (bottom);
            add_face (top);
            for (int i = 0; i < segments; i++) {
                creases.add (edge_key (i, (i + 1) % segments));
                creases.add (edge_key (segments + i, segments + (i + 1) % segments));
            }
        }

        public void make_sphere (double radius, int segments) {
            make_cube (radius * 2 / Math.sqrt (3) * 1.3);
            levels = int.max (levels, 2);
        }

        public int extrude_face (int f, double distance) {
            if (f < 0 || f >= faces.size) return -1;
            var face = faces[f];
            var n = face_normal (f);
            int k = face.size;
            int[] fresh = new int[k];
            for (int i = 0; i < k; i++) fresh[i] = cage.add_vertex (cage.vertices[face[i]].add (n.scale (distance)));
            for (int i = 0; i < k; i++) {
                int a = face[i], b = face[(i + 1) % k];
                add_face ({ a, b, fresh[(i + 1) % k], fresh[i] });
            }
            for (int i = 0; i < k; i++) face[i] = fresh[i];
            return f;
        }

        public int inset_face (int f, double amount) {
            if (f < 0 || f >= faces.size) return -1;
            var face = faces[f];
            var c = face_center (f);
            int k = face.size;
            int[] fresh = new int[k];
            for (int i = 0; i < k; i++) {
                var v = cage.vertices[face[i]];
                var dir = c.sub (v);
                double l = dir.length ();
                double t = l > 1e-9 ? (amount / l).clamp (0, 0.95) : 0;
                fresh[i] = cage.add_vertex (v.lerp (c, t));
            }
            for (int i = 0; i < k; i++) {
                int a = face[i], b = face[(i + 1) % k];
                add_face ({ a, b, fresh[(i + 1) % k], fresh[i] });
            }
            for (int i = 0; i < k; i++) face[i] = fresh[i];
            return f;
        }

        public void move_vertices (int[] ids, Vec3 delta) {
            foreach (var i in ids) if (i >= 0 && i < cage.vertices.size) cage.vertices[i] = cage.vertices[i].add (delta);
        }

        public void move_face (int f, Vec3 delta) {
            if (f < 0 || f >= faces.size) return;
            int[] ids = {};
            foreach (var i in faces[f]) ids += i;
            move_vertices (ids, delta);
        }

        public void set_crease (int a, int b, bool on) {
            if (on) creases.add (edge_key (a, b));
            else creases.remove (edge_key (a, b));
        }

        public void crease_face (int f, bool on) {
            if (f < 0 || f >= faces.size) return;
            var face = faces[f];
            for (int i = 0; i < face.size; i++) set_crease (face[i], face[(i + 1) % face.size], on);
        }

        public void delete_face (int f) {
            if (f >= 0 && f < faces.size) faces.remove_at (f);
        }

        public Vec3 face_center (int f) {
            var c = Vec3.zero ();
            foreach (var i in faces[f]) c = c.add (cage.vertices[i]);
            return c.scale (1.0 / faces[f].size);
        }

        public Vec3 face_normal (int f) {
            var face = faces[f];
            var n = Vec3.zero ();
            for (int i = 0; i < face.size; i++) {
                var a = cage.vertices[face[i]];
                var b = cage.vertices[face[(i + 1) % face.size]];
                n = n.add (Vec3 ((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)));
            }
            return n.normalized ();
        }

        public static void catmull_clark (Gee.List<Vec3?> verts, Gee.List<Gee.ArrayList<int>> faces, Gee.Set<string> creases,
                                          out Gee.ArrayList<Vec3?> out_verts, out Gee.ArrayList<Gee.ArrayList<int>> out_faces, out Gee.HashSet<string> out_creases) {
            int nv = verts.size;
            var edge_index = new Gee.HashMap<string, int> ();
            var edge_a = new Gee.ArrayList<int> ();
            var edge_b = new Gee.ArrayList<int> ();
            var edge_faces = new Gee.ArrayList<Gee.ArrayList<int>> ();
            var face_points = new Gee.ArrayList<Vec3?> ();
            for (int f = 0; f < faces.size; f++) {
                var face = faces[f];
                var c = Vec3.zero ();
                foreach (var i in face) c = c.add (verts[i]);
                face_points.add (c.scale (1.0 / face.size));
                for (int k = 0; k < face.size; k++) {
                    int a = face[k], b = face[(k + 1) % face.size];
                    string key = edge_key (a, b);
                    if (!edge_index.has_key (key)) {
                        edge_index[key] = edge_a.size;
                        edge_a.add (a);
                        edge_b.add (b);
                        edge_faces.add (new Gee.ArrayList<int> ());
                    }
                    edge_faces[edge_index[key]].add (f);
                }
            }
            int ne = edge_a.size;
            var sharp = new bool[ne];
            var edge_points = new Gee.ArrayList<Vec3?> ();
            for (int e = 0; e < ne; e++) {
                var a = verts[edge_a[e]];
                var b = verts[edge_b[e]];
                sharp[e] = edge_faces[e].size != 2 || creases.contains (edge_key (edge_a[e], edge_b[e]));
                if (sharp[e]) {
                    edge_points.add (a.add (b).scale (0.5));
                } else {
                    var f0 = face_points[edge_faces[e][0]];
                    var f1 = face_points[edge_faces[e][1]];
                    edge_points.add (a.add (b).add (f0).add (f1).scale (0.25));
                }
            }
            var vface_sum = new Vec3[nv];
            var vface_cnt = new int[nv];
            var vedge_mid = new Vec3[nv];
            var vedge_cnt = new int[nv];
            var vsharp_sum = new Vec3[nv];
            var vsharp_cnt = new int[nv];
            for (int i = 0; i < nv; i++) {
                vface_sum[i] = Vec3.zero ();
                vedge_mid[i] = Vec3.zero ();
                vsharp_sum[i] = Vec3.zero ();
            }
            for (int f = 0; f < faces.size; f++) foreach (var i in faces[f]) {
                vface_sum[i] = vface_sum[i].add (face_points[f]);
                vface_cnt[i]++;
            }
            for (int e = 0; e < ne; e++) {
                int a = edge_a[e], b = edge_b[e];
                var mid = verts[a].add (verts[b]).scale (0.5);
                vedge_mid[a] = vedge_mid[a].add (mid);
                vedge_mid[b] = vedge_mid[b].add (mid);
                vedge_cnt[a]++;
                vedge_cnt[b]++;
                if (sharp[e]) {
                    vsharp_sum[a] = vsharp_sum[a].add (verts[b]);
                    vsharp_sum[b] = vsharp_sum[b].add (verts[a]);
                    vsharp_cnt[a]++;
                    vsharp_cnt[b]++;
                }
            }
            out_verts = new Gee.ArrayList<Vec3?> ();
            for (int i = 0; i < nv; i++) {
                var v = verts[i];
                if (vsharp_cnt[i] > 2 || vface_cnt[i] == 0) {
                    out_verts.add (v);
                } else if (vsharp_cnt[i] == 2) {
                    out_verts.add (v.scale (6).add (vsharp_sum[i]).scale (1.0 / 8));
                } else {
                    double n = vedge_cnt[i];
                    var f = vface_sum[i].scale (1.0 / vface_cnt[i]);
                    var r = vedge_mid[i].scale (1.0 / n);
                    out_verts.add (f.add (r.scale (2)).add (v.scale (n - 3)).scale (1.0 / n));
                }
            }
            int fp_base = out_verts.size;
            out_verts.add_all (face_points);
            int ep_base = out_verts.size;
            out_verts.add_all (edge_points);
            out_faces = new Gee.ArrayList<Gee.ArrayList<int>> ();
            for (int f = 0; f < faces.size; f++) {
                var face = faces[f];
                int k = face.size;
                for (int j = 0; j < k; j++) {
                    int v = face[j];
                    int e_next = edge_index[edge_key (v, face[(j + 1) % k])];
                    int e_prev = edge_index[edge_key (face[(j - 1 + k) % k], v)];
                    var q = new Gee.ArrayList<int> ();
                    q.add (v);
                    q.add (ep_base + e_next);
                    q.add (fp_base + f);
                    q.add (ep_base + e_prev);
                    out_faces.add (q);
                }
            }
            out_creases = new Gee.HashSet<string> ();
            for (int e = 0; e < ne; e++) {
                if (!creases.contains (edge_key (edge_a[e], edge_b[e]))) continue;
                out_creases.add (edge_key (edge_a[e], ep_base + e));
                out_creases.add (edge_key (edge_b[e], ep_base + e));
            }
        }

        public void subdivide (int level, out Gee.ArrayList<Vec3?> verts, out Gee.ArrayList<Gee.ArrayList<int>> out_faces) {
            var v = new Gee.ArrayList<Vec3?> ();
            v.add_all (cage.vertices);
            var f = new Gee.ArrayList<Gee.ArrayList<int>> ();
            f.add_all (faces);
            var c = new Gee.HashSet<string> ();
            c.add_all (creases);
            for (int i = 0; i < level; i++) {
                Gee.ArrayList<Vec3?> nv;
                Gee.ArrayList<Gee.ArrayList<int>> nf;
                Gee.HashSet<string> nc;
                catmull_clark (v, f, c, out nv, out nf, out nc);
                v = nv;
                f = nf;
                c = nc;
            }
            verts = v;
            out_faces = f;
        }

        public Mesh subdivided () {
            Gee.ArrayList<Vec3?> v;
            Gee.ArrayList<Gee.ArrayList<int>> f;
            subdivide (levels, out v, out f);
            var m = polygons_to_mesh (v, f);
            m.name = "product";
            apply_material (m, material);
            return m;
        }

        public static Mesh polygons_to_mesh (Gee.List<Vec3?> v, Gee.List<Gee.ArrayList<int>> f) {
            var m = new Mesh ();
            m.vertices.add_all (v);
            foreach (var face in f) for (int k = 1; k + 1 < face.size; k++) m.add_triangle (face[0], face[k], face[k + 1]);
            m.compute_normals ();
            return m;
        }

        public Mesh cage_mesh () {
            var m = new Mesh ();
            m.name = "cage";
            m.vertices.add_all (cage.vertices);
            var seen = new Gee.HashSet<string> ();
            foreach (var face in faces) {
                for (int k = 0; k < face.size; k++) {
                    int a = face[k], b = face[(k + 1) % face.size];
                    string key = edge_key (a, b);
                    if (seen.contains (key)) continue;
                    seen.add (key);
                    m.add_line (a, b);
                }
            }
            m.color = Rgba (0.2, 0.45, 0.9, 1);
            return m;
        }

        public Mesh sketch_mesh () {
            var m = new Mesh ();
            m.name = "sketches";
            foreach (var c in sketches) {
                int base_index = m.vertices.size;
                for (int i = 0; i < c.count (); i++) m.vertices.add (c.point3d (i));
                for (int i = 0; i + 1 < c.count (); i++) m.add_line (base_index + i, base_index + i + 1);
                if (c.closed && c.count () > 2) m.add_line (base_index + c.count () - 1, base_index);
            }
            m.color = Rgba (0.9, 0.35, 0.1, 1);
            return m;
        }

        public Gee.ArrayList<Mesh> scene () {
            var list = new Gee.ArrayList<Mesh> ();
            if (!is_empty ()) {
                list.add (subdivided ());
                list.add (cage_mesh ());
            }
            foreach (var s in surfaces) list.add (s);
            if (sketches.size > 0) list.add (sketch_mesh ());
            return list;
        }
    }

    public class Surfaces {
        public static double[] bspline (double[] pts, int degree, int samples) {
            int n = pts.length / 2;
            if (n < 2) return pts;
            int p = int.min (degree, n - 1);
            int m = n + p + 1;
            var knots = new double[m];
            for (int i = 0; i < m; i++) {
                if (i <= p) knots[i] = 0;
                else if (i >= n) knots[i] = 1;
                else knots[i] = (double) (i - p) / (n - p);
            }
            double[] out_pts = {};
            for (int s = 0; s <= samples; s++) {
                double t = (double) s / samples;
                if (t >= 1) t = 1 - 1e-9;
                int k = p;
                while (k < n - 1 && knots[k + 1] <= t) k++;
                var dx = new double[p + 1];
                var dy = new double[p + 1];
                for (int j = 0; j <= p; j++) {
                    dx[j] = pts[(j + k - p) * 2];
                    dy[j] = pts[(j + k - p) * 2 + 1];
                }
                for (int r = 1; r <= p; r++) {
                    for (int j = p; j >= r; j--) {
                        double den = knots[j + 1 + k - r] - knots[j + k - p];
                        double alpha = den > 0 ? (t - knots[j + k - p]) / den : 0;
                        dx[j] = (1 - alpha) * dx[j - 1] + alpha * dx[j];
                        dy[j] = (1 - alpha) * dy[j - 1] + alpha * dy[j];
                    }
                }
                out_pts += dx[p];
                out_pts += dy[p];
            }
            return out_pts;
        }

        public static Mesh revolve (double[] profile, int segments, double angle_deg = 360) {
            var m = new Mesh ();
            int n = profile.length / 2;
            bool full = angle_deg >= 359.999;
            int cols = full ? segments : segments + 1;
            for (int s = 0; s < cols; s++) {
                double a = angle_deg * Math.PI / 180 * s / segments;
                for (int i = 0; i < n; i++) {
                    double r = profile[i * 2], y = profile[i * 2 + 1];
                    m.add_vertex (Vec3 (r * Math.cos (a), y, r * Math.sin (a)));
                    m.uvs.add ((double) s / segments);
                    m.uvs.add ((double) i / double.max (1, n - 1));
                }
            }
            for (int s = 0; s < segments; s++) {
                int c0 = s * n, c1 = ((s + 1) % cols) * n;
                for (int i = 0; i < n - 1; i++) {
                    m.add_triangle (c0 + i, c0 + i + 1, c1 + i);
                    m.add_triangle (c1 + i, c0 + i + 1, c1 + i + 1);
                }
            }
            m.compute_normals ();
            m.name = "revolve";
            return m;
        }

        public static Mesh extrude (double[] profile, double depth, bool cap) {
            var m = new Mesh ();
            int n = profile.length / 2;
            for (int layer = 0; layer < 2; layer++) {
                for (int i = 0; i < n; i++) m.add_vertex (Vec3 (profile[i * 2], profile[i * 2 + 1], layer == 0 ? 0 : depth));
            }
            for (int i = 0; i < n; i++) {
                int j = (i + 1) % n;
                m.add_triangle (i, j, n + i);
                m.add_triangle (n + i, j, n + j);
            }
            if (cap && n >= 3) {
                for (int i = 1; i + 1 < n; i++) {
                    m.add_triangle (0, i + 1, i);
                    m.add_triangle (n, n + i, n + i + 1);
                }
            }
            m.compute_normals ();
            m.name = "extrude";
            return m;
        }

        public static Mesh loft (Gee.List<Gee.ArrayList<Vec3?>> sections, bool closed) {
            var m = new Mesh ();
            int n = sections[0].size;
            foreach (var s in sections) {
                for (int i = 0; i < n; i++) {
                    double t = (double) i / double.max (1, s.size - 1) * (s.size - 1);
                    int k = (int) Math.floor (t);
                    k = int.min (k, s.size - 1);
                    m.add_vertex (s[k]);
                }
            }
            int cols = closed ? n : n - 1;
            for (int r = 0; r + 1 < sections.size; r++) {
                for (int i = 0; i < cols; i++) {
                    int j = (i + 1) % n;
                    int a = r * n + i, b = r * n + j, c = (r + 1) * n + i, d = (r + 1) * n + j;
                    m.add_triangle (a, b, c);
                    m.add_triangle (c, b, d);
                }
            }
            m.compute_normals ();
            m.name = "loft";
            return m;
        }

        public static Mesh sweep (double[] profile, Gee.List<Vec3?> path, bool closed_profile) {
            var sections = new Gee.ArrayList<Gee.ArrayList<Vec3?>> ();
            int np = path.size;
            var up = Vec3 (0, 1, 0);
            for (int i = 0; i < np; i++) {
                var t = (i + 1 < np ? path[i + 1].sub (path[i]) : path[i].sub (path[i - 1])).normalized ();
                if (i > 0 && i + 1 < np) t = path[i + 1].sub (path[i - 1]).normalized ();
                var nrm = up.sub (t.scale (up.dot (t)));
                if (nrm.length () < 1e-6) nrm = t.any_perpendicular ();
                nrm = nrm.normalized ();
                var bin = t.cross (nrm).normalized ();
                var sec = new Gee.ArrayList<Vec3?> ();
                for (int k = 0; k < profile.length / 2; k++) sec.add (path[i].add (bin.scale (profile[k * 2])).add (nrm.scale (profile[k * 2 + 1])));
                sections.add (sec);
            }
            var m = loft (sections, closed_profile);
            m.name = "sweep";
            return m;
        }
    }
}
