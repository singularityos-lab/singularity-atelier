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

        public const string[] FIELDS = { "height", "bust", "waist", "hip", "neck", "across_back", "arm", "upper_arm", "wrist", "inseam", "thigh", "knee", "ankle", "back_waist" };

        public double field (string name) {
            switch (name) {
                case "height": return height;
                case "bust": return bust;
                case "waist": return waist;
                case "hip": return hip;
                case "neck": return neck;
                case "across_back": return across_back;
                case "arm": return arm;
                case "upper_arm": return upper_arm;
                case "wrist": return wrist;
                case "inseam": return inseam;
                case "thigh": return thigh;
                case "knee": return knee;
                case "ankle": return ankle;
                case "back_waist": return back_waist;
                default: return 0;
            }
        }

        public void set_field (string name, double v) {
            switch (name) {
                case "height": height = v; break;
                case "bust": bust = v; break;
                case "waist": waist = v; break;
                case "hip": hip = v; break;
                case "neck": neck = v; break;
                case "across_back": across_back = v; break;
                case "arm": arm = v; break;
                case "upper_arm": upper_arm = v; break;
                case "wrist": wrist = v; break;
                case "inseam": inseam = v; break;
                case "thigh": thigh = v; break;
                case "knee": knee = v; break;
                case "ankle": ankle = v; break;
                case "back_waist": back_waist = v; break;
            }
        }

        public static string field_label (string name) {
            switch (name) {
                case "height": return _("Height");
                case "bust": return _("Bust");
                case "waist": return _("Waist");
                case "hip": return _("Hips");
                case "neck": return _("Neck");
                case "across_back": return _("Across Back");
                case "arm": return _("Arm Length");
                case "upper_arm": return _("Upper Arm");
                case "wrist": return _("Wrist");
                case "inseam": return _("Inseam");
                case "thigh": return _("Thigh");
                case "knee": return _("Knee");
                case "ankle": return _("Ankle");
                default: return _("Back Length");
            }
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

    public class BodyData {
        public int nv;
        public int nrender;
        public uint[] triangles = {};
        public string[] bone_names = {};
        public int[] bone_parent = {};
        public int[] bone_head = {};
        public int[] bone_tail = {};
        public int[] joint_start = {};
        public int[] joint_verts = {};
        public uint8[] skin_bone = {};
        public uint8[] skin_weight = {};
        public uint8[] part = {};
        private HashTable<string, int> dense_at = new HashTable<string, int> (str_hash, str_equal);
        private float[] dense = {};
        private HashTable<string, int> sparse_at = new HashTable<string, int> (str_hash, str_equal);
        private int[] sparse_count = {};
        private uint16[] sparse_index = {};
        private float[] sparse_delta = {};
        private int[] sparse_offset = {};
        public string[] proxy_names = {};
        public int[] proxy_first = {};
        public int[] proxy_count = {};
        public int[] proxy_tri_first = {};
        public int[] proxy_tri_count = {};
        public int[] proxy_ref = {};
        public float[] proxy_den = {};
        public int[] proxy_vert = {};
        public float[] proxy_weight = {};
        public uint[] proxy_tris = {};
        public bool[] brow = {};
        private static BodyData? instance;

        public const uint8 PART_TORSO = 0;
        public const uint8 PART_ARM = 1;
        public const uint8 PART_LEG_L = 2;
        public const uint8 PART_LEG_R = 3;
        public const uint8 PART_HEAD = 4;

        public static BodyData get_default () {
            if (instance == null) {
                instance = new BodyData ();
                try {
                    var bytes = resources_lookup_data ("/dev/sinty/atelier/avatar/body.bin", ResourceLookupFlags.NONE);
                    instance.parse (bytes.get_data ());
                } catch (Error e) {
                    critical ("avatar data: %s", e.message);
                }
            }
            return instance;
        }

        public static BodyData from_file (string path) throws Error {
            uint8[] raw;
            FileUtils.get_data (path, out raw);
            instance = new BodyData ();
            instance.parse (raw);
            return instance;
        }

        private static uint32 u32 (uint8[] d, ref int o) {
            uint32 v = d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | ((uint32) d[o + 3] << 24);
            o += 4;
            return v;
        }

        private static int u16 (uint8[] d, ref int o) {
            int v = d[o] | (d[o + 1] << 8);
            o += 2;
            return v;
        }

        private static int i16 (uint8[] d, ref int o) {
            int v = u16 (d, ref o);
            return v >= 32768 ? v - 65536 : v;
        }

        private static float f32 (uint8[] d, ref int o) {
            float v = 0;
            Memory.copy (&v, &d[o], 4);
            o += 4;
            return v;
        }

        private static string str (uint8[] d, ref int o) {
            int n = d[o++];
            var sb = new StringBuilder.sized (n);
            for (int i = 0; i < n; i++) sb.append_c ((char) d[o + i]);
            o += n;
            return sb.str;
        }

        private void parse (uint8[] d) {
            int o = 4;
            if (d.length < 40 || d[0] != 'A' || d[1] != 'T' || d[2] != 'A' || d[3] != 'V') return;
            int version = (int) u32 (d, ref o);
            nv = (int) u32 (d, ref o);
            nrender = (int) u32 (d, ref o);
            int nq = (int) u32 (d, ref o);
            int nb = (int) u32 (d, ref o);
            int nj = (int) u32 (d, ref o);
            int nd = (int) u32 (d, ref o);
            int ns = (int) u32 (d, ref o);
            triangles = new uint[nq * 6];
            for (int q = 0; q < nq; q++) {
                uint a = u16 (d, ref o), b = u16 (d, ref o), c = u16 (d, ref o), e = u16 (d, ref o);
                triangles[q * 6] = a;
                triangles[q * 6 + 1] = b;
                triangles[q * 6 + 2] = c;
                triangles[q * 6 + 3] = a;
                triangles[q * 6 + 4] = c;
                triangles[q * 6 + 5] = e;
            }
            bone_names = new string[nb];
            bone_parent = new int[nb];
            bone_head = new int[nb];
            bone_tail = new int[nb];
            for (int i = 0; i < nb; i++) {
                bone_names[i] = str (d, ref o);
                bone_parent[i] = i16 (d, ref o);
                bone_head[i] = u16 (d, ref o);
                bone_tail[i] = u16 (d, ref o);
            }
            joint_start = new int[nj + 1];
            var jv = new GenericArray<int> ();
            for (int i = 0; i < nj; i++) {
                joint_start[i] = jv.length;
                int n = d[o++];
                for (int k = 0; k < n; k++) jv.add (u16 (d, ref o));
            }
            joint_start[nj] = jv.length;
            joint_verts = new int[jv.length];
            for (int i = 0; i < jv.length; i++) joint_verts[i] = jv[i];
            skin_bone = d[o:o + nv * 4];
            o += nv * 4;
            skin_weight = d[o:o + nv * 4];
            o += nv * 4;
            dense = new float[nd * nv * 3];
            for (int i = 0; i < nd; i++) {
                string name = str (d, ref o);
                bool absolute = d[o++] == 1;
                float scale = f32 (d, ref o);
                int at = i * nv * 3;
                if (absolute) {
                    Memory.copy (&dense[at], &d[o], nv * 12);
                    o += nv * 12;
                } else {
                    for (int k = 0; k < nv * 3; k++) dense[at + k] = i16 (d, ref o) * scale;
                }
                dense_at[name] = at;
            }
            sparse_count = new int[ns];
            sparse_offset = new int[ns];
            var idx = new GenericArray<int> ();
            var del = new GenericArray<float?> ();
            for (int i = 0; i < ns; i++) {
                string name = str (d, ref o);
                int n = (int) u32 (d, ref o);
                float scale = f32 (d, ref o);
                sparse_at[name] = i;
                sparse_count[i] = n;
                sparse_offset[i] = idx.length;
                for (int k = 0; k < n; k++) idx.add (u16 (d, ref o));
                for (int k = 0; k < n * 3; k++) del.add (i16 (d, ref o) * scale);
            }
            sparse_index = new uint16[idx.length];
            for (int i = 0; i < idx.length; i++) sparse_index[i] = (uint16) idx[i];
            sparse_delta = new float[del.length];
            for (int i = 0; i < del.length; i++) sparse_delta[i] = del[i];
            brow = new bool[nv];
            if (version >= 2) {
                int np = (int) u32 (d, ref o);
                string[] l_names = {};
                int[] l_first = {};
                int[] l_count = {};
                int[] l_tri_first = {};
                int[] l_tri_count = {};
                int[] l_ref = {};
                float[] l_den = {};
                var verts = new GenericArray<int> ();
                var weights = new GenericArray<float?> ();
                var tris = new GenericArray<uint> ();
                for (int i = 0; i < np; i++) {
                    l_names += str (d, ref o);
                    int count = (int) u32 (d, ref o);
                    int nt = (int) u32 (d, ref o);
                    l_first += verts.length / 3;
                    l_count += count;
                    l_tri_first += tris.length;
                    l_tri_count += nt * 3;
                    for (int a = 0; a < 3; a++) {
                        l_ref += u16 (d, ref o);
                        l_ref += u16 (d, ref o);
                        l_den += f32 (d, ref o);
                    }
                    for (int k = 0; k < count; k++) {
                        for (int q = 0; q < 3; q++) verts.add (u16 (d, ref o));
                        for (int q = 0; q < 6; q++) weights.add (f32 (d, ref o));
                    }
                    for (int k = 0; k < nt * 3; k++) tris.add ((uint) u16 (d, ref o));
                }
                proxy_names = l_names;
                proxy_first = l_first;
                proxy_count = l_count;
                proxy_tri_first = l_tri_first;
                proxy_tri_count = l_tri_count;
                proxy_ref = l_ref;
                proxy_den = l_den;
                proxy_vert = new int[verts.length];
                for (int i = 0; i < verts.length; i++) proxy_vert[i] = verts[i];
                proxy_weight = new float[weights.length];
                for (int i = 0; i < weights.length; i++) proxy_weight[i] = weights[i];
                proxy_tris = new uint[tris.length];
                for (int i = 0; i < tris.length; i++) proxy_tris[i] = tris[i];
                int nm = (int) u32 (d, ref o);
                for (int i = 0; i < nm; i++) brow[u16 (d, ref o)] = true;
            }
            classify ();
            orient ();
        }

        private void orient () {
            if (!dense_at.contains ("female")) return;
            int at = dense_at["female"];
            double volume = 0;
            for (int t = 0; t + 2 < triangles.length; t += 3) {
                int a = at + (int) triangles[t] * 3, b = at + (int) triangles[t + 1] * 3, c = at + (int) triangles[t + 2] * 3;
                volume += dense[a] * (dense[b + 1] * dense[c + 2] - dense[b + 2] * dense[c + 1])
                    - dense[a + 1] * (dense[b] * dense[c + 2] - dense[b + 2] * dense[c])
                    + dense[a + 2] * (dense[b] * dense[c + 1] - dense[b + 1] * dense[c]);
            }
            if (volume >= 0) return;
            for (int t = 0; t + 2 < triangles.length; t += 3) {
                uint k = triangles[t + 1];
                triangles[t + 1] = triangles[t + 2];
                triangles[t + 2] = k;
            }
        }

        private void classify () {
            int nb = bone_names.length;
            var bone_part = new uint8[nb];
            for (int i = 0; i < nb; i++) {
                string n = bone_names[i];
                uint8 p = bone_parent[i] >= 0 ? bone_part[bone_parent[i]] : PART_TORSO;
                if (n.has_prefix ("upperarm01")) p = PART_ARM;
                else if (n == "upperleg01.L") p = PART_LEG_L;
                else if (n == "upperleg01.R") p = PART_LEG_R;
                else if (n == "neck02") p = PART_HEAD;
                bone_part[i] = p;
            }
            part = new uint8[nv];
            for (int v = 0; v < nv; v++) part[v] = bone_part[skin_bone[v * 4]];
        }

        public bool valid () {
            return nv > 0;
        }

        public int bone (string name) {
            for (int i = 0; i < bone_names.length; i++) if (bone_names[i] == name) return i;
            return -1;
        }

        public void add_dense (float[] pos, string name, double w) {
            if (w == 0 || !dense_at.contains (name)) return;
            int at = dense_at[name];
            float k = (float) w;
            for (int i = 0; i < nv * 3; i++) pos[i] += dense[at + i] * k;
        }

        public void add_sparse (float[] pos, string name, double w) {
            if (w == 0 || !sparse_at.contains (name)) return;
            int t = sparse_at[name];
            int off = sparse_offset[t];
            float k = (float) w;
            for (int i = 0; i < sparse_count[t]; i++) {
                int v = sparse_index[off + i] * 3;
                int s = (off + i) * 3;
                pos[v] += sparse_delta[s] * k;
                pos[v + 1] += sparse_delta[s + 1] * k;
                pos[v + 2] += sparse_delta[s + 2] * k;
            }
        }
    }

    public class BodyShape {
        public string gender = "female";
        public double weight;
        public double muscle;
        public double stature;
        public double cup;
        public double scale = 1;
        public HashTable<string, double?> measure = new HashTable<string, double?> (str_hash, str_equal);

        public const string[] MEASURES = {
            "bust-circ", "underbust-circ", "waist-circ", "hips-circ", "neck-circ", "upperarm-circ", "wrist-circ", "thigh-circ", "knee-circ",
            "calf-circ", "ankle-circ", "shoulder-dist", "napetowaist-dist", "waisttohip-dist", "upperarm-length", "lowerarm-length",
            "upperleg-height", "lowerleg-height", "neck-height", "frontchest-dist"
        };

        public double get_measure (string name) {
            return measure.contains (name) ? measure[name] : 0;
        }

        public BodyShape copy () {
            var s = new BodyShape ();
            s.gender = gender;
            s.weight = weight;
            s.muscle = muscle;
            s.stature = stature;
            s.cup = cup;
            s.scale = scale;
            measure.foreach ((k, v) => s.measure[k] = v);
            return s;
        }

        public string key () {
            var sb = new StringBuilder ();
            sb.append_printf ("%s %.4f %.4f %.4f %.4f %.5f", gender, weight, muscle, stature, cup, scale);
            foreach (unowned string m in MEASURES) sb.append_printf (" %.4f", get_measure (m));
            return sb.str;
        }
    }

    public class BodyPose {
        public string id = "a-pose";
        public double arm = 42;
        public double arm_forward;
        public double elbow = 6;
        public double leg = 6;

        public static BodyPose named (string id) {
            var p = new BodyPose ();
            p.id = id;
            switch (id) {
                case "t-pose":
                    p.arm = 88;
                    break;
                case "relaxed":
                    p.arm = 16;
                    p.elbow = 10;
                    p.leg = 3;
                    break;
                case "walk":
                    p.arm = 14;
                    p.arm_forward = 18;
                    p.elbow = 18;
                    p.leg = 4;
                    break;
                default:
                    p.id = "a-pose";
                    break;
            }
            return p;
        }

        public static string[] ids () {
            return { "a-pose", "t-pose", "relaxed", "walk" };
        }

        public static string label (string id) {
            switch (id) {
                case "t-pose": return _("T-Pose");
                case "relaxed": return _("Relaxed");
                case "walk": return _("Walking");
                default: return _("A-Pose");
            }
        }
    }

    public class BodyMeasures {
        public double height;
        public double bust;
        public double underbust;
        public double waist;
        public double hip;
        public double neck;
        public double upper_arm;
        public double wrist;
        public double thigh;
        public double knee;
        public double calf;
        public double ankle;
        public double shoulder_width;
        public double arm;
        public double inseam;
        public double back_waist;
        public double waist_hip;
        public double y_bust;
        public double y_waist;
        public double y_hip;
        public double y_crotch;
        public double y_neck;
        public double y_shoulder;
        public double y_knee;
        public double y_ankle;
    }

    public class Body {
        public BodyShape shape;
        public BodyPose pose;
        public float[] rest = {};
        public float[] posed = {};
        public float[] joints = {};
        public float[] posed_joints = {};
        public BodyMeasures measures;
        public Scene.Mesh mesh;
        public string hair = "";
        public Rgba hair_color = Rgba (0.20, 0.13, 0.10, 1);
        public uint[] solid_triangles = {};
        public int solid_vertices;
        public Gee.ArrayList<Scene.Mesh> extras = new Gee.ArrayList<Scene.Mesh> ();
        private BodyData data;

        public static Body build (BodyShape shape, BodyPose pose, string hair = "", Rgba? hair_color = null) {
            var b = new Body ();
            b.hair = hair;
            if (hair_color != null) b.hair_color = hair_color;
            b.data = BodyData.get_default ();
            b.shape = shape;
            b.pose = pose;
            b.morph ();
            b.measures = b.measure ();
            b.smooth_cover ();
            b.apply_pose ();
            b.make_mesh ();
            return b;
        }

        public Vec3 joint (string name, bool tail = false, bool in_pose = true) {
            int bi = data.bone (name);
            if (bi < 0) return Vec3.zero ();
            int j = (tail ? data.bone_tail[bi] : data.bone_head[bi]) * 3;
            unowned float[] src = in_pose ? posed_joints : joints;
            return Vec3 (src[j], src[j + 1], src[j + 2]);
        }

        private static void grid (double v, out double lo, out double mid, out double hi) {
            v = v.clamp (-1, 1);
            lo = double.max (0, -v);
            hi = double.max (0, v);
            mid = 1 - v.abs ();
        }

        private void morph () {
            int nv = data.nv;
            rest = new float[nv * 3];
            if (!data.valid ()) return;
            string g = shape.gender == "male" ? "male" : "female";
            data.add_dense (rest, g, 1);
            double m0, m1, m2, w0, w1, w2;
            grid (shape.muscle, out m0, out m1, out m2);
            grid (shape.weight, out w0, out w1, out w2);
            double[] mw = { m0, m1, m2 };
            double[] ww = { w0, w1, w2 };
            string[] mn = { "minmuscle", "averagemuscle", "maxmuscle" };
            string[] wn = { "minweight", "averageweight", "maxweight" };
            for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) {
                if (i == 1 && j == 1) continue;
                data.add_dense (rest, "%s:%s-%s".printf (g, mn[i], wn[j]), mw[i] * ww[j]);
            }
            data.add_dense (rest, g + (shape.stature < 0 ? ":minheight" : ":maxheight"), shape.stature.abs ().clamp (0, 1));
            if (g == "female") data.add_dense (rest, shape.cup < 0 ? "female:mincup" : "female:maxcup", shape.cup.abs ().clamp (0, 1.5));
            foreach (unowned string name in BodyShape.MEASURES) {
                double v = shape.get_measure (name);
                if (v != 0) data.add_sparse (rest, name + (v < 0 ? "-decr" : "-incr"), v.abs ());
            }
            float s = (float) shape.scale;
            float miny = float.MAX;
            for (int i = 0; i < data.nrender; i++) if (rest[i * 3 + 1] < miny) miny = rest[i * 3 + 1];
            for (int i = 0; i < nv; i++) {
                rest[i * 3] *= s;
                rest[i * 3 + 1] = (rest[i * 3 + 1] - miny) * s;
                rest[i * 3 + 2] *= s;
            }
            joints = joint_positions (rest);
        }

        private void smooth_cover () {
            if (shape.gender == "male") return;
            unowned uint[] tri = data.triangles;
            int n = data.nrender;
            double front = joint ("spine02", false, false).z + 45 * shape.scale;
            var weight = new float[n];
            for (int i = 0; i < n; i++) {
                if (data.part[i] != BodyData.PART_TORSO) continue;
                double y = rest[i * 3 + 1];
                double band = double.min (y - (measures.y_bust - 75), (measures.y_bust + 55) - y) / 20;
                weight[i] = (float) (band.clamp (0, 1) * ((rest[i * 3 + 2] - front) / 20).clamp (0, 1));
            }
            var sum = new float[n * 3];
            var count = new int[n];
            for (int pass = 0; pass < 5; pass++) {
                Memory.set (sum, 0, n * 3 * sizeof (float));
                Memory.set (count, 0, n * sizeof (int));
                for (int t = 0; t + 2 < tri.length; t += 3) {
                    if (weight[tri[t]] == 0 && weight[tri[t + 1]] == 0 && weight[tri[t + 2]] == 0) continue;
                    for (int e = 0; e < 3; e++) {
                        uint a = tri[t + e], b = tri[t + (e + 1) % 3];
                        sum[a * 3] += rest[b * 3];
                        sum[a * 3 + 1] += rest[b * 3 + 1];
                        sum[a * 3 + 2] += rest[b * 3 + 2];
                        count[a]++;
                    }
                }
                for (int i = 0; i < n; i++) {
                    if (weight[i] == 0 || count[i] == 0) continue;
                    float k = weight[i] * 0.5f;
                    for (int c = 0; c < 3; c++) rest[i * 3 + c] += (sum[i * 3 + c] / count[i] - rest[i * 3 + c]) * k;
                }
            }
        }

        private float[] joint_positions (float[] pos) {
            int nj = data.joint_start.length - 1;
            var out_j = new float[nj * 3];
            for (int j = 0; j < nj; j++) {
                double x = 0, y = 0, z = 0;
                int a = data.joint_start[j], b = data.joint_start[j + 1];
                for (int k = a; k < b; k++) {
                    int v = data.joint_verts[k] * 3;
                    x += pos[v];
                    y += pos[v + 1];
                    z += pos[v + 2];
                }
                int n = int.max (1, b - a);
                out_j[j * 3] = (float) (x / n);
                out_j[j * 3 + 1] = (float) (y / n);
                out_j[j * 3 + 2] = (float) (z / n);
            }
            return out_j;
        }

        private static void mat_identity (double[] m) {
            for (int i = 0; i < 12; i++) m[i] = 0;
            m[0] = m[5] = m[10] = 1;
        }

        private static void mat_rotation (double[] m, Vec3 pivot, Vec3 axis, double angle) {
            var a = axis.normalized ();
            double c = Math.cos (angle), s = Math.sin (angle), t = 1 - c;
            m[0] = t * a.x * a.x + c;
            m[1] = t * a.x * a.y - s * a.z;
            m[2] = t * a.x * a.z + s * a.y;
            m[4] = t * a.x * a.y + s * a.z;
            m[5] = t * a.y * a.y + c;
            m[6] = t * a.y * a.z - s * a.x;
            m[8] = t * a.x * a.z - s * a.y;
            m[9] = t * a.y * a.z + s * a.x;
            m[10] = t * a.z * a.z + c;
            m[3] = pivot.x - (m[0] * pivot.x + m[1] * pivot.y + m[2] * pivot.z);
            m[7] = pivot.y - (m[4] * pivot.x + m[5] * pivot.y + m[6] * pivot.z);
            m[11] = pivot.z - (m[8] * pivot.x + m[9] * pivot.y + m[10] * pivot.z);
        }

        private static void mat_mul (double[] o, double[] a, double[] b) {
            var r = new double[12];
            for (int i = 0; i < 3; i++) {
                for (int j = 0; j < 4; j++) {
                    r[i * 4 + j] = a[i * 4] * b[j] + a[i * 4 + 1] * b[4 + j] + a[i * 4 + 2] * b[8 + j] + (j == 3 ? a[i * 4 + 3] : 0);
                }
            }
            for (int i = 0; i < 12; i++) o[i] = r[i];
        }

        private static Vec3 mat_apply (double[] m, Vec3 p) {
            return Vec3 (m[0] * p.x + m[1] * p.y + m[2] * p.z + m[3], m[4] * p.x + m[5] * p.y + m[6] * p.z + m[7], m[8] * p.x + m[9] * p.y + m[10] * p.z + m[11]);
        }

        private void apply_pose () {
            int nv = data.nv, nb = data.bone_names.length;
            posed = new float[nv * 3];
            posed_joints = new float[joints.length];
            if (!data.valid ()) return;
            var local = new double[nb, 12];
            var global = new double[nb * 12];
            var tmp = new double[12];
            var has_local = new bool[nb];
            for (int side = 0; side < 2; side++) {
                string sfx = side == 0 ? ".L" : ".R";
                double sign = side == 0 ? 1 : -1;
                var sh = joint ("upperarm01" + sfx, false, false);
                var el = joint ("lowerarm01" + sfx, false, false);
                var wr = joint ("wrist" + sfx, false, false);
                var dir = wr.sub (sh);
                double rest_angle = Math.atan2 (dir.x.abs (), -dir.y) * 180 / Math.PI;
                double delta = (pose.arm - rest_angle) * Math.PI / 180;
                set_local (local, has_local, "upperarm01" + sfx, sh, Vec3 (0, 0, 1), delta * 0.82 * sign);
                set_local (local, has_local, "shoulder01" + sfx, joint ("shoulder01" + sfx, false, false), Vec3 (0, 0, 1), delta * 0.18 * sign);
                if (pose.arm_forward != 0) {
                    double f = pose.arm_forward * Math.PI / 180 * (side == 0 ? 1 : -1);
                    var m2 = new double[12];
                    mat_rotation (m2, sh, Vec3 (1, 0, 0), -f);
                    int bi = data.bone ("upperarm01" + sfx);
                    var cur = row (local, bi);
                    mat_mul (cur, m2, cur);
                    put_row (local, bi, cur);
                }
                var upper = el.sub (sh).normalized ();
                var fore = wr.sub (el).normalized ();
                var hinge = upper.cross (fore);
                if (hinge.length () > 1e-6) {
                    double bend = Math.acos (upper.dot (fore).clamp (-1, 1));
                    set_local (local, has_local, "lowerarm01" + sfx, el, hinge.normalized (), pose.elbow * Math.PI / 180 - bend);
                }
                var hip = joint ("upperleg01" + sfx, false, false);
                var foot = joint ("foot" + sfx, false, false);
                var ld = foot.sub (hip);
                double leg_rest = Math.atan2 (ld.x.abs (), -ld.y) * 180 / Math.PI;
                double ldelta = (pose.leg - leg_rest) * Math.PI / 180;
                if (pose.id == "walk") {
                    var m2 = new double[12];
                    mat_rotation (m2, hip, Vec3 (1, 0, 0), (side == 0 ? -1 : 1) * 14 * Math.PI / 180);
                    set_local (local, has_local, "upperleg01" + sfx, hip, Vec3 (0, 0, 1), ldelta * sign);
                    int bi = data.bone ("upperleg01" + sfx);
                    var cur = row (local, bi);
                    mat_mul (cur, m2, cur);
                    put_row (local, bi, cur);
                } else {
                    set_local (local, has_local, "upperleg01" + sfx, hip, Vec3 (0, 0, 1), ldelta * sign);
                }
            }
            for (int b = 0; b < nb; b++) {
                var g = new double[12];
                if (has_local[b]) g = row (local, b);
                else mat_identity (g);
                int p = data.bone_parent[b];
                if (p >= 0) {
                    for (int k = 0; k < 12; k++) tmp[k] = global[p * 12 + k];
                    mat_mul (g, tmp, g);
                }
                for (int k = 0; k < 12; k++) global[b * 12 + k] = g[k];
            }
            unowned uint8[] sb = data.skin_bone;
            unowned uint8[] sw = data.skin_weight;
            for (int v = 0; v < nv; v++) {
                double x = rest[v * 3], y = rest[v * 3 + 1], z = rest[v * 3 + 2];
                double ox = 0, oy = 0, oz = 0, total = 0;
                for (int k = 0; k < 4; k++) {
                    int w8 = sw[v * 4 + k];
                    if (w8 == 0) continue;
                    double w = w8 / 255.0;
                    int m = sb[v * 4 + k] * 12;
                    ox += w * (global[m] * x + global[m + 1] * y + global[m + 2] * z + global[m + 3]);
                    oy += w * (global[m + 4] * x + global[m + 5] * y + global[m + 6] * z + global[m + 7]);
                    oz += w * (global[m + 8] * x + global[m + 9] * y + global[m + 10] * z + global[m + 11]);
                    total += w;
                }
                if (total < 1e-6) {
                    ox = x;
                    oy = y;
                    oz = z;
                    total = 1;
                }
                posed[v * 3] = (float) (ox / total);
                posed[v * 3 + 1] = (float) (oy / total);
                posed[v * 3 + 2] = (float) (oz / total);
            }
            float miny = float.MAX;
            for (int i = 0; i < data.nrender; i++) if (posed[i * 3 + 1] < miny) miny = posed[i * 3 + 1];
            for (int i = 0; i < nv; i++) posed[i * 3 + 1] -= miny;
            posed_joints = joint_positions (posed);
        }

        private static double[] row (double[,] local, int b) {
            var r = new double[12];
            for (int k = 0; k < 12; k++) r[k] = local[b, k];
            return r;
        }

        private static void put_row (double[,] local, int b, double[] r) {
            for (int k = 0; k < 12; k++) local[b, k] = r[k];
        }

        private void set_local (double[,] local, bool[] has, string bone, Vec3 pivot, Vec3 axis, double angle) {
            int bi = data.bone (bone);
            if (bi < 0) return;
            var m = new double[12];
            mat_rotation (m, pivot, axis, angle);
            put_row (local, bi, m);
            has[bi] = true;
        }

        private void soften (float[] pos, int n) {
            unowned uint[] tri = data.triangles;
            var sum = new float[n * 3];
            var count = new int[n];
            double[] factors = { 0.5, -0.52, 0.5, -0.52 };
            foreach (double k in factors) {
                Memory.set (sum, 0, n * 3 * sizeof (float));
                Memory.set (count, 0, n * sizeof (int));
                for (int t = 0; t + 2 < tri.length; t += 3) {
                    for (int e = 0; e < 3; e++) {
                        uint a = tri[t + e], b = tri[t + (e + 1) % 3];
                        sum[a * 3] += pos[b * 3];
                        sum[a * 3 + 1] += pos[b * 3 + 1];
                        sum[a * 3 + 2] += pos[b * 3 + 2];
                        count[a]++;
                    }
                }
                for (int i = 0; i < n; i++) {
                    if (count[i] == 0 || data.part[i] == BodyData.PART_HEAD || data.part[i] == BodyData.PART_ARM) continue;
                    float f = (float) k;
                    for (int c = 0; c < 3; c++) pos[i * 3 + c] += (sum[i * 3 + c] / count[i] - pos[i * 3 + c]) * f;
                }
            }
        }

        private void make_mesh () {
            mesh = new Scene.Mesh ();
            mesh.name = "avatar";
            int n = data.nrender;
            soften (posed, n);
            mesh.positions = posed[0:n * 3];
            mesh.triangles = data.triangles;
            mesh.compute_normals ();
            mesh.material.color = Gdk.RGBA () { red = 0.80f, green = 0.63f, blue = 0.54f, alpha = 1 };
            mesh.material.roughness = 0.62;
            mesh.material.sheen = 0.12;
            split_eyes ();
            mesh.material.double_sided = false;
        }

        public void extent (double y, out double cx, out double cz, out double rx, out double rz) {
            double x0 = double.INFINITY, x1 = -double.INFINITY, z0 = double.INFINITY, z1 = -double.INFINITY;
            for (int i = 0; i < data.nrender; i++) {
                if (data.part[i] == BodyData.PART_ARM || (posed[i * 3 + 1] - y).abs () > 14) continue;
                double x = posed[i * 3], z = posed[i * 3 + 2];
                if (x < x0) x0 = x;
                if (x > x1) x1 = x;
                if (z < z0) z0 = z;
                if (z > z1) z1 = z;
            }
            if (x0 > x1) {
                cx = 0;
                cz = 0;
                rx = 150;
                rz = 110;
                return;
            }
            cx = (x0 + x1) / 2;
            cz = (z0 + z1) / 2;
            rx = (x1 - x0) / 2;
            rz = (z1 - z0) / 2;
        }

        private void split_eyes () {
            extras = new Gee.ArrayList<Scene.Mesh> ();
            int left = data.bone ("eye.L"), right = data.bone ("eye.R");
            if (left < 0 || right < 0) return;
            unowned uint[] tri = data.triangles;
            bool female = shape.gender != "male";
            int n0 = data.nrender;
            var low = new float[n0];
            var high = new float[n0];
            for (int i = 0; i < n0; i++) {
                double y = rest[i * 3 + 1];
                uint8 where = data.part[i];
                bool limb = where == BodyData.PART_ARM || where == BodyData.PART_HEAD;
                low[i] = limb ? -20 : (float) double.min (y - (measures.y_crotch - 30), (measures.y_hip + 85) - y);
                high[i] = !female || where != BodyData.PART_TORSO ? -20 : (float) double.min (y - (measures.y_bust - 80), (measures.y_bust + 62) - y);
            }
            solid_triangles = data.triangles;
            solid_vertices = n0;
            var grown = new Grow (mesh.positions);
            uint[] wear = {};
            uint[] skin = {};
            uint[] brows = {};
            uint[] white = {};
            uint[] iris = {};
            uint[] pupil = {};
            var pole = new int[2] { -1, -1 };
            for (int i = 0; i < data.nrender; i++) {
                int b = data.skin_bone[i * 4];
                int e = b == left ? 0 : (b == right ? 1 : -1);
                if (e < 0 || data.skin_weight[i * 4] < 250) continue;
                if (pole[e] < 0 || posed[i * 3 + 2] > posed[pole[e] * 3 + 2]) pole[e] = i;
            }
            double size = shape.scale;
            for (int t = 0; t + 2 < tri.length; t += 3) {
                int b = data.skin_bone[tri[t] * 4];
                int e = b == left ? 0 : (b == right ? 1 : -1);
                if (e < 0 || data.skin_weight[tri[t] * 4] < 250 || pole[e] < 0) {
                    bool hairy = data.brow[tri[t]] && data.brow[tri[t + 1]] && data.brow[tri[t + 2]];
                    if (hairy) {
                        for (int k = 0; k < 3; k++) brows += tri[t + k];
                        continue;
                    }
                    var inside = new GenericArray<uint> ();
                    var outside = new GenericArray<uint> ();
                    var rest_in = new GenericArray<uint> ();
                    var rest_out = new GenericArray<uint> ();
                    grown.clip ({ tri[t], tri[t + 1], tri[t + 2] }, low, inside, outside);
                    for (int q = 0; q < inside.length; q++) wear += inside[q];
                    for (int q = 0; q + 2 < outside.length; q += 3) grown.clip ({ outside[q], outside[q + 1], outside[q + 2] }, high, rest_in, rest_out);
                    for (int q = 0; q < rest_in.length; q++) wear += rest_in[q];
                    for (int q = 0; q < rest_out.length; q++) skin += rest_out[q];
                    continue;
                }
                double far = 0;
                for (int k = 0; k < 3; k++) {
                    uint v = tri[t + k];
                    far = double.max (far, Math.hypot (posed[v * 3] - posed[pole[e] * 3], posed[v * 3 + 1] - posed[pole[e] * 3 + 1]));
                }
                for (int k = 0; k < 3; k++) {
                    if (far < 2.4 * size) pupil += tri[t + k];
                    else if (far < 6.4 * size) iris += tri[t + k];
                    else white += tri[t + k];
                }
            }
            mesh.positions = grown.positions ();
            mesh.triangles = skin;
            uint[] all = {};
            foreach (uint v in skin) all += v;
            foreach (uint v in wear) all += v;
            foreach (uint v in brows) all += v;
            foreach (uint v in white) all += v;
            foreach (uint v in iris) all += v;
            foreach (uint v in pupil) all += v;
            mesh.triangles = all;
            mesh.compute_normals ();
            mesh.triangles = skin;
            extras.add (part (white, 0.93f, 0.92f, 0.90f, 0.25));
            extras.add (part (iris, 0.30f, 0.21f, 0.14f, 0.2));
            extras.add (part (pupil, 0.03f, 0.03f, 0.03f, 0.15));
            extras.add (part (wear, 0.87f, 0.86f, 0.84f, 0.85));
            var brow_mesh = part (brows, (float) (hair_color.r * 0.85), (float) (hair_color.g * 0.85), (float) (hair_color.b * 0.85), 0.8);
            extras.add (brow_mesh);
            add_hair ();
        }

        public static string[] hair_styles () {
            return BodyData.get_default ().proxy_names;
        }

        private void add_hair () {
            int index = -1;
            for (int i = 0; i < data.proxy_names.length; i++) if (data.proxy_names[i] == hair) index = i;
            if (index < 0) return;
            int count = data.proxy_count[index], first = data.proxy_first[index];
            var factor = new double[3];
            for (int a = 0; a < 3; a++) {
                int ra = data.proxy_ref[(index * 3 + a) * 2], rb = data.proxy_ref[(index * 3 + a) * 2 + 1];
                float den = data.proxy_den[index * 3 + a];
                factor[a] = den > 0 ? ((double) rest[ra * 3 + a] - rest[rb * 3 + a]).abs () / den : 100 * shape.scale;
            }
            var m = new Scene.Mesh ();
            m.name = "hair";
            m.positions = new float[count * 3];
            for (int k = 0; k < count; k++) {
                int v = (first + k) * 3, w = (first + k) * 6;
                for (int a = 0; a < 3; a++) {
                    double at = 0;
                    for (int q = 0; q < 3; q++) at += posed[data.proxy_vert[v + q] * 3 + a] * data.proxy_weight[w + q];
                    m.positions[k * 3 + a] = (float) (at + data.proxy_weight[w + 3 + a] * factor[a]);
                }
            }
            m.triangles = data.proxy_tris[data.proxy_tri_first[index]:data.proxy_tri_first[index] + data.proxy_tri_count[index]];
            m.compute_normals ();
            m.pickable = false;
            m.material.color = Gdk.RGBA () { red = (float) hair_color.r, green = (float) hair_color.g, blue = (float) hair_color.b, alpha = 1 };
            m.material.roughness = 0.55;
            m.material.sheen = 0.5;
            m.material.double_sided = true;
            extras.add (m);
        }

        private Scene.Mesh part (uint[] triangles, float r, float g, float b, double roughness) {
            var m = new Scene.Mesh ();
            m.positions = mesh.positions;
            m.normals = mesh.normals;
            m.triangles = triangles;
            m.pickable = false;
            m.material.color = Gdk.RGBA () { red = r, green = g, blue = b, alpha = 1 };
            m.material.roughness = roughness;
            m.material.double_sided = false;
            m.material.cast_shadow = false;
            return m;
        }

        public double girth (float[] pos, double y, int mask) {
            var cut = new Cut ();
            slice (pos, y, mask, cut);
            return hull_perimeter (cut.xs[0:cut.n], cut.zs[0:cut.n]);
        }

        private class Cut {
            public double[] xs = new double[256];
            public double[] zs = new double[256];
            public int n;

            public void push (double x, double z) {
                if (n == xs.length) {
                    xs.resize (n * 2);
                    zs.resize (n * 2);
                }
                xs[n] = x;
                zs[n] = z;
                n++;
            }
        }

        private void slice (float[] pos, double y, int mask, Cut cut) {
            unowned uint[] tri = data.triangles;
            unowned uint8[] part = data.part;
            float fy = (float) y;
            for (int t = 0; t + 2 < tri.length; t += 3) {
                uint a = tri[t], b = tri[t + 1], c = tri[t + 2];
                float ya = pos[a * 3 + 1], yb = pos[b * 3 + 1], yc = pos[c * 3 + 1];
                if ((ya < fy && yb < fy && yc < fy) || (ya > fy && yb > fy && yc > fy)) continue;
                if (((1 << part[a]) & mask) == 0 || ((1 << part[b]) & mask) == 0 || ((1 << part[c]) & mask) == 0) continue;
                uint[] v = { a, b, c };
                for (int e = 0; e < 3; e++) {
                    uint p = v[e], q = v[(e + 1) % 3];
                    float py = pos[p * 3 + 1], qy = pos[q * 3 + 1];
                    if ((py - fy) * (qy - fy) >= 0) continue;
                    float k = (fy - py) / (qy - py);
                    cut.push (pos[p * 3] + (pos[q * 3] - pos[p * 3]) * k, pos[p * 3 + 2] + (pos[q * 3 + 2] - pos[p * 3 + 2]) * k);
                }
            }
        }

        public static double hull_perimeter (double[] xs, double[] zs) {
            int n = xs.length;
            if (n < 3) return 0;
            var order = new int[n];
            for (int i = 0; i < n; i++) order[i] = i;
            for (int gap = n / 2; gap > 0; gap /= 2) {
                for (int i = gap; i < n; i++) {
                    int v = order[i];
                    int j = i;
                    while (j >= gap && xs[order[j - gap]] > xs[v]) {
                        order[j] = order[j - gap];
                        j -= gap;
                    }
                    order[j] = v;
                }
            }
            var hull = new int[2 * n + 2];
            int k = 0;
            for (int pass = 0; pass < 2; pass++) {
                int start = k;
                for (int s = 0; s < n; s++) {
                    int i = order[pass == 0 ? s : n - 1 - s];
                    while (k >= start + 2) {
                        int a = hull[k - 2], b = hull[k - 1];
                        double cr = (xs[b] - xs[a]) * (zs[i] - zs[a]) - (zs[b] - zs[a]) * (xs[i] - xs[a]);
                        if (cr <= 0) k--;
                        else break;
                    }
                    hull[k++] = i;
                }
                k--;
            }
            double per = 0;
            for (int i = 0; i < k; i++) {
                int a = hull[i], b = hull[(i + 1) % k];
                per += Math.hypot (xs[b] - xs[a], zs[b] - zs[a]);
            }
            return per;
        }

        private double crotch_height () {
            unowned uint[] tri = data.triangles;
            double best = double.INFINITY;
            double limit = joints[data.bone_head[data.bone ("spine05")] * 3 + 1];
            for (int t = 0; t + 2 < tri.length; t += 3) {
                uint[] v = { tri[t], tri[t + 1], tri[t + 2] };
                if (data.part[v[0]] == BodyData.PART_ARM || data.part[v[0]] == BodyData.PART_HEAD) continue;
                for (int e = 0; e < 3; e++) {
                    uint p = v[e], q = v[(e + 1) % 3];
                    float px = rest[p * 3], qx = rest[q * 3];
                    if (px * qx > 0) continue;
                    double k = (px - qx).abs () > 1e-9 ? px / (px - qx) : 0;
                    double y = rest[p * 3 + 1] + (rest[q * 3 + 1] - rest[p * 3 + 1]) * k;
                    if (y < limit + 200 && y < best) best = y;
                }
            }
            return best == double.INFINITY ? 0 : best;
        }

        public static BodyMeasures rest_measures (BodyShape shape) {
            var b = new Body ();
            b.data = BodyData.get_default ();
            b.shape = shape;
            b.morph ();
            return b.measure ();
        }

        public BodyMeasures measure () {
            var m = new BodyMeasures ();
            if (!data.valid ()) return m;
            float top = 0;
            for (int i = 0; i < data.nrender; i++) if (rest[i * 3 + 1] > top) top = rest[i * 3 + 1];
            m.height = top;
            int torso = (1 << BodyData.PART_TORSO) | (1 << BodyData.PART_LEG_L) | (1 << BodyData.PART_LEG_R) | (1 << BodyData.PART_HEAD);
            var sh_l = joint ("upperarm01.L", false, false);
            var sh_r = joint ("upperarm01.R", false, false);
            var neck = joint ("neck01", false, false);
            m.y_neck = neck.y;
            m.y_shoulder = (sh_l.y + sh_r.y) / 2;
            m.y_crotch = crotch_height ();
            m.inseam = m.y_crotch;
            double arm_pit = m.y_shoulder - 0.05 * m.height;
            double span = arm_pit - m.y_crotch;
            double best = 0;
            for (double y = m.y_crotch + span * 0.55; y <= arm_pit; y += 5) {
                double g = girth (rest, y, torso);
                if (g > best) {
                    best = g;
                    m.y_bust = y;
                }
            }
            m.bust = best;
            best = double.INFINITY;
            for (double y = m.y_crotch + span * 0.30; y <= m.y_bust - span * 0.10; y += 5) {
                double g = girth (rest, y, torso);
                if (g < best) {
                    best = g;
                    m.y_waist = y;
                }
            }
            m.waist = best;
            m.underbust = girth (rest, m.y_bust - (m.y_bust - m.y_waist) * 0.42, torso);
            best = 0;
            for (double y = m.y_crotch + 10; y <= m.y_waist - span * 0.08; y += 5) {
                double g = girth (rest, y, torso);
                if (g > best) {
                    best = g;
                    m.y_hip = y;
                }
            }
            m.hip = best;
            m.back_waist = m.y_neck - m.y_waist;
            m.waist_hip = m.y_waist - m.y_hip;
            var n2 = joint ("neck02", false, false);
            m.neck = girth (rest, (neck.y + n2.y) / 2 + 10, torso);
            int leg = 1 << BodyData.PART_LEG_L;
            m.thigh = girth (rest, m.y_crotch - 30, leg);
            var knee = joint ("lowerleg01.L", false, false);
            var ankle = joint ("foot.L", false, false);
            m.y_knee = knee.y;
            m.y_ankle = ankle.y;
            m.knee = girth (rest, knee.y, leg);
            best = 0;
            for (double y = ankle.y + (knee.y - ankle.y) * 0.45; y < knee.y - 20; y += 8) best = double.max (best, girth (rest, y, leg));
            m.calf = best;
            best = double.INFINITY;
            for (double y = ankle.y + 15; y < ankle.y + (knee.y - ankle.y) * 0.3; y += 6) {
                double g = girth (rest, y, leg);
                if (g > 0) best = double.min (best, g);
            }
            m.ankle = best == double.INFINITY ? 0 : best;
            var el = joint ("lowerarm01.L", false, false);
            var wr = joint ("wrist.L", false, false);
            m.arm = sh_l.distance (el) + el.distance (wr) + 0.027 * m.height;
            m.shoulder_width = sh_l.distance (sh_r);
            m.upper_arm = limb_girth (sh_l.lerp (el, 0.45), el.sub (sh_l));
            m.wrist = limb_girth (wr.lerp (el, 0.06), wr.sub (el));
            return m;
        }

        private double limb_girth (Vec3 at, Vec3 axis) {
            var n = axis.normalized ();
            var u = n.any_perpendicular ();
            var w = n.cross (u).normalized ();
            unowned uint[] tri = data.triangles;
            var xs = new double[0];
            var zs = new double[0];
            for (int t = 0; t + 2 < tri.length; t += 3) {
                uint[] v = { tri[t], tri[t + 1], tri[t + 2] };
                if (data.part[v[0]] != BodyData.PART_ARM || rest[v[0] * 3] < 0) continue;
                for (int e = 0; e < 3; e++) {
                    uint p = v[e], q = v[(e + 1) % 3];
                    var a = Vec3 (rest[p * 3], rest[p * 3 + 1], rest[p * 3 + 2]).sub (at);
                    var b = Vec3 (rest[q * 3], rest[q * 3 + 1], rest[q * 3 + 2]).sub (at);
                    double da = a.dot (n), db = b.dot (n);
                    if (da * db >= 0) continue;
                    var c = a.lerp (b, da / (da - db));
                    if (c.length () > 200) continue;
                    xs += c.dot (u);
                    zs += c.dot (w);
                }
            }
            return hull_perimeter (xs, zs);
        }
    }

    private class Grow {
        private float[] pos;
        private int used;
        private HashTable<int64?, uint> made = new HashTable<int64?, uint> (int64_hash, int64_equal);

        public Grow (float[] start) {
            pos = start;
            used = start.length;
        }

        public float[] positions () {
            return pos[0:used];
        }

        private static float value (float[] f, uint v) {
            return v < f.length ? f[v] : 0;
        }

        private uint cut (uint a, uint b, float fa, float fb) {
            int64 key = a < b ? ((int64) a << 32) | b : ((int64) b << 32) | a;
            if (made.contains (key)) return made[key];
            float t = fa / (fa - fb);
            if (used + 3 > pos.length) pos.resize (pos.length + 3072);
            for (int c = 0; c < 3; c++) pos[used + c] = pos[a * 3 + c] + (pos[b * 3 + c] - pos[a * 3 + c]) * t;
            uint id = used / 3;
            used += 3;
            made[key] = id;
            return id;
        }

        public void clip (uint[] t, float[] f, GenericArray<uint> inside, GenericArray<uint> outside) {
            float[] v = { value (f, t[0]), value (f, t[1]), value (f, t[2]) };
            int positive = 0;
            for (int i = 0; i < 3; i++) if (v[i] > 0) positive++;
            if (positive == 3 || positive == 0) {
                for (int i = 0; i < 3; i++) {
                    if (positive == 3) inside.add (t[i]);
                    else outside.add (t[i]);
                }
                return;
            }
            bool lone_in = positive == 1;
            int k = 0;
            for (int i = 0; i < 3; i++) if ((v[i] > 0) == lone_in) k = i;
            uint a = t[k], b = t[(k + 1) % 3], c = t[(k + 2) % 3];
            uint ab = cut (a, b, v[k], v[(k + 1) % 3]);
            uint ac = cut (a, c, v[k], v[(k + 2) % 3]);
            uint[] tip = { a, ab, ac };
            uint[] quad = { ab, b, c, ab, c, ac };
            foreach (uint q in tip) {
                if (lone_in) inside.add (q);
                else outside.add (q);
            }
            foreach (uint q in quad) {
                if (lone_in) outside.add (q);
                else inside.add (q);
            }
        }
    }

    public class BodyFit {
        private delegate double Probe (BodyMeasures m);

        private static double param (BodyShape s, string name) {
            return name == "cup" ? s.cup : s.get_measure (name);
        }

        private static void set_param (BodyShape s, string name, double v) {
            if (name == "cup") s.cup = v;
            else s.measure[name] = v;
        }

        private static void solve (BodyShape s, string[] names, double target, Probe probe, double lo, double hi) {
            var m = Body.rest_measures (s);
            double cur = probe (m);
            if ((cur - target).abs () < 1.0) return;
            double p = param (s, names[0]);
            double step = p < hi - 0.25 ? 0.25 : -0.25;
            foreach (unowned string n in names) set_param (s, n, p + step);
            double slope = (probe (Body.rest_measures (s)) - cur) / step;
            if (slope.abs () < 1e-6) {
                foreach (unowned string n in names) set_param (s, n, p);
                return;
            }
            double next = (p + (target - cur) / slope).clamp (lo, hi);
            foreach (unowned string n in names) set_param (s, n, next);
        }

        public static BodyShape fit (BodyDims d, string gender) {
            var s = new BodyShape ();
            s.gender = gender == "male" ? "male" : "female";
            if (!BodyData.get_default ().valid ()) return s;
            if (s.gender == "female") s.cup = 0.45;
            var m = Body.rest_measures (s);
            s.scale = d.height / double.max (1, m.height);
            double target = d.waist + d.hip;
            double w0 = 0, f0 = low2 (Body.rest_measures (s)) - target;
            double w1 = f0 > 0 ? -0.3 : 0.3;
            for (int i = 0; i < 6 && f0.abs () > 4; i++) {
                s.weight = w1;
                double f1 = low2 (Body.rest_measures (s)) - target;
                if ((f1 - f0).abs () < 1e-6) break;
                double w2 = (w1 - f1 * (w1 - w0) / (f1 - f0)).clamp (-1, 1);
                w0 = w1;
                f0 = f1;
                w1 = w2;
                if ((w1 - w0).abs () < 1e-4) break;
            }
            s.weight = w1;
            for (int sweep = 0; sweep < 3; sweep++) {
                m = Body.rest_measures (s);
                s.scale *= d.height / double.max (1, m.height);
                solve (s, { "hips-circ" }, d.hip, (q) => q.hip, -0.6, 0.6);
                solve (s, { "waist-circ" }, d.waist, (q) => q.waist, -0.6, 0.6);
                solve (s, { "bust-circ" }, d.bust, (q) => q.bust, -0.5, 0.5);
                solve (s, { "upperleg-height", "lowerleg-height" }, d.inseam, (q) => q.inseam, -0.5, 0.5);
                solve (s, { "upperarm-length", "lowerarm-length" }, d.arm, (q) => q.arm, -0.5, 0.5);
                solve (s, { "shoulder-dist" }, d.across_back * 1.02, (q) => q.shoulder_width, -0.5, 0.5);
                solve (s, { "neck-circ" }, d.neck, (q) => q.neck, -0.5, 0.5);
                solve (s, { "upperarm-circ" }, d.upper_arm, (q) => q.upper_arm, -0.5, 0.5);
                solve (s, { "wrist-circ" }, d.wrist, (q) => q.wrist, -0.5, 0.5);
                solve (s, { "thigh-circ" }, d.thigh, (q) => q.thigh, -0.5, 0.5);
                solve (s, { "knee-circ" }, d.knee, (q) => q.knee, -0.5, 0.5);
                solve (s, { "ankle-circ" }, d.ankle, (q) => q.ankle, -0.5, 0.5);
            }
            m = Body.rest_measures (s);
            s.scale *= d.height / double.max (1, m.height);
            return s;
        }

        private static double low2 (BodyMeasures m) {
            return m.waist + m.hip;
        }
    }
}
