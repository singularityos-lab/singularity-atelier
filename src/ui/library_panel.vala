using Gtk;
using Singularity.Widgets;
using Singularity.Assets;

namespace Singularity.Apps.Atelier {

    public class LibraryPage : Box {
        private string kind;
        private PreferencesGroup group;
        private Singularity.Widgets.SearchEntry search;
        private Box empty_box;

        public LibraryPage (string kind) {
            Object (orientation: Orientation.VERTICAL, spacing: 12);
            this.kind = kind;
            string title = kind == "fabric" ? _("Fabrics") : (kind == "trim" ? _("Trims") : _("Colours"));
            group = new PreferencesGroup (title, _("Shared with the other creative apps through the asset library."));
            Dialogs.header_button (group, _("Add"), () => edit (null));
            search = new Singularity.Widgets.SearchEntry ();
            search.placeholder_text = _("Search %s").printf (title.down ());
            search.search_changed.connect (() => fill ());
            append (search);
            append (group);
            empty_box = new Box (Orientation.VERTICAL, 0);
            empty_box.vexpand = true;
            append (empty_box);
            AssetLibrary.get_default ().changed.connect (() => fill ());
            fill ();
        }

        private void fill () {
            group.clear ();
            Dialogs.clear (empty_box);
            var items = AssetLibrary.get_default ().list (kind, search.text);
            search.visible = items.size > 0 || search.text != "";
            group.visible = items.size > 0 || search.text != "";
            if (items.size == 0) {
                group.visible = false;
                if (search.text != "") {
                    var st = new StatusPage ();
                    st.icon_name = "system-search";
                    st.title = _("No Matches");
                    st.description = _("Try another search.");
                    var clear = new Button.with_label (_("Clear Search"));
                    clear.halign = Align.CENTER;
                    clear.clicked.connect (() => search.text = "");
                    st.child = clear;
                    empty_box.append (st);
                    return;
                }
                string title = kind == "fabric" ? _("Fabrics") : (kind == "trim" ? _("Trims") : _("Colours"));
                var wp = new WelcomePage ();
                wp.is_section = true;
                wp.embedded = true;
                wp.app_icon_name = "dev.sinty.atelier";
                wp.title = title;
                wp.subtitle = kind == "fabric" ? _("No fabrics in the library yet. Add them once and use them in every project.") : (kind == "trim" ? _("No trims in the library yet. Add buttons, zips and labels once and reuse them.") : _("No colours in the library yet. Add them by hand or import a palette."));
                wp.add_action ("document-new", kind == "fabric" ? _("Add a Fabric") : (kind == "trim" ? _("Add a Trim") : _("Add a Colour")), kind == "color" ? _("Name, colour, code and colour book") : _("Name, colour, code and supplier"), () => edit (null));
                if (kind == "color") wp.add_action ("x-office-drawing", _("Import a Palette"), _("GIMP palettes and Adobe swatch exchange files"), () => {
                    var w = get_root () as AtelierWindow;
                    if (w != null) w.import ("palette");
                });
                empty_box.append (wp);
                return;
            }
            foreach (var a in items) {
                var asset = a;
                string sub;
                if (a.kind == "fabric") {
                    string wt = a.get_field ("weight") != "" ? a.get_field ("weight") + " g/m²" : "";
                    sub = a.get_field ("composition") + " " + wt;
                } else {
                    sub = a.get_field ("code") + " " + a.get_field ("supplier");
                }
                var row = new ActionRow (a.name, sub.strip () != "" ? sub.strip () : null);
                var sw = new DrawingArea ();
                sw.set_size_request (28, 28);
                sw.valign = Align.CENTER;
                sw.margin_end = 10;
                sw.set_draw_func ((d, cr, w, h) => {
                    cr.arc (w / 2.0, h / 2.0, 12, 0, 2 * Math.PI);
                    Rgba.parse (asset.get_field ("color", "#b8b8b8")).apply (cr);
                    cr.fill_preserve ();
                    cr.set_source_rgba (0.5, 0.5, 0.5, 0.35);
                    cr.set_line_width (1);
                    cr.stroke ();
                    if (asset.kind == "trim") {
                        Trims.draw (cr, asset.get_field ("trim", "button"), w / 2.0, h / 2.0, 16, 0, Rgba (0.95, 0.95, 0.95), Rgba (0.1, 0.1, 0.1));
                    }
                });
                row.add_prefix (sw);
                var more = new Button.from_icon_name ("document-edit-symbolic");
                more.add_css_class ("flat");
                more.valign = Align.CENTER;
                more.tooltip_text = _("Edit");
                more.clicked.connect (() => edit (asset));
                row.add_suffix (more);
                var drag = new DragSource ();
                drag.actions = Gdk.DragAction.COPY;
                drag.prepare.connect ((x, y) => new Gdk.ContentProvider.for_value (AssetLibrary.drag_text (asset)));
                row.add_controller (drag);
                group.add_row (row);
            }
        }

        private void edit (Asset? existing) {
            var win = get_root () as Gtk.Window;
            if (win == null) return;
            var a = existing != null ? existing.copy () : new Asset ();
            if (existing == null) {
                a.kind = kind;
                a.app = "dev.sinty.atelier";
            }
            Box body;
            var entries = new Gee.HashMap<string, Entry> ();
            ColorPickerButton? color = null;
            Choice? weave = null, trim = null, physics = null;
            string[] weaves = { "plain", "twill", "check", "stripe" };
            var presets = FabricPreset.all ();
            string dtitle = _("Add to Library");
            if (existing != null) dtitle = _("Edit %s").printf (a.name);
            string daction = existing != null ? _("Save") : _("Add");
            var dlg = Dialogs.form (win, dtitle, daction, out body, () => {
                foreach (var e in entries.entries) {
                    if (e.key == "name") a.name = e.value.text.strip ();
                    else a.set_field (e.key, e.value.text.strip ());
                }
                if (color != null) a.set_field ("color", Dialogs.from_gdk (color.color).to_hex ());
                if (weave != null) a.set_field ("weave", weaves[weave.selected]);
                if (trim != null) a.set_field ("trim", Trims.KINDS[trim.selected]);
                if (physics != null) a.set_field ("physics", presets[(int) physics.selected].id);
                if (a.name == "") a.name = _("Unnamed");
                try {
                    if (existing != null) AssetLibrary.get_default ().update (a);
                    else AssetLibrary.get_default ().add (a);
                } catch (Error e) {
                    warning ("library: %s", e.message);
                }
            });
            var g = new PreferencesGroup (a.kind == "fabric" ? _("Fabric") : (a.kind == "trim" ? _("Trim") : _("Colour")));
            entries["name"] = Dialogs.entry_row (g, _("Name"), a.name);
            color = new ColorPickerButton (Dialogs.to_gdk (Rgba.parse (a.get_field ("color", "#b8b8b8"))));
            color.valign = Align.CENTER;
            var crow = new ActionRow (_("Colour"));
            crow.add_suffix (color);
            g.add_row (crow);
            entries["code"] = Dialogs.entry_row (g, _("Code"), a.get_field ("code"));
            if (a.kind == "fabric") {
                entries["composition"] = Dialogs.entry_row (g, _("Composition"), a.get_field ("composition"), _("For example 100% cotton"));
                entries["weight"] = Dialogs.entry_row (g, _("Weight"), a.get_field ("weight"), _("Grams per square metre"));
                entries["width"] = Dialogs.entry_row (g, _("Width"), a.get_field ("width"), _("Centimetres"));
                entries["price"] = Dialogs.entry_row (g, _("Price per Metre"), a.get_field ("price"));
                entries["supplier"] = Dialogs.entry_row (g, _("Supplier"), a.get_field ("supplier"));
                entries["image"] = Dialogs.entry_row (g, _("Swatch Image"), a.get_field ("image"), _("Path of a repeating image"));
                int ws = 0;
                for (int i = 0; i < weaves.length; i++) if (weaves[i] == a.get_field ("weave", "plain")) ws = i;
                weave = Dialogs.choice_row (g, _("Weave"), { _("Plain"), _("Twill"), _("Check"), _("Stripe") }, ws);
                string[] pl = {};
                int psel = 0;
                for (int i = 0; i < presets.size; i++) {
                    pl += presets[i].name;
                    if (presets[i].id == a.get_field ("physics", "cotton")) psel = i;
                }
                physics = Dialogs.choice_row (g, _("Behaves Like"), pl, psel);
            } else if (a.kind == "trim") {
                int ts = 0;
                string[] tl = {};
                for (int i = 0; i < Trims.KINDS.length; i++) {
                    tl += Trims.label (Trims.KINDS[i]);
                    if (Trims.KINDS[i] == a.get_field ("trim", "button")) ts = i;
                }
                trim = Dialogs.choice_row (g, _("Kind"), tl, ts);
                entries["size"] = Dialogs.entry_row (g, _("Size"), a.get_field ("size", "10"), _("Millimetres on the drawing"));
                entries["cost"] = Dialogs.entry_row (g, _("Unit Cost"), a.get_field ("cost"));
                entries["supplier"] = Dialogs.entry_row (g, _("Supplier"), a.get_field ("supplier"));
            } else {
                entries["book"] = Dialogs.entry_row (g, _("Colour Book"), a.get_field ("book"));
            }
            body.append (g);
            if (existing != null) {
                var dg = new PreferencesGroup (_("Library"));
                var del = new ConfirmRow (_("Remove from Library"), _("Projects that use it keep their copy"));
                del.confirm_label = _("Remove");
                del.confirmed.connect (() => {
                    try {
                        AssetLibrary.get_default ().remove (existing.id);
                    } catch (Error e) {
                    }
                    ((AppDialog) dlg).close_dialog ();
                });
                dg.add_row (del);
                body.append (dg);
            }
            dlg.present ();
        }
    }
}
