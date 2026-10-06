using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public enum DxfFlavor {
        AAMA,
        ASTM
    }

    public class AamaExportOptions {
        public DxfFlavor flavor = DxfFlavor.AAMA;
        public bool all_sizes = true;
        public bool metric = true;
        public string style = "";
        public string author = "Atelier";
    }

    public class Aama {
        private static Point flip (Point p, double k) {
            return Point (p.x / k, -p.y / k);
        }

        private static Point[] flip_all (Point[] pts, double k) {
            Point[] r = new Point[pts.length];
            for (int i = 0; i < pts.length; i++) r[i] = flip (pts[i], k);
            return r;
        }

        private static string notch_layer (string type, DxfFlavor flavor) {
            if (flavor == DxfFlavor.AAMA) return "4";
            switch (type) {
                case "t": return "80";
                case "castle": return "81";
                case "check": return "82";
                case "u": return "83";
                default: return "4";
            }
        }

        private static string notch_type (string layer) {
            switch (layer) {
                case "80": return "t";
                case "81": return "castle";
                case "82": return "check";
                case "83": return "u";
                default: return "slit";
            }
        }

        public static string block_name (PieceGeometry g, string size, bool graded) {
            string base_name = g.piece.name.up ().replace (" ", "_");
            return graded ? "%s-%s".printf (base_name, size) : base_name;
        }

        public static string export (Pattern pattern, AamaExportOptions opts) {
            double k = opts.metric ? 1.0 : 25.4;
            var sizes = new Gee.ArrayList<string> ();
            if (opts.all_sizes) sizes.add_all (pattern.all_sizes ());
            else sizes.add (pattern.active_size != "" ? pattern.active_size : pattern.table.base_size);
            bool graded = sizes.size > 1;
            var results = new Gee.ArrayList<PatternResult> ();
            foreach (var sz in sizes) results.add (pattern.evaluate (sz));
            var w = new DxfWriter ();
            var hdr = new Gee.HashMap<string, string> ();
            hdr["$INSUNITS"] = opts.metric ? "4" : "1";
            hdr["$MEASUREMENT"] = opts.metric ? "1" : "0";
            w.header (hdr);
            w.tables ({ "0", "1", "2", "3", "4", "7", "8", "13", "14", "15", "80", "81", "82", "83" });
            w.begin_section ("BLOCKS");
            var names = new Gee.ArrayList<string> ();
            for (int si = 0; si < sizes.size; si++) {
                var res = results[si];
                foreach (var g in res.pieces) {
                    if (g.cut.length < 3) continue;
                    string name = block_name (g, sizes[si], graded);
                    names.add (name);
                    w.begin_block (name);
                    var cut = flip_all (g.cut, k);
                    w.polyline ("1", cut, true);
                    foreach (var p in cut) w.point ("2", p);
                    if (g.seam.length > 2 && !g.piece.built_in) w.polyline ("14", flip_all (g.seam, k), true);
                    foreach (var n in g.notches) {
                        var at = flip (n.cut_at, k);
                        double ang = -n.angle * 180 / Math.PI;
                        if (opts.flavor == DxfFlavor.AAMA) {
                            double len = n.length / k;
                            var end = Point (at.x + len * Math.cos (-n.angle), at.y + len * Math.sin (-n.angle));
                            w.line ("4", at, end);
                        } else {
                            w.point (notch_layer (n.type, opts.flavor), at, ang);
                        }
                    }
                    if (g.has_grain) w.line ("7", flip (g.grain_a, k), flip (g.grain_b, k));
                    foreach (var d in g.drills) w.point ("13", flip (d, k));
                    foreach (var il in g.internals) w.polyline ("8", flip_all (il.pts, k), false);
                    var c = flip (g.center (), k);
                    w.text ("1", c, "Piece Name: %s".printf (g.piece.name));
                    w.text ("1", Point (c.x, c.y - 5), "Size: %s".printf (sizes[si]));
                    w.text ("1", Point (c.x, c.y - 10), "Quantity: %d".printf (g.piece.quantity));
                    if (g.piece.material != "") w.text ("1", Point (c.x, c.y - 15), "Category: %s".printf (g.piece.material));
                    if (g.piece.code != "") w.text ("1", Point (c.x, c.y - 20), "Annotation: %s".printf (g.piece.code));
                    if (g.piece.pair) w.text ("1", Point (c.x, c.y - 25), "Mirror: Y");
                    if (g.piece.on_fold) w.text ("1", Point (c.x, c.y - 30), "Fold: %d".printf (g.piece.fold_edge));
                    w.end_block ();
                }
            }
            w.end_section ();
            w.begin_section ("ENTITIES");
            w.text ("0", Point (0, 0), "Style Name: %s".printf (opts.style != "" ? opts.style : "Atelier"));
            w.text ("0", Point (0, -5), "Creation Date: %s".printf (new DateTime.now_local ().format ("%Y-%m-%d")));
            w.text ("0", Point (0, -10), "Author: %s".printf (opts.author));
            w.text ("0", Point (0, -15), "Units: %s".printf (opts.metric ? "METRIC" : "ENGLISH"));
            if (opts.flavor == DxfFlavor.ASTM) {
                w.text ("0", Point (0, -20), "Sample Size: %s".printf (pattern.table.base_size));
                w.text ("0", Point (0, -25), "Grade Rule Table: %s".printf (pattern.table.name != "" ? pattern.table.name : "Atelier"));
                w.text ("0", Point (0, -30), "Number of Sizes: %d".printf (sizes.size));
            }
            foreach (var n in names) w.insert (n);
            w.end_section ();
            return w.finish ();
        }

        public static string export_rules (Pattern pattern, bool metric = true) {
            var sb = new StringBuilder ();
            double k = metric ? 1.0 : 25.4;
            sb.append ("ASTM/D6673/RUL\n");
            sb.append ("AUTHOR: Atelier\n");
            sb.append ("PRODUCT: Atelier\n");
            sb.append ("VERSION: 1\n");
            sb.append ("CREATION DATE: %s\n".printf (new DateTime.now_local ().format ("%Y-%m-%d")));
            sb.append ("UNITS: %s\n".printf (metric ? "METRIC" : "ENGLISH"));
            sb.append ("GRADE RULE TABLE: %s\n".printf (pattern.table.name != "" ? pattern.table.name : "Atelier"));
            sb.append ("NUMBER OF SIZES: %d\n".printf (pattern.table.sizes.size));
            sb.append ("SIZE LIST: %s\n".printf (string.joinv (" ", pattern.table.sizes.to_array ())));
            sb.append ("SAMPLE SIZE: %s\n".printf (pattern.table.base_size));
            foreach (var r in pattern.rules.rules) {
                sb.append ("RULE: DELTA %d\n".printf (r.number));
                var parts = new Gee.ArrayList<string> ();
                foreach (var sz in pattern.table.sizes) {
                    var st = r.step (sz);
                    parts.add ("%s,%s".printf (PathData.fmt (st.x / k, 4), PathData.fmt (-st.y / k, 4)));
                }
                sb.append (string.joinv (" ", parts.to_array ()));
                sb.append ("\n");
            }
            sb.append ("END\n");
            return sb.str;
        }

        public static void import_rules (string text, Pattern pattern) {
            bool metric = true;
            GradeRule? current = null;
            var sizes = new Gee.ArrayList<string> ();
            foreach (var raw in text.split ("\n")) {
                string line = raw.strip ();
                if (line.has_prefix ("UNITS:")) metric = line.substring (6).strip ().up () != "ENGLISH";
                else if (line.has_prefix ("SIZE LIST:")) {
                    foreach (var s in Regex.split_simple ("\\s+", line.substring (10).strip ())) if (s != "") sizes.add (s);
                } else if (line.has_prefix ("RULE: DELTA")) {
                    current = pattern.rules.ensure (int.parse (line.substring (11).strip ()));
                } else if (current != null && line != "" && line != "END") {
                    var parts = Regex.split_simple ("\\s+", line);
                    double k = metric ? 1.0 : 25.4;
                    for (int i = 0; i < parts.length && i < sizes.size; i++) {
                        var xy = parts[i].split (",");
                        if (xy.length == 2) current.set_step (sizes[i], double.parse (xy[0]) * k, -double.parse (xy[1]) * k);
                    }
                    current = null;
                }
            }
        }

        public static Gee.List<Piece> import (string text, out string units) throws FormatError {
            var doc = DxfDocument.parse (text);
            units = "METRIC";
            foreach (var e in doc.entities) if (e.type == "TEXT" && e.text.up ().has_prefix ("UNITS:")) units = e.text.substring (6).strip ().up ();
            foreach (var b in doc.blocks) foreach (var e in b.entities) if (e.type == "TEXT" && e.text.up ().has_prefix ("UNITS:")) units = e.text.substring (6).strip ().up ();
            if (doc.header.has_key ("$INSUNITS") && doc.header["$INSUNITS"] == "1" && units == "METRIC") units = "ENGLISH";
            double k = units == "ENGLISH" ? 25.4 : 1.0;
            var by_name = new Gee.HashMap<string, Piece> ();
            var order = new Gee.ArrayList<Piece> ();
            var used_blocks = new Gee.HashSet<string> ();
            foreach (var e in doc.entities) if (e.type == "INSERT") used_blocks.add (e.block);
            int counter = 1;
            foreach (var b in doc.blocks) {
                if (b.name.has_prefix ("*")) continue;
                if (used_blocks.size > 0 && !used_blocks.contains (b.name)) continue;
                string pname = b.name;
                string size = "";
                int qty = 1;
                string material = "";
                string code = "";
                bool mirror = false;
                int fold = -1;
                var fg = new FixedGeometry ();
                Point[]? boundary = null;
                Point[]? sew = null;
                foreach (var e in b.entities) {
                    var pts = new Point[e.points.size];
                    for (int i = 0; i < e.points.size; i++) pts[i] = Point (e.points[i].x * k, -e.points[i].y * k);
                    switch (e.layer) {
                        case "1":
                            if ((e.type == "POLYLINE" || e.type == "LWPOLYLINE") && pts.length > 2) {
                                if (boundary == null || Solid.area_of (pts) > Solid.area_of (boundary)) boundary = strip_closing (pts);
                            } else if (e.type == "TEXT") {
                                string t = e.text;
                                string up = t.up ();
                                if (up.has_prefix ("PIECE NAME:")) pname = t.substring (11).strip ();
                                else if (up.has_prefix ("SIZE:")) size = t.substring (5).strip ();
                                else if (up.has_prefix ("QUANTITY:")) qty = int.parse (t.substring (9).strip ());
                                else if (up.has_prefix ("CATEGORY:")) material = t.substring (9).strip ();
                                else if (up.has_prefix ("ANNOTATION:")) code = t.substring (11).strip ();
                                else if (up.has_prefix ("MIRROR:")) mirror = t.substring (7).strip ().up ().has_prefix ("Y");
                                else if (up.has_prefix ("FOLD:")) fold = int.parse (t.substring (5).strip ());
                            }
                            break;
                        case "14":
                            if (pts.length > 2) sew = strip_closing (pts);
                            break;
                        case "4":
                        case "80":
                        case "81":
                        case "82":
                        case "83":
                            if (e.type == "POINT" && pts.length > 0) {
                                fg.notches.add (new FixedNotch (pts[0], -e.angle * Math.PI / 180, notch_type (e.layer), 6));
                            } else if (e.type == "LINE" && pts.length == 2) {
                                double ang = Math.atan2 (pts[1].y - pts[0].y, pts[1].x - pts[0].x);
                                fg.notches.add (new FixedNotch (pts[0], ang, "slit", pts[0].distance (pts[1])));
                            }
                            break;
                        case "7":
                            if (pts.length >= 2) {
                                fg.grain_a = pts[0];
                                fg.grain_b = pts[pts.length - 1];
                                fg.has_grain = true;
                            }
                            break;
                        case "13":
                            if (pts.length > 0) fg.drills.add (pts[0]);
                            break;
                        case "8":
                        case "86":
                            if (pts.length > 1) fg.internals.add (new PointList (pts));
                            break;
                        default:
                            break;
                    }
                }
                if (boundary == null) continue;
                fg.cut = boundary;
                fg.seam = sew ?? boundary;
                string key = pname;
                if (size != "" && pname.has_suffix ("-" + size) == false && b.name.has_suffix ("-" + size)) key = pname;
                Piece piece;
                if (by_name.has_key (key)) {
                    piece = by_name[key];
                } else {
                    piece = new Piece ("d%d".printf (counter++), pname);
                    piece.quantity = qty;
                    piece.material = material != "" ? material : "fabric";
                    piece.code = code;
                    piece.pair = mirror;
                    piece.on_fold = fold >= 0;
                    piece.fold_edge = fold;
                    piece.built_in = sew == null;
                    piece.fixed = fg;
                    by_name[key] = piece;
                    order.add (piece);
                }
                if (size != "") piece.fixed_sizes[size] = fg;
                else piece.fixed = fg;
            }
            return order;
        }

        private static Point[] strip_closing (Point[] pts) {
            if (pts.length > 1 && pts[0].distance (pts[pts.length - 1]) < 1e-6) return pts[0:pts.length - 1];
            return pts;
        }

        public static void import_into (string text, Project project, bool replace) throws FormatError {
            string units;
            var pieces = import (text, out units);
            if (replace) {
                project.pattern = new Pattern ();
                project.pattern.points.clear ();
            }
            var sizes = new Gee.ArrayList<string> ();
            foreach (var p in pieces) {
                foreach (var s in p.fixed_sizes.keys) if (!sizes.contains (s)) sizes.add (s);
                p.id = project.pattern.new_id ("d");
                project.pattern.pieces.add (p);
            }
            if (sizes.size > 0) {
                sizes.sort ((a, b) => {
                    double x = 0, y = 0;
                    bool ok = double.try_parse (a, out x);
                    ok = double.try_parse (b, out y) && ok;
                    if (ok) return x < y ? -1 : (x > y ? 1 : 0);
                    return strcmp (a, b);
                });
                var t = project.pattern.table;
                foreach (var s in sizes) if (!t.sizes.contains (s)) t.sizes.add (s);
                if (!t.sizes.contains (t.base_size)) t.base_size = sizes[sizes.size / 2];
                project.pattern.active_size = t.base_size;
                foreach (var p in pieces) if (p.fixed_sizes.has_key (t.base_size)) p.fixed = p.fixed_sizes[t.base_size];
            }
        }
    }
}
