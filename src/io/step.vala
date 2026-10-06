namespace Singularity.Apps.Atelier {

    public class Step {
        private StringBuilder data;
        private int next_id;

        private Step () {
            data = new StringBuilder ();
            next_id = 1;
        }

        public static string real (double v) {
            if (v.is_nan () || v.is_infinity () != 0) v = 0;
            if (v.abs () < 1e-300) return "0.";
            char[] buf = new char[double.DTOSTR_BUF_SIZE];
            string s = v.format (buf, "%.15G");
            string mant = s, exp = "";
            int e = s.index_of ("E");
            if (e >= 0) {
                mant = s.substring (0, e);
                exp = s.substring (e);
            }
            if (!mant.contains (".")) mant += ".";
            return mant + exp;
        }

        public static string text (string s) {
            var b = new StringBuilder ();
            unichar c;
            int i = 0;
            while (s.get_next_char (ref i, out c)) {
                if (c == '\'') b.append ("''");
                else if (c == '\\') b.append ("\\\\");
                else if (c >= 32 && c < 127) b.append_unichar (c);
                else if (c <= 0xFFFF) b.append ("\\X2\\%04X\\X0\\".printf ((uint) c));
                else b.append ("\\X4\\%08X\\X0\\".printf ((uint) c));
            }
            return "'" + b.str + "'";
        }

        private int add (string entity) {
            int id = next_id++;
            data.append ("#%d=%s;\n".printf (id, entity));
            return id;
        }

        private static string refs (int[] ids) {
            var b = new StringBuilder ("(");
            for (int i = 0; i < ids.length; i++) {
                if (i > 0) b.append (",");
                b.append ("#%d".printf (ids[i]));
            }
            b.append (")");
            return b.str;
        }

        private static void compress (double[] knots, out string mults, out string values) {
            var m = new StringBuilder ("(");
            var v = new StringBuilder ("(");
            int i = 0;
            bool first = true;
            while (i < knots.length) {
                int j = i;
                while (j + 1 < knots.length && (knots[j + 1] - knots[i]).abs () < 1e-12) j++;
                if (!first) {
                    m.append (",");
                    v.append (",");
                }
                first = false;
                m.append ((j - i + 1).to_string ());
                v.append (real (knots[i]));
                i = j + 1;
            }
            m.append (")");
            v.append (")");
            mults = m.str;
            values = v.str;
        }

        private int point (Vec3 p) {
            return add ("CARTESIAN_POINT('',(%s,%s,%s))".printf (real (p.x), real (p.y), real (p.z)));
        }

        private int curve (NurbsCurve c) {
            int[] pts = {};
            foreach (var p in c.ctrl) pts += point (p);
            string mults, values;
            compress (c.knots, out mults, out values);
            bool rational = false;
            foreach (var w in c.weights) if ((w - 1).abs () > 1e-12) rational = true;
            if (!rational) {
                return add ("B_SPLINE_CURVE_WITH_KNOTS('',%d,%s,.UNSPECIFIED.,.F.,.F.,%s,%s,.UNSPECIFIED.)".printf (c.degree, refs (pts), mults, values));
            }
            var w = new StringBuilder ("(");
            for (int i = 0; i < c.weights.size; i++) {
                if (i > 0) w.append (",");
                w.append (real (c.weights[i]));
            }
            w.append (")");
            return add ("(BOUNDED_CURVE() B_SPLINE_CURVE(%d,%s,.UNSPECIFIED.,.F.,.F.) B_SPLINE_CURVE_WITH_KNOTS(%s,%s,.UNSPECIFIED.) CURVE() GEOMETRIC_REPRESENTATION_ITEM() RATIONAL_B_SPLINE_CURVE(%s) REPRESENTATION_ITEM(''))".printf (
                c.degree, refs (pts), mults, values, w.str));
        }

        private int surface (NurbsSurface s) {
            var grid = new StringBuilder ("(");
            var wgrid = new StringBuilder ("(");
            for (int i = 0; i < s.count_u; i++) {
                int[] row = {};
                for (int j = 0; j < s.count_v; j++) row += point (s.point (i, j));
                if (i > 0) {
                    grid.append (",");
                    wgrid.append (",");
                }
                grid.append (refs (row));
                wgrid.append ("(");
                for (int j = 0; j < s.count_v; j++) {
                    if (j > 0) wgrid.append (",");
                    wgrid.append (real (s.weight (i, j)));
                }
                wgrid.append (")");
            }
            grid.append (")");
            wgrid.append (")");
            string um, uv, vm, vv;
            compress (s.knots_u, out um, out uv);
            compress (s.knots_v, out vm, out vv);
            if (!s.is_rational ()) {
                return add ("B_SPLINE_SURFACE_WITH_KNOTS(%s,%d,%d,%s,.UNSPECIFIED.,.F.,.F.,.F.,%s,%s,%s,%s,.UNSPECIFIED.)".printf (
                    text (s.name), s.degree_u, s.degree_v, grid.str, um, vm, uv, vv));
            }
            return add ("(BOUNDED_SURFACE() B_SPLINE_SURFACE(%d,%d,%s,.UNSPECIFIED.,.F.,.F.,.F.) B_SPLINE_SURFACE_WITH_KNOTS(%s,%s,%s,%s,.UNSPECIFIED.) GEOMETRIC_REPRESENTATION_ITEM() RATIONAL_B_SPLINE_SURFACE(%s) REPRESENTATION_ITEM(%s) SURFACE())".printf (
                s.degree_u, s.degree_v, grid.str, um, vm, uv, vv, wgrid.str, text (s.name)));
        }

        public static string write (string name, Gee.List<NurbsSurface> surfaces, Gee.List<NurbsCurve> curves) {
            var w = new Step ();
            int app = w.add ("APPLICATION_CONTEXT('core data for automotive mechanical design processes')");
            w.add ("APPLICATION_PROTOCOL_DEFINITION('international standard','automotive_design',2000,#%d)".printf (app));
            int pctx = w.add ("PRODUCT_CONTEXT('',#%d,'mechanical')".printf (app));
            int prod = w.add ("PRODUCT(%s,%s,'',(#%d))".printf (text (name), text (name), pctx));
            w.add ("PRODUCT_RELATED_PRODUCT_CATEGORY('part',$,(#%d))".printf (prod));
            int form = w.add ("PRODUCT_DEFINITION_FORMATION('','',#%d)".printf (prod));
            int pdctx = w.add ("PRODUCT_DEFINITION_CONTEXT('part definition',#%d,'design')".printf (app));
            int pdef = w.add ("PRODUCT_DEFINITION('design','',#%d,#%d)".printf (form, pdctx));
            int pds = w.add ("PRODUCT_DEFINITION_SHAPE('','',#%d)".printf (pdef));
            int len = w.add ("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.))");
            int ang = w.add ("(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.))");
            int sol = w.add ("(NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT())");
            int unc = w.add ("UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(1.E-07),#%d,'distance_accuracy_value','confusion accuracy')".printf (len));
            int ctx = w.add ("(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT((#%d)) GLOBAL_UNIT_ASSIGNED_CONTEXT((#%d,#%d,#%d)) REPRESENTATION_CONTEXT('Context #1','3D Context with UNIT and UNCERTAINTY'))".printf (unc, len, ang, sol));
            int origin = w.point (Vec3 (0, 0, 0));
            int dz = w.add ("DIRECTION('',(0.,0.,1.))");
            int dx = w.add ("DIRECTION('',(1.,0.,0.))");
            int axis = w.add ("AXIS2_PLACEMENT_3D('',#%d,#%d,#%d)".printf (origin, dz, dx));
            int[] items = {};
            foreach (var s in surfaces) items += w.surface (s);
            foreach (var c in curves) items += w.curve (c);
            int[] rep_items = { axis };
            if (items.length > 0) rep_items += w.add ("GEOMETRIC_SET('',%s)".printf (refs (items)));
            int rep = w.add ("GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION(%s,%s,#%d)".printf (text (name), refs (rep_items), ctx));
            w.add ("SHAPE_DEFINITION_REPRESENTATION(#%d,#%d)".printf (pds, rep));
            var now = new DateTime.now_utc ();
            var head = new StringBuilder ();
            head.append ("ISO-10303-21;\nHEADER;\n");
            head.append ("FILE_DESCRIPTION(('Atelier surfaces and curves'),'2;1');\n");
            head.append ("FILE_NAME(%s,'%s',(''),(''),'Atelier','Atelier','');\n".printf (text (name + ".stp"), now.format ("%Y-%m-%dT%H:%M:%S")));
            head.append ("FILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'));\nENDSEC;\nDATA;\n");
            head.append (w.data.str);
            head.append ("ENDSEC;\nEND-ISO-10303-21;\n");
            return head.str;
        }

        public static void save (string path, string name, Gee.List<NurbsSurface> surfaces, Gee.List<NurbsCurve> curves) throws Error {
            FileUtils.set_contents (path, write (name, surfaces, curves));
        }

        private class Record {
            public string type = "";
            public Gee.ArrayList<string> parts = new Gee.ArrayList<string> ();
            public Gee.ArrayList<string> part_names = new Gee.ArrayList<string> ();
        }

        private static Gee.ArrayList<string> split_args (string body) {
            var list = new Gee.ArrayList<string> ();
            int depth = 0;
            bool quote = false;
            int start = 0;
            for (int i = 0; i < body.length; i++) {
                char c = body[i];
                if (quote) {
                    if (c == '\'') {
                        if (i + 1 < body.length && body[i + 1] == '\'') i++;
                        else quote = false;
                    }
                    continue;
                }
                if (c == '\'') quote = true;
                else if (c == '(') depth++;
                else if (c == ')') depth--;
                else if (c == ',' && depth == 0) {
                    list.add (body.substring (start, i - start).strip ());
                    start = i + 1;
                }
            }
            string last = body.substring (start).strip ();
            if (last != "" || list.size > 0) list.add (last);
            return list;
        }

        private static string inner (string s) {
            string t = s.strip ();
            if (t.has_prefix ("(") && t.has_suffix (")")) return t.substring (1, t.length - 2);
            return t;
        }

        private static Gee.ArrayList<Record> parse_records (string entity) {
            var list = new Gee.ArrayList<Record> ();
            string e = entity.strip ();
            bool complex = e.has_prefix ("(");
            string body = complex ? inner (e) : e;
            int i = 0;
            while (i < body.length) {
                while (i < body.length && (body[i] == ' ' || body[i] == '\n' || body[i] == '\r' || body[i] == '\t')) i++;
                if (i >= body.length) break;
                int name_start = i;
                while (i < body.length && body[i] != '(') i++;
                string name = body.substring (name_start, i - name_start).strip ();
                int depth = 0;
                bool quote = false;
                int arg_start = i + 1;
                for (; i < body.length; i++) {
                    char c = body[i];
                    if (quote) {
                        if (c == '\'') {
                            if (i + 1 < body.length && body[i + 1] == '\'') i++;
                            else quote = false;
                        }
                        continue;
                    }
                    if (c == '\'') quote = true;
                    else if (c == '(') depth++;
                    else if (c == ')') {
                        depth--;
                        if (depth == 0) break;
                    }
                }
                var r = new Record ();
                r.type = name;
                r.parts = split_args (body.substring (arg_start, i - arg_start));
                list.add (r);
                i++;
                if (!complex) break;
            }
            return list;
        }

        private static int ref_id (string s) {
            string t = s.strip ();
            return t.has_prefix ("#") ? int.parse (t.substring (1)) : -1;
        }

        private static double[] expand_knots (string mults, string values) {
            var m = split_args (inner (mults));
            var v = split_args (inner (values));
            double[] k = {};
            for (int i = 0; i < int.min (m.size, v.size); i++) {
                int count = int.parse (m[i]);
                double value = double.parse (v[i]);
                for (int c = 0; c < count; c++) k += value;
            }
            return k;
        }

        public static void read (string content, Gee.List<NurbsSurface> surfaces, Gee.List<NurbsCurve> curves, out string schema) throws Error {
            schema = "";
            int ds = content.index_of ("DATA;");
            if (!content.has_prefix ("ISO-10303-21;") || ds < 0) throw new MeshIOError.INVALID ("Not an ISO 10303-21 file");
            int fs = content.index_of ("FILE_SCHEMA");
            if (fs >= 0) {
                int q1 = content.index_of ("'", fs);
                int q2 = content.index_of ("'", q1 + 1);
                if (q1 >= 0 && q2 > q1) schema = content.substring (q1 + 1, q2 - q1 - 1);
            }
            var entities = new Gee.HashMap<int, string> ();
            var order = new Gee.ArrayList<int> ();
            int pos = ds + 5;
            while (true) {
                int hash = content.index_of ("#", pos);
                if (hash < 0) break;
                int eq = content.index_of ("=", hash);
                int end_sec = content.index_of ("ENDSEC;", pos);
                if (eq < 0 || (end_sec >= 0 && end_sec < hash)) break;
                int id = int.parse (content.substring (hash + 1, eq - hash - 1));
                int i = eq + 1;
                bool quote = false;
                while (i < content.length) {
                    char c = content[i];
                    if (quote) {
                        if (c == '\'') {
                            if (i + 1 < content.length && content[i + 1] == '\'') i++;
                            else quote = false;
                        }
                    } else if (c == '\'') {
                        quote = true;
                    } else if (c == ';') {
                        break;
                    }
                    i++;
                }
                entities[id] = content.substring (eq + 1, i - eq - 1).replace ("\n", "").replace ("\r", "");
                order.add (id);
                pos = i + 1;
            }
            var points = new Gee.HashMap<int, Vec3?> ();
            foreach (var id in order) {
                string e = entities[id].strip ();
                if (!e.has_prefix ("CARTESIAN_POINT")) continue;
                var r = parse_records (e)[0];
                var c = split_args (inner (r.parts[1]));
                points[id] = Vec3 (double.parse (c[0]), double.parse (c.size > 1 ? c[1] : "0"), double.parse (c.size > 2 ? c[2] : "0"));
            }
            foreach (var id in order) {
                var recs = parse_records (entities[id]);
                Record? bsc = null, bsck = null, rat = null, bss = null, bssk = null, rats = null;
                foreach (var r in recs) {
                    switch (r.type) {
                        case "B_SPLINE_CURVE": bsc = r; break;
                        case "B_SPLINE_CURVE_WITH_KNOTS": bsck = r; break;
                        case "RATIONAL_B_SPLINE_CURVE": rat = r; break;
                        case "B_SPLINE_SURFACE": bss = r; break;
                        case "B_SPLINE_SURFACE_WITH_KNOTS": bssk = r; break;
                        case "RATIONAL_B_SPLINE_SURFACE": rats = r; break;
                    }
                }
                if (bsck != null) {
                    string deg, pts, mults, values;
                    if (bsc == null) {
                        deg = bsck.parts[1];
                        pts = bsck.parts[2];
                        mults = bsck.parts[6];
                        values = bsck.parts[7];
                    } else {
                        deg = bsc.parts[0];
                        pts = bsc.parts[1];
                        mults = bsck.parts[0];
                        values = bsck.parts[1];
                    }
                    var c = new NurbsCurve (int.parse (deg));
                    foreach (var p in split_args (inner (pts))) c.ctrl.add (points[ref_id (p)]);
                    if (rat != null) foreach (var w in split_args (inner (rat.parts[0]))) c.weights.add (double.parse (w));
                    else for (int k = 0; k < c.ctrl.size; k++) c.weights.add (1.0);
                    c.knots = expand_knots (mults, values);
                    curves.add (c);
                } else if (bssk != null) {
                    string du, dv, grid, um, vm, uv, vv, name = "";
                    if (bss == null) {
                        name = bssk.parts[0];
                        du = bssk.parts[1];
                        dv = bssk.parts[2];
                        grid = bssk.parts[3];
                        um = bssk.parts[8];
                        vm = bssk.parts[9];
                        uv = bssk.parts[10];
                        vv = bssk.parts[11];
                    } else {
                        du = bss.parts[0];
                        dv = bss.parts[1];
                        grid = bss.parts[2];
                        um = bssk.parts[0];
                        vm = bssk.parts[1];
                        uv = bssk.parts[2];
                        vv = bssk.parts[3];
                        foreach (var r in recs) if (r.type == "REPRESENTATION_ITEM" && r.parts.size > 0) name = r.parts[0];
                    }
                    var rows = split_args (inner (grid));
                    int nu = rows.size;
                    int nv = split_args (inner (rows[0])).size;
                    var s = new NurbsSurface (int.parse (du), int.parse (dv), nu, nv);
                    Gee.ArrayList<string>? wrows = rats != null ? split_args (inner (rats.parts[0])) : null;
                    for (int i = 0; i < nu; i++) {
                        var row = split_args (inner (rows[i]));
                        Gee.ArrayList<string>? wr = wrows != null ? split_args (inner (wrows[i])) : null;
                        for (int j = 0; j < nv; j++) s.set_point (i, j, points[ref_id (row[j])], wr != null ? double.parse (wr[j]) : 1.0);
                    }
                    s.knots_u = expand_knots (um, uv);
                    s.knots_v = expand_knots (vm, vv);
                    if (name.length >= 2) s.name = name.substring (1, name.length - 2).replace ("''", "'");
                    surfaces.add (s);
                }
            }
        }
    }
}
