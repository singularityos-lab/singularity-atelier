using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class CurveEditor : DrawingArea {
        public ResponseCurve curve;
        public signal void changed ();
        private int drag = -1;

        public CurveEditor (ResponseCurve curve) {
            this.curve = curve;
            set_size_request (120, 120);
            halign = Align.CENTER;
            set_draw_func ((a, cr, w, h) => {
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.12);
                cr.rectangle (0, 0, w, h);
                cr.fill ();
                cr.set_source_rgba (0.5, 0.5, 0.5, 0.35);
                cr.set_line_width (1);
                cr.move_to (0, h);
                cr.line_to (w, 0);
                cr.stroke ();
                cr.set_source_rgba (0.2, 0.45, 0.9, 1);
                cr.set_line_width (2);
                for (int i = 0; i <= 40; i++) {
                    double x = i / 40.0;
                    double y = this.curve.map (x);
                    if (i == 0) cr.move_to (x * w, h - y * h);
                    else cr.line_to (x * w, h - y * h);
                }
                cr.stroke ();
                handle (cr, this.curve.x1 * w, h - this.curve.y1 * h);
                handle (cr, this.curve.x2 * w, h - this.curve.y2 * h);
            });
            var g = new GestureDrag ();
            g.drag_begin.connect ((x, y) => {
                int w = get_width (), h = get_height ();
                double d1 = Math.hypot (x - this.curve.x1 * w, y - (h - this.curve.y1 * h));
                double d2 = Math.hypot (x - this.curve.x2 * w, y - (h - this.curve.y2 * h));
                drag = d1 < d2 ? 0 : 1;
            });
            g.drag_update.connect ((dx, dy) => {
                double sx, sy;
                g.get_start_point (out sx, out sy);
                int w = get_width (), h = get_height ();
                double x = ((sx + dx) / w).clamp (0, 1), y = (1 - (sy + dy) / h).clamp (0, 1);
                if (drag == 0) {
                    this.curve.x1 = x;
                    this.curve.y1 = y;
                } else {
                    this.curve.x2 = x;
                    this.curve.y2 = y;
                }
                queue_draw ();
                changed ();
            });
            add_controller (g);
        }

        private static void handle (Cairo.Context cr, double x, double y) {
            cr.arc (x, y, 5, 0, 2 * Math.PI);
            cr.set_source_rgba (1, 1, 1, 1);
            cr.fill_preserve ();
            cr.set_source_rgba (0.2, 0.45, 0.9, 1);
            cr.stroke ();
        }
    }

    public class SketchPanel : InspectorPanel {
        private AtelierWindow win;
        private SketchCanvas canvas;
        public ToolPalette palette { get; private set; }
        private PreferencesGroup brushes_group;
        private LayerList layer_list;
        private Box selection_box;
        private SpinButton size_spin;
        private SpinButton opacity_spin;
        private CurveEditor curve_editor;
        private ColorPickerButton color_btn;
        private ColorPickerButton color2_btn;
        private Box swatches;
        private bool syncing;

        public SketchPanel (AtelierWindow win, SketchCanvas canvas) {
            this.win = win;
            this.canvas = canvas;
            build ();
            canvas.selection_changed.connect (() => fill_selection ());
            canvas.color_picked.connect ((c) => {
                syncing = true;
                color_btn.color = Dialogs.to_gdk (c);
                syncing = false;
            });
            canvas.layers_changed.connect (() => fill_layers ());
            canvas.project.changed.connect ((what) => {
                if (what == "sketch") fill_layers ();
            });
        }

        public void refresh () {
            fill_brushes ();
            fill_layers ();
            fill_swatches ();
            fill_selection ();
        }

        public void sync_tool () {
            palette.set_active (canvas.tool);
        }

        private void build () {
            palette = new ToolPalette ();
            string[,] list = {
                { "brush", "atelier-brush-symbolic", _("Brush (B)") }, { "eraser", "atelier-eraser-symbolic", _("Eraser (E)") },
                { "select", "atelier-lasso-symbolic", _("Select and Transform (V)") }, { "edit", "atelier-pen-symbolic", _("Edit Strokes") },
                { "liquify", "atelier-transform-symbolic", _("Liquify") }, { "fill", "atelier-bucket-symbolic", _("Fill (G)") },
                { "gradient", "atelier-fill-symbolic", _("Gradient") }, { "picker", "atelier-picker-symbolic", _("Pick Colour") },
                { "guide", "atelier-ruler-symbolic", _("Move Guides") }, { "tape", "atelier-tape-symbolic", _("Tape Drawing") }
            };
            for (int i = 0; i < list.length[0]; i++) palette.add_tool (list[i, 0], list[i, 1], list[i, 2]);
            palette.set_active (canvas.tool);
            palette.tool_selected.connect ((id) => {
                canvas.tool = id;
                canvas.queue_draw ();
            });

            var cg = new PreferencesGroup (_("Colour"));
            var crow = new ActionRow (_("Stroke and Fill"));
            color_btn = new ColorPickerButton (Dialogs.to_gdk (canvas.color));
            color_btn.valign = Align.CENTER;
            color_btn.color_changed.connect ((c) => {
                if (syncing) return;
                canvas.color = Dialogs.from_gdk (c);
                if (canvas.selection.size > 0) canvas.recolor_selection (canvas.color);
            });
            crow.add_suffix (color_btn);
            cg.add_row (crow);
            var crow2 = new ActionRow (_("Gradient End"));
            color2_btn = new ColorPickerButton (Dialogs.to_gdk (canvas.color2));
            color2_btn.valign = Align.CENTER;
            color2_btn.color_changed.connect ((c) => canvas.color2 = Dialogs.from_gdk (c));
            crow2.add_suffix (color2_btn);
            cg.add_row (crow2);
            var radial = Dialogs.switch_row (cg, _("Radial Gradient"), false);
            radial.notify["active"].connect (() => canvas.radial_gradient = radial.active);
            swatches = new Box (Orientation.HORIZONTAL, 6);
            swatches.margin_top = 10;
            swatches.margin_bottom = 10;
            swatches.margin_start = 12;
            swatches.margin_end = 12;
            var sw_scroll = new ScrolledWindow ();
            sw_scroll.vscrollbar_policy = PolicyType.NEVER;
            sw_scroll.child = swatches;
            cg.add_row (sw_scroll);
            append (cg);

            brushes_group = new PreferencesGroup (_("Brushes"));
            append (brushes_group);

            var bg = new PreferencesGroup (_("Stroke"));
            size_spin = Dialogs.spin_row (bg, _("Size"), 0.2, 400, 0.2, canvas.brush.size, 1);
            size_spin.value_changed.connect (() => {
                canvas.brush.size = size_spin.value;
                canvas.brush.min_size = double.min (canvas.brush.min_size, canvas.brush.size);
            });
            opacity_spin = Dialogs.spin_row (bg, _("Opacity"), 1, 100, 1, canvas.brush.opacity * 100, 0);
            opacity_spin.value_changed.connect (() => canvas.brush.opacity = opacity_spin.value / 100);
            var stab = Dialogs.spin_row (bg, _("Stabilizer"), 0, 95, 5, canvas.stabilizer * 100, 0);
            stab.value_changed.connect (() => canvas.stabilizer = stab.value / 100);
            var hold = Dialogs.switch_row (bg, _("Hold to Straighten"), canvas.hold_to_shape, _("Keep the pen still to get a line, arc or ellipse"));
            hold.notify["active"].connect (() => canvas.hold_to_shape = hold.active);
            var pred = Dialogs.switch_row (bg, _("Predictive Stroke"), canvas.predictive, _("Smooth curves when the pen is lifted"));
            pred.notify["active"].connect (() => canvas.predictive = pred.active);
            var tilt = Dialogs.spin_row (bg, _("Tilt Widens"), 0, 3, 0.1, canvas.brush.tilt_size, 1);
            tilt.value_changed.connect (() => canvas.brush.tilt_size = tilt.value);
            var speed = Dialogs.spin_row (bg, _("Speed Thins"), 0, 1, 0.05, canvas.brush.velocity_thin, 2);
            speed.value_changed.connect (() => canvas.brush.velocity_thin = speed.value);
            var curve_row = new ActionRow (_("Pressure Response"), _("Drag the two handles"));
            curve_editor = new CurveEditor (canvas.brush.pressure_curve);
            curve_editor.set_size_request (96, 96);
            curve_editor.valign = Align.CENTER;
            curve_editor.changed.connect (() => canvas.brush.pressure_curve = curve_editor.curve);
            curve_row.add_suffix (curve_editor);
            bg.add_row (curve_row);
            append (bg);

            var gg = new PreferencesGroup (_("Guides"));
            var g = canvas.project.sketch.guides;
            var ruler = Dialogs.switch_row (gg, _("Ruler"), g.ruler_on);
            ruler.notify["active"].connect (() => {
                canvas.project.sketch.guides.ruler_on = ruler.active;
                place_guides ();
            });
            var ell = Dialogs.switch_row (gg, _("Ellipse"), g.ellipse_on);
            ell.notify["active"].connect (() => {
                canvas.project.sketch.guides.ellipse_on = ell.active;
                place_guides ();
            });
            var curve = Dialogs.switch_row (gg, _("French Curve"), g.curve_on);
            curve.notify["active"].connect (() => {
                canvas.project.sketch.guides.curve_on = curve.active;
                place_guides ();
            });
            string[] labels = {};
            foreach (var id in FrenchCurves.IDS) labels += FrenchCurves.label (id);
            var tmpl = Dialogs.choice_row (gg, _("Curve"), labels, 0);
            tmpl.notify["selected"].connect (() => {
                canvas.project.sketch.guides.curve_template = FrenchCurves.IDS[tmpl.selected];
                canvas.queue_draw ();
            });
            Dialogs.button_row (gg, _("Curve from Selection"), _("Use the selected stroke as a free-form guide"), _("Use"), () => {
                foreach (var st in canvas.selection) {
                    var pd = new PathData ();
                    pd.add_polygon (st.centers (), false);
                    var gd = canvas.project.sketch.guides;
                    gd.custom_curve = pd;
                    gd.curve_template = "custom";
                    gd.curve_pos = Point (0, 0);
                    gd.curve_angle = 0;
                    gd.curve_scale = 1;
                    gd.curve_on = true;
                    curve.active = true;
                    break;
                }
                canvas.queue_draw ();
            });
            var persp = Dialogs.choice_row (gg, _("Perspective"), { _("Off"), _("1 Point"), _("2 Points"), _("3 Points") }, g.perspective.clamp (0, 3));
            persp.notify["selected"].connect (() => {
                var gd = canvas.project.sketch.guides;
                gd.perspective = (int) persp.selected;
                var v = canvas.visible_doc ();
                if (gd.perspective == 1) gd.vp1 = Point (v.cx (), v.y + v.h * 0.4);
                if (gd.perspective >= 2) {
                    gd.vp1 = Point (v.x - v.w * 0.2, v.y + v.h * 0.4);
                    gd.vp2 = Point (v.x2 () + v.w * 0.2, v.y + v.h * 0.4);
                }
                if (gd.perspective == 3) gd.vp3 = Point (v.cx (), v.y2 () + v.h * 1.5);
                canvas.queue_draw ();
            });
            string[] sym_ids = { "none", "vertical", "horizontal", "radial" };
            int sym_sel = 0;
            for (int i = 0; i < sym_ids.length; i++) if (sym_ids[i] == g.symmetry.to_id ()) sym_sel = i;
            var sym = Dialogs.choice_row (gg, _("Symmetry"), { _("Off"), _("Vertical"), _("Horizontal"), _("Radial") }, sym_sel);
            sym.notify["selected"].connect (() => {
                var gd = canvas.project.sketch.guides;
                gd.symmetry = SymmetryMode.from_id (sym_ids[sym.selected]);
                var v = canvas.visible_doc ();
                gd.symmetry_center = Point (v.cx (), v.cy ());
                canvas.queue_draw ();
            });
            var rc = Dialogs.spin_row (gg, _("Radial Copies"), 2, 24, 1, g.radial_count, 0);
            rc.value_changed.connect (() => {
                canvas.project.sketch.guides.radial_count = (int) rc.value;
                canvas.queue_draw ();
            });
            var snap = Dialogs.switch_row (gg, _("Snap Strokes to Guides"), g.snap_enabled);
            snap.notify["active"].connect (() => canvas.project.sketch.guides.snap_enabled = snap.active);
            append (gg);

            selection_box = new Box (Orientation.VERTICAL, 0);
            append (selection_box);

            var lg = new PreferencesGroup (_("Layers"), _("New strokes go on the active layer."));
            layer_list = new LayerList ();
            lg.add_row (layer_list);
            wire_layers ();
            append (lg);
            var tl = new PreferencesGroup (_("Time-Lapse"));
            var rec = Dialogs.switch_row (tl, _("Record Strokes"), canvas.project.sketch.record_timelapse);
            rec.notify["active"].connect (() => canvas.project.sketch.record_timelapse = rec.active);
            Dialogs.button_row (tl, _("Export Video"), _("Replays the drawing stroke by stroke"), _("Export"), () => win.export ("timelapse"));
            append (tl);
            refresh ();
        }

        private void add_menu (Widget anchor) {
            var m = new ContextMenu (anchor);
            m.add_item (_("New Layer"), "list-add-symbolic", () => add_layer ());
            m.add_item (_("New Group"), "atelier-group-symbolic", () => {
                canvas.history.checkpoint ();
                var sk = canvas.project.sketch;
                var gl = new SketchLayer (sk.new_id (), _("Group %d").printf (sk.layers.size + 1), LayerKind.GROUP);
                var child = new SketchLayer (sk.new_id (), _("Layer %d").printf (sk.all_layers ().size + 1));
                gl.children.add (child);
                sk.layers.add (gl);
                canvas.layer = child;
                canvas.project.touch ("layers");
                fill_layers ();
            });
            m.add_separator ();
            m.add_item (_("Reference Image…"), "image-x-generic-symbolic", () => win.import ("image"));
            var vehicles = m.add_submenu (_("Vehicle Template"), "atelier-car-symbolic");
            foreach (var k in VehicleTemplate.KINDS) {
                string kind = k;
                vehicles.add_item (VehicleTemplate.label (kind), "atelier-car-symbolic", () => canvas.add_vehicle_underlay (kind));
            }
            vehicles.closed.connect (() => Idle.add (() => {
                vehicles.unparent ();
                return Source.REMOVE;
            }));
            Dialogs.popup (m);
        }

        private void place_guides () {
            var g = canvas.project.sketch.guides;
            var v = canvas.visible_doc ();
            if (g.ruler_on && !v.contains (g.ruler_a.x, g.ruler_a.y)) {
                g.ruler_a = Point (v.x + v.w * 0.2, v.cy ());
                g.ruler_b = Point (v.x + v.w * 0.8, v.cy ());
            }
            if (g.ellipse_on && !v.contains (g.ellipse_center.x, g.ellipse_center.y)) {
                g.ellipse_center = Point (v.cx (), v.cy ());
                g.ellipse_rx = v.w * 0.2;
                g.ellipse_ry = v.h * 0.12;
            }
            if (g.curve_on && !v.contains (g.curve_pos.x, g.curve_pos.y)) {
                g.curve_pos = Point (v.cx (), v.cy ());
                g.curve_scale = v.w / 800;
            }
            if (canvas.tool == "brush" && (g.ruler_on || g.ellipse_on || g.curve_on)) {
                win.add_toast (new Toast (_("Draw near a guide to follow it; use Move Guides to place it")));
            }
            canvas.queue_draw ();
        }

        private void fill_brushes () {
            brushes_group.clear ();
            foreach (var b in canvas.project.sketch.brushes) {
                if (b.kind == BrushKind.ERASER) continue;
                var row = new ActionRow (b.name);
                var preview = new DrawingArea ();
                preview.set_size_request (64, 22);
                preview.valign = Align.CENTER;
                preview.margin_end = 12;
                var br = b;
                preview.set_draw_func ((a, cr, w, h) => {
                    var fg = a.get_color ();
                    var st = new Stroke.from_brush (br, Rgba (fg.red, fg.green, fg.blue, 1));
                    st.size = double.min (br.size, 10);
                    st.min_size = double.min (br.min_size, st.size);
                    for (int i = 0; i <= 24; i++) {
                        double t = i / 24.0;
                        st.samples.add (StrokeSample (4 + t * (w - 8), h / 2.0 + Math.sin (t * Math.PI * 2) * 5, Math.sin (t * Math.PI), 0, 0, t));
                    }
                    SketchRenderer.draw_stroke (cr, st);
                });
                row.add_prefix (preview);
                if (b.id == canvas.brush.id) row.add_suffix (new Image.from_icon_name ("object-select-symbolic"));
                row.activated.connect (() => {
                    var found = canvas.project.sketch.find_brush (br.id);
                    if (found == null) return;
                    canvas.brush = found.copy ();
                    size_spin.value = canvas.brush.size;
                    opacity_spin.value = canvas.brush.opacity * 100;
                    curve_editor.curve = canvas.brush.pressure_curve;
                    curve_editor.queue_draw ();
                    if (canvas.tool != "brush" && canvas.tool != "tape") {
                        canvas.tool = "brush";
                        sync_tool ();
                    }
                    Idle.add (() => {
                        fill_brushes ();
                        return Source.REMOVE;
                    });
                });
                brushes_group.add_row (row);
            }
        }

        private void fill_swatches () {
            Dialogs.clear (swatches);
            foreach (var slot in canvas.project.slots) {
                var c = canvas.project.colorway ().color (slot, Rgba (0.5, 0.5, 0.5));
                var b = Dialogs.swatch (c, slot);
                b.clicked.connect (() => {
                    canvas.color = c;
                    color_btn.color = Dialogs.to_gdk (c);
                });
                swatches.append (b);
            }
            foreach (var a in Singularity.Assets.AssetLibrary.get_default ().list ("color")) {
                var c = Rgba.parse (a.get_field ("color"));
                var b = Dialogs.swatch (c, a.name);
                b.clicked.connect (() => {
                    canvas.color = c;
                    color_btn.color = Dialogs.to_gdk (c);
                });
                swatches.append (b);
            }
        }

        private void fill_selection () {
            Dialogs.clear (selection_box);
            if (canvas.selection.size == 0) return;
            var g = new PreferencesGroup (ngettext ("%d Stroke Selected", "%d Strokes Selected", canvas.selection.size).printf (canvas.selection.size),
                _("Drag inside to move, corners to scale, Ctrl and a corner to distort in perspective, the circle to rotate."));
            Dialogs.button_row (g, _("Smooth"), _("Evens out the selected strokes"), _("Smooth"), () => canvas.smooth_selection ());
            Dialogs.button_row (g, _("Apply Colour"), _("Uses the stroke colour above"), _("Apply"), () => canvas.recolor_selection (canvas.color));
            var del = new ActionRow (_("Delete"), _("Removes the selected strokes"));
            var db = new Button.with_label (_("Delete"));
            db.valign = Align.CENTER;
            db.add_css_class ("destructive-action");
            db.clicked.connect (() => canvas.delete_selection ());
            del.add_suffix (db);
            g.add_row (del);
            selection_box.append (g);
        }

        private void add_layer () {
            canvas.history.checkpoint ();
            var sk = canvas.project.sketch;
            var l = new SketchLayer (sk.new_id (), _("Layer %d").printf (sk.layers.size + 1));
            sk.layers.add (l);
            canvas.layer = l;
            canvas.project.touch ("layers");
            fill_layers ();
        }

        private Gee.HashSet<string> collapsed = new Gee.HashSet<string> ();

        public void fill_layers () {
            var sk = canvas.project.sketch;
            var items = new Gee.ArrayList<LayerItem> ();
            for (int i = sk.layers.size - 1; i >= 0; i--) {
                var top = sk.layers[i];
                items.add (layer_item (top, 0));
                for (int k = top.children.size - 1; k >= 0; k--) items.add (layer_item (top.children[k], 1));
            }
            layer_list.set_items (items);
        }

        private LayerItem layer_item (SketchLayer l, int depth) {
            var it = new LayerItem (l.id, l.name);
            it.depth = depth;
            it.visible = l.visible;
            it.locked = l.locked;
            it.expandable = l.kind == LayerKind.GROUP;
            it.expanded = !collapsed.contains (l.id);
            it.active = canvas.layer == l;
            switch (l.kind) {
                case LayerKind.GROUP: it.subtitle = ngettext ("%d layer", "%d layers", l.children.size).printf (l.children.size); break;
                case LayerKind.IMAGE: it.subtitle = _("Reference image"); break;
                case LayerKind.UNDERLAY: it.subtitle = _("Template"); break;
                default: it.subtitle = ngettext ("%d stroke", "%d strokes", l.strokes.size).printf (l.strokes.size); break;
            }
            return it;
        }

        private void wire_layers () {
            var sk = canvas.project.sketch;
            layer_list.selected.connect ((id) => {
                var l = canvas.project.sketch.find_layer (id);
                if (l != null && l.kind != LayerKind.GROUP) canvas.layer = l;
            });
            layer_list.visibility_changed.connect ((id, v) => {
                var l = canvas.project.sketch.find_layer (id);
                if (l == null) return;
                l.visible = v;
                canvas.queue_draw ();
            });
            layer_list.lock_changed.connect ((id, v) => {
                var l = canvas.project.sketch.find_layer (id);
                if (l != null) l.locked = v;
            });
            layer_list.renamed.connect ((id, name) => {
                var l = canvas.project.sketch.find_layer (id);
                if (l == null) return;
                canvas.history.checkpoint ();
                l.name = name;
                canvas.project.touch ("layers");
                Idle.add (() => {
                    fill_layers ();
                    return Source.REMOVE;
                });
            });
            layer_list.expanded_changed.connect ((id, e) => {
                if (e) collapsed.remove (id);
                else collapsed.add (id);
                fill_layers ();
            });
            layer_list.options.connect ((id, anchor) => {
                var l = canvas.project.sketch.find_layer (id);
                if (l != null) layer_menu (anchor, l);
            });
            layer_list.add_requested.connect ((anchor) => add_menu (anchor));
            layer_list.duplicate_requested.connect ((id) => {
                var l = canvas.project.sketch.find_layer (id);
                if (l != null) duplicate_layer (l);
            });
            layer_list.delete_requested.connect ((id) => {
                var l = canvas.project.sketch.find_layer (id);
                if (l != null) delete_layer (l);
            });
            layer_list.raise_requested.connect ((id) => {
                var l = canvas.project.sketch.find_layer (id);
                if (l != null) move_layer (l, 1);
            });
            layer_list.lower_requested.connect ((id) => {
                var l = canvas.project.sketch.find_layer (id);
                if (l != null) move_layer (l, -1);
            });
            layer_list.moved.connect ((src, target) => {
                var l = canvas.project.sketch.find_layer (src);
                var t = canvas.project.sketch.find_layer (target);
                if (l == null || t == null) return;
                Gee.ArrayList<SketchLayer> from = sk.layers;
                foreach (var top in sk.layers) if (top.children.contains (l)) from = top.children;
                Gee.ArrayList<SketchLayer> into = sk.layers;
                foreach (var top in sk.layers) if (top.children.contains (t)) into = top.children;
                if (l.kind == LayerKind.GROUP && into != sk.layers) return;
                canvas.history.checkpoint ();
                from.remove (l);
                int idx = into.index_of (t);
                into.insert (idx < 0 ? into.size : idx + 1, l);
                canvas.project.touch ("layers");
                fill_layers ();
                canvas.queue_draw ();
            });
        }

        private void duplicate_layer (SketchLayer l) {
            var sk = canvas.project.sketch;
            canvas.history.checkpoint ();
            var d = new SketchLayer (sk.new_id (), l.name + " " + _("Copy"), l.kind);
            foreach (var st in l.strokes) d.strokes.add (st.copy ());
            foreach (var f in l.fills) d.fills.add (f.copy ());
            d.image_data = l.image_data;
            d.image_matrix = l.image_matrix;
            d.underlay = l.underlay;
            foreach (var e in l.underlay_params.entries) d.underlay_params[e.key] = e.value;
            Gee.ArrayList<SketchLayer> list = sk.layers;
            foreach (var top in sk.layers) if (top.children.contains (l)) list = top.children;
            list.insert (list.index_of (l) + 1, d);
            canvas.project.touch ("layers");
            fill_layers ();
            canvas.queue_draw ();
        }

        private void delete_layer (SketchLayer l) {
            var sk = canvas.project.sketch;
            if (sk.all_layers ().size <= 1) return;
            canvas.history.checkpoint ();
            sk.layers.remove (l);
            foreach (var top in sk.layers) top.children.remove (l);
            if (canvas.layer == l) canvas.layer = canvas.first_stroke_layer ();
            canvas.project.touch ("layers");
            fill_layers ();
            canvas.queue_draw ();
        }

        private void layer_menu (Widget anchor, SketchLayer l) {
            var sk = canvas.project.sketch;
            var m = new ContextMenu (anchor);
            m.add_item (_("Rename"), "document-edit-symbolic", () => rename_layer (l));
            SketchLayer? parent = null;
            foreach (var top in sk.layers) if (top.children.contains (l)) parent = top;
            if (parent != null) {
                var par = parent;
                m.add_item (_("Move out of Group"), "go-previous-symbolic", () => {
                    canvas.history.checkpoint ();
                    par.children.remove (l);
                    sk.layers.insert (sk.layers.index_of (par) + 1, l);
                    canvas.project.touch ("layers");
                    fill_layers ();
                });
            } else if (l.kind != LayerKind.GROUP) {
                foreach (var top in sk.layers) {
                    if (top.kind != LayerKind.GROUP) continue;
                    var grp = top;
                    m.add_item (_("Move into %s").printf (grp.name), "go-next-symbolic", () => {
                        canvas.history.checkpoint ();
                        sk.layers.remove (l);
                        grp.children.add (l);
                        canvas.project.touch ("layers");
                        fill_layers ();
                    });
                }
            }
            if (l.kind == LayerKind.UNDERLAY) m.add_item (_("Proportions…"), "atelier-car-symbolic", () => vehicle_dialog (l));
            m.add_item (_("Move Up"), "go-up-symbolic", () => move_layer (l, 1));
            m.add_item (_("Move Down"), "go-down-symbolic", () => move_layer (l, -1));
            m.add_item (_("Duplicate"), "edit-copy-symbolic", () => duplicate_layer (l));
            m.add_item (_("Group with Layer Below"), "atelier-group-symbolic", () => {
                int i = sk.layers.index_of (l);
                if (i <= 0) return;
                canvas.history.checkpoint ();
                var below = sk.layers[i - 1];
                SketchLayer group;
                if (below.kind == LayerKind.GROUP) {
                    group = below;
                    sk.layers.remove (l);
                    group.children.add (l);
                } else {
                    group = new SketchLayer (sk.new_id (), _("Group %d").printf (sk.layers.size), LayerKind.GROUP);
                    sk.layers.remove (l);
                    sk.layers.remove (below);
                    group.children.add (below);
                    group.children.add (l);
                    sk.layers.insert (i - 1, group);
                }
                canvas.project.touch ("layers");
                fill_layers ();
                canvas.queue_draw ();
            });
            if (l.kind == LayerKind.GROUP) m.add_item (_("Ungroup"), "atelier-group-symbolic", () => {
                int i = sk.layers.index_of (l);
                if (i < 0) return;
                canvas.history.checkpoint ();
                sk.layers.remove (l);
                foreach (var c in l.children) sk.layers.insert (i++, c);
                canvas.project.touch ("layers");
                fill_layers ();
                canvas.queue_draw ();
            });
            m.add_item (_("Merge Down"), "go-bottom-symbolic", () => {
                int i = sk.layers.index_of (l);
                if (i <= 0) return;
                var below = sk.layers[i - 1];
                if (below.kind != LayerKind.STROKES || l.kind != LayerKind.STROKES) return;
                canvas.history.checkpoint ();
                below.strokes.add_all (l.strokes);
                below.fills.add_all (l.fills);
                sk.layers.remove (l);
                canvas.layer = below;
                canvas.project.touch ("layers");
                fill_layers ();
                canvas.queue_draw ();
            });
            m.add_separator ();
            foreach (var op in new int[] { 100, 75, 50, 25 }) {
                int o = op;
                m.add_item (_("Opacity %d%%").printf (o), null, () => {
                    l.opacity = o / 100.0;
                    canvas.queue_draw ();
                });
            }
            m.add_separator ();
            string[] modes = { "normal", "multiply", "screen", "overlay", "darken", "lighten" };
            string[] names = { _("Normal"), _("Multiply"), _("Screen"), _("Overlay"), _("Darken"), _("Lighten") };
            for (int i = 0; i < modes.length; i++) {
                string md = modes[i];
                m.add_item (names[i], l.blend == md ? "object-select-symbolic" : null, () => {
                    l.blend = md;
                    canvas.queue_draw ();
                });
            }
            m.add_separator ();
            m.add_item (_("Delete Layer"), "user-trash-symbolic", () => delete_layer (l), "destructive-action");
            Dialogs.popup (m);
        }

        private void move_layer (SketchLayer l, int dir) {
            var sk = canvas.project.sketch;
            Gee.ArrayList<SketchLayer> list = sk.layers;
            foreach (var top in sk.layers) if (top.children.contains (l)) list = top.children;
            int i = list.index_of (l);
            int j = i + dir;
            if (i < 0 || j < 0 || j >= list.size) return;
            canvas.history.checkpoint ();
            list.remove_at (i);
            list.insert (j, l);
            canvas.project.touch ("layers");
            fill_layers ();
            canvas.queue_draw ();
        }

        private void vehicle_dialog (SketchLayer l) {
            var t = VehicleTemplate.preset (l.underlay.has_prefix ("vehicle:") ? l.underlay.substring (8) : "sedan");
            string[] keys = { "wheelbase", "length", "height", "wheel", "front_overhang", "ground" };
            string[] labels = { _("Wheelbase"), _("Overall Length"), _("Height"), _("Wheel Diameter"), _("Front Overhang"), _("Ground Clearance") };
            double[] defaults = { t.wheelbase, t.length, t.height, t.wheel, t.front_overhang, t.ground };
            Box body;
            var spins = new Gee.ArrayList<SpinButton> ();
            var dlg = Dialogs.form (win, _("Vehicle Proportions"), _("Apply"), out body, () => {
                canvas.history.checkpoint ();
                for (int i = 0; i < keys.length; i++) l.underlay_params[keys[i]] = spins[i].value;
                canvas.project.touch ("layers");
                canvas.queue_draw ();
            });
            var g = new PreferencesGroup (_("Dimensions"), _("In millimetres"));
            for (int i = 0; i < keys.length; i++) spins.add (Dialogs.spin_row (g, labels[i], 50, 8000, 10, l.underlay_params.has_key (keys[i]) ? l.underlay_params[keys[i]] : defaults[i], 0));
            body.append (g);
            dlg.present ();
        }

        private void rename_layer (SketchLayer l) {
            Box body;
            Entry? e = null;
            var dlg = Dialogs.form (win, _("Rename Layer"), _("Rename"), out body, () => {
                canvas.history.checkpoint ();
                l.name = e.text.strip () != "" ? e.text.strip () : l.name;
                fill_layers ();
            });
            var g = new PreferencesGroup (_("Layer"));
            e = Dialogs.entry_row (g, _("Name"), l.name);
            body.append (g);
            dlg.present ();
        }
    }
}
