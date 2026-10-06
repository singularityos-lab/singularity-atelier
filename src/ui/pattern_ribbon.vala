using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Atelier {

    public class PatternRibbon : ContextRibbon {
        private AtelierWindow win;
        private Gee.ArrayList<RibbonSelector> size_selectors = new Gee.ArrayList<RibbonSelector> ();
        private RibbonSelector units;
        private RibbonSelector grading;
        private RibbonSelector anchor;
        private RibbonContext sizes_context;
        private bool syncing;

        public PatternRibbon (AtelierWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.win = win;
            build_draft (add_context ("draft", _("Draft"), "atelier-pattern-symbolic"));
            build_pieces (add_context ("pieces", _("Pieces"), "atelier-piece-symbolic"));
            sizes_context = add_context ("nest", _("Sizes"), "atelier-grading-symbolic");
            build_sizes (sizes_context);
            build_marker (add_context ("marker", _("Marker"), "atelier-marker-layout-symbolic"));
            tabs.tooltip_text = _("Pattern View");
        }

        private PatternPanel? panel {
            get { return win.pattern_panel; }
        }

        private Pattern? pattern {
            get { return win.project != null ? win.project.pattern : null; }
        }

        private void size_selector (RibbonContext c) {
            var sel = c.add_selector (_("Size"), 8);
            sel.label = _("Size");
            sel.changed.connect ((id) => {
                if (syncing || panel == null) return;
                panel.set_size (id);
                sync_sizes ();
            });
            size_selectors.add (sel);
        }

        private RibbonButton button (RibbonContext c, string icon, string label, string tooltip, bool in_compact, owned Dialogs.ConfirmedFunc run) {
            var b = c.add_button (icon, label, tooltip);
            b.label_in_compact = in_compact;
            b.activated.connect (() => run ());
            return b;
        }

        private void build_draft (RibbonContext c) {
            size_selector (c);
            units = c.add_selector (_("Units"), 11);
            units.label = _("Units");
            units.add_option ("cm", _("Centimetres"));
            units.add_option ("mm", _("Millimetres"));
            units.add_option ("inch", _("Inches"));
            units.changed.connect ((id) => {
                if (!syncing && panel != null) panel.set_unit (id);
            });
            c.add_separator ();
            button (c, "atelier-measure-symbolic", _("Measurements"), _("Edit the Measurement Table"), true, () => {
                if (panel != null) panel.edit_measurements ();
            });
            button (c, "document-open-symbolic", _("Import Table"), _("Import a Measurement Table from Seamly2D, Valentina, CSV or XLSX"), false, () => win.import ("measurements"));
            button (c, "camera-photo-symbolic", _("Pattern from Photo"), _("Trace a Paper Pattern Photographed on a Table"), false, () => win.import ("photo"));
        }

        private void build_pieces (RibbonContext c) {
            size_selector (c);
            c.add_separator ();
            var solid = c.add_menu ("atelier-cube-symbolic", _("Develop a Solid"), _("Flat Pieces for Bags, Cylinders and Cones"));
            solid.label_in_compact = true;
            solid.set_builder ((menu) => {
                string[,] solids = { { "gusset", _("Bag with Gusset…") }, { "boxed-corners", _("Bag with Boxed Corners…") }, { "two-piece", _("Wrap and Side Panels…") }, { "cylinder", _("Cylinder or Duffel…") }, { "cone", _("Bucket or Cone…") } };
                for (int i = 0; i < solids.length[0]; i++) {
                    string id = solids[i, 0];
                    menu.add_item (solids[i, 1], null, () => {
                        if (panel != null) panel.develop_solid (id);
                    });
                }
            });
        }

        private void build_sizes (RibbonContext c) {
            size_selector (c);
            c.add_separator ();
            grading = c.add_selector (_("Grade Sizes"), 15, "atelier-grading-symbolic");
            grading.label = _("Grade Sizes");
            grading.add_option ("measurements", _("By Measurements"));
            grading.add_option ("rules", _("By Rules"));
            grading.changed.connect ((id) => {
                if (!syncing && panel != null) panel.set_grading (id);
            });
            button (c, "view-refresh-symbolic", _("Derive Rules"), _("Compute a Rule Table that Reproduces the Current Grading"), true, () => {
                if (panel != null) panel.derive_rules ();
            });
            button (c, "x-office-spreadsheet-symbolic", _("Rule Table"), _("Increments per Size Break for Every Rule"), true, () => {
                if (panel != null) panel.edit_rules ();
            });
            foreach (var prov in PluginHost.get_default ().rule_providers) {
                var provider = prov;
                button (c, "application-x-addon-symbolic", provider.title, _("Grade Rules from a Plugin"), false, () => {
                    if (panel != null) panel.apply_rule_provider (provider);
                });
            }
            c.add_separator ();
            anchor = c.add_selector (_("Stack Sizes On"), 16, "atelier-nesting-symbolic");
            anchor.label = _("Stack Sizes On");
            anchor.add_option ("grain", _("On Grain Line"));
            anchor.add_option ("corner", _("On Top Left Corner"));
            anchor.add_option ("center", _("On Centre"));
            anchor.changed.connect ((id) => {
                if (!syncing && panel != null) panel.set_stack_anchor (id);
            });
        }

        private void build_marker (RibbonContext c) {
            button (c, "atelier-marker-layout-symbolic", _("Lay Out"), _("Lay Out the Pieces on the Fabric"), true, () => {
                if (panel != null) panel.lay_out ();
            });
            button (c, "atelier-fill-symbolic", _("Consumption"), _("Set the Consumption of the Main Fabric in the Bill of Materials"), true, () => {
                if (panel != null) panel.apply_consumption ();
            });
            c.add_separator ();
            button (c, "printer-symbolic", _("Plotter File"), _("Export for Plotter (HPGL)"), true, () => win.activate_action ("export", new Variant.string ("hpgl")));
            button (c, "x-office-document-symbolic", _("Large PDF"), _("Export Large Format PDF"), true, () => win.activate_action ("export", new Variant.string ("pdf-large")));
        }

        private void sync_sizes () {
            var p = pattern;
            if (p == null) return;
            syncing = true;
            var sizes = p.all_sizes ();
            string active = sizes.contains (p.active_size) ? p.active_size : (sizes.size > 0 ? sizes[0] : "");
            foreach (var sel in size_selectors) {
                sel.clear_options ();
                foreach (var s in sizes) sel.add_option (s, _("Size %s").printf (s));
                sel.selected = active;
            }
            syncing = false;
        }

        public void sync () {
            var p = pattern;
            if (p == null) return;
            sync_sizes ();
            syncing = true;
            units.selected = p.unit;
            grading.selected = p.grading == "rules" ? "rules" : "measurements";
            if (win.pattern_canvas != null) anchor.selected = win.pattern_canvas.nest_anchor;
            syncing = false;
        }
    }
}
