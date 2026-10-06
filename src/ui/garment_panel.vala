using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Atelier {

    public class GarmentPanel : InspectorPanel {
        private Project project;
        private View3D view;
        private GarmentSim? sim;
        private Mesh? avatar_mesh;
        private Mesh? garment;
        private Thread<void*>? worker;
        private int running;
        private string size;
        private ActionRow status_row;
        private Button simulate_button;
        private Button stop_button;
        private SelectionRow size_row;
        private Box fabric_box;
        private string fit_map = "material";

        public signal void message (string text);

        public GarmentPanel (Project project, View3D view) {
            this.project = project;
            this.view = view;
            size = project.pattern.active_size != "" ? project.pattern.active_size : project.pattern.table.base_size;

            var avatar = new PreferencesGroup (_("Avatar"));
            string[] sizes = {};
            foreach (var s in project.pattern.table.sizes) sizes += s;
            if (sizes.length == 0) sizes += size;
            size_row = new SelectionRow (_("Size"), sizes, size);
            size_row.selected.connect ((s) => {
                size = s;
                refresh ();
            });
            avatar.add_row (size_row);
            var pose_row = new ActionRow (_("Pose"));
            var pose = new BubbleSwitcher ();
            pose.add_option ("a-pose", _("A-Pose"));
            pose.add_option ("t-pose", _("T-Pose"));
            pose.set_active (project.garment.pose);
            pose.valign = Align.CENTER;
            pose.selected.connect ((p) => {
                project.garment.pose = p;
                refresh ();
            });
            pose_row.add_suffix (pose);
            avatar.add_row (pose_row);
            append (avatar);

            var fabric = new PreferencesGroup (_("Fabric"));
            string[] labels = {};
            foreach (var f in FabricPreset.all ()) labels += f.name;
            var default_row = new SelectionRow (_("Default Fabric"), labels, FabricPreset.find (project.garment.fabric_preset).name);
            default_row.selected.connect ((label) => {
                project.garment.fabric_preset = preset_by_name (label).id;
                project.touch ("garment");
            });
            fabric.add_row (default_row);
            append (fabric);
            fabric_box = new Box (Orientation.VERTICAL, 0);
            append (fabric_box);

            var simg = new PreferencesGroup (_("Simulation"), _("Pieces are placed around the avatar and sewn together. Smaller spacing is finer and slower."));
            simulate_button = Dialogs.header_button (simg, _("Simulate"), () => start (), true);
            status_row = new ActionRow (_("Ready"), _("Not simulated yet"));
            stop_button = new Button.with_label (_("Stop"));
            stop_button.valign = Align.CENTER;
            stop_button.visible = false;
            stop_button.clicked.connect (() => stop ());
            status_row.add_suffix (stop_button);
            simg.add_row (status_row);
            Dialogs.button_row (simg, _("Reset the Cloth"), _("Puts the pieces back around the avatar"), _("Reset"), () => {
                stop ();
                sim = null;
                garment = null;
                status_row.title = _("Ready");
                status_row.subtitle = _("Not simulated yet");
                show_scene ();
            });
            var spacing = new SpinRow (_("Particle Spacing"), _("In millimetres"), 8, 60, 1, project.garment.resolution);
            spacing.spin_btn.value_changed.connect (() => project.garment.resolution = (int) spacing.value);
            simg.add_row (spacing);
            append (simg);

            var fit = new PreferencesGroup (_("Fit Map"));
            string[] maps = { "material", "strain", "distance", "wireframe" };
            string[] map_labels = { _("Fabric"), _("Tension"), _("Distance"), _("Mesh") };
            var fit_row = new SelectionRow (_("Show"), map_labels, map_labels[0]);
            fit_row.selected.connect ((label) => {
                string m = "material";
                for (int i = 0; i < maps.length; i++) if (map_labels[i] == label) m = maps[i];
                fit_map = m;
                if (sim != null && (m == "strain" || m == "distance")) {
                    garment = sim.garment_mesh (m);
                    show_scene ();
                }
                view.shading = m;
            });
            fit.add_row (fit_row);
            append (fit);

            refresh ();
        }

        private static FabricPreset preset_by_name (string label) {
            foreach (var f in FabricPreset.all ()) if (f.name == label) return f;
            return FabricPreset.find (null);
        }

        private void rebuild_fabrics () {
            Widget? c;
            while ((c = fabric_box.get_first_child ()) != null) fabric_box.remove (c);
            if (project.pattern.pieces.size == 0) return;
            var g = new PreferencesGroup (_("Fabric per Piece"));
            string[] labels = {};
            foreach (var f in FabricPreset.all ()) labels += f.name;
            foreach (var piece in project.pattern.pieces) {
                string id = piece.id;
                string cur = project.garment.piece_fabrics.has_key (id) ? project.garment.piece_fabrics[id] : project.garment.fabric_preset;
                var row = new SelectionRow (piece.name, labels, FabricPreset.find (cur).name);
                row.selected.connect ((label) => {
                    project.garment.piece_fabrics[id] = preset_by_name (label).id;
                    project.touch ("garment");
                });
                g.add_row (row);
            }
            fabric_box.append (g);
        }

        public void refresh () {
            avatar_mesh = Avatar.build (project.pattern.table, size, project.garment.pose);
            if (sim != null && running == 0) {
                sim.set_avatar (project.pattern.table, size, project.garment.pose);
            }
            rebuild_fabrics ();
            show_scene ();
        }

        public void sync_pattern () {
            if (sim == null || running != 0) return;
            sim.rebuild (project.pattern.evaluate (size));
            sim.run (10);
            garment = sim.garment_mesh (fit_map == "distance" ? "distance" : "strain");
            show_scene ();
        }

        private void show_scene () {
            var list = new Gee.ArrayList<Mesh> ();
            if (avatar_mesh != null) list.add (avatar_mesh);
            if (garment != null) list.add (garment);
            view.set_meshes (list);
        }

        private void start () {
            if (running != 0) return;
            var result = project.pattern.evaluate (size);
            if (result.pieces.size == 0) {
                message (_("Add pattern pieces before simulating"));
                return;
            }
            if (sim == null) sim = new GarmentSim (result, project.garment, project.pattern.table, size);
            else sim.rebuild (result);
            AtomicInt.set (ref running, 1);
            simulate_button.sensitive = false;
            stop_button.visible = true;
            status_row.title = _("Simulating");
            var local = sim;
            string map = fit_map == "distance" ? "distance" : "strain";
            worker = new Thread<void*> ("atelier-cloth", () => {
                int total = 240;
                for (int f = 0; f < total && AtomicInt.get (ref running) == 1; f++) {
                    local.step (local.substeps);
                    if (f % 6 == 5 || f == total - 1) {
                        var mesh = local.garment_mesh (map);
                        int frame = local.frame;
                        Idle.add (() => {
                            garment = mesh;
                            status_row.subtitle = _("Frame %d").printf (frame);
                            show_scene ();
                            return Source.REMOVE;
                        });
                    }
                }
                Idle.add (() => {
                    finished ();
                    return Source.REMOVE;
                });
                return null;
            });
        }

        private void finished () {
            if (worker != null) {
                worker.join ();
                worker = null;
            }
            AtomicInt.set (ref running, 0);
            simulate_button.sensitive = true;
            stop_button.visible = false;
            if (sim != null) {
                status_row.title = _("Draped");
                status_row.subtitle = _("Largest seam gap %.1f mm, largest stretch %.0f%%").printf (sim.max_sew_gap (), sim.max_stretch () * 100);
            }
        }

        private void stop () {
            if (AtomicInt.get (ref running) == 1) AtomicInt.set (ref running, 2);
        }

        private Gtk.Window? window () {
            return get_root () as Gtk.Window;
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
                    var list = view.get_meshes ();
                    switch (kind) {
                        case "obj":
                            Obj.save (path, list);
                            break;
                        case "fbx":
                        case "fbxbin":
                            Fbx.save (path, list, kind == "fbxbin");
                            break;
                        case "png":
                            view.snapshot_image (1600, 1200, view.camera.yaw * 180 / Math.PI).write_to_png (path);
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
                var img = view.snapshot_image (480, 640, i * 10);
                img.write_to_png (Path.build_filename (folder, "turntable-%02d.png".printf (i)));
                frames.add (img);
            }
            View3D.contact_sheet (frames, 6).write_to_png (Path.build_filename (folder, "turntable-sheet.png"));
            message (_("Saved 36 frames and a contact sheet"));
        }
    }
}
