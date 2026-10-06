using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class PatternPanel : InspectorPanel {
        private AtelierWindow win;
        private PatternCanvas canvas;
        public ToolPalette palette { get; private set; }
        private Box action_box;
        private Box inspector;
        private PreferencesGroup marker_group;
        private Box leather_box;
        private PreferencesGroup increments_group;
        private PreferencesGroup seams_group;
        private Button keep_seams;
        private bool building;

        public signal void refreshed ();

        public PatternPanel (AtelierWindow win, PatternCanvas canvas) {
            this.win = win;
            this.canvas = canvas;
            build ();
            canvas.selection_changed.connect (() => {
                fill_inspector ();
                fill_actions ();
                fill_leather ();
            });
            canvas.message.connect ((m) => win.add_toast (new Toast (m)));
            canvas.request_point.connect ((x, y) => new_point_dialog (x, y));
            canvas.evaluated.connect (() => {
                if (!building) fill_seams ();
            });
        }

        private Pattern pattern {
            get { return canvas.project.pattern; }
        }

        public void refresh () {
            building = true;
            fill_inspector ();
            fill_actions ();
            fill_increments ();
            fill_seams ();
            fill_marker ();
            fill_leather ();
            building = false;
            refreshed ();
        }

        public void set_size (string size) {
            if (pattern.active_size == size) return;
            pattern.active_size = size;
            canvas.reevaluate ();
            fill_inspector ();
        }

        public void set_unit (string u) {
            if (u == pattern.unit) return;
            win.add_toast (new Toast (_("Formulas keep their numbers; new values are read in %s").printf (u)));
            canvas.history.checkpoint ();
            pattern.unit = u;
            canvas.project.touch ("pattern");
        }

        public void edit_measurements () {
            var v = new MeasurementsView (win, canvas.project, canvas.history);
            v.closed.connect (() => refresh ());
            v.present ();
        }

        public void set_grading (string n) {
            if (n == pattern.grading) return;
            canvas.history.checkpoint ();
            if (n == "rules" && pattern.rules.rules.size == 0) Grading.derive_rules (pattern, Grading.nest_by_measurements (pattern));
            pattern.grading = n;
            canvas.project.touch ("pattern");
        }

        public void derive_rules () {
            canvas.history.checkpoint ();
            Grading.derive_rules (pattern, Grading.nest_by_measurements (pattern));
            canvas.project.touch ("pattern");
            win.add_toast (new Toast (ngettext ("%d grade rule", "%d grade rules", pattern.rules.rules.size).printf (pattern.rules.rules.size)));
        }

        public void edit_rules () {
            rules_dialog ();
        }

        public void apply_rule_provider (AtelierPlugin.GradeRuleProvider provider) {
            try {
                canvas.history.checkpoint ();
                Aama.import_rules (provider.rules (PluginHost.get_default ().pattern_json (pattern)), pattern);
                canvas.project.touch ("pattern");
                win.add_toast (new Toast (ngettext ("%d grade rule", "%d grade rules", pattern.rules.rules.size).printf (pattern.rules.rules.size)));
            } catch (Error e) {
                win.show_error (_("Could Not Apply the Rules"), e.message);
            }
        }

        public void set_stack_anchor (string anchor) {
            canvas.nest_anchor = anchor;
            canvas.queue_draw ();
        }

        public void develop_solid (string kind) {
            solid_dialog (kind);
        }

        public void lay_out () {
            canvas.compute_marker ();
            canvas.switch_mode ("marker");
        }

        public void apply_consumption () {
            var m = canvas.project.marker;
            double per = Marker.fabric_consumption_m (pattern, m, 1);
            BomItem? target = null;
            foreach (var b in canvas.project.techpack.bom) if (b.category == "fabric" && (target == null || b.from_marker)) target = b;
            if (target == null) {
                win.add_toast (new Toast (_("Add a fabric to the bill of materials first")));
                return;
            }
            canvas.history.checkpoint ();
            target.quantity = Math.round (per * 1000) / 1000;
            target.unit = "m";
            target.from_marker = true;
            target.width_cm = m.fabric_width / 10;
            canvas.project.touch ("techpack");
            win.add_toast (new Toast (_("%s: %s m per garment").printf (target.name, PathData.fmt (per, 3))));
        }

        private void build () {
            palette = new ToolPalette ();
            string[,] list = {
                { "select", "atelier-pointer-symbolic", _("Select and Move Points") }, { "point", "atelier-point-symbolic", _("New Point") },
                { "curve", "atelier-curve-symbolic", _("New Curve") }, { "piece", "atelier-piece-symbolic", _("New Piece") },
                { "notch", "atelier-notch-symbolic", _("Notch") }, { "drill", "atelier-drill-symbolic", _("Drill Hole") },
                { "grain", "atelier-grainline-symbolic", _("Grain Line") }, { "dart", "atelier-dart-symbolic", _("Move Dart") },
                { "pleat", "atelier-marker-layout-symbolic", _("Pleat") }, { "measure", "atelier-measure-symbolic", _("Measure") }
            };
            for (int i = 0; i < list.length[0]; i++) palette.add_tool (list[i, 0], list[i, 1], list[i, 2]);
            palette.set_active (canvas.tool);
            palette.tool_selected.connect ((id) => {
                canvas.tool = id;
                if (canvas.mode != "draft") canvas.switch_mode ("draft");
                if (id != "select") canvas.selection.clear ();
                fill_actions ();
            });
            action_box = new Box (Orientation.VERTICAL, 0);
            append (action_box);

            inspector = new Box (Orientation.VERTICAL, 0);
            append (inspector);

            increments_group = new PreferencesGroup (_("Variables"), _("Named values such as ease, used in formulas as #name."));
            Dialogs.header_button (increments_group, _("Add"), () => {
                canvas.history.checkpoint ();
                int n = pattern.increments.size + 1;
                while (find_inc ("var%d".printf (n)) != null) n++;
                pattern.increments.add (new Increment ("var%d".printf (n), "0"));
                canvas.project.touch ("pattern");
                fill_increments ();
            });
            append (increments_group);

            seams_group = new PreferencesGroup (_("Seams"), _("Matching edges between pieces, used for sewing in 3D and seam checks."));
            keep_seams = Dialogs.header_button (seams_group, _("Keep"), () => {
                var r = canvas.result;
                if (r == null) return;
                canvas.history.checkpoint ();
                canvas.project.garment.seams.add_all (Seams.guess_pairs (r));
                fill_seams ();
            });
            keep_seams.tooltip_text = _("Keep These Seams");
            append (seams_group);

            marker_group = new PreferencesGroup (_("Marker and Consumption"));
            append (marker_group);

            leather_box = new Box (Orientation.VERTICAL, 0);
            append (leather_box);

            refresh ();
        }

        public void sync_tool () {
            palette.set_active (canvas.tool);
            fill_actions ();
        }

        private Increment? find_inc (string name) {
            foreach (var i in pattern.increments) if (i.name == name) return i;
            return null;
        }

        private void fill_actions () {
            Dialogs.clear (action_box);
            var sel = canvas.selection;
            string[] tool_ids = { "select", "point", "curve", "piece", "notch", "drill", "grain", "dart", "pleat", "measure" };
            string[] tool_titles = { _("Select"), _("New Point"), _("New Curve"), _("New Piece"), _("Notch"), _("Drill Hole"), _("Grain Line"), _("Move Dart"), _("Pleat"), _("Measure") };
            string tool_title = tool_titles[0];
            for (int i = 0; i < tool_ids.length; i++) if (tool_ids[i] == canvas.tool) tool_title = tool_titles[i];
            var tg = new PreferencesGroup (tool_title);
            string hint = "";
            Button? go = null;
            switch (canvas.tool) {
                case "curve":
                    hint = _("Selected %d points. Select at least two, in order.").printf (sel.size);
                    go = new Button.with_label (_("Create Curve"));
                    go.sensitive = count_points () >= 2;
                    go.clicked.connect (() => {
                        string[] ids = {};
                        foreach (var id in sel) if (pattern.find_point (id) != null) ids += id;
                        canvas.history.checkpoint ();
                        var c = pattern.add_curve (ids, CurveKind.AUTO);
                        canvas.selection.clear ();
                        canvas.selection.add (c.id);
                        canvas.project.touch ("pattern");
                        canvas.selection_changed ();
                    });
                    break;
                case "piece":
                    hint = _("Selected %d points and curves. Go round the outline in order.").printf (sel.size);
                    go = new Button.with_label (_("Create Piece"));
                    go.sensitive = sel.size >= 3 || (sel.size >= 2 && count_points () < sel.size);
                    go.clicked.connect (() => {
                        canvas.history.checkpoint ();
                        var pc = new Piece (pattern.new_id ("d"), _("Piece %d").printf (pattern.pieces.size + 1));
                        foreach (var id in sel) pc.nodes.add (new PieceNode (id, pattern.find_curve (id) != null));
                        pc.seam_allowance = PathData.fmt (win.app.get_int ("default-seam-allowance", 10) / pattern.unit_mm (), 3);
                        pattern.pieces.add (pc);
                        canvas.selection.clear ();
                        canvas.selected_piece = pc.id;
                        canvas.project.touch ("pattern");
                        canvas.selection_changed ();
                    });
                    break;
                case "grain":
                    hint = _("Select two points, then choose the piece.");
                    go = new Button.with_label (_("Set Grain Line"));
                    go.sensitive = count_points () == 2 && canvas.selected_piece != null;
                    go.clicked.connect (() => {
                        var pc = pattern.find_piece (canvas.selected_piece);
                        if (pc == null) return;
                        canvas.history.checkpoint ();
                        pc.grain_a = sel[0];
                        pc.grain_b = sel[1];
                        canvas.project.touch ("pattern");
                    });
                    if (canvas.selected_piece == null) hint = _("Click inside a piece first, then Shift click two points.");
                    break;
                case "dart":
                    hint = _("Select the apex, the first leg, the second leg and the new position on the outline.");
                    go = new Button.with_label (_("Move Dart"));
                    go.sensitive = count_points () == 4;
                    go.clicked.connect (() => {
                        Piece? target = null;
                        foreach (var pc in pattern.pieces) foreach (var nd in pc.nodes) if (nd.ref_id == sel[0]) target = pc;
                        if (target == null) {
                            win.add_toast (new Toast (_("The apex must be a point of a piece outline")));
                            return;
                        }
                        canvas.history.checkpoint ();
                        try {
                            DartTools.transfer (pattern, target, sel[0], sel[1], sel[2], sel[3]);
                            canvas.project.touch ("pattern");
                            canvas.selection.clear ();
                            canvas.selection_changed ();
                        } catch (PatternOpError e) {
                            canvas.history.undo ();
                            win.add_toast (new Toast (e.message));
                        }
                    });
                    break;
                case "pleat":
                    hint = _("Select two points on the outline where the pleat line starts and ends.");
                    var depth = Dialogs.spin_row (tg, _("Depth"), 0.1, 30, 0.1, 2, 1, _("In %s").printf (pattern.unit));
                    var kind = Dialogs.choice_row (tg, _("Kind"), { _("Knife Pleat"), _("Box Pleat") }, 0);
                    go = new Button.with_label (_("Insert Pleat"));
                    go.sensitive = count_points () == 2;
                    go.clicked.connect (() => {
                        Piece? target = null;
                        foreach (var pc in pattern.pieces) foreach (var nd in pc.nodes) if (nd.ref_id == sel[0]) target = pc;
                        if (target == null) return;
                        canvas.history.checkpoint ();
                        try {
                            DartTools.insert_pleat (pattern, target, sel[0], sel[1], PathData.fmt (depth.value, 3), kind.selected == 1 ? "box" : "knife", false);
                            var r = pattern.evaluate ();
                            var g0 = r.piece (target.id);
                            if (g0 != null && canvas.result != null) {
                                var before = canvas.result.piece (target.id);
                                if (before != null && g0.area () < before.area ()) {
                                    canvas.history.undo ();
                                    canvas.history.checkpoint ();
                                    target = pattern.find_piece (target.id);
                                    DartTools.insert_pleat (pattern, target, sel[0], sel[1], PathData.fmt (depth.value, 3), kind.selected == 1 ? "box" : "knife", true);
                                }
                            }
                            canvas.project.touch ("pattern");
                            canvas.selection.clear ();
                            canvas.selection_changed ();
                        } catch (PatternOpError e) {
                            win.add_toast (new Toast (e.message));
                        }
                    });
                    break;
                case "point":
                    hint = _("Click on the canvas to place a point, or select existing points first to build from them.");
                    break;
                case "notch":
                    hint = _("Click a point of a piece to add or remove a notch there, or click an edge.");
                    break;
                case "measure":
                    hint = _("Drag between two points to measure.");
                    break;
                default:
                    hint = _("Click to select, Shift to add, drag base points to move them.");
                    break;
            }
            tg.description = hint;
            if (go != null) {
                go.add_css_class ("suggested-action");
                go.valign = Align.CENTER;
                tg.add_header_suffix (go);
            }
            action_box.append (tg);
        }

        private int count_points () {
            int n = 0;
            foreach (var id in canvas.selection) if (pattern.find_point (id) != null) n++;
            return n;
        }

        private string[] point_names () {
            string[] n = { _("None") };
            foreach (var p in pattern.points) n += p.name;
            return n;
        }

        private string[] curve_names () {
            string[] n = { _("None") };
            foreach (var c in pattern.curves) n += c.name;
            return n;
        }

        private Choice ref_row (PreferencesGroup g, string title, string current, bool curves) {
            var names = curves ? curve_names () : point_names ();
            int sel = 0;
            string cur_name = "";
            if (curves) {
                var c = pattern.find_curve (current);
                if (c != null) cur_name = c.name;
            } else {
                var p = pattern.find_point (current);
                if (p != null) cur_name = p.name;
            }
            for (int i = 0; i < names.length; i++) if (names[i] == cur_name && cur_name != "") sel = i;
            return Dialogs.choice_row (g, title, names, sel);
        }

        private string ref_id (Choice d, bool curves) {
            if (d.selected == 0) return "";
            int i = (int) d.selected - 1;
            if (curves) return i < pattern.curves.size ? pattern.curves[i].id : "";
            return i < pattern.points.size ? pattern.points[i].id : "";
        }

        private Entry formula_row (PreferencesGroup g, string title, string value, owned FormulaSet setter) {
            var row = new FieldRow (title);
            row.text = value;
            var e = row.field;
            e.add_css_class ("atelier-value");
            update_status (row, e.text);
            e.changed.connect (() => update_status (row, e.text));
            e.activate.connect (() => {
                canvas.history.checkpoint ();
                setter (e.text.strip ());
                canvas.project.touch ("pattern");
            });
            var focus = new EventControllerFocus ();
            focus.leave.connect (() => {
                if (e.text.strip () == value) return;
                canvas.history.checkpoint ();
                setter (e.text.strip ());
                canvas.project.touch ("pattern");
            });
            e.add_controller (focus);
            g.add_row (row);
            return e;
        }

        private delegate void FormulaSet (string text);

        private void update_status (ActionRow row, string text) {
            try {
                double v = pattern.eval_formula (text, pattern.active_size != "" ? pattern.active_size : pattern.table.base_size);
                row.subtitle = "= %s".printf (PathData.fmt (v, 3));
                row.remove_css_class ("atelier-formula-error");
            } catch (ExprError e) {
                row.subtitle = e.message;
                row.add_css_class ("atelier-formula-error");
            }
        }

        private void fill_inspector () {
            Dialogs.clear (inspector);
            if (canvas.selection.size == 1) {
                var p = pattern.find_point (canvas.selection[0]);
                if (p != null) {
                    point_inspector (p);
                    return;
                }
                var c = pattern.find_curve (canvas.selection[0]);
                if (c != null) {
                    curve_inspector (c);
                    return;
                }
            }
            if (canvas.selected_piece != null) {
                var pc = pattern.find_piece (canvas.selected_piece);
                if (pc != null) piece_inspector (pc);
            }
        }

        private void point_inspector (PatternPoint p) {
            var g = new PreferencesGroup (_("Point %s").printf (p.name), p.kind.label ());
            var name = Dialogs.entry_row (g, _("Name"), p.name);
            name.activate.connect (() => {
                string n = name.text.strip ();
                if (n == "" || n == p.name || pattern.point_by_name (n) != null) return;
                canvas.history.checkpoint ();
                p.name = n;
                canvas.project.touch ("pattern");
            });
            PointKind[] kinds = { PointKind.BASE, PointKind.END_LINE, PointKind.ALONG_LINE, PointKind.NORMAL, PointKind.MIDPOINT, PointKind.INTERSECT, PointKind.ALONG_CURVE, PointKind.FOOT, PointKind.ROTATE, PointKind.OFFSET, PointKind.BISECTOR, PointKind.CIRCLE_LINE, PointKind.XY, PointKind.LINE_AXIS, PointKind.CURVE_AXIS, PointKind.CIRCLE_CONTACT };
            string[] kl = {};
            int ksel = 0;
            for (int i = 0; i < kinds.length; i++) {
                kl += kinds[i].label ();
                if (kinds[i] == p.kind) ksel = i;
            }
            var kd = Dialogs.choice_row (g, _("Construction"), kl, ksel);
            kd.notify["selected"].connect (() => {
                var k = kinds[kd.selected];
                if (k == p.kind) return;
                canvas.history.checkpoint ();
                p.kind = k;
                canvas.project.touch ("pattern");
                Idle.add (() => {
                    fill_inspector ();
                    return Source.REMOVE;
                });
            });
            string[] labels_ref;
            bool[] curve_ref;
            string[] labels_f;
            describe (p.kind, out labels_ref, out curve_ref, out labels_f);
            string[] refs = { p.a, p.b, p.c, p.d };
            for (int i = 0; i < labels_ref.length; i++) {
                int idx = i;
                bool isc = curve_ref[i];
                var d = ref_row (g, labels_ref[i], refs[i], isc);
                d.notify["selected"].connect (() => {
                    string id = ref_id (d, isc);
                    if (id == p.id) return;
                    canvas.history.checkpoint ();
                    switch (idx) {
                        case 0: p.a = id; break;
                        case 1: p.b = id; break;
                        case 2: p.c = id; break;
                        default: p.d = id; break;
                    }
                    canvas.project.touch ("pattern");
                });
            }
            foreach (var f in labels_f) {
                switch (f) {
                    case "x": formula_row (g, _("X"), p.fx, (t) => p.fx = t); break;
                    case "y": formula_row (g, _("Y"), p.fy, (t) => p.fy = t); break;
                    case "length": formula_row (g, _("Length"), p.flength, (t) => p.flength = t); break;
                    case "angle": formula_row (g, _("Angle"), p.fangle, (t) => p.fangle = t); break;
                }
            }
            if (canvas.result != null && canvas.result.errors.has_key (p.id)) {
                var err = new ActionRow (_("Cannot Be Placed"), canvas.result.errors[p.id]);
                err.add_css_class ("atelier-formula-error");
                g.add_row (err);
            } else if (canvas.result != null && canvas.result.points.has_key (p.id)) {
                var at = canvas.result.points[p.id];
                var pos = new ActionRow (_("Position"), "%s, %s %s".printf (PathData.fmt (at.x / pattern.unit_mm (), 2), PathData.fmt (at.y / pattern.unit_mm (), 2), pattern.unit));
                g.add_row (pos);
            }
            var rule = Dialogs.spin_row (g, _("Grade Rule"), 0, 999, 1, p.rule, 0, _("Used when grading by rules"));
            rule.value_changed.connect (() => {
                p.rule = (int) rule.value;
                canvas.project.touch ("pattern");
            });
            var hidden = Dialogs.switch_row (g, _("Hide in the Draft"), p.hidden);
            hidden.notify["active"].connect (() => {
                p.hidden = hidden.active;
                canvas.queue_draw ();
            });
            var deps = pattern.dependents_of (p.id);
            if (deps.size > 0) g.description = "%s. %s.".printf (p.kind.label (), ngettext ("%d object depends on this point", "%d objects depend on this point", deps.size).printf (deps.size));
            inspector.append (g);
        }

        private void describe (PointKind k, out string[] refs, out bool[] curve, out string[] formulas) {
            switch (k) {
                case PointKind.END_LINE: refs = { _("From") }; curve = { false }; formulas = { "length", "angle" }; break;
                case PointKind.ALONG_LINE: refs = { _("From"), _("Towards") }; curve = { false, false }; formulas = { "length" }; break;
                case PointKind.NORMAL: refs = { _("From"), _("Line To") }; curve = { false, false }; formulas = { "length", "angle" }; break;
                case PointKind.MIDPOINT: refs = { _("First"), _("Second") }; curve = { false, false }; formulas = {}; break;
                case PointKind.INTERSECT: refs = { _("Line 1 Start"), _("Line 1 End"), _("Line 2 Start"), _("Line 2 End") }; curve = { false, false, false, false }; formulas = {}; break;
                case PointKind.ALONG_CURVE: refs = { _("Curve") }; curve = { true }; formulas = { "length" }; break;
                case PointKind.FOOT: refs = { _("Line Start"), _("Line End"), _("Point") }; curve = { false, false, false }; formulas = {}; break;
                case PointKind.ROTATE: refs = { _("Point"), _("Centre") }; curve = { false, false }; formulas = { "angle" }; break;
                case PointKind.OFFSET: refs = { _("From") }; curve = { false }; formulas = { "x", "y" }; break;
                case PointKind.BISECTOR: refs = { _("First"), _("Vertex"), _("Third") }; curve = { false, false, false }; formulas = { "length" }; break;
                case PointKind.CIRCLE_LINE: refs = { _("Line Start"), _("Line End"), _("Centre") }; curve = { false, false, false }; formulas = { "length" }; break;
                case PointKind.XY: refs = { _("X From"), _("Y From") }; curve = { false, false }; formulas = {}; break;
                case PointKind.LINE_AXIS: refs = { _("Line Start"), _("Line End"), _("Axis Through") }; curve = { false, false, false }; formulas = { "angle" }; break;
                case PointKind.CURVE_AXIS: refs = { _("Axis Through"), _("Curve") }; curve = { false, true }; formulas = { "angle" }; break;
                case PointKind.CIRCLE_CONTACT: refs = { _("Line Start"), _("Line End"), _("Centre") }; curve = { false, false, false }; formulas = { "length" }; break;
                default: refs = {}; curve = {}; formulas = { "x", "y" }; break;
            }
        }

        private void curve_inspector (PatternCurve c) {
            var g = new PreferencesGroup (_("Curve %s").printf (c.name));
            var name = Dialogs.entry_row (g, _("Name"), c.name);
            name.activate.connect (() => {
                string n = name.text.strip ();
                if (n == "" || pattern.curve_by_name (n) != null) return;
                canvas.history.checkpoint ();
                c.name = n;
                canvas.project.touch ("pattern");
            });
            var kd = Dialogs.choice_row (g, _("Shape"), { _("Straight Lines"), _("Handles"), _("Smooth Through Points"), _("Part of a Curve") }, (int) c.kind);
            kd.notify["selected"].connect (() => {
                canvas.history.checkpoint ();
                c.kind = (CurveKind) kd.selected;
                canvas.project.touch ("pattern");
                Idle.add (() => {
                    fill_inspector ();
                    return Source.REMOVE;
                });
            });
            if (c.kind == CurveKind.AUTO) formula_row (g, _("Tension"), c.tension, (t) => c.tension = t);
            if (c.kind == CurveKind.AUTO || c.kind == CurveKind.PATH) formula_row (g, _("Fixed Length"), c.target_length, (t) => c.target_length = t);
            if (canvas.result != null && canvas.result.curves.has_key (c.id)) {
                double l = 0;
                foreach (var bz in canvas.result.curves[c.id]) l += bz.length ();
                g.add_row (new ActionRow (_("Length"), "%s %s".printf (PathData.fmt (l / pattern.unit_mm (), 2), pattern.unit)));
            }
            inspector.append (g);
            if (c.kind == CurveKind.PATH) {
                for (int i = 0; i < c.knots.size; i++) {
                    var k = c.knots[i];
                    var pt = pattern.find_point (k.point);
                    var kg = new PreferencesGroup (_("Through %s").printf (pt != null ? pt.name : k.point));
                    if (i > 0) {
                        formula_row (kg, _("Handle In Angle"), k.angle_in, (t) => k.angle_in = t);
                        formula_row (kg, _("Handle In Length"), k.len_in, (t) => k.len_in = t);
                    }
                    if (i < c.knots.size - 1) {
                        formula_row (kg, _("Handle Out Angle"), k.angle_out, (t) => k.angle_out = t);
                        formula_row (kg, _("Handle Out Length"), k.len_out, (t) => k.len_out = t);
                    }
                    inspector.append (kg);
                }
            }
        }

        private void piece_inspector (Piece pc) {
            var g = new PreferencesGroup (_("Piece %s").printf (pc.name));
            var name = Dialogs.entry_row (g, _("Name"), pc.name);
            name.changed.connect (() => {
                pc.name = name.text;
                canvas.queue_draw ();
            });
            var code = Dialogs.entry_row (g, _("Code"), pc.code);
            code.changed.connect (() => pc.code = code.text);
            string[] mats = { "fabric", "lining", "interfacing", "leather", "reinforcement", "trim" };
            string[] matl = { _("Fabric"), _("Lining"), _("Interfacing"), _("Leather"), _("Reinforcement"), _("Trim") };
            int ms = 0;
            for (int i = 0; i < mats.length; i++) if (mats[i] == pc.material) ms = i;
            var mat = Dialogs.choice_row (g, _("Material"), matl, ms);
            mat.notify["selected"].connect (() => {
                canvas.history.checkpoint ();
                pc.material = mats[mat.selected];
                canvas.project.touch ("pattern");
            });
            var qty = Dialogs.spin_row (g, _("Cut Quantity"), 1, 99, 1, pc.quantity, 0);
            qty.value_changed.connect (() => {
                pc.quantity = (int) qty.value;
                canvas.project.touch ("pattern");
            });
            var pair = Dialogs.switch_row (g, _("Cut in Pairs"), pc.pair, _("Mirrored left and right"));
            pair.notify["active"].connect (() => {
                pc.pair = pair.active;
                canvas.project.touch ("pattern");
            });
            var fold = Dialogs.switch_row (g, _("On Fold"), pc.on_fold);
            fold.notify["active"].connect (() => {
                canvas.history.checkpoint ();
                pc.on_fold = fold.active;
                if (pc.on_fold && pc.fold_edge < 0) pc.fold_edge = 0;
                canvas.project.touch ("pattern");
            });
            var fe = Dialogs.spin_row (g, _("Fold Edge"), 0, 99, 1, int.max (0, pc.fold_edge), 0);
            fe.value_changed.connect (() => {
                pc.fold_edge = (int) fe.value;
                canvas.project.touch ("pattern");
            });
            formula_row (g, _("Seam Allowance"), pc.seam_allowance, (t) => pc.seam_allowance = t);
            var builtin = Dialogs.switch_row (g, _("Allowance Included"), pc.built_in, _("The outline is already the cutting line"));
            builtin.notify["active"].connect (() => {
                canvas.history.checkpoint ();
                pc.built_in = builtin.active;
                canvas.project.touch ("pattern");
            });
            string[] places = { "front", "back", "sleeve", "left", "right" };
            string[] placel = { _("Front"), _("Back"), _("Sleeve"), _("Left Side"), _("Right Side") };
            int ps = 0;
            for (int i = 0; i < places.length; i++) if (places[i] == pc.placement) ps = i;
            var place = Dialogs.choice_row (g, _("3D Placement"), placel, ps);
            place.notify["selected"].connect (() => pc.placement = places[place.selected]);
            var ga = Dialogs.spin_row (g, _("Grain Angle"), -180, 180, 5, pc.grain_angle, 0, _("When no grain points are set"));
            ga.value_changed.connect (() => {
                pc.grain_angle = ga.value;
                canvas.project.touch ("pattern");
            });
            var arrows = Dialogs.choice_row (g, _("Grain Arrows"), { _("Both Ends"), _("Top"), _("Bottom") }, pc.grain_arrows);
            arrows.notify["selected"].connect (() => {
                pc.grain_arrows = (int) arrows.selected;
                canvas.queue_draw ();
            });
            var label = Dialogs.entry_row (g, _("Label"), pc.label.replace ("\n", " | "), "{name} | {size} | {cut}");
            label.activate.connect (() => {
                pc.label = label.text.replace (" | ", "\n").replace ("|", "\n");
                canvas.queue_draw ();
            });
            inspector.append (g);
            if (pc.is_fixed ()) return;
            var ng = new PreferencesGroup (_("Outline"), _("Allowance after each node, corner style and notches"));
            for (int i = 0; i < pc.nodes.size; i++) {
                var nd = pc.nodes[i];
                string label_text;
                if (nd.is_curve) {
                    var c = pattern.find_curve (nd.ref_id);
                    label_text = c != null ? c.name : nd.ref_id;
                } else {
                    var p = pattern.find_point (nd.ref_id);
                    label_text = p != null ? p.name : nd.ref_id;
                }
                string? row_sub = null;
                if (nd.sa_after != "") row_sub = _("Allowance %s").printf (nd.sa_after);
                string row_title = "%d. %s".printf (i, label_text);
                var row = new ExpanderRow (row_title, row_sub);
                var sa = new EntryRow (_("Allowance After"));
                sa.text = nd.sa_after;
                sa.entry_changed.connect (() => nd.sa_after = sa.text.strip ());
                sa.entry_activated.connect (() => canvas.project.touch ("pattern"));
                row.add_row (sa);
                var corner = new Choice (_("Corner"), { _("Intersect"), _("Square"), _("Bevel"), _("Round") }, (int) nd.corner);
                corner.notify["selected"].connect (() => {
                    canvas.history.checkpoint ();
                    nd.corner = (CornerStyle) corner.selected;
                    canvas.project.touch ("pattern");
                });
                row.add_row (corner.row);
                if (!nd.is_curve) {
                    string[] ids = { "", "slit", "t", "v", "castle", "check" };
                    int nsel = 0;
                    if (nd.notch) for (int k = 1; k < ids.length; k++) if (ids[k] == nd.notch_type) nsel = k;
                    var notch = new Choice (_("Notch"), { _("None"), _("Slit"), _("T"), _("V"), _("Castle"), _("Check") }, nsel);
                    notch.notify["selected"].connect (() => {
                        canvas.history.checkpoint ();
                        nd.notch = notch.selected > 0;
                        if (nd.notch) nd.notch_type = ids[notch.selected];
                        canvas.project.touch ("pattern");
                    });
                    row.add_row (notch.row);
                } else {
                    var rev = new SwitchRow (_("Reverse"), null, nd.reverse);
                    rev.switch_btn.notify["active"].connect (() => {
                        nd.reverse = rev.switch_btn.active;
                        canvas.project.touch ("pattern");
                    });
                    row.add_row (rev);
                }
                ng.add_row (row);
            }
            inspector.append (ng);
        }

        private void fill_increments () {
            increments_group.clear ();
            foreach (var inc in pattern.increments) {
                var i = inc;
                formula_row (increments_group, "#" + inc.name, inc.formula, (t) => i.formula = t);
            }
        }

        private void fill_seams () {
            seams_group.clear ();
            var r = canvas.result;
            keep_seams.visible = false;
            if (r == null) return;
            var pairs = canvas.project.garment.seams.size > 0 ? canvas.project.garment.seams : Seams.guess_pairs (r);
            if (pairs.size == 0) {
                seams_group.add_row (new ActionRow (_("No Matching Seams"), _("No edges of the same length were found between pieces")));
                return;
            }
            keep_seams.visible = canvas.project.garment.seams.size == 0;
            foreach (var pair in pairs) {
                var chk = Seams.walk (r, pair);
                if (chk == null) continue;
                var pa = pattern.find_piece (pair.piece_a);
                var pb = pattern.find_piece (pair.piece_b);
                double diff = chk.difference () / pattern.unit_mm ();
                var p2 = pair;
                Dialogs.button_row (seams_group, "%s %d, %s %d".printf (pa != null ? pa.name : "", pair.edge_a, pb != null ? pb.name : "", pair.edge_b),
                    _("%s and %s %s, difference %s").printf (PathData.fmt (chk.length_a / pattern.unit_mm (), 2), PathData.fmt (chk.length_b / pattern.unit_mm (), 2), pattern.unit, PathData.fmt (diff, 2)),
                    _("Walk"), () => canvas.start_walk (p2));
            }
        }

        private void fill_marker () {
            var g = marker_group;
            g.clear ();
            var m = canvas.project.marker;
            var width = Dialogs.spin_row (g, _("Fabric Width"), 20, 400, 1, m.fabric_width / 10, 0, _("In centimetres"));
            width.value_changed.connect (() => m.fabric_width = width.value * 10);
            var rot = Dialogs.choice_row (g, _("Rotation"), { _("None"), _("Half Turn"), _("Quarter Turns") }, m.rotations == "0" ? 0 : (m.rotations == "90" ? 2 : 1));
            rot.notify["selected"].connect (() => m.rotations = rot.selected == 0 ? "0" : (rot.selected == 2 ? "90" : "180"));
            var mat = Dialogs.choice_row (g, _("Material"), { _("Fabric"), _("Lining"), _("Leather"), _("All") }, m.material == "lining" ? 1 : (m.material == "leather" ? 2 : (m.material == "" ? 3 : 0)));
            mat.notify["selected"].connect (() => m.material = mat.selected == 1 ? "lining" : (mat.selected == 2 ? "leather" : (mat.selected == 3 ? "" : "fabric")));
            var ratio = new ExpanderRow (_("Size Ratio"), _("Garments of each size in the lay"));
            foreach (var s in pattern.all_sizes ()) {
                string size = s;
                var r = new SpinRow (size, null, 0, 20, 1, m.ratio.has_key (size) ? m.ratio[size] : 0);
                r.spin_btn.value_changed.connect (() => {
                    if ((int) r.value == 0) m.ratio.unset (size);
                    else m.ratio[size] = (int) r.value;
                });
                ratio.add_row (r);
            }
            g.add_row (ratio);
        }

        private void fill_leather () {
            Dialogs.clear (leather_box);
            if (canvas.selected_piece == null || canvas.result == null) return;
            var pc = pattern.find_piece (canvas.selected_piece);
            var geom = canvas.result.piece (canvas.selected_piece);
            if (pc == null || geom == null) return;
            var g = new PreferencesGroup (_("Leather and Bags"), _("For %s").printf (pc.name));
            var th = Dialogs.spin_row (g, _("Thickness"), 0, 10, 0.1, pc.thickness, 1, _("In millimetres"));
            th.value_changed.connect (() => pc.thickness = th.value);
            var turn = Dialogs.spin_row (g, _("Turned Edge"), 0, 30, 0.5, pc.leather_turn != "" ? double.parse (pc.leather_turn) * pattern.unit_mm () : 12, 1, _("Width of the turn in millimetres, thickness is added"));
            var apply = new ActionRow (_("Turn Allowance"));
            var ab = new Button.with_label (_("Apply"));
            ab.valign = Align.CENTER;
            ab.clicked.connect (() => {
                canvas.history.checkpoint ();
                Leather.apply_turn (pattern, pc, PathData.fmt (turn.value / pattern.unit_mm (), 3));
                canvas.project.touch ("pattern");
            });
            apply.add_suffix (ab);
            g.add_row (apply);
            var skive = Dialogs.spin_row (g, _("Skiving Width"), 0, 40, 0.5, pc.leather_skive != "" ? double.parse (pc.leather_skive) * pattern.unit_mm () : 8, 1, _("Shown as an internal line, in millimetres"));
            skive.value_changed.connect (() => pc.leather_skive = PathData.fmt (skive.value / pattern.unit_mm (), 3));
            var reinf = new ActionRow (_("Reinforcement"), _("A smaller piece inside this one"));
            var rb = new Button.with_label (_("Create"));
            rb.valign = Align.CENTER;
            rb.clicked.connect (() => {
                canvas.history.checkpoint ();
                Leather.reinforcement (pattern, geom, 5);
                canvas.project.touch ("pattern");
            });
            reinf.add_suffix (rb);
            g.add_row (reinf);
            var lining = new ActionRow (_("Lining"), _("A lining piece with its own allowance"));
            var lb = new Button.with_label (_("Create"));
            lb.valign = Align.CENTER;
            lb.clicked.connect (() => {
                canvas.history.checkpoint ();
                Leather.lining (pattern, geom, 2);
                canvas.project.touch ("pattern");
            });
            lining.add_suffix (lb);
            g.add_row (lining);
            leather_box.append (g);
        }

        private void solid_dialog (string kind) {
            Box body;
            SpinButton? a = null, b = null, c = null, sa = null;
            var dlg = Dialogs.form (win, _("Develop a Solid"), _("Create Pieces"), out body, () => {
                canvas.history.checkpoint ();
                double u = pattern.unit_mm ();
                Gee.List<Piece> made;
                switch (kind) {
                    case "cylinder": made = Solid.cylinder (pattern, a.value * u, b.value * u, sa.value * u); break;
                    case "cone": made = Solid.truncated_cone (pattern, a.value * u, b.value * u, c.value * u, sa.value * u); break;
                    default: made = Solid.box_bag (pattern, a.value * u, b.value * u, c.value * u, kind, sa.value * u); break;
                }
                double x = 0;
                var r0 = PatternRenderer.pieces_bounds (canvas.result, true);
                foreach (var pc in made) {
                    pc.place_x = (r0.is_empty () ? 0 : r0.x2 () + 50) + x;
                    pc.material = canvas.project.trade == "leather" ? "leather" : "fabric";
                    var g0 = pattern.evaluate ().piece (pc.id);
                    x += g0 != null ? g0.bounds ().w + 30 : 300;
                }
                canvas.project.touch ("pattern");
                canvas.switch_mode ("pieces");
            });
            var g = new PreferencesGroup (_("Dimensions"), _("Sizes in %s").printf (pattern.unit));
            if (kind == "cylinder") {
                a = Dialogs.spin_row (g, _("Diameter"), 1, 500, 0.5, 30, 1);
                b = Dialogs.spin_row (g, _("Length"), 1, 500, 0.5, 50, 1);
            } else if (kind == "cone") {
                a = Dialogs.spin_row (g, _("Top Diameter"), 1, 500, 0.5, 30, 1);
                b = Dialogs.spin_row (g, _("Bottom Diameter"), 1, 500, 0.5, 22, 1);
                c = Dialogs.spin_row (g, _("Height"), 1, 500, 0.5, 28, 1);
            } else {
                a = Dialogs.spin_row (g, _("Width"), 1, 500, 0.5, 40, 1);
                b = Dialogs.spin_row (g, _("Height"), 1, 500, 0.5, 35, 1);
                c = Dialogs.spin_row (g, _("Depth"), 1, 500, 0.5, 12, 1);
            }
            sa = Dialogs.spin_row (g, _("Seam Allowance"), 0, 10, 0.1, 1, 1);
            body.append (g);
            dlg.present ();
        }

        private void new_point_dialog (double x, double y) {
            var sel = new Gee.ArrayList<string> ();
            foreach (var id in canvas.selection) if (pattern.find_point (id) != null) sel.add (id);
            Box body;
            Choice? kind = null;
            Entry? len = null, ang = null;
            PointKind[] kinds;
            if (sel.size == 0) kinds = { PointKind.BASE };
            else if (sel.size == 1) kinds = { PointKind.END_LINE, PointKind.OFFSET };
            else if (sel.size == 2) kinds = { PointKind.ALONG_LINE, PointKind.MIDPOINT, PointKind.NORMAL, PointKind.XY };
            else if (sel.size == 3) kinds = { PointKind.FOOT, PointKind.BISECTOR, PointKind.CIRCLE_LINE };
            else kinds = { PointKind.INTERSECT };
            var dlg = Dialogs.form (win, _("New Point"), _("Create"), out body, () => {
                var k = kinds[kind.selected];
                canvas.history.checkpoint ();
                var p = pattern.add_point (k);
                double um = pattern.unit_mm ();
                if (sel.size > 0) p.a = sel[0];
                if (sel.size > 1) p.b = sel[1];
                if (sel.size > 2) p.c = sel[2];
                if (sel.size > 3) p.d = sel[3];
                switch (k) {
                    case PointKind.BASE:
                        p.fx = PathData.fmt (x / um, 2);
                        p.fy = PathData.fmt (y / um, 2);
                        break;
                    case PointKind.OFFSET:
                        p.fx = len.text != "" ? len.text : "0";
                        p.fy = ang.text != "" ? ang.text : "0";
                        break;
                    case PointKind.FOOT:
                        p.a = sel[1];
                        p.b = sel[2];
                        p.c = sel[0];
                        break;
                    case PointKind.CIRCLE_LINE:
                        p.a = sel[1];
                        p.b = sel[2];
                        p.c = sel[0];
                        p.flength = len.text != "" ? len.text : "10";
                        break;
                    default:
                        p.flength = len.text != "" ? len.text : "10";
                        p.fangle = ang.text != "" ? ang.text : "0";
                        break;
                }
                canvas.selection.clear ();
                canvas.selection.add (p.id);
                canvas.project.touch ("pattern");
                canvas.selection_changed ();
            });
            string gdesc = _("A free point where you clicked");
            if (sel.size > 0) gdesc = _("Built from %d selected points").printf (sel.size);
            var g = new PreferencesGroup (_("Point"), gdesc);
            string[] labels = {};
            foreach (var k in kinds) labels += k.label ();
            kind = Dialogs.choice_row (g, _("Construction"), labels, 0);
            len = Dialogs.entry_row (g, _("Length or X"), "", _("A number or a formula such as bust_circ / 4"));
            ang = Dialogs.entry_row (g, _("Angle or Y"), "", _("Degrees, 0 is right and 90 is up"));
            body.append (g);
            dlg.present ();
        }

        private void rules_dialog () {
            var dlg = new AppDialog (win.application, true, false);
            dlg.set_title (_("Grade Rules"));
            dlg.transient_for = win;
            dlg.set_default_size (720, 520);
            var scroll = new ScrolledWindow ();
            scroll.vexpand = true;
            var grid = new Grid ();
            grid.row_spacing = 4;
            grid.column_spacing = 6;
            grid.margin_start = 12;
            grid.margin_end = 12;
            grid.margin_top = 8;
            grid.margin_bottom = 12;
            var sizes = pattern.table.sizes;
            var head = new Label (_("Rule"));
            head.add_css_class ("heading");
            grid.attach (head, 0, 0);
            for (int i = 1; i < sizes.size; i++) {
                var l = new Label (_("%s to %s").printf (sizes[i - 1], sizes[i]));
                l.add_css_class ("heading");
                grid.attach (l, i, 0);
            }
            int row = 1;
            foreach (var r in pattern.rules.rules) {
                var rl = new Label ("%d %s".printf (r.number, r.name));
                rl.halign = Align.START;
                grid.attach (rl, 0, row);
                for (int i = 1; i < sizes.size; i++) {
                    var st = r.step (sizes[i]);
                    var e = new Entry ();
                    e.width_chars = 9;
                    e.text = "%s, %s".printf (PathData.fmt (st.x / pattern.unit_mm (), 2), PathData.fmt (-st.y / pattern.unit_mm (), 2));
                    string size = sizes[i];
                    var rule = r;
                    e.changed.connect (() => {
                        var parts = e.text.split (",");
                        if (parts.length != 2) return;
                        double dx = 0, dy = 0;
                        bool okx = double.try_parse (parts[0].strip (), out dx);
                        bool oky = double.try_parse (parts[1].strip (), out dy);
                        if (okx && oky) rule.set_step (size, dx * pattern.unit_mm (), -dy * pattern.unit_mm ());
                    });
                    grid.attach (e, i, row);
                }
                row++;
            }
            scroll.child = grid;
            scroll.hscrollbar_policy = PolicyType.AUTOMATIC;
            scroll.min_content_height = 300;
            var group = new PreferencesGroup (_("Increments"), _("Each cell is the X, Y increment from the previous size, Y pointing up, in %s.").printf (pattern.unit));
            group.vexpand = true;
            group.margin_start = 18;
            group.margin_end = 18;
            group.add_row (scroll);
            dlg.content_box.append (group);
            var bb = new Box (Orientation.HORIZONTAL, 8);
            bb.halign = Align.END;
            bb.margin_end = 18;
            bb.margin_bottom = 18;
            bb.margin_top = 8;
            var done = new Button.with_label (_("Done"));
            done.add_css_class ("suggested-action");
            dlg.set_cancel_button (done);
            done.clicked.connect (() => {
                canvas.project.touch ("pattern");
                dlg.close_dialog ();
            });
            bb.append (done);
            dlg.content_box.append (bb);
            canvas.history.checkpoint ();
            dlg.present ();
        }
    }
}
