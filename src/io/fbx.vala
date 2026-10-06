namespace Singularity.Apps.Atelier {

    public class FbxProp {
        public char kind;
        public int64 ival;
        public double dval;
        public string sval = "";
        public double[] darr = {};
        public int[] iarr = {};
        public int64[] larr = {};

        public static FbxProp i (int v) {
            var p = new FbxProp ();
            p.kind = 'I';
            p.ival = v;
            return p;
        }

        public static FbxProp l (int64 v) {
            var p = new FbxProp ();
            p.kind = 'L';
            p.ival = v;
            return p;
        }

        public static FbxProp d (double v) {
            var p = new FbxProp ();
            p.kind = 'D';
            p.dval = v;
            return p;
        }

        public static FbxProp c (bool v) {
            var p = new FbxProp ();
            p.kind = 'C';
            p.ival = v ? 1 : 0;
            return p;
        }

        public static FbxProp s (string v) {
            var p = new FbxProp ();
            p.kind = 'S';
            p.sval = v;
            return p;
        }

        public static FbxProp da (double[] v) {
            var p = new FbxProp ();
            p.kind = 'd';
            p.darr = v;
            return p;
        }

        public static FbxProp ia (int[] v) {
            var p = new FbxProp ();
            p.kind = 'i';
            p.iarr = v;
            return p;
        }

        public bool is_array () {
            return kind == 'd' || kind == 'i' || kind == 'l' || kind == 'f' || kind == 'b';
        }

        public int length () {
            if (kind == 'd' || kind == 'f') return darr.length;
            if (kind == 'i' || kind == 'b') return iarr.length;
            if (kind == 'l') return larr.length;
            return 0;
        }

        public double as_double () {
            if (kind == 'D' || kind == 'F') return dval;
            return (double) ival;
        }
    }

    public class FbxNode {
        public string name;
        public Gee.ArrayList<FbxProp> props = new Gee.ArrayList<FbxProp> ();
        public Gee.ArrayList<FbxNode> children = new Gee.ArrayList<FbxNode> ();

        public FbxNode (string name) {
            this.name = name;
        }

        public FbxNode add (FbxProp p) {
            props.add (p);
            return this;
        }

        public FbxNode child (string name) {
            var n = new FbxNode (name);
            children.add (n);
            return n;
        }

        public FbxNode leaf (string name, FbxProp p) {
            var n = child (name);
            n.add (p);
            return n;
        }

        public FbxNode? find (string name) {
            foreach (var c in children) if (c.name == name) return c;
            return null;
        }

        public Gee.ArrayList<FbxNode> all (string name) {
            var list = new Gee.ArrayList<FbxNode> ();
            foreach (var c in children) if (c.name == name) list.add (c);
            return list;
        }
    }

    public class Fbx {
        public const int VERSION = 7400;
        private const uint8[] FOOTER_ID = { 0xfa, 0xbc, 0xab, 0x09, 0xd0, 0xc8, 0xd4, 0x66, 0xb1, 0x76, 0xfb, 0x83, 0x1c, 0xf7, 0x26, 0x7e };
        private const uint8[] FOOTER_MAGIC = { 0xf8, 0x5a, 0x8c, 0x6a, 0xde, 0xf5, 0xd9, 0x7e, 0xec, 0xe9, 0x0c, 0xe3, 0x75, 0x8f, 0x29, 0x0b };

        private static void prop70 (FbxNode p70, string name, string type, string label, string flags, FbxProp[] values) {
            var p = p70.child ("P");
            p.add (FbxProp.s (name)).add (FbxProp.s (type)).add (FbxProp.s (label)).add (FbxProp.s (flags));
            foreach (var v in values) p.add (v);
        }

        private static string safe_name (string n, int index) {
            string s = n.strip ();
            if (s == "") s = "mesh%d".printf (index);
            return s.replace ("\"", "'").replace ("\n", " ");
        }

        public static Gee.ArrayList<FbxNode> build (Gee.List<Mesh> meshes) {
            var root = new Gee.ArrayList<FbxNode> ();
            var head = new FbxNode ("FBXHeaderExtension");
            head.leaf ("FBXHeaderVersion", FbxProp.i (1003));
            head.leaf ("FBXVersion", FbxProp.i (VERSION));
            var now = new DateTime.now_utc ();
            var ts = head.child ("CreationTimeStamp");
            ts.leaf ("Version", FbxProp.i (1000));
            ts.leaf ("Year", FbxProp.i (now.get_year ()));
            ts.leaf ("Month", FbxProp.i (now.get_month ()));
            ts.leaf ("Day", FbxProp.i (now.get_day_of_month ()));
            ts.leaf ("Hour", FbxProp.i (now.get_hour ()));
            ts.leaf ("Minute", FbxProp.i (now.get_minute ()));
            ts.leaf ("Second", FbxProp.i (now.get_second ()));
            ts.leaf ("Millisecond", FbxProp.i (0));
            head.leaf ("Creator", FbxProp.s ("Atelier"));
            root.add (head);

            var gs = new FbxNode ("GlobalSettings");
            gs.leaf ("Version", FbxProp.i (1000));
            var gp = gs.child ("Properties70");
            prop70 (gp, "UpAxis", "int", "Integer", "", { FbxProp.i (1) });
            prop70 (gp, "UpAxisSign", "int", "Integer", "", { FbxProp.i (1) });
            prop70 (gp, "FrontAxis", "int", "Integer", "", { FbxProp.i (2) });
            prop70 (gp, "FrontAxisSign", "int", "Integer", "", { FbxProp.i (1) });
            prop70 (gp, "CoordAxis", "int", "Integer", "", { FbxProp.i (0) });
            prop70 (gp, "CoordAxisSign", "int", "Integer", "", { FbxProp.i (1) });
            prop70 (gp, "OriginalUpAxis", "int", "Integer", "", { FbxProp.i (1) });
            prop70 (gp, "OriginalUpAxisSign", "int", "Integer", "", { FbxProp.i (1) });
            prop70 (gp, "UnitScaleFactor", "double", "Number", "", { FbxProp.d (0.1) });
            prop70 (gp, "OriginalUnitScaleFactor", "double", "Number", "", { FbxProp.d (0.1) });
            root.add (gs);

            var list = new Gee.ArrayList<Mesh> ();
            foreach (var m in meshes) if (m.vertices.size > 0 && m.triangles.size >= 3) list.add (m);

            var defs = new FbxNode ("Definitions");
            defs.leaf ("Version", FbxProp.i (100));
            defs.leaf ("Count", FbxProp.i (1 + list.size * 3));
            defs.child ("ObjectType").add (FbxProp.s ("GlobalSettings")).leaf ("Count", FbxProp.i (1));
            defs.child ("ObjectType").add (FbxProp.s ("Model")).leaf ("Count", FbxProp.i (list.size));
            defs.child ("ObjectType").add (FbxProp.s ("Geometry")).leaf ("Count", FbxProp.i (list.size));
            defs.child ("ObjectType").add (FbxProp.s ("Material")).leaf ("Count", FbxProp.i (list.size));
            root.add (defs);

            var objects = new FbxNode ("Objects");
            var conns = new FbxNode ("Connections");
            int64 next = 1000000;
            int index = 0;
            foreach (var m in list) {
                if (m.normals.size != m.vertices.size) m.compute_normals ();
                string name = safe_name (m.name, index);
                int64 geom_id = next++;
                int64 model_id = next++;
                int64 mat_id = next++;
                var g = objects.child ("Geometry");
                g.add (FbxProp.l (geom_id)).add (FbxProp.s ("Geometry::" + name)).add (FbxProp.s ("Mesh"));
                var verts = new double[m.vertices.size * 3];
                for (int i = 0; i < m.vertices.size; i++) {
                    verts[i * 3] = m.vertices[i].x;
                    verts[i * 3 + 1] = m.vertices[i].y;
                    verts[i * 3 + 2] = m.vertices[i].z;
                }
                g.leaf ("Vertices", FbxProp.da (verts));
                int tris = m.triangles.size / 3;
                var poly = new int[tris * 3];
                for (int t = 0; t < tris; t++) {
                    poly[t * 3] = m.triangles[t * 3];
                    poly[t * 3 + 1] = m.triangles[t * 3 + 1];
                    poly[t * 3 + 2] = -m.triangles[t * 3 + 2] - 1;
                }
                g.leaf ("PolygonVertexIndex", FbxProp.ia (poly));
                g.leaf ("GeometryVersion", FbxProp.i (124));
                var ln = g.child ("LayerElementNormal").add (FbxProp.i (0));
                ln.leaf ("Version", FbxProp.i (102));
                ln.leaf ("Name", FbxProp.s (""));
                ln.leaf ("MappingInformationType", FbxProp.s ("ByVertice"));
                ln.leaf ("ReferenceInformationType", FbxProp.s ("Direct"));
                var nrm = new double[m.normals.size * 3];
                for (int i = 0; i < m.normals.size; i++) {
                    nrm[i * 3] = m.normals[i].x;
                    nrm[i * 3 + 1] = m.normals[i].y;
                    nrm[i * 3 + 2] = m.normals[i].z;
                }
                ln.leaf ("Normals", FbxProp.da (nrm));
                bool has_uv = m.uvs.size == m.vertices.size * 2;
                if (has_uv) {
                    var lu = g.child ("LayerElementUV").add (FbxProp.i (0));
                    lu.leaf ("Version", FbxProp.i (101));
                    lu.leaf ("Name", FbxProp.s ("UVMap"));
                    lu.leaf ("MappingInformationType", FbxProp.s ("ByVertice"));
                    lu.leaf ("ReferenceInformationType", FbxProp.s ("Direct"));
                    var uv = new double[m.uvs.size];
                    for (int i = 0; i < m.uvs.size; i++) uv[i] = m.uvs[i];
                    lu.leaf ("UV", FbxProp.da (uv));
                }
                var lm = g.child ("LayerElementMaterial").add (FbxProp.i (0));
                lm.leaf ("Version", FbxProp.i (101));
                lm.leaf ("Name", FbxProp.s (""));
                lm.leaf ("MappingInformationType", FbxProp.s ("AllSame"));
                lm.leaf ("ReferenceInformationType", FbxProp.s ("IndexToDirect"));
                lm.leaf ("Materials", FbxProp.ia ({ 0 }));
                var layer = g.child ("Layer").add (FbxProp.i (0));
                layer.leaf ("Version", FbxProp.i (100));
                string[] kinds = has_uv ? new string[] { "LayerElementNormal", "LayerElementUV", "LayerElementMaterial" } : new string[] { "LayerElementNormal", "LayerElementMaterial" };
                foreach (var k in kinds) {
                    var le = layer.child ("LayerElement");
                    le.leaf ("Type", FbxProp.s (k));
                    le.leaf ("TypedIndex", FbxProp.i (0));
                }

                var model = objects.child ("Model");
                model.add (FbxProp.l (model_id)).add (FbxProp.s ("Model::" + name)).add (FbxProp.s ("Mesh"));
                model.leaf ("Version", FbxProp.i (232));
                var mp = model.child ("Properties70");
                prop70 (mp, "DefaultAttributeIndex", "int", "Integer", "", { FbxProp.i (0) });
                prop70 (mp, "Lcl Translation", "Lcl Translation", "", "A", { FbxProp.d (0), FbxProp.d (0), FbxProp.d (0) });
                model.leaf ("Shading", FbxProp.c (true));
                model.leaf ("Culling", FbxProp.s (m.double_sided ? "CullingOff" : "CullingOnCCW"));

                string mat_name = m.material != "" ? m.material : name;
                var mat = objects.child ("Material");
                mat.add (FbxProp.l (mat_id)).add (FbxProp.s ("Material::%s_%d".printf (safe_name (mat_name, index), index))).add (FbxProp.s (""));
                mat.leaf ("Version", FbxProp.i (102));
                mat.leaf ("ShadingModel", FbxProp.s ("phong"));
                mat.leaf ("MultiLayer", FbxProp.i (0));
                var matp = mat.child ("Properties70");
                prop70 (matp, "DiffuseColor", "Color", "", "A", { FbxProp.d (m.color.r), FbxProp.d (m.color.g), FbxProp.d (m.color.b) });
                prop70 (matp, "DiffuseFactor", "Number", "", "A", { FbxProp.d (1) });
                double spec = 0.04 + m.metallic * 0.9;
                prop70 (matp, "SpecularColor", "Color", "", "A", { FbxProp.d (spec), FbxProp.d (spec), FbxProp.d (spec) });
                prop70 (matp, "Shininess", "Number", "", "A", { FbxProp.d ((1 - m.roughness) * 100 + 2) });
                prop70 (matp, "ShininessExponent", "Number", "", "A", { FbxProp.d ((1 - m.roughness) * 100 + 2) });
                prop70 (matp, "Opacity", "Number", "", "A", { FbxProp.d (m.color.a) });
                prop70 (matp, "TransparencyFactor", "Number", "", "A", { FbxProp.d (1 - m.color.a) });
                prop70 (matp, "Roughness", "Number", "", "A", { FbxProp.d (m.roughness) });
                prop70 (matp, "Metallic", "Number", "", "A", { FbxProp.d (m.metallic) });

                conns.child ("C").add (FbxProp.s ("OO")).add (FbxProp.l (model_id)).add (FbxProp.l (0));
                conns.child ("C").add (FbxProp.s ("OO")).add (FbxProp.l (geom_id)).add (FbxProp.l (model_id));
                conns.child ("C").add (FbxProp.s ("OO")).add (FbxProp.l (mat_id)).add (FbxProp.l (model_id));
                index++;
            }
            root.add (objects);
            root.add (conns);
            return root;
        }

        private static string num (double v) {
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            string s = v.format (buf, "%.10g");
            if (s == "-0") s = "0";
            return s;
        }

        private static string quote (string s) {
            return "\"" + s.replace ("\"", "&quot;") + "\"";
        }

        private static string ascii_value (FbxProp p) {
            switch (p.kind) {
                case 'S': return quote (p.sval);
                case 'C': return p.ival != 0 ? "T" : "F";
                case 'D':
                case 'F': return num (p.dval);
                default: return p.ival.to_string ();
            }
        }

        private static void write_ascii_node (StringBuilder sb, FbxNode n, int depth) {
            string ind = string.nfill (depth, '\t');
            sb.append (ind).append (n.name).append (": ");
            bool array_node = n.props.size == 1 && n.props[0].is_array ();
            if (array_node) {
                var p = n.props[0];
                sb.append ("*%d {\n".printf (p.length ()));
                sb.append (ind).append ("\ta: ");
                for (int i = 0; i < p.length (); i++) {
                    if (i > 0) sb.append (",");
                    if (p.kind == 'd' || p.kind == 'f') sb.append (num (p.darr[i]));
                    else if (p.kind == 'l') sb.append (p.larr[i].to_string ());
                    else sb.append (p.iarr[i].to_string ());
                }
                sb.append ("\n").append (ind).append ("}\n");
                return;
            }
            for (int i = 0; i < n.props.size; i++) {
                if (i > 0) sb.append (", ");
                sb.append (ascii_value (n.props[i]));
            }
            if (n.children.size > 0 || n.props.size == 0) {
                sb.append (" {\n");
                foreach (var c in n.children) write_ascii_node (sb, c, depth + 1);
                sb.append (ind).append ("}\n");
            } else {
                sb.append ("\n");
            }
        }

        public static string write_ascii (Gee.List<Mesh> meshes) {
            var sb = new StringBuilder ();
            sb.append ("; FBX 7.4.0 project file\n; Created by Atelier\n; ----------------------------------------------------\n\n");
            foreach (var n in build (meshes)) {
                write_ascii_node (sb, n, 0);
                sb.append ("\n");
            }
            return sb.str;
        }

        private static void put32 (ByteArray b, uint32 v) {
            uint8[] d = { (uint8) (v & 0xff), (uint8) ((v >> 8) & 0xff), (uint8) ((v >> 16) & 0xff), (uint8) ((v >> 24) & 0xff) };
            b.append (d);
        }

        private static void put64 (ByteArray b, uint64 v) {
            put32 (b, (uint32) (v & 0xffffffff));
            put32 (b, (uint32) (v >> 32));
        }

        private static void put_double (ByteArray b, double v) {
            uint64 bits = 0;
            Memory.copy (&bits, &v, 8);
            put64 (b, bits);
        }

        private static void set32 (ByteArray b, uint at, uint32 v) {
            b.data[at] = (uint8) (v & 0xff);
            b.data[at + 1] = (uint8) ((v >> 8) & 0xff);
            b.data[at + 2] = (uint8) ((v >> 16) & 0xff);
            b.data[at + 3] = (uint8) ((v >> 24) & 0xff);
        }

        private static uint8[] binary_name (string s, FbxNode n, int index) {
            var b = new ByteArray ();
            int sep = s.index_of ("::");
            if (index != 1 || sep < 0 || !(n.name == "Geometry" || n.name == "Model" || n.name == "Material")) {
                b.append (s.data[0:s.length]);
                return b.steal ();
            }
            string obj = s.substring (sep + 2), cls = s.substring (0, sep);
            b.append (obj.data[0:obj.length]);
            b.append ({ 0x00, 0x01 });
            b.append (cls.data[0:cls.length]);
            return b.steal ();
        }

        private static void write_prop (ByteArray b, FbxProp p, uint8[] sval) {
            b.append ({ (uint8) p.kind });
            switch (p.kind) {
                case 'I':
                    put32 (b, (uint32) (int32) p.ival);
                    break;
                case 'L':
                    put64 (b, (uint64) p.ival);
                    break;
                case 'D':
                    put_double (b, p.dval);
                    break;
                case 'C':
                    b.append ({ (uint8) (p.ival != 0 ? 1 : 0) });
                    break;
                case 'S':
                    put32 (b, (uint32) sval.length);
                    b.append (sval);
                    break;
                case 'd':
                    put32 (b, (uint32) p.darr.length);
                    put32 (b, 0);
                    put32 (b, (uint32) (p.darr.length * 8));
                    foreach (var v in p.darr) put_double (b, v);
                    break;
                case 'i':
                    put32 (b, (uint32) p.iarr.length);
                    put32 (b, 0);
                    put32 (b, (uint32) (p.iarr.length * 4));
                    foreach (var v in p.iarr) put32 (b, (uint32) v);
                    break;
                default:
                    break;
            }
        }

        private static void write_bin_node (ByteArray b, FbxNode n) {
            uint start = b.len;
            put32 (b, 0);
            put32 (b, (uint32) n.props.size);
            put32 (b, 0);
            b.append ({ (uint8) n.name.length });
            b.append (n.name.data[0:n.name.length]);
            uint props_start = b.len;
            for (int i = 0; i < n.props.size; i++) {
                var p = n.props[i];
                uint8[] sv = p.kind == 'S' ? binary_name (p.sval, n, i) : new uint8[0];
                write_prop (b, p, sv);
            }
            set32 (b, start + 8, (uint32) (b.len - props_start));
            if (n.children.size > 0 || n.props.size == 0) {
                foreach (var c in n.children) write_bin_node (b, c);
                b.append (new uint8[13]);
            }
            set32 (b, start, (uint32) b.len);
        }

        public static uint8[] write_binary (Gee.List<Mesh> meshes) {
            var b = new ByteArray ();
            b.append ("Kaydara FBX Binary  ".data);
            b.append ({ 0x00, 0x1a, 0x00 });
            put32 (b, VERSION);
            foreach (var n in build (meshes)) write_bin_node (b, n);
            b.append (new uint8[13]);
            b.append (FOOTER_ID);
            b.append (new uint8[4]);
            uint pad = ((b.len + 15) & ~15u) - b.len;
            if (pad == 0) pad = 16;
            b.append (new uint8[pad]);
            put32 (b, VERSION);
            b.append (new uint8[120]);
            b.append (FOOTER_MAGIC);
            return b.steal ();
        }

        public static void save (string path, Gee.List<Mesh> meshes, bool binary = false) throws Error {
            if (binary) FileUtils.set_data (path, write_binary (meshes));
            else FileUtils.set_contents (path, write_ascii (meshes));
        }

        private class Lexer {
            public string src;
            public int pos;

            public Lexer (string s) {
                src = s;
                pos = 0;
            }

            public void skip () {
                while (pos < src.length) {
                    char c = src[pos];
                    if (c == ';') {
                        while (pos < src.length && src[pos] != '\n') pos++;
                    } else if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
                        pos++;
                    } else {
                        break;
                    }
                }
            }

            public void skip_inline () {
                while (pos < src.length && (src[pos] == ' ' || src[pos] == '\t')) pos++;
            }

            public bool at_end () {
                skip ();
                return pos >= src.length;
            }

            public char peek () {
                skip ();
                return pos < src.length ? src[pos] : '\0';
            }

            public string word () {
                skip ();
                int s = pos;
                while (pos < src.length) {
                    char c = src[pos];
                    if (c.isalnum () || c == '_' || c == '-' || c == '+' || c == '.' || c == '*') pos++;
                    else break;
                }
                return src.substring (s, pos - s);
            }

            public string str () throws Error {
                skip ();
                if (src[pos] != '"') throw new MeshIOError.INVALID ("FBX: string expected at %d", pos);
                int e = src.index_of_char ('"', pos + 1);
                if (e < 0) throw new MeshIOError.INVALID ("FBX: unterminated string");
                string v = src.substring (pos + 1, e - pos - 1).replace ("&quot;", "\"");
                pos = e + 1;
                return v;
            }
        }

        private static FbxProp scalar (string w) {
            if (w == "T" || w == "Y") return FbxProp.c (true);
            if (w == "F" || w == "N") return FbxProp.c (false);
            if (w.contains (".") || w.contains ("e") || w.contains ("E")) return FbxProp.d (double.parse (w));
            int64 v = int64.parse (w);
            if (v > int32.MAX || v < int32.MIN) return FbxProp.l (v);
            return FbxProp.i ((int) v);
        }

        private static FbxNode parse_ascii_node (Lexer lx, string name) throws Error {
            var n = new FbxNode (name);
            lx.skip_inline ();
            if (lx.pos < lx.src.length && lx.src[lx.pos] == '*') {
                lx.pos++;
                lx.word ();
                if (lx.peek () != '{') throw new MeshIOError.INVALID ("FBX: array body expected");
                lx.pos++;
                string a = lx.word ();
                if (a != "a" || lx.peek () != ':') throw new MeshIOError.INVALID ("FBX: array values expected");
                lx.pos++;
                double[] ds = {};
                int[] ints = {};
                bool floating = false;
                while (lx.peek () != '}') {
                    string w = lx.word ();
                    if (w == "") throw new MeshIOError.INVALID ("FBX: bad array value at %d", lx.pos);
                    if (w.contains (".") || w.contains ("e") || w.contains ("E")) floating = true;
                    ds += double.parse (w);
                    ints += int.parse (w);
                    if (lx.peek () == ',') lx.pos++;
                }
                lx.pos++;
                n.add (floating || name == "Vertices" || name == "Normals" || name == "UV" ? FbxProp.da (ds) : FbxProp.ia (ints));
                return n;
            }
            while (true) {
                lx.skip_inline ();
                if (lx.pos >= lx.src.length) return n;
                char c = lx.src[lx.pos];
                if (c == '{') break;
                if (c == '\n' || c == '\r' || c == ';' || c == '}') return n;
                if (c == '"') {
                    n.add (FbxProp.s (lx.str ()));
                } else {
                    string w = lx.word ();
                    if (w == "") throw new MeshIOError.INVALID ("FBX: value expected at %d", lx.pos);
                    n.add (scalar (w));
                }
                lx.skip_inline ();
                if (lx.pos < lx.src.length && lx.src[lx.pos] == ',') {
                    lx.pos++;
                    continue;
                }
                if (lx.pos < lx.src.length && lx.src[lx.pos] == '{') break;
                return n;
            }
            if (lx.peek () == '{') {
                lx.pos++;
                while (lx.peek () != '}') {
                    if (lx.at_end ()) throw new MeshIOError.INVALID ("FBX: unexpected end");
                    string cname = lx.word ();
                    if (lx.peek () != ':') throw new MeshIOError.INVALID ("FBX: ':' expected after %s", cname);
                    lx.pos++;
                    n.children.add (parse_ascii_node (lx, cname));
                }
                lx.pos++;
            }
            return n;
        }

        public static Gee.ArrayList<FbxNode> parse_ascii (string text) throws Error {
            var lx = new Lexer (text);
            var list = new Gee.ArrayList<FbxNode> ();
            while (!lx.at_end ()) {
                string name = lx.word ();
                if (name == "" || lx.peek () != ':') throw new MeshIOError.INVALID ("FBX: node name expected at %d", lx.pos);
                lx.pos++;
                list.add (parse_ascii_node (lx, name));
            }
            return list;
        }

        private static uint32 get32 (uint8[] d, int p) {
            return d[p] | ((uint32) d[p + 1] << 8) | ((uint32) d[p + 2] << 16) | ((uint32) d[p + 3] << 24);
        }

        private static uint64 get64 (uint8[] d, int p) {
            return get32 (d, p) | ((uint64) get32 (d, p + 4) << 32);
        }

        private static double getd (uint8[] d, int p) {
            uint64 bits = get64 (d, p);
            double v = 0;
            Memory.copy (&v, &bits, 8);
            return v;
        }

        private static string bytes_str (uint8[] d, int start, int len) {
            var copy = new uint8[len + 1];
            if (len > 0) Memory.copy (copy, &d[start], len);
            copy[len] = 0;
            return (string) copy;
        }

        private static FbxNode? read_bin_node (uint8[] d, ref int p) throws Error {
            if (p + 13 > d.length) throw new MeshIOError.INVALID ("FBX: truncated");
            uint32 end = get32 (d, p);
            uint32 nprops = get32 (d, p + 4);
            uint8 nlen = d[p + 12];
            if (end == 0) {
                p += 13;
                return null;
            }
            var n = new FbxNode (bytes_str (d, p + 13, nlen));
            p += 13 + nlen;
            for (uint i = 0; i < nprops; i++) {
                char k = (char) d[p++];
                switch (k) {
                    case 'I':
                        n.add (FbxProp.i ((int32) get32 (d, p)));
                        p += 4;
                        break;
                    case 'L':
                        n.add (FbxProp.l ((int64) get64 (d, p)));
                        p += 8;
                        break;
                    case 'D':
                        n.add (FbxProp.d (getd (d, p)));
                        p += 8;
                        break;
                    case 'C':
                        n.add (FbxProp.c (d[p] != 0));
                        p += 1;
                        break;
                    case 'S':
                        uint32 len = get32 (d, p);
                        p += 4;
                        string raw;
                        int zero = -1;
                        for (int q = 0; q + 1 < (int) len; q++) if (d[p + q] == 0 && d[p + q + 1] == 1) zero = q;
                        if (zero >= 0) raw = bytes_str (d, p + zero + 2, (int) len - zero - 2) + "::" + bytes_str (d, p, zero);
                        else raw = bytes_str (d, p, (int) len);
                        n.add (FbxProp.s (raw));
                        p += (int) len;
                        break;
                    case 'd':
                    case 'i':
                        uint32 count = get32 (d, p);
                        uint32 enc = get32 (d, p + 4);
                        uint32 clen = get32 (d, p + 8);
                        p += 12;
                        if (enc != 0) throw new MeshIOError.UNSUPPORTED ("FBX: compressed arrays are not supported");
                        if (k == 'd') {
                            var a = new double[count];
                            for (uint q = 0; q < count; q++) a[q] = getd (d, p + (int) q * 8);
                            n.add (FbxProp.da (a));
                        } else {
                            var a = new int[count];
                            for (uint q = 0; q < count; q++) a[q] = (int32) get32 (d, p + (int) q * 4);
                            n.add (FbxProp.ia (a));
                        }
                        p += (int) clen;
                        break;
                    default:
                        throw new MeshIOError.UNSUPPORTED ("FBX: property type %c", k);
                }
            }
            while (p < (int) end) {
                var c = read_bin_node (d, ref p);
                if (c == null) break;
                n.children.add (c);
            }
            p = (int) end;
            return n;
        }

        public static Gee.ArrayList<FbxNode> parse_binary (uint8[] d) throws Error {
            if (d.length < 27 || Memory.cmp (d, "Kaydara FBX Binary  ".data, 20) != 0) throw new MeshIOError.INVALID ("Not a binary FBX file");
            uint32 version = get32 (d, 23);
            if (version >= 7500) throw new MeshIOError.UNSUPPORTED ("FBX: version %u is not supported", version);
            var list = new Gee.ArrayList<FbxNode> ();
            int p = 27;
            while (p < d.length) {
                var n = read_bin_node (d, ref p);
                if (n == null) break;
                list.add (n);
            }
            return list;
        }

        private static FbxNode? top (Gee.List<FbxNode> root, string name) {
            foreach (var n in root) if (n.name == name) return n;
            return null;
        }

        public static Gee.ArrayList<Mesh> to_meshes (Gee.List<FbxNode> root) throws Error {
            var objects = top (root, "Objects");
            var conns = top (root, "Connections");
            if (objects == null) throw new MeshIOError.INVALID ("FBX: no Objects");
            var geoms = new Gee.HashMap<string, FbxNode> ();
            var mats = new Gee.HashMap<string, FbxNode> ();
            var models = new Gee.ArrayList<FbxNode> ();
            foreach (var o in objects.children) {
                if (o.props.size == 0) continue;
                string id = o.props[0].ival.to_string ();
                if (o.name == "Geometry") geoms[id] = o;
                else if (o.name == "Material") mats[id] = o;
                else if (o.name == "Model") models.add (o);
            }
            var list = new Gee.ArrayList<Mesh> ();
            foreach (var model in models) {
                int64 mid = model.props[0].ival;
                FbxNode? geom = null, mat = null;
                if (conns != null) {
                    foreach (var c in conns.children) {
                        if (c.props.size < 3 || c.props[2].ival != mid) continue;
                        string child_id = c.props[1].ival.to_string ();
                        if (geoms.has_key (child_id)) geom = geoms[child_id];
                        if (mats.has_key (child_id)) mat = mats[child_id];
                    }
                }
                if (geom == null) continue;
                var m = new Mesh ();
                string label = model.props[1].sval;
                int sep = label.index_of ("::");
                m.name = sep >= 0 ? label.substring (sep + 2) : label;
                var vn = geom.find ("Vertices");
                var pn = geom.find ("PolygonVertexIndex");
                if (vn == null || pn == null) continue;
                var va = vn.props[0];
                for (int i = 0; i + 2 < va.length (); i += 3) m.vertices.add (Vec3 (va.darr[i], va.darr[i + 1], va.darr[i + 2]));
                var pa = pn.props[0];
                int[] poly = {};
                for (int i = 0; i < pa.length (); i++) {
                    int v = pa.kind == 'd' ? (int) pa.darr[i] : pa.iarr[i];
                    bool last = v < 0;
                    poly += last ? -v - 1 : v;
                    if (last) {
                        for (int k = 1; k + 1 < poly.length; k++) m.add_triangle (poly[0], poly[k], poly[k + 1]);
                        poly = {};
                    }
                }
                var uvl = geom.find ("LayerElementUV");
                if (uvl != null && uvl.find ("UV") != null) {
                    var ua = uvl.find ("UV").props[0];
                    if (ua.length () == m.vertices.size * 2) for (int i = 0; i < ua.length (); i++) m.uvs.add (ua.darr[i]);
                }
                if (mat != null) {
                    var p70 = mat.find ("Properties70");
                    if (p70 != null) {
                        foreach (var p in p70.children) {
                            if (p.props.size < 5) continue;
                            string key = p.props[0].sval;
                            if (key == "DiffuseColor" && p.props.size >= 7) m.color = Rgba (p.props[4].as_double (), p.props[5].as_double (), p.props[6].as_double (), m.color.a);
                            else if (key == "Opacity") m.color.a = p.props[4].as_double ();
                            else if (key == "Roughness") m.roughness = p.props[4].as_double ();
                            else if (key == "Metallic") m.metallic = p.props[4].as_double ();
                        }
                    }
                    string ml = mat.props[1].sval;
                    int ms = ml.index_of ("::");
                    string mname = ms >= 0 ? ml.substring (ms + 2) : ml;
                    int us = mname.last_index_of ("_");
                    m.material = us > 0 ? mname.substring (0, us) : mname;
                }
                m.compute_normals ();
                list.add (m);
            }
            return list;
        }

        public static Gee.ArrayList<Mesh> load (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            if (data.length >= 20 && Memory.cmp (data, "Kaydara FBX Binary  ".data, 20) == 0) return to_meshes (parse_binary (data));
            return to_meshes (parse_ascii ((string) data));
        }
    }
}
