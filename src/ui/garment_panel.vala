using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Atelier {

    public class GarmentPanel : InspectorPanel {
        private Project project;
        private View3D view;
        private GarmentCanvas canvas;
        private GarmentSim? sim;
        private Body? body;
        private string body_key = "";
        private Thread<void*>? worker;
        private int running;
        private int steps;
        private uint tick_id;
        private int64 rate_time;
        private int rate_steps;
        private string size;
        private ActionRow status_row;
        private Button simulate_button;
        private Box seam_box;
        private Box shape_box;
        private Box measure_box;
        private Box fabric_list;
        private Box fabric_props;
        private Box piece_box;
        private Stack pages;
        private string fit_map = "material";
        private string selected_fabric = "";
        private bool stale = true;
        private bool grabbing;
        private uint body_timer;
        private Scene.Vec3 grab_point;
        private static HashTable<string, BodyShape>? fits;

        public ToolPalette palette { get; private set; }
        public signal void message (string text);

        public GarmentPanel (Project project, View3D view, GarmentCanvas canvas) {
            this.project = project;
            this.view = view;
            this.canvas = canvas;
            size = project.pattern.active_size != "" ? project.pattern.active_size : project.pattern.table.base_size;
            project.garment.ensure_fabrics ();
            selected_fabric = project.garment.fabrics[0].id;

            palette = new ToolPalette ();
            palette.add_tool ("select", "atelier-pointer-symbolic", _("Select (A)"));
            palette.add_tool ("edit", "atelier-point-symbolic", _("Edit Pattern (Z)"));
            palette.add_tool ("rect", "atelier-piece-symbolic", _("Rectangle (S)"));
            palette.add_tool ("polygon", "atelier-pen-symbolic", _("Polygon (H)"));
            palette.add_tool ("sew", "atelier-stitch-symbolic", _("Segment Sewing (N)"));
            palette.add_tool ("free-sew", "atelier-seam-walk-symbolic", _("Free Sewing (M)"));
            palette.add_tool ("edit-sew", "atelier-transform-symbolic", _("Edit Sewing (B)"));
            palette.set_active (canvas.tool);
            palette.tool_selected.connect ((id) => canvas.choose_tool (id));
            canvas.tool_changed.connect (() => palette.set_active (canvas.tool));
            canvas.seams_changed.connect (() => {
                if (sim != null) sim.reseam ();
                view.queue_render ();
            });
            canvas.pattern_changed.connect (() => {
                stop ();
                stale = true;
                ensure_sim ();
                rebuild_fabric_list ();
                status_row.title = _("Ready");
                status_row.subtitle = _("Pattern changed, not simulated yet");
            });
            canvas.selection_changed.connect (() => {
                rebuild_shape_box ();
                rebuild_seam_box ();
                rebuild_piece_box ();
                view.queue_render ();
            });

            pages = new Stack ();
            pages.vhomogeneous = false;
            pages.transition_type = StackTransitionType.CROSSFADE;
            pages.add_titled (simulation_page (), "simulation", _("Simulation"));
            pages.add_titled (avatar_page (), "avatar", _("Avatar"));
            pages.add_titled (fabric_page (), "fabric", _("Fabric"));
            var tabs = new BubbleSwitcher (pages);
            tabs.margin_top = 4;
            tabs.margin_bottom = 8;
            append (tabs);
            append (pages);

            view.overlay.connect ((o) => {
                if (!get_mapped () || sim == null) return;
                int n = sim.stitch_count ();
                for (int i = 0; i < n; i++) {
                    Vec3 a, b;
                    int seam = sim.stitch (i, out a, out b);
                    var c = GarmentCanvas.seam_color (seam);
                    var col = Gdk.RGBA () { red = (float) c.r, green = (float) c.g, blue = (float) c.b, alpha = 0.9f };
                    if (seam == canvas.selected_seam) o.point (Scene.Vec3 (a.x, a.y, a.z), col, 7);
                    if (a.distance (b) < 6) continue;
                    o.line (Scene.Vec3 (a.x, a.y, a.z), Scene.Vec3 (b.x, b.y, b.z), col, 1.2);
                }
            });
            view.tool_pressed.connect (on_press);
            view.tool_dragged.connect (on_drag);
            view.tool_released.connect (on_release);
            var keys = new EventControllerKey ();
            keys.key_pressed.connect ((keyval, code, state) => {
                if (!get_mapped ()) return false;
                if (keyval == Gdk.Key.space) {
                    toggle ();
                    return true;
                }
                return view_key (keyval);
            });
            view.add_controller (keys);
            refresh ();
        }

        private Widget simulation_page () {
            var page = new Box (Orientation.VERTICAL, 0);
            var simg = new PreferencesGroup (_("Simulation"), _("Pieces are arranged around the avatar and sewn. Drag the cloth while it runs."));
            simulate_button = Dialogs.header_button (simg, _("Simulate"), () => toggle (), true);
            status_row = new ActionRow (_("Ready"), _("Not simulated yet"));
            simg.add_row (status_row);
            Dialogs.button_row (simg, _("Reset Arrangement"), _("Puts the pieces back around the avatar"), _("Reset"), () => {
                stop ();
                stale = true;
                ensure_sim ();
                status_row.title = _("Ready");
                status_row.subtitle = _("Not simulated yet");
            });
            var spacing = new SpinRow (_("Particle Distance"), _("In millimetres, smaller is finer and slower"), 5, 60, 1, project.garment.resolution);
            spacing.spin_btn.value_changed.connect (() => {
                project.garment.resolution = (int) spacing.value;
                stale = true;
            });
            simg.add_row (spacing);
            page.append (simg);

            var start = new PreferencesGroup (_("Start From"), _("A block replaces the current pattern and its seams."));
            foreach (var id in Samples.garments ()) {
                string kind = id;
                Dialogs.button_row (start, Samples.garment_label (kind), null, _("Use"), () => use_block (kind));
            }
            page.append (start);

                        var sewing = new PreferencesGroup (_("Sewing"), _("Sew edges in the pattern window with the sewing tools."));
            Dialogs.header_button (sewing, _("Auto Sew"), () => {
                if (sim == null) return;
                sim.auto_sew (project.pattern.evaluate (size));
                project.touch ("garment");
                canvas.selected_seam = -1;
                canvas.queue_draw ();
                rebuild_seam_box ();
                view.queue_render ();
            }, false);
            page.append (sewing);
            seam_box = new Box (Orientation.VERTICAL, 0);
            page.append (seam_box);
            shape_box = new Box (Orientation.VERTICAL, 0);
            page.append (shape_box);

            var fit = new PreferencesGroup (_("Fit Map"));
            string[] maps = { "material", "strain", "distance", "wireframe" };
            string[] map_labels = { _("Fabric"), _("Tension"), _("Distance"), _("Mesh") };
            var fit_row = new SelectionRow (_("Show"), map_labels, map_labels[0]);
            fit_row.selected.connect ((label) => {
                string m = "material";
                for (int i = 0; i < maps.length; i++) if (map_labels[i] == label) m = maps[i];
                fit_map = m;
                if (sim != null) {
                    sim.map = m;
                    sim.sync ();
                }
                view.shading = m;
            });
            fit.add_row (fit_row);
            page.append (fit);
            return page;
        }

        private string gender () {
            string g = project.garment.avatar_gender != "" ? project.garment.avatar_gender : project.pattern.table.gender;
            return g == "male" ? "male" : "female";
        }

        private string hair () {
            string h = project.garment.avatar_hair;
            if (h == "auto") return gender () == "male" ? "short02" : "bob01";
            return h;
        }

        private static string hair_label (string id) {
            switch (id) {
                case "bob01": return _("Bob");
                case "long01": return _("Long");
                case "short02": return _("Short");
                case "short04": return _("Cropped");
                case "ponytail01": return _("Ponytail");
                default: return _("None");
            }
        }

        private BodyDims dims () {
            var d = BodyDims.from_table (project.pattern.table, size);
            foreach (var e in project.garment.avatar.entries) d.set_field (e.key, e.value);
            return d;
        }

        private Widget avatar_page () {
            var page = new Box (Orientation.VERTICAL, 0);
            var avatar = new PreferencesGroup (_("Avatar"));
            string[] genders = { _("Female"), _("Male") };
            var gender_row = new SelectionRow (_("Body"), genders, genders[gender () == "male" ? 1 : 0]);
            gender_row.selected.connect ((label) => {
                project.garment.avatar_gender = label == genders[1] ? "male" : "female";
                project.touch ("garment");
                body_changed ();
            });
            avatar.add_row (gender_row);
            string[] sizes = {};
            foreach (var s in project.pattern.table.sizes) sizes += s;
            if (sizes.length == 0) sizes += size;
            var size_row = new SelectionRow (_("Size"), sizes, size);
            size_row.selected.connect ((s) => {
                size = s;
                stale = true;
                rebuild_measures ();
                refresh ();
            });
            avatar.add_row (size_row);
            string[] pose_labels = {};
            foreach (var id in BodyPose.ids ()) pose_labels += BodyPose.label (id);
            var pose_row = new SelectionRow (_("Pose"), pose_labels, BodyPose.label (project.garment.pose));
            pose_row.selected.connect ((label) => {
                foreach (var id in BodyPose.ids ()) if (BodyPose.label (id) == label) project.garment.pose = id;
                project.touch ("garment");
                body_changed ();
            });
            avatar.add_row (pose_row);
            string[] hair_ids = { "none" };
            foreach (unowned string h in Body.hair_styles ()) hair_ids += h;
            string[] hair_labels = {};
            foreach (unowned string h in hair_ids) hair_labels += hair_label (h);
            var hair_row = new SelectionRow (_("Hair"), hair_labels, hair_label (hair ()));
            hair_row.selected.connect ((label) => {
                foreach (unowned string h in hair_ids) if (hair_label (h) == label) project.garment.avatar_hair = h;
                project.touch ("garment");
                body_changed ();
            });
            avatar.add_row (hair_row);
            page.append (avatar);
            measure_box = new Box (Orientation.VERTICAL, 0);
            page.append (measure_box);
            rebuild_measures ();
            return page;
        }

        private void rebuild_measures () {
            Widget? c;
            while ((c = measure_box.get_first_child ()) != null) measure_box.remove (c);
            double unit = project.pattern.unit_mm ();
            var g = new PreferencesGroup (_("Measurements"), _("In %s. The avatar follows the size chart until a value is changed here.").printf (project.pattern.unit));
            Dialogs.header_button (g, _("Reset"), () => {
                project.garment.avatar.clear ();
                project.touch ("garment");
                rebuild_measures ();
                body_changed ();
            }, false);
            var d = dims ();
            foreach (unowned string name in BodyDims.FIELDS) {
                string field = name;
                double v = d.field (field) / unit;
                var row = new SpinRow (BodyDims.field_label (field), null, Math.floor (v * 0.5), Math.ceil (v * 1.8), unit >= 10 ? 0.5 : 5, Math.round (v * 10) / 10);
                row.spin_btn.digits = unit >= 10 ? 1 : 0;
                row.spin_btn.value_changed.connect (() => {
                    project.garment.avatar[field] = row.value * unit;
                    project.touch ("garment");
                    body_changed ();
                });
                g.add_row (row);
            }
            measure_box.append (g);
        }

        private void body_changed () {
            if (body_timer != 0) Source.remove (body_timer);
            body_timer = Timeout.add (350, () => {
                body_timer = 0;
                ensure_body ();
                show_scene ();
                return Source.REMOVE;
            });
        }

        private Widget fabric_page () {
            var page = new Box (Orientation.VERTICAL, 0);
            piece_box = new Box (Orientation.VERTICAL, 0);
            page.append (piece_box);
            fabric_list = new Box (Orientation.VERTICAL, 0);
            page.append (fabric_list);
            fabric_props = new Box (Orientation.VERTICAL, 0);
            page.append (fabric_props);
            rebuild_fabric_list ();
            rebuild_fabric_props ();
            return page;
        }

        private static Widget swatch (FabricPreset f) {
            var area = new DrawingArea ();
            area.set_size_request (26, 26);
            area.valign = Align.CENTER;
            area.set_draw_func ((a, cr, w, h) => {
                cr.arc (w / 2.0, h / 2.0, double.min (w, h) / 2.0 - 1, 0, 2 * Math.PI);
                var pix = f.image ();
                if (pix != null) {
                    cr.save ();
                    cr.clip_preserve ();
                    double k = double.max ((double) w / pix.width, (double) h / pix.height);
                    cr.scale (k, k);
                    Gdk.cairo_set_source_pixbuf (cr, pix, 0, 0);
                    cr.paint ();
                    cr.restore ();
                } else {
                    cr.set_source_rgb (f.color.r, f.color.g, f.color.b);
                    cr.fill_preserve ();
                }
                cr.set_source_rgba (0, 0, 0, 0.25);
                cr.set_line_width (1);
                cr.stroke ();
            });
            return area;
        }

        private void rebuild_fabric_list () {
            Widget? c;
            while ((c = fabric_list.get_first_child ()) != null) fabric_list.remove (c);
            var g = new PreferencesGroup (_("Fabrics"));
            Dialogs.header_button (g, _("Add"), () => {
                var src = project.garment.find_fabric (selected_fabric) ?? project.garment.fabrics[0];
                var made = src.copy (project.garment.new_fabric_id (), _("Fabric %d").printf (project.garment.fabrics.size + 1));
                project.garment.fabrics.add (made);
                selected_fabric = made.id;
                project.touch ("garment");
                rebuild_fabric_list ();
                rebuild_fabric_props ();
                rebuild_piece_box ();
            }, false);
            foreach (var f in project.garment.fabrics) {
                string id = f.id;
                int used = 0;
                foreach (var piece in project.pattern.pieces) if (project.garment.fabric_for (piece.id).id == id) used++;
                var row = new ActionRow (f.name, used == 1 ? _("1 piece") : _("%d pieces").printf (used));
                row.add_prefix (swatch (f));
                var pick = new CheckButton ();
                pick.valign = Align.CENTER;
                pick.active = id == selected_fabric;
                pick.tooltip_text = _("Edit This Fabric");
                pick.toggled.connect (() => {
                    if (!pick.active || selected_fabric == id) return;
                    selected_fabric = id;
                    rebuild_fabric_list ();
                    rebuild_fabric_props ();
                });
                row.add_suffix (pick);
                g.add_row (row);
            }
            fabric_list.append (g);
        }

        private delegate void Setter (FabricPreset f, double v);

        private void number (PreferencesGroup g, FabricPreset f, string title, string? subtitle, double lo, double hi, double step, int digits, double value, bool physical, owned Setter set) {
            var row = new SpinRow (title, subtitle, lo, hi, step, value);
            row.spin_btn.digits = digits;
            row.spin_btn.value_changed.connect (() => {
                set (f, row.value);
                fabric_changed (f, physical);
            });
            g.add_row (row);
        }

        private void rebuild_fabric_props () {
            Widget? c;
            while ((c = fabric_props.get_first_child ()) != null) fabric_props.remove (c);
            var f = project.garment.find_fabric (selected_fabric);
            if (f == null) return;
            var g = new PreferencesGroup (f.name);
            var name_row = new EntryRow (_("Name"));
            name_row.text = f.name;
            name_row.entry_activated.connect (() => {
                if (name_row.text.strip () == "") return;
                f.name = name_row.text.strip ();
                project.touch ("garment");
                rebuild_fabric_list ();
                rebuild_fabric_props ();
                rebuild_piece_box ();
            });
            g.add_row (name_row);
            string[] labels = {};
            foreach (var p in FabricPreset.all ()) labels += p.name;
            var type_row = new SelectionRow (_("Type"), labels, FabricPreset.find (f.preset).name);
            type_row.selected.connect ((label) => {
                foreach (var p in FabricPreset.all ()) if (p.name == label) f.take_physics (p);
                fabric_changed (f, true);
                rebuild_fabric_props ();
            });
            g.add_row (type_row);
            var color_row = new ActionRow (_("Colour"));
            var picker = new ColorPickerButton (Gdk.RGBA () { red = (float) f.color.r, green = (float) f.color.g, blue = (float) f.color.b, alpha = 1 });
            picker.valign = Align.CENTER;
            picker.color_changed.connect ((col) => {
                f.color = Rgba (col.red, col.green, col.blue, 1);
                fabric_changed (f, false);
                rebuild_fabric_list ();
            });
            color_row.add_suffix (picker);
            g.add_row (color_row);
            var tex_row = new ActionRow (_("Print"), f.texture != "" ? Path.get_basename (f.texture) : _("No image"));
            var choose = new Button.with_label (_("Choose"));
            choose.valign = Align.CENTER;
            choose.clicked.connect (() => {
                Dialogs.open.begin (window (), _("Choose an Image"), _("Images"), { "png", "jpg", "jpeg", "webp" }, (o, r) => {
                    var file = Dialogs.open.end (r);
                    if (file == null || file.get_path () == null) return;
                    f.texture = file.get_path ();
                    fabric_changed (f, false);
                    rebuild_fabric_list ();
                    rebuild_fabric_props ();
                });
            });
            tex_row.add_suffix (choose);
            if (f.texture != "") {
                var clear = new Button.with_label (_("Remove"));
                clear.valign = Align.CENTER;
                clear.clicked.connect (() => {
                    f.texture = "";
                    fabric_changed (f, false);
                    rebuild_fabric_list ();
                    rebuild_fabric_props ();
                });
                tex_row.add_suffix (clear);
            }
            g.add_row (tex_row);
            number (g, f, _("Print Size"), _("Width of one repeat in millimetres"), 5, 2000, 5, 0, f.texture_size, false, (x, v) => x.texture_size = v);
            fabric_props.append (g);

            var p = new PreferencesGroup (_("Physical Properties"));
            number (p, f, _("Stretch Weft"), _("Resistance across the grain"), 50, 60000, 100, 0, f.stretch_weft, true, (x, v) => x.stretch_weft = v);
            number (p, f, _("Stretch Warp"), _("Resistance along the grain"), 50, 60000, 100, 0, f.stretch_warp, true, (x, v) => x.stretch_warp = v);
            number (p, f, _("Shear"), _("Resistance on the bias"), 20, 30000, 20, 0, f.shear, true, (x, v) => x.shear = v);
            number (p, f, _("Bending Weft"), _("Stiffness when folding across the grain"), 0.2, 2000, 0.5, 1, f.bend_weft, true, (x, v) => x.bend_weft = v);
            number (p, f, _("Bending Warp"), _("Stiffness when folding along the grain"), 0.2, 2000, 0.5, 1, f.bend_warp, true, (x, v) => x.bend_warp = v);
            number (p, f, _("Weight"), _("Grams per square metre"), 20, 1500, 5, 0, f.density, true, (x, v) => x.density = v);
            number (p, f, _("Thickness"), _("In millimetres"), 0.05, 10, 0.05, 2, f.thickness, true, (x, v) => x.thickness = v);
            number (p, f, _("Friction"), null, 0, 1, 0.05, 2, f.friction, true, (x, v) => x.friction = v);
            number (p, f, _("Shrinkage Weft"), _("Percent of the cut width"), 50, 150, 1, 0, f.shrink_weft * 100, true, (x, v) => x.shrink_weft = v / 100);
            number (p, f, _("Shrinkage Warp"), _("Percent of the cut length"), 50, 150, 1, 0, f.shrink_warp * 100, true, (x, v) => x.shrink_warp = v / 100);
            fabric_props.append (p);

            var look = new PreferencesGroup (_("Surface"));
            number (look, f, _("Roughness"), null, 0.05, 1, 0.05, 2, f.roughness, false, (x, v) => x.roughness = v);
            number (look, f, _("Sheen"), null, 0, 2, 0.05, 2, f.sheen, false, (x, v) => x.sheen = v);
            number (look, f, _("Weave Depth"), null, 0, 1, 0.05, 2, f.weave, false, (x, v) => x.weave = v);
            number (look, f, _("Threads"), _("Per millimetre"), 0.3, 6, 0.1, 1, f.weave_scale, false, (x, v) => x.weave_scale = v);
            if (project.garment.fabrics.size > 1) {
                Dialogs.button_row (look, _("Remove the Fabric"), _("Its pieces go back to the first fabric"), _("Remove"), () => {
                    project.garment.fabrics.remove (f);
                    foreach (var key in project.garment.piece_fabrics.keys.to_array ()) if (project.garment.piece_fabrics[key] == f.id) project.garment.piece_fabrics.unset (key);
                    selected_fabric = project.garment.fabrics[0].id;
                    project.touch ("garment");
                    apply_fabrics ();
                    rebuild_fabric_list ();
                    rebuild_fabric_props ();
                    rebuild_piece_box ();
                });
            }
            fabric_props.append (look);
        }

        private void fabric_changed (FabricPreset f, bool physical) {
            project.touch ("garment");
            if (sim != null) {
                foreach (var p in sim.pieces) {
                    if (project.garment.fabric_for (p.piece_id) != f) continue;
                    if (physical) sim.set_fabric (p, f);
                    else {
                        p.fabric = f;
                        sim.apply_material (p);
                    }
                }
            }
            canvas.queue_draw ();
            view.queue_render ();
        }

        private void rebuild_piece_box () {
            Widget? c;
            while ((c = piece_box.get_first_child ()) != null) piece_box.remove (c);
            var piece = project.pattern.find_piece (canvas.selected_piece);
            var g = new PreferencesGroup (piece != null ? piece.name : _("Pieces"), piece != null ? null : _("Click a piece in the pattern window to change only that one."));
            string[] names = {};
            foreach (var f in project.garment.fabrics) names += f.name;
            foreach (var p in project.pattern.pieces) {
                if (piece != null && p != piece) continue;
                string id = p.id;
                var row = new SelectionRow (piece != null ? _("Fabric") : p.name, names, project.garment.fabric_for (id).name);
                row.selected.connect ((label) => {
                    foreach (var f in project.garment.fabrics) if (f.name == label) project.garment.piece_fabrics[id] = f.id;
                    project.touch ("garment");
                    apply_fabrics ();
                    rebuild_fabric_list ();
                });
                g.add_row (row);
            }
            piece_box.append (g);
        }

        private const string[] PLACEMENTS = { "front", "back", "sleeve", "skirt-front", "skirt-back", "leg-front", "leg-back" };

        private static string placement_label (string id) {
            switch (id) {
                case "back": return _("Back");
                case "sleeve": return _("Sleeves");
                case "skirt-front": return _("Front, from the Waist");
                case "skirt-back": return _("Back, from the Waist");
                case "leg-front": return _("Front of the Legs");
                case "leg-back": return _("Back of the Legs");
                default: return _("Front");
            }
        }

        private void rebuild_shape_box () {
            Widget? c;
            while ((c = shape_box.get_first_child ()) != null) shape_box.remove (c);
            var piece = project.pattern.find_piece (canvas.selected_piece);
            if (piece == null) return;
            var g = new PreferencesGroup (piece.name);
            var name_row = new EntryRow (_("Name"));
            name_row.text = piece.name;
            name_row.entry_activated.connect (() => {
                if (name_row.text.strip () == "") return;
                piece.name = name_row.text.strip ();
                canvas.piece_edited ();
                rebuild_shape_box ();
                rebuild_piece_box ();
            });
            g.add_row (name_row);
            string[] labels = {};
            foreach (unowned string id in PLACEMENTS) labels += placement_label (id);
            var place_row = new SelectionRow (_("Arrangement"), labels, placement_label (piece.placement));
            place_row.selected.connect ((label) => {
                foreach (unowned string id in PLACEMENTS) if (placement_label (id) == label) piece.placement = id;
                if (piece.placement == "sleeve" || piece.placement.has_prefix ("leg-")) piece.pair = true;
                canvas.piece_edited ();
            });
            g.add_row (place_row);
            var pair_row = new SwitchRow (_("Symmetric Pair"), _("Cuts and places a mirrored second piece"));
            pair_row.active = piece.pair;
            pair_row.notify["active"].connect (() => {
                piece.pair = pair_row.active;
                canvas.piece_edited ();
            });
            g.add_row (pair_row);
            Dialogs.button_row (g, _("Remove the Piece"), null, _("Remove"), () => canvas.delete_piece (piece.id));
            shape_box.append (g);
        }

        private void rebuild_seam_box () {
            Widget? c;
            while ((c = seam_box.get_first_child ()) != null) seam_box.remove (c);
            int index = canvas.selected_seam;
            if (index < 0 || index >= project.garment.seams.size) return;
            var g = new PreferencesGroup (canvas.seam_title (index));
            double unit = project.pattern.unit_mm ();
            var lengths = new ActionRow (_("Lengths"), "%s and %s %s".printf (Singularity.Vector.PathData.fmt (canvas.seam_length (index, false) / unit, 1), Singularity.Vector.PathData.fmt (canvas.seam_length (index, true) / unit, 1), project.pattern.unit));
            g.add_row (lengths);
            Dialogs.button_row (g, _("Direction"), _("Swaps which ends are sewn together"), _("Reverse"), () => canvas.reverse_selected_seam ());
            Dialogs.button_row (g, _("Remove the Seam"), null, _("Remove"), () => canvas.delete_selected_seam ());
            seam_box.append (g);
            pages.visible_child_name = "simulation";
        }

        private bool view_key (uint keyval) {
            double yaw = 0, pitch = 0.08;
            switch (keyval) {
                case Gdk.Key.@2:
                case Gdk.Key.KP_2:
                    break;
                case Gdk.Key.@8:
                case Gdk.Key.KP_8:
                    yaw = Math.PI;
                    break;
                case Gdk.Key.@4:
                case Gdk.Key.KP_4:
                    yaw = -Math.PI / 2;
                    break;
                case Gdk.Key.@6:
                case Gdk.Key.KP_6:
                    yaw = Math.PI / 2;
                    break;
                case Gdk.Key.@5:
                case Gdk.Key.KP_5:
                    pitch = 1.5;
                    break;
                case Gdk.Key.@0:
                case Gdk.Key.KP_0:
                    pitch = -1.5;
                    break;
                case Gdk.Key.f:
                case Gdk.Key.F:
                    view.frame_all (true);
                    return true;
                default:
                    return false;
            }
            var c = view.camera.copy ();
            c.yaw = yaw;
            c.pitch = pitch;
            view.animate_to (c);
            return true;
        }

        private void apply_fabrics () {
            if (sim != null) foreach (var p in sim.pieces) sim.set_fabric (p, project.garment.fabric_for (p.piece_id));
            canvas.queue_draw ();
            view.queue_render ();
        }

        private void ensure_body () {
            var d = dims ();
            string key = gender ();
            foreach (unowned string name in BodyDims.FIELDS) key += " %.0f".printf (d.field (name));
            string full = key + " " + project.garment.pose + " " + hair ();
            if (body != null && body_key == full) return;
            if (fits == null) fits = new HashTable<string, BodyShape> (str_hash, str_equal);
            BodyShape? shape = fits[key];
            if (shape == null) {
                shape = BodyFit.fit (d, gender ());
                fits[key] = shape;
            }
            body = Body.build (shape, BodyPose.named (project.garment.pose), hair ());
            body_key = full;
            if (sim != null) sim.set_body (body);
        }

        private void ensure_sim () {
            ensure_body ();
            if (sim != null && !stale) return;
            if (running != 0) stop ();
            stale = false;
            sim = null;
            var result = project.pattern.evaluate (size);
            canvas.show_size (size);
            if (result.pieces.size > 0) {
                sim = new GarmentSim (result, project.garment, body);
                sim.map = fit_map;
                sim.sync ();
            }
            show_scene ();
        }

        public void refresh () {
            project.garment.ensure_fabrics ();
            rebuild_piece_box ();
            rebuild_fabric_list ();
            ensure_sim ();
            show_scene ();
        }

        public void sync_pattern () {
            stop ();
            stale = true;
            ensure_sim ();
            status_row.title = _("Ready");
            status_row.subtitle = _("Pattern changed, not simulated yet");
        }

        private void show_scene () {
            var list = new Gee.ArrayList<Scene.Mesh> ();
            if (body != null) {
                list.add (body.mesh);
                foreach (var extra in body.extras) list.add (extra);
            }
            if (sim != null) foreach (var p in sim.pieces) list.add (p.mesh);
            view.set_meshes (new Gee.ArrayList<Mesh> ());
            view.set_native (list);
        }

        private void toggle () {
            if (running != 0) stop ();
            else start ();
        }

        private void start () {
            if (running != 0) return;
            ensure_sim ();
            if (sim == null) {
                message (_("Add pattern pieces before simulating"));
                return;
            }
            AtomicInt.set (ref running, 1);
            simulate_button.label = _("Stop");
            status_row.title = _("Simulating");
            var local = sim;
            rate_time = get_monotonic_time ();
            rate_steps = AtomicInt.get (ref steps);
            worker = new Thread<void*> ("atelier-cloth", () => {
                while (AtomicInt.get (ref running) == 1) {
                    int64 t0 = get_monotonic_time ();
                    local.step ();
                    AtomicInt.inc (ref steps);
                    int64 spent = get_monotonic_time () - t0;
                    Thread.usleep ((ulong) (spent < 15000 ? 16000 - spent : 1000));
                }
                return null;
            });
            tick_id = view.add_tick_callback ((w, clock) => {
                if (sim == null) return Source.REMOVE;
                sim.sync ();
                view.queue_render ();
                int64 now = get_monotonic_time ();
                if (now - rate_time > 500000) {
                    int done = AtomicInt.get (ref steps);
                    double fps = (done - rate_steps) * 1e6 / (now - rate_time);
                    rate_steps = done;
                    rate_time = now;
                    status_row.subtitle = _("%d particles, %.0f steps per second, seam gap %.1f mm").printf (sim.particle_count (), fps, sim.max_sew_gap ());
                }
                return Source.CONTINUE;
            });
        }

        private void stop () {
            if (running == 0) return;
            AtomicInt.set (ref running, 0);
            if (worker != null) worker.join ();
            worker = null;
            if (tick_id != 0) view.remove_tick_callback (tick_id);
            tick_id = 0;
            simulate_button.label = _("Simulate");
            if (sim != null) {
                sim.release ();
                sim.sync ();
                status_row.title = _("Draped");
                status_row.subtitle = _("Largest seam gap %.1f mm, largest stretch %.0f%%").printf (sim.max_sew_gap (), sim.max_stretch () * 100);
            }
            view.queue_render ();
        }

        public void simulate_for (int frames) {
            stop ();
            ensure_sim ();
            if (sim == null) return;
            sim.run (frames);
            status_row.title = _("Draped");
            status_row.subtitle = _("Largest seam gap %.1f mm, largest stretch %.0f%%").printf (sim.max_sew_gap (), sim.max_stretch () * 100);
            view.queue_render ();
        }

        public void use_block (string kind) {
            stop ();
            Samples.garment (project, kind);
            project.garment.ensure_fabrics ();
            canvas.selected_piece = "";
            canvas.selected_seam = -1;
            stale = true;
            ensure_sim ();
            canvas.fit_all ();
            rebuild_piece_box ();
            rebuild_fabric_list ();
            rebuild_seam_box ();
            status_row.title = _("Ready");
            status_row.subtitle = _("Not simulated yet");
        }

        public void avatar_updated () {
            ensure_body ();
            show_scene ();
        }

        public void fabrics_updated () {
            apply_fabrics ();
            rebuild_fabric_list ();
            rebuild_fabric_props ();
            rebuild_piece_box ();
        }

        public string report () {
            if (sim == null) return "no garment";
            var sb = new StringBuilder ();
            sb.append_printf ("%d particles, gap %.1f, stretch %.3f, body %.2f, motion %.1f;", sim.particle_count (), sim.max_sew_gap (), sim.max_stretch (), sim.min_body_distance (), sim.motion ());
            var gaps = sim.seam_gaps ();
            for (int i = 0; i < gaps.length; i++) sb.append_printf (" %s=%.0f", canvas.seam_title (i), gaps[i]);
            return sb.str;
        }

        public void show_page (string name) {
            pages.visible_child_name = name;
        }

        private ClothPiece? piece_of (Scene.Mesh? mesh) {
            if (sim == null || mesh == null) return null;
            foreach (var p in sim.pieces) if (p.mesh == mesh) return p;
            return null;
        }

        private bool on_press (double x, double y, Gdk.ModifierType state) {
            if (!get_mapped () || sim == null) return false;
            Scene.Hit hit;
            var piece = piece_of (view.native_at (x, y, out hit));
            if (piece == null) return false;
            if (running == 0) {
                if (canvas.selected_piece != piece.piece_id) {
                    canvas.selected_piece = piece.piece_id;
                    canvas.selected_seam = -1;
                    canvas.selection_changed ();
                    canvas.queue_draw ();
                }
                return false;
            }
            grabbing = true;
            grab_point = hit.point;
            sim.grab (piece, hit.nearest_vertex (), Vec3 (hit.point.x, hit.point.y, hit.point.z), 70);
            return true;
        }

        private void on_drag (double x, double y, Gdk.ModifierType state) {
            if (!grabbing || sim == null) return;
            Scene.Vec3 r, u, f, at;
            view.camera.basis (out r, out u, out f);
            if (view.ray (x, y).plane (grab_point, f, out at)) sim.grab_move (Vec3 (at.x, at.y, at.z));
        }

        private void on_release (double x, double y) {
            if (!grabbing) return;
            grabbing = false;
            if (sim != null) sim.release ();
        }

        private Gtk.Window? window () {
            return get_root () as Gtk.Window;
        }

        private Gee.List<Mesh> export_list () {
            if (sim != null) return sim.export_meshes ();
            var list = new Gee.ArrayList<Mesh> ();
            if (body != null) list.add (Mesh.from_scene (body.mesh));
            return list;
        }

        public void export_as (string kind) {
            if (kind == "turntable") {
                var fd = new FileDialog ();
                fd.title = _("Choose a Folder for the Turntable");
                fd.select_folder.begin (window (), null, (o, res) => {
                    try {
                        var folder = fd.select_folder.end (res);
                        if (folder != null) turntable (folder.get_path ());
                    } catch (Error e) {
                        if (!(e is Gtk.DialogError.DISMISSED)) message (e.message);
                    }
                });
                return;
            }
            var d = new FileDialog ();
            d.title = _("Export");
            string base_name = project.title != "" ? project.title : _("Garment");
            d.initial_name = "%s.%s".printf (base_name, kind == "fbxbin" ? "fbx" : kind);
            d.save.begin (window (), null, (o, res) => {
                try {
                    var file = d.save.end (res);
                    if (file == null) return;
                    string path = file.get_path ();
                    var list = export_list ();
                    switch (kind) {
                        case "obj":
                            Obj.save (path, list);
                            break;
                        case "fbx":
                        case "fbxbin":
                            Fbx.save (path, list, kind == "fbxbin");
                            break;
                        case "png":
                            view.snapshot_at (1600, 1200, view.camera.yaw * 180 / Math.PI).write_to_png (path);
                            break;
                        default:
                            Gltf.save (path, list);
                            break;
                    }
                    message (_("Exported %s").printf (Path.get_basename (path)));
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) message (e.message);
                }
            });
        }

        public void turntable (string folder) {
            var frames = new Gee.ArrayList<Cairo.ImageSurface> ();
            for (int i = 0; i < 36; i++) {
                var img = view.snapshot_at (480, 640, i * 10);
                img.write_to_png (Path.build_filename (folder, "turntable-%02d.png".printf (i)));
                frames.add (img);
            }
            View3D.contact_sheet (frames, 6).write_to_png (Path.build_filename (folder, "turntable-sheet.png"));
            message (_("Saved 36 frames and a contact sheet"));
        }
    }
}
