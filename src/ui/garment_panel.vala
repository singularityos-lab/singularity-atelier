using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Atelier {

    public class GarmentPanel : InspectorPanel {
        private Project project;
        private View3D view;
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
        private SelectionRow size_row;
        private Box fabric_box;
        private string fit_map = "material";
        private bool stale = true;
        private bool grabbing;
        private Scene.Vec3 grab_point;
        private static HashTable<string, BodyShape>? fits;

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
                stale = true;
                refresh ();
            });
            avatar.add_row (size_row);
            string[] pose_labels = {};
            foreach (var id in BodyPose.ids ()) pose_labels += BodyPose.label (id);
            var pose_row = new SelectionRow (_("Pose"), pose_labels, BodyPose.label (project.garment.pose));
            pose_row.selected.connect ((label) => {
                foreach (var id in BodyPose.ids ()) if (BodyPose.label (id) == label) project.garment.pose = id;
                project.touch ("garment");
                refresh ();
            });
            avatar.add_row (pose_row);
            append (avatar);

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
            append (simg);

            var fabric = new PreferencesGroup (_("Fabric"));
            string[] labels = {};
            foreach (var f in FabricPreset.all ()) labels += f.name;
            var default_row = new SelectionRow (_("Default Fabric"), labels, FabricPreset.find (project.garment.fabric_preset).name);
            default_row.selected.connect ((label) => {
                project.garment.fabric_preset = preset_by_name (label).id;
                project.touch ("garment");
                apply_fabrics ();
            });
            fabric.add_row (default_row);
            append (fabric);
            fabric_box = new Box (Orientation.VERTICAL, 0);
            append (fabric_box);

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
            append (fit);

            view.overlay.connect ((o) => {
                if (!get_mapped () || sim == null) return;
                var accent = Gdk.RGBA () { red = 0.16f, green = 0.50f, blue = 0.96f, alpha = 0.9f };
                int n = sim.stitch_count ();
                for (int i = 0; i < n; i++) {
                    Vec3 a, b;
                    sim.stitch (i, out a, out b);
                    if (a.distance (b) < 3) continue;
                    o.line (Scene.Vec3 (a.x, a.y, a.z), Scene.Vec3 (b.x, b.y, b.z), accent, 1.2);
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

        private static FabricPreset preset_by_name (string label) {
            foreach (var f in FabricPreset.all ()) if (f.name == label) return f;
            return FabricPreset.find (null);
        }

        private FabricPreset fabric_for (string piece_id) {
            return FabricPreset.find (project.garment.piece_fabrics.has_key (piece_id) ? project.garment.piece_fabrics[piece_id] : project.garment.fabric_preset);
        }

        private void apply_fabrics () {
            if (sim == null) return;
            foreach (var p in sim.pieces) sim.set_fabric (p, fabric_for (p.piece_id));
            view.queue_render ();
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
                var row = new SelectionRow (piece.name, labels, fabric_for (id).name);
                row.selected.connect ((label) => {
                    project.garment.piece_fabrics[id] = preset_by_name (label).id;
                    project.touch ("garment");
                    apply_fabrics ();
                });
                g.add_row (row);
            }
            fabric_box.append (g);
        }

        private void ensure_body () {
            var table = project.pattern.table;
            var dims = BodyDims.from_table (table, size);
            string gender = table.gender == "male" ? "male" : "female";
            string key = "%s %.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f".printf (gender, dims.height, dims.bust, dims.waist, dims.hip, dims.neck,
                dims.across_back, dims.arm, dims.upper_arm, dims.wrist, dims.inseam, dims.thigh, dims.knee, dims.ankle, dims.back_waist);
            string full = key + " " + project.garment.pose;
            if (body != null && body_key == full) return;
            if (fits == null) fits = new HashTable<string, BodyShape> (str_hash, str_equal);
            BodyShape? shape = fits[key];
            if (shape == null) {
                shape = BodyFit.fit (dims, gender);
                fits[key] = shape;
            }
            body = Body.build (shape, BodyPose.named (project.garment.pose));
            body_key = full;
            if (sim != null) stale = true;
        }

        private void ensure_sim () {
            ensure_body ();
            if (sim != null && !stale) return;
            stale = false;
            sim = null;
            var result = project.pattern.evaluate (size);
            if (result.pieces.size > 0) {
                sim = new GarmentSim (result, project.garment, body);
                sim.map = fit_map;
                sim.sync ();
            }
            show_scene ();
        }

        public void refresh () {
            if (running != 0) stop ();
            rebuild_fabrics ();
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
            if (body != null) list.add (body.mesh);
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
                    if (spent < 16000) Thread.usleep ((ulong) (16000 - spent));
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

        private ClothPiece? piece_of (Scene.Mesh? mesh) {
            if (sim == null || mesh == null) return null;
            foreach (var p in sim.pieces) if (p.mesh == mesh) return p;
            return null;
        }

        private bool on_press (double x, double y, Gdk.ModifierType state) {
            if (!get_mapped () || sim == null || running == 0) return false;
            Scene.Hit hit;
            var piece = piece_of (view.native_at (x, y, out hit));
            if (piece == null) return false;
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
