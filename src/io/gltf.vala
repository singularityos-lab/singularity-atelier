namespace Singularity.Apps.Atelier {

    public errordomain MeshIOError {
        INVALID,
        UNSUPPORTED
    }

    public class Gltf {
        public const uint32 GLB_MAGIC = 0x46546C67;
        public const uint32 CHUNK_JSON = 0x4E4F534A;
        public const uint32 CHUNK_BIN = 0x004E4942;

        private static void put_f32 (ByteArray b, double v) {
            float f = (float) v;
            uint32 bits = 0;
            Memory.copy (&bits, &f, 4);
            put_u32 (b, bits);
        }

        private static void put_u32 (ByteArray b, uint32 v) {
            uint8[] d = { (uint8) v, (uint8) (v >> 8), (uint8) (v >> 16), (uint8) (v >> 24) };
            b.append (d);
        }

        private static void pad (ByteArray b, uint8 with) {
            while (b.len % 4 != 0) {
                uint8[] d = { with };
                b.append (d);
            }
        }

        private static int add_view (Json.Builder jb, ByteArray bin, int start, int length, int target, ref int views) {
            jb.begin_object ();
            jb.set_member_name ("buffer").add_int_value (0);
            jb.set_member_name ("byteOffset").add_int_value (start);
            jb.set_member_name ("byteLength").add_int_value (length);
            if (target > 0) jb.set_member_name ("target").add_int_value (target);
            jb.end_object ();
            return views++;
        }

        public static uint8[] write (Gee.List<Mesh> meshes, bool binary, double scale = 0.001) {
            var bin = new ByteArray ();
            var views = new Json.Builder ();
            var accessors = new Json.Builder ();
            var mesh_json = new Json.Builder ();
            var materials = new Json.Builder ();
            var nodes = new Json.Builder ();
            views.begin_array ();
            accessors.begin_array ();
            mesh_json.begin_array ();
            materials.begin_array ();
            nodes.begin_array ();
            int view_count = 0;
            int acc_count = 0;
            int index = 0;
            foreach (var m in meshes) {
                if (m.vertices.size == 0 || m.triangles.size == 0) continue;
                if (m.normals.size != m.vertices.size) m.compute_normals ();
                int start = (int) bin.len;
                double minx = double.INFINITY, miny = double.INFINITY, minz = double.INFINITY;
                double maxx = -double.INFINITY, maxy = -double.INFINITY, maxz = -double.INFINITY;
                foreach (var v in m.vertices) {
                    put_f32 (bin, v.x * scale);
                    put_f32 (bin, v.y * scale);
                    put_f32 (bin, v.z * scale);
                    minx = double.min (minx, (float) (v.x * scale));
                    miny = double.min (miny, (float) (v.y * scale));
                    minz = double.min (minz, (float) (v.z * scale));
                    maxx = double.max (maxx, (float) (v.x * scale));
                    maxy = double.max (maxy, (float) (v.y * scale));
                    maxz = double.max (maxz, (float) (v.z * scale));
                }
                int pos_view = add_view (views, bin, start, (int) bin.len - start, 34962, ref view_count);
                start = (int) bin.len;
                foreach (var n in m.normals) {
                    put_f32 (bin, n.x);
                    put_f32 (bin, n.y);
                    put_f32 (bin, n.z);
                }
                int nrm_view = add_view (views, bin, start, (int) bin.len - start, 34962, ref view_count);
                int uv_view = -1;
                if (m.uvs.size == m.vertices.size * 2) {
                    start = (int) bin.len;
                    foreach (var u in m.uvs) put_f32 (bin, u);
                    uv_view = add_view (views, bin, start, (int) bin.len - start, 34962, ref view_count);
                }
                start = (int) bin.len;
                foreach (var i in m.triangles) put_u32 (bin, (uint32) i);
                int idx_view = add_view (views, bin, start, (int) bin.len - start, 34963, ref view_count);
                int pos_acc = acc_count++;
                accessors.begin_object ();
                accessors.set_member_name ("bufferView").add_int_value (pos_view);
                accessors.set_member_name ("componentType").add_int_value (5126);
                accessors.set_member_name ("count").add_int_value (m.vertices.size);
                accessors.set_member_name ("type").add_string_value ("VEC3");
                accessors.set_member_name ("min").begin_array ().add_double_value (minx).add_double_value (miny).add_double_value (minz).end_array ();
                accessors.set_member_name ("max").begin_array ().add_double_value (maxx).add_double_value (maxy).add_double_value (maxz).end_array ();
                accessors.end_object ();
                int nrm_acc = acc_count++;
                accessors.begin_object ();
                accessors.set_member_name ("bufferView").add_int_value (nrm_view);
                accessors.set_member_name ("componentType").add_int_value (5126);
                accessors.set_member_name ("count").add_int_value (m.vertices.size);
                accessors.set_member_name ("type").add_string_value ("VEC3");
                accessors.end_object ();
                int uv_acc = -1;
                if (uv_view >= 0) {
                    uv_acc = acc_count++;
                    accessors.begin_object ();
                    accessors.set_member_name ("bufferView").add_int_value (uv_view);
                    accessors.set_member_name ("componentType").add_int_value (5126);
                    accessors.set_member_name ("count").add_int_value (m.vertices.size);
                    accessors.set_member_name ("type").add_string_value ("VEC2");
                    accessors.end_object ();
                }
                int idx_acc = acc_count++;
                accessors.begin_object ();
                accessors.set_member_name ("bufferView").add_int_value (idx_view);
                accessors.set_member_name ("componentType").add_int_value (5125);
                accessors.set_member_name ("count").add_int_value (m.triangles.size);
                accessors.set_member_name ("type").add_string_value ("SCALAR");
                accessors.end_object ();
                materials.begin_object ();
                materials.set_member_name ("name").add_string_value (m.material != "" ? m.material : "material%d".printf (index));
                materials.set_member_name ("doubleSided").add_boolean_value (m.double_sided);
                materials.set_member_name ("pbrMetallicRoughness").begin_object ();
                materials.set_member_name ("baseColorFactor").begin_array ().add_double_value (m.color.r).add_double_value (m.color.g).add_double_value (m.color.b).add_double_value (m.color.a).end_array ();
                materials.set_member_name ("metallicFactor").add_double_value (m.metallic);
                materials.set_member_name ("roughnessFactor").add_double_value (m.roughness);
                materials.end_object ();
                materials.end_object ();
                mesh_json.begin_object ();
                mesh_json.set_member_name ("name").add_string_value (m.name != "" ? m.name : "mesh%d".printf (index));
                mesh_json.set_member_name ("primitives").begin_array ().begin_object ();
                mesh_json.set_member_name ("attributes").begin_object ();
                mesh_json.set_member_name ("POSITION").add_int_value (pos_acc);
                mesh_json.set_member_name ("NORMAL").add_int_value (nrm_acc);
                if (uv_acc >= 0) mesh_json.set_member_name ("TEXCOORD_0").add_int_value (uv_acc);
                mesh_json.end_object ();
                mesh_json.set_member_name ("indices").add_int_value (idx_acc);
                mesh_json.set_member_name ("material").add_int_value (index);
                mesh_json.set_member_name ("mode").add_int_value (4);
                mesh_json.end_object ().end_array ();
                mesh_json.end_object ();
                nodes.begin_object ();
                nodes.set_member_name ("name").add_string_value (m.name != "" ? m.name : "mesh%d".printf (index));
                nodes.set_member_name ("mesh").add_int_value (index);
                nodes.end_object ();
                index++;
            }
            views.end_array ();
            accessors.end_array ();
            mesh_json.end_array ();
            materials.end_array ();
            nodes.end_array ();
            var root = new Json.Object ();
            var asset = new Json.Object ();
            asset.set_string_member ("version", "2.0");
            asset.set_string_member ("generator", "Singularity Atelier");
            root.set_object_member ("asset", asset);
            root.set_int_member ("scene", 0);
            var scenes = new Json.Array ();
            var scene = new Json.Object ();
            var scene_nodes = new Json.Array ();
            for (int i = 0; i < index; i++) scene_nodes.add_int_element (i);
            scene.set_array_member ("nodes", scene_nodes);
            scenes.add_object_element (scene);
            root.set_array_member ("scenes", scenes);
            root.set_member ("nodes", nodes.get_root ());
            root.set_member ("meshes", mesh_json.get_root ());
            root.set_member ("materials", materials.get_root ());
            root.set_member ("accessors", accessors.get_root ());
            root.set_member ("bufferViews", views.get_root ());
            pad (bin, 0);
            var buffers = new Json.Array ();
            var buf = new Json.Object ();
            buf.set_int_member ("byteLength", bin.len);
            if (!binary) buf.set_string_member ("uri", "data:application/octet-stream;base64," + Base64.encode (bin.data));
            buffers.add_object_element (buf);
            root.set_array_member ("buffers", buffers);
            var gen = new Json.Generator ();
            var rn = new Json.Node (Json.NodeType.OBJECT);
            rn.set_object (root);
            gen.set_root (rn);
            gen.pretty = !binary;
            string json = gen.to_data (null);
            if (!binary) return json.data;
            var jbytes = new ByteArray ();
            jbytes.append (json.data);
            pad (jbytes, 0x20);
            var out_bytes = new ByteArray ();
            put_u32 (out_bytes, GLB_MAGIC);
            put_u32 (out_bytes, 2);
            put_u32 (out_bytes, 12 + 8 + jbytes.len + 8 + bin.len);
            put_u32 (out_bytes, jbytes.len);
            put_u32 (out_bytes, CHUNK_JSON);
            out_bytes.append (jbytes.data);
            put_u32 (out_bytes, bin.len);
            put_u32 (out_bytes, CHUNK_BIN);
            out_bytes.append (bin.data);
            return out_bytes.data;
        }

        public static void save (string path, Gee.List<Mesh> meshes) throws Error {
            bool glb = path.down ().has_suffix (".glb");
            FileUtils.set_data (path, write (meshes, glb));
        }

        public static Gee.ArrayList<Mesh> load (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            return parse (data, Path.get_dirname (path));
        }

        private static uint32 u32 (uint8[] d, int p) {
            return d[p] | ((uint32) d[p + 1] << 8) | ((uint32) d[p + 2] << 16) | ((uint32) d[p + 3] << 24);
        }

        public static Gee.ArrayList<Mesh> parse (uint8[] data, string? base_dir = null, double scale = 1000) throws Error {
            string json_text;
            uint8[]? glb_bin = null;
            if (data.length >= 12 && u32 (data, 0) == GLB_MAGIC) {
                uint32 total = u32 (data, 8);
                if (total > data.length) throw new MeshIOError.INVALID (_("The GLB file is truncated"));
                int pos = 12;
                json_text = "";
                while (pos + 8 <= total) {
                    uint32 len = u32 (data, pos);
                    uint32 type = u32 (data, pos + 4);
                    int start = pos + 8;
                    if (start + len > total) throw new MeshIOError.INVALID (_("Bad GLB chunk"));
                    if (type == CHUNK_JSON) json_text = ((string) data[start:start + len]).substring (0, (long) len);
                    else if (type == CHUNK_BIN) glb_bin = data[start:start + len];
                    pos = start + (int) len;
                }
            } else {
                var sb = new StringBuilder ();
                foreach (var b in data) sb.append_c ((char) b);
                json_text = sb.str;
            }
            var parser = new Json.Parser ();
            parser.load_from_data (json_text);
            var root = parser.get_root ().get_object ();
            var buffers = new Gee.ArrayList<Bytes> ();
            if (root.has_member ("buffers")) {
                foreach (var bn in root.get_array_member ("buffers").get_elements ()) {
                    var bo = bn.get_object ();
                    if (bo.has_member ("uri")) {
                        string uri = bo.get_string_member ("uri");
                        if (uri.has_prefix ("data:")) {
                            int comma = uri.index_of (",");
                            buffers.add (new Bytes (Base64.decode (uri.substring (comma + 1))));
                        } else {
                            uint8[] ext;
                            FileUtils.get_data (Path.build_filename (base_dir ?? ".", Uri.unescape_string (uri) ?? uri), out ext);
                            buffers.add (new Bytes (ext));
                        }
                    } else if (glb_bin != null) {
                        buffers.add (new Bytes (glb_bin));
                    } else {
                        throw new MeshIOError.INVALID (_("A buffer has no data"));
                    }
                }
            }
            var views = root.has_member ("bufferViews") ? root.get_array_member ("bufferViews") : new Json.Array ();
            var accs = root.has_member ("accessors") ? root.get_array_member ("accessors") : new Json.Array ();
            var mats = root.has_member ("materials") ? root.get_array_member ("materials") : new Json.Array ();
            var result = new Gee.ArrayList<Mesh> ();
            if (!root.has_member ("meshes")) return result;
            var node_scale = new Gee.HashMap<int, Json.Object> ();
            if (root.has_member ("nodes")) {
                var nl = root.get_array_member ("nodes");
                for (int i = 0; i < nl.get_length (); i++) {
                    var no = nl.get_object_element (i);
                    if (no.has_member ("mesh")) node_scale[(int) no.get_int_member ("mesh")] = no;
                }
            }
            var ml = root.get_array_member ("meshes");
            for (int mi = 0; mi < ml.get_length (); mi++) {
                var mo = ml.get_object_element (mi);
                foreach (var pn in mo.get_array_member ("primitives").get_elements ()) {
                    var po = pn.get_object ();
                    if (po.has_member ("mode") && po.get_int_member ("mode") != 4) continue;
                    var attrs = po.get_object_member ("attributes");
                    var m = new Mesh ();
                    m.name = mo.has_member ("name") ? mo.get_string_member ("name") : "mesh%d".printf (mi);
                    var pos = read_floats (accs, views, buffers, (int) attrs.get_int_member ("POSITION"), 3);
                    for (int i = 0; i + 2 < pos.length; i += 3) m.vertices.add (Vec3 (pos[i] * scale, pos[i + 1] * scale, pos[i + 2] * scale));
                    if (attrs.has_member ("NORMAL")) {
                        var nrm = read_floats (accs, views, buffers, (int) attrs.get_int_member ("NORMAL"), 3);
                        for (int i = 0; i + 2 < nrm.length; i += 3) m.normals.add (Vec3 (nrm[i], nrm[i + 1], nrm[i + 2]));
                    }
                    if (attrs.has_member ("TEXCOORD_0")) {
                        var uv = read_floats (accs, views, buffers, (int) attrs.get_int_member ("TEXCOORD_0"), 2);
                        foreach (var u in uv) m.uvs.add (u);
                    }
                    if (po.has_member ("indices")) {
                        foreach (var i in read_ints (accs, views, buffers, (int) po.get_int_member ("indices"))) m.triangles.add (i);
                    } else {
                        for (int i = 0; i < m.vertices.size; i++) m.triangles.add (i);
                    }
                    if (po.has_member ("material") && po.get_int_member ("material") < mats.get_length ()) {
                        var mat = mats.get_object_element ((uint) po.get_int_member ("material"));
                        if (mat.has_member ("name")) m.material = mat.get_string_member ("name");
                        if (mat.has_member ("doubleSided")) m.double_sided = mat.get_boolean_member ("doubleSided");
                        if (mat.has_member ("pbrMetallicRoughness")) {
                            var pbr = mat.get_object_member ("pbrMetallicRoughness");
                            if (pbr.has_member ("baseColorFactor")) {
                                var c = pbr.get_array_member ("baseColorFactor");
                                m.color = Rgba (c.get_double_element (0), c.get_double_element (1), c.get_double_element (2), c.get_length () > 3 ? c.get_double_element (3) : 1);
                            }
                            if (pbr.has_member ("metallicFactor")) m.metallic = pbr.get_double_member ("metallicFactor");
                            if (pbr.has_member ("roughnessFactor")) m.roughness = pbr.get_double_member ("roughnessFactor");
                        }
                    }
                    if (node_scale.has_key (mi)) apply_node (m, node_scale[mi]);
                    if (m.normals.size != m.vertices.size) m.compute_normals ();
                    result.add (m);
                }
            }
            return result;
        }

        private static void apply_node (Mesh m, Json.Object node) {
            double sx = 1, sy = 1, sz = 1, tx = 0, ty = 0, tz = 0, qx = 0, qy = 0, qz = 0, qw = 1;
            if (node.has_member ("scale")) {
                var a = node.get_array_member ("scale");
                sx = a.get_double_element (0);
                sy = a.get_double_element (1);
                sz = a.get_double_element (2);
            }
            if (node.has_member ("translation")) {
                var a = node.get_array_member ("translation");
                tx = a.get_double_element (0) * 1000;
                ty = a.get_double_element (1) * 1000;
                tz = a.get_double_element (2) * 1000;
            }
            if (node.has_member ("rotation")) {
                var a = node.get_array_member ("rotation");
                qx = a.get_double_element (0);
                qy = a.get_double_element (1);
                qz = a.get_double_element (2);
                qw = a.get_double_element (3);
            }
            if (sx == 1 && sy == 1 && sz == 1 && tx == 0 && ty == 0 && tz == 0 && qw == 1) return;
            for (int i = 0; i < m.vertices.size; i++) {
                var v = m.vertices[i];
                v = Vec3 (v.x * sx, v.y * sy, v.z * sz);
                v = rotate (v, qx, qy, qz, qw);
                m.vertices[i] = Vec3 (v.x + tx, v.y + ty, v.z + tz);
            }
            for (int i = 0; i < m.normals.size; i++) m.normals[i] = rotate (m.normals[i], qx, qy, qz, qw);
        }

        private static Vec3 rotate (Vec3 v, double x, double y, double z, double w) {
            var q = Vec3 (x, y, z);
            var t = q.cross (v).scale (2);
            return v.add (t.scale (w)).add (q.cross (t));
        }

        private static uint8[] view_data (Json.Array views, Gee.List<Bytes> buffers, int view, out int stride) {
            var vo = views.get_object_element (view);
            int buffer = (int) vo.get_int_member ("buffer");
            int off = vo.has_member ("byteOffset") ? (int) vo.get_int_member ("byteOffset") : 0;
            int len = (int) vo.get_int_member ("byteLength");
            stride = vo.has_member ("byteStride") ? (int) vo.get_int_member ("byteStride") : 0;
            unowned uint8[] all = buffers[buffer].get_data ();
            return all[off:off + len];
        }

        private static double[] read_floats (Json.Array accs, Json.Array views, Gee.List<Bytes> buffers, int acc, int comps) throws Error {
            var ao = accs.get_object_element (acc);
            int count = (int) ao.get_int_member ("count");
            if (ao.get_int_member ("componentType") != 5126) throw new MeshIOError.UNSUPPORTED (_("Only float vertex data is supported"));
            int stride;
            var d = view_data (views, buffers, (int) ao.get_int_member ("bufferView"), out stride);
            int off = ao.has_member ("byteOffset") ? (int) ao.get_int_member ("byteOffset") : 0;
            if (stride == 0) stride = comps * 4;
            var r = new double[count * comps];
            for (int i = 0; i < count; i++) {
                for (int c = 0; c < comps; c++) {
                    int p = off + i * stride + c * 4;
                    uint32 bits = u32 (d, p);
                    float f = 0;
                    Memory.copy (&f, &bits, 4);
                    r[i * comps + c] = f;
                }
            }
            return r;
        }

        private static int[] read_ints (Json.Array accs, Json.Array views, Gee.List<Bytes> buffers, int acc) throws Error {
            var ao = accs.get_object_element (acc);
            int count = (int) ao.get_int_member ("count");
            int type = (int) ao.get_int_member ("componentType");
            int stride;
            var d = view_data (views, buffers, (int) ao.get_int_member ("bufferView"), out stride);
            int off = ao.has_member ("byteOffset") ? (int) ao.get_int_member ("byteOffset") : 0;
            int size = type == 5125 ? 4 : (type == 5123 ? 2 : 1);
            if (stride == 0) stride = size;
            var r = new int[count];
            for (int i = 0; i < count; i++) {
                int p = off + i * stride;
                if (size == 4) r[i] = (int) u32 (d, p);
                else if (size == 2) r[i] = d[p] | (d[p + 1] << 8);
                else r[i] = d[p];
            }
            return r;
        }
    }
}
