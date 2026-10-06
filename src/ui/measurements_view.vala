using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class MeasurementsView : AppDialog {
        private AtelierWindow win;
        private Project project;
        private History history;
        private Grid grid;
        private bool changed_any;
        public signal void closed ();

        public MeasurementsView (AtelierWindow win, Project project, History history) {
            base (win.application, true, false);
            this.win = win;
            this.project = project;
            this.history = history;
            set_title (_("Measurements"));
            transient_for = win;
            set_default_size (980, 640);
            history.checkpoint ();
            var t = table ();
            var body = new Box (Orientation.VERTICAL, 12);
            body.margin_start = 18;
            body.margin_end = 18;
            body.vexpand = true;
            var tg = new PreferencesGroup (_("Table"));
            var name = Dialogs.entry_row (tg, _("Name"), t.name);
            name.changed.connect (() => t.name = name.text);
            var unit = Dialogs.choice_row (tg, _("Units"), { _("Centimetres"), _("Millimetres"), _("Inches") }, t.unit == "mm" ? 1 : (t.unit == "inch" ? 2 : 0));
            unit.notify["selected"].connect (() => {
                t.unit = unit.selected == 1 ? "mm" : (unit.selected == 2 ? "inch" : "cm");
                changed_any = true;
            });
            var std = Dialogs.header_button (tg, _("Standard Table"), () => { });
            std.clicked.connect (() => {
                var m = new ContextMenu (std);
                m.add_item (_("Women EU 34 to 46"), null, () => replace (MeasurementTable.standard_women ()));
                m.add_item (_("Men EU 44 to 56"), null, () => replace (MeasurementTable.standard_men ()));
                Dialogs.popup (m);
            });
            body.append (tg);
            var mg = new PreferencesGroup (_("Measurements"), _("Values in the table units. A formula overrides the values and can use other measurements. Click a size to make it the base size."));
            mg.vexpand = true;
            Dialogs.header_button (mg, _("Add Size"), () => add_size ());
            Dialogs.header_button (mg, _("Add Measurement"), () => {
                int n = t.items.size + 1;
                while (t.find ("m%d".printf (n)) != null) n++;
                t.items.add (new Measurement ("m%d".printf (n), 0));
                changed_any = true;
                fill ();
            });
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hexpand = true;
            scroll.min_content_height = 340;
            scroll.overlay_scrolling = false;
            grid = new Grid ();
            grid.row_spacing = 2;
            grid.column_spacing = 4;
            grid.margin_start = 12;
            grid.margin_end = 12;
            grid.margin_top = 8;
            grid.margin_bottom = 12;
            scroll.child = grid;
            mg.add_row (scroll);
            body.append (mg);
            content_box.append (body);
            var bottom = new Box (Orientation.HORIZONTAL, 8);
            bottom.margin_start = 18;
            bottom.margin_end = 18;
            bottom.margin_top = 8;
            bottom.margin_bottom = 18;
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            bottom.append (spacer);
            var export_csv = new Button.with_label (_("Export…"));
            export_csv.clicked.connect (() => export_table ());
            bottom.append (export_csv);
            var done = new Button.with_label (_("Done"));
            done.add_css_class ("suggested-action");
            done.clicked.connect (() => close_dialog ());
            set_cancel_button (done);
            bottom.append (done);
            content_box.append (bottom);
            fill ();
        }

        public override void close_dialog () {
            if (changed_any) project.touch ("measurements");
            closed ();
            base.close_dialog ();
        }

        private MeasurementTable table () {
            return project.pattern.table;
        }

        private void replace (MeasurementTable t) {
            project.pattern.table = t;
            project.pattern.active_size = t.base_size;
            changed_any = true;
            fill ();
        }

        private void add_size () {
            Box body;
            Entry? e = null;
            var dlg = Dialogs.form (win, _("Add Size"), _("Add"), out body, () => {
                string s = e.text.strip ();
                var t = table ();
                if (s == "" || t.sizes.contains (s)) return;
                double v = 0, last = 0;
                if (t.sizes.size > 0 && double.try_parse (s, out v) && double.try_parse (t.sizes[t.sizes.size - 1], out last) && v < last) {
                    int i = 0;
                    while (i < t.sizes.size && double.try_parse (t.sizes[i], out last) && last < v) i++;
                    t.sizes.insert (i, s);
                } else {
                    t.sizes.add (s);
                }
                if (t.base_size == "" || t.base_size == "base") t.base_size = s;
                t.sizes.remove ("base");
                t.kind = TableKind.MULTISIZE;
                changed_any = true;
                fill ();
            });
            var g = new PreferencesGroup (_("Size"));
            e = Dialogs.entry_row (g, _("Name"), "", _("For example 40 or M"));
            body.append (g);
            dlg.present ();
        }

        private Label head (string text) {
            var l = new Label (text);
            l.add_css_class ("heading");
            l.halign = Align.START;
            l.margin_top = 6;
            l.margin_bottom = 4;
            return l;
        }

        private void fill () {
            Widget? c;
            while ((c = grid.get_first_child ()) != null) grid.remove (c);
            var t = table ();
            grid.attach (head (_("Name")), 0, 0);
            grid.attach (head (_("Description")), 1, 0);
            for (int i = 0; i < t.sizes.size; i++) {
                string s = t.sizes[i];
                string hl = s;
                if (s == t.base_size) hl = _("%s base").printf (s);
                var hb = new Button.with_label (hl);
                hb.add_css_class ("flat");
                hb.tooltip_text = _("Make this the base size");
                hb.clicked.connect (() => {
                    t.base_size = s;
                    project.pattern.active_size = s;
                    changed_any = true;
                    fill ();
                });
                grid.attach (hb, 2 + i, 0);
            }
            int fcol = 2 + t.sizes.size;
            grid.attach (head (_("Step")), fcol, 0);
            grid.attach (head (_("Formula")), fcol + 1, 0);
            int row = 1;
            foreach (var m in t.items) {
                var mm = m;
                var name = new Entry ();
                name.text = m.name;
                name.width_chars = 16;
                name.changed.connect (() => {
                    string n = name.text.strip ().replace (" ", "_");
                    if (n != "" && (t.find (n) == null || t.find (n) == mm)) {
                        mm.name = n;
                        changed_any = true;
                    }
                });
                grid.attach (name, 0, row);
                var full = new Entry ();
                full.text = m.full_name;
                full.width_chars = 20;
                full.changed.connect (() => mm.full_name = full.text);
                grid.attach (full, 1, row);
                for (int i = 0; i < t.sizes.size; i++) {
                    string s = t.sizes[i];
                    var e = new Entry ();
                    e.width_chars = 6;
                    e.xalign = 1;
                    e.add_css_class ("atelier-value");
                    double v = 0;
                    try {
                        v = t.value (m.name, s);
                    } catch (ExprError err) {
                    }
                    e.text = PathData.fmt (v, 2);
                    bool explicit_value = m.per_size.has_key (s);
                    if (!explicit_value) e.add_css_class ("dim-label");
                    e.sensitive = m.formula == "";
                    e.changed.connect (() => {
                        double nv;
                        if (!double.try_parse (e.text.strip ().replace (",", "."), out nv)) return;
                        if (s == t.base_size) mm.base_value = nv;
                        mm.per_size[s] = nv;
                        e.remove_css_class ("dim-label");
                        changed_any = true;
                    });
                    grid.attach (e, 2 + i, row);
                }
                var step = new Entry ();
                step.width_chars = 5;
                step.xalign = 1;
                step.text = PathData.fmt (m.size_step, 2);
                step.tooltip_text = _("Change per size for sizes without their own value");
                step.changed.connect (() => {
                    double nv;
                    if (double.try_parse (step.text.strip ().replace (",", "."), out nv)) {
                        mm.size_step = nv;
                        changed_any = true;
                    }
                });
                grid.attach (step, fcol, row);
                var f = new Entry ();
                f.width_chars = 14;
                f.text = m.formula;
                f.changed.connect (() => {
                    mm.formula = f.text.strip ();
                    changed_any = true;
                });
                grid.attach (f, fcol + 1, row);
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.tooltip_text = _("Remove");
                del.clicked.connect (() => {
                    t.items.remove (mm);
                    changed_any = true;
                    fill ();
                });
                grid.attach (del, fcol + 2, row);
                row++;
            }
        }

        private void export_table () {
            Dialogs.save.begin (win, _("Export Measurements"), (table ().name != "" ? table ().name : _("Measurements")) + ".csv", _("Tables"), { "csv", "xlsx", "smis", "smms" }, (o, r) => {
                var f = Dialogs.save.end (r);
                if (f == null) return;
                string path = f.get_path ();
                try {
                    string lower = path.down ();
                    if (lower.has_suffix (".xlsx")) {
                        var sheets = new Gee.ArrayList<Sheet> ();
                        sheets.add (Tables.measurements_sheet (table ()));
                        FileUtils.set_data (path, Tables.xlsx (sheets));
                    } else if (lower.has_suffix (".smis") || lower.has_suffix (".smms")) {
                        FileUtils.set_contents (path, Seamly.write_measurements (table ()));
                    } else {
                        FileUtils.set_contents (Dialogs.ensure_suffix (path, "csv"), Tables.measurements_csv (table ()));
                    }
                } catch (Error e) {
                    win.show_error (_("Could Not Export"), e.message);
                }
            });
        }

        public static MeasurementTable read_table_file (string path) throws Error {
            string lower = path.down ();
            if (lower.has_suffix (".csv")) {
                string text;
                FileUtils.get_contents (path, out text);
                return Tables.measurements_from_rows (Tables.parse_csv (text));
            }
            if (lower.has_suffix (".xlsx")) {
                uint8[] data;
                FileUtils.get_data (path, out data);
                return Tables.measurements_from_rows (Tables.read_xlsx (data));
            }
            string xml;
            FileUtils.get_contents (path, out xml);
            return Seamly.read_measurements (xml);
        }
    }
}
