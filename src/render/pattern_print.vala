using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class PatternTiler {
        public const double PT_PER_MM = 72.0 / 25.4;
        public Rect area;
        public double tile_w;
        public double tile_h;
        public double overlap;
        public int cols;
        public int rows;

        public PatternTiler (Rect area, double content_w_pt, double content_h_pt, double overlap_mm) {
            this.area = area;
            overlap = overlap_mm;
            tile_w = content_w_pt / PT_PER_MM;
            tile_h = content_h_pt / PT_PER_MM;
            double step_w = double.max (10, tile_w - overlap);
            double step_h = double.max (10, tile_h - overlap);
            cols = int.max (1, (int) Math.ceil ((area.w - overlap) / step_w));
            rows = int.max (1, (int) Math.ceil ((area.h - overlap) / step_h));
        }

        public int count () {
            return cols * rows;
        }

        public Rect tile (int index) {
            int c = index % cols, r = index / cols;
            return Rect (area.x + c * (tile_w - overlap), area.y + r * (tile_h - overlap), tile_w, tile_h);
        }

        public static string label (int col, int row) {
            string letters = "";
            int n = row;
            do {
                letters = ((char) ('A' + n % 26)).to_string () + letters;
                n = n / 26 - 1;
            } while (n >= 0);
            return "%s%d".printf (letters, col + 1);
        }
    }

    public class PatternPrint {
        public static Rect print_area (PatternResult r, bool placed) {
            var b = PatternRenderer.pieces_bounds (r, placed);
            if (b.is_empty ()) b = Rect (0, 0, 100, 100);
            return b.inflate (5);
        }

        public static void draw_pieces (Cairo.Context cr, PatternResult r, bool placed, double zoom) {
            var st = new PatternStyle ();
            st.zoom = zoom;
            st.print_mode = true;
            foreach (var g in r.pieces) PatternRenderer.draw_piece (cr, placed ? g.transformed (g.placement_matrix ()) : g, st, r.size);
        }

        public static void draw_nest (Cairo.Context cr, Pattern p, Gee.Map<string, PatternResult> by_size, double zoom) {
            var st = new PatternStyle ();
            st.zoom = zoom;
            st.print_mode = true;
            var base_res = by_size[p.table.base_size];
            if (base_res == null) return;
            foreach (var g in base_res.pieces) {
                cr.save ();
                var m = g.placement_matrix ();
                cr.transform (m);
                PatternRenderer.draw_nest (cr, p, by_size, g.piece.id, "grain", st);
                cr.restore ();
            }
        }

        public static void draw_tile (Cairo.Context cr, PatternTiler t, int index, double x0, double y0, bool marks, bool test_square, PatternResult r, bool placed, Pattern? nest_pattern, Gee.Map<string, PatternResult>? nest) {
            var tile = t.tile (index);
            double k = PatternTiler.PT_PER_MM;
            cr.save ();
            cr.rectangle (x0, y0, tile.w * k, tile.h * k);
            cr.clip ();
            cr.translate (x0, y0);
            cr.scale (k, k);
            cr.translate (-tile.x, -tile.y);
            if (nest != null && nest_pattern != null) draw_nest (cr, nest_pattern, nest, k);
            else draw_pieces (cr, r, placed, k);
            cr.restore ();
            if (!marks) return;
            int col = index % t.cols, row = index / t.cols;
            cr.save ();
            cr.set_source_rgba (0.4, 0.4, 0.45, 1);
            cr.set_line_width (0.4);
            double ov = t.overlap * k;
            double w = tile.w * k, h = tile.h * k;
            cr.set_dash ({ 3, 3 }, 0);
            if (col > 0) {
                cr.move_to (x0 + ov, y0);
                cr.line_to (x0 + ov, y0 + h);
            }
            if (row > 0) {
                cr.move_to (x0, y0 + ov);
                cr.line_to (x0 + w, y0 + ov);
            }
            cr.stroke ();
            cr.set_dash (null, 0);
            foreach (var p in new Point[] { Point (x0 + ov / 2, y0 + ov / 2), Point (x0 + w - ov / 2, y0 + ov / 2), Point (x0 + ov / 2, y0 + h - ov / 2), Point (x0 + w - ov / 2, y0 + h - ov / 2) }) {
                cr.arc (p.x, p.y, 4, 0, 2 * Math.PI);
                cr.move_to (p.x - 6, p.y);
                cr.line_to (p.x + 6, p.y);
                cr.move_to (p.x, p.y - 6);
                cr.line_to (p.x, p.y + 6);
            }
            cr.stroke ();
            var lay = Pango.cairo_create_layout (cr);
            var fd = Pango.FontDescription.from_string ("Sans Bold");
            fd.set_absolute_size (14 * Pango.SCALE);
            lay.set_font_description (fd);
            lay.set_text (PatternTiler.label (col, row), -1);
            int lw, lh;
            lay.get_pixel_size (out lw, out lh);
            cr.move_to (x0 + (w - lw) / 2, y0 + (h - lh) / 2);
            cr.set_source_rgba (0.5, 0.5, 0.55, 0.35);
            Pango.cairo_show_layout (cr, lay);
            fd = Pango.FontDescription.from_string ("Sans");
            fd.set_absolute_size (7 * Pango.SCALE);
            lay.set_font_description (fd);
            lay.set_text (_("%s: page %d of %d, row %d, column %d").printf (PatternTiler.label (col, row), index + 1, t.count (), row + 1, col + 1), -1);
            cr.move_to (x0 + ov + 4, y0 + h - 12);
            cr.set_source_rgb (0.3, 0.3, 0.35);
            Pango.cairo_show_layout (cr, lay);
            if (test_square && index == 0) {
                double sq = 50 * k;
                double sx = x0 + ov + 10, sy = y0 + ov + 10;
                cr.rectangle (sx, sy, sq, sq);
                cr.set_line_width (0.8);
                cr.set_source_rgb (0, 0, 0);
                cr.stroke ();
                lay.set_text (_("50 mm test square"), -1);
                cr.move_to (sx + 3, sy + 3);
                Pango.cairo_show_layout (cr, lay);
            }
            cr.restore ();
        }

        public static void write_large_pdf (PatternResult r, string path, bool placed, double margin_mm = 10) {
            var area = print_area (r, placed);
            double k = PatternTiler.PT_PER_MM;
            var surf = new Cairo.PdfSurface (path, (area.w + 2 * margin_mm) * k, (area.h + 2 * margin_mm) * k);
            surf.set_metadata (Cairo.PdfMetadata.CREATOR, "Atelier");
            var cr = new Cairo.Context (surf);
            cr.scale (k, k);
            cr.translate (margin_mm - area.x, margin_mm - area.y);
            draw_pieces (cr, r, placed, k);
            cr.show_page ();
            surf.finish ();
        }

        public static void write_tiled_pdf (PatternResult r, string path, bool placed, double page_w_pt = 595.28, double page_h_pt = 841.89, double margin_pt = 28, double overlap_mm = 10) {
            var area = print_area (r, placed);
            var t = new PatternTiler (area, page_w_pt - 2 * margin_pt, page_h_pt - 2 * margin_pt, overlap_mm);
            var surf = new Cairo.PdfSurface (path, page_w_pt, page_h_pt);
            var cr = new Cairo.Context (surf);
            for (int i = 0; i < t.count (); i++) {
                draw_tile (cr, t, i, margin_pt, margin_pt, true, true, r, placed, null, null);
                cr.show_page ();
            }
            surf.finish ();
        }
    }
}
