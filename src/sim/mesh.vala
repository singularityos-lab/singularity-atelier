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
