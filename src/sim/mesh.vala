namespace Singularity.Apps.Atelier {

    public class Mesh {
        public string name = "";
        public Gee.ArrayList<Vec3?> vertices = new Gee.ArrayList<Vec3?> ();
        public Gee.ArrayList<Vec3?> normals = new Gee.ArrayList<Vec3?> ();
        public Gee.ArrayList<double?> uvs = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<int> triangles = new Gee.ArrayList<int> ();
        public Gee.ArrayList<double?> scalars = new Gee.ArrayList<double?> ();
        public Gee.ArrayList<int> lines = new Gee.ArrayList<int> ();
        public Rgba color = Rgba (0.8, 0.8, 0.8, 1);
        public double roughness = 0.7;
        public double metallic = 0;
        public double clearcoat = 0;
        public string material = "";
        public bool visible = true;
        public bool double_sided = true;

        public int triangle_count () {
            return triangles.size / 3;
        }

        public int add_vertex (Vec3 v) {
            vertices.add (v);
            return vertices.size - 1;
        }

        public void add_triangle (int a, int b, int c) {
            triangles.add (a);
            triangles.add (b);
            triangles.add (c);
        }

        public void add_line (int a, int b) {
            lines.add (a);
            lines.add (b);
        }

        public void compute_normals () {
            var acc = new Vec3[vertices.size];
            for (int i = 0; i < acc.length; i++) acc[i] = Vec3.zero ();
            for (int t = 0; t + 2 < triangles.size; t += 3) {
                int a = triangles[t], b = triangles[t + 1], c = triangles[t + 2];
                var n = vertices[b].sub (vertices[a]).cross (vertices[c].sub (vertices[a]));
                acc[a] = acc[a].add (n);
                acc[b] = acc[b].add (n);
                acc[c] = acc[c].add (n);
            }
            normals.clear ();
            foreach (var n in acc) normals.add (n.normalized ());
        }

        public double[] curvature () {
            int n = vertices.size;
            var sum = new double[n];
            var cnt = new int[n];
            if (normals.size != n) compute_normals ();
            for (int t = 0; t + 2 < triangles.size; t += 3) {
                for (int e = 0; e < 3; e++) {
                    int a = triangles[t + e], b = triangles[t + (e + 1) % 3];
                    double len = vertices[a].distance (vertices[b]);
                    if (len < 1e-9) continue;
                    double ang = Math.acos (normals[a].dot (normals[b]).clamp (-1, 1));
                    sum[a] += ang / len;
                    sum[b] += ang / len;
                    cnt[a]++;
                    cnt[b]++;
                }
            }
            for (int i = 0; i < n; i++) if (cnt[i] > 0) sum[i] /= cnt[i];
            return sum;
        }

        public static Mesh from_scene (Scene.Mesh src) {
            var m = new Mesh ();
            m.name = src.name;
            int n = src.vertex_count;
            for (int i = 0; i < n; i++) m.vertices.add (Vec3 (src.positions[i * 3], src.positions[i * 3 + 1], src.positions[i * 3 + 2]));
            if (src.normals.length == n * 3) for (int i = 0; i < n; i++) m.normals.add (Vec3 (src.normals[i * 3], src.normals[i * 3 + 1], src.normals[i * 3 + 2]));
            if (src.uvs.length == n * 2) for (int i = 0; i < n * 2; i++) m.uvs.add (src.uvs[i]);
            for (int i = 0; i < src.triangles.length; i++) m.triangles.add ((int) src.triangles[i]);
            var c = src.material.color;
            m.color = Rgba (c.red, c.green, c.blue, c.alpha);
            m.roughness = src.material.roughness;
            m.metallic = src.material.metallic;
            m.double_sided = src.material.double_sided;
            return m;
        }

        public Scene.Mesh to_scene (bool with_curvature = false) {
            var m = new Scene.Mesh ();
            m.name = name;
            int n = vertices.size;
            m.positions = new float[n * 3];
            for (int i = 0; i < n; i++) {
                var v = vertices[i];
                m.positions[i * 3] = (float) v.x;
                m.positions[i * 3 + 1] = (float) v.y;
                m.positions[i * 3 + 2] = (float) v.z;
            }
            m.triangles = new uint[triangles.size];
            for (int i = 0; i < triangles.size; i++) m.triangles[i] = triangles[i];
            m.lines = new uint[lines.size];
            for (int i = 0; i < lines.size; i++) m.lines[i] = lines[i];
            if (uvs.size == n * 2) {
                m.uvs = new float[n * 2];
                for (int i = 0; i < n * 2; i++) m.uvs[i] = (float) uvs[i];
            }
            if (with_curvature && triangles.size > 0) {
                var c = curvature ();
                double cmax = 0;
                foreach (var k in c) cmax = double.max (cmax, k);
                m.scalars = new float[n];
                for (int i = 0; i < n; i++) m.scalars[i] = cmax > 0 ? (float) Math.sqrt (c[i] / cmax) : 0;
            } else if (scalars.size == n) {
                m.scalars = new float[n];
                for (int i = 0; i < n; i++) m.scalars[i] = (float) scalars[i];
            }
            if (triangles.size > 0) m.compute_normals ();
            m.visible = visible;
            m.material.color = Gdk.RGBA () { red = (float) color.r, green = (float) color.g, blue = (float) color.b, alpha = (float) color.a };
            m.material.roughness = roughness;
            m.material.metallic = metallic;
            m.material.clearcoat = clearcoat;
            m.material.double_sided = double_sided;
            if (triangles.size == 0) m.material.shading = Scene.Shading.FLAT;
            return m;
        }

        public void bounds (out Vec3 min, out Vec3 max) {
            min = Vec3 (double.INFINITY, double.INFINITY, double.INFINITY);
            max = Vec3 (-double.INFINITY, -double.INFINITY, -double.INFINITY);
            foreach (var v in vertices) {
                min = Vec3 (double.min (min.x, v.x), double.min (min.y, v.y), double.min (min.z, v.z));
                max = Vec3 (double.max (max.x, v.x), double.max (max.y, v.y), double.max (max.z, v.z));
            }
        }

        public void append (Mesh other) {
            int base_index = vertices.size;
            bool keep_normals = normals.size == vertices.size && other.normals.size == other.vertices.size;
            bool keep_uvs = uvs.size == vertices.size * 2 && other.uvs.size == other.vertices.size * 2;
            bool keep_scalars = scalars.size == vertices.size && other.scalars.size == other.vertices.size;
            vertices.add_all (other.vertices);
            if (keep_normals) normals.add_all (other.normals);
            else normals.clear ();
            if (keep_uvs) uvs.add_all (other.uvs);
            else uvs.clear ();
            if (keep_scalars) scalars.add_all (other.scalars);
            else scalars.clear ();
            foreach (var i in other.triangles) triangles.add (i + base_index);
            foreach (var i in other.lines) lines.add (i + base_index);
        }

        public Mesh copy () {
            var m = new Mesh ();
            m.name = name;
            m.vertices.add_all (vertices);
            m.normals.add_all (normals);
            m.uvs.add_all (uvs);
            m.triangles.add_all (triangles);
            m.scalars.add_all (scalars);
            m.lines.add_all (lines);
            m.color = color;
            m.roughness = roughness;
            m.metallic = metallic;
            m.clearcoat = clearcoat;
            m.material = material;
            m.visible = visible;
            m.double_sided = double_sided;
            return m;
        }

        public void translate (Vec3 d) {
            for (int i = 0; i < vertices.size; i++) vertices[i] = vertices[i].add (d);
        }

        public void scale_by (double s) {
            for (int i = 0; i < vertices.size; i++) vertices[i] = vertices[i].scale (s);
        }

        public double surface_area () {
            double a = 0;
            for (int t = 0; t + 2 < triangles.size; t += 3) {
                var p = vertices[triangles[t]];
                a += vertices[triangles[t + 1]].sub (p).cross (vertices[triangles[t + 2]].sub (p)).length () / 2;
            }
            return a;
        }

        public Gee.ArrayList<Vec3?> slice_y (double y) {
            var pts = new Gee.ArrayList<Vec3?> ();
            for (int t = 0; t + 2 < triangles.size; t += 3) {
                Vec3[] tri = { vertices[triangles[t]], vertices[triangles[t + 1]], vertices[triangles[t + 2]] };
                for (int e = 0; e < 3; e++) {
                    var a = tri[e];
                    var b = tri[(e + 1) % 3];
                    if ((a.y - y) * (b.y - y) < 0 || (a.y == y && b.y != y)) {
                        double k = (y - a.y) / (b.y - a.y);
                        pts.add (a.lerp (b, k));
                    }
                }
            }
            return pts;
        }

        public static double hull_perimeter_xz (Gee.List<Vec3?> pts) {
            int n = pts.size;
            if (n < 3) return 0;
            var sorted = new Gee.ArrayList<Vec3?> ();
            sorted.add_all (pts);
            sorted.sort ((a, b) => a.x < b.x ? -1 : (a.x > b.x ? 1 : (a.z < b.z ? -1 : (a.z > b.z ? 1 : 0))));
            var hull = new Gee.ArrayList<Vec3?> ();
            for (int pass = 0; pass < 2; pass++) {
                int start = hull.size;
                for (int k = 0; k < n; k++) {
                    var p = sorted[pass == 0 ? k : n - 1 - k];
                    while (hull.size >= start + 2) {
                        var a = hull[hull.size - 2];
                        var b = hull[hull.size - 1];
                        double cr = (b.x - a.x) * (p.z - a.z) - (b.z - a.z) * (p.x - a.x);
                        if (cr <= 0) hull.remove_at (hull.size - 1);
                        else break;
                    }
                    hull.add (p);
                }
                hull.remove_at (hull.size - 1);
            }
            double per = 0;
            for (int i = 0; i < hull.size; i++) {
                var a = hull[i];
                var b = hull[(i + 1) % hull.size];
                per += Math.hypot (b.x - a.x, b.z - a.z);
            }
            return per;
        }
    }
}
