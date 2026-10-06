using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class FlatRenderer {
        public static Gee.HashMap<string, Cairo.ImageSurface> fabric_cache = new Gee.HashMap<string, Cairo.ImageSurface> ();

        public static Point[] path_points (PathData p) {
            Point[] pts = {};
            foreach (var poly in p.flatten (0.3)) {
                foreach (var q in poly.pts) pts += q;
                if (poly.closed && poly.pts.length > 0) pts += poly.pts[0];
            }
            return pts;
        }

        public static Gee.ArrayList<PointList> polylines (PathData p) {
            var list = new Gee.ArrayList<PointList> ();
            foreach (var poly in p.flatten (0.3)) {
                Point[] pts = poly.pts;
                if (poly.closed && pts.length > 0) pts += pts[0];
                list.add (new PointList (pts));
            }
            return list;
        }

        public static Gee.ArrayList<PointList> stitch_geometry (Point[] base_pts, StitchStyle st, out bool dashed) {
            var out_lines = new Gee.ArrayList<PointList> ();
            dashed = false;
            if (base_pts.length < 2) return out_lines;
            var line = st.offset != 0 ? Offset.polyline (base_pts, st.offset) : base_pts;
            switch (st.kind) {
                case StitchKind.SINGLE:
                case StitchKind.CHAIN:
                    dashed = st.kind == StitchKind.SINGLE;
                    out_lines.add (new PointList (line));
                    break;
                case StitchKind.DOUBLE:
                    dashed = true;
                    out_lines.add (new PointList (Offset.polyline (line, -st.gap / 2)));
                    out_lines.add (new PointList (Offset.polyline (line, st.gap / 2)));
                    break;
                case StitchKind.TRIPLE:
                    dashed = true;
                    out_lines.add (new PointList (Offset.polyline (line, -st.gap / 2)));
                    out_lines.add (new PointList (line));
                    out_lines.add (new PointList (Offset.polyline (line, st.gap / 2)));
                    break;
                case StitchKind.COVERSTITCH:
                    dashed = true;
                    out_lines.add (new PointList (Offset.polyline (line, -st.gap / 3)));
                    out_lines.add (new PointList (Offset.polyline (line, st.gap / 3)));
                    break;
                case StitchKind.ZIGZAG:
                    out_lines.add (new PointList (zigzag (line, st.pitch, st.width / 2)));
                    break;
                case StitchKind.OVERLOCK:
                    out_lines.add (new PointList (zigzag (line, st.pitch * 0.8, st.width / 2)));
                    out_lines.add (new PointList (Offset.polyline (line, st.width / 2)));
                    break;
                default:
                    out_lines.add (new PointList (line));
                    break;
            }
            return out_lines;
        }

        public static Point[] zigzag (Point[] line, double pitch, double amp) {
            double total = Polyline.length (line);
            int n = int.max (2, (int) (total / double.max (0.5, pitch / 2)));
            Point[] pts = {};
            for (int i = 0; i <= n; i++) {
                double ang;
                var p = Polyline.at_length (line, total * i / n, out ang);
                double s = (i % 2 == 0 ? 1 : -1) * amp;
                pts += Point (p.x - Math.sin (ang) * s, p.y + Math.cos (ang) * s);
            }
            return pts;
        }

        public static void draw_stitch (Cairo.Context cr, Point[] base_pts, StitchStyle st, Rgba color, double zoom) {
            bool dashed;
            var lines = stitch_geometry (base_pts, st, out dashed);
            cr.save ();
            color.apply (cr);
            cr.set_line_width (double.max (0.35, 0.6));
            if (dashed) cr.set_dash ({ st.pitch * 0.65, st.pitch * 0.35 }, 0);
            foreach (var l in lines) {
                cr.new_path ();
                PatternRenderer.poly (cr, l.pts, false);
                cr.stroke ();
            }
            cr.set_dash (null, 0);
            var line = st.offset != 0 ? Offset.polyline (base_pts, st.offset) : base_pts;
            double total = Polyline.length (line);
            if (st.kind == StitchKind.CHAIN) {
                for (double d = 0; d < total; d += st.pitch) {
                    double ang;
                    var p = Polyline.at_length (line, d, out ang);
                    cr.save ();
                    cr.translate (p.x, p.y);
                    cr.rotate (ang);
                    cr.scale (st.pitch * 0.45, st.pitch * 0.25);
                    cr.arc (0, 0, 1, 0, 2 * Math.PI);
                    cr.restore ();
                    cr.stroke ();
                }
            } else if (st.kind == StitchKind.ZIPPER) {
                cr.set_line_width (1.2);
                cr.new_path ();
                PatternRenderer.poly (cr, line, false);
                cr.stroke ();
                cr.set_line_width (0.6);
                for (double d = 0; d < total; d += st.pitch * 0.7) {
                    double ang;
                    var p = Polyline.at_length (line, d, out ang);
                    double s = st.width;
                    cr.move_to (p.x - Math.sin (ang) * s, p.y + Math.cos (ang) * s);
                    cr.line_to (p.x + Math.sin (ang) * s, p.y - Math.cos (ang) * s);
                }
                cr.stroke ();
            } else if (st.kind == StitchKind.BLIND) {
                for (double d = 0; d < total; d += st.pitch * 3) {
                    double ang;
                    var p = Polyline.at_length (line, d, out ang);
                    var q = Polyline.at_length (line, d + st.pitch, out ang);
                    cr.move_to (p.x, p.y);
                    cr.line_to ((p.x + q.x) / 2 - Math.sin (ang) * st.width, (p.y + q.y) / 2 + Math.cos (ang) * st.width);
                    cr.line_to (q.x, q.y);
                }
                cr.stroke ();
            } else if (st.kind == StitchKind.COVERSTITCH) {
                var zz = zigzag (line, st.pitch * 2, st.gap / 3);
                cr.set_line_width (0.3);
                cr.new_path ();
                PatternRenderer.poly (cr, zz, false);
                cr.stroke ();
            }
            cr.restore ();
        }

        public static Cairo.Pattern? fabric_pattern (FlatItem it) {
            if (it.fabric_id == "") return null;
            var asset = Singularity.Assets.AssetLibrary.get_default ().find (it.fabric_id);
            if (asset == null) return null;
            string img = asset.get_field ("image");
            Cairo.ImageSurface? surf = null;
            if (img != "") {
                if (!fabric_cache.has_key (img)) {
                    try {
                        var pb = new Gdk.Pixbuf.from_file (img);
                        var s = new Cairo.ImageSurface (Cairo.Format.ARGB32, pb.width, pb.height);
                        var c = new Cairo.Context (s);
                        Gdk.cairo_set_source_pixbuf (c, pb, 0, 0);
                        c.paint ();
                        fabric_cache[img] = s;
                    } catch (Error e) {
                    }
                }
                if (fabric_cache.has_key (img)) surf = fabric_cache[img];
            }
            if (surf == null) {
                var col = Rgba.parse (asset.get_field ("color", "#b0b0b0"));
                string weave = asset.get_field ("weave", "plain");
                surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 16, 16);
                var c = new Cairo.Context (surf);
                col.apply (c);
                c.paint ();
                c.set_source_rgba (0, 0, 0, 0.18);
                c.set_line_width (1.2);
                if (weave == "twill") {
                    for (int i = -16; i < 32; i += 4) {
                        c.move_to (i, 16);
                        c.line_to (i + 16, 0);
                    }
                } else if (weave == "check") {
                    c.rectangle (0, 0, 8, 8);
                    c.rectangle (8, 8, 8, 8);
                    c.fill ();
                } else if (weave == "stripe") {
                    c.rectangle (0, 0, 16, 4);
                    c.fill ();
                } else {
                    for (int i = 0; i < 16; i += 2) {
                        c.move_to (i, 0);
                        c.line_to (i, 16);
                    }
                }
                c.stroke ();
            }
            var pat = new Cairo.Pattern.for_surface (surf);
            pat.set_extend (Cairo.Extend.REPEAT);
            var m = Cairo.Matrix.identity ();
            double sc = it.pattern_scale > 0 ? it.pattern_scale : 1;
            m.rotate (-it.pattern_angle * Math.PI / 180);
            m.scale (1 / sc, 1 / sc);
            pat.set_matrix (m);
            return pat;
        }

        public static void draw_sheet (Cairo.Context cr, FlatSheet sheet, Colorway cw, double zoom, Gee.Set<string>? selected = null, bool show_axis = false) {
            if (show_axis) {
                var b = sheet.bounds ();
                cr.save ();
                cr.set_source_rgba (0.55, 0.2, 0.75, 0.35);
                cr.set_line_width (1 / zoom);
                cr.set_dash ({ 6 / zoom, 4 / zoom }, 0);
                cr.move_to (sheet.axis_x, b.y - 40);
                cr.line_to (sheet.axis_x, b.y2 () + 40);
                cr.stroke ();
                cr.restore ();
            }
            foreach (var it in sheet.items) {
                if (it.kind != FlatItemKind.SHAPE) continue;
                draw_shape (cr, sheet, it, cw, zoom, selected != null && selected.contains (it.id));
            }
            foreach (var it in sheet.items) {
                bool sel = selected != null && selected.contains (it.id);
                switch (it.kind) {
                    case FlatItemKind.TRIM:
                        Trims.draw (cr, it.trim, it.at.x, it.at.y, it.size, it.rotation, cw.color (it.fill_slot, Rgba (0.3, 0.3, 0.3)), cw.color ("Outline", Rgba (0.1, 0.1, 0.1)));
                        if (it.mirror) Trims.draw (cr, it.trim, 2 * sheet.axis_x - it.at.x, it.at.y, it.size, -it.rotation, cw.color (it.fill_slot, Rgba (0.3, 0.3, 0.3)), cw.color ("Outline", Rgba (0.1, 0.1, 0.1)));
                        if (sel) select_box (cr, Rect (it.at.x - it.size / 2 - 3, it.at.y - it.size / 2 - 3, it.size + 6, it.size + 6), zoom);
                        break;
                    case FlatItemKind.DIMENSION:
                        draw_dimension (cr, it, sheet, zoom, sel);
                        break;
                    case FlatItemKind.CALLOUT:
                        draw_callout (cr, it, zoom, sel);
                        break;
                    case FlatItemKind.TEXT:
                        draw_text (cr, it, sel, zoom);
                        break;
                    default:
                        break;
                }
            }
        }

        private static void select_box (Cairo.Context cr, Rect r, double zoom) {
            cr.save ();
            cr.rectangle (r.x, r.y, r.w, r.h);
            cr.set_source_rgba (0.95, 0.45, 0.1, 0.9);
            cr.set_line_width (1.5 / zoom);
            cr.set_dash ({ 4 / zoom, 3 / zoom }, 0);
            cr.stroke ();
            cr.restore ();
        }

        public static void draw_shape (Cairo.Context cr, FlatSheet sheet, FlatItem it, Colorway cw, double zoom, bool selected) {
            var full = sheet.full_path (it);
            cr.save ();
            cr.new_path ();
            full.to_cairo (cr);
            bool closed = full.has_closed_subpath ();
            if (closed && (it.fill_slot != "" || it.fabric_id != "")) {
                var fp = fabric_pattern (it);
                if (fp != null) cr.set_source (fp);
                else cw.color (it.fill_slot, Rgba (0.9, 0.9, 0.9)).apply (cr);
                cr.set_fill_rule (Cairo.FillRule.WINDING);
                cr.fill_preserve ();
            }
            if (it.line_width > 0) {
                cw.color (it.line_slot, Rgba (0.1, 0.1, 0.1)).apply (cr);
                cr.set_line_width (it.line_width);
                cr.set_line_join (Cairo.LineJoin.ROUND);
                if (it.dashed) cr.set_dash ({ 4, 2 }, 0);
                cr.stroke ();
            } else {
                cr.new_path ();
            }
            cr.set_dash (null, 0);
            if (it.stitch.kind != StitchKind.NONE) {
                var col = cw.color (it.stitch.color_slot, Rgba (0.4, 0.3, 0.2));
                foreach (var pl in polylines (it.path)) draw_stitch (cr, pl.pts, it.stitch, col, zoom);
                if (it.mirror) foreach (var pl in polylines (it.path.transformed (Cairo.Matrix (-1, 0, 0, 1, 2 * sheet.axis_x, 0)))) {
                    var mirrored = it.stitch.copy ();
                    mirrored.offset = -mirrored.offset;
                    draw_stitch (cr, pl.pts, mirrored, col, zoom);
                }
            }
            if (selected) {
                cr.new_path ();
                full.to_cairo (cr);
                cr.set_source_rgba (0.95, 0.45, 0.1, 0.9);
                cr.set_line_width (2 / zoom);
                cr.stroke ();
                foreach (var s in it.path.segs) {
                    if (s.kind == SegKind.CLOSE) continue;
                    cr.rectangle (s.x - 3 / zoom, s.y - 3 / zoom, 6 / zoom, 6 / zoom);
                }
                cr.fill ();
            }
            cr.restore ();
        }

        public static string format_length (double mm) {
            return _("%s cm").printf (PathData.fmt (mm / 10, 1));
        }

        public static void draw_dimension (Cairo.Context cr, FlatItem it, FlatSheet sheet, double zoom, bool sel) {
            cr.save ();
            Rgba col = sel ? Rgba (0.95, 0.45, 0.1, 1) : Rgba (0.1, 0.4, 0.8, 1);
            col.apply (cr);
            cr.set_line_width (0.7);
            double len;
            Point label_at;
            if (!it.path.is_empty ()) {
                cr.new_path ();
                it.path.to_cairo (cr);
                cr.stroke ();
                var pts = path_points (it.path);
                len = Polyline.length (pts) * sheet.scale_mm;
                double ang;
                label_at = Polyline.at_length (pts, Polyline.length (pts) / 2, out ang);
                arrow (cr, pts[1], pts[0]);
                arrow (cr, pts[pts.length - 2], pts[pts.length - 1]);
            } else {
                var a = it.at;
                var b = it.at2;
                double dx = b.x - a.x, dy = b.y - a.y;
                double l = Math.hypot (dx, dy);
                double nx = l > 0 ? -dy / l : 0, ny = l > 0 ? dx / l : 1;
                var a2 = Point (a.x + nx * it.offset, a.y + ny * it.offset);
                var b2 = Point (b.x + nx * it.offset, b.y + ny * it.offset);
                cr.move_to (a.x, a.y);
                cr.line_to (a2.x + nx * 3, a2.y + ny * 3);
                cr.move_to (b.x, b.y);
                cr.line_to (b2.x + nx * 3, b2.y + ny * 3);
                cr.move_to (a2.x, a2.y);
                cr.line_to (b2.x, b2.y);
                cr.stroke ();
                arrow (cr, b2, a2);
                arrow (cr, a2, b2);
                len = l * sheet.scale_mm;
                label_at = Point ((a2.x + b2.x) / 2 + nx * 6, (a2.y + b2.y) / 2 + ny * 6);
            }
            string text = it.text != "" ? it.text : format_length (len);
            if (it.link != "") text = "%s  %s".printf (it.link, text);
            var layout = Pango.cairo_create_layout (cr);
            var fd = Pango.FontDescription.from_string ("Sans");
            fd.set_absolute_size (9 * Pango.SCALE);
            layout.set_font_description (fd);
            layout.set_text (text, -1);
            int w, h;
            layout.get_pixel_size (out w, out h);
            cr.rectangle (label_at.x - w / 2.0 - 2, label_at.y - h / 2.0 - 1, w + 4, h + 2);
            cr.set_source_rgba (1, 1, 1, 0.9);
            cr.fill ();
            col.apply (cr);
            cr.move_to (label_at.x - w / 2.0, label_at.y - h / 2.0);
            Pango.cairo_show_layout (cr, layout);
            cr.restore ();
        }

        private static void arrow (Cairo.Context cr, Point from, Point to) {
            double ang = Math.atan2 (to.y - from.y, to.x - from.x);
            double h = 5;
            cr.move_to (to.x, to.y);
            cr.line_to (to.x - h * Math.cos (ang - 0.4), to.y - h * Math.sin (ang - 0.4));
            cr.line_to (to.x - h * Math.cos (ang + 0.4), to.y - h * Math.sin (ang + 0.4));
            cr.close_path ();
            cr.fill ();
        }

        public static void draw_callout (Cairo.Context cr, FlatItem it, double zoom, bool sel) {
            cr.save ();
            Rgba col = sel ? Rgba (0.95, 0.45, 0.1, 1) : Rgba (0.8, 0.15, 0.2, 1);
            col.apply (cr);
            cr.set_line_width (0.8);
            cr.move_to (it.at.x, it.at.y);
            cr.line_to (it.at2.x, it.at2.y);
            cr.stroke ();
            cr.arc (it.at.x, it.at.y, 1.8, 0, 2 * Math.PI);
            cr.fill ();
            double r = 8;
            cr.arc (it.at2.x, it.at2.y, r, 0, 2 * Math.PI);
            cr.fill ();
            var layout = Pango.cairo_create_layout (cr);
            var fd = Pango.FontDescription.from_string ("Sans Bold");
            fd.set_absolute_size (9 * Pango.SCALE);
            layout.set_font_description (fd);
            layout.set_text (it.number.to_string (), -1);
            int w, h;
            layout.get_pixel_size (out w, out h);
            cr.set_source_rgb (1, 1, 1);
            cr.move_to (it.at2.x - w / 2.0, it.at2.y - h / 2.0);
            Pango.cairo_show_layout (cr, layout);
            if (it.text != "") {
                fd = Pango.FontDescription.from_string ("Sans");
                fd.set_absolute_size (8 * Pango.SCALE);
                layout.set_font_description (fd);
                layout.set_width ((int) (140 * Pango.SCALE));
                layout.set_wrap (Pango.WrapMode.WORD);
                layout.set_text (it.text, -1);
                col.apply (cr);
                cr.move_to (it.at2.x + r + 3, it.at2.y - 5);
                Pango.cairo_show_layout (cr, layout);
            }
            cr.restore ();
        }

        public static void draw_text (Cairo.Context cr, FlatItem it, bool sel, double zoom) {
            var layout = Pango.cairo_create_layout (cr);
            var fd = Pango.FontDescription.from_string ("Sans");
            fd.set_absolute_size (it.size * Pango.SCALE);
            layout.set_font_description (fd);
            layout.set_text (it.text, -1);
            cr.save ();
            cr.set_source_rgba (0.1, 0.1, 0.1, 1);
            cr.move_to (it.at.x, it.at.y);
            Pango.cairo_show_layout (cr, layout);
            if (sel) {
                int w, h;
                layout.get_pixel_size (out w, out h);
                select_box (cr, Rect (it.at.x - 2, it.at.y - 2, w + 4, h + 4), zoom);
            }
            cr.restore ();
        }

        public static Rect sheet_bounds (FlatSheet sheet) {
            var b = sheet.bounds ();
            return b.is_empty () ? Rect (0, 0, 800, 800) : b.inflate (30);
        }

        public static Cairo.ImageSurface render_sheet (FlatSheet sheet, Colorway cw, int max_px) {
            var b = sheet_bounds (sheet);
            double sc = double.min (max_px / b.w, max_px / b.h);
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, int.max (1, (int) (b.w * sc)), int.max (1, (int) (b.h * sc)));
            var cr = new Cairo.Context (surf);
            cr.set_source_rgb (1, 1, 1);
            cr.paint ();
            cr.scale (sc, sc);
            cr.translate (-b.x, -b.y);
            draw_sheet (cr, sheet, cw, sc);
            return surf;
        }
    }
}
