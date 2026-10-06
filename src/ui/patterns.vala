using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Atelier {

    public class ToolPalette : Box {
        public signal void tool_selected (string id);

        private Gee.HashMap<string, ToggleButton> buttons = new Gee.HashMap<string, ToggleButton> ();
        private string active = "";

        public ToolPalette () {
            Object (orientation: Orientation.VERTICAL, spacing: 2);
            add_css_class ("sx-tool-palette");
            halign = Align.START;
            valign = Align.CENTER;
            margin_start = 10;
        }

        public ToggleButton add_tool (string id, string icon_name, string label) {
            var b = new ToggleButton ();
            b.icon_name = icon_name;
            b.add_css_class ("flat");
            b.add_css_class ("sx-tool");
            b.tooltip_text = label;
            b.update_property (AccessibleProperty.LABEL, label, -1);
            b.toggled.connect (() => {
                if (b.active && active != id) {
                    active = id;
                    sync ();
                    tool_selected (id);
                } else if (!b.active && active == id) {
                    b.active = true;
                }
            });
            buttons[id] = b;
            append (b);
            return b;
        }

        public void set_active (string id) {
            active = id;
            sync ();
        }

        private void sync () {
            foreach (var e in buttons.entries) {
                bool on = e.key == active;
                if (e.value.active != on) e.value.active = on;
            }
        }
    }

    public class ControlStrip : Box {

        public ControlStrip (int top = 4, int bottom = 4) {
            Object (orientation: Orientation.HORIZONTAL, spacing: 6);
            add_css_class ("sx-control-strip");
            margin_start = 10;
            margin_end = 10;
            margin_top = top;
            margin_bottom = bottom;
        }

        public Button add_icon_button (string icon_name, string tooltip) {
            var b = new Button.from_icon_name (icon_name);
            b.tooltip_text = tooltip;
            b.add_css_class ("flat");
            append (b);
            return b;
        }

        public Button add_text_button (string label, string? tooltip = null) {
            var b = new Button.with_label (label);
            b.add_css_class ("flat");
            if (tooltip != null) b.tooltip_text = tooltip;
            append (b);
            return b;
        }

        public Label add_numeric_label () {
            var l = new Label ("");
            l.add_css_class ("numeric");
            append (l);
            return l;
        }

        public Label add_status_label () {
            var l = new Label ("");
            l.add_css_class ("dim-label");
            l.xalign = 0;
            l.hexpand = true;
            l.ellipsize = Pango.EllipsizeMode.END;
            append (l);
            return l;
        }

        public void add_spacer () {
            var spacer = new Box (Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            append (spacer);
        }
    }

    public class InspectorPanel : Box {

        public InspectorPanel () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class ("sx-inspector");
            margin_bottom = 12;
            margin_end = 6;
        }
    }

    public class LayerItem : Object {
        public string id;
        public string name;
        public string subtitle = "";
        public int depth;
        public bool visible = true;
        public bool locked;
        public bool expandable;
        public bool expanded = true;
        public bool active;

        public LayerItem (string id, string name) {
            this.id = id;
            this.name = name;
        }
    }

    public class LayerList : Box {
        public signal void selected (string id);
        public signal void visibility_changed (string id, bool visible);
        public signal void lock_changed (string id, bool locked);
        public signal void renamed (string id, string name);
        public signal void expanded_changed (string id, bool expanded);
        public signal void moved (string id, string target_id);
        public signal void options (string id, Widget anchor);
        public signal void add_requested (Widget anchor);
        public signal void duplicate_requested (string id);
        public signal void delete_requested (string id);
        public signal void raise_requested (string id);
        public signal void lower_requested (string id);

        private ListBox list;
        private Gee.HashMap<ListBoxRow, LayerItem> rows = new Gee.HashMap<ListBoxRow, LayerItem> ();
        private string active_id = "";
        private ControlStrip bar;
        private Button dup;
        private Button del;
        private Button up;
        private Button down;

        public LayerList () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class ("sx-layer-list");
            list = new ListBox ();
            list.selection_mode = SelectionMode.SINGLE;
            list.add_css_class ("sx-layer-rows");
            list.row_selected.connect ((r) => {
                if (r == null || !rows.has_key (r)) return;
                var it = rows[r];
                if (it.id == active_id) return;
                active_id = it.id;
                sync_bar ();
                selected (it.id);
            });
            append (list);
            bar = new ControlStrip (4, 4);
            bar.margin_start = 6;
            bar.margin_end = 6;
            var add = bar.add_icon_button ("list-add-symbolic", _("Add a Layer, a Group or a Template"));
            add.clicked.connect (() => add_requested (add));
            dup = bar.add_icon_button ("edit-copy-symbolic", _("Duplicate Layer"));
            dup.clicked.connect (() => duplicate_requested (active_id));
            bar.add_spacer ();
            up = bar.add_icon_button ("go-up-symbolic", _("Move Layer Up"));
            up.clicked.connect (() => raise_requested (active_id));
            down = bar.add_icon_button ("go-down-symbolic", _("Move Layer Down"));
            down.clicked.connect (() => lower_requested (active_id));
            del = bar.add_icon_button ("user-trash-symbolic", _("Delete Layer"));
            del.clicked.connect (() => delete_requested (active_id));
            append (bar);
        }

        public void set_items (Gee.List<LayerItem> items) {
            Widget? c;
            while ((c = list.get_first_child ()) != null) list.remove (c);
            rows.clear ();
            active_id = "";
            bool hidden_depth = false;
            foreach (var it in items) {
                if (it.depth == 0) hidden_depth = it.expandable && !it.expanded;
                else if (hidden_depth) continue;
                var row = make_row (it);
                rows[row] = it;
                list.append (row);
                if (it.active) {
                    active_id = it.id;
                    list.select_row (row);
                }
            }
            sync_bar ();
        }

        private void sync_bar () {
            bool any = active_id != "";
            dup.sensitive = any;
            del.sensitive = any;
            up.sensitive = any;
            down.sensitive = any;
        }

        private ListBoxRow make_row (LayerItem it) {
            var row = new ListBoxRow ();
            row.add_css_class ("sx-layer-row");
            var box = new Box (Orientation.HORIZONTAL, 2);
            box.margin_start = 4 + it.depth * 20;
            box.margin_end = 4;
            box.margin_top = 2;
            box.margin_bottom = 2;
            if (it.expandable) {
                var exp = new Button.from_icon_name (it.expanded ? "pan-down-symbolic" : "pan-end-symbolic");
                exp.add_css_class ("flat");
                exp.add_css_class ("sx-layer-toggle");
                exp.valign = Align.CENTER;
                exp.tooltip_text = it.expanded ? _("Collapse") : _("Expand");
                exp.clicked.connect (() => expanded_changed (it.id, !it.expanded));
                box.append (exp);
            }
            var vis = new ToggleButton ();
            vis.icon_name = it.visible ? "view-reveal-symbolic" : "view-conceal-symbolic";
            vis.add_css_class ("flat");
            vis.add_css_class ("sx-layer-toggle");
            vis.valign = Align.CENTER;
            vis.active = !it.visible;
            vis.tooltip_text = it.visible ? _("Hide") : _("Show");
            vis.toggled.connect (() => {
                vis.icon_name = vis.active ? "view-conceal-symbolic" : "view-reveal-symbolic";
                vis.tooltip_text = vis.active ? _("Show") : _("Hide");
                visibility_changed (it.id, !vis.active);
            });
            box.append (vis);
            var lock_btn = new ToggleButton ();
            lock_btn.icon_name = it.locked ? "changes-prevent-symbolic" : "changes-allow-symbolic";
            lock_btn.add_css_class ("flat");
            lock_btn.add_css_class ("sx-layer-toggle");
            lock_btn.valign = Align.CENTER;
            lock_btn.active = it.locked;
            lock_btn.tooltip_text = it.locked ? _("Unlock") : _("Lock");
            lock_btn.toggled.connect (() => {
                lock_btn.icon_name = lock_btn.active ? "changes-prevent-symbolic" : "changes-allow-symbolic";
                lock_btn.tooltip_text = lock_btn.active ? _("Unlock") : _("Lock");
                lock_changed (it.id, lock_btn.active);
            });
            box.append (lock_btn);
            var texts = new Box (Orientation.VERTICAL, 0);
            texts.hexpand = true;
            texts.valign = Align.CENTER;
            texts.margin_start = 6;
            var name = new EditableLabel (it.name);
            name.add_css_class ("sx-layer-name");
            name.editable = false;
            var dbl = new GestureClick ();
            dbl.pressed.connect ((n, x, y) => {
                if (n == 2) {
                    name.editable = true;
                    name.start_editing ();
                }
            });
            name.add_controller (dbl);
            name.notify["editing"].connect (() => {
                if (name.editing) return;
                name.editable = false;
                string t = name.text.strip ();
                if (t != "" && t != it.name) renamed (it.id, t);
            });
            texts.append (name);
            if (it.subtitle != "") {
                var sub = new Label (it.subtitle);
                sub.add_css_class ("caption");
                sub.add_css_class ("dim-label");
                sub.xalign = 0;
                sub.ellipsize = Pango.EllipsizeMode.END;
                texts.append (sub);
            }
            box.append (texts);
            var more = new Button.from_icon_name ("view-more-symbolic");
            more.add_css_class ("flat");
            more.add_css_class ("sx-layer-toggle");
            more.valign = Align.CENTER;
            more.tooltip_text = _("Layer Options");
            more.clicked.connect (() => options (it.id, more));
            box.append (more);
            row.child = box;
            var drag = new DragSource ();
            drag.actions = Gdk.DragAction.MOVE;
            drag.prepare.connect ((x, y) => new Gdk.ContentProvider.for_value ("atelier-layer:" + it.id));
            row.add_controller (drag);
            var drop = new DropTarget (typeof (string), Gdk.DragAction.MOVE);
            drop.drop.connect ((val, x, y) => {
                string s = (string) val;
                if (!s.has_prefix ("atelier-layer:")) return false;
                string src = s.substring (14);
                if (src == it.id) return false;
                moved (src, it.id);
                return true;
            });
            row.add_controller (drop);
            return row;
        }
    }
}
