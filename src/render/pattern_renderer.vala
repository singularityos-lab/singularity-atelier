using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class PatternStyle {
        public Rgba ink = Rgba (0.12, 0.13, 0.16, 1);
        public Rgba accent = Rgba (0.15, 0.42, 0.85, 1);
        public Rgba construction = Rgba (0.45, 0.47, 0.52, 0.7);
        public Rgba selected = Rgba (0.95, 0.45, 0.1, 1);
        public Rgba error = Rgba (0.85, 0.15, 0.15, 1);
        public Rgba piece_fill = Rgba (0.98, 0.95, 0.88, 0.85);
        public double zoom = 1;
        public bool show_labels = true;
        public bool show_construction = true;
        public bool show_seam = true;
        public bool print_mode;
        public string label_font = "Sans";

        public double px (double v) {
            return v / zoom;
        }
    }

    public class PatternRenderer {
        public static Rgba size_color (int index, int count) {
            double h = count <= 1 ? 0.6 : (double) index / count;
            return hsv (h * 0.85, 0.75, 0.85);
        }

        private static Rgba hsv (double h, double s, double v) {
            double r = 0, g = 0, b = 0;
            int i = (int) Math.floor (h * 6);
            double f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
            switch (i % 6) {
                case 0: r = v; g = t; b = p; break;
                case 1: r = q; g = v; b = p; break;
                case 2: r = p; g = v; b = t; break;
                case 3: r = p; g = q; b = v; break;
                case 4: r = t; g = p; b = v; break;
                default: r = v; g = p; b = q; break;
            }
            return Rgba (r, g, b, 1);
        }

        public static void poly (Cairo.Context cr, Point[] pts, bool closed) {
            if (pts.length == 0) return;
            cr.move_to (pts[0].x, pts[0].y);
            for (int i = 1; i < pts.length; i++) cr.line_to (pts[i].x, pts[i].y);
            if (closed) cr.close_path ();
        }

        public static void draw_draft (Cairo.Context cr, Pattern pattern, PatternResult r, PatternStyle st, Gee.Set<string>? selected = null) {
            cr.save ();
            cr.set_line_width (st.px (1.2));
            foreach (var c in pattern.curves) {
                if (!r.curves.has_key (c.id)) continue;
                bool sel = selected != null && selected.contains (c.id);
                cr.new_path ();
                bool first = true;
                foreach (var bz in r.curves[c.id]) {
                    if (first) cr.move_to (bz.p0.x, bz.p0.y);
                    first = false;
                    cr.curve_to (bz.p1.x, bz.p1.y, bz.p2.x, bz.p2.y, bz.p3.x, bz.p3.y);
                }
                (sel ? st.selected : (c.kind == CurveKind.LINE ? st.construction : st.ink)).apply (cr);
                cr.set_line_width (st.px (sel ? 2.4 : 1.4));
                cr.stroke ();
                if (sel && c.kind != CurveKind.LINE) {
                    cr.set_line_width (st.px (0.8));
                    foreach (var bz in r.curves[c.id]) {
                        cr.move_to (bz.p0.x, bz.p0.y);
                        cr.line_to (bz.p1.x, bz.p1.y);
                        cr.move_to (bz.p3.x, bz.p3.y);
                        cr.line_to (bz.p2.x, bz.p2.y);
                    }
                    st.selected.apply (cr, 0.6);
                    cr.stroke ();
                    foreach (var bz in r.curves[c.id]) {
                        foreach (var hp in new Point[] { bz.p1, bz.p2 }) {
                            cr.arc (hp.x, hp.y, st.px (3), 0, 2 * Math.PI);
                            st.selected.apply (cr);
                            cr.fill ();
                        }
                    }
                }
            }
            if (st.show_construction) {
                cr.set_line_width (st.px (0.8));
                cr.set_dash ({ st.px (4), st.px (3) }, 0);
                st.construction.apply (cr);
                foreach (var p in pattern.points) {
                    if (!r.points.has_key (p.id) || p.hidden) continue;
                    var at = r.points[p.id];
                    string? from = null;
                    switch (p.kind) {
                        case PointKind.END_LINE:
                        case PointKind.ALONG_LINE:
                        case PointKind.NORMAL:
                        case PointKind.OFFSET:
                        case PointKind.BISECTOR:
                            from = p.kind == PointKind.BISECTOR ? p.b : p.a;
                            break;
                        case PointKind.FOOT:
                        case PointKind.LINE_AXIS:
                            from = p.c;
                            break;
                        default:
                            break;
                    }
                    if (from != null && r.points.has_key (from)) {
                        var f = r.points[from];
                        cr.move_to (f.x, f.y);
                        cr.line_to (at.x, at.y);
                    }
                }
                cr.stroke ();
                cr.set_dash (null, 0);
            }
            var layout = Pango.cairo_create_layout (cr);
            var fd = Pango.FontDescription.from_string (st.label_font);
            fd.set_absolute_size (st.px (11) * Pango.SCALE);
            layout.set_font_description (fd);
            foreach (var p in pattern.points) {
                bool err = r.errors.has_key (p.id);
                if (!r.points.has_key (p.id) || (p.hidden && !(selected != null && selected.contains (p.id)))) continue;
                var at = r.points[p.id];
                bool sel = selected != null && selected.contains (p.id);
                cr.arc (at.x, at.y, st.px (sel ? 4.5 : 3), 0, 2 * Math.PI);
                (err ? st.error : (sel ? st.selected : st.accent)).apply (cr);
                cr.fill ();
                if (st.show_labels) {
                    layout.set_text (p.name, -1);
                    cr.move_to (at.x + st.px (5), at.y - st.px (16));
                    st.ink.apply (cr, 0.85);
                    Pango.cairo_show_layout (cr, layout);
                }
            }
            cr.restore ();
        }

        public static void draw_piece (Cairo.Context cr, PieceGeometry g, PatternStyle st, string size, bool selected = false, Rgba? outline_color = null) {
            if (g.cut.length < 3 && g.seam.length < 3) return;
            cr.save ();
            var ink = outline_color ?? st.ink;
            cr.new_path ();
            poly (cr, g.cut.length > 2 ? g.cut : g.seam, true);
            if (!st.print_mode) {
                st.piece_fill.apply (cr, selected ? 1 : 0.8);
                cr.fill_preserve ();
            }
            (selected ? st.selected : ink).apply (cr);
            cr.set_line_width (st.px (selected ? 2.2 : 1.5));
            cr.stroke ();
            if (st.show_seam && g.cut.length > 2 && g.seam.length > 2 && !g.piece.built_in) {
                cr.new_path ();
                poly (cr, g.seam, true);
                cr.set_dash ({ st.px (6), st.px (3) }, 0);
                cr.set_line_width (st.px (0.9));
                ink.apply (cr, 0.8);
                cr.stroke ();
                cr.set_dash (null, 0);
            }
            cr.set_line_width (st.px (1.1));
            foreach (var n in g.notches) draw_notch (cr, n, st, ink);
            foreach (var il in g.internals) {
                cr.new_path ();
                poly (cr, il.pts, false);
                cr.set_dash ({ st.px (8), st.px (3), st.px (2), st.px (3) }, 0);
                ink.apply (cr, 0.8);
                cr.stroke ();
                cr.set_dash (null, 0);
            }
            for (int i = 0; i < g.drills.size; i++) {
                var d = g.drills[i];
                double rr = (i < g.drill_sizes.size ? g.drill_sizes[i] : 3) / 2;
                cr.arc (d.x, d.y, rr, 0, 2 * Math.PI);
                cr.move_to (d.x - rr * 2, d.y);
                cr.line_to (d.x + rr * 2, d.y);
                cr.move_to (d.x, d.y - rr * 2);
                cr.line_to (d.x, d.y + rr * 2);
                ink.apply (cr);
                cr.stroke ();
            }
            if (g.has_grain) draw_grain (cr, g.grain_a, g.grain_b, g.piece.grain_arrows, st, ink);
            if (g.piece.on_fold && g.piece.fold_edge >= 0 && g.piece.fold_edge < g.edges.size) {
                var e = g.edges[g.piece.fold_edge].pts;
                if (e.length >= 2) {
                    var a = e[0];
                    var b = e[e.length - 1];
                    var c = g.center ();
                    double nx = c.x - (a.x + b.x) / 2, ny = c.y - (a.y + b.y) / 2;
                    double nl = Math.hypot (nx, ny);
                    if (nl > 1e-6) {
                        nx /= nl;
                        ny /= nl;
                    }
                    var a2 = Point (a.x + (b.x - a.x) * 0.2 + nx * 15, a.y + (b.y - a.y) * 0.2 + ny * 15);
                    var b2 = Point (a.x + (b.x - a.x) * 0.8 + nx * 15, a.y + (b.y - a.y) * 0.8 + ny * 15);
                    cr.move_to (a.x + (b.x - a.x) * 0.2, a.y + (b.y - a.y) * 0.2);
                    cr.line_to (a2.x, a2.y);
                    cr.line_to (b2.x, b2.y);
                    cr.line_to (a.x + (b.x - a.x) * 0.8, a.y + (b.y - a.y) * 0.8);
                    st.accent.apply (cr);
                    cr.set_line_width (st.px (1.2));
                    cr.stroke ();
                }
            }
            if (st.show_labels) draw_label (cr, g, st, size, ink);
            if (g.error != "") {
                var c = g.center ();
                var layout = Pango.cairo_create_layout (cr);
                var fd = Pango.FontDescription.from_string (st.label_font);
                fd.set_absolute_size (st.px (11) * Pango.SCALE);
                layout.set_font_description (fd);
                layout.set_text (g.error, -1);
                cr.move_to (c.x, c.y + 20);
                st.error.apply (cr);
                Pango.cairo_show_layout (cr, layout);
            }
            cr.restore ();
        }

        public static void draw_notch (Cairo.Context cr, NotchGeometry n, PatternStyle st, Rgba ink) {
            var a = n.cut_at;
            double ux = Math.cos (n.angle), uy = Math.sin (n.angle);
            double vx = -uy, vy = ux;
            ink.apply (cr);
            switch (n.type) {
                case "t":
                    cr.move_to (a.x, a.y);
                    cr.line_to (a.x + ux * n.length, a.y + uy * n.length);
                    cr.move_to (a.x + ux * n.length - vx * n.width, a.y + uy * n.length - vy * n.width);
                    cr.line_to (a.x + ux * n.length + vx * n.width, a.y + uy * n.length + vy * n.width);
                    break;
                case "v":
                case "u":
                case "castle":
                    cr.move_to (a.x - vx * n.width / 2, a.y - vy * n.width / 2);
                    cr.line_to (a.x + ux * n.length, a.y + uy * n.length);
                    cr.line_to (a.x + vx * n.width / 2, a.y + vy * n.width / 2);
                    break;
                case "check":
                    cr.move_to (a.x, a.y);
                    cr.line_to (a.x + ux * n.length + vx * n.width, a.y + uy * n.length + vy * n.width);
                    break;
                default:
                    cr.move_to (a.x, a.y);
                    cr.line_to (a.x + ux * n.length, a.y + uy * n.length);
                    break;
            }
            cr.stroke ();
        }

        public static void draw_grain (Cairo.Context cr, Point a, Point b, int arrows, PatternStyle st, Rgba ink) {
            cr.move_to (a.x, a.y);
            cr.line_to (b.x, b.y);
            double ang = Math.atan2 (b.y - a.y, b.x - a.x);
            double h = 12;
            if (arrows == 0 || arrows == 1) {
                cr.move_to (b.x, b.y);
                cr.line_to (b.x - h * Math.cos (ang - 0.35), b.y - h * Math.sin (ang - 0.35));
                cr.move_to (b.x, b.y);
                cr.line_to (b.x - h * Math.cos (ang + 0.35), b.y - h * Math.sin (ang + 0.35));
            }
            if (arrows == 0 || arrows == 2) {
                cr.move_to (a.x, a.y);
                cr.line_to (a.x + h * Math.cos (ang - 0.35), a.y + h * Math.sin (ang - 0.35));
                cr.move_to (a.x, a.y);
                cr.line_to (a.x + h * Math.cos (ang + 0.35), a.y + h * Math.sin (ang + 0.35));
            }
            ink.apply (cr);
            cr.set_line_width (st.px (1.2));
            cr.stroke ();
        }

        public static string label_text (Piece p, string size) {
            string cut;
            if (p.pair) cut = _("Cut %d, %d pairs").printf (p.quantity, int.max (1, p.quantity / 2));
            else cut = _("Cut %d").printf (p.quantity);
            if (p.on_fold) cut = cut + " " + _("on fold");
            string size_text = "";
            if (size != "base") size_text = _("Size %s").printf (size);
            string t = p.label;
            t = t.replace ("{name}", p.name);
            t = t.replace ("{size}", size_text);
            t = t.replace ("{cut}", cut);
            t = t.replace ("{code}", p.code);
            t = t.replace ("{material}", p.material);
            var lines = new Gee.ArrayList<string> ();
            foreach (var l in t.split ("\n")) if (l.strip () != "") lines.add (l.strip ());
            return string.joinv ("\n", lines.to_array ());
        }

        private static void draw_label (Cairo.Context cr, PieceGeometry g, PatternStyle st, string size, Rgba ink) {
            var c = g.center ();
            var layout = Pango.cairo_create_layout (cr);
            var fd = Pango.FontDescription.from_string (st.label_font);
            var b = g.bounds ();
            double fs = (double.min (b.w, b.h) / 14).clamp (4, 16);
            fd.set_absolute_size (fs * Pango.SCALE);
            layout.set_font_description (fd);
            layout.set_alignment (Pango.Alignment.CENTER);
            layout.set_text (label_text (g.piece, size), -1);
            int lw, lh;
            layout.get_pixel_size (out lw, out lh);
            double shift = g.has_grain ? fs * 1.2 : 0;
            cr.move_to (c.x - lw / 2.0 + shift, c.y - lh / 2.0);
            ink.apply (cr, 0.9);
            Pango.cairo_show_layout (cr, layout);
        }

        public static void draw_nest (Cairo.Context cr, Pattern pattern, Gee.Map<string, PatternResult> by_size, string piece_id, string anchor, PatternStyle st) {
            var sizes = pattern.all_sizes ();
            var base_res = by_size[pattern.table.base_size] ?? by_size[sizes[0]];
            var base_geom = base_res != null ? base_res.piece (piece_id) : null;
            for (int i = 0; i < sizes.size; i++) {
                var r = by_size[sizes[i]];
                if (r == null) continue;
                var g = r.piece (piece_id);
                if (g == null || g.cut.length < 3) continue;
                var off = base_geom != null ? Grading.anchor_offset (base_geom, g, anchor) : Point (0, 0);
                cr.save ();
                cr.translate (off.x, off.y);
                cr.new_path ();
                poly (cr, g.cut, true);
                var col = size_color (i, sizes.size);
                col.apply (cr, sizes[i] == pattern.table.base_size ? 1 : 0.85);
                cr.set_line_width (st.px (sizes[i] == pattern.table.base_size ? 2 : 1.1));
                cr.stroke ();
                cr.restore ();
            }
        }

        public static void draw_marker (Cairo.Context cr, MarkerResult m, PatternStyle st) {
            cr.save ();
            cr.rectangle (0, 0, m.length, m.width);
            cr.set_source_rgba (0.93, 0.9, 0.84, 1);
            cr.fill_preserve ();
            cr.set_source_rgba (0.3, 0.3, 0.3, 1);
            cr.set_line_width (st.px (1));
            cr.stroke ();
            var layout = Pango.cairo_create_layout (cr);
            var fd = Pango.FontDescription.from_string (st.label_font);
            fd.set_absolute_size (14 * Pango.SCALE);
            layout.set_font_description (fd);
            int i = 0;
            foreach (var p in m.placements) {
                cr.new_path ();
                poly (cr, p.outline, true);
                var col = size_color (i++ % 7, 7);
                col.apply (cr, 0.25);
                cr.fill_preserve ();
                col.apply (cr, 0.9);
                cr.stroke ();
                var r = Rect.empty ();
                foreach (var q in p.outline) r = r.include (q.x, q.y);
                layout.set_text (p.label, -1);
                cr.move_to (r.cx () - 30, r.cy () - 8);
                cr.set_source_rgba (0.1, 0.1, 0.1, 0.9);
                Pango.cairo_show_layout (cr, layout);
            }
            cr.restore ();
        }

        public static Rect pieces_bounds (PatternResult r, bool placed) {
            var b = Rect.empty ();
            foreach (var g in r.pieces) {
                var gg = placed ? g.transformed (g.placement_matrix ()) : g;
                b = b.union (gg.bounds ());
            }
            return b;
        }

        public static Rect draft_bounds (PatternResult r) {
            var b = Rect.empty ();
            foreach (var p in r.points.values) b = b.include (p.x, p.y);
            foreach (var list in r.curves.values) foreach (var bz in list) {
                b = b.include (bz.p0.x, bz.p0.y);
                b = b.include (bz.p3.x, bz.p3.y);
            }
            return b;
        }
    }
}
