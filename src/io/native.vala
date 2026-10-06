using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public errordomain FormatError {
        INVALID,
        UNSUPPORTED
    }

    public class NativeFormat {
        public const string MIME = "application/x-atelier";
        public const int VERSION = 1;

        public static uint8[] save (Project p) throws Error {
            var zip = new ZipWriter ();
            zip.add_text ("mimetype", MIME, false);
            zip.add_text ("project.json", to_json (p));
            foreach (var l in p.sketch.all_layers ()) {
                if (l.kind == LayerKind.IMAGE && l.image_data != null) zip.add ("sketch/images/%s.png".printf (l.id), l.image_data.get_data (), false);
            }
            foreach (var sheet in p.flats) zip.add_text ("flats/%s.svg".printf (sheet.id), SvgExport.flat_sheet (sheet, p.colorway ()));
            try {
                zip.add_text ("pattern/pattern.svg", SvgExport.pattern (p.pattern, p.pattern.evaluate ()));
            } catch (Error e) {
            }
            zip.add_text ("pattern/measurements.csv", Tables.measurements_csv (p.pattern.table));
            zip.add_text ("techpack/bom.csv", Tables.bom_csv (p.techpack, p.colorways));
            zip.add_text ("sketch/sketch.svg", SvgExport.sketch (p.sketch));
            return zip.finish ();
        }

        public static void save_to (Project p, string path) throws Error {
            var data = save (p);
            FileUtils.set_data (path, data);
        }

        public static Project load (string path) throws Error {
            uint8[] data;
            FileUtils.get_data (path, out data);
            var p = load_data (data);
            p.path = path;
            p.title = title_from_path (path);
            p.modified = false;
            return p;
        }

        public static string title_from_path (string path) {
            string b = Path.get_basename (path);
            int dot = b.last_index_of (".");
            return dot > 0 ? b.substring (0, dot) : b;
        }

        public static Project load_data (uint8[] data) throws Error {
            var zip = new ZipReader (data);
            string? json = zip.read_text ("project.json");
            if (json == null) throw new FormatError.INVALID (_("The project file is damaged"));
            var p = from_json (json);
            foreach (var l in p.sketch.all_layers ()) {
                string name = "sketch/images/%s.png".printf (l.id);
                if (l.kind == LayerKind.IMAGE && zip.has (name)) l.image_data = new Bytes (zip.read (name));
            }
            return p;
        }

        private static void pts (Json.Builder b, Point[] list) {
            b.begin_array ();
            foreach (var q in list) {
                b.add_double_value (round (q.x));
                b.add_double_value (round (q.y));
            }
            b.end_array ();
        }

        private static Gee.List<string> sorted (Gee.Set<string> keys) {
            var l = new Gee.ArrayList<string> ();
            l.add_all (keys);
            l.sort ();
            return l;
        }

        private static double round (double v) {
            return Math.round (v * 1000) / 1000;
        }

        private static Point[] read_pts (Json.Array? a) {
            Point[] r = {};
            if (a == null) return r;
            for (uint i = 0; i + 1 < a.get_length (); i += 2) r += Point (a.get_double_element (i), a.get_double_element (i + 1));
            return r;
        }

        private static string s (Json.Object o, string k, string d = "") {
            return o.has_member (k) && o.get_member (k).get_node_type () == Json.NodeType.VALUE ? o.get_string_member (k) ?? d : d;
        }

        private static double n (Json.Object o, string k, double d = 0) {
            if (!o.has_member (k)) return d;
            var node = o.get_member (k);
            if (node.get_node_type () != Json.NodeType.VALUE) return d;
            if (node.get_value_type () == typeof (int64)) return (double) node.get_int ();
            if (node.get_value_type () == typeof (double)) return node.get_double ();
            return d;
        }

        private static bool bo (Json.Object o, string k, bool d = false) {
            return o.has_member (k) ? o.get_boolean_member (k) : d;
        }

        private static Json.Array? arr (Json.Object o, string k) {
            return o.has_member (k) && o.get_member (k).get_node_type () == Json.NodeType.ARRAY ? o.get_array_member (k) : null;
        }

        private static Json.Object? obj (Json.Object o, string k) {
            return o.has_member (k) && o.get_member (k).get_node_type () == Json.NodeType.OBJECT ? o.get_object_member (k) : null;
        }

        public static string to_json (Project p) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("format").add_string_value ("atelier");
            b.set_member_name ("version").add_int_value (VERSION);
            b.set_member_name ("title").add_string_value (p.title);
            b.set_member_name ("trade").add_string_value (p.trade);
            b.set_member_name ("slots").begin_array ();
            foreach (var sl in p.slots) b.add_string_value (sl);
            b.end_array ();
            b.set_member_name ("active_colorway").add_string_value (p.active_colorway);
            b.set_member_name ("colorways").begin_array ();
            foreach (var cw in p.colorways) {
                b.begin_object ();
                b.set_member_name ("name").add_string_value (cw.name);
                b.set_member_name ("colors").begin_object ();
                foreach (var ek in sorted (cw.colors.keys)) {
                    var ev = cw.colors[ek];
                    b.set_member_name (ek).begin_object ();
                    b.set_member_name ("rgba").add_string_value (ev.color.to_hex (true));
                    b.set_member_name ("name").add_string_value (ev.name);
                    b.set_member_name ("code").add_string_value (ev.code);
                    b.set_member_name ("book").add_string_value (ev.book);
                    b.end_object ();
                }
                b.end_object ();
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("sketch");
            write_sketch (b, p.sketch);
            b.set_member_name ("pattern");
            write_pattern (b, p.pattern);
            b.set_member_name ("flats").begin_array ();
            foreach (var sh in p.flats) write_sheet (b, sh);
            b.end_array ();
            b.set_member_name ("techpack");
            write_techpack (b, p.techpack);
            b.set_member_name ("garment");
            write_garment (b, p.garment);
            b.set_member_name ("marker");
            write_marker (b, p.marker);
            b.set_member_name ("product");
            write_product (b, p.product);
            b.end_object ();
            var gen = new Json.Generator ();
            gen.pretty = true;
            gen.indent = 1;
            gen.set_root (b.get_root ());
            return gen.to_data (null);
        }

        public static Project from_json (string text) throws Error {
            var parser = new Json.Parser ();
            parser.load_from_data (text);
            var root = parser.get_root ();
            if (root == null || root.get_node_type () != Json.NodeType.OBJECT) throw new FormatError.INVALID (_("The project file is damaged"));
            var o = root.get_object ();
            if (s (o, "format") != "atelier") throw new FormatError.INVALID (_("This is not an Atelier project"));
            var p = new Project ();
            p.title = s (o, "title");
            p.trade = s (o, "trade", "fashion");
            var sl = arr (o, "slots");
            if (sl != null) {
                p.slots.clear ();
                foreach (var e in sl.get_elements ()) p.slots.add (e.get_string ());
            }
            var cws = arr (o, "colorways");
            if (cws != null) {
                p.colorways.clear ();
                foreach (var e in cws.get_elements ()) {
                    var co = e.get_object ();
                    var cw = new Colorway (s (co, "name"));
                    var cols = obj (co, "colors");
                    if (cols != null) {
                        foreach (var k in cols.get_members ()) {
                            var c = cols.get_object_member (k);
                            var cr = new ColorRef (Rgba.parse (s (c, "rgba")), s (c, "name"));
                            cr.code = s (c, "code");
                            cr.book = s (c, "book");
                            cw.colors[k] = cr;
                        }
                    }
                    p.colorways.add (cw);
                }
            }
            p.active_colorway = s (o, "active_colorway", p.colorways.size > 0 ? p.colorways[0].name : "");
            var so = obj (o, "sketch");
            if (so != null) p.sketch = read_sketch (so);
            var po = obj (o, "pattern");
            if (po != null) p.pattern = read_pattern (po);
            var fl = arr (o, "flats");
            if (fl != null) foreach (var e in fl.get_elements ()) p.flats.add (read_sheet (e.get_object ()));
            var tp = obj (o, "techpack");
            if (tp != null) p.techpack = read_techpack (tp);
            var go = obj (o, "garment");
            if (go != null) p.garment = read_garment (go);
            var mo = obj (o, "marker");
            if (mo != null) p.marker = read_marker (mo);
            var pr = obj (o, "product");
            if (pr != null) p.product = read_product (pr);
            return p;
        }

        private static void write_sketch (Json.Builder b, Sketch sk) {
            b.begin_object ();
            b.set_member_name ("paper").add_string_value (sk.paper.to_hex ());
            b.set_member_name ("record_timelapse").add_boolean_value (sk.record_timelapse);
            b.set_member_name ("layers").begin_array ();
            foreach (var l in sk.layers) write_layer (b, l);
            b.end_array ();
            b.set_member_name ("brushes").begin_array ();
            foreach (var br in sk.brushes) {
                b.begin_object ();
                b.set_member_name ("id").add_string_value (br.id);
                b.set_member_name ("name").add_string_value (br.name);
                b.set_member_name ("kind").add_string_value (br.kind.to_id ());
                b.set_member_name ("size").add_double_value (br.size);
                b.set_member_name ("min_size").add_double_value (br.min_size);
                b.set_member_name ("opacity").add_double_value (br.opacity);
                b.set_member_name ("hardness").add_double_value (br.hardness);
                b.set_member_name ("pressure_curve").add_string_value (br.pressure_curve.to_string ());
                b.set_member_name ("pressure_size").add_boolean_value (br.pressure_size);
                b.set_member_name ("pressure_opacity").add_boolean_value (br.pressure_opacity);
                b.set_member_name ("tilt_size").add_double_value (br.tilt_size);
                b.set_member_name ("velocity_thin").add_double_value (br.velocity_thin);
                b.set_member_name ("texture").add_double_value (br.texture);
                b.end_object ();
            }
            b.end_array ();
            var g = sk.guides;
            b.set_member_name ("guides").begin_object ();
            b.set_member_name ("ruler").add_boolean_value (g.ruler_on);
            b.set_member_name ("ruler_pts");
            pts (b, { g.ruler_a, g.ruler_b });
            b.set_member_name ("ellipse").add_boolean_value (g.ellipse_on);
            b.set_member_name ("ellipse_geom").begin_array ();
            foreach (var v in new double[] { g.ellipse_center.x, g.ellipse_center.y, g.ellipse_rx, g.ellipse_ry, g.ellipse_angle }) b.add_double_value (v);
            b.end_array ();
            b.set_member_name ("curve").add_boolean_value (g.curve_on);
            b.set_member_name ("curve_template").add_string_value (g.curve_template);
            b.set_member_name ("curve_geom").begin_array ();
            foreach (var v in new double[] { g.curve_pos.x, g.curve_pos.y, g.curve_scale, g.curve_angle }) b.add_double_value (v);
            b.end_array ();
            if (g.custom_curve != null) b.set_member_name ("custom_curve").add_string_value (g.custom_curve.to_svg (3));
            b.set_member_name ("perspective").add_int_value (g.perspective);
            b.set_member_name ("vps");
            pts (b, { g.vp1, g.vp2, g.vp3 });
            b.set_member_name ("symmetry").add_string_value (g.symmetry.to_id ());
            b.set_member_name ("symmetry_center");
            pts (b, { g.symmetry_center });
            b.set_member_name ("radial_count").add_int_value (g.radial_count);
            b.end_object ();
            b.set_member_name ("timelapse").begin_array ();
            foreach (var ev in sk.timelapse) {
                b.begin_array ();
                b.add_string_value (ev.layer);
                b.add_int_value (ev.stroke_index);
                b.add_double_value (ev.time);
                b.end_array ();
            }
            b.end_array ();
            b.end_object ();
        }

        private static void write_layer (Json.Builder b, SketchLayer l) {
            b.begin_object ();
            b.set_member_name ("id").add_string_value (l.id);
            b.set_member_name ("name").add_string_value (l.name);
            b.set_member_name ("kind").add_string_value (l.kind == LayerKind.IMAGE ? "image" : (l.kind == LayerKind.GROUP ? "group" : (l.kind == LayerKind.UNDERLAY ? "underlay" : "strokes")));
            b.set_member_name ("visible").add_boolean_value (l.visible);
            b.set_member_name ("locked").add_boolean_value (l.locked);
            b.set_member_name ("opacity").add_double_value (l.opacity);
            b.set_member_name ("blend").add_string_value (l.blend);
            if (l.kind == LayerKind.IMAGE) {
                var m = l.image_matrix;
                b.set_member_name ("matrix").begin_array ();
                foreach (var v in new double[] { m.xx, m.yx, m.xy, m.yy, m.x0, m.y0 }) b.add_double_value (v);
                b.end_array ();
                b.set_member_name ("image_name").add_string_value (l.image_name);
            }
            if (l.kind == LayerKind.UNDERLAY) {
                b.set_member_name ("underlay").add_string_value (l.underlay);
                b.set_member_name ("params").begin_object ();
                foreach (var ek in sorted (l.underlay_params.keys)) b.set_member_name (ek).add_double_value (l.underlay_params[ek]);
                b.end_object ();
            }
            b.set_member_name ("strokes").begin_array ();
            foreach (var st in l.strokes) {
                b.begin_object ();
                b.set_member_name ("brush").add_string_value (st.brush_id);
                b.set_member_name ("kind").add_string_value (st.kind.to_id ());
                b.set_member_name ("color").add_string_value (st.color.to_hex (true));
                b.set_member_name ("size").add_double_value (st.size);
                b.set_member_name ("min_size").add_double_value (st.min_size);
                b.set_member_name ("opacity").add_double_value (st.opacity);
                b.set_member_name ("hardness").add_double_value (st.hardness);
                b.set_member_name ("texture").add_double_value (st.texture);
                b.set_member_name ("curve").add_string_value (st.pressure_curve.to_string ());
                b.set_member_name ("pressure_size").add_boolean_value (st.pressure_size);
                b.set_member_name ("pressure_opacity").add_boolean_value (st.pressure_opacity);
                b.set_member_name ("tilt_size").add_double_value (st.tilt_size);
                b.set_member_name ("velocity_thin").add_double_value (st.velocity_thin);
                b.set_member_name ("smooth").add_boolean_value (st.smooth_curve);
                b.set_member_name ("samples").begin_array ();
                foreach (var sm in st.samples) {
                    b.add_double_value (round (sm.x));
                    b.add_double_value (round (sm.y));
                    b.add_double_value (round (sm.pressure));
                    b.add_double_value (round (sm.tilt_x));
                    b.add_double_value (round (sm.tilt_y));
                    b.add_double_value (round (sm.time));
                }
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("fills").begin_array ();
            foreach (var f in l.fills) {
                b.begin_object ();
                b.set_member_name ("path").add_string_value (f.path.to_svg (3));
                b.set_member_name ("mode").add_string_value (f.mode);
                b.set_member_name ("color").add_string_value (f.color.to_hex (true));
                b.set_member_name ("color2").add_string_value (f.color2.to_hex (true));
                b.set_member_name ("geom").begin_array ();
                foreach (var v in new double[] { f.x1, f.y1, f.x2, f.y2, f.opacity }) b.add_double_value (v);
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("children").begin_array ();
            foreach (var c in l.children) write_layer (b, c);
            b.end_array ();
            b.end_object ();
        }

        private static Sketch read_sketch (Json.Object o) {
            var sk = new Sketch ();
            sk.layers.clear ();
            sk.paper = Rgba.parse (s (o, "paper", "#ffffff"));
            sk.record_timelapse = bo (o, "record_timelapse", true);
            var la = arr (o, "layers");
            if (la != null) foreach (var e in la.get_elements ()) sk.layers.add (read_layer (e.get_object ()));
            if (sk.layers.size == 0) sk.layers.add (new SketchLayer (sk.new_id (), _("Layer 1")));
            var ba = arr (o, "brushes");
            if (ba != null) {
                sk.brushes.clear ();
                foreach (var e in ba.get_elements ()) {
                    var bo2 = e.get_object ();
                    var br = new Brush (s (bo2, "id"), s (bo2, "name"), BrushKind.from_id (s (bo2, "kind")));
                    br.size = n (bo2, "size", 2);
                    br.min_size = n (bo2, "min_size", 0.2);
                    br.opacity = n (bo2, "opacity", 1);
                    br.hardness = n (bo2, "hardness", 0.9);
                    br.pressure_curve = ResponseCurve.parse (s (bo2, "pressure_curve"));
                    br.pressure_size = bo (bo2, "pressure_size", true);
                    br.pressure_opacity = bo (bo2, "pressure_opacity");
                    br.tilt_size = n (bo2, "tilt_size");
                    br.velocity_thin = n (bo2, "velocity_thin");
                    br.texture = n (bo2, "texture");
                    sk.brushes.add (br);
                }
            }
            var go = obj (o, "guides");
            if (go != null) {
                var g = sk.guides;
                g.ruler_on = bo (go, "ruler");
                var rp = read_pts (arr (go, "ruler_pts"));
                if (rp.length == 2) {
                    g.ruler_a = rp[0];
                    g.ruler_b = rp[1];
                }
                g.ellipse_on = bo (go, "ellipse");
                var eg = arr (go, "ellipse_geom");
                if (eg != null && eg.get_length () == 5) {
                    g.ellipse_center = Point (eg.get_double_element (0), eg.get_double_element (1));
                    g.ellipse_rx = eg.get_double_element (2);
                    g.ellipse_ry = eg.get_double_element (3);
                    g.ellipse_angle = eg.get_double_element (4);
                }
                g.curve_on = bo (go, "curve");
                g.curve_template = s (go, "curve_template", "french-1");
                var cg = arr (go, "curve_geom");
                if (cg != null && cg.get_length () == 4) {
                    g.curve_pos = Point (cg.get_double_element (0), cg.get_double_element (1));
                    g.curve_scale = cg.get_double_element (2);
                    g.curve_angle = cg.get_double_element (3);
                }
                if (go.has_member ("custom_curve")) g.custom_curve = PathData.parse_svg (s (go, "custom_curve"));
                g.perspective = (int) n (go, "perspective");
                var vp = read_pts (arr (go, "vps"));
                if (vp.length == 3) {
                    g.vp1 = vp[0];
                    g.vp2 = vp[1];
                    g.vp3 = vp[2];
                }
                g.symmetry = SymmetryMode.from_id (s (go, "symmetry"));
                var sc = read_pts (arr (go, "symmetry_center"));
                if (sc.length == 1) g.symmetry_center = sc[0];
                g.radial_count = (int) n (go, "radial_count", 6);
            }
            var tl = arr (o, "timelapse");
            if (tl != null) {
                foreach (var e in tl.get_elements ()) {
                    var a = e.get_array ();
                    if (a.get_length () == 3) sk.timelapse.add (new TimelapseEvent (a.get_string_element (0), (int) a.get_int_element (1), a.get_double_element (2)));
                }
            }
            return sk;
        }

        private static SketchLayer read_layer (Json.Object o) {
            string kind = s (o, "kind", "strokes");
            var l = new SketchLayer (s (o, "id"), s (o, "name"), kind == "image" ? LayerKind.IMAGE : (kind == "group" ? LayerKind.GROUP : (kind == "underlay" ? LayerKind.UNDERLAY : LayerKind.STROKES)));
            l.visible = bo (o, "visible", true);
            l.locked = bo (o, "locked");
            l.opacity = n (o, "opacity", 1);
            l.blend = s (o, "blend", "normal");
            var m = arr (o, "matrix");
            if (m != null && m.get_length () == 6) l.image_matrix = Cairo.Matrix (m.get_double_element (0), m.get_double_element (1), m.get_double_element (2), m.get_double_element (3), m.get_double_element (4), m.get_double_element (5));
            l.image_name = s (o, "image_name");
            l.underlay = s (o, "underlay");
            var prm = obj (o, "params");
            if (prm != null) foreach (var k in prm.get_members ()) l.underlay_params[k] = prm.get_double_member (k);
            var sa = arr (o, "strokes");
            if (sa != null) {
                foreach (var e in sa.get_elements ()) {
                    var so = e.get_object ();
                    var st = new Stroke ();
                    st.brush_id = s (so, "brush", "pencil");
                    st.kind = BrushKind.from_id (s (so, "kind"));
                    st.color = Rgba.parse (s (so, "color"));
                    st.size = n (so, "size", 2);
                    st.min_size = n (so, "min_size", 0.2);
                    st.opacity = n (so, "opacity", 1);
                    st.hardness = n (so, "hardness", 0.9);
                    st.texture = n (so, "texture");
                    st.pressure_curve = ResponseCurve.parse (s (so, "curve"));
                    st.pressure_size = bo (so, "pressure_size", true);
                    st.pressure_opacity = bo (so, "pressure_opacity");
                    st.tilt_size = n (so, "tilt_size");
                    st.velocity_thin = n (so, "velocity_thin");
                    st.smooth_curve = bo (so, "smooth", true);
                    var smp = arr (so, "samples");
                    if (smp != null) {
                        for (uint i = 0; i + 5 < smp.get_length (); i += 6) {
                            st.samples.add (StrokeSample (smp.get_double_element (i), smp.get_double_element (i + 1), smp.get_double_element (i + 2),
                                smp.get_double_element (i + 3), smp.get_double_element (i + 4), smp.get_double_element (i + 5)));
                        }
                    }
                    l.strokes.add (st);
                }
            }
            var fa = arr (o, "fills");
            if (fa != null) {
                foreach (var e in fa.get_elements ()) {
                    var fo = e.get_object ();
                    var f = new FillRegion ();
                    f.path = PathData.parse_svg (s (fo, "path"));
                    f.mode = s (fo, "mode", "solid");
                    f.color = Rgba.parse (s (fo, "color"));
                    f.color2 = Rgba.parse (s (fo, "color2"));
                    var g = arr (fo, "geom");
                    if (g != null && g.get_length () == 5) {
                        f.x1 = g.get_double_element (0);
                        f.y1 = g.get_double_element (1);
                        f.x2 = g.get_double_element (2);
                        f.y2 = g.get_double_element (3);
                        f.opacity = g.get_double_element (4);
                    }
                    l.fills.add (f);
                }
            }
            var ch = arr (o, "children");
            if (ch != null) foreach (var e in ch.get_elements ()) l.children.add (read_layer (e.get_object ()));
            return l;
        }

        public static void write_table (Json.Builder b, MeasurementTable t) {
            b.begin_object ();
            b.set_member_name ("kind").add_string_value (t.kind == TableKind.INDIVIDUAL ? "individual" : "multisize");
            b.set_member_name ("name").add_string_value (t.name);
            b.set_member_name ("unit").add_string_value (t.unit);
            b.set_member_name ("base_size").add_string_value (t.base_size);
            b.set_member_name ("customer").add_string_value (t.customer);
            b.set_member_name ("gender").add_string_value (t.gender);
            b.set_member_name ("sizes").begin_array ();
            foreach (var sz in t.sizes) b.add_string_value (sz);
            b.end_array ();
            b.set_member_name ("items").begin_array ();
            foreach (var m in t.items) {
                b.begin_object ();
                b.set_member_name ("name").add_string_value (m.name);
                b.set_member_name ("full_name").add_string_value (m.full_name);
                b.set_member_name ("description").add_string_value (m.description);
                b.set_member_name ("formula").add_string_value (m.formula);
                b.set_member_name ("base").add_double_value (m.base_value);
                b.set_member_name ("step").add_double_value (m.size_step);
                b.set_member_name ("height_step").add_double_value (m.height_step);
                b.set_member_name ("sizes").begin_object ();
                foreach (var ek in sorted (m.per_size.keys)) b.set_member_name (ek).add_double_value (m.per_size[ek]);
                b.end_object ();
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
        }

        public static MeasurementTable read_table (Json.Object o) {
            var t = new MeasurementTable ();
            t.kind = s (o, "kind") == "individual" ? TableKind.INDIVIDUAL : TableKind.MULTISIZE;
            t.name = s (o, "name");
            t.unit = s (o, "unit", "cm");
            t.base_size = s (o, "base_size");
            t.customer = s (o, "customer");
            t.gender = s (o, "gender");
            var sz = arr (o, "sizes");
            if (sz != null) foreach (var e in sz.get_elements ()) t.sizes.add (e.get_string ());
            var it = arr (o, "items");
            if (it != null) {
                foreach (var e in it.get_elements ()) {
                    var mo = e.get_object ();
                    var m = new Measurement (s (mo, "name"), n (mo, "base"));
                    m.full_name = s (mo, "full_name");
                    m.description = s (mo, "description");
                    m.formula = s (mo, "formula");
                    m.size_step = n (mo, "step");
                    m.height_step = n (mo, "height_step");
                    var ps = obj (mo, "sizes");
                    if (ps != null) foreach (var k in ps.get_members ()) m.per_size[k] = ps.get_double_member (k);
                    t.items.add (m);
                }
            }
            return t;
        }

        private static void write_pattern (Json.Builder b, Pattern p) {
            b.begin_object ();
            b.set_member_name ("unit").add_string_value (p.unit);
            b.set_member_name ("grading").add_string_value (p.grading);
            b.set_member_name ("active_size").add_string_value (p.active_size);
            b.set_member_name ("table");
            write_table (b, p.table);
            b.set_member_name ("increments").begin_array ();
            foreach (var inc in p.increments) {
                b.begin_object ();
                b.set_member_name ("name").add_string_value (inc.name);
                b.set_member_name ("formula").add_string_value (inc.formula);
                b.set_member_name ("description").add_string_value (inc.description);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("points").begin_array ();
            foreach (var pt in p.points) {
                b.begin_object ();
                b.set_member_name ("id").add_string_value (pt.id);
                b.set_member_name ("name").add_string_value (pt.name);
                b.set_member_name ("kind").add_string_value (pt.kind.to_id ());
                string[] keys = { "a", "b", "c", "d", "x", "y", "length", "angle" };
                string[] vals = { pt.a, pt.b, pt.c, pt.d, pt.fx, pt.fy, pt.flength, pt.fangle };
                for (int i = 0; i < keys.length; i++) if (vals[i] != "" && vals[i] != "0") b.set_member_name (keys[i]).add_string_value (vals[i]);
                if (pt.rule != 0) b.set_member_name ("rule").add_int_value (pt.rule);
                if (pt.hidden) b.set_member_name ("hidden").add_boolean_value (true);
                b.set_member_name ("label").begin_array ();
                b.add_double_value (pt.label_dx);
                b.add_double_value (pt.label_dy);
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("curves").begin_array ();
            foreach (var c in p.curves) {
                b.begin_object ();
                b.set_member_name ("id").add_string_value (c.id);
                b.set_member_name ("name").add_string_value (c.name);
                b.set_member_name ("kind").add_string_value (c.kind == CurveKind.LINE ? "line" : (c.kind == CurveKind.AUTO ? "auto" : (c.kind == CurveKind.SEGMENT ? "segment" : "path")));
                if (c.parent != "") b.set_member_name ("parent").add_string_value (c.parent);
                if (c.target_length != "") b.set_member_name ("target_length").add_string_value (c.target_length);
                b.set_member_name ("tension").add_string_value (c.tension);
                b.set_member_name ("knots").begin_array ();
                foreach (var k in c.knots) {
                    b.begin_object ();
                    b.set_member_name ("point").add_string_value (k.point);
                    if (k.angle_in != "") b.set_member_name ("angle_in").add_string_value (k.angle_in);
                    if (k.len_in != "") b.set_member_name ("len_in").add_string_value (k.len_in);
                    if (k.angle_out != "") b.set_member_name ("angle_out").add_string_value (k.angle_out);
                    if (k.len_out != "") b.set_member_name ("len_out").add_string_value (k.len_out);
                    b.end_object ();
                }
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("pieces").begin_array ();
            foreach (var pc in p.pieces) write_piece (b, pc);
            b.end_array ();
            b.set_member_name ("rules").begin_array ();
            foreach (var r in p.rules.rules) {
                b.begin_object ();
                b.set_member_name ("number").add_int_value (r.number);
                b.set_member_name ("name").add_string_value (r.name);
                b.set_member_name ("steps").begin_object ();
                foreach (var ek in sorted (r.steps.keys)) {
                    b.set_member_name (ek);
                    pts (b, { r.steps[ek] });
                }
                b.end_object ();
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
        }

        private static void write_fixed (Json.Builder b, FixedGeometry g) {
            b.begin_object ();
            b.set_member_name ("seam");
            pts (b, g.seam);
            b.set_member_name ("cut");
            pts (b, g.cut);
            b.set_member_name ("notches").begin_array ();
            foreach (var nn in g.notches) {
                b.begin_array ();
                b.add_double_value (round (nn.at.x));
                b.add_double_value (round (nn.at.y));
                b.add_double_value (round (nn.angle));
                b.add_string_value (nn.type);
                b.add_double_value (nn.length);
                b.end_array ();
            }
            b.end_array ();
            b.set_member_name ("drills");
            Point[] dr = {};
            foreach (var d in g.drills) dr += d;
            pts (b, dr);
            b.set_member_name ("internals").begin_array ();
            foreach (var il in g.internals) pts (b, il.pts);
            b.end_array ();
            if (g.has_grain) {
                b.set_member_name ("grain");
                pts (b, { g.grain_a, g.grain_b });
            }
            b.end_object ();
        }

        private static FixedGeometry read_fixed (Json.Object o) {
            var g = new FixedGeometry ();
            g.seam = read_pts (arr (o, "seam"));
            g.cut = read_pts (arr (o, "cut"));
            var na = arr (o, "notches");
            if (na != null) {
                foreach (var e in na.get_elements ()) {
                    var a = e.get_array ();
                    g.notches.add (new FixedNotch (Point (a.get_double_element (0), a.get_double_element (1)), a.get_double_element (2), a.get_string_element (3), a.get_double_element (4)));
                }
            }
            foreach (var d in read_pts (arr (o, "drills"))) g.drills.add (d);
            var ia = arr (o, "internals");
            if (ia != null) foreach (var e in ia.get_elements ()) g.internals.add (new PointList (read_pts (e.get_array ())));
            var gr = read_pts (arr (o, "grain"));
            if (gr.length == 2) {
                g.grain_a = gr[0];
                g.grain_b = gr[1];
                g.has_grain = true;
            }
            return g;
        }

        private static void write_piece (Json.Builder b, Piece pc) {
            b.begin_object ();
            b.set_member_name ("id").add_string_value (pc.id);
            b.set_member_name ("name").add_string_value (pc.name);
            b.set_member_name ("code").add_string_value (pc.code);
            b.set_member_name ("material").add_string_value (pc.material);
            b.set_member_name ("quantity").add_int_value (pc.quantity);
            b.set_member_name ("pair").add_boolean_value (pc.pair);
            b.set_member_name ("on_fold").add_boolean_value (pc.on_fold);
            b.set_member_name ("fold_edge").add_int_value (pc.fold_edge);
            b.set_member_name ("seam_allowance").add_string_value (pc.seam_allowance);
            b.set_member_name ("built_in").add_boolean_value (pc.built_in);
            b.set_member_name ("grain").begin_array ();
            b.add_string_value (pc.grain_a);
            b.add_string_value (pc.grain_b);
            b.add_double_value (pc.grain_angle);
            b.add_int_value (pc.grain_arrows);
            b.end_array ();
            b.set_member_name ("label").add_string_value (pc.label);
            b.set_member_name ("place").begin_array ();
            b.add_double_value (pc.place_x);
            b.add_double_value (pc.place_y);
            b.add_double_value (pc.rotation);
            b.add_boolean_value (pc.flipped);
            b.end_array ();
            b.set_member_name ("placement").add_string_value (pc.placement);
            b.set_member_name ("leather_turn").add_string_value (pc.leather_turn);
            b.set_member_name ("leather_skive").add_string_value (pc.leather_skive);
            b.set_member_name ("thickness").add_double_value (pc.thickness);
            b.set_member_name ("nodes").begin_array ();
            foreach (var nd in pc.nodes) {
                b.begin_object ();
                b.set_member_name ("ref").add_string_value (nd.ref_id);
                if (nd.is_curve) b.set_member_name ("curve").add_boolean_value (true);
                if (nd.reverse) b.set_member_name ("reverse").add_boolean_value (true);
                if (nd.sa_after != "") b.set_member_name ("sa").add_string_value (nd.sa_after);
                if (nd.corner != CornerStyle.INTERSECT) b.set_member_name ("corner").add_string_value (nd.corner.to_id ());
                if (nd.notch) b.set_member_name ("notch").add_string_value (nd.notch_type);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("extra_notches").begin_array ();
            foreach (var xn in pc.extra_notches) {
                b.begin_array ();
                b.add_int_value (xn.edge);
                b.add_double_value (xn.distance);
                b.add_string_value (xn.type);
                b.end_array ();
            }
            b.end_array ();
            b.set_member_name ("drills").begin_array ();
            foreach (var d in pc.drills) {
                b.begin_array ();
                b.add_string_value (d.point);
                b.add_double_value (d.dx);
                b.add_double_value (d.dy);
                b.add_double_value (d.diameter);
                b.end_array ();
            }
            b.end_array ();
            b.set_member_name ("internals").begin_array ();
            foreach (var il in pc.internals) {
                b.begin_object ();
                b.set_member_name ("kind").add_string_value (il.kind);
                b.set_member_name ("refs").begin_array ();
                foreach (var r in il.refs) b.add_string_value (r);
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            if (pc.fixed != null) {
                b.set_member_name ("fixed");
                write_fixed (b, pc.fixed);
                b.set_member_name ("fixed_sizes").begin_object ();
                foreach (var ek in sorted (pc.fixed_sizes.keys)) {
                    b.set_member_name (ek);
                    write_fixed (b, pc.fixed_sizes[ek]);
                }
                b.end_object ();
            }
            b.end_object ();
        }

        private static Pattern read_pattern (Json.Object o) {
            var p = new Pattern ();
            p.unit = s (o, "unit", "cm");
            p.grading = s (o, "grading", "measurements");
            var to = obj (o, "table");
            if (to != null) p.table = read_table (to);
            p.active_size = s (o, "active_size", p.table.base_size);
            var inc = arr (o, "increments");
            if (inc != null) {
                foreach (var e in inc.get_elements ()) {
                    var io = e.get_object ();
                    var i = new Increment (s (io, "name"), s (io, "formula"));
                    i.description = s (io, "description");
                    p.increments.add (i);
                }
            }
            var pa = arr (o, "points");
            if (pa != null) {
                foreach (var e in pa.get_elements ()) {
                    var po = e.get_object ();
                    var pt = new PatternPoint (s (po, "id"), s (po, "name"));
                    pt.kind = PointKind.from_id (s (po, "kind"));
                    pt.a = s (po, "a");
                    pt.b = s (po, "b");
                    pt.c = s (po, "c");
                    pt.d = s (po, "d");
                    pt.fx = s (po, "x", "0");
                    pt.fy = s (po, "y", "0");
                    pt.flength = s (po, "length", "0");
                    pt.fangle = s (po, "angle", "0");
                    pt.rule = (int) n (po, "rule");
                    pt.hidden = bo (po, "hidden");
                    var lb = arr (po, "label");
                    if (lb != null && lb.get_length () == 2) {
                        pt.label_dx = lb.get_double_element (0);
                        pt.label_dy = lb.get_double_element (1);
                    }
                    p.points.add (pt);
                    p.bump_ids (pt.id);
                }
            }
            var ca = arr (o, "curves");
            if (ca != null) {
                foreach (var e in ca.get_elements ()) {
                    var co = e.get_object ();
                    var c = new PatternCurve (s (co, "id"), s (co, "name"));
                    string k = s (co, "kind", "path");
                    c.kind = k == "line" ? CurveKind.LINE : (k == "auto" ? CurveKind.AUTO : (k == "segment" ? CurveKind.SEGMENT : CurveKind.PATH));
                    c.parent = s (co, "parent");
                    c.target_length = s (co, "target_length");
                    c.tension = s (co, "tension", "1");
                    var ka = arr (co, "knots");
                    if (ka != null) {
                        foreach (var ke in ka.get_elements ()) {
                            var ko = ke.get_object ();
                            var kn = new CurveKnot (s (ko, "point"));
                            kn.angle_in = s (ko, "angle_in");
                            kn.len_in = s (ko, "len_in");
                            kn.angle_out = s (ko, "angle_out");
                            kn.len_out = s (ko, "len_out");
                            c.knots.add (kn);
                        }
                    }
                    p.curves.add (c);
                    p.bump_ids (c.id);
                }
            }
            var pcs = arr (o, "pieces");
            if (pcs != null) foreach (var e in pcs.get_elements ()) {
                var pc = read_piece (e.get_object ());
                p.pieces.add (pc);
                p.bump_ids (pc.id);
            }
            var ra = arr (o, "rules");
            if (ra != null) {
                foreach (var e in ra.get_elements ()) {
                    var ro = e.get_object ();
                    var r = new GradeRule ((int) n (ro, "number"));
                    r.name = s (ro, "name");
                    var st = obj (ro, "steps");
                    if (st != null) {
                        foreach (var k in st.get_members ()) {
                            var q = read_pts (st.get_array_member (k));
                            if (q.length == 1) r.steps[k] = q[0];
                        }
                    }
                    p.rules.rules.add (r);
                }
            }
            return p;
        }

        private static Piece read_piece (Json.Object o) {
            var pc = new Piece (s (o, "id"), s (o, "name"));
            pc.code = s (o, "code");
            pc.material = s (o, "material", "fabric");
            pc.quantity = (int) n (o, "quantity", 1);
            pc.pair = bo (o, "pair");
            pc.on_fold = bo (o, "on_fold");
            pc.fold_edge = (int) n (o, "fold_edge", -1);
            pc.seam_allowance = s (o, "seam_allowance", "1");
            pc.built_in = bo (o, "built_in");
            var g = arr (o, "grain");
            if (g != null && g.get_length () == 4) {
                pc.grain_a = g.get_string_element (0);
                pc.grain_b = g.get_string_element (1);
                pc.grain_angle = g.get_double_element (2);
                pc.grain_arrows = (int) g.get_int_element (3);
            }
            pc.label = s (o, "label", pc.label);
            var pl = arr (o, "place");
            if (pl != null && pl.get_length () == 4) {
                pc.place_x = pl.get_double_element (0);
                pc.place_y = pl.get_double_element (1);
                pc.rotation = pl.get_double_element (2);
                pc.flipped = pl.get_boolean_element (3);
            }
            pc.placement = s (o, "placement", "front");
            pc.leather_turn = s (o, "leather_turn");
            pc.leather_skive = s (o, "leather_skive");
            pc.thickness = n (o, "thickness");
            var na = arr (o, "nodes");
            if (na != null) {
                foreach (var e in na.get_elements ()) {
                    var no = e.get_object ();
                    var nd = new PieceNode (s (no, "ref"), bo (no, "curve"));
                    nd.reverse = bo (no, "reverse");
                    nd.sa_after = s (no, "sa");
                    nd.corner = CornerStyle.from_id (s (no, "corner"));
                    if (no.has_member ("notch")) {
                        nd.notch = true;
                        nd.notch_type = s (no, "notch", "slit");
                    }
                    pc.nodes.add (nd);
                }
            }
            var xa = arr (o, "extra_notches");
            if (xa != null) {
                foreach (var e in xa.get_elements ()) {
                    var a = e.get_array ();
                    var xn = new ExtraNotch ((int) a.get_int_element (0), a.get_double_element (1));
                    xn.type = a.get_string_element (2);
                    pc.extra_notches.add (xn);
                }
            }
            var da = arr (o, "drills");
            if (da != null) {
                foreach (var e in da.get_elements ()) {
                    var a = e.get_array ();
                    var d = new DrillHole ();
                    d.point = a.get_string_element (0);
                    d.dx = a.get_double_element (1);
                    d.dy = a.get_double_element (2);
                    d.diameter = a.get_double_element (3);
                    pc.drills.add (d);
                }
            }
            var ia = arr (o, "internals");
            if (ia != null) {
                foreach (var e in ia.get_elements ()) {
                    var io = e.get_object ();
                    var il = new InternalLine ();
                    il.kind = s (io, "kind", "line");
                    var r = arr (io, "refs");
                    if (r != null) foreach (var re in r.get_elements ()) il.refs.add (re.get_string ());
                    pc.internals.add (il);
                }
            }
            var fo = obj (o, "fixed");
            if (fo != null) {
                pc.fixed = read_fixed (fo);
                var fs = obj (o, "fixed_sizes");
                if (fs != null) foreach (var k in fs.get_members ()) pc.fixed_sizes[k] = read_fixed (fs.get_object_member (k));
            }
            return pc;
        }

        private static void write_sheet (Json.Builder b, FlatSheet sh) {
            b.begin_object ();
            b.set_member_name ("id").add_string_value (sh.id);
            b.set_member_name ("name").add_string_value (sh.name);
            b.set_member_name ("axis").add_double_value (sh.axis_x);
            b.set_member_name ("scale_mm").add_double_value (sh.scale_mm);
            b.set_member_name ("items").begin_array ();
            foreach (var it in sh.items) {
                b.begin_object ();
                b.set_member_name ("id").add_string_value (it.id);
                string kind = "shape";
                switch (it.kind) {
                    case FlatItemKind.TRIM: kind = "trim"; break;
                    case FlatItemKind.DIMENSION: kind = "dimension"; break;
                    case FlatItemKind.CALLOUT: kind = "callout"; break;
                    case FlatItemKind.TEXT: kind = "text"; break;
                    default: break;
                }
                b.set_member_name ("kind").add_string_value (kind);
                b.set_member_name ("name").add_string_value (it.name);
                if (!it.path.is_empty ()) b.set_member_name ("path").add_string_value (it.path.to_svg (3));
                b.set_member_name ("mirror").add_boolean_value (it.mirror);
                b.set_member_name ("fill").add_string_value (it.fill_slot);
                b.set_member_name ("line").add_string_value (it.line_slot);
                b.set_member_name ("line_width").add_double_value (it.line_width);
                b.set_member_name ("dashed").add_boolean_value (it.dashed);
                b.set_member_name ("stitch").begin_array ();
                b.add_string_value (it.stitch.kind.to_id ());
                b.add_double_value (it.stitch.pitch);
                b.add_double_value (it.stitch.gap);
                b.add_double_value (it.stitch.offset);
                b.add_double_value (it.stitch.width);
                b.add_string_value (it.stitch.color_slot);
                b.end_array ();
                b.set_member_name ("trim").add_string_value (it.trim);
                b.set_member_name ("asset").add_string_value (it.asset_id);
                b.set_member_name ("at");
                pts (b, { it.at, it.at2 });
                b.set_member_name ("size").add_double_value (it.size);
                b.set_member_name ("rotation").add_double_value (it.rotation);
                b.set_member_name ("offset").add_double_value (it.offset);
                b.set_member_name ("text").add_string_value (it.text);
                b.set_member_name ("number").add_int_value (it.number);
                b.set_member_name ("link").add_string_value (it.link);
                b.set_member_name ("fabric").add_string_value (it.fabric_id);
                b.set_member_name ("pattern_xf").begin_array ();
                b.add_double_value (it.pattern_scale);
                b.add_double_value (it.pattern_angle);
                b.end_array ();
                b.end_object ();
            }
            b.end_array ();
            b.end_object ();
        }

        private static FlatSheet read_sheet (Json.Object o) {
            var sh = new FlatSheet (s (o, "id"), s (o, "name"));
            sh.axis_x = n (o, "axis", 400);
            sh.scale_mm = n (o, "scale_mm", 1);
            var ia = arr (o, "items");
            if (ia != null) {
                foreach (var e in ia.get_elements ()) {
                    var io = e.get_object ();
                    string kind = s (io, "kind", "shape");
                    FlatItemKind k = FlatItemKind.SHAPE;
                    if (kind == "trim") k = FlatItemKind.TRIM;
                    else if (kind == "dimension") k = FlatItemKind.DIMENSION;
                    else if (kind == "callout") k = FlatItemKind.CALLOUT;
                    else if (kind == "text") k = FlatItemKind.TEXT;
                    var it = new FlatItem (s (io, "id"), k);
                    it.name = s (io, "name");
                    if (io.has_member ("path")) it.path = PathData.parse_svg (s (io, "path"));
                    it.mirror = bo (io, "mirror");
                    it.fill_slot = s (io, "fill");
                    it.line_slot = s (io, "line", "Outline");
                    it.line_width = n (io, "line_width", 0.8);
                    it.dashed = bo (io, "dashed");
                    var st = arr (io, "stitch");
                    if (st != null && st.get_length () == 6) {
                        it.stitch.kind = StitchKind.from_id (st.get_string_element (0));
                        it.stitch.pitch = st.get_double_element (1);
                        it.stitch.gap = st.get_double_element (2);
                        it.stitch.offset = st.get_double_element (3);
                        it.stitch.width = st.get_double_element (4);
                        it.stitch.color_slot = st.get_string_element (5);
                    }
                    it.trim = s (io, "trim", "button");
                    it.asset_id = s (io, "asset");
                    var at = read_pts (arr (io, "at"));
                    if (at.length == 2) {
                        it.at = at[0];
                        it.at2 = at[1];
                    }
                    it.size = n (io, "size", 12);
                    it.rotation = n (io, "rotation");
                    it.offset = n (io, "offset", 12);
                    it.text = s (io, "text");
                    it.number = (int) n (io, "number");
                    it.link = s (io, "link");
                    it.fabric_id = s (io, "fabric");
                    var px = arr (io, "pattern_xf");
                    if (px != null && px.get_length () == 2) {
                        it.pattern_scale = px.get_double_element (0);
                        it.pattern_angle = px.get_double_element (1);
                    }
                    sh.items.add (it);
                }
            }
            return sh;
        }

        private static void write_techpack (Json.Builder b, TechPack t) {
            b.begin_object ();
            string[] keys = { "style_number", "style_name", "season", "brand", "designer", "category", "status", "notes" };
            string[] vals = { t.style_number, t.style_name, t.season, t.brand, t.designer, t.category, t.status, t.notes };
            for (int i = 0; i < keys.length; i++) b.set_member_name (keys[i]).add_string_value (vals[i]);
            b.set_member_name ("poms").begin_array ();
            foreach (var p in t.poms) {
                b.begin_object ();
                b.set_member_name ("code").add_string_value (p.code);
                b.set_member_name ("description").add_string_value (p.description);
                b.set_member_name ("method").add_string_value (p.method);
                b.set_member_name ("tol_plus").add_double_value (p.tol_plus);
                b.set_member_name ("tol_minus").add_double_value (p.tol_minus);
                b.set_member_name ("link").add_string_value (p.link);
                b.set_member_name ("values").begin_object ();
                foreach (var ek in sorted (p.values.keys)) b.set_member_name (ek).add_double_value (p.values[ek]);
                b.end_object ();
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("bom").begin_array ();
            foreach (var it in t.bom) {
                b.begin_object ();
                b.set_member_name ("id").add_string_value (it.id);
                b.set_member_name ("category").add_string_value (it.category);
                b.set_member_name ("name").add_string_value (it.name);
                b.set_member_name ("code").add_string_value (it.code);
                b.set_member_name ("supplier").add_string_value (it.supplier);
                b.set_member_name ("asset").add_string_value (it.asset_id);
                b.set_member_name ("placement").add_string_value (it.placement);
                b.set_member_name ("composition").add_string_value (it.composition);
                b.set_member_name ("quantity").add_double_value (it.quantity);
                b.set_member_name ("unit").add_string_value (it.unit);
                b.set_member_name ("from_marker").add_boolean_value (it.from_marker);
                b.set_member_name ("waste").add_double_value (it.waste);
                b.set_member_name ("unit_cost").add_double_value (it.unit_cost);
                b.set_member_name ("currency").add_string_value (it.currency);
                b.set_member_name ("width_cm").add_double_value (it.width_cm);
                b.set_member_name ("colors").begin_object ();
                foreach (var ek in sorted (it.colors.keys)) b.set_member_name (ek).add_string_value (it.colors[ek]);
                b.end_object ();
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("operations").begin_array ();
            foreach (var op in t.operations) {
                b.begin_object ();
                b.set_member_name ("seq").add_int_value (op.seq);
                b.set_member_name ("description").add_string_value (op.description);
                b.set_member_name ("stitch").add_string_value (op.stitch);
                b.set_member_name ("spi").add_double_value (op.spi);
                b.set_member_name ("machine").add_string_value (op.machine);
                b.set_member_name ("seam").add_string_value (op.seam);
                b.set_member_name ("callout").add_int_value (op.callout);
                b.set_member_name ("minutes").add_double_value (op.minutes);
                b.set_member_name ("notes").add_string_value (op.notes);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("revisions").begin_array ();
            foreach (var r in t.revisions) {
                b.begin_object ();
                b.set_member_name ("number").add_int_value (r.number);
                b.set_member_name ("date").add_string_value (r.date);
                b.set_member_name ("author").add_string_value (r.author);
                b.set_member_name ("note").add_string_value (r.note);
                b.set_member_name ("snapshot").add_string_value (r.snapshot);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("comments").begin_array ();
            foreach (var c in t.comments) write_comment (b, c);
            b.end_array ();
            b.end_object ();
        }

        private static void write_comment (Json.Builder b, Comment c) {
            b.begin_object ();
            b.set_member_name ("id").add_string_value (c.id);
            b.set_member_name ("author").add_string_value (c.author);
            b.set_member_name ("date").add_string_value (c.date);
            b.set_member_name ("text").add_string_value (c.text);
            b.set_member_name ("sheet").add_string_value (c.sheet);
            b.set_member_name ("x").add_double_value (c.x);
            b.set_member_name ("y").add_double_value (c.y);
            b.set_member_name ("resolved").add_boolean_value (c.resolved);
            b.set_member_name ("replies").begin_array ();
            foreach (var r in c.replies) write_comment (b, r);
            b.end_array ();
            b.end_object ();
        }

        private static Comment read_comment (Json.Object o) {
            var c = new Comment (s (o, "id"), s (o, "text"));
            c.author = s (o, "author");
            c.date = s (o, "date", c.date);
            c.sheet = s (o, "sheet");
            c.x = n (o, "x");
            c.y = n (o, "y");
            c.resolved = bo (o, "resolved");
            var r = arr (o, "replies");
            if (r != null) foreach (var e in r.get_elements ()) c.replies.add (read_comment (e.get_object ()));
            return c;
        }

        private static TechPack read_techpack (Json.Object o) {
            var t = new TechPack ();
            t.style_number = s (o, "style_number");
            t.style_name = s (o, "style_name");
            t.season = s (o, "season");
            t.brand = s (o, "brand");
            t.designer = s (o, "designer");
            t.category = s (o, "category");
            t.status = s (o, "status", "Development");
            t.notes = s (o, "notes");
            var pa = arr (o, "poms");
            if (pa != null) {
                foreach (var e in pa.get_elements ()) {
                    var po = e.get_object ();
                    var p = new Pom (s (po, "code"), s (po, "description"));
                    p.method = s (po, "method");
                    p.tol_plus = n (po, "tol_plus", 0.5);
                    p.tol_minus = n (po, "tol_minus", 0.5);
                    p.link = s (po, "link");
                    var v = obj (po, "values");
                    if (v != null) foreach (var k in v.get_members ()) p.values[k] = v.get_double_member (k);
                    t.poms.add (p);
                }
            }
            var ba = arr (o, "bom");
            if (ba != null) {
                foreach (var e in ba.get_elements ()) {
                    var bo2 = e.get_object ();
                    var it = new BomItem (s (bo2, "id"));
                    t.bump (it.id);
                    it.category = s (bo2, "category", "fabric");
                    it.name = s (bo2, "name");
                    it.code = s (bo2, "code");
                    it.supplier = s (bo2, "supplier");
                    it.asset_id = s (bo2, "asset");
                    it.placement = s (bo2, "placement");
                    it.composition = s (bo2, "composition");
                    it.quantity = n (bo2, "quantity", 1);
                    it.unit = s (bo2, "unit", "pcs");
                    it.from_marker = bo (bo2, "from_marker");
                    it.waste = n (bo2, "waste");
                    it.unit_cost = n (bo2, "unit_cost");
                    it.currency = s (bo2, "currency", "EUR");
                    it.width_cm = n (bo2, "width_cm");
                    var c = obj (bo2, "colors");
                    if (c != null) foreach (var k in c.get_members ()) it.colors[k] = c.get_string_member (k);
                    t.bom.add (it);
                }
            }
            var oa = arr (o, "operations");
            if (oa != null) {
                foreach (var e in oa.get_elements ()) {
                    var oo = e.get_object ();
                    var op = new Operation ((int) n (oo, "seq"), s (oo, "description"));
                    op.stitch = s (oo, "stitch");
                    op.spi = n (oo, "spi", 10);
                    op.machine = s (oo, "machine");
                    op.seam = s (oo, "seam");
                    op.callout = (int) n (oo, "callout");
                    op.minutes = n (oo, "minutes");
                    op.notes = s (oo, "notes");
                    t.operations.add (op);
                }
            }
            var ra = arr (o, "revisions");
            if (ra != null) {
                foreach (var e in ra.get_elements ()) {
                    var ro = e.get_object ();
                    var r = new Revision ((int) n (ro, "number"), s (ro, "note"));
                    r.date = s (ro, "date", r.date);
                    r.author = s (ro, "author");
                    r.snapshot = s (ro, "snapshot");
                    t.revisions.add (r);
                }
            }
            var ca = arr (o, "comments");
            if (ca != null) foreach (var e in ca.get_elements ()) {
                var c = read_comment (e.get_object ());
                t.comments.add (c);
                t.bump (c.id);
            }
            return t;
        }

        private static void write_garment (Json.Builder b, GarmentSettings g) {
            b.begin_object ();
            b.set_member_name ("fabric").add_string_value (g.fabric_preset);
            b.set_member_name ("pose").add_string_value (g.pose);
            b.set_member_name ("gender").add_string_value (g.avatar_gender);
            b.set_member_name ("resolution").add_int_value (g.resolution);
            b.set_member_name ("environment").add_string_value (g.environment);
            b.set_member_name ("piece_fabrics").begin_object ();
            foreach (var ek in sorted (g.piece_fabrics.keys)) b.set_member_name (ek).add_string_value (g.piece_fabrics[ek]);
            b.end_object ();
            b.set_member_name ("seams").begin_array ();
            foreach (var sp in g.seams) {
                b.begin_array ();
                b.add_string_value (sp.piece_a);
                b.add_int_value (sp.edge_a);
                b.add_string_value (sp.piece_b);
                b.add_int_value (sp.edge_b);
                b.add_boolean_value (sp.reverse_b);
                b.add_double_value (sp.ease);
                b.end_array ();
            }
            b.end_array ();
            b.end_object ();
        }

        private static GarmentSettings read_garment (Json.Object o) {
            var g = new GarmentSettings ();
            g.fabric_preset = s (o, "fabric", "cotton");
            g.pose = s (o, "pose", "a-pose");
            g.avatar_gender = s (o, "gender", "female");
            g.resolution = (int) n (o, "resolution", 18);
            g.environment = s (o, "environment", "studio");
            var pf = obj (o, "piece_fabrics");
            if (pf != null) foreach (var k in pf.get_members ()) g.piece_fabrics[k] = pf.get_string_member (k);
            var sa = arr (o, "seams");
            if (sa != null) {
                foreach (var e in sa.get_elements ()) {
                    var a = e.get_array ();
                    var sp = new SeamPair (a.get_string_element (0), (int) a.get_int_element (1), a.get_string_element (2), (int) a.get_int_element (3));
                    sp.reverse_b = a.get_boolean_element (4);
                    sp.ease = a.get_double_element (5);
                    g.seams.add (sp);
                }
            }
            return g;
        }

        private static void write_marker (Json.Builder b, MarkerSettings m) {
            b.begin_object ();
            b.set_member_name ("width").add_double_value (m.fabric_width);
            b.set_member_name ("spacing").add_double_value (m.spacing);
            b.set_member_name ("resolution").add_double_value (m.resolution);
            b.set_member_name ("rotations").add_string_value (m.rotations);
            b.set_member_name ("flip").add_boolean_value (m.allow_flip);
            b.set_member_name ("material").add_string_value (m.material);
            b.set_member_name ("ratio").begin_object ();
            foreach (var ek in sorted (m.ratio.keys)) b.set_member_name (ek).add_int_value (m.ratio[ek]);
            b.end_object ();
            b.end_object ();
        }

        private static MarkerSettings read_marker (Json.Object o) {
            var m = new MarkerSettings ();
            m.fabric_width = n (o, "width", 1500);
            m.spacing = n (o, "spacing", 3);
            m.resolution = n (o, "resolution", 5);
            m.rotations = s (o, "rotations", "180");
            m.allow_flip = bo (o, "flip");
            m.material = s (o, "material", "fabric");
            var r = obj (o, "ratio");
            if (r != null) foreach (var k in r.get_members ()) m.ratio[k] = (int) r.get_int_member (k);
            return m;
        }

        private static void add_vec3 (Json.Builder b, Vec3 v) {
            b.add_double_value (v.x);
            b.add_double_value (v.y);
            b.add_double_value (v.z);
        }

        private static void write_product (Json.Builder b, ProductModel pm) {
            b.begin_object ();
            b.set_member_name ("levels").add_int_value (pm.levels);
            b.set_member_name ("material").add_string_value (pm.material);
            b.set_member_name ("vertices").begin_array ();
            foreach (var v in pm.cage.vertices) add_vec3 (b, v);
            b.end_array ();
            b.set_member_name ("faces").begin_array ();
            foreach (var f in pm.faces) {
                b.begin_array ();
                foreach (var i in f) b.add_int_value (i);
                b.end_array ();
            }
            b.end_array ();
            b.set_member_name ("creases").begin_array ();
            foreach (var c in sorted (pm.creases)) b.add_string_value (c);
            b.end_array ();
            b.set_member_name ("sketches").begin_array ();
            foreach (var curve in pm.sketches) write_plane_curve (b, curve);
            b.end_array ();
            b.set_member_name ("surfaces").begin_array ();
            foreach (var mesh in pm.surfaces) write_mesh (b, mesh);
            b.end_array ();
            b.set_member_name ("nurbs").begin_array ();
            foreach (var surface in pm.nurbs) write_nurbs_surface (b, surface);
            b.end_array ();
            b.end_object ();
        }

        private static void write_plane_curve (Json.Builder b, PlaneCurve curve) {
            b.begin_object ();
            b.set_member_name ("plane").add_string_value (curve.plane);
            b.set_member_name ("offset").add_double_value (curve.offset);
            b.set_member_name ("closed").add_boolean_value (curve.closed);
            b.set_member_name ("points").begin_array ();
            foreach (var v in curve.points) b.add_double_value (v);
            b.end_array ();
            if (curve.exact != null) {
                var c = curve.exact;
                b.set_member_name ("exact").begin_object ();
                b.set_member_name ("degree").add_int_value (c.degree);
                b.set_member_name ("ctrl").begin_array ();
                foreach (var p in c.ctrl) add_vec3 (b, p);
                b.end_array ();
                b.set_member_name ("weights").begin_array ();
                foreach (var w in c.weights) b.add_double_value (w);
                b.end_array ();
                b.set_member_name ("knots").begin_array ();
                foreach (var k in c.knots) b.add_double_value (k);
                b.end_array ();
                b.end_object ();
            }
            b.end_object ();
        }

        private static void write_mesh (Json.Builder b, Mesh mesh) {
            b.begin_object ();
            b.set_member_name ("name").add_string_value (mesh.name);
            b.set_member_name ("vertices").begin_array ();
            foreach (var v in mesh.vertices) add_vec3 (b, v);
            b.end_array ();
            b.set_member_name ("triangles").begin_array ();
            foreach (var i in mesh.triangles) b.add_int_value (i);
            b.end_array ();
            b.set_member_name ("normals").begin_array ();
            foreach (var v in mesh.normals) add_vec3 (b, v);
            b.end_array ();
            b.set_member_name ("uvs").begin_array ();
            foreach (var v in mesh.uvs) b.add_double_value (v);
            b.end_array ();
            b.set_member_name ("lines").begin_array ();
            foreach (var i in mesh.lines) b.add_int_value (i);
            b.end_array ();
            b.set_member_name ("scalars").begin_array ();
            foreach (var v in mesh.scalars) b.add_double_value (v);
            b.end_array ();
            b.set_member_name ("color").begin_array ();
            foreach (var v in new double[] { mesh.color.r, mesh.color.g, mesh.color.b, mesh.color.a }) b.add_double_value (v);
            b.end_array ();
            b.set_member_name ("material").add_string_value (mesh.material);
            b.set_member_name ("roughness").add_double_value (mesh.roughness);
            b.set_member_name ("metallic").add_double_value (mesh.metallic);
            b.set_member_name ("visible").add_boolean_value (mesh.visible);
            b.set_member_name ("double_sided").add_boolean_value (mesh.double_sided);
            b.end_object ();
        }

        private static void write_nurbs_surface (Json.Builder b, NurbsSurface surface) {
            b.begin_object ();
            b.set_member_name ("name").add_string_value (surface.name);
            b.set_member_name ("degree_u").add_int_value (surface.degree_u);
            b.set_member_name ("degree_v").add_int_value (surface.degree_v);
            b.set_member_name ("count_u").add_int_value (surface.count_u);
            b.set_member_name ("count_v").add_int_value (surface.count_v);
            b.set_member_name ("ctrl").begin_array ();
            foreach (var p in surface.ctrl) add_vec3 (b, p);
            b.end_array ();
            b.set_member_name ("weights").begin_array ();
            foreach (var w in surface.weights) b.add_double_value (w);
            b.end_array ();
            b.set_member_name ("knots_u").begin_array ();
            foreach (var k in surface.knots_u) b.add_double_value (k);
            b.end_array ();
            b.set_member_name ("knots_v").begin_array ();
            foreach (var k in surface.knots_v) b.add_double_value (k);
            b.end_array ();
            b.end_object ();
        }

        private static FormatError damaged_product () {
            return new FormatError.INVALID (_("The 3D product in this project is damaged"));
        }

        private static double[] read_numbers (Json.Object o, string key) throws FormatError {
            var a = arr (o, key);
            if (a == null) return {};
            var values = new double[a.get_length ()];
            for (uint i = 0; i < a.get_length (); i++) {
                var node = a.get_element (i);
                if (node.get_node_type () != Json.NodeType.VALUE) throw damaged_product ();
                var type = node.get_value_type ();
                if (type == typeof (int64)) values[i] = node.get_int ();
                else if (type == typeof (double)) values[i] = node.get_double ();
                else throw damaged_product ();
                if (!values[i].is_finite ()) throw damaged_product ();
            }
            return values;
        }

        private static Gee.ArrayList<Vec3?> read_vectors (Json.Object o, string key) throws FormatError {
            var values = read_numbers (o, key);
            if (values.length % 3 != 0) throw damaged_product ();
            var list = new Gee.ArrayList<Vec3?> ();
            for (int i = 0; i < values.length; i += 3) list.add (Vec3 (values[i], values[i + 1], values[i + 2]));
            return list;
        }

        private static Gee.ArrayList<int> read_indices (Json.Object o, string key, int group, int limit) throws FormatError {
            var values = read_numbers (o, key);
            if (values.length % group != 0) throw damaged_product ();
            var list = new Gee.ArrayList<int> ();
            foreach (var v in values) {
                if (v != Math.floor (v) || v < 0 || v >= limit) throw damaged_product ();
                list.add ((int) v);
            }
            return list;
        }

        private static double[] read_weights (Json.Object o, int count) throws FormatError {
            var weights = read_numbers (o, "weights");
            if (weights.length != count) throw damaged_product ();
            foreach (var w in weights) if (w <= 0) throw damaged_product ();
            return weights;
        }

        private static double[] read_knots (Json.Object o, string key, int count, int degree) throws FormatError {
            if (arr (o, key) == null) return NurbsSurface.clamped_knots (count, degree);
            var knots = read_numbers (o, key);
            if (knots.length != count + degree + 1) throw damaged_product ();
            for (int i = 1; i < knots.length; i++) if (knots[i] < knots[i - 1]) throw damaged_product ();
            if (knots[degree] >= knots[count]) throw damaged_product ();
            return knots;
        }

        private static ProductModel read_product (Json.Object o) throws FormatError {
            var pm = new ProductModel ();
            pm.levels = ((int) n (o, "levels", 2)).clamp (0, 4);
            pm.material = s (o, "material", "plastic");
            pm.cage.vertices.add_all (read_vectors (o, "vertices"));
            var fa = arr (o, "faces");
            if (fa != null) {
                foreach (var e in fa.get_elements ()) {
                    if (e.get_node_type () != Json.NodeType.ARRAY) throw damaged_product ();
                    var f = new Gee.ArrayList<int> ();
                    foreach (var ie in e.get_array ().get_elements ()) {
                        if (ie.get_value_type () != typeof (int64) || ie.get_int () < 0 || ie.get_int () >= pm.cage.vertices.size) throw damaged_product ();
                        f.add ((int) ie.get_int ());
                    }
                    if (f.size < 3) throw damaged_product ();
                    pm.faces.add (f);
                }
            }
            var ca = arr (o, "creases");
            if (ca != null) foreach (var e in ca.get_elements ()) pm.creases.add (e.get_string () ?? "");
            var sketches = arr (o, "sketches");
            if (sketches != null) foreach (var e in sketches.get_elements ()) pm.sketches.add (read_plane_curve (e));
            var surfaces = arr (o, "surfaces");
            if (surfaces != null) foreach (var e in surfaces.get_elements ()) pm.surfaces.add (read_mesh (e));
            var nurbs = arr (o, "nurbs");
            if (nurbs != null) foreach (var e in nurbs.get_elements ()) pm.nurbs.add (read_nurbs_surface (e));
            return pm;
        }

        private static PlaneCurve read_plane_curve (Json.Node node) throws FormatError {
            if (node.get_node_type () != Json.NodeType.OBJECT) throw damaged_product ();
            var o = node.get_object ();
            var curve = new PlaneCurve (s (o, "plane", "xy"), n (o, "offset"));
            curve.closed = bo (o, "closed");
            var points = read_numbers (o, "points");
            if (points.length % 2 != 0) throw damaged_product ();
            foreach (var v in points) curve.points.add (v);
            var exact = obj (o, "exact");
            if (exact != null) {
                int degree = (int) n (exact, "degree");
                var ctrl = read_vectors (exact, "ctrl");
                if (degree < 1 || ctrl.size <= degree) throw damaged_product ();
                var c = new NurbsCurve (degree);
                c.ctrl.add_all (ctrl);
                foreach (var w in read_weights (exact, ctrl.size)) c.weights.add (w);
                c.knots = read_knots (exact, "knots", ctrl.size, degree);
                curve.exact = c;
            }
            return curve;
        }

        private static Mesh read_mesh (Json.Node node) throws FormatError {
            if (node.get_node_type () != Json.NodeType.OBJECT) throw damaged_product ();
            var o = node.get_object ();
            var mesh = new Mesh ();
            mesh.name = s (o, "name");
            mesh.vertices.add_all (read_vectors (o, "vertices"));
            int count = mesh.vertices.size;
            mesh.triangles.add_all (read_indices (o, "triangles", 3, count));
            mesh.lines.add_all (read_indices (o, "lines", 2, count));
            mesh.normals.add_all (read_vectors (o, "normals"));
            foreach (var v in read_numbers (o, "uvs")) mesh.uvs.add (v);
            foreach (var v in read_numbers (o, "scalars")) mesh.scalars.add (v);
            if (mesh.normals.size != 0 && mesh.normals.size != count) throw damaged_product ();
            if (mesh.uvs.size != 0 && mesh.uvs.size != count * 2) throw damaged_product ();
            if (mesh.scalars.size != 0 && mesh.scalars.size != count) throw damaged_product ();
            var color = read_numbers (o, "color");
            if (color.length == 4) mesh.color = Rgba (color[0], color[1], color[2], color[3]);
            else if (color.length != 0) throw damaged_product ();
            mesh.material = s (o, "material");
            mesh.roughness = n (o, "roughness", 0.7);
            mesh.metallic = n (o, "metallic");
            mesh.visible = bo (o, "visible", true);
            mesh.double_sided = bo (o, "double_sided", true);
            return mesh;
        }

        private static NurbsSurface read_nurbs_surface (Json.Node node) throws FormatError {
            if (node.get_node_type () != Json.NodeType.OBJECT) throw damaged_product ();
            var o = node.get_object ();
            int du = (int) n (o, "degree_u"), dv = (int) n (o, "degree_v");
            int nu = (int) n (o, "count_u"), nv = (int) n (o, "count_v");
            if (du < 1 || dv < 1 || nu <= du || nv <= dv) throw damaged_product ();
            var ctrl = read_vectors (o, "ctrl");
            if (ctrl.size != nu * nv) throw damaged_product ();
            var surface = new NurbsSurface (du, dv, nu, nv);
            surface.name = s (o, "name");
            for (int i = 0; i < ctrl.size; i++) surface.ctrl[i] = ctrl[i];
            surface.weights = read_weights (o, ctrl.size);
            surface.knots_u = read_knots (o, "knots_u", nu, du);
            surface.knots_v = read_knots (o, "knots_v", nv, dv);
            return surface;
        }
    }
}
