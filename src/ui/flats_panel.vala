using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class FlatsPanel : InspectorPanel {
        private Project project;
        private History history;
        private FlatsCanvas canvas;
        private PreferencesGroup sheets_group;
        private Box inspector;
        private Box colorways_box;
        public ToolPalette palette { get; private set; }
        private Box tool_options;
        public signal void message (string text);

        public FlatsPanel (Project project, History history, FlatsCanvas canvas) {
            this.project = project;
            this.history = history;
            this.canvas = canvas;
            build ();
            canvas.selection_changed.connect (() => fill_inspector ());
            canvas.message.connect ((m) => message (m));
            history.restored.connect (() => {
                project = canvas.project;
                refresh ();
            });
        }

        public void refresh () {
            project = canvas.project;
            fill_sheets ();
            fill_inspector ();
            fill_colorways ();
        }

        private void build () {
            sheets_group = new PreferencesGroup (_("Drawings"));
            var add = Dialogs.header_button (sheets_group, _("Add"), () => { });
            add.tooltip_text = _("Add a Drawing");
            add.clicked.connect (() => template_menu (add));
            append (sheets_group);

            palette = new ToolPalette ();
            string[,] list = {
                { "select", "atelier-pointer-symbolic", _("Select, Move and Edit Nodes") }, { "pen", "atelier-pen-symbolic", _("Pen: click for corners, drag for curves, close on the first point or press Enter") },
                { "line", "atelier-line-symbolic", _("Line") }, { "stitch", "atelier-stitch-symbolic", _("Stitch Line: draw like the pen, Enter to finish") },
                { "trim", "atelier-trim-symbolic", _("Trims and Components") }, { "dimension", "atelier-dimension-symbolic", _("Dimension: two clicks") },
                { "curve-dimension", "atelier-seam-walk-symbolic", _("Measure Along a Line") }, { "callout", "atelier-callout-symbolic", _("Numbered Callout: anchor, then label") },
                { "text", "atelier-text-symbolic", _("Text") }, { "comment", "atelier-techpack-symbolic", _("Review Comment") }
            };
            for (int i = 0; i < list.length[0]; i++) palette.add_tool (list[i, 0], list[i, 1], list[i, 2]);
            palette.set_active (canvas.tool);
            palette.tool_selected.connect ((id) => {
                canvas.choose_tool (id);
                fill_tool_options ();
            });
            tool_options = new Box (Orientation.VERTICAL, 0);
            append (tool_options);

            inspector = new Box (Orientation.VERTICAL, 0);
            append (inspector);

            colorways_box = new Box (Orientation.VERTICAL, 0);
            append (colorways_box);
            refresh ();
            fill_tool_options ();
        }

        public void sync_tool () {
            palette.set_active (canvas.tool);
            fill_tool_options ();
        }

        private void template_menu (Widget anchor) {
            var m = new ContextMenu (anchor);
            m.add_item (_("Blank Sheet"), "list-add-symbolic", () => {
                history.checkpoint ();
                var sh = new FlatSheet ("s%d".printf (project.flats.size + 1), _("View %d").printf (project.flats.size + 1));
                while (project.find_sheet (sh.id) != null) sh.id += "x";
                project.flats.add (sh);
                canvas.sheet = sh;
                project.touch ("flats");
                fill_sheets ();
                canvas.fit_all ();
            });
            m.add_separator ();
            foreach (var t in Flats.TEMPLATES) {
                string id = t;
                m.add_item (Flats.template_label (id), "atelier-flat-symbolic", () => {
                    history.checkpoint ();
                    var made = Flats.build (id);
                    foreach (var sh in made) {
                        sh.id = "%s-%s".printf (id, sh.id);
                        while (project.find_sheet (sh.id) != null) sh.id += "x";
                        sh.name = "%s %s".printf (Flats.template_label (id), sh.name);
                        project.flats.add (sh);
                    }
                    canvas.sheet = made[0];
                    project.touch ("flats");
                    fill_sheets ();
                    canvas.fit_all ();
                });
            }
            Dialogs.popup (m);
        }

        private void fill_sheets () {
            sheets_group.clear ();
            if (project.flats.size == 0) {
                sheets_group.add_row (new ActionRow (_("No Drawings"), _("Add a blank sheet or start from a template")));
                return;
            }
            foreach (var sh in project.flats) {
                var s = sh;
                var row = new ActionRow (sh.name);
                var thumb = new DrawingArea ();
                thumb.set_size_request (40, 40);
                thumb.valign = Align.CENTER;
                thumb.margin_end = 10;
                thumb.set_draw_func ((a, cr, w, h) => TechPackLayout.draw_sheet_fit (cr, s, project.colorway (), 0, 0, w, h, false));
                row.add_prefix (thumb);
                if (canvas.sheet == sh) row.add_suffix (new Image.from_icon_name ("object-select-symbolic"));
                var more = new Button.from_icon_name ("view-more-symbolic");
                more.add_css_class ("flat");
                more.valign = Align.CENTER;
                more.tooltip_text = _("Drawing Options");
                more.clicked.connect (() => sheet_menu (more, s));
                row.add_suffix (more);
                row.activated.connect (() => {
                    canvas.sheet = s;
                    canvas.selection.clear ();
                    canvas.fit_all ();
                    fill_inspector ();
                    Idle.add (() => {
                        fill_sheets ();
                        return Source.REMOVE;
                    });
                });
                sheets_group.add_row (row);
            }
        }

        private void sheet_menu (Widget anchor, FlatSheet sh) {
            var m = new ContextMenu (anchor);
            m.add_item (_("Rename"), "document-edit-symbolic", () => {
                Box body;
                Entry? e = null;
                SpinButton? sc = null;
                var dlg = Dialogs.form ((Gtk.Window) get_root (), _("Drawing"), _("Apply"), out body, () => {
                    history.checkpoint ();
                    if (e.text.strip () != "") sh.name = e.text.strip ();
                    sh.scale_mm = sc.value;
                    project.touch ("flats");
                    fill_sheets ();
                });
                var g = new PreferencesGroup (_("Drawing"));
                e = Dialogs.entry_row (g, _("Name"), sh.name);
                sc = Dialogs.spin_row (g, _("Scale"), 0.1, 20, 0.05, sh.scale_mm, 2, _("Millimetres of garment per drawing unit, used by dimensions"));
                body.append (g);
                dlg.present ();
            });
            m.add_item (_("Duplicate"), "edit-copy-symbolic", () => {
                history.checkpoint ();
                var c = new FlatSheet (sh.id + "-copy", sh.name + " " + _("Copy"));
                while (project.find_sheet (c.id) != null) c.id += "x";
                c.axis_x = sh.axis_x;
                c.scale_mm = sh.scale_mm;
                foreach (var it in sh.items) c.items.add (it.copy ());
                project.flats.insert (project.flats.index_of (sh) + 1, c);
                project.touch ("flats");
                fill_sheets ();
            });
            m.add_separator ();
            m.add_item (_("Delete"), "user-trash-symbolic", () => {
                history.checkpoint ();
                project.flats.remove (sh);
                if (canvas.sheet == sh) canvas.sheet = project.flats.size > 0 ? project.flats[0] : null;
                project.touch ("flats");
                fill_sheets ();
                canvas.queue_draw ();
            }, "destructive-action");
            Dialogs.popup (m);
        }

        private void fill_tool_options () {
            Dialogs.clear (tool_options);
            if (canvas.tool == "stitch") {
                var g = new PreferencesGroup (_("Stitch Line"), _("Draw like the pen, press Enter to finish."));
                stitch_rows (g, canvas.stitch, null);
                tool_options.append (g);
            } else if (canvas.tool == "trim") {
                var g = new PreferencesGroup (_("Trims and Components"), _("Click on the drawing to place one."));
                string[] labels = {};
                int sel = 0;
                for (int i = 0; i < Trims.KINDS.length; i++) {
                    labels += Trims.label (Trims.KINDS[i]);
                    if (Trims.KINDS[i] == canvas.trim_kind) sel = i;
                }
                var d = Dialogs.choice_row (g, _("Component"), labels, sel);
                d.notify["selected"].connect (() => {
                    canvas.trim_kind = Trims.KINDS[d.selected];
                    canvas.trim_asset = "";
                });
                var assets = Singularity.Assets.AssetLibrary.get_default ().list ("trim");
                if (assets.size > 0) {
                    string[] al = { _("None") };
                    foreach (var a in assets) al += a.name;
                    var ad = Dialogs.choice_row (g, _("From Library"), al, 0);
                    ad.notify["selected"].connect (() => canvas.trim_asset = ad.selected > 0 ? assets[(int) ad.selected - 1].id : "");
                }
                tool_options.append (g);
            }
        }

        private void stitch_rows (PreferencesGroup g, StitchStyle st, FlatItem? item) {
            string[] labels = {};
            var kinds = StitchKind.all ();
            int sel = 0;
            for (int i = 0; i < kinds.length; i++) {
                labels += kinds[i].label ();
                if (kinds[i] == st.kind) sel = i;
            }
            var kd = Dialogs.choice_row (g, _("Stitch"), labels, sel);
            kd.notify["selected"].connect (() => {
                if (item != null) history.checkpoint ();
                st.kind = kinds[kd.selected];
                touch ();
            });
            var pitch = Dialogs.spin_row (g, _("Stitch Length"), 0.5, 20, 0.5, st.pitch, 1);
            pitch.value_changed.connect (() => {
                st.pitch = pitch.value;
                touch ();
            });
            var gap = Dialogs.spin_row (g, _("Needle Gap"), 0.5, 30, 0.5, st.gap, 1);
            gap.value_changed.connect (() => {
                st.gap = gap.value;
                touch ();
            });
            var off = Dialogs.spin_row (g, _("Distance from Edge"), -30, 30, 0.5, st.offset, 1);
            off.value_changed.connect (() => {
                st.offset = off.value;
                touch ();
            });
            var w = Dialogs.spin_row (g, _("Width"), 0.5, 20, 0.5, st.width, 1, _("Zigzag, overlock and zipper"));
            w.value_changed.connect (() => {
                st.width = w.value;
                touch ();
            });
            var slot = slot_row (g, _("Thread Colour"), st.color_slot);
            slot.notify["selected"].connect (() => {
                st.color_slot = project.slots[(int) slot.selected];
                touch ();
            });
        }

        private Choice slot_row (PreferencesGroup g, string title, string current, bool allow_none = false) {
            string[] labels = {};
            if (allow_none) labels += _("None");
            int sel = 0;
            for (int i = 0; i < project.slots.size; i++) {
                labels += project.slots[i];
                if (project.slots[i] == current) sel = i + (allow_none ? 1 : 0);
            }
            return Dialogs.choice_row (g, title, labels, sel);
        }

        private void touch () {
            project.touch ("flats");
            canvas.queue_draw ();
        }

        private void fill_inspector () {
            Dialogs.clear (inspector);
            if (canvas.sheet == null || canvas.selection.size != 1) return;
            var it = canvas.sheet.find (canvas.selection.to_array ()[0]);
            if (it == null) return;
            var g = new PreferencesGroup (it.name != "" ? it.name : _("Selection"));
            var name = Dialogs.entry_row (g, _("Name"), it.name);
            name.changed.connect (() => it.name = name.text);
            switch (it.kind) {
                case FlatItemKind.SHAPE: {
                    var fill = slot_row (g, _("Fill"), it.fill_slot, true);
                    fill.notify["selected"].connect (() => {
                        history.checkpoint ();
                        it.fill_slot = fill.selected == 0 ? "" : project.slots[(int) fill.selected - 1];
                        touch ();
                    });
                    var line = slot_row (g, _("Line Colour"), it.line_slot);
                    line.notify["selected"].connect (() => {
                        it.line_slot = project.slots[(int) line.selected];
                        touch ();
                    });
                    var lw = Dialogs.spin_row (g, _("Line Width"), 0, 6, 0.1, it.line_width, 1);
                    lw.value_changed.connect (() => {
                        it.line_width = lw.value;
                        touch ();
                    });
                    var dashed = Dialogs.switch_row (g, _("Dashed"), it.dashed);
                    dashed.notify["active"].connect (() => {
                        it.dashed = dashed.active;
                        touch ();
                    });
                    var mirror = Dialogs.switch_row (g, _("Mirror on the Centre Line"), it.mirror);
                    mirror.notify["active"].connect (() => {
                        history.checkpoint ();
                        it.mirror = mirror.active;
                        touch ();
                    });
                    inspector.append (g);
                    var sg = new PreferencesGroup (_("Stitching"));
                    stitch_rows (sg, it.stitch, it);
                    inspector.append (sg);
                    var fabrics = Singularity.Assets.AssetLibrary.get_default ().list ("fabric");
                    var fg = new PreferencesGroup (_("Fabric and Print"));
                    string[] fl = { _("Plain Colour") };
                    int fsel = 0;
                    for (int i = 0; i < fabrics.size; i++) {
                        fl += fabrics[i].name;
                        if (fabrics[i].id == it.fabric_id) fsel = i + 1;
                    }
                    var fd = Dialogs.choice_row (fg, _("Fill With"), fl, fsel);
                    fd.notify["selected"].connect (() => {
                        history.checkpoint ();
                        it.fabric_id = fd.selected > 0 ? fabrics[(int) fd.selected - 1].id : "";
                        touch ();
                    });
                    var sc = Dialogs.spin_row (fg, _("Print Scale"), 0.05, 20, 0.05, it.pattern_scale, 2);
                    sc.value_changed.connect (() => {
                        it.pattern_scale = sc.value;
                        touch ();
                    });
                    var ang = Dialogs.spin_row (fg, _("Print Angle"), -180, 180, 5, it.pattern_angle, 0);
                    ang.value_changed.connect (() => {
                        it.pattern_angle = ang.value;
                        touch ();
                    });
                    if (fabrics.size == 0) fg.description = _("Add fabrics in the Tech Pack library to fill shapes with them.");
                    inspector.append (fg);
                    return;
                }
                case FlatItemKind.TRIM: {
                    string[] labels = {};
                    int sel = 0;
                    for (int i = 0; i < Trims.KINDS.length; i++) {
                        labels += Trims.label (Trims.KINDS[i]);
                        if (Trims.KINDS[i] == it.trim) sel = i;
                    }
                    var d = Dialogs.choice_row (g, _("Component"), labels, sel);
                    d.notify["selected"].connect (() => {
                        it.trim = Trims.KINDS[d.selected];
                        touch ();
                    });
                    var size = Dialogs.spin_row (g, _("Size"), 1, 400, 0.5, it.size, 1);
                    size.value_changed.connect (() => {
                        it.size = size.value;
                        touch ();
                    });
                    var rot = Dialogs.spin_row (g, _("Rotation"), -180, 180, 5, it.rotation, 0);
                    rot.value_changed.connect (() => {
                        it.rotation = rot.value;
                        touch ();
                    });
                    var fill = slot_row (g, _("Colour"), it.fill_slot);
                    fill.notify["selected"].connect (() => {
                        it.fill_slot = project.slots[(int) fill.selected];
                        touch ();
                    });
                    var mirror = Dialogs.switch_row (g, _("Mirror on the Centre Line"), it.mirror);
                    mirror.notify["active"].connect (() => {
                        it.mirror = mirror.active;
                        touch ();
                    });
                    break;
                }
                case FlatItemKind.CALLOUT: {
                    var num = Dialogs.spin_row (g, _("Number"), 1, 999, 1, it.number, 0);
                    num.value_changed.connect (() => {
                        it.number = (int) num.value;
                        touch ();
                    });
                    var text = Dialogs.entry_row (g, _("Text"), it.text);
                    text.changed.connect (() => {
                        it.text = text.text;
                        canvas.queue_draw ();
                    });
                    string[] links = { _("None") };
                    string[] ids = { "" };
                    int sel = 0;
                    foreach (var b in project.techpack.bom) {
                        links += _("Material: %s").printf (b.name);
                        ids += b.id;
                        if (b.id == it.link) sel = ids.length - 1;
                    }
                    var link = Dialogs.choice_row (g, _("Linked To"), links, sel);
                    link.notify["selected"].connect (() => it.link = ids[link.selected]);
                    string[] ops = { _("None") };
                    int osel = 0;
                    for (int i = 0; i < project.techpack.operations.size; i++) {
                        var o = project.techpack.operations[i];
                        ops += "%d. %s".printf (o.seq, o.description);
                        if (o.callout == it.number) osel = i + 1;
                    }
                    var opd = Dialogs.choice_row (g, _("Construction Step"), ops, osel);
                    opd.notify["selected"].connect (() => {
                        foreach (var o in project.techpack.operations) if (o.callout == it.number) o.callout = 0;
                        if (opd.selected > 0) project.techpack.operations[(int) opd.selected - 1].callout = it.number;
                        project.touch ("techpack");
                    });
                    break;
                }
                case FlatItemKind.DIMENSION: {
                    var text = Dialogs.entry_row (g, _("Label"), it.text, _("Empty shows the measured length"));
                    text.changed.connect (() => {
                        it.text = text.text;
                        canvas.queue_draw ();
                    });
                    var off = Dialogs.spin_row (g, _("Offset"), -200, 200, 1, it.offset, 0);
                    off.value_changed.connect (() => {
                        it.offset = off.value;
                        canvas.queue_draw ();
                    });
                    string[] codes = { _("None") };
                    int sel = 0;
                    foreach (var p in project.techpack.poms) {
                        codes += "%s %s".printf (p.code, p.description);
                        if (p.code == it.link) sel = codes.length - 1;
                    }
                    var pom = Dialogs.choice_row (g, _("Point of Measure"), codes, sel);
                    pom.notify["selected"].connect (() => {
                        it.link = pom.selected > 0 ? project.techpack.poms[(int) pom.selected - 1].code : "";
                        canvas.queue_draw ();
                    });
                    double len = it.measured_length (0) * canvas.sheet.scale_mm;
                    g.add_row (new ActionRow (_("Measured"), FlatRenderer.format_length (len)));
                    break;
                }
                case FlatItemKind.TEXT: {
                    var text = Dialogs.entry_row (g, _("Text"), it.text);
                    text.changed.connect (() => {
                        it.text = text.text;
                        canvas.queue_draw ();
                    });
                    var size = Dialogs.spin_row (g, _("Size"), 4, 72, 1, it.size, 0);
                    size.value_changed.connect (() => {
                        it.size = size.value;
                        canvas.queue_draw ();
                    });
                    break;
                }
            }
            inspector.append (g);
        }

        private void fill_colorways () {
            Dialogs.clear (colorways_box);
            var cw = project.colorway ();
            var g = new PreferencesGroup (_("Colorways"));
            Dialogs.header_button (g, _("Duplicate"), () => {
                history.checkpoint ();
                int n = project.colorways.size + 1;
                string nm = _("Colorway %d").printf (n);
                while (project.find_colorway (nm) != null) nm = _("Colorway %d").printf (++n);
                project.colorways.add (cw.copy (nm));
                project.active_colorway = nm;
                project.touch ("colorway");
                fill_colorways ();
            });
            string[] names = {};
            int active = 0;
            for (int i = 0; i < project.colorways.size; i++) {
                names += project.colorways[i].name;
                if (project.colorways[i] == cw) active = i;
            }
            var pick_cw = Dialogs.choice_row (g, _("Shown"), names, active);
            pick_cw.notify["selected"].connect (() => {
                project.active_colorway = project.colorways[(int) pick_cw.selected].name;
                canvas.queue_draw ();
                Idle.add (() => {
                    fill_colorways ();
                    return Source.REMOVE;
                });
            });
            foreach (var slot in project.slots) {
                string sl = slot;
                var cref = cw.colors.has_key (sl) ? cw.colors[sl] : null;
                string? sub = null;
                if (cref != null) sub = cref.code != "" ? cref.code + " " + cref.name : cref.name;
                if (cref != null && canvas.proof_profile != "") {
                    bool oog;
                    ColorManager.soft_proof (cref.color, canvas.proof_profile, out oog);
                    if (oog) sub = _("%s, outside the printable range").printf (sub ?? "");
                }
                var row = new ActionRow (sl, sub);
                var book = new Button.from_icon_name ("atelier-colorway-symbolic");
                book.add_css_class ("flat");
                book.valign = Align.CENTER;
                book.tooltip_text = _("Choose from a Colour Book");
                book.clicked.connect (() => book_menu (book, cw, sl));
                row.add_suffix (book);
                var pick = new ColorPickerButton (Dialogs.to_gdk (cref != null ? cref.color : Rgba (0.5, 0.5, 0.5)));
                pick.valign = Align.CENTER;
                pick.color_changed.connect ((c) => {
                    history.checkpoint ();
                    var nc = new ColorRef (Dialogs.from_gdk (c), sl);
                    cw.colors[sl] = nc;
                    project.touch ("colorway");
                    canvas.queue_draw ();
                });
                row.add_suffix (pick);
                g.add_row (row);
            }
            var profiles = ColorManager.system_profiles ();
            if (ColorManager.available () && profiles.size > 0) {
                string[] pl = { _("Screen Colours") };
                int psel = 0;
                for (int i = 0; i < profiles.size; i++) {
                    pl += Path.get_basename (profiles[i]);
                    if (profiles[i] == canvas.proof_profile) psel = i + 1;
                }
                var proof = Dialogs.choice_row (g, _("Proof For"), pl, psel);
                proof.notify["selected"].connect (() => {
                    canvas.proof_profile = proof.selected > 0 ? profiles[(int) proof.selected - 1] : "";
                    canvas.queue_draw ();
                    Idle.add (() => {
                        fill_colorways ();
                        return Source.REMOVE;
                    });
                });
            }
            Dialogs.button_row (g, _("Rename Colorway"), cw.name, _("Rename"), () => {
                Box body;
                Entry? e = null;
                var dlg = Dialogs.form ((Gtk.Window) get_root (), _("Rename Colorway"), _("Rename"), out body, () => {
                    string nm = e.text.strip ();
                    if (nm == "" || project.find_colorway (nm) != null) return;
                    history.checkpoint ();
                    foreach (var b in project.techpack.bom) if (b.colors.has_key (cw.name)) {
                        b.colors[nm] = b.colors[cw.name];
                        b.colors.unset (cw.name);
                    }
                    cw.name = nm;
                    project.active_colorway = nm;
                    project.touch ("colorway");
                    fill_colorways ();
                });
                var gg = new PreferencesGroup (_("Colorway"));
                e = Dialogs.entry_row (gg, _("Name"), cw.name);
                body.append (gg);
                dlg.present ();
            });
            if (project.colorways.size > 1) {
                var del = new ConfirmRow (_("Delete Colorway"), cw.name);
                del.confirm_label = _("Delete");
                del.confirmed.connect (() => {
                    history.checkpoint ();
                    project.colorways.remove (cw);
                    project.active_colorway = project.colorways[0].name;
                    project.touch ("colorway");
                    canvas.queue_draw ();
                    Idle.add (() => {
                        fill_colorways ();
                        return Source.REMOVE;
                    });
                });
                g.add_row (del);
            }
            colorways_box.append (g);
        }

        private void book_menu (Widget anchor, Colorway cw, string slot) {
            var pop = new Popover ();
            pop.set_parent (anchor);
            var box = new Box (Orientation.VERTICAL, 6);
            box.margin_start = 8;
            box.margin_end = 8;
            box.margin_top = 8;
            box.margin_bottom = 8;
            var books = new Gee.ArrayList<ColorBook> ();
            books.add (ColorBook.textile ());
            var lib = new ColorBook (_("Library"));
            foreach (var a in Singularity.Assets.AssetLibrary.get_default ().list ("color")) {
                var c = new ColorRef (Rgba.parse (a.get_field ("color")), a.name);
                c.code = a.get_field ("code");
                c.book = a.get_field ("book", _("Library"));
                lib.colors.add (c);
            }
            if (lib.colors.size > 0) books.add (lib);
            foreach (var bk in books) {
                var t = new Label (bk.name);
                t.add_css_class ("heading");
                t.halign = Align.START;
                box.append (t);
                var flow = new FlowBox ();
                flow.selection_mode = SelectionMode.NONE;
                flow.max_children_per_line = 8;
                flow.min_children_per_line = 8;
                foreach (var c in bk.colors) {
                    var cc = c;
                    var b = Dialogs.swatch (c.color, "%s %s".printf (c.code, c.name));
                    b.clicked.connect (() => {
                        history.checkpoint ();
                        var r = cc.copy ();
                        if (r.book == "") r.book = bk.name;
                        cw.colors[slot] = r;
                        project.touch ("colorway");
                        canvas.queue_draw ();
                        pop.popdown ();
                        Idle.add (() => {
                            fill_colorways ();
                            return Source.REMOVE;
                        });
                    });
                    flow.append (b);
                }
                box.append (flow);
            }
            pop.child = box;
            pop.has_arrow = false;
            pop.closed.connect (() => Idle.add (() => {
                pop.unparent ();
                return Source.REMOVE;
            }));
            pop.popup ();
        }
    }
}
