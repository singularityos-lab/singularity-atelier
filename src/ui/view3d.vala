using Gtk;

namespace Singularity.Apps.Atelier {

    public class View3D : Scene.SceneView {
        public string plane_mode = "";
        public double plane_offset;
        private Gee.ArrayList<Mesh> source = new Gee.ArrayList<Mesh> ();
        private Gee.ArrayList<Scene.Mesh> native = new Gee.ArrayList<Scene.Mesh> ();
        private string shading_name = "material";
        private bool drawing_plane;
        private bool picking;
        private double press_x;
        private double press_y;

        private bool tool_active;

        public signal bool tool_pressed (double x, double y, Gdk.ModifierType state);
        public signal void tool_dragged (double x, double y, Gdk.ModifierType state);
        public signal void tool_released (double x, double y);
        public signal void pick (int mesh_index, int vertex, int triangle);
        public signal void plane_point (double a, double b, bool first);
        public signal void plane_stroke_done ();

        public string shading {
            get { return shading_name; }
            set {
                shading_name = value;
                rebuild ();
            }
        }

        public View3D () {
            auto_floor = false;
            camera.target = Scene.Vec3 (0, 1000, 0);
            camera.distance = 3200;
            overlay.connect ((o) => {
                foreach (var m in source) {
                    if (m.name != "cage" || !m.visible) continue;
                    var c = Gdk.RGBA () { red = (float) m.color.r, green = (float) m.color.g, blue = (float) m.color.b, alpha = 1 };
                    foreach (var v in m.vertices) o.point (Scene.Vec3 (v.x, v.y, v.z), c, 5);
                }
            });
            pressed.connect ((x, y, button, state) => {
                if (button != Gdk.BUTTON_PRIMARY) return false;
                press_x = x;
                press_y = y;
                tool_active = tool_pressed (x, y, state);
                if (tool_active) return true;
                if (plane_mode != "") {
                    double a, b;
                    drawing_plane = ray_plane (x, y, plane_mode, plane_offset, out a, out b);
                    if (drawing_plane) plane_point (a, b, true);
                    return drawing_plane;
                }
                Scene.Hit hit;
                picking = pick_at (x, y, out hit);
                return picking;
            });
            dragged.connect ((x, y, state) => {
                if (tool_active) {
                    tool_dragged (x, y, state);
                    return;
                }
                if (!drawing_plane) return;
                double a, b;
                if (ray_plane (x, y, plane_mode, plane_offset, out a, out b)) plane_point (a, b, false);
            });
            released.connect ((x, y, button) => {
                if (tool_active) {
                    tool_active = false;
                    tool_released (x, y);
                    return;
                }
                if (drawing_plane) {
                    drawing_plane = false;
                    plane_stroke_done ();
                    return;
                }
                if (!picking || Math.hypot (x - press_x, y - press_y) > 4) return;
                picking = false;
                Scene.Hit hit;
                if (!pick_at (x, y, out hit)) return;
                unowned GenericArray<Scene.Mesh> shown = meshes ();
                for (int i = 0; i < shown.length; i++) if (shown[i] == hit.mesh) pick (i, hit.nearest_vertex (), hit.triangle);
            });
        }

        private void rebuild () {
            clear ();
            shading_override = -1;
            wireframe = false;
            switch (shading_name) {
                case "strain":
                    shading_override = Scene.Shading.RAMP;
                    ramp_min = -0.02;
                    ramp_max = 0.12;
                    break;
                case "distance":
                    shading_override = Scene.Shading.RAMP;
                    ramp_min = 60;
                    ramp_max = 0;
                    break;
                case "curvature":
                    shading_override = Scene.Shading.RAMP;
                    ramp_min = 0;
                    ramp_max = 1;
                    break;
                case "zebra":
                    shading_override = Scene.Shading.ZEBRA;
                    break;
                case "wireframe":
                    shading_override = Scene.Shading.CLAY;
                    wireframe = true;
                    break;
            }
            auto_floor = native.size == 0;
            foreach (var m in native) add (m);
            foreach (var m in source) add (m.to_scene (shading_name == "curvature"));
            queue_render ();
        }

        public void set_meshes (Gee.List<Mesh> list, bool frame = false) {
            bool first = source.size == 0;
            source = new Gee.ArrayList<Mesh> ();
            source.add_all (list);
            rebuild ();
            if (first || frame) frame_all ();
        }

        public void set_native (Gee.List<Scene.Mesh> list, bool frame = false) {
            native = new Gee.ArrayList<Scene.Mesh> ();
            native.add_all (list);
            rebuild ();
            if (frame) frame_all ();
        }

        public Scene.Mesh? native_at (double x, double y, out Scene.Hit hit) {
            if (!pick_at (x, y, out hit)) return null;
            return native.contains (hit.mesh) ? hit.mesh : null;
        }

        public Gee.List<Mesh> get_meshes () {
            return source;
        }

        public void reset_camera () {
            camera = new Scene.Camera ();
            frame_all ();
        }

        public bool ray_plane (double x, double y, string plane, double offset, out double a, out double b) {
            a = 0;
            b = 0;
            Scene.Vec3 n, at, p;
            switch (plane) {
                case "yz":
                    n = Scene.Vec3 (1, 0, 0);
                    at = Scene.Vec3 (offset, 0, 0);
                    break;
                case "xz":
                    n = Scene.Vec3 (0, 1, 0);
                    at = Scene.Vec3 (0, offset, 0);
                    break;
                default:
                    n = Scene.Vec3 (0, 0, 1);
                    at = Scene.Vec3 (0, 0, offset);
                    break;
            }
            if (!ray (x, y).plane (at, n, out p)) return false;
            switch (plane) {
                case "yz":
                    a = p.z;
                    b = p.y;
                    break;
                case "xz":
                    a = p.x;
                    b = p.z;
                    break;
                default:
                    a = p.x;
                    b = p.y;
                    break;
            }
            return true;
        }

        public Cairo.ImageSurface snapshot_at (int w, int h, double yaw_deg) {
            var cam = camera.copy ();
            cam.yaw = yaw_deg * Math.PI / 180;
            return snapshot_image (w, h, cam) ?? new Cairo.ImageSurface (Cairo.Format.ARGB32, 1, 1);
        }

        public static Cairo.ImageSurface contact_sheet (Gee.List<Cairo.ImageSurface> frames, int columns) {
            int n = frames.size;
            if (n == 0) return new Cairo.ImageSurface (Cairo.Format.ARGB32, 1, 1);
            int fw = frames[0].get_width (), fh = frames[0].get_height ();
            int cols = int.max (1, columns);
            int rows = (n + cols - 1) / cols;
            var sheet = new Cairo.ImageSurface (Cairo.Format.ARGB32, fw * cols, fh * rows);
            var cr = new Cairo.Context (sheet);
            cr.set_source_rgb (1, 1, 1);
            cr.paint ();
            for (int i = 0; i < n; i++) {
                cr.set_source_surface (frames[i], (i % cols) * fw, (i / cols) * fh);
                cr.paint ();
            }
            return sheet;
        }
    }
}
