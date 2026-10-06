namespace Singularity.Apps.Atelier {

    public class Obj {
        private static string num (double v) {
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            return v.format (buf, "%.6g");
        }

        private static string mat_name (Mesh m, int index) {
            string n = m.material != "" ? m.material : (m.name != "" ? m.name : "material");
            return "%s_%d".printf (n.replace (" ", "_"), index);
        }

        public static string write (Gee.List<Mesh> meshes, string mtl_file, out string mtl) {
            var sb = new StringBuilder ();
            var ms = new StringBuilder ();
            sb.append ("# Singularity Atelier\n");
            if (mtl_file != "") sb.append ("mtllib %s\n".printf (mtl_file));
            int vbase = 1, tbase = 1, nbase = 1;
            int index = 0;
            foreach (var m in meshes) {
                if (m.vertices.size == 0 || m.triangles.size == 0) continue;
                if (m.normals.size != m.vertices.size) m.compute_normals ();
                bool uv = m.uvs.size == m.vertices.size * 2;
                string mn = mat_name (m, index);
                sb.append ("o %s\n".printf ((m.name != "" ? m.name : "mesh%d".printf (index)).replace (" ", "_")));
                foreach (var v in m.vertices) sb.append ("v %s %s %s\n".printf (num (v.x), num (v.y), num (v.z)));
                if (uv) for (int i = 0; i < m.uvs.size; i += 2) sb.append ("vt %s %s\n".printf (num (m.uvs[i]), num (m.uvs[i + 1])));
                foreach (var n in m.normals) sb.append ("vn %s %s %s\n".printf (num (n.x), num (n.y), num (n.z)));
                sb.append ("usemtl %s\n".printf (mn));
                for (int t = 0; t + 2 < m.triangles.size; t += 3) {
                    sb.append ("f");
                    for (int k = 0; k < 3; k++) {
                        int i = m.triangles[t + k];
                        if (uv) sb.append (" %d/%d/%d".printf (vbase + i, tbase + i, nbase + i));
                        else sb.append (" %d//%d".printf (vbase + i, nbase + i));
                    }
                    sb.append ("\n");
                }
                vbase += m.vertices.size;
                if (uv) tbase += m.vertices.size;
                nbase += m.vertices.size;
                ms.append ("newmtl %s\n".printf (mn));
                ms.append ("Kd %s %s %s\n".printf (num (m.color.r), num (m.color.g), num (m.color.b)));
                ms.append ("Ka 0 0 0\n");
                ms.append ("Ks %s %s %s\n".printf (num (0.04 + m.metallic * 0.9), num (0.04 + m.metallic * 0.9), num (0.04 + m.metallic * 0.9)));
                ms.append ("Ns %s\n".printf (num ((1 - m.roughness) * 900 + 2)));
                ms.append ("d %s\n".printf (num (m.color.a)));
                ms.append ("Pr %s\nPm %s\n\n".printf (num (m.roughness), num (m.metallic)));
                index++;
            }
            mtl = ms.str;
            return sb.str;
        }

        public static void save (string path, Gee.List<Mesh> meshes) throws Error {
            string base_name = Path.get_basename (path);
            int dot = base_name.last_index_of (".");
            string mtl_name = (dot > 0 ? base_name.substring (0, dot) : base_name) + ".mtl";
            string mtl;
            string text = write (meshes, mtl_name, out mtl);
            FileUtils.set_contents (path, text);
            FileUtils.set_contents (Path.build_filename (Path.get_dirname (path), mtl_name), mtl);
        }

        public static Gee.ArrayList<Mesh> load (string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            string? mtl = null;
            foreach (var line in text.split ("\n")) {
                if (line.has_prefix ("mtllib ")) {
                    string mp = Path.build_filename (Path.get_dirname (path), line.substring (7).strip ());
                    if (FileUtils.test (mp, FileTest.EXISTS)) FileUtils.get_contents (mp, out mtl);
                    break;
                }
            }
            return parse (text, mtl);
        }

        private class MatInfo {
            public Rgba color = Rgba (0.8, 0.8, 0.8, 1);
            public double roughness = 0.7;
            public double metallic;
        }

        private static int resolve (string s, int count) {
            int v = int.parse (s);
            return v < 0 ? count + v : v - 1;
        }

        private static void reorder (Mesh m, Gee.ArrayList<int> src) {
            var seen = new Gee.HashSet<int> ();
            foreach (var s in src) {
                if (seen.contains (s)) return;
                seen.add (s);
            }
            int n = m.vertices.size;
            var order = new Gee.ArrayList<int> ();
            for (int i = 0; i < n; i++) order.add (i);
            order.sort ((a, b) => src[a] < src[b] ? -1 : (src[a] > src[b] ? 1 : 0));
            var new_index = new int[n];
            for (int i = 0; i < n; i++) new_index[order[i]] = i;
            var v = new Gee.ArrayList<Vec3?> ();
            var nr = new Gee.ArrayList<Vec3?> ();
            var uv = new Gee.ArrayList<double?> ();
            bool has_n = m.normals.size == n, has_uv = m.uvs.size == n * 2;
            foreach (var i in order) {
                v.add (m.vertices[i]);
                if (has_n) nr.add (m.normals[i]);
                if (has_uv) {
                    uv.add (m.uvs[i * 2]);
                    uv.add (m.uvs[i * 2 + 1]);
                }
            }
            m.vertices = v;
            if (has_n) m.normals = nr;
            if (has_uv) m.uvs = uv;
            for (int t = 0; t < m.triangles.size; t++) m.triangles[t] = new_index[m.triangles[t]];
        }

        public static Gee.ArrayList<Mesh> parse (string text, string? mtl_text = null) throws Error {
            var mats = new Gee.HashMap<string, MatInfo> ();
            if (mtl_text != null) {
                MatInfo? cur = null;
                foreach (var raw in mtl_text.split ("\n")) {
                    var p = Regex.split_simple ("\\s+", raw.strip ());
                    if (p.length < 2) continue;
                    if (p[0] == "newmtl") {
                        cur = new MatInfo ();
                        mats[p[1]] = cur;
                    } else if (cur != null && p[0] == "Kd" && p.length >= 4) {
                        cur.color = Rgba (double.parse (p[1]), double.parse (p[2]), double.parse (p[3]), cur.color.a);
                    } else if (cur != null && p[0] == "d") {
                        cur.color.a = double.parse (p[1]);
                    } else if (cur != null && p[0] == "Pr") {
                        cur.roughness = double.parse (p[1]);
                    } else if (cur != null && p[0] == "Pm") {
                        cur.metallic = double.parse (p[1]);
                    } else if (cur != null && p[0] == "Ns") {
                        cur.roughness = (1 - (double.parse (p[1]) - 2) / 900).clamp (0, 1);
                    }
                }
            }
            var pos = new Gee.ArrayList<Vec3?> ();
            var tex = new Gee.ArrayList<double?> ();
            var nor = new Gee.ArrayList<Vec3?> ();
            var result = new Gee.ArrayList<Mesh> ();
            Mesh? cur_mesh = null;
            Gee.HashMap<string, int>? remap = null;
            var sources = new Gee.HashMap<Mesh, Gee.ArrayList<int>> ();
            string pending_name = "mesh";
            string pending_mat = "";
            int line_no = 0;
            foreach (var raw in text.split ("\n")) {
                line_no++;
                string line = raw.strip ();
                if (line == "" || line.has_prefix ("#")) continue;
                var p = Regex.split_simple ("\\s+", line);
                switch (p[0]) {
                    case "v":
                        if (p.length < 4) throw new MeshIOError.INVALID (_("Bad vertex on line %d").printf (line_no));
                        pos.add (Vec3 (double.parse (p[1]), double.parse (p[2]), double.parse (p[3])));
                        break;
                    case "vt":
                        tex.add (double.parse (p[1]));
                        tex.add (p.length > 2 ? double.parse (p[2]) : 0);
                        break;
                    case "vn":
                        nor.add (Vec3 (double.parse (p[1]), double.parse (p[2]), double.parse (p[3])));
                        break;
                    case "o":
                    case "g":
                        pending_name = p.length > 1 ? p[1] : "mesh";
                        cur_mesh = null;
                        break;
                    case "usemtl":
                        pending_mat = p.length > 1 ? p[1] : "";
                        cur_mesh = null;
                        break;
                    case "f": {
                        if (cur_mesh == null) {
                            cur_mesh = new Mesh ();
                            cur_mesh.name = pending_name;
                            cur_mesh.material = pending_mat;
                            if (mats.has_key (pending_mat)) {
                                cur_mesh.color = mats[pending_mat].color;
                                cur_mesh.roughness = mats[pending_mat].roughness;
                                cur_mesh.metallic = mats[pending_mat].metallic;
                            }
                            result.add (cur_mesh);
                            sources[cur_mesh] = new Gee.ArrayList<int> ();
                            remap = new Gee.HashMap<string, int> ();
                        }
                        int[] idx = {};
                        for (int k = 1; k < p.length; k++) {
                            string key = p[k];
                            if (!remap.has_key (key)) {
                                var parts = key.split ("/");
                                int vi = resolve (parts[0], pos.size);
                                if (vi < 0 || vi >= pos.size) throw new MeshIOError.INVALID (_("Bad face on line %d").printf (line_no));
                                cur_mesh.vertices.add (pos[vi]);
                                sources[cur_mesh].add (vi);
                                if (parts.length > 1 && parts[1] != "") {
                                    int ti = resolve (parts[1], tex.size / 2);
                                    if (ti >= 0 && ti * 2 + 1 < tex.size) {
                                        cur_mesh.uvs.add (tex[ti * 2]);
                                        cur_mesh.uvs.add (tex[ti * 2 + 1]);
                                    }
                                }
                                if (parts.length > 2 && parts[2] != "") {
                                    int ni = resolve (parts[2], nor.size);
                                    if (ni >= 0 && ni < nor.size) cur_mesh.normals.add (nor[ni]);
                                }
                                remap[key] = cur_mesh.vertices.size - 1;
                            }
                            idx += remap[key];
                        }
                        for (int k = 1; k + 1 < idx.length; k++) cur_mesh.add_triangle (idx[0], idx[k], idx[k + 1]);
                        break;
                    }
                    default:
                        break;
                }
            }
            foreach (var m in result) {
                reorder (m, sources[m]);
                if (m.normals.size != m.vertices.size) m.compute_normals ();
                if (m.uvs.size != m.vertices.size * 2) m.uvs.clear ();
            }
            return result;
        }
    }
}
