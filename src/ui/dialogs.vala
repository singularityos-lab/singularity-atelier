using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Atelier {

    public class Dialogs {
        public static GLib.ListStore filters (string name, string[] suffixes) {
            var store = new GLib.ListStore (typeof (FileFilter));
            var f = new FileFilter ();
            f.name = name;
            foreach (var s in suffixes) f.add_suffix (s);
            store.append (f);
            return store;
        }

        public static async File? save (Gtk.Window parent, string title, string suggested, string filter_name, string[] suffixes) {
            var d = new FileDialog ();
            d.title = title;
            d.initial_name = suggested;
            d.filters = filters (filter_name, suffixes);
            try {
                return yield d.save (parent, null);
            } catch (Error e) {
                return null;
            }
        }

        public static async File? open (Gtk.Window parent, string title, string filter_name, string[] suffixes) {
            var d = new FileDialog ();
            d.title = title;
            d.filters = filters (filter_name, suffixes);
            try {
                return yield d.open (parent, null);
            } catch (Error e) {
                return null;
            }
        }

        public static async File? folder (Gtk.Window parent, string title) {
            var d = new FileDialog ();
            d.title = title;
            try {
                return yield d.select_folder (parent, null);
            } catch (Error e) {
                return null;
            }
        }

        public static string ensure_suffix (string path, string suffix) {
            return path.down ().has_suffix ("." + suffix) ? path : path + "." + suffix;
        }

        public static void confirm (Gtk.Window parent, string title, string body, string action, owned ConfirmedFunc done, bool destructive = true) {
            var app = parent.application;
            var dlg = new ConfirmDialog (app, title, null, body, action, destructive ? ConfirmDialog.ActionStyle.DESTRUCTIVE : ConfirmDialog.ActionStyle.SUGGESTED);
            dlg.transient_for = parent;
            dlg.response.connect ((r) => {
                if (r == ConfirmDialog.Response.PRIMARY) done ();
            });
            dlg.present ();
        }

        public delegate void ConfirmedFunc ();

        public static AppDialog form (Gtk.Window parent, string title, string action, out Box body, owned ConfirmedFunc done) {
            var dlg = new AppDialog (parent.application, true, false);
            dlg.set_title (title);
            dlg.transient_for = parent;
            dlg.set_default_size (440, -1);
            body = new Box (Orientation.VERTICAL, 12);
            body.margin_start = 18;
            body.margin_end = 18;
            body.margin_top = 6;
            body.margin_bottom = 12;
            dlg.content_box.append (body);
            var buttons = new Box (Orientation.HORIZONTAL, 8);
            buttons.halign = Align.END;
            buttons.margin_end = 18;
            buttons.margin_bottom = 18;
            buttons.append (dlg.add_cancel_button (_("Cancel")));
            var ok = new Button.with_label (action);
            ok.add_css_class ("suggested-action");
            ok.clicked.connect (() => {
                done ();
                dlg.close_dialog ();
            });
            buttons.append (ok);
            dlg.content_box.append (buttons);
            return dlg;
        }

        public static Entry entry_row (PreferencesGroup g, string title, string value, string? placeholder = null) {
            var row = new FieldRow (title);
            row.text = value;
            if (placeholder != null) row.field.placeholder_text = placeholder;
            g.add_row (row);
            return row.field;
        }

        public static SpinButton spin_row (PreferencesGroup g, string title, double min, double max, double step, double value, int digits = 1, string? subtitle = null) {
            var row = new SpinRow (title, subtitle, min, max, step, value);
            row.spin_btn.digits = digits;
            row.value = value;
            g.add_row (row);
            return row.spin_btn;
        }

        public static Choice choice_row (PreferencesGroup g, string title, string[] labels, int active) {
            var c = new Choice (title, labels, active);
            g.add_row (c.row);
            return c;
        }

        public static Switch switch_row (PreferencesGroup g, string title, bool active, string? subtitle = null) {
            var row = new SwitchRow (title, subtitle, active);
            g.add_row (row);
            return row.switch_btn;
        }

        public static Button header_button (PreferencesGroup g, string label, owned ConfirmedFunc action, bool suggested = false) {
            var b = new Button.with_label (label);
            b.valign = Align.CENTER;
            if (suggested) b.add_css_class ("suggested-action");
            b.clicked.connect (() => action ());
            g.add_header_suffix (b);
            return b;
        }

        public static ActionRow button_row (PreferencesGroup g, string title, string? subtitle, string label, owned ConfirmedFunc action) {
            var row = new ActionRow (title, subtitle);
            var b = new Button.with_label (label);
            b.valign = Align.CENTER;
            b.clicked.connect (() => action ());
            row.add_suffix (b);
            g.add_row (row);
            return row;
        }

        public static void popup (ContextMenu m) {
            m.closed.connect (() => Idle.add (() => {
                m.unparent ();
                return Source.REMOVE;
            }));
            m.popup ();
        }

        public static Button swatch (Rgba c, string tooltip) {
            var b = new Button ();
            b.add_css_class ("atelier-swatch");
            b.tooltip_text = tooltip;
            var area = new DrawingArea ();
            area.set_size_request (22, 22);
            var col = c;
            area.set_draw_func ((a, cr, w, h) => {
                cr.arc (w / 2.0, h / 2.0, double.min (w, h) / 2.0 - 1, 0, 2 * Math.PI);
                col.apply (cr);
                cr.fill ();
            });
            b.child = area;
            return b;
        }

        public static Gdk.RGBA to_gdk (Rgba c) {
            var g = Gdk.RGBA ();
            g.red = (float) c.r;
            g.green = (float) c.g;
            g.blue = (float) c.b;
            g.alpha = (float) c.a;
            return g;
        }

        public static Rgba from_gdk (Gdk.RGBA g) {
            return Rgba (g.red, g.green, g.blue, g.alpha);
        }

        public static void clear (Box box) {
            Widget? c;
            while ((c = box.get_first_child ()) != null) box.remove (c);
        }
    }

    public class FieldRow : EntryRow {
        public Entry field {
            get { return entry; }
        }

        public FieldRow (string title) {
            base (title);
        }
    }

    public class Choice : Object {
        public SelectionRow row { get; private set; }
        private string[] labels;
        private uint _selected;

        public uint selected {
            get { return _selected; }
            set {
                if (value >= labels.length) return;
                _selected = value;
                row.current_value = labels[value];
            }
        }

        public Choice (string title, string[] labels, int active) {
            this.labels = labels.length > 0 ? labels : new string[] { "" };
            _selected = (uint) active.clamp (0, this.labels.length - 1);
            row = new SelectionRow (title, this.labels, this.labels[_selected]);
            row.selected.connect ((item) => {
                for (uint i = 0; i < this.labels.length; i++) {
                    if (this.labels[i] != item) continue;
                    if (i != _selected) selected = i;
                    return;
                }
            });
        }

        public void set_labels (string[] labels, int active) {
            this.labels = labels.length > 0 ? labels : new string[] { "" };
            row.set_items (this.labels);
            _selected = (uint) active.clamp (0, this.labels.length - 1);
            row.current_value = this.labels[_selected];
        }
    }
}
