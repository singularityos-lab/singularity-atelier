using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Atelier {

    public class ProductPanel : InspectorPanel {
        private Project project;
        private ProductEditor editor;
        private View3D view;
        private bool syncing;
        private int selected_face = -1;
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

            var ops = new PreferencesGroup (_("Edit the Cage"), _("Click a face in the view to select it"));
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
            double best = double.INFINITY;
            for (int f = 0; f < model.faces.size; f++) {
                var c = model.face_center (f);
                var n = model.face_normal (f);
                double d = c.distance (at) - at.sub (c).dot (n) * 0.5;
                if (d < best) {
                    best = d;
                    selected_face = f;
                }
            }
            refresh ();
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
