using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class TechPackView : Box {
        private Project project;
        private History history;
        private Box page;
        private ScrolledWindow scroll;
        private string current = "style";
        private Gee.HashMap<string, SidebarRow> nav_rows = new Gee.HashMap<string, SidebarRow> ();
        public Box nav { get; private set; }
        public signal void message (string text);

        public TechPackView (Project project, History history) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            this.project = project;
            this.history = history;
            hexpand = true;
            vexpand = true;
            nav = new Box (Orientation.VERTICAL, 2);
            nav.add_css_class ("sx-inspector");
            nav.append (new SidebarSectionLabel (_("Tech Pack")));
            nav_row ("style", "atelier-techpack-symbolic", _("Style"));
            nav_row ("poms", "atelier-measure-symbolic", _("Points of Measure"));
            nav_row ("bom", "atelier-trim-symbolic", _("Bill of Materials"));
            nav_row ("ops", "atelier-stitch-symbolic", _("Construction"));
            nav_row ("review", "document-open-recent-symbolic", _("Revisions and Comments"));
            nav.append (new SidebarSectionLabel (_("Library")));
            nav_row ("lib-fabric", "atelier-fill-symbolic", _("Fabrics"));
            nav_row ("lib-trim", "atelier-trim-symbolic", _("Trims"));
            nav_row ("lib-color", "atelier-colorway-symbolic", _("Colours"));
            scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;
            page = new Box (Orientation.VERTICAL, 12);
            page.margin_start = 24;
            page.margin_end = 24;
            page.margin_bottom = 24;
            apply_view_edge (page);
            scroll.child = page;
            append (scroll);
            refresh ();
        }

        private void nav_row (string id, string icon, string label) {
            var r = new SidebarRow (icon, label);
            r.clicked.connect (() => show_section (id));
            nav_rows[id] = r;
            nav.append (r);
        }

        private TechPack tp {
            get { return project.techpack; }
        }

        public void show_section (string name) {
            current = name;
            refresh ();
            scroll.vadjustment.value = 0;
        }

        public void refresh () {
            Dialogs.clear (page);
            var root = get_root () as Gtk.Window;
            if (root != null) root.set_focus (null);
            foreach (var e in nav_rows.entries) e.value.set_active (e.key == current);
            if (current.has_prefix ("lib-")) {
                page.append (new LibraryPage (current.substring (4)));
                return;
            }
            switch (current) {
                case "poms": build_poms (); break;
                case "bom": build_bom (); break;
                case "ops": build_ops (); break;
                case "review": build_review (); break;
                default: build_style (); break;
            }
        }

        private Entry cell (string text, int chars, owned SetText setter, bool numeric = false) {
            var e = new Entry ();
            e.text = text;
            e.width_chars = chars;
            if (numeric) {
                e.xalign = 1;
                e.add_css_class ("atelier-value");
            }
            e.changed.connect (() => {
                setter (e.text);
                project.modified = true;
            });
            var focus = new EventControllerFocus ();
            focus.enter.connect (() => history.checkpoint ());
            e.add_controller (focus);
            return e;
        }

        private delegate void SetText (string t);

        private static double num (string t) {
            double v;
            return double.try_parse (t.strip ().replace (",", "."), out v) ? v : 0;
        }

        private Label head (string text) {
            var l = new Label (text);
            l.add_css_class ("heading");
            l.halign = Align.START;
            return l;
        }

        private Widget table (Grid grid) {
            grid.margin_start = 12;
            grid.margin_end = 12;
            grid.margin_top = 10;
            grid.margin_bottom = 12;
            var sc = new ScrolledWindow ();
            sc.vscrollbar_policy = PolicyType.NEVER;
            sc.hscrollbar_policy = PolicyType.AUTOMATIC;
            sc.overlay_scrolling = false;
            sc.child = grid;
            return sc;
        }

        private void build_style () {
            var g = new PreferencesGroup (_("Style"));
            var t = tp;
            string[] labels = { _("Style Name"), _("Style Number"), _("Season"), _("Brand"), _("Designer"), _("Category") };
            string[] values = { t.style_name, t.style_number, t.season, t.brand, t.designer, t.category };
            for (int i = 0; i < labels.length; i++) {
                int idx = i;
                var e = Dialogs.entry_row (g, labels[i], values[i]);
                e.changed.connect (() => {
                    switch (idx) {
                        case 0: t.style_name = e.text; break;
                        case 1: t.style_number = e.text; break;
                        case 2: t.season = e.text; break;
                        case 3: t.brand = e.text; break;
                        case 4: t.designer = e.text; break;
                        default: t.category = e.text; break;
                    }
                    project.modified = true;
                });
            }
            string[] statuses = { "Development", "Proto", "Sample", "Approved", "Production" };
            string[] sl = { _("Development"), _("Prototype"), _("Sample"), _("Approved"), _("Production") };
            int ss = 0;
            for (int i = 0; i < statuses.length; i++) if (statuses[i] == t.status) ss = i;
            var st = Dialogs.choice_row (g, _("Status"), sl, ss);
            st.notify["selected"].connect (() => {
                t.status = statuses[st.selected];
                project.modified = true;
            });
            page.append (g);
            var ng = new PreferencesGroup (_("Notes"));
            var tv = new TextView ();
            tv.add_css_class ("atelier-notes");
            tv.wrap_mode = WrapMode.WORD_CHAR;
            tv.buffer.text = t.notes;
            tv.top_margin = 8;
            tv.bottom_margin = 8;
            tv.left_margin = 10;
            tv.right_margin = 10;
            tv.set_size_request (-1, 110);
            tv.buffer.changed.connect (() => {
                t.notes = tv.buffer.text;
                project.modified = true;
            });
            ng.add_row (tv);
            page.append (ng);
            var cost = new PreferencesGroup (_("Totals"));
            cost.add_row (new ActionRow (_("Materials Cost"), "%s %s".printf (PathData.fmt (t.total_cost (), 2), t.bom.size > 0 ? t.bom[0].currency : "")));
            cost.add_row (new ActionRow (_("Standard Minutes"), PathData.fmt (t.total_minutes (), 2)));
            cost.add_row (new ActionRow (_("Pages"), _("Cover, drawings, measurements, materials, construction, pieces, colorways and revisions")));
            page.append (cost);
        }

        private void build_poms () {
            var pg = new PreferencesGroup (_("Points of Measure"), _("Values follow the pattern grading through the formula; typing a value in a size overrides it. Values in %s.").printf (project.pattern.unit));
            Dialogs.header_button (pg, _("Add"), () => {
                history.checkpoint ();
                string code = ((char) ('A' + tp.poms.size % 26)).to_string ();
                tp.poms.add (new Pom (code, _("New measurement")));
                project.touch ("techpack");
                refresh ();
            });
            var sizes = project.pattern.all_sizes ();
            var grid = new Grid ();
            grid.row_spacing = 4;
            grid.column_spacing = 6;
            string[] heads = { _("Code"), _("Description"), _("How to Measure"), _("Tol -"), _("Tol +"), _("Formula") };
            for (int i = 0; i < heads.length; i++) grid.attach (head (heads[i]), i, 0);
            for (int i = 0; i < sizes.size; i++) {
                var h = head (sizes[i]);
                if (sizes[i] == project.pattern.table.base_size) h.add_css_class ("accent");
                grid.attach (h, heads.length + i, 0);
            }
            int row = 1;
            foreach (var p in tp.poms) {
                var pom = p;
                grid.attach (cell (p.code, 4, (t) => pom.code = t), 0, row);
                grid.attach (cell (p.description, 18, (t) => pom.description = t), 1, row);
                grid.attach (cell (p.method, 22, (t) => pom.method = t), 2, row);
                grid.attach (cell (PathData.fmt (p.tol_minus, 2), 4, (t) => pom.tol_minus = num (t), true), 3, row);
                grid.attach (cell (PathData.fmt (p.tol_plus, 2), 4, (t) => pom.tol_plus = num (t), true), 4, row);
                var cells = new Gee.ArrayList<Entry> ();
                var link = cell (p.link, 18, (t) => pom.link = t.strip ());
                link.tooltip_text = _("A formula with measurements and pattern values, for example bust_circ / 2 + 5 or Line_A_B * 2");
                grid.attach (link, 5, row);
                for (int i = 0; i < sizes.size; i++) {
                    string size = sizes[i];
                    string? err;
                    var v = p.value_for (project.pattern, size, out err);
                    var e = new Entry ();
                    e.width_chars = 6;
                    e.xalign = 1;
                    e.add_css_class ("atelier-value");
                    e.text = v != null ? PathData.fmt (v, 1) : "";
                    if (!p.values.has_key (size)) e.add_css_class ("dim-label");
                    if (err != null) {
                        e.tooltip_text = err;
                        e.add_css_class ("atelier-error");
                    }
                    e.changed.connect (() => {
                        if (e.has_focus && e.text.strip () != "") {
                            pom.values[size] = num (e.text);
                            e.remove_css_class ("dim-label");
                            project.modified = true;
                        }
                    });
                    cells.add (e);
                    grid.attach (e, heads.length + i, row);
                }
                link.activate.connect (() => refresh ());
                var more = new Button.from_icon_name ("view-more-symbolic");
                more.add_css_class ("flat");
                more.tooltip_text = _("Options");
                more.clicked.connect (() => {
                    var m = new ContextMenu (more);
                    m.add_item (_("Use Formula for All Sizes"), "view-refresh-symbolic", () => {
                        history.checkpoint ();
                        pom.values.clear ();
                        refresh ();
                    });
                    m.add_item (_("Delete"), "user-trash-symbolic", () => {
                        history.checkpoint ();
                        tp.poms.remove (pom);
                        project.touch ("techpack");
                        refresh ();
                    });
                    m.closed.connect (() => Idle.add (() => {
                        m.unparent ();
                        return Source.REMOVE;
                    }));
                    m.popup ();
                });
                grid.attach (more, heads.length + sizes.size, row);
                row++;
            }
            pg.add_row (table (grid));
            page.append (pg);
        }

        private void build_bom () {
            var bg = new PreferencesGroup (_("Bill of Materials"));
            var add = Dialogs.header_button (bg, _("Add"), () => { });
            add.clicked.connect (() => {
                var m = new ContextMenu (add);
                m.add_item (_("Empty Item"), "list-add-symbolic", () => {
                    history.checkpoint ();
                    var b = new BomItem (tp.new_id ("b"));
                    b.name = _("New item");
                    b.currency = tp.bom.size > 0 ? tp.bom[0].currency : "EUR";
                    tp.bom.add (b);
                    project.touch ("techpack");
                    refresh ();
                });
                m.add_separator ();
                library_items (m);
                Dialogs.popup (m);
            });
            var grid = new Grid ();
            grid.row_spacing = 4;
            grid.column_spacing = 6;
            string[] heads = { _("Category"), _("Item"), _("Code"), _("Supplier"), _("Placement"), _("Composition"), _("Quantity"), _("Unit"), _("Waste %"), _("Unit Cost"), _("Cost") };
            for (int i = 0; i < heads.length; i++) grid.attach (head (heads[i]), i, 0);
            for (int i = 0; i < project.colorways.size; i++) grid.attach (head (project.colorways[i].name), heads.length + i, 0);
            string[] cats = { "fabric", "lining", "interfacing", "trim", "thread", "label", "packaging", "leather", "hardware" };
            string[] catl = { _("Fabric"), _("Lining"), _("Interfacing"), _("Trim"), _("Thread"), _("Label"), _("Packaging"), _("Leather"), _("Hardware") };
            int row = 1;
            foreach (var b in tp.bom) {
                var it = b;
                var cd = new DropDown.from_strings (catl);
                cd.valign = Align.CENTER;
                int cs = 0;
                for (int i = 0; i < cats.length; i++) if (cats[i] == b.category) cs = i;
                cd.selected = cs;
                cd.notify["selected"].connect (() => {
                    it.category = cats[cd.selected];
                    project.modified = true;
                });
                grid.attach (cd, 0, row);
                grid.attach (cell (b.name, 12, (t) => it.name = t), 1, row);
                grid.attach (cell (b.code, 5, (t) => it.code = t), 2, row);
                grid.attach (cell (b.supplier, 7, (t) => it.supplier = t), 3, row);
                grid.attach (cell (b.placement, 7, (t) => it.placement = t), 4, row);
                grid.attach (cell (b.composition, 7, (t) => it.composition = t), 5, row);
                var cost_label = new Label (PathData.fmt (b.cost (), 2));
                cost_label.add_css_class ("atelier-value");
                cost_label.xalign = 1;
                var qty = cell (PathData.fmt (b.quantity, 3), 5, (t) => {
                    it.quantity = num (t);
                    cost_label.label = PathData.fmt (it.cost (), 2);
                }, true);
                if (b.from_marker) qty.tooltip_text = _("From the marker layout");
                grid.attach (qty, 6, row);
                grid.attach (cell (b.unit, 3, (t) => it.unit = t), 7, row);
                grid.attach (cell (PathData.fmt (b.waste, 1), 4, (t) => {
                    it.waste = num (t);
                    cost_label.label = PathData.fmt (it.cost (), 2);
                }, true), 8, row);
                grid.attach (cell (PathData.fmt (b.unit_cost, 3), 5, (t) => {
                    it.unit_cost = num (t);
                    cost_label.label = PathData.fmt (it.cost (), 2);
                }, true), 9, row);
                grid.attach (cost_label, 10, row);
                for (int i = 0; i < project.colorways.size; i++) {
                    string cw = project.colorways[i].name;
                    grid.attach (cell (b.colors.has_key (cw) ? b.colors[cw] : "", 7, (t) => it.colors[cw] = t), heads.length + i, row);
                }
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.tooltip_text = _("Remove");
                del.clicked.connect (() => {
                    history.checkpoint ();
                    tp.bom.remove (it);
                    project.touch ("techpack");
                    refresh ();
                });
                grid.attach (del, heads.length + project.colorways.size, row);
                row++;
            }
            bg.add_row (table (grid));
            page.append (bg);
            var tg = new PreferencesGroup (_("Totals"));
            tg.add_row (new ActionRow (_("Cost per Garment"), "%s %s".printf (PathData.fmt (tp.total_cost (), 2), tp.bom.size > 0 ? tp.bom[0].currency : "")));
            Dialogs.button_row (tg, _("Fabric from Marker"), _("Sets the main fabric consumption from the marker layout"), _("Apply"), () => {
                double per = Marker.fabric_consumption_m (project.pattern, project.marker, 1);
                BomItem? target = null;
                foreach (var b in tp.bom) if (b.category == "fabric" && (target == null || b.from_marker)) target = b;
                if (target == null) {
                    message (_("Add a fabric first"));
                    return;
                }
                history.checkpoint ();
                target.quantity = Math.round (per * 1000) / 1000;
                target.unit = "m";
                target.from_marker = true;
                target.width_cm = project.marker.fabric_width / 10;
                project.touch ("techpack");
                refresh ();
                message (_("%s: %s m per garment").printf (target.name, PathData.fmt (per, 3)));
            });
            page.append (tg);
        }

        private void library_items (ContextMenu m) {
            var lib = Singularity.Assets.AssetLibrary.get_default ();
            int n = 0;
            foreach (var a in lib.list ()) {
                if (a.kind != "fabric" && a.kind != "trim") continue;
                var asset = a;
                n++;
                m.add_item (a.name, a.kind == "fabric" ? "atelier-fill-symbolic" : "atelier-trim-symbolic", () => {
                    history.checkpoint ();
                    var b = new BomItem (tp.new_id ("b"));
                    b.asset_id = asset.id;
                    b.name = asset.name;
                    b.category = asset.kind == "fabric" ? "fabric" : "trim";
                    b.code = asset.get_field ("code");
                    b.supplier = asset.get_field ("supplier");
                    b.composition = asset.get_field ("composition");
                    b.unit = asset.kind == "fabric" ? "m" : "pcs";
                    b.unit_cost = asset.get_number (asset.kind == "fabric" ? "price" : "cost");
                    b.width_cm = asset.get_number ("width");
                    tp.bom.add (b);
                    project.touch ("techpack");
                    refresh ();
                });
            }
            if (n == 0) m.add_item (_("Library Fabrics and Trims Appear Here"), null, () => show_section ("lib-fabric"));
        }

        private void build_ops () {
            var og = new PreferencesGroup (_("Construction"), _("Operations in sewing order with their standard minutes."));
            Dialogs.header_button (og, _("Add"), () => {
                history.checkpoint ();
                int seq = 1;
                foreach (var o in tp.operations) seq = int.max (seq, o.seq + 1);
                tp.operations.add (new Operation (seq, _("New operation")));
                project.touch ("techpack");
                refresh ();
            });
            var grid = new Grid ();
            grid.row_spacing = 4;
            grid.column_spacing = 6;
            string[] heads = { _("Step"), _("Operation"), _("Stitch"), _("SPI"), _("Machine"), _("Seam"), _("Callout"), _("Minutes"), _("Notes") };
            for (int i = 0; i < heads.length; i++) grid.attach (head (heads[i]), i, 0);
            int row = 1;
            foreach (var o in tp.operations) {
                var op = o;
                grid.attach (cell (o.seq.to_string (), 3, (t) => op.seq = (int) num (t), true), 0, row);
                grid.attach (cell (o.description, 22, (t) => op.description = t), 1, row);
                grid.attach (cell (o.stitch, 6, (t) => op.stitch = t), 2, row);
                grid.attach (cell (PathData.fmt (o.spi, 1), 4, (t) => op.spi = num (t), true), 3, row);
                grid.attach (cell (o.machine, 12, (t) => op.machine = t), 4, row);
                grid.attach (cell (o.seam, 8, (t) => op.seam = t), 5, row);
                grid.attach (cell (o.callout > 0 ? o.callout.to_string () : "", 3, (t) => op.callout = (int) num (t), true), 6, row);
                grid.attach (cell (PathData.fmt (o.minutes, 2), 5, (t) => op.minutes = num (t), true), 7, row);
                grid.attach (cell (o.notes, 16, (t) => op.notes = t), 8, row);
                var del = new Button.from_icon_name ("user-trash-symbolic");
                del.add_css_class ("flat");
                del.tooltip_text = _("Remove");
                del.clicked.connect (() => {
                    history.checkpoint ();
                    tp.operations.remove (op);
                    project.touch ("techpack");
                    refresh ();
                });
                grid.attach (del, heads.length, row);
                row++;
            }
            og.add_row (table (grid));
            og.add_row (new ActionRow (_("Standard Minutes"), PathData.fmt (tp.total_minutes (), 2)));
            page.append (og);
        }

        private void build_review () {
            var rg = new PreferencesGroup (_("Revisions"), _("Each revision keeps a copy of the whole project."));
            var note = new FieldRow (_("What Changed"));
            Dialogs.header_button (rg, _("Save Revision"), () => {
                history.checkpoint ();
                var r = new Revision (tp.revisions.size + 1, note.text.strip () != "" ? note.text.strip () : _("Revision"));
                r.author = Environment.get_real_name () != "Unknown" ? Environment.get_real_name () : Environment.get_user_name ();
                var keep = tp.revisions;
                tp.revisions = new Gee.ArrayList<Revision> ();
                r.snapshot = NativeFormat.to_json (project);
                tp.revisions = keep;
                tp.revisions.add (r);
                project.touch ("techpack");
                refresh ();
            });
            rg.add_row (note);
            foreach (var r in tp.revisions) {
                var rev = r;
                var row = new ActionRow (_("Revision %d: %s").printf (r.number, r.note), "%s %s".printf (r.date, r.author));
                if (r.snapshot != "") {
                    var restore = new Button.with_label (_("Restore"));
                    restore.valign = Align.CENTER;
                    restore.clicked.connect (() => {
                        Dialogs.confirm ((Gtk.Window) get_root (), _("Restore Revision %d?").printf (rev.number), _("The project goes back to this revision. You can undo it."), _("Restore"), () => {
                            try {
                                history.checkpoint ();
                                var old = NativeFormat.from_json (rev.snapshot);
                                var keep = tp.revisions;
                                project.assign_from (old);
                                project.techpack.revisions = keep;
                                project.touch ("all");
                                history.restored ();
                                refresh ();
                            } catch (Error e) {
                                message (e.message);
                            }
                        }, false);
                    });
                    row.add_suffix (restore);
                }
                rg.add_row (row);
            }
            page.append (rg);
            if (tp.comments.size == 0) {
                var cg = new PreferencesGroup (_("Comments"));
                cg.add_row (new ActionRow (_("No Comments"), _("Use the comment tool in Flats to pin a remark on a drawing")));
                page.append (cg);
            }
            foreach (var c in tp.comments) page.append (comment_card (c));
        }

        private Widget comment_card (Comment c) {
            string who = c.author != "" ? c.author : _("Someone");
            string gtitle = "%s, %s".printf (who, c.date);
            string? gsub = null;
            if (c.sheet != "") {
                var sh = project.find_sheet (c.sheet);
                string shn = sh != null ? sh.name : c.sheet;
                gsub = _("On %s").printf (shn);
            }
            var g = new PreferencesGroup (gtitle, gsub);
            var tv = new TextView ();
            tv.add_css_class ("atelier-notes");
            tv.wrap_mode = WrapMode.WORD_CHAR;
            tv.buffer.text = c.text;
            tv.left_margin = 10;
            tv.right_margin = 10;
            tv.top_margin = 6;
            tv.bottom_margin = 6;
            tv.buffer.changed.connect (() => {
                c.text = tv.buffer.text;
                project.modified = true;
            });
            g.add_row (tv);
            foreach (var r in c.replies) g.add_row (new ActionRow (r.text, "%s %s".printf (r.author, r.date)));
            var reply = new FieldRow (_("Reply"));
            reply.field.activate.connect (() => {
                if (reply.text.strip () == "") return;
                history.checkpoint ();
                var r = new Comment (tp.new_id ("k"), reply.text.strip ());
                r.author = Environment.get_real_name () != "Unknown" ? Environment.get_real_name () : Environment.get_user_name ();
                c.replies.add (r);
                project.touch ("techpack");
                refresh ();
            });
            g.add_row (reply);
            Dialogs.header_button (g, c.resolved ? _("Reopen") : _("Resolve"), () => {
                history.checkpoint ();
                c.resolved = !c.resolved;
                project.touch ("techpack");
                refresh ();
            });
            var del = new Button.from_icon_name ("user-trash-symbolic");
            del.valign = Align.CENTER;
            del.tooltip_text = _("Delete Comment");
            del.clicked.connect (() => {
                history.checkpoint ();
                tp.comments.remove (c);
                project.touch ("techpack");
                refresh ();
            });
            g.add_header_suffix (del);
            return g;
        }
    }
}
