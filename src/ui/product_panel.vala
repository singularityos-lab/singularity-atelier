using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Atelier {

    public class ProductPanel : InspectorPanel {
        private Project project;
        private ProductEditor editor;
        private View3D view;
        private bool syncing;
        private int selected_face = -1;
        private bool dragging;
        private string component = "face";
        private int selected_vertex = -1;
        private int edge_a = -1;
        private int edge_b = -1;
        private bool symmetry = true;
        private bool show_package = true;
        private Scene.Vec3 drag_last;
        private ActionRow selection_row;
        private SpinRow amount;
        private SpinRow move_x;
        private SpinRow move_y;
        private SpinRow move_z;
        private SpinRow level_row;
        private SelectionRow material_row;
        private SpinRow plane_offset;
        private SpinRow circle_radius;
        private SpinRow radius_row;
        private Choice plane_switch;
        private const string[] PLANES = { "xy", "yz", "xz" };
        private SwitchRow draw_row;
        private SwitchRow comb_row;

        public signal void message (string text);

        public ProductModel model {
            get { return project.product; }
        }

        public ProductPanel (Project project, History history, View3D view) {
            this.project = project;
            this.editor = new ProductEditor (project, history);
            this.view = view;

            var shape = new PreferencesGroup (_("Start From"), _("A primitive replaces the current cage"));
            foreach (var id in new string[] { "cube", "cylinder", "sphere" }) {
                string label = id == "cube" ? _("Cube") : (id == "cylinder" ? _("Cylinder") : _("Sphere"));
                string kind = id;
                action_row (shape, label, null, _("Create"), () => {
                    editor.primitive (kind);
                    selected_face = -1;
                    view.reset_camera ();
                    return true;
                });
            }
            append (shape);

            var car = new PreferencesGroup (_("Vehicle Body"), _("A body with the proportions of a package, ready to reshape."));
            string[] kinds = {};
            foreach (unowned string k in VehicleTemplate.KINDS) kinds += VehicleTemplate.label (k);
            var kind_row = new SelectionRow (_("Package"), kinds, kinds[0]);
            car.add_row (kind_row);
            action_row (car, _("Body and Wheels"), _("Replaces the current cage and surfaces"), _("Create"), () => {
                string chosen = VehicleTemplate.KINDS[0];
                foreach (unowned string k in VehicleTemplate.KINDS) if (VehicleTemplate.label (k) == kind_row.current_value) chosen = k;
                editor.vehicle (chosen);
                selected_face = -1;
                view.reset_camera ();
                return true;
            });
            append (car);

            var views = new PreferencesGroup (_("View"));
            string[] view_ids = { "perspective", "side", "front", "rear", "top" };
            string[] view_labels = { _("Perspective"), _("Side"), _("Front"), _("Rear"), _("Top") };
            var view_row = new SelectionRow (_("Camera"), view_labels, view_labels[0]);
            view_row.selected.connect ((label) => {
                for (int i = 0; i < view_ids.length; i++) if (view_labels[i] == label) look (view_ids[i]);
            });
            views.add_row (view_row);
            var package_row = new SwitchRow (_("Package Outline"), _("Side profile, wheels and axle lines of the chosen package"));
            package_row.active = show_package;
            package_row.notify["active"].connect (() => {
                show_package = package_row.active;
                view.queue_render ();
            });
            views.add_row (package_row);
            append (views);

            var ops = new PreferencesGroup (_("Edit the Cage"), _("Pick a component, then drag it in the view. Faces move along their normal, Shift moves them freely."));
            string[] comp_ids = { "face", "edge", "vertex" };
            string[] comp_labels = { _("Faces"), _("Edges"), _("Points") };
            var comp_row = new SelectionRow (_("Select"), comp_labels, comp_labels[0]);
            comp_row.selected.connect ((label) => {
                for (int i = 0; i < comp_ids.length; i++) if (comp_labels[i] == label) component = comp_ids[i];
                view.queue_render ();
            });
            ops.add_row (comp_row);
            var sym_row = new SwitchRow (_("Symmetry"), _("Mirrors every move across the centre plane"));
            sym_row.active = symmetry;
            sym_row.notify["active"].connect (() => symmetry = sym_row.active);
            ops.add_row (sym_row);
            action_row (ops, _("Insert an Edge Loop"), _("Cuts the ring of faces across the selected edge"), _("Insert"), () => {
                if (edge_a < 0 || !editor.insert_loop (edge_a, edge_b)) return false;
                edge_a = -1;
                edge_b = -1;
                return true;
            });
            selection_row = new ActionRow (_("No Face Selected"));
            ops.add_row (selection_row);
            amount = new SpinRow (_("Amount"), _("In millimetres"), -500, 500, 1, 30);
            ops.add_row (amount);
            action_row (ops, _("Extrude the Face"), _("Pushes it out by the amount"), _("Extrude"), () => editor.extrude_face (selected_face, amount.value));
            action_row (ops, _("Inset the Face"), _("Adds a smaller face inside it"), _("Inset"), () => editor.inset_face (selected_face, amount.value));
            action_row (ops, _("Sharp Edges"), _("Creases the edges of the face"), _("Sharpen"), () => editor.crease_face (selected_face, true));
            action_row (ops, _("Smooth Edges"), _("Removes the creases of the face"), _("Smooth"), () => editor.crease_face (selected_face, false));
            move_x = new SpinRow (_("Move X"), null, -1000, 1000, 1, 0);
            move_y = new SpinRow (_("Move Y"), null, -1000, 1000, 1, 0);
            move_z = new SpinRow (_("Move Z"), null, -1000, 1000, 1, 0);
            ops.add_row (move_x);
            ops.add_row (move_y);
            ops.add_row (move_z);
            action_row (ops, _("Move the Face"), _("By the X, Y and Z offsets"), _("Move"), () => editor.move_face (selected_face, Vec3 (move_x.value, move_y.value, move_z.value)));
            var del_row = new ActionRow (_("Delete the Face"), _("Leaves an opening in the cage"));
            var del_btn = action_button (_("Delete"), () => {
                if (!editor.delete_face (selected_face)) return false;
                selected_face = -1;
                return true;
            });
            del_btn.add_css_class ("destructive-action");
            del_row.add_suffix (del_btn);
            ops.add_row (del_row);
            append (ops);

            var look = new PreferencesGroup (_("Surface"));
            level_row = new SpinRow (_("Smoothness"), _("Subdivision levels"), 0, 4, 1, model.levels);
            level_row.spin_btn.value_changed.connect (() => {
                if (!syncing && editor.set_levels ((int) level_row.value)) refresh ();
            });
            look.add_row (level_row);
            string[] labels = {};
            foreach (var m in ProductModel.MATERIALS) labels += ProductModel.material_label (m);
            material_row = new SelectionRow (_("Material"), labels, ProductModel.material_label (model.material));
            material_row.selected.connect ((label) => {
                if (syncing) return;
                foreach (var m in ProductModel.MATERIALS) {
                    if (ProductModel.material_label (m) == label && editor.set_material (m)) refresh ();
                }
            });
            look.add_row (material_row);
            string[] shadings = { "material", "zebra", "curvature", "wireframe" };
            string[] shading_labels = { _("Material"), _("Zebra"), _("Curvature"), _("Mesh") };
            var analysis_row = new SelectionRow (_("Analysis"), shading_labels, shading_labels[0]);
            analysis_row.selected.connect ((label) => {
                for (int i = 0; i < shadings.length; i++) if (shading_labels[i] == label) view.shading = shadings[i];
            });
            look.add_row (analysis_row);
            append (look);

            var sketch = new PreferencesGroup (_("Sketch on Planes"), _("Draw curves on a plane, then build surfaces from them"));
            plane_switch = Dialogs.choice_row (sketch, _("Plane"), { _("Front"), _("Side"), _("Top") }, 0);
            plane_switch.notify["selected"].connect (() => update_plane ());
            plane_offset = new SpinRow (_("Plane Offset"), _("In millimetres"), -2000, 2000, 5, 0);
            plane_offset.spin_btn.value_changed.connect (() => update_plane ());
            sketch.add_row (plane_offset);
            draw_row = new SwitchRow (_("Draw on the Plane"), _("Drag in the view to draw a curve"), false);
            draw_row.switch_btn.notify["active"].connect (() => update_plane ());
            sketch.add_row (draw_row);
            circle_radius = new SpinRow (_("Circle Radius"), _("In millimetres"), 1, 2000, 1, 60);
            sketch.add_row (circle_radius);
            action_row (sketch, _("Exact Circle"), _("Rational, on the plane"), _("Add"), () => {
                editor.add_circle (PLANES[plane_switch.selected], plane_offset.value, circle_radius.value);
                return true;
            });
            action_row (sketch, _("Last Curve"), _("Removes the curve drawn last"), _("Remove"), () => editor.remove_last_curve ());
            var cont_row = new ActionRow (_("Continuity"), _("Between the last two curves"));
            var check = new Button.with_label (_("Check"));
            check.valign = Align.CENTER;
            check.clicked.connect (check_continuity);
            cont_row.add_suffix (check);
            sketch.add_row (cont_row);
            comb_row = new SwitchRow (_("Curvature Combs"), _("Curvature along each curve"), false);
            comb_row.switch_btn.notify["active"].connect (() => refresh ());
            sketch.add_row (comb_row);
            append (sketch);

            var surf = new PreferencesGroup (_("Build Surfaces"), _("Revolve, extrude and sweep use the last curve, loft joins all curves"));
            radius_row = new SpinRow (_("Depth or Diameter"), _("In millimetres"), 1, 2000, 1, 40);
            surf.add_row (radius_row);
            action_row (surf, _("Surface of Revolution"), _("Turns the last curve around the vertical axis"), _("Revolve"), () => build (() => editor.revolve ()));
            action_row (surf, _("Extrusion"), _("Pulls the last curve by the depth"), _("Extrude"), () => build (() => editor.extrude (radius_row.value)));
            action_row (surf, _("Sweep"), _("Moves a circle of the diameter along the last curve"), _("Sweep"), () => build (() => editor.sweep (radius_row.value)));
            action_row (surf, _("Loft"), _("Joins all curves with one surface"), _("Loft"), () => build (() => editor.loft ()));
            action_row (surf, _("Built Surfaces"), _("Removes every built surface"), _("Clear"), () => editor.clear_surfaces ());
            append (surf);

            view.pick.connect (on_pick);
            view.overlay.connect ((o) => {
                if (!get_mapped () || model.is_empty ()) return;
                var hot = Gdk.RGBA () { red = 1.0f, green = 0.6f, blue = 0.1f, alpha = 1 };
                if (component == "vertex" && selected_vertex >= 0 && selected_vertex < model.cage.vertices.size) {
                    var v = model.cage.vertices[selected_vertex];
                    o.point (Scene.Vec3 (v.x, v.y, v.z), hot, 11);
                }
                if (component == "edge" && edge_a >= 0 && edge_a < model.cage.vertices.size && edge_b < model.cage.vertices.size) {
                    var a2 = model.cage.vertices[edge_a], b2 = model.cage.vertices[edge_b];
                    o.line (Scene.Vec3 (a2.x, a2.y, a2.z), Scene.Vec3 (b2.x, b2.y, b2.z), hot, 3.5);
                }
                if (show_package && model.vehicle != "") draw_package (o);
            });
            view.tool_pressed.connect ((x, y, state) => {
                if (!get_mapped () || view.plane_mode != "" || model.is_empty ()) return false;
                Scene.Hit hit;
                if (component == "vertex") {
                    int found = vertex_at (x, y);
                    if (found < 0) return false;
                    selected_vertex = found;
                    var v = model.cage.vertices[found];
                    drag_last = Scene.Vec3 (v.x, v.y, v.z);
                } else if (component == "edge") {
                    int ea, eb;
                    if (!edge_at (x, y, out ea, out eb)) return false;
                    edge_a = ea;
                    edge_b = eb;
                    var m = model.cage.vertices[ea].lerp (model.cage.vertices[eb], 0.5);
                    drag_last = Scene.Vec3 (m.x, m.y, m.z);
                } else {
                    if (selected_face < 0 || selected_face >= model.faces.size) return false;
                    if (!view.pick_at (x, y, out hit) || nearest_face (Vec3 (hit.point.x, hit.point.y, hit.point.z)) != selected_face) return false;
                    drag_last = hit.point;
                }
                dragging = true;
                editor.begin_drag ();
                refresh ();
                return true;
            });
            view.tool_dragged.connect ((x, y, state) => {
                if (!dragging) return;
                Scene.Vec3 r, u, f, at;
                view.camera.basis (out r, out u, out f);
                if (!view.ray (x, y).plane (drag_last, f, out at)) return;
                var delta = Vec3 (at.x - drag_last.x, at.y - drag_last.y, at.z - drag_last.z);
                int[] ids = {};
                if (component == "vertex") ids += selected_vertex;
                else if (component == "edge") {
                    ids += edge_a;
                    ids += edge_b;
                } else {
                    if ((state & Gdk.ModifierType.SHIFT_MASK) == 0) {
                        var n = model.face_normal (selected_face);
                        delta = n.scale (delta.dot (n));
                    }
                    foreach (var i in model.faces[selected_face]) ids += i;
                }
                editor.drag_vertices (ids, delta, symmetry);
                drag_last = Scene.Vec3 (drag_last.x + delta.x, drag_last.y + delta.y, drag_last.z + delta.z);
                view.set_meshes (scene ());
            });
            view.tool_released.connect ((x, y) => {
                if (!dragging) return;
                dragging = false;
                editor.end_drag ();
            });
            view.plane_point.connect (on_plane_point);
            view.plane_stroke_done.connect (() => {
                if (editor.end_stroke ()) refresh ();
                else view.set_meshes (scene ());
            });
            history.restored.connect (() => {
                selected_face = -1;
            });
            if (model.is_empty () && model.surfaces.size == 0 && model.sketches.size == 0) model.make_cube (200);
            refresh ();
        }

        private delegate bool Edit ();
        private delegate void Build () throws ProductError;

        private Button action_button (string label, owned Edit edit) {
            var b = new Button.with_label (label);
            b.valign = Align.CENTER;
            b.clicked.connect (() => {
                if (edit ()) refresh ();
            });
            return b;
        }

        private void action_row (PreferencesGroup g, string title, string? subtitle, string label, owned Edit edit) {
            var row = new ActionRow (title, subtitle);
            row.add_suffix (action_button (label, (owned) edit));
            g.add_row (row);
        }

        private bool build (Build op) {
            try {
                op ();
                return true;
            } catch (ProductError e) {
                message (e.message);
                return false;
            }
        }

        private void check_continuity () {
            if (model.sketches.size < 2) {
                message (_("Draw at least two curves"));
                return;
            }
            var a = model.sketches[model.sketches.size - 2].to_nurbs (24);
            var b = model.sketches[model.sketches.size - 1].to_nurbs (24);
            double tol = double.max (1, a.length () * 0.01);
            message (ContinuityCheck.between (a, b, tol, 3, 0.15).label ());
        }

        private void update_plane () {
            view.plane_mode = draw_row.active ? (PLANES[plane_switch.selected]) : "";
            view.plane_offset = plane_offset.value;
        }

        private void on_pick (int mesh_index, int vertex, int triangle) {
            if (!is_visible () || view.plane_mode != "" || model.is_empty ()) return;
            var list = view.get_meshes ();
            if (mesh_index < 0 || mesh_index >= list.size || list[mesh_index].name != "product") return;
            var m = list[mesh_index];
            Vec3 at = m.vertices[vertex];
            if (triangle >= 0 && triangle * 3 + 2 < m.triangles.size) {
                at = m.vertices[m.triangles[triangle * 3]].add (m.vertices[m.triangles[triangle * 3 + 1]]).add (m.vertices[m.triangles[triangle * 3 + 2]]).scale (1.0 / 3);
            }
            selected_face = nearest_face (at);
            refresh ();
        }

        private void draw_package (Scene.Overlay o) {
            var t = VehicleTemplate.preset (model.vehicle);
            var ink = Gdk.RGBA () { red = 0.15f, green = 0.3f, blue = 0.55f, alpha = 0.55f };
            Singularity.Vector.PathData[] paths = { t.body (), t.wheels (), t.guides (), t.ground_line () };
            foreach (var path in paths) {
                foreach (var poly in path.flatten (2)) {
                    Scene.Vec3[] pts = {};
                    foreach (var q in poly.pts) pts += Scene.Vec3 (t.length / 2 - q.x, -q.y, 0);
                    o.polyline (pts, ink, 1.2, false, poly.closed);
                }
            }
        }

        private int vertex_at (double x, double y) {
            int found = -1;
            double best = 14;
            for (int i = 0; i < model.cage.vertices.size; i++) {
                var v = model.cage.vertices[i];
                double sx, sy;
                if (!view.project (Scene.Vec3 (v.x, v.y, v.z), out sx, out sy)) continue;
                double d = Math.hypot (sx - x, sy - y);
                if (d < best) {
                    best = d;
                    found = i;
                }
            }
            return found;
        }

        private bool edge_at (double x, double y, out int ea, out int eb) {
            ea = -1;
            eb = -1;
            double best = 10;
            var list = model.edges ();
            for (int i = 0; i < list.length[0]; i++) {
                var a = model.cage.vertices[list[i, 0]], b = model.cage.vertices[list[i, 1]];
                double ax, ay, bx, by;
                if (!view.project (Scene.Vec3 (a.x, a.y, a.z), out ax, out ay)) continue;
                if (!view.project (Scene.Vec3 (b.x, b.y, b.z), out bx, out by)) continue;
                double d = Singularity.Vector.PathData.segment_distance (Singularity.Vector.Point (ax, ay), Singularity.Vector.Point (bx, by), x, y);
                if (d < best) {
                    best = d;
                    ea = list[i, 0];
                    eb = list[i, 1];
                }
            }
            return ea >= 0;
        }

        private void look (string where) {
            var c = view.camera.copy ();
            c.fov = where == "perspective" ? 32 : 3;
            switch (where) {
                case "side":
                    c.yaw = 0;
                    c.pitch = 0;
                    break;
                case "front":
                    c.yaw = Math.PI / 2;
                    c.pitch = 0;
                    break;
                case "rear":
                    c.yaw = -Math.PI / 2;
                    c.pitch = 0;
                    break;
                case "top":
                    c.yaw = 0;
                    c.pitch = 1.5;
                    break;
                default:
                    c.yaw = 0.7;
                    c.pitch = 0.25;
                    break;
            }
            view.max_distance = 400000;
            view.camera = c;
            view.frame_all ();
        }

        private int nearest_face (Vec3 at) {
            double best = double.INFINITY;
            int found = -1;
            for (int f = 0; f < model.faces.size; f++) {
                var c = model.face_center (f);
                var n = model.face_normal (f);
                double d = c.distance (at) - at.sub (c).dot (n) * 0.5;
                if (d < best) {
                    best = d;
                    found = f;
                }
            }
            return found;
        }

        private void on_plane_point (double a, double b, bool first) {
            if (first || !editor.drawing) editor.begin_stroke (view.plane_mode, view.plane_offset);
            if (editor.stroke_point (a, b)) view.set_meshes (scene ());
        }

        private Gee.ArrayList<Mesh> scene () {
            var list = model.scene ();
            if (comb_row.active) {
                foreach (var c in model.sketches) {
                    if (c.count () < 3) continue;
                    var n = c.to_nurbs (24);
                    var comb = n.comb (80, n.length () * 2);
                    comb.color = Rgba (0.85, 0.25, 0.55, 1);
                    list.add (comb);
                }
            }
            if (selected_face >= 0 && selected_face < model.faces.size) {
                var sel = new Mesh ();
                sel.name = "selection";
                var face = model.faces[selected_face];
                foreach (var i in face) sel.vertices.add (model.cage.vertices[i]);
                for (int k = 0; k < face.size; k++) sel.add_line (k, (k + 1) % face.size);
                sel.color = Rgba (1, 0.6, 0.1, 1);
                list.add (sel);
            }
            return list;
        }

        public void refresh () {
            view.set_native (new Gee.ArrayList<Scene.Mesh> ());
            syncing = true;
            level_row.value = model.levels;
            material_row.current_value = ProductModel.material_label (model.material);
            syncing = false;
            if (selected_face >= model.faces.size) selected_face = -1;
            selection_row.title = selected_face < 0 ? _("No Face Selected") : _("Face %d Selected").printf (selected_face + 1);
            view.set_meshes (scene ());
        }

        public void export_as (string kind) {
            var d = new FileDialog ();
            d.title = _("Export");
            d.initial_name = "%s.%s".printf (project.title != "" ? project.title : _("Product"), kind == "fbxbin" ? "fbx" : kind);
            d.save.begin (get_root () as Gtk.Window, null, (o, res) => {
                try {
                    var file = d.save.end (res);
                    if (file == null) return;
                    var list = new Gee.ArrayList<Mesh> ();
                    foreach (var m in model.scene ()) if (m.triangles.size > 0) list.add (m);
                    if (kind == "stp") {
                        if (model.nurbs.size == 0 && model.sketches.size == 0) {
                            message (_("Build a surface or draw a curve first"));
                            return;
                        }
                        Step.save (file.get_path (), project.title != "" ? project.title : _("Product"), model.nurbs, model.curves ());
                    } else if (kind == "obj") {
                        Obj.save (file.get_path (), list);
                    } else if (kind == "fbx" || kind == "fbxbin") {
                        Fbx.save (file.get_path (), list, kind == "fbxbin");
                    } else {
                        Gltf.save (file.get_path (), list);
                    }
                    message (_("Exported %s").printf (file.get_basename ()));
                } catch (Error e) {
                    if (!(e is Gtk.DialogError.DISMISSED)) message (e.message);
                }
            });
        }
    }
}
