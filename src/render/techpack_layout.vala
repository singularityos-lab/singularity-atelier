using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public abstract class TpBlock {
        public double space_after = 10;

        public abstract double measure (Cairo.Context cr, double width);
        public abstract void draw (Cairo.Context cr, double x, double y, double width);

        public virtual TpBlock? split (Cairo.Context cr, double width, double available) {
            return null;
        }
    }

    public class TpHeading : TpBlock {
        public string text;
        public double size;

        public TpHeading (string text, double size = 15) {
            this.text = text;
            this.size = size;
            space_after = 6;
        }

        private Pango.Layout layout (Cairo.Context cr, double width) {
            var l = Pango.cairo_create_layout (cr);
            var fd = Pango.FontDescription.from_string ("Sans Bold");
            fd.set_absolute_size (size * Pango.SCALE);
            l.set_font_description (fd);
            l.set_width ((int) (width * Pango.SCALE));
            l.set_text (text, -1);
            return l;
        }

        public override double measure (Cairo.Context cr, double width) {
            int w, h;
            layout (cr, width).get_pixel_size (out w, out h);
            return h;
        }

        public override void draw (Cairo.Context cr, double x, double y, double width) {
            cr.move_to (x, y);
            cr.set_source_rgb (0.1, 0.1, 0.12);
            Pango.cairo_show_layout (cr, layout (cr, width));
        }
    }

    public class TpText : TpBlock {
        public string text;
        public double size;

        public TpText (string text, double size = 9) {
            this.text = text;
            this.size = size;
        }

        private Pango.Layout layout (Cairo.Context cr, double width) {
            var l = Pango.cairo_create_layout (cr);
            var fd = Pango.FontDescription.from_string ("Sans");
            fd.set_absolute_size (size * Pango.SCALE);
            l.set_font_description (fd);
            l.set_width ((int) (width * Pango.SCALE));
            l.set_wrap (Pango.WrapMode.WORD_CHAR);
            l.set_text (text, -1);
            return l;
        }

        public override double measure (Cairo.Context cr, double width) {
            int w, h;
            layout (cr, width).get_pixel_size (out w, out h);
            return h;
        }

        public override void draw (Cairo.Context cr, double x, double y, double width) {
            cr.move_to (x, y);
            cr.set_source_rgb (0.15, 0.15, 0.18);
            Pango.cairo_show_layout (cr, layout (cr, width));
        }
    }

    public delegate void TpPainter (Cairo.Context cr, double width, double height);

    public class TpPicture : TpBlock {
        public double height;
        private TpPainter painter;

        public TpPicture (double height, owned TpPainter painter) {
            this.height = height;
            this.painter = (owned) painter;
        }

        public override double measure (Cairo.Context cr, double width) {
            return height;
        }

        public override void draw (Cairo.Context cr, double x, double y, double width) {
            cr.save ();
            cr.translate (x, y);
            cr.rectangle (0, 0, width, height);
            cr.clip ();
            painter (cr, width, height);
            cr.restore ();
        }
    }

    public class TpTable : TpBlock {
        public Sheet sheet;
        public double font = 7.5;
        public int header_count = 1;
        public int highlight_col = -1;
        private int start_row;

        public TpTable (Sheet sheet, int highlight_col = -1) {
            this.sheet = sheet;
            this.highlight_col = highlight_col;
            header_count = sheet.header_rows.contains (0) ? 1 : 0;
            start_row = header_count;
        }

        private double[] widths (Cairo.Context cr, double width) {
            int cols = 0;
            foreach (var r in sheet.rows) cols = int.max (cols, r.size);
            var want = new double[cols];
            var l = cell_layout (cr, "", 0, false);
            foreach (var r in sheet.rows) {
                for (int c = 0; c < r.size; c++) {
                    l.set_width (-1);
                    l.set_text (r[c], -1);
                    int w, h;
                    l.get_pixel_size (out w, out h);
                    want[c] = double.max (want[c], double.min (w + 8, 200));
                }
            }
            double total = 0;
            foreach (var w in want) total += double.max (w, 18);
            var out_w = new double[cols];
            for (int c = 0; c < cols; c++) out_w[c] = double.max (want[c], 18) / total * width;
            return out_w;
        }

        private Pango.Layout cell_layout (Cairo.Context cr, string text, double width, bool bold) {
            var l = Pango.cairo_create_layout (cr);
            var fd = Pango.FontDescription.from_string (bold ? "Sans Bold" : "Sans");
            fd.set_absolute_size (font * Pango.SCALE);
            l.set_font_description (fd);
            if (width > 0) l.set_width ((int) ((width - 6) * Pango.SCALE));
            l.set_wrap (Pango.WrapMode.WORD_CHAR);
            l.set_text (text, -1);
            return l;
        }

        private double row_height (Cairo.Context cr, Gee.List<string> row, double[] w, bool bold) {
            double h = 0;
            for (int c = 0; c < row.size && c < w.length; c++) {
                int pw, ph;
                cell_layout (cr, row[c], w[c], bold).get_pixel_size (out pw, out ph);
                h = double.max (h, ph);
            }
            return h + 5;
        }

        public override double measure (Cairo.Context cr, double width) {
            var w = widths (cr, width);
            double h = 0;
            for (int r = 0; r < header_count; r++) h += row_height (cr, sheet.rows[r], w, true);
            for (int r = start_row; r < sheet.rows.size; r++) h += row_height (cr, sheet.rows[r], w, sheet.header_rows.contains (r));
            return h;
        }

        public override TpBlock? split (Cairo.Context cr, double width, double available) {
            var w = widths (cr, width);
            double h = 0;
            for (int r = 0; r < header_count; r++) h += row_height (cr, sheet.rows[r], w, true);
            int r2 = start_row;
            while (r2 < sheet.rows.size) {
                double rh = row_height (cr, sheet.rows[r2], w, sheet.header_rows.contains (r2));
                if (h + rh > available) break;
                h += rh;
                r2++;
            }
            if (r2 <= start_row || r2 >= sheet.rows.size) return null;
            var rest = new TpTable (sheet, highlight_col);
            rest.font = font;
            rest.header_count = header_count;
            rest.start_row = r2;
            rest.end_row_limit = -1;
            end_row_limit = r2;
            return rest;
        }

        public int end_row_limit = -1;

        public override void draw (Cairo.Context cr, double x, double y, double width) {
            var w = widths (cr, width);
            double cy = y;
            int end = end_row_limit > 0 ? end_row_limit : sheet.rows.size;
            var rows = new Gee.ArrayList<int> ();
            for (int r = 0; r < header_count; r++) rows.add (r);
            for (int r = start_row; r < end; r++) rows.add (r);
            int zebra = 0;
            foreach (int r in rows) {
                bool hdr = sheet.header_rows.contains (r);
                double rh = row_height (cr, sheet.rows[r], w, hdr);
                if (hdr) {
                    cr.rectangle (x, cy, width, rh);
                    cr.set_source_rgb (0.9, 0.91, 0.93);
                    cr.fill ();
                } else if (zebra++ % 2 == 1) {
                    cr.rectangle (x, cy, width, rh);
                    cr.set_source_rgb (0.97, 0.97, 0.98);
                    cr.fill ();
                }
                double cx = x;
                for (int c = 0; c < sheet.rows[r].size && c < w.length; c++) {
                    if (c == highlight_col && !hdr) {
                        cr.rectangle (cx, cy, w[c], rh);
                        cr.set_source_rgba (0.95, 0.75, 0.2, 0.25);
                        cr.fill ();
                    }
                    cr.move_to (cx + 3, cy + 2.5);
                    cr.set_source_rgb (0.12, 0.12, 0.15);
                    Pango.cairo_show_layout (cr, cell_layout (cr, sheet.rows[r][c], w[c], hdr));
                    cx += w[c];
                }
                cr.set_source_rgb (0.8, 0.81, 0.84);
                cr.set_line_width (0.4);
                cr.move_to (x, cy + rh);
                cr.line_to (x + width, cy + rh);
                cr.stroke ();
                cy += rh;
            }
        }
    }

    public class TpPage {
        public string title;
        public Gee.ArrayList<TpBlock> blocks = new Gee.ArrayList<TpBlock> ();

        public TpPage (string title) {
            this.title = title;
        }
    }

    public class TechPackLayout {
        public Project project;
        public Gee.ArrayList<TpPage> pages = new Gee.ArrayList<TpPage> ();
        public double width;
        public double height;
        public string colorway = "";
        public bool include_pattern = true;
        public bool include_colorways = true;
        public bool include_sketch = true;
        public const double HEADER = 34;
        public const double FOOTER = 18;

        public TechPackLayout (Project project) {
            this.project = project;
        }

        private Colorway cw () {
            var c = colorway != "" ? project.find_colorway (colorway) : null;
            return c ?? project.colorway ();
        }

        public void build (double content_width, double content_height) {
            width = content_width;
            height = content_height;
            pages.clear ();
            var tp = project.techpack;
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 4, 4);
            var mcr = new Cairo.Context (surf);
            var cover = new TpPage (_("Overview"));
            cover.blocks.add (new TpHeading (tp.style_name != "" ? tp.style_name : project.title, 20));
            var info = new Sheet (_("Style"));
            info.add ({ _("Style Number"), tp.style_number, _("Season"), tp.season });
            info.add ({ _("Brand"), tp.brand, _("Designer"), tp.designer });
            info.add ({ _("Category"), tp.category, _("Status"), tp.status });
            info.add ({ _("Base Size"), project.pattern.table.base_size, _("Size Range"), string.joinv (" ", project.pattern.all_sizes ().to_array ()) });
            info.add ({ _("Colorway"), cw ().name, _("Date"), new DateTime.now_local ().format ("%Y-%m-%d") });
            var info_table = new TpTable (info);
            info_table.header_count = 0;
            cover.blocks.add (info_table);
            if (project.flats.size > 0) {
                var sheets = project.flats;
                var colorway_obj = cw ();
                cover.blocks.add (new TpPicture (double.min (content_height * 0.5, 360), (cr, w, h) => {
                    double cell = w / double.max (1, int.min (2, sheets.size));
                    for (int i = 0; i < sheets.size && i < 2; i++) draw_sheet_fit (cr, sheets[i], colorway_obj, i * cell, 0, cell, h, true);
                }));
            }
            if (tp.notes != "") cover.blocks.add (new TpText (tp.notes));
            if (project.colorways.size > 0) cover.blocks.add (swatches_block ());
            if (include_sketch && !project.sketch.bounds ().is_empty ()) {
                var sk = project.sketch;
                cover.blocks.add (new TpHeading (_("Concept"), 11));
                cover.blocks.add (new TpPicture (150, (cr, w, h) => {
                    var b = sk.bounds ();
                    double sc = double.min (w / b.w, h / b.h);
                    cr.translate ((w - b.w * sc) / 2, 0);
                    cr.scale (sc, sc);
                    cr.translate (-b.x, -b.y);
                    SketchRenderer.draw (cr, sk, null, null, false);
                }));
            }
            pages.add (cover);
            foreach (var sheet in project.flats) {
                var pg = new TpPage (_("Technical Drawing: %s").printf (sheet.name));
                pg.blocks.add (new TpHeading (_("Technical Drawing: %s").printf (sheet.name)));
                var s = sheet;
                var colorway_obj = cw ();
                pg.blocks.add (new TpPicture (content_height * 0.62, (cr, w, h) => draw_sheet_fit (cr, s, colorway_obj, 0, 0, w, h, false)));
                var legend = new Sheet (_("Callouts"));
                legend.add ({ "#", _("Detail"), _("Link") }, true);
                foreach (var it in sheet.items) {
                    if (it.kind != FlatItemKind.CALLOUT) continue;
                    string link = "";
                    foreach (var op in tp.operations) if (op.callout == it.number) link = "%d. %s".printf (op.seq, op.description);
                    var bi = tp.find_bom (it.link);
                    if (bi != null) link = bi.name;
                    legend.add ({ it.number.to_string (), it.text, link });
                }
                if (legend.rows.size > 1) pg.blocks.add (new TpTable (legend));
                pages.add (pg);
            }
            if (tp.poms.size > 0) {
                var pg = new TpPage (_("Points of Measure"));
                pg.blocks.add (new TpHeading (_("Points of Measure")));
                pg.blocks.add (new TpText (_("Values in %s. Tolerances apply to every size.").printf (project.pattern.unit)));
                int base_col = 5 + project.pattern.all_sizes ().index_of (project.pattern.table.base_size);
                pg.blocks.add (new TpTable (Tables.pom_sheet (tp, project.pattern), base_col));
                pages.add (pg);
            }
            if (tp.bom.size > 0) {
                var pg = new TpPage (_("Bill of Materials"));
                pg.blocks.add (new TpHeading (_("Bill of Materials")));
                pg.blocks.add (new TpTable (Tables.bom_sheet (tp, project.colorways)));
                pg.blocks.add (new TpText (_("Total cost per garment: %s %s").printf (PathData.fmt (tp.total_cost (), 2), tp.bom.size > 0 ? tp.bom[0].currency : "")));
                pages.add (pg);
            }
            if (tp.operations.size > 0) {
                var pg = new TpPage (_("Construction"));
                pg.blocks.add (new TpHeading (_("Construction")));
                pg.blocks.add (new TpTable (Tables.operations_sheet (tp)));
                pg.blocks.add (new TpText (_("Standard minutes: %s").printf (PathData.fmt (tp.total_minutes (), 2))));
                pages.add (pg);
            }
            if (include_pattern && project.pattern.pieces.size > 0) {
                var pg = new TpPage (_("Pattern Pieces"));
                pg.blocks.add (new TpHeading (_("Pattern Pieces")));
                var res = project.pattern.evaluate (project.pattern.table.base_size);
                pg.blocks.add (new TpPicture (content_height * 0.45, (cr, w, h) => {
                    var b = PatternRenderer.pieces_bounds (res, true);
                    if (b.is_empty ()) return;
                    b = b.inflate (10);
                    double sc = double.min (w / b.w, h / b.h);
                    cr.translate ((w - b.w * sc) / 2, 0);
                    cr.scale (sc, sc);
                    cr.translate (-b.x, -b.y);
                    var st = new PatternStyle ();
                    st.zoom = sc;
                    st.print_mode = true;
                    foreach (var g in res.pieces) PatternRenderer.draw_piece (cr, g.transformed (g.placement_matrix ()), st, res.size);
                }));
                var list = new Sheet (_("Pieces"));
                list.add ({ _("Code"), _("Piece"), _("Material"), _("Cut"), _("On Fold"), _("Area (cm²)") }, true);
                foreach (var g in res.pieces) list.add ({ g.piece.code, g.piece.name, g.piece.material, g.piece.quantity.to_string (), g.piece.on_fold ? _("Yes") : _("No"), PathData.fmt (g.area () / 100, 1) });
                pg.blocks.add (new TpTable (list));
                pages.add (pg);
            }
            if (include_colorways && project.colorways.size > 1 && project.flats.size > 0) {
                var pg = new TpPage (_("Colorways"));
                pg.blocks.add (new TpHeading (_("Colorways")));
                var sheet = project.flats[0];
                var cws = project.colorways;
                pg.blocks.add (new TpPicture (content_height * 0.6, (cr, w, h) => {
                    int n = cws.size;
                    int cols = int.min (3, n);
                    int rows = (n + cols - 1) / cols;
                    double cw2 = w / cols, ch = h / rows;
                    var lay = Pango.cairo_create_layout (cr);
                    var fd = Pango.FontDescription.from_string ("Sans Bold");
                    fd.set_absolute_size (9 * Pango.SCALE);
                    lay.set_font_description (fd);
                    for (int i = 0; i < n; i++) {
                        double x = (i % cols) * cw2, y = (i / cols) * ch;
                        draw_sheet_fit (cr, sheet, cws[i], x, y + 14, cw2, ch - 14, true);
                        lay.set_text (cws[i].name, -1);
                        cr.move_to (x + 4, y);
                        cr.set_source_rgb (0.1, 0.1, 0.1);
                        Pango.cairo_show_layout (cr, lay);
                    }
                }));
                pages.add (pg);
            }
            if (tp.revisions.size > 0 || tp.comments.size > 0) {
                var pg = new TpPage (_("Revisions"));
                pg.blocks.add (new TpHeading (_("Revisions and Comments")));
                var rev = new Sheet (_("Revisions"));
                rev.add ({ _("Revision"), _("Date"), _("Author"), _("Change") }, true);
                foreach (var r in tp.revisions) rev.add ({ r.number.to_string (), r.date, r.author, r.note });
                if (rev.rows.size > 1) pg.blocks.add (new TpTable (rev));
                var com = new Sheet (_("Comments"));
                com.add ({ _("Date"), _("Author"), _("Comment"), _("Status") }, true);
                foreach (var c in tp.comments) {
                    com.add ({ c.date, c.author, c.text, c.resolved ? _("Resolved") : _("Open") });
                    foreach (var r in c.replies) com.add ({ r.date, r.author, "  " + r.text, "" });
                }
                if (com.rows.size > 1) pg.blocks.add (new TpTable (com));
                pages.add (pg);
            }
            paginate (mcr);
        }

        private TpBlock swatches_block () {
            var cws = project.colorways;
            var slots = project.slots;
            return new TpPicture (18 + 26 * cws.size, (cr, w, h) => {
                var lay = Pango.cairo_create_layout (cr);
                var fd = Pango.FontDescription.from_string ("Sans");
                fd.set_absolute_size (7.5 * Pango.SCALE);
                lay.set_font_description (fd);
                double col = (w - 90) / double.max (1, slots.size);
                for (int s = 0; s < slots.size; s++) {
                    lay.set_text (slots[s], -1);
                    cr.move_to (90 + s * col, 0);
                    cr.set_source_rgb (0.3, 0.3, 0.3);
                    Pango.cairo_show_layout (cr, lay);
                }
                for (int i = 0; i < cws.size; i++) {
                    double y = 14 + i * 26;
                    lay.set_text (cws[i].name, -1);
                    cr.move_to (0, y + 5);
                    cr.set_source_rgb (0.1, 0.1, 0.1);
                    Pango.cairo_show_layout (cr, lay);
                    for (int s = 0; s < slots.size; s++) {
                        var cref = cws[i].colors.has_key (slots[s]) ? cws[i].colors[slots[s]] : null;
                        if (cref == null) continue;
                        cr.rectangle (90 + s * col, y, 18, 18);
                        cref.color.apply (cr);
                        cr.fill_preserve ();
                        cr.set_source_rgb (0.6, 0.6, 0.6);
                        cr.set_line_width (0.5);
                        cr.stroke ();
                        lay.set_text (cref.code != "" ? cref.code : cref.name, -1);
                        cr.move_to (90 + s * col + 21, y + 4);
                        cr.set_source_rgb (0.2, 0.2, 0.2);
                        Pango.cairo_show_layout (cr, lay);
                    }
                }
            });
        }

        public static void draw_sheet_fit (Cairo.Context cr, FlatSheet sheet, Colorway cw, double x, double y, double w, double h, bool caption) {
            var b = FlatRenderer.sheet_bounds (sheet);
            double sc = double.min (w / b.w, h / b.h);
            cr.save ();
            cr.translate (x + (w - b.w * sc) / 2, y + (h - b.h * sc) / 2);
            cr.scale (sc, sc);
            cr.translate (-b.x, -b.y);
            FlatRenderer.draw_sheet (cr, sheet, cw, sc);
            cr.restore ();
            if (caption) {
                var lay = Pango.cairo_create_layout (cr);
                var fd = Pango.FontDescription.from_string ("Sans");
                fd.set_absolute_size (8 * Pango.SCALE);
                lay.set_font_description (fd);
                lay.set_text (sheet.name, -1);
                int lw, lh;
                lay.get_pixel_size (out lw, out lh);
                cr.move_to (x + (w - lw) / 2, y + h - lh);
                cr.set_source_rgb (0.35, 0.35, 0.35);
                Pango.cairo_show_layout (cr, lay);
            }
        }

        private void paginate (Cairo.Context cr) {
            var out_pages = new Gee.ArrayList<TpPage> ();
            double avail = height - HEADER - FOOTER;
            foreach (var pg in pages) {
                var cur = new TpPage (pg.title);
                double used = 0;
                var queue = new Gee.ArrayList<TpBlock> ();
                queue.add_all (pg.blocks);
                while (queue.size > 0) {
                    var b = queue.remove_at (0);
                    double h = b.measure (cr, width);
                    if (used + h <= avail || cur.blocks.size == 0 && h > avail && b.split (cr, width, avail - used) == null) {
                        cur.blocks.add (b);
                        used += h + b.space_after;
                        continue;
                    }
                    var rest = b.split (cr, width, avail - used);
                    if (rest != null) {
                        cur.blocks.add (b);
                        out_pages.add (cur);
                        cur = new TpPage (pg.title);
                        used = 0;
                        queue.insert (0, rest);
                    } else {
                        out_pages.add (cur);
                        cur = new TpPage (pg.title);
                        used = 0;
                        queue.insert (0, b);
                        if (b.measure (cr, width) > avail) {
                            cur.blocks.add (queue.remove_at (0));
                            used = avail;
                        }
                    }
                }
                if (cur.blocks.size > 0) out_pages.add (cur);
            }
            pages = out_pages;
        }

        public void draw_page (Cairo.Context cr, int index, double x0, double y0) {
            if (index < 0 || index >= pages.size) return;
            var pg = pages[index];
            var tp = project.techpack;
            cr.save ();
            var lay = Pango.cairo_create_layout (cr);
            var fd = Pango.FontDescription.from_string ("Sans Bold");
            fd.set_absolute_size (8 * Pango.SCALE);
            lay.set_font_description (fd);
            lay.set_text ("%s  %s".printf (tp.style_number, tp.style_name != "" ? tp.style_name : project.title).strip (), -1);
            cr.move_to (x0, y0);
            cr.set_source_rgb (0.1, 0.1, 0.12);
            Pango.cairo_show_layout (cr, lay);
            fd = Pango.FontDescription.from_string ("Sans");
            fd.set_absolute_size (8 * Pango.SCALE);
            lay.set_font_description (fd);
            lay.set_text ("%s  %s".printf (tp.season, pg.title), -1);
            int lw, lh;
            lay.get_pixel_size (out lw, out lh);
            cr.move_to (x0 + width - lw, y0);
            Pango.cairo_show_layout (cr, lay);
            cr.set_source_rgb (0.75, 0.55, 0.3);
            cr.rectangle (x0, y0 + 14, width, 1.5);
            cr.fill ();
            double y = y0 + HEADER;
            foreach (var b in pg.blocks) {
                double h = b.measure (cr, width);
                b.draw (cr, x0, y, width);
                y += h + b.space_after;
            }
            lay.set_text (_("Page %d of %d").printf (index + 1, pages.size), -1);
            lay.get_pixel_size (out lw, out lh);
            cr.move_to (x0 + width - lw, y0 + height - lh);
            cr.set_source_rgb (0.4, 0.4, 0.45);
            Pango.cairo_show_layout (cr, lay);
            lay.set_text (_("Made with Atelier"), -1);
            cr.move_to (x0, y0 + height - lh);
            Pango.cairo_show_layout (cr, lay);
            cr.restore ();
        }

        public void write_pdf (string path, double page_w = 841.89, double page_h = 595.28, double margin = 32) {
            build (page_w - 2 * margin, page_h - 2 * margin);
            var surf = new Cairo.PdfSurface (path, page_w, page_h);
            surf.set_metadata (Cairo.PdfMetadata.TITLE, project.techpack.style_name != "" ? project.techpack.style_name : project.title);
            surf.set_metadata (Cairo.PdfMetadata.CREATOR, "Atelier");
            var cr = new Cairo.Context (surf);
            for (int i = 0; i < pages.size; i++) {
                draw_page (cr, i, margin, margin);
                cr.show_page ();
            }
            surf.finish ();
        }
    }
}
