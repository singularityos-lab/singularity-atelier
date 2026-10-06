using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class SketchPrintSource : Singularity.Print.PageSource {
        private Sketch sketch;
        private Singularity.Print.PageFormat? format;

        public SketchPrintSource (Sketch sketch, string title) {
            this.sketch = sketch;
            this.title = title;
            var x = new Singularity.Print.ExtraOptions (_("Sketch"), _("How the sketch is placed on the paper"));
            x.add_switch ("paper", _("Print the Paper Colour"), null, false);
            x.add_switch ("guides", _("Print the Guides"), null, false);
            extra_options = x;
        }

        public override async int paginate (Singularity.Print.PageFormat f) throws Error {
            format = f;
            page_width = f.width;
            page_height = f.height;
            return 1;
        }

        public override void render_page (Cairo.Context cr, int index) {
            if (format == null) return;
            var b = sketch.bounds ();
            if (b.is_empty ()) return;
            b = b.inflate (10);
            double sc = double.min (format.content_width / b.w, format.content_height / b.h);
            cr.save ();
            cr.translate (format.margin_left + (format.content_width - b.w * sc) / 2, format.margin_top + (format.content_height - b.h * sc) / 2);
            cr.scale (sc, sc);
            cr.translate (-b.x, -b.y);
            cr.rectangle (b.x, b.y, b.w, b.h);
            cr.clip ();
            SketchRenderer.draw (cr, sketch, null, null, extra_options.get_bool ("paper"));
            if (extra_options.get_bool ("guides")) SketchRenderer.draw_guides (cr, sketch.guides, sc, b);
            cr.restore ();
        }
    }

    public class PatternPrintSource : Singularity.Print.PageSource {
        private Pattern pattern;
        private Singularity.Print.PageFormat? format;
        private PatternTiler? tiler;
        private PatternResult? result;
        private Gee.HashMap<string, PatternResult>? nest;

        public PatternPrintSource (Pattern pattern, string title, int overlap_mm) {
            this.pattern = pattern;
            this.title = title;
            var x = new Singularity.Print.ExtraOptions (_("Pattern"), _("Real scale pages for cutting, or the whole pattern on one page"));
            x.add_choice ("mode", _("Layout"), { "tiled", "fit" }, { _("Real Scale on Several Pages"), _("Whole Pattern on One Page") }, "tiled");
            var sizes = pattern.all_sizes ();
            string[] ids = { "all" };
            string[] labels = { _("All Sizes Nested") };
            foreach (var s in sizes) {
                ids += s;
                labels += s;
            }
            x.add_choice ("size", _("Size"), ids, labels, pattern.active_size != "" ? pattern.active_size : pattern.table.base_size);
            x.add_number ("overlap", _("Overlap"), _("In millimetres, for taping pages together"), 0, 30, 1, overlap_mm);
            x.add_switch ("marks", _("Page Labels and Alignment Marks"), null, true);
            x.add_switch ("square", _("50 mm Test Square"), _("Check the printer scale with a ruler"), true);
            extra_options = x;
        }

        public override async int paginate (Singularity.Print.PageFormat f) throws Error {
            format = f;
            page_width = f.width;
            page_height = f.height;
            string size = extra_options.get_choice ("size");
            nest = null;
            if (size == "all") {
                nest = Grading.nest (pattern);
                result = nest[pattern.table.base_size] ?? pattern.evaluate ();
            } else {
                result = pattern.evaluate (size);
            }
            if (extra_options.get_choice ("mode") == "fit") {
                tiler = null;
                return 1;
            }
            var area = PatternPrint.print_area (result, true);
            if (nest != null) foreach (var r in nest.values) area = area.union (PatternPrint.print_area (r, true));
            tiler = new PatternTiler (area, f.content_width, f.content_height, extra_options.get_number ("overlap"));
            return tiler.count ();
        }

        public override void render_page (Cairo.Context cr, int index) {
            if (format == null || result == null) return;
            if (tiler != null) {
                PatternPrint.draw_tile (cr, tiler, index, format.margin_left, format.margin_top, extra_options.get_bool ("marks"), extra_options.get_bool ("square"), result, true, nest != null ? pattern : null, nest);
                return;
            }
            var b = PatternPrint.print_area (result, true);
            double sc = double.min (format.content_width / b.w, format.content_height / b.h);
            cr.save ();
            cr.translate (format.margin_left + (format.content_width - b.w * sc) / 2, format.margin_top + (format.content_height - b.h * sc) / 2);
            cr.scale (sc, sc);
            cr.translate (-b.x, -b.y);
            if (nest != null) PatternPrint.draw_nest (cr, pattern, nest, sc);
            else PatternPrint.draw_pieces (cr, result, true, sc);
            cr.restore ();
        }
    }

    public class FlatsPrintSource : Singularity.Print.PageSource {
        private Project project;
        private Singularity.Print.PageFormat? format;

        public FlatsPrintSource (Project project, string title) {
            this.project = project;
            this.title = title;
            var x = new Singularity.Print.ExtraOptions (_("Technical Drawings"), "");
            string[] ids = {};
            string[] labels = {};
            foreach (var c in project.colorways) {
                ids += c.name;
                labels += c.name;
            }
            x.add_choice ("colorway", _("Colorway"), ids, labels, project.colorway ().name);
            x.add_switch ("caption", _("Sheet Names"), null, true);
            extra_options = x;
        }

        public override async int paginate (Singularity.Print.PageFormat f) throws Error {
            format = f;
            page_width = f.width;
            page_height = f.height;
            return int.max (1, project.flats.size);
        }

        public override void render_page (Cairo.Context cr, int index) {
            if (format == null || index >= project.flats.size) return;
            var cw = project.find_colorway (extra_options.get_choice ("colorway")) ?? project.colorway ();
            TechPackLayout.draw_sheet_fit (cr, project.flats[index], cw, format.margin_left, format.margin_top, format.content_width, format.content_height, extra_options.get_bool ("caption"));
        }
    }

    public class TechPackPrintSource : Singularity.Print.PageSource {
        private Project project;
        private TechPackLayout layout;
        private Singularity.Print.PageFormat? format;

        public TechPackPrintSource (Project project) {
            this.project = project;
            this.title = project.techpack.style_name != "" ? project.techpack.style_name : project.title;
            layout = new TechPackLayout (project);
            var x = new Singularity.Print.ExtraOptions (_("Tech Pack"), _("Sections and colorway of the printed tech pack"));
            string[] ids = {};
            string[] labels = {};
            foreach (var c in project.colorways) {
                ids += c.name;
                labels += c.name;
            }
            x.add_choice ("colorway", _("Colorway"), ids, labels, project.colorway ().name);
            x.add_switch ("pattern", _("Pattern Pieces"), null, true);
            x.add_switch ("colorways", _("All Colorways"), null, true);
            x.add_switch ("sketch", _("Concept Sketch"), null, true);
            extra_options = x;
        }

        public override async int paginate (Singularity.Print.PageFormat f) throws Error {
            format = f;
            page_width = f.width;
            page_height = f.height;
            layout.colorway = extra_options.get_choice ("colorway");
            layout.include_pattern = extra_options.get_bool ("pattern");
            layout.include_colorways = extra_options.get_bool ("colorways");
            layout.include_sketch = extra_options.get_bool ("sketch");
            layout.build (f.content_width, f.content_height);
            return layout.pages.size;
        }

        public override void render_page (Cairo.Context cr, int index) {
            if (format == null) return;
            layout.draw_page (cr, index, format.margin_left, format.margin_top);
        }
    }
}
