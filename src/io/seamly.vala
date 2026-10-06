using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class SeamlyReport {
        public int points;
        public int curves;
        public int pieces;
        public Gee.ArrayList<string> skipped = new Gee.ArrayList<string> ();
        public string measurements_file = "";
    }

    public class Seamly {
        private static string? attr (Xml.Node* n, string name) {
            return n->get_prop (name);
        }

        private static string a (Xml.Node* n, string name, string fallback = "") {
            string? v = n->get_prop (name);
            return v ?? fallback;
        }

        private static string text_of (Xml.Node* root, string name) {
            for (Xml.Node* c = root->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c->get_content ().strip ();
            }
            return "";
        }

        private static Xml.Node* child (Xml.Node* root, string name) {
            for (Xml.Node* c = root->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
            }
            return null;
        }

        public static MeasurementTable read_measurements (string xml_text) throws FormatError {
            var doc = Xml.Parser.read_memory (xml_text, xml_text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOBLANKS);
            if (doc == null) throw new FormatError.INVALID (_("The measurements file is not valid XML"));
            var root = doc->get_root_element ();
            var t = new MeasurementTable ();
            string rn = root->name;
            t.unit = text_of (root, "unit");
            if (t.unit == "") t.unit = "cm";
            double unit_to_cm = t.unit == "mm" ? 0.1 : (t.unit == "inch" ? 2.54 : 1.0);
            if (rn == "vit" || rn == "smis") {
                t.kind = TableKind.INDIVIDUAL;
                t.name = _("Individual");
                var pers = child (root, "personal");
                if (pers != null) {
                    t.customer = (text_of (pers, "given-name") + " " + text_of (pers, "family-name")).strip ();
                    t.gender = text_of (pers, "gender");
                }
                t.base_size = "base";
                t.sizes.add ("base");
            } else if (rn == "vst" || rn == "smms") {
                t.kind = TableKind.MULTISIZE;
                t.name = _("Multisize");
                var sz = child (root, "size");
                double base_size = sz != null ? double.parse (a (sz, "base", "50")) * unit_to_cm : 50;
                for (int i = -3; i <= 3; i++) t.sizes.add (PathData.fmt (base_size + i * 2, 1));
                t.base_size = PathData.fmt (base_size, 1);
            } else {
                delete doc;
                throw new FormatError.UNSUPPORTED (_("This is not a Seamly2D or Valentina measurements file"));
            }
            var bm = child (root, "body-measurements");
            if (bm != null) {
                for (Xml.Node* m = bm->children; m != null; m = m->next) {
                    if (m->type != Xml.ElementType.ELEMENT_NODE || m->name != "m") continue;
                    string name = a (m, "name");
                    if (name == "") continue;
                    var mm = new Measurement (name.has_prefix ("@") ? name.substring (1) : name);
                    mm.full_name = a (m, "full_name");
                    mm.description = a (m, "description");
                    if (t.kind == TableKind.INDIVIDUAL) {
                        string v = a (m, "value", "0");
                        double d;
                        if (double.try_parse (v, out d)) mm.base_value = d;
                        else mm.formula = v;
                    } else {
                        mm.base_value = double.parse (a (m, "base", "0"));
                        mm.size_step = double.parse (a (m, "size_increase", "0")) * (t.unit == "mm" ? 1 : 1);
                        mm.height_step = double.parse (a (m, "height_increase", "0"));
                    }
                    t.items.add (mm);
                }
            }
            delete doc;
            return t;
        }

        public static string write_measurements (MeasurementTable t) {
            var sb = new StringBuilder ();
            sb.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            bool indiv = t.kind == TableKind.INDIVIDUAL;
            string root = indiv ? "smis" : "smms";
            sb.append ("<%s>\n".printf (root));
            sb.append ("    <version>%s</version>\n".printf (indiv ? "0.3.3" : "0.4.4"));
            sb.append ("    <read-only>false</read-only>\n");
            sb.append ("    <notes/>\n");
            sb.append ("    <unit>%s</unit>\n".printf (Markup.escape_text (t.unit)));
            sb.append ("    <pm_system>998</pm_system>\n");
            if (indiv) {
                sb.append ("    <personal>\n        <family-name/>\n        <given-name>%s</given-name>\n        <birth-date>1900-01-01</birth-date>\n        <gender>%s</gender>\n        <email/>\n    </personal>\n".printf (Markup.escape_text (t.customer), t.gender != "" ? t.gender : "unknown"));
            } else {
                double bs = double.parse (t.base_size);
                double to_unit = t.unit == "mm" ? 10 : (t.unit == "inch" ? 1 / 2.54 : 1);
                sb.append ("    <size base=\"%s\"/>\n    <height base=\"%s\"/>\n".printf (PathData.fmt (bs * to_unit, 3), PathData.fmt (176 * to_unit, 3)));
            }
            sb.append ("    <body-measurements>\n");
            foreach (var m in t.items) {
                if (indiv) {
                    string v;
                    if (m.formula != "") v = m.formula;
                    else {
                        double d = m.base_value;
                        try {
                            d = t.value (m.name, t.base_size);
                        } catch (ExprError e) {
                        }
                        v = PathData.fmt (d, 4);
                    }
                    sb.append ("        <m name=\"%s\" value=\"%s\" full_name=\"%s\" description=\"%s\"/>\n".printf (Markup.escape_text (m.name), Markup.escape_text (v), Markup.escape_text (m.full_name), Markup.escape_text (m.description)));
                } else {
                    sb.append ("        <m name=\"%s\" base=\"%s\" size_increase=\"%s\" height_increase=\"%s\" full_name=\"%s\" description=\"%s\"/>\n".printf (Markup.escape_text (m.name), PathData.fmt (m.base_value, 4), PathData.fmt (m.size_step, 4), PathData.fmt (m.height_step, 4), Markup.escape_text (m.full_name), Markup.escape_text (m.description)));
                }
            }
            sb.append ("    </body-measurements>\n");
            sb.append ("</%s>\n".printf (root));
            return sb.str;
        }

        private class Ctx {
            public Pattern pattern;
            public Gee.HashMap<string, string> ids = new Gee.HashMap<string, string> ();
            public Gee.HashMap<string, string> model_to_real = new Gee.HashMap<string, string> ();
            public Gee.HashMap<string, string> names = new Gee.HashMap<string, string> ();
            public SeamlyReport report;
            public double dx;
        }

        private static string rid (Ctx c, string? seamly_id) {
            if (seamly_id == null) return "";
            string sid = seamly_id;
            if (c.model_to_real.has_key (sid)) sid = c.model_to_real[sid];
            return c.ids.has_key (sid) ? c.ids[sid] : "";
        }

        private static string fix_formula (string? f) {
            if (f == null) return "0";
            string r = f.replace ("\n", " ").strip ();
            if (r == "") return "0";
            return r;
        }

        private static PatternPoint new_point (Ctx c, Xml.Node* n, PointKind kind) {
            string name = a (n, "name", c.pattern.next_point_name ());
            var p = new PatternPoint (c.pattern.new_id ("p"), name);
            p.kind = kind;
            p.label_dx = double.parse (a (n, "mx", "0.2")) * c.pattern.unit_mm ();
            p.label_dy = double.parse (a (n, "my", "0.2")) * c.pattern.unit_mm ();
            c.pattern.points.add (p);
            c.ids[a (n, "id")] = p.id;
            c.names[a (n, "id")] = name;
            c.report.points++;
            return p;
        }

        private static string point_name (Ctx c, string? sid) {
            string id = sid ?? "";
            if (c.model_to_real.has_key (id)) id = c.model_to_real[id];
            return c.names.has_key (id) ? c.names[id] : id;
        }

        private static void read_point (Ctx c, Xml.Node* n) {
            string type = a (n, "type");
            PatternPoint p;
            switch (type) {
                case "single":
                    p = new_point (c, n, PointKind.BASE);
                    p.fx = PathData.fmt (double.parse (a (n, "x", "0")) + c.dx, 4);
                    p.fy = a (n, "y", "0");
                    break;
                case "endLine":
                    p = new_point (c, n, PointKind.END_LINE);
                    p.a = rid (c, attr (n, "basePoint"));
                    p.flength = fix_formula (attr (n, "length"));
                    p.fangle = fix_formula (attr (n, "angle"));
                    break;
                case "alongLine":
                    p = new_point (c, n, PointKind.ALONG_LINE);
                    p.a = rid (c, attr (n, "firstPoint"));
                    p.b = rid (c, attr (n, "secondPoint"));
                    p.flength = fix_formula (attr (n, "length"));
                    break;
                case "normal":
                    p = new_point (c, n, PointKind.NORMAL);
                    p.a = rid (c, attr (n, "firstPoint"));
                    p.b = rid (c, attr (n, "secondPoint"));
                    p.flength = fix_formula (attr (n, "length"));
                    p.fangle = fix_formula (attr (n, "angle"));
                    break;
                case "bisector":
                    p = new_point (c, n, PointKind.BISECTOR);
                    p.a = rid (c, attr (n, "firstPoint"));
                    p.b = rid (c, attr (n, "secondPoint"));
                    p.c = rid (c, attr (n, "thirdPoint"));
                    p.flength = fix_formula (attr (n, "length"));
                    break;
                case "shoulder":
                    p = new_point (c, n, PointKind.CIRCLE_LINE);
                    p.a = rid (c, attr (n, "p1Line"));
                    p.b = rid (c, attr (n, "p2Line"));
                    p.c = rid (c, attr (n, "pShoulder"));
                    p.flength = fix_formula (attr (n, "length"));
                    break;
                case "pointOfContact":
                    p = new_point (c, n, PointKind.CIRCLE_CONTACT);
                    p.a = rid (c, attr (n, "firstPoint"));
                    p.b = rid (c, attr (n, "secondPoint"));
                    p.c = rid (c, attr (n, "center"));
                    p.flength = fix_formula (attr (n, "radius"));
                    break;
                case "lineIntersect":
                    p = new_point (c, n, PointKind.INTERSECT);
                    p.a = rid (c, attr (n, "p1Line1"));
                    p.b = rid (c, attr (n, "p2Line1"));
                    p.c = rid (c, attr (n, "p1Line2"));
                    p.d = rid (c, attr (n, "p2Line2"));
                    break;
                case "pointOfIntersection":
                    p = new_point (c, n, PointKind.XY);
                    p.a = rid (c, attr (n, "firstPoint"));
                    p.b = rid (c, attr (n, "secondPoint"));
                    break;
                case "height":
                    p = new_point (c, n, PointKind.FOOT);
                    p.a = rid (c, attr (n, "p1Line"));
                    p.b = rid (c, attr (n, "p2Line"));
                    p.c = rid (c, attr (n, "basePoint"));
                    break;
                case "lineIntersectAxis":
                    p = new_point (c, n, PointKind.LINE_AXIS);
                    p.a = rid (c, attr (n, "p1Line"));
                    p.b = rid (c, attr (n, "p2Line"));
                    p.c = rid (c, attr (n, "basePoint"));
                    p.fangle = fix_formula (attr (n, "angle"));
                    break;
                case "curveIntersectAxis":
                    p = new_point (c, n, PointKind.CURVE_AXIS);
                    p.a = rid (c, attr (n, "basePoint"));
                    p.b = rid (c, attr (n, "curve"));
                    p.fangle = fix_formula (attr (n, "angle"));
                    cut_segments (c, n, p, p.b);
                    break;
                case "cutSpline":
                case "cutSplinePath":
                case "cutArc": {
                    string curve = rid (c, attr (n, type == "cutSpline" ? "spline" : (type == "cutArc" ? "arc" : "splinePath")));
                    p = new_point (c, n, PointKind.ALONG_CURVE);
                    p.a = curve;
                    string len = fix_formula (attr (n, "length"));
                    string dir = a (n, "direction", "forward");
                    var parent = c.pattern.find_curve (curve);
                    if (dir == "backward" && parent != null) len = "%s - (%s)".printf (parent.name, len);
                    p.flength = len;
                    cut_segments (c, n, p, curve);
                    break;
                }
                case "modeling":
                    c.model_to_real[a (n, "id")] = a (n, "idObject");
                    break;
                default:
                    c.report.skipped.add ("%s (%s)".printf (type, a (n, "name")));
                    break;
            }
        }

        private static void cut_segments (Ctx c, Xml.Node* n, PatternPoint p, string curve) {
            var parent = c.pattern.find_curve (curve);
            if (parent == null || parent.knots.size < 2) return;
            string prefix = parent.name.has_prefix ("SplPath") ? "SplPath" : "Spl";
            var s1 = new PatternCurve (c.pattern.new_id ("c"), "%s_%s_%s".printf (prefix, point_name (c, key_of (c, parent.knots[0].point)), p.name));
            s1.kind = CurveKind.SEGMENT;
            s1.parent = curve;
            s1.knots.add (new CurveKnot (parent.knots[0].point));
            s1.knots.add (new CurveKnot (p.id));
            var s2 = new PatternCurve (c.pattern.new_id ("c"), "%s_%s_%s".printf (prefix, p.name, point_name (c, key_of (c, parent.knots[parent.knots.size - 1].point))));
            s2.kind = CurveKind.SEGMENT;
            s2.parent = curve;
            s2.knots.add (new CurveKnot (p.id));
            s2.knots.add (new CurveKnot (parent.knots[parent.knots.size - 1].point));
            c.pattern.curves.add (s1);
            c.pattern.curves.add (s2);
            int own = int.parse (a (n, "id"));
            c.ids[(own + 1).to_string ()] = s1.id;
            c.ids[(own + 2).to_string ()] = s2.id;
        }

        private static string key_of (Ctx c, string internal_id) {
            foreach (var e in c.ids.entries) if (e.value == internal_id) return e.key;
            return internal_id;
        }

        private static void read_spline (Ctx c, Xml.Node* n) {
            string type = a (n, "type");
            string sid = a (n, "id");
            PatternCurve? curve = null;
            switch (type) {
                case "simpleInteractive": {
                    string p1 = rid (c, attr (n, "point1"));
                    string p4 = rid (c, attr (n, "point4"));
                    curve = new PatternCurve (c.pattern.new_id ("c"), "Spl_%s_%s".printf (point_name (c, attr (n, "point1")), point_name (c, attr (n, "point4"))));
                    curve.kind = CurveKind.PATH;
                    var k0 = new CurveKnot (p1);
                    var k1 = new CurveKnot (p4);
                    k0.angle_out = fix_formula (attr (n, "angle1"));
                    k0.len_out = fix_formula (attr (n, "length1"));
                    k1.angle_in = fix_formula (attr (n, "angle2"));
                    k1.len_in = fix_formula (attr (n, "length2"));
                    curve.knots.add (k0);
                    curve.knots.add (k1);
                    break;
                }
                case "simple": {
                    string n1 = point_name (c, attr (n, "point1"));
                    string n4 = point_name (c, attr (n, "point4"));
                    curve = new PatternCurve (c.pattern.new_id ("c"), "Spl_%s_%s".printf (n1, n4));
                    curve.kind = CurveKind.PATH;
                    string l = "Line_%s_%s / sqrt(2) * 4 / 3 * tan(pi / 8) * %s".printf (n1, n4, a (n, "kCurve", "1"));
                    var k0 = new CurveKnot (rid (c, attr (n, "point1")));
                    var k1 = new CurveKnot (rid (c, attr (n, "point4")));
                    k0.angle_out = a (n, "angle1", "0");
                    k0.len_out = "%s * %s".printf (l, a (n, "kAsm1", "1"));
                    k1.angle_in = a (n, "angle2", "0");
                    k1.len_in = "%s * %s".printf (l, a (n, "kAsm2", "1"));
                    curve.knots.add (k0);
                    curve.knots.add (k1);
                    break;
                }
                case "cubicBezier": {
                    string[] ids = { rid (c, attr (n, "point1")), rid (c, attr (n, "point2")), rid (c, attr (n, "point3")), rid (c, attr (n, "point4")) };
                    string[] nm = { point_name (c, attr (n, "point1")), point_name (c, attr (n, "point2")), point_name (c, attr (n, "point3")), point_name (c, attr (n, "point4")) };
                    curve = new PatternCurve (c.pattern.new_id ("c"), "Spl_%s_%s".printf (nm[0], nm[3]));
                    curve.kind = CurveKind.PATH;
                    var k0 = new CurveKnot (ids[0]);
                    var k1 = new CurveKnot (ids[3]);
                    k0.angle_out = "AngleLine_%s_%s".printf (nm[0], nm[1]);
                    k0.len_out = "Line_%s_%s".printf (nm[0], nm[1]);
                    k1.angle_in = "AngleLine_%s_%s".printf (nm[3], nm[2]);
                    k1.len_in = "Line_%s_%s".printf (nm[3], nm[2]);
                    curve.knots.add (k0);
                    curve.knots.add (k1);
                    break;
                }
                case "pathInteractive":
                case "path": {
                    var names = new Gee.ArrayList<string> ();
                    var knots = new Gee.ArrayList<CurveKnot> ();
                    for (Xml.Node* pp = n->children; pp != null; pp = pp->next) {
                        if (pp->type != Xml.ElementType.ELEMENT_NODE || pp->name != "pathPoint") continue;
                        var k = new CurveKnot (rid (c, attr (pp, "pSpline")));
                        names.add (point_name (c, attr (pp, "pSpline")));
                        if (type == "pathInteractive") {
                            k.angle_in = fix_formula (attr (pp, "angle1"));
                            k.len_in = fix_formula (attr (pp, "length1"));
                            k.angle_out = fix_formula (attr (pp, "angle2"));
                            k.len_out = fix_formula (attr (pp, "length2"));
                        } else {
                            k.angle_in = "(%s) + 180".printf (a (pp, "angle", "0"));
                            k.angle_out = a (pp, "angle", "0");
                            k.len_in = "1 * %s".printf (a (pp, "kAsm1", "1"));
                            k.len_out = "1 * %s".printf (a (pp, "kAsm2", "1"));
                        }
                        knots.add (k);
                    }
                    if (knots.size < 2) break;
                    curve = new PatternCurve (c.pattern.new_id ("c"), "SplPath_%s_%s".printf (names[0], names[names.size - 1]));
                    curve.kind = CurveKind.PATH;
                    curve.knots.add_all (knots);
                    break;
                }
                case "modelingSpline":
                case "modelingPath":
                    c.model_to_real[sid] = a (n, "idObject");
                    return;
                default:
                    c.report.skipped.add ("spline %s".printf (type));
                    return;
            }
            if (curve == null) return;
            while (c.pattern.curve_by_name (curve.name) != null) curve.name += "_";
            c.pattern.curves.add (curve);
            c.ids[sid] = curve.id;
            c.report.curves++;
        }

        private static void read_line (Ctx c, Xml.Node* n) {
            var curve = new PatternCurve (c.pattern.new_id ("c"), "Line_%s_%s".printf (point_name (c, attr (n, "firstPoint")), point_name (c, attr (n, "secondPoint"))));
            curve.kind = CurveKind.LINE;
            curve.knots.add (new CurveKnot (rid (c, attr (n, "firstPoint"))));
            curve.knots.add (new CurveKnot (rid (c, attr (n, "secondPoint"))));
            if (curve.knots[0].point == "" || curve.knots[1].point == "") return;
            while (c.pattern.curve_by_name (curve.name) != null) curve.name += "_";
            c.pattern.curves.add (curve);
            c.ids[a (n, "id")] = curve.id;
        }

        private static void read_arc (Ctx c, Xml.Node* n) {
            string type = a (n, "type");
            if (type == "modeling") {
                c.model_to_real[a (n, "id")] = a (n, "idObject");
                return;
            }
            if (type != "simple") {
                c.report.skipped.add ("arc %s".printf (type));
                return;
            }
            string center = rid (c, attr (n, "center"));
            string cname = point_name (c, attr (n, "center"));
            string r = fix_formula (attr (n, "radius"));
            string a1 = fix_formula (attr (n, "angle1"));
            string a2 = fix_formula (attr (n, "angle2"));
            var s = c.pattern.add_point (PointKind.END_LINE, "Arc_%s_s".printf (cname));
            s.a = center;
            s.flength = r;
            s.fangle = a1;
            s.hidden = true;
            var m = c.pattern.add_point (PointKind.END_LINE, "Arc_%s_m".printf (cname));
            m.a = center;
            m.flength = r;
            m.fangle = "(%s + %s) / 2".printf (a1, a2);
            m.hidden = true;
            var e = c.pattern.add_point (PointKind.END_LINE, "Arc_%s_e".printf (cname));
            e.a = center;
            e.flength = r;
            e.fangle = a2;
            e.hidden = true;
            var curve = c.pattern.add_curve ({ s.id, m.id, e.id }, CurveKind.PATH);
            curve.name = "Arc_%s_%s".printf (cname, a (n, "id"));
            string k = "(%s) * 4 / 3 * tan(((%s) - (%s)) * pi / 720)".printf (r, a2, a1);
            curve.knots[0].angle_out = "(%s) + 90".printf (a1);
            curve.knots[0].len_out = k;
            curve.knots[1].angle_in = "(%s + %s) / 2 - 90".printf (a1, a2);
            curve.knots[1].len_in = k;
            curve.knots[1].angle_out = "(%s + %s) / 2 + 90".printf (a1, a2);
            curve.knots[1].len_out = k;
            curve.knots[2].angle_in = "(%s) - 90".printf (a2);
            curve.knots[2].len_in = k;
            c.ids[a (n, "id")] = curve.id;
            c.report.curves++;
        }

        private static void read_operation (Ctx c, Xml.Node* n) {
            string type = a (n, "type");
            if (type != "rotation" && type != "moving" && type != "flippingByLine") {
                c.report.skipped.add ("operation %s".printf (type));
                return;
            }
            Xml.Node* src = child (n, "source");
            Xml.Node* dst = child (n, "destination");
            if (src == null || dst == null) return;
            var sources = new Gee.ArrayList<string> ();
            for (Xml.Node* it = src->children; it != null; it = it->next) if (it->type == Xml.ElementType.ELEMENT_NODE) sources.add (a (it, "idObject"));
            int i = 0;
            string suffix = a (n, "suffix", "a");
            for (Xml.Node* it = dst->children; it != null; it = it->next) {
                if (it->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (i >= sources.size) break;
                string srcid = sources[i++];
                string dstid = a (it, "idObject");
                string real = rid (c, srcid);
                var sp = c.pattern.find_point (real);
                if (sp == null) {
                    c.report.skipped.add ("%s of a curve".printf (type));
                    continue;
                }
                PatternPoint p;
                if (type == "rotation") {
                    p = c.pattern.add_point (PointKind.ROTATE, sp.name + suffix);
                    p.a = real;
                    p.b = rid (c, attr (n, "center"));
                    p.fangle = fix_formula (attr (n, "angle"));
                } else if (type == "moving") {
                    p = c.pattern.add_point (PointKind.OFFSET, sp.name + suffix);
                    p.a = real;
                    string len = fix_formula (attr (n, "length"));
                    string ang = fix_formula (attr (n, "angle"));
                    p.fx = "(%s) * cosD(%s)".printf (len, ang);
                    p.fy = "-(%s) * sinD(%s)".printf (len, ang);
                } else {
                    c.report.skipped.add ("flipping of %s".printf (sp.name));
                    continue;
                }
                c.ids[dstid] = p.id;
                c.names[dstid] = p.name;
                c.report.points++;
            }
        }

        private static void read_detail (Ctx c, Xml.Node* n) {
            var piece = new Piece (c.pattern.new_id ("d"), a (n, "name", _("Piece")));
            bool v2 = a (n, "version") == "2";
            double width = double.parse (a (n, "width", "1"));
            bool sa_on = v2 ? a (n, "seamAllowance", "0") == "1" || a (n, "seamAllowance") == "true" : a (n, "supplement", "0") == "1";
            if (!v2) width = width / 10.0 * (10.0 / c.pattern.unit_mm ());
            piece.seam_allowance = PathData.fmt (width, 4);
            piece.built_in = !sa_on;
            Xml.Node* nodes = child (n, "nodes");
            if (nodes == null) nodes = n;
            for (Xml.Node* nd = nodes->children; nd != null; nd = nd->next) {
                if (nd->type != Xml.ElementType.ELEMENT_NODE || nd->name != "node") continue;
                if (a (nd, "excluded") == "true") continue;
                string type = a (nd, "type");
                string real = rid (c, attr (nd, "idObject"));
                if (real == "") continue;
                bool is_curve = type != "NodePoint";
                var pn = new PieceNode (real, is_curve);
                pn.reverse = a (nd, "reverse", "0") == "1";
                string after = a (nd, "after");
                if (after != "" && sa_on) pn.sa_after = after;
                string pm = a (nd, "passmark", a (nd, "notch"));
                if (pm == "true") {
                    pn.notch = true;
                    string line = a (nd, "passmarkLine", a (nd, "notchType", "one"));
                    pn.notch_type = line == "tMark" ? "t" : (line == "vMark" ? "v" : "slit");
                }
                piece.nodes.add (pn);
            }
            Xml.Node* grain = child (n, "grainline");
            if (grain != null) {
                piece.grain_angle = double.parse (a (grain, "rotation", "90"));
                string ga = rid (c, attr (grain, "topPin"));
                string gb = rid (c, attr (grain, "bottomPin"));
                if (ga != "" && gb != "") {
                    piece.grain_a = gb;
                    piece.grain_b = ga;
                }
            }
            Xml.Node* data = child (n, "data");
            if (data != null) {
                string letter = a (data, "letter");
                if (letter != "") piece.code = letter;
                for (Xml.Node* mc = data->children; mc != null; mc = mc->next) {
                    if (mc->type == Xml.ElementType.ELEMENT_NODE && mc->name == "mcp") piece.quantity = int.max (1, int.parse (a (mc, "cutNumber", "1")));
                }
            }
            piece.place_x = double.parse (a (n, "mx", "0")) * c.pattern.unit_mm ();
            piece.place_y = double.parse (a (n, "my", "0")) * c.pattern.unit_mm ();
            if (piece.nodes.size >= 2) {
                c.pattern.pieces.add (piece);
                c.report.pieces++;
            }
        }

        public static Pattern read_pattern (string xml_text, out SeamlyReport report, MeasurementTable? table = null) throws FormatError {
            report = new SeamlyReport ();
            var doc = Xml.Parser.read_memory (xml_text, xml_text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOBLANKS);
            if (doc == null) throw new FormatError.INVALID (_("The pattern file is not valid XML"));
            var root = doc->get_root_element ();
            if (root->name != "pattern") {
                delete doc;
                throw new FormatError.UNSUPPORTED (_("This is not a Seamly2D or Valentina pattern"));
            }
            var c = new Ctx ();
            c.report = report;
            c.pattern = new Pattern ();
            c.pattern.unit = text_of (root, "unit");
            if (c.pattern.unit == "") c.pattern.unit = "cm";
            report.measurements_file = text_of (root, "measurements");
            if (table != null) {
                c.pattern.table = table;
                c.pattern.active_size = table.base_size;
            } else {
                c.pattern.table = new MeasurementTable ();
                c.pattern.table.base_size = "base";
                c.pattern.table.sizes.add ("base");
                c.pattern.active_size = "base";
            }
            Xml.Node* incs = child (root, "increments");
            if (incs != null) {
                for (Xml.Node* i = incs->children; i != null; i = i->next) {
                    if (i->type != Xml.ElementType.ELEMENT_NODE || i->name != "increment") continue;
                    string nm = a (i, "name");
                    var inc = new Increment (nm.has_prefix ("#") ? nm.substring (1) : nm, fix_formula (attr (i, "formula")));
                    inc.description = a (i, "description");
                    c.pattern.increments.add (inc);
                }
            }
            int draw_index = 0;
            for (Xml.Node* d = root->children; d != null; d = d->next) {
                if (d->type != Xml.ElementType.ELEMENT_NODE || d->name != "draw") continue;
                c.dx = 0;
                draw_index++;
                Xml.Node* calc = child (d, "calculation");
                if (calc != null) {
                    for (Xml.Node* n = calc->children; n != null; n = n->next) {
                        if (n->type != Xml.ElementType.ELEMENT_NODE) continue;
                        switch (n->name) {
                            case "point": read_point (c, n); break;
                            case "spline": read_spline (c, n); break;
                            case "line": read_line (c, n); break;
                            case "arc": read_arc (c, n); break;
                            case "operation": read_operation (c, n); break;
                            default: c.report.skipped.add (n->name); break;
                        }
                    }
                }
                Xml.Node* model = child (d, "modeling");
                if (model != null) {
                    for (Xml.Node* n = model->children; n != null; n = n->next) {
                        if (n->type != Xml.ElementType.ELEMENT_NODE) continue;
                        string id = a (n, "id");
                        string obj = a (n, "idObject");
                        if (id != "" && obj != "") c.model_to_real[id] = obj;
                    }
                }
                Xml.Node* details = child (d, "details");
                if (details != null) {
                    for (Xml.Node* n = details->children; n != null; n = n->next) {
                        if (n->type == Xml.ElementType.ELEMENT_NODE && n->name == "detail") read_detail (c, n);
                    }
                }
            }
            delete doc;
            return c.pattern;
        }

        private static string nid (Gee.HashMap<string, int> num, string internal_id) {
            return num.has_key (internal_id) ? num[internal_id].to_string () : "0";
        }

        private static string e (string s) {
            return Markup.escape_text (s);
        }

        private static void write_point (StringBuilder sb, Pattern p, PatternPoint pt, Gee.HashMap<string, int> num) {
            string common = "id=\"%s\" name=\"%s\" mx=\"%s\" my=\"%s\"".printf (nid (num, pt.id), e (pt.name), PathData.fmt (pt.label_dx / p.unit_mm (), 4), PathData.fmt (pt.label_dy / p.unit_mm (), 4));
            switch (pt.kind) {
                case PointKind.BASE:
                    sb.append ("            <point type=\"single\" %s x=\"%s\" y=\"%s\"/>\n".printf (common, e (pt.fx), e (pt.fy)));
                    break;
                case PointKind.END_LINE:
                    sb.append ("            <point type=\"endLine\" %s typeLine=\"hair\" lineColor=\"black\" basePoint=\"%s\" length=\"%s\" angle=\"%s\"/>\n".printf (common, nid (num, pt.a), e (pt.flength), e (pt.fangle)));
                    break;
                case PointKind.ALONG_LINE:
                    sb.append ("            <point type=\"alongLine\" %s typeLine=\"none\" lineColor=\"black\" firstPoint=\"%s\" secondPoint=\"%s\" length=\"%s\"/>\n".printf (common, nid (num, pt.a), nid (num, pt.b), e (pt.flength)));
                    break;
                case PointKind.MIDPOINT:
                    sb.append ("            <point type=\"alongLine\" %s typeLine=\"none\" lineColor=\"black\" firstPoint=\"%s\" secondPoint=\"%s\" length=\"%s\"/>\n".printf (common, nid (num, pt.a), nid (num, pt.b), e ("Line_%s_%s/2".printf (p.find_point (pt.a).name, p.find_point (pt.b).name))));
                    break;
                case PointKind.NORMAL:
                    sb.append ("            <point type=\"normal\" %s typeLine=\"hair\" lineColor=\"black\" firstPoint=\"%s\" secondPoint=\"%s\" length=\"%s\" angle=\"%s\"/>\n".printf (common, nid (num, pt.a), nid (num, pt.b), e (pt.flength), e (pt.fangle)));
                    break;
                case PointKind.INTERSECT:
                    sb.append ("            <point type=\"lineIntersect\" %s p1Line1=\"%s\" p2Line1=\"%s\" p1Line2=\"%s\" p2Line2=\"%s\"/>\n".printf (common, nid (num, pt.a), nid (num, pt.b), nid (num, pt.c), nid (num, pt.d)));
                    break;
                case PointKind.BISECTOR:
                    sb.append ("            <point type=\"bisector\" %s typeLine=\"hair\" lineColor=\"black\" firstPoint=\"%s\" secondPoint=\"%s\" thirdPoint=\"%s\" length=\"%s\"/>\n".printf (common, nid (num, pt.a), nid (num, pt.b), nid (num, pt.c), e (pt.flength)));
                    break;
                case PointKind.CIRCLE_LINE:
                    sb.append ("            <point type=\"shoulder\" %s typeLine=\"hair\" lineColor=\"black\" p1Line=\"%s\" p2Line=\"%s\" pShoulder=\"%s\" length=\"%s\"/>\n".printf (common, nid (num, pt.a), nid (num, pt.b), nid (num, pt.c), e (pt.flength)));
                    break;
                case PointKind.FOOT:
                    sb.append ("            <point type=\"height\" %s typeLine=\"hair\" lineColor=\"black\" p1Line=\"%s\" p2Line=\"%s\" basePoint=\"%s\"/>\n".printf (common, nid (num, pt.a), nid (num, pt.b), nid (num, pt.c)));
                    break;
                case PointKind.XY:
                    sb.append ("            <point type=\"pointOfIntersection\" %s firstPoint=\"%s\" secondPoint=\"%s\"/>\n".printf (common, nid (num, pt.a), nid (num, pt.b)));
                    break;
                case PointKind.LINE_AXIS:
                    sb.append ("            <point type=\"lineIntersectAxis\" %s typeLine=\"hair\" lineColor=\"black\" p1Line=\"%s\" p2Line=\"%s\" basePoint=\"%s\" angle=\"%s\"/>\n".printf (common, nid (num, pt.a), nid (num, pt.b), nid (num, pt.c), e (pt.fangle)));
                    break;
                case PointKind.CURVE_AXIS:
                    sb.append ("            <point type=\"curveIntersectAxis\" %s typeLine=\"hair\" lineColor=\"black\" basePoint=\"%s\" curve=\"%s\" angle=\"%s\"/>\n".printf (common, nid (num, pt.a), nid (num, pt.b), e (pt.fangle)));
                    break;
                case PointKind.ALONG_CURVE:
                    sb.append ("            <point type=\"cutSplinePath\" %s color=\"black\" splinePath=\"%s\" length=\"%s\"/>\n".printf (common, nid (num, pt.a), e (pt.flength)));
                    break;
                case PointKind.OFFSET:
                    sb.append ("            <point type=\"endLine\" %s typeLine=\"none\" lineColor=\"black\" basePoint=\"%s\" length=\"%s\" angle=\"%s\"/>\n".printf (common, nid (num, pt.a),
                        e ("sqrt((%s)^2 + (%s)^2)".printf (pt.fx, pt.fy)), e ("atan2(-(%s), %s) * 180 / pi".printf (pt.fy, pt.fx))));
                    break;
                default:
                    sb.append ("            <point type=\"single\" %s x=\"0\" y=\"0\"/>\n".printf (common));
                    break;
            }
        }

        private static void write_curve (StringBuilder sb, PatternCurve cv, Gee.HashMap<string, int> num) {
            if (cv.kind == CurveKind.SEGMENT) return;
            if (cv.kind == CurveKind.LINE && cv.knots.size == 2) {
                sb.append ("            <line id=\"%s\" typeLine=\"hair\" lineColor=\"black\" firstPoint=\"%s\" secondPoint=\"%s\"/>\n".printf (nid (num, cv.id), nid (num, cv.knots[0].point), nid (num, cv.knots[1].point)));
                return;
            }
            if (cv.knots.size == 2) {
                var k0 = cv.knots[0];
                var k1 = cv.knots[1];
                sb.append ("            <spline type=\"simpleInteractive\" id=\"%s\" color=\"black\" point1=\"%s\" point4=\"%s\" angle1=\"%s\" length1=\"%s\" angle2=\"%s\" length2=\"%s\"/>\n".printf (
                    nid (num, cv.id), nid (num, k0.point), nid (num, k1.point), e (k0.angle_out != "" ? k0.angle_out : "0"), e (k0.len_out != "" ? k0.len_out : "0"), e (k1.angle_in != "" ? k1.angle_in : "0"), e (k1.len_in != "" ? k1.len_in : "0")));
                return;
            }
            sb.append ("            <spline type=\"pathInteractive\" id=\"%s\" color=\"black\">\n".printf (nid (num, cv.id)));
            foreach (var k in cv.knots) {
                string ai = k.angle_in != "" ? k.angle_in : "0";
                string ao = k.angle_out != "" ? k.angle_out : "(%s) + 180".printf (ai);
                if (k.angle_in == "" && k.angle_out != "") ai = "(%s) + 180".printf (k.angle_out);
                sb.append ("                <pathPoint pSpline=\"%s\" angle1=\"%s\" angle2=\"%s\" length1=\"%s\" length2=\"%s\"/>\n".printf (nid (num, k.point), e (ai), e (ao), e (k.len_in != "" ? k.len_in : "0"), e (k.len_out != "" ? k.len_out : "0")));
            }
            sb.append ("            </spline>\n");
        }

        public static string write_pattern (Pattern p, string measurements_file) {
            var sb = new StringBuilder ();
            sb.append ("<?xml version='1.0' encoding='UTF-8'?>\n<pattern>\n");
            sb.append ("    <version>0.6.0</version>\n");
            sb.append ("    <unit>%s</unit>\n".printf (p.unit));
            sb.append ("    <description/>\n    <notes/>\n");
            sb.append ("    <measurements>%s</measurements>\n".printf (Markup.escape_text (measurements_file)));
            sb.append ("    <increments>\n");
            foreach (var inc in p.increments) sb.append ("        <increment name=\"#%s\" description=\"%s\" formula=\"%s\"/>\n".printf (Markup.escape_text (inc.name), Markup.escape_text (inc.description), Markup.escape_text (inc.formula)));
            sb.append ("    </increments>\n");
            sb.append ("    <draw name=\"%s\">\n        <calculation>\n".printf ("Atelier"));
            var num = new Gee.HashMap<string, int> ();
            int next = 1;
            foreach (var pt in p.points) {
                num[pt.id] = next++;
                if (pt.kind == PointKind.ALONG_CURVE || pt.kind == PointKind.CURVE_AXIS) next += 2;
            }
            foreach (var cv in p.curves) {
                if (cv.kind == CurveKind.SEGMENT && cv.knots.size == 2) {
                    foreach (var pt in p.points) {
                        if (pt.kind != PointKind.ALONG_CURVE && pt.kind != PointKind.CURVE_AXIS) continue;
                        string host = pt.kind == PointKind.ALONG_CURVE ? pt.a : pt.b;
                        if (host != cv.parent) continue;
                        if (cv.knots[1].point == pt.id) num[cv.id] = num[pt.id] + 1;
                        else if (cv.knots[0].point == pt.id) num[cv.id] = num[pt.id] + 2;
                    }
                    if (num.has_key (cv.id)) continue;
                }
                num[cv.id] = next++;
            }
            var done_pts = new Gee.HashSet<string> ();
            var done_curves = new Gee.HashSet<string> ();
            foreach (var pt in p.points) {
                write_point (sb, p, pt, num);
                done_pts.add (pt.id);
                bool again = true;
                while (again) {
                    again = false;
                    foreach (var cv in p.curves) {
                        if (done_curves.contains (cv.id)) continue;
                        bool ready = cv.parent == "" || done_curves.contains (cv.parent);
                        foreach (var k in cv.knots) if (!done_pts.contains (k.point)) ready = false;
                        if (!ready) continue;
                        write_curve (sb, cv, num);
                        done_curves.add (cv.id);
                        again = true;
                    }
                }
            }
            sb.append ("        </calculation>\n        <modeling/>\n        <details>\n");
            foreach (var pc in p.pieces) {
                if (pc.is_fixed ()) continue;
                sb.append ("            <detail closed=\"1\" id=\"%d\" name=\"%s\" seamAllowance=\"%s\" width=\"%s\" mx=\"0\" my=\"0\" version=\"2\">\n                <nodes>\n".printf (next++, e (pc.name), pc.built_in ? "0" : "1", e (pc.seam_allowance)));
                foreach (var nd in pc.nodes) {
                    string t = nd.is_curve ? "NodeSplinePath" : "NodePoint";
                    sb.append ("                    <node type=\"%s\" idObject=\"%s\"%s%s%s/>\n".printf (t, nid (num, nd.ref_id), nd.reverse ? " reverse=\"1\"" : "", nd.sa_after != "" ? " after=\"%s\"".printf (e (nd.sa_after)) : "", nd.notch ? " passmark=\"true\" passmarkLine=\"one\"" : ""));
                }
                sb.append ("                </nodes>\n            </detail>\n");
            }
            sb.append ("        </details>\n    </draw>\n</pattern>\n");
            return sb.str;
        }
    }
}
