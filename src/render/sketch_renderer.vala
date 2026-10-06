using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class SketchRenderer {
        public static void draw (Cairo.Context cr, Sketch sketch, Stroke? live = null, SketchLayer? live_layer = null, bool paper = true) {
            if (paper) {
                sketch.paper.apply (cr);
                cr.paint ();
            }
            foreach (var l in sketch.layers) draw_layer (cr, l, live, live_layer);
            if (live != null && live_layer == null) draw_stroke (cr, live);
        }

        public static Cairo.Operator blend_op (string blend) {
            switch (blend) {
                case "multiply": return Cairo.Operator.MULTIPLY;
                case "screen": return Cairo.Operator.SCREEN;
                case "overlay": return Cairo.Operator.OVERLAY;
                case "darken": return Cairo.Operator.DARKEN;
                case "lighten": return Cairo.Operator.LIGHTEN;
                default: return Cairo.Operator.OVER;
            }
        }

        public static void draw_layer (Cairo.Context cr, SketchLayer l, Stroke? live = null, SketchLayer? live_layer = null) {
            if (!l.visible) return;
            cr.push_group ();
            switch (l.kind) {
                case LayerKind.IMAGE: {
                    var img = l.image ();
                    if (img != null) {
                        cr.save ();
                        cr.transform (l.image_matrix);
                        cr.set_source_surface (img, 0, 0);
                        cr.paint ();
                        cr.restore ();
                    }
                    break;
                }
                case LayerKind.UNDERLAY:
                    draw_underlay (cr, l);
                    break;
                case LayerKind.GROUP:
                    foreach (var c in l.children) draw_layer (cr, c, live, live_layer);
                    break;
                default:
                    break;
            }
            foreach (var f in l.fills) {
                cr.new_path ();
                f.path.to_cairo (cr);
                cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                f.set_source (cr);
                cr.fill ();
            }
            foreach (var s in l.strokes) draw_stroke (cr, s);
            if (live != null && live_layer == l) draw_stroke (cr, live);
            cr.pop_group_to_source ();
            cr.save ();
            cr.set_operator (blend_op (l.blend));
            cr.paint_with_alpha (l.opacity);
            cr.restore ();
        }

        public static void draw_underlay (Cairo.Context cr, SketchLayer l) {
            if (l.underlay.has_prefix ("vehicle:")) {
                var t = VehicleTemplate.preset (l.underlay.substring (8));
                foreach (var e in l.underlay_params.entries) {
                    switch (e.key) {
                        case "wheelbase": t.wheelbase = e.value; break;
                        case "length": t.length = e.value; break;
                        case "height": t.height = e.value; break;
                        case "wheel": t.wheel = e.value; break;
                        case "front_overhang": t.front_overhang = e.value; break;
                        case "ground": t.ground = e.value; break;
                        case "x": break;
                        case "y": break;
                        case "scale": break;
                    }
                }
                double ox = l.underlay_params.has_key ("x") ? l.underlay_params["x"] : 100;
                double oy = l.underlay_params.has_key ("y") ? l.underlay_params["y"] : 600;
                double sc = l.underlay_params.has_key ("scale") ? l.underlay_params["scale"] : 0.12;
                cr.save ();
                cr.translate (ox, oy);
                cr.scale (sc, sc);
                cr.set_line_width (1.2 / sc);
                cr.set_source_rgba (0.25, 0.45, 0.8, 0.45);
                cr.new_path ();
                t.ground_line ().to_cairo (cr);
                t.guides ().to_cairo (cr);
                cr.set_dash ({ 8 / sc, 6 / sc }, 0);
                cr.stroke ();
                cr.set_dash (null, 0);
                cr.new_path ();
                t.wheels ().to_cairo (cr);
                cr.set_source_rgba (0.25, 0.45, 0.8, 0.6);
                cr.stroke ();
                cr.new_path ();
                t.body ().to_cairo (cr);
                cr.set_source_rgba (0.25, 0.45, 0.8, 0.08);
                cr.fill_preserve ();
                cr.set_source_rgba (0.25, 0.45, 0.8, 0.5);
                cr.stroke ();
                cr.restore ();
            }
        }

        public static void draw_stroke (Cairo.Context cr, Stroke s) {
            if (s.samples.size == 0) return;
            Point[] c;
            double[] w;
            double[] a;
            s.outline (out c, out w, out a);
            cr.save ();
            if (s.kind == BrushKind.ERASER) cr.set_operator (Cairo.Operator.DEST_OUT);
            switch (s.kind) {
                case BrushKind.AIRBRUSH:
                    airbrush (cr, s, c, w, a);
                    break;
                case BrushKind.MARKER:
                    fill_outline (cr, c, w, s.color, avg (a), false);
                    break;
                case BrushKind.PENCIL:
                    chunked (cr, s, c, w, a);
                    break;
                case BrushKind.ERASER:
                    fill_outline (cr, c, w, Rgba (0, 0, 0, 1), 1, true);
                    break;
                default:
                    fill_outline (cr, c, w, s.color, avg (a), true);
                    break;
            }
            cr.restore ();
        }

        private static double avg (double[] a) {
            if (a.length == 0) return 1;
            double t = 0;
            foreach (var v in a) t += v;
            return t / a.length;
        }

        private static void fill_outline (Cairo.Context cr, Point[] c, double[] w, Rgba color, double alpha, bool round) {
            var outline = StrokeOutline.build (c, w, round);
            if (outline.length < 3) return;
            cr.new_path ();
            cr.move_to (outline[0].x, outline[0].y);
            for (int i = 1; i < outline.length; i++) cr.line_to (outline[i].x, outline[i].y);
            cr.close_path ();
            cr.set_fill_rule (Cairo.FillRule.WINDING);
            color.apply (cr, alpha);
            cr.fill ();
        }

        private static void chunked (Cairo.Context cr, Stroke s, Point[] c, double[] w, double[] a) {
            int n = c.length;
            if (n < 2) {
                fill_outline (cr, c, w, s.color, a.length > 0 ? a[0] : 1, true);
                return;
            }
            cr.push_group ();
            int step = 6;
            for (int i = 0; i < n - 1; i += step) {
                int end = int.min (n, i + step + 1);
                Point[] cc = c[i:end];
                double[] ww = w[i:end];
                double al = 0;
                for (int k = i; k < end; k++) al += a[k];
                cr.set_operator (Cairo.Operator.SOURCE);
                fill_outline (cr, cc, ww, s.color, al / (end - i), true);
            }
            cr.pop_group_to_source ();
            cr.paint ();
            if (s.texture > 0) {
                cr.save ();
                cr.new_path ();
                var outline = StrokeOutline.build (c, w, true);
                if (outline.length > 2) {
                    cr.move_to (outline[0].x, outline[0].y);
                    for (int i = 1; i < outline.length; i++) cr.line_to (outline[i].x, outline[i].y);
                    cr.close_path ();
                    cr.clip ();
                    cr.set_operator (Cairo.Operator.DEST_OUT);
                    cr.set_source (grain_pattern ());
                    cr.paint_with_alpha (s.texture);
                }
                cr.restore ();
            }
        }

        private static Cairo.Pattern? grain_cache;

        private static Cairo.Pattern grain_pattern () {
            if (grain_cache == null) {
                var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 64, 64);
                surf.flush ();
                unowned uint8[] data = surf.get_data ();
                int stride = surf.get_stride ();
                var rnd = new Rand.with_seed (7);
                for (int y = 0; y < 64; y++) {
                    for (int x = 0; x < 64; x++) {
                        uint8 v = (uint8) (rnd.int_range (0, 100) < 30 ? rnd.int_range (80, 255) : 0);
                        int o = y * stride + x * 4;
                        data[o] = 0;
                        data[o + 1] = 0;
                        data[o + 2] = 0;
                        data[o + 3] = v;
                    }
                }
                surf.mark_dirty ();
                var p = new Cairo.Pattern.for_surface (surf);
                p.set_extend (Cairo.Extend.REPEAT);
                var m = Cairo.Matrix.identity ();
                m.scale (3, 3);
                p.set_matrix (m);
                grain_cache = p;
            }
            return grain_cache;
        }

        private static void airbrush (Cairo.Context cr, Stroke s, Point[] c, double[] w, double[] a) {
            double acc = 0;
            for (int i = 0; i < c.length; i++) {
                if (i > 0) acc += c[i].distance (c[i - 1]);
                double r = w[i] / 2;
                if (i > 0 && acc < r * 0.25) continue;
                acc = 0;
                var g = new Cairo.Pattern.radial (c[i].x, c[i].y, 0, c[i].x, c[i].y, r);
                g.add_color_stop_rgba (0, s.color.r, s.color.g, s.color.b, s.color.a * a[i]);
                g.add_color_stop_rgba (s.hardness.clamp (0, 0.95), s.color.r, s.color.g, s.color.b, s.color.a * a[i] * 0.6);
                g.add_color_stop_rgba (1, s.color.r, s.color.g, s.color.b, 0);
                cr.set_source (g);
                cr.arc (c[i].x, c[i].y, r, 0, 2 * Math.PI);
                cr.fill ();
            }
        }

        public static Cairo.ImageSurface render_image (Sketch sketch, double scale, out Rect area, int max_px = 8192) {
            area = sketch.bounds ();
            if (area.is_empty ()) area = Rect (0, 0, 800, 600);
            area = area.inflate (20);
            double sc = scale;
            if (area.w * sc > max_px) sc = max_px / area.w;
            if (area.h * sc > max_px) sc = max_px / area.h;
            int w = int.max (1, (int) Math.ceil (area.w * sc));
            int h = int.max (1, (int) Math.ceil (area.h * sc));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surf);
            cr.scale (sc, sc);
            cr.translate (-area.x, -area.y);
            draw (cr, sketch);
            return surf;
        }

        public static Cairo.ImageSurface render_layer (SketchLayer l, Rect area, double scale) {
            int w = int.max (1, (int) Math.ceil (area.w * scale));
            int h = int.max (1, (int) Math.ceil (area.h * scale));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surf);
            cr.scale (scale, scale);
            cr.translate (-area.x, -area.y);
            bool vis = l.visible;
            double op = l.opacity;
            l.visible = true;
            l.opacity = 1;
            draw_layer (cr, l);
            l.visible = vis;
            l.opacity = op;
            return surf;
        }

        public static void draw_guides (Cairo.Context cr, Guides g, double zoom, Rect view) {
            double lw = 1.2 / zoom;
            cr.save ();
            cr.set_line_width (lw);
            if (g.ruler_on) {
                double dx = g.ruler_b.x - g.ruler_a.x, dy = g.ruler_b.y - g.ruler_a.y;
                double l = Math.hypot (dx, dy);
                if (l > 1e-6) {
                    double ux = dx / l, uy = dy / l;
                    double big = double.max (view.w, view.h) * 4;
                    cr.set_source_rgba (0.1, 0.45, 0.9, 0.55);
                    cr.move_to (g.ruler_a.x - ux * big, g.ruler_a.y - uy * big);
                    cr.line_to (g.ruler_a.x + ux * big, g.ruler_a.y + uy * big);
                    cr.stroke ();
                    cr.set_source_rgba (0.1, 0.45, 0.9, 0.12);
                    double nx = -uy * 18 / zoom, ny = ux * 18 / zoom;
                    cr.move_to (g.ruler_a.x, g.ruler_a.y);
                    cr.line_to (g.ruler_b.x, g.ruler_b.y);
                    cr.line_to (g.ruler_b.x + nx, g.ruler_b.y + ny);
                    cr.line_to (g.ruler_a.x + nx, g.ruler_a.y + ny);
                    cr.close_path ();
                    cr.fill ();
                    handle (cr, g.ruler_a, zoom);
                    handle (cr, g.ruler_b, zoom);
                }
            }
            if (g.ellipse_on) {
                cr.save ();
                cr.translate (g.ellipse_center.x, g.ellipse_center.y);
                cr.rotate (g.ellipse_angle * Math.PI / 180);
                cr.scale (g.ellipse_rx, g.ellipse_ry);
                cr.arc (0, 0, 1, 0, 2 * Math.PI);
                cr.restore ();
                cr.set_source_rgba (0.1, 0.45, 0.9, 0.55);
                cr.stroke ();
                handle (cr, g.ellipse_center, zoom);
                double r = g.ellipse_angle * Math.PI / 180;
                handle (cr, Point (g.ellipse_center.x + g.ellipse_rx * Math.cos (r), g.ellipse_center.y + g.ellipse_rx * Math.sin (r)), zoom);
                handle (cr, Point (g.ellipse_center.x - g.ellipse_ry * Math.sin (r), g.ellipse_center.y + g.ellipse_ry * Math.cos (r)), zoom);
            }
            if (g.curve_on) {
                var p = g.curve_path ();
                if (p != null) {
                    cr.new_path ();
                    p.to_cairo (cr);
                    cr.set_source_rgba (0.1, 0.45, 0.9, 0.1);
                    cr.fill_preserve ();
                    cr.set_source_rgba (0.1, 0.45, 0.9, 0.6);
                    cr.stroke ();
                    handle (cr, g.curve_pos, zoom);
                }
            }
            if (g.perspective > 0) {
                cr.set_source_rgba (0.85, 0.35, 0.15, 0.35);
                cr.set_line_width (lw * 0.8);
                cr.move_to (view.x - view.w, g.vp1.y);
                cr.line_to (view.x2 () + view.w, g.vp1.y);
                cr.stroke ();
                foreach (var vp in g.vanishing_points ()) {
                    for (int i = 0; i < 36; i++) {
                        double ang = 2 * Math.PI * i / 36;
                        double big = double.max (view.w, view.h) * 3;
                        cr.move_to (vp.x, vp.y);
                        cr.line_to (vp.x + big * Math.cos (ang), vp.y + big * Math.sin (ang));
                    }
                    cr.set_source_rgba (0.85, 0.35, 0.15, 0.16);
                    cr.stroke ();
                    handle (cr, vp, zoom);
                }
            }
            if (g.symmetry != SymmetryMode.NONE) {
                cr.set_source_rgba (0.55, 0.2, 0.75, 0.5);
                cr.set_dash ({ 6 / zoom, 4 / zoom }, 0);
                var c = g.symmetry_center;
                double big = double.max (view.w, view.h) * 3;
                if (g.symmetry == SymmetryMode.VERTICAL || g.symmetry == SymmetryMode.BOTH) {
                    cr.move_to (c.x, c.y - big);
                    cr.line_to (c.x, c.y + big);
                }
                if (g.symmetry == SymmetryMode.HORIZONTAL || g.symmetry == SymmetryMode.BOTH) {
                    cr.move_to (c.x - big, c.y);
                    cr.line_to (c.x + big, c.y);
                }
                if (g.symmetry == SymmetryMode.RADIAL) {
                    int n = int.max (2, g.radial_count);
                    for (int i = 0; i < n; i++) {
                        double ang = 2 * Math.PI * i / n - Math.PI / 2;
                        cr.move_to (c.x, c.y);
                        cr.line_to (c.x + big * Math.cos (ang), c.y + big * Math.sin (ang));
                    }
                }
                cr.stroke ();
                cr.set_dash (null, 0);
                handle (cr, c, zoom);
            }
            cr.restore ();
        }

        private static void handle (Cairo.Context cr, Point p, double zoom) {
            cr.save ();
            cr.arc (p.x, p.y, 5 / zoom, 0, 2 * Math.PI);
            cr.set_source_rgba (1, 1, 1, 0.95);
            cr.fill_preserve ();
            cr.set_source_rgba (0.1, 0.45, 0.9, 0.9);
            cr.set_line_width (1.5 / zoom);
            cr.stroke ();
            cr.restore ();
        }
    }
}
