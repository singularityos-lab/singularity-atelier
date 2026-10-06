using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class SvgExport {
        private static string f (double v) {
            return PathData.fmt (v, 3);
        }

        private static string pts_d (Point[] pts, bool closed) {
            var sb = new StringBuilder ();
            for (int i = 0; i < pts.length; i++) sb.append ("%s%s %s ".printf (i == 0 ? "M" : "L", f (pts[i].x), f (pts[i].y)));
            if (closed) sb.append ("Z");
            return sb.str.strip ();
        }

        private static string color (Rgba c) {
            return c.to_hex ();
        }

        private static string head (Rect b, string unit) {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%s%s\" height=\"%s%s\" viewBox=\"%s %s %s %s\">\n".printf (
                f (b.w), unit, f (b.h), unit, f (b.x), f (b.y), f (b.w), f (b.h));
        }

        public static string sketch (Sketch sk) {
            var b = sk.bounds ();
            if (b.is_empty ()) b = Rect (0, 0, 800, 600);
            b = b.inflate (10);
            var sb = new StringBuilder (head (b, ""));
            sb.append ("<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\"/>\n".printf (f (b.x), f (b.y), f (b.w), f (b.h), color (sk.paper)));
            foreach (var l in sk.layers) layer (sb, l);
            sb.append ("</svg>\n");
            return sb.str;
        }

        private static void layer (StringBuilder sb, SketchLayer l) {
            sb.append ("<g id=\"%s\" inkscape:label=\"%s\" opacity=\"%s\"%s xmlns:inkscape=\"http://www.inkscape.org/namespaces/inkscape\" inkscape:groupmode=\"layer\">\n".printf (
                Markup.escape_text (l.id), Markup.escape_text (l.name), f (l.opacity), l.visible ? "" : " display=\"none\""));
            if (l.kind == LayerKind.IMAGE && l.image_data != null) {
                var m = l.image_matrix;
                var img = l.image ();
                sb.append ("<image transform=\"matrix(%s %s %s %s %s %s)\" width=\"%d\" height=\"%d\" href=\"data:image/png;base64,%s\"/>\n".printf (
                    f (m.xx), f (m.yx), f (m.xy), f (m.yy), f (m.x0), f (m.y0), img != null ? img.get_width () : 0, img != null ? img.get_height () : 0, Base64.encode (l.image_data.get_data ())));
            }
            foreach (var fl in l.fills) {
                sb.append ("<path d=\"%s\" fill=\"%s\" fill-opacity=\"%s\" fill-rule=\"evenodd\"/>\n".printf (fl.path.to_svg (3), color (fl.color), f (fl.opacity * fl.color.a)));
            }
            foreach (var s in l.strokes) {
                if (s.kind == BrushKind.ERASER) continue;
                Point[] c;
                double[] w;
                double[] a;
                s.outline (out c, out w, out a);
                var o = StrokeOutline.build (c, w, true);
                double al = 0;
                foreach (var v in a) al += v;
                al = a.length > 0 ? al / a.length : 1;
                sb.append ("<path d=\"%s\" fill=\"%s\" fill-opacity=\"%s\" data-brush=\"%s\"/>\n".printf (pts_d (o, true), color (s.color), f (al * s.color.a), s.brush_id));
            }
            foreach (var c in l.children) layer (sb, c);
            sb.append ("</g>\n");
        }

        public static string flat_sheet (FlatSheet sheet, Colorway cw) {
            var b = FlatRenderer.sheet_bounds (sheet);
            var sb = new StringBuilder (head (b, ""));
            foreach (var it in sheet.items) {
                if (it.kind == FlatItemKind.SHAPE) {
                    var full = sheet.full_path (it);
                    bool closed = full.has_closed_subpath ();
                    string fill = closed && it.fill_slot != "" ? color (cw.color (it.fill_slot, Rgba (0.9, 0.9, 0.9))) : "none";
                    string stroke = it.line_width > 0 ? color (cw.color (it.line_slot, Rgba (0.1, 0.1, 0.1))) : "none";
                    sb.append ("<path id=\"%s\" d=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"round\"%s><title>%s</title></path>\n".printf (
                        it.id, full.to_svg (3), fill, stroke, f (it.line_width), it.dashed ? " stroke-dasharray=\"4 2\"" : "", Markup.escape_text (it.name)));
                    if (it.stitch.kind != StitchKind.NONE) {
                        var paths = FlatRenderer.polylines (it.path);
                        if (it.mirror) paths.add_all (FlatRenderer.polylines (it.path.transformed (Cairo.Matrix (-1, 0, 0, 1, 2 * sheet.axis_x, 0))));
                        foreach (var pl in paths) {
                            bool dashed;
                            foreach (var sl in FlatRenderer.stitch_geometry (pl.pts, it.stitch, out dashed)) {
                                sb.append ("<path d=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"0.6\"%s data-stitch=\"%s\"/>\n".printf (
                                    pts_d (sl.pts, false), color (cw.color (it.stitch.color_slot, Rgba (0.4, 0.3, 0.2))),
                                    dashed ? " stroke-dasharray=\"%s %s\"".printf (f (it.stitch.pitch * 0.65), f (it.stitch.pitch * 0.35)) : "", it.stitch.kind.to_id ()));
                            }
                        }
                    }
                } else if (it.kind == FlatItemKind.TRIM) {
                    sb.append ("<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\" stroke=\"#1a1a1a\" stroke-width=\"0.6\" data-trim=\"%s\"/>\n".printf (
                        f (it.at.x), f (it.at.y), f (it.size / 2), color (cw.color (it.fill_slot, Rgba (0.3, 0.3, 0.3))), it.trim));
                } else if (it.kind == FlatItemKind.CALLOUT) {
                    sb.append ("<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"#cc2633\" stroke-width=\"0.8\"/>\n".printf (f (it.at.x), f (it.at.y), f (it.at2.x), f (it.at2.y)));
                    sb.append ("<circle cx=\"%s\" cy=\"%s\" r=\"8\" fill=\"#cc2633\"/>\n<text x=\"%s\" y=\"%s\" font-family=\"sans-serif\" font-size=\"9\" fill=\"#ffffff\" text-anchor=\"middle\">%d</text>\n".printf (
                        f (it.at2.x), f (it.at2.y), f (it.at2.x), f (it.at2.y + 3), it.number));
                } else if (it.kind == FlatItemKind.DIMENSION) {
                    double len = it.path.is_empty () ? it.at.distance (it.at2) : Polyline.length (FlatRenderer.path_points (it.path));
                    if (it.path.is_empty ()) sb.append ("<line x1=\"%s\" y1=\"%s\" x2=\"%s\" y2=\"%s\" stroke=\"#1a66cc\" stroke-width=\"0.7\"/>\n".printf (f (it.at.x), f (it.at.y), f (it.at2.x), f (it.at2.y)));
                    else sb.append ("<path d=\"%s\" fill=\"none\" stroke=\"#1a66cc\" stroke-width=\"0.7\"/>\n".printf (it.path.to_svg (3)));
                    sb.append ("<text x=\"%s\" y=\"%s\" font-family=\"sans-serif\" font-size=\"9\" fill=\"#1a66cc\">%s</text>\n".printf (
                        f ((it.at.x + it.at2.x) / 2), f ((it.at.y + it.at2.y) / 2 - 4), Markup.escape_text (FlatRenderer.format_length (len * sheet.scale_mm))));
                } else if (it.kind == FlatItemKind.TEXT) {
                    sb.append ("<text x=\"%s\" y=\"%s\" font-family=\"sans-serif\" font-size=\"%s\">%s</text>\n".printf (f (it.at.x), f (it.at.y + it.size), f (it.size), Markup.escape_text (it.text)));
                }
            }
            sb.append ("</svg>\n");
            return sb.str;
        }

        public static string pattern (Pattern p, PatternResult r) {
            var b = PatternRenderer.pieces_bounds (r, true);
            if (b.is_empty ()) b = Rect (0, 0, 100, 100);
            b = b.inflate (10);
            var sb = new StringBuilder (head (b, "mm"));
            foreach (var g0 in r.pieces) {
                var g = g0.transformed (g0.placement_matrix ());
                sb.append ("<g id=\"%s\" data-name=\"%s\" data-quantity=\"%d\">\n".printf (g.piece.id, Markup.escape_text (g.piece.name), g.piece.quantity));
                if (g.cut.length > 2) sb.append ("<path class=\"cut\" d=\"%s\" fill=\"none\" stroke=\"#000000\" stroke-width=\"0.5\"/>\n".printf (pts_d (g.cut, true)));
                if (g.seam.length > 2 && !g.piece.built_in) sb.append ("<path class=\"seam\" d=\"%s\" fill=\"none\" stroke=\"#000000\" stroke-width=\"0.3\" stroke-dasharray=\"3 1.5\"/>\n".printf (pts_d (g.seam, true)));
                foreach (var n in g.notches) {
                    var e = Point (n.cut_at.x + Math.cos (n.angle) * n.length, n.cut_at.y + Math.sin (n.angle) * n.length);
                    sb.append ("<path class=\"notch\" d=\"%s\" stroke=\"#000000\" stroke-width=\"0.4\"/>\n".printf (pts_d ({ n.cut_at, e }, false)));
                }
                if (g.has_grain) sb.append ("<path class=\"grain\" d=\"%s\" stroke=\"#000000\" stroke-width=\"0.4\"/>\n".printf (pts_d ({ g.grain_a, g.grain_b }, false)));
                foreach (var d in g.drills) sb.append ("<circle class=\"drill\" cx=\"%s\" cy=\"%s\" r=\"1.5\" fill=\"none\" stroke=\"#000000\" stroke-width=\"0.3\"/>\n".printf (f (d.x), f (d.y)));
                foreach (var il in g.internals) sb.append ("<path class=\"internal\" d=\"%s\" fill=\"none\" stroke=\"#000000\" stroke-width=\"0.3\" stroke-dasharray=\"6 2 1 2\"/>\n".printf (pts_d (il.pts, false)));
                var c = g.center ();
                int line = 0;
                foreach (var t in PatternRenderer.label_text (g.piece, r.size).split ("\n")) {
                    sb.append ("<text x=\"%s\" y=\"%s\" font-family=\"sans-serif\" font-size=\"6\" text-anchor=\"middle\">%s</text>\n".printf (f (c.x), f (c.y + line * 8), Markup.escape_text (t)));
                    line++;
                }
                sb.append ("</g>\n");
            }
            sb.append ("</svg>\n");
            return sb.str;
        }
    }

    public class SvgImport {
        public static Gee.ArrayList<PathData> paths (string text, out Rect bounds) throws Error {
            var list = new Gee.ArrayList<PathData> ();
            bounds = Rect.empty ();
            var doc = Xml.Parser.read_memory (text, text.length, null, null, Xml.ParserOption.NONET | Xml.ParserOption.NOBLANKS);
            if (doc == null) throw new FormatError.INVALID (_("The SVG file is not valid"));
            walk (doc->get_root_element (), Cairo.Matrix.identity (), list);
            delete doc;
            foreach (var p in list) bounds = bounds.union (p.bounds ());
            return list;
        }

        private static Cairo.Matrix parse_transform (string? t) {
            var m = Cairo.Matrix.identity ();
            if (t == null) return m;
            try {
                var re = new Regex ("(matrix|translate|scale|rotate)\\s*\\(([^)]*)\\)");
                MatchInfo mi;
                re.match (t, 0, out mi);
                while (mi.matches ()) {
                    string fn = mi.fetch (1);
                    var nums = Regex.split_simple ("[\\s,]+", mi.fetch (2).strip ());
                    double[] v = {};
                    foreach (var s in nums) if (s != "") v += double.parse (s);
                    var step = Cairo.Matrix.identity ();
                    if (fn == "matrix" && v.length == 6) step = Cairo.Matrix (v[0], v[1], v[2], v[3], v[4], v[5]);
                    else if (fn == "translate" && v.length >= 1) step.translate (v[0], v.length > 1 ? v[1] : 0);
                    else if (fn == "scale" && v.length >= 1) step.scale (v[0], v.length > 1 ? v[1] : v[0]);
                    else if (fn == "rotate" && v.length >= 1) {
                        if (v.length == 3) step.translate (v[1], v[2]);
                        step.rotate (v[0] * Math.PI / 180);
                        if (v.length == 3) step.translate (-v[1], -v[2]);
                    }
                    var r = Cairo.Matrix.identity ();
                    r.multiply (step, m);
                    m = r;
                    mi.next ();
                }
            } catch (Error e) {
            }
            return m;
        }

        private static void walk (Xml.Node* n, Cairo.Matrix parent, Gee.List<PathData> out_list) {
            for (Xml.Node* c = n; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                var local = parse_transform (c->get_prop ("transform"));
                var m = Cairo.Matrix.identity ();
                m.multiply (local, parent);
                PathData? p = null;
                switch (c->name) {
                    case "path":
                        p = PathData.parse_svg (c->get_prop ("d") ?? "");
                        break;
                    case "rect":
                        p = new PathData.rect (dbl (c, "x"), dbl (c, "y"), dbl (c, "width"), dbl (c, "height"));
                        break;
                    case "circle":
                        p = new PathData.ellipse (dbl (c, "cx"), dbl (c, "cy"), dbl (c, "r"), dbl (c, "r"));
                        break;
                    case "ellipse":
                        p = new PathData.ellipse (dbl (c, "cx"), dbl (c, "cy"), dbl (c, "rx"), dbl (c, "ry"));
                        break;
                    case "line":
                        p = new PathData ();
                        p.move_to (dbl (c, "x1"), dbl (c, "y1"));
                        p.line_to (dbl (c, "x2"), dbl (c, "y2"));
                        break;
                    case "polyline":
                    case "polygon": {
                        var nums = Regex.split_simple ("[\\s,]+", (c->get_prop ("points") ?? "").strip ());
                        Point[] pts = {};
                        for (int i = 0; i + 1 < nums.length; i += 2) pts += Point (double.parse (nums[i]), double.parse (nums[i + 1]));
                        p = new PathData ();
                        p.add_polygon (pts, c->name == "polygon");
                        break;
                    }
                    default:
                        if (c->children != null) walk (c->children, m, out_list);
                        break;
                }
                if (p != null && !p.is_empty ()) {
                    p.transform (m);
                    out_list.add (p);
                }
            }
        }

        private static double dbl (Xml.Node* n, string name) {
            return Units.parse_length (n->get_prop (name), 0);
        }

        public static SketchLayer to_layer (Gee.List<PathData> paths, string id, string name) {
            var l = new SketchLayer (id, name);
            foreach (var p in paths) {
                foreach (var poly in p.flatten (0.5)) {
                    var s = new Stroke ();
                    s.brush_id = "technical";
                    s.kind = BrushKind.TECHNICAL;
                    s.size = 0.8;
                    s.min_size = 0.8;
                    s.pressure_size = false;
                    s.smooth_curve = false;
                    foreach (var q in poly.pts) s.samples.add (StrokeSample (q.x, q.y, 1));
                    if (poly.closed && poly.pts.length > 0) s.samples.add (StrokeSample (poly.pts[0].x, poly.pts[0].y, 1));
                    l.strokes.add (s);
                }
            }
            return l;
        }
    }
}
