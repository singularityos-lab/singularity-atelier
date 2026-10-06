using Gtk;

namespace Singularity.Apps.Atelier {

    public class View3D : DrawingArea {
        public Camera camera = new Camera ();
        public Renderer3D renderer = new CpuRenderer ();
        public RenderOptions options = new RenderOptions ();
        public string plane_mode = "";
        public double plane_offset;
        private Gee.ArrayList<Mesh> meshes = new Gee.ArrayList<Mesh> ();
        private Camera? drag_start;
        private bool interacting;
        private uint settle_id;
        private double zoom_start;
        private double rotate_last;
        private double pinch_cx;
        private double pinch_cy;
        private bool drawing_plane;
        private double pick_scale = 1;

        public signal void pick (int mesh_index, int vertex, int triangle);
        public signal void plane_point (double a, double b, bool first);
        public signal void plane_stroke_done ();

        public string shading {
            get { return options.shading; }
            set {
                options.shading = value;
                queue_draw ();
            }
        }

        public View3D () {
            hexpand = true;
            vexpand = true;
            focusable = true;
            set_draw_func (draw);
            var drag = new GestureDrag ();
            drag.button = 0;
            drag.drag_begin.connect ((x, y) => {
                drag_start = camera.copy ();
                interacting = true;
                if (plane_mode != "" && drag.get_current_button () == Gdk.BUTTON_PRIMARY) {
                    double a, b;
                    drawing_plane = ray_plane (x, y, plane_mode, plane_offset, out a, out b);
                    if (drawing_plane) plane_point (a, b, true);
                }
            });
            drag.drag_update.connect ((dx, dy) => {
                if (drag_start == null) return;
                double sx, sy;
                drag.get_start_point (out sx, out sy);
                if (drawing_plane) {
                    double a, b;
                    if (ray_plane (sx + dx, sy + dy, plane_mode, plane_offset, out a, out b)) plane_point (a, b, false);
                    return;
                }
                uint button = drag.get_current_button ();
                var state = drag.get_current_event_state ();
                bool pan = button == Gdk.BUTTON_MIDDLE || (state & Gdk.ModifierType.SHIFT_MASK) != 0;
                if (pan) {
                    pan_by (drag_start, dx, dy);
                } else {
                    camera.yaw = drag_start.yaw - dx * 0.01;
                    camera.pitch = (drag_start.pitch + dy * 0.01).clamp (-1.45, 1.45);
                }
                queue_draw ();
            });
            drag.drag_end.connect ((dx, dy) => {
                drag_start = null;
                if (drawing_plane) {
                    drawing_plane = false;
                    plane_stroke_done ();
                }
                settle ();
            });
            add_controller (drag);
            var scroll = new EventControllerScroll (EventControllerScrollFlags.VERTICAL);
            scroll.scroll.connect ((dx, dy) => {
                camera.distance = (camera.distance * Math.pow (1.12, dy)).clamp (50, 50000);
                interacting = true;
                queue_draw ();
                settle ();
                return true;
            });
            add_controller (scroll);
            var zoom = new GestureZoom ();
            zoom.begin.connect ((seq) => {
                zoom_start = camera.distance;
                drag_start = camera.copy ();
                zoom.get_bounding_box_center (out pinch_cx, out pinch_cy);
                interacting = true;
            });
            zoom.scale_changed.connect ((scale) => {
                if (scale > 0) camera.distance = (zoom_start / scale).clamp (50, 50000);
                double cx = 0, cy = 0;
                if (drag_start != null && zoom.get_bounding_box_center (out cx, out cy)) {
                    var saved = camera.distance;
                    pan_by (drag_start, cx - pinch_cx, cy - pinch_cy);
                    camera.distance = saved;
                }
                queue_draw ();
            });
            zoom.end.connect ((seq) => settle ());
            add_controller (zoom);
            var rotate = new GestureRotate ();
            rotate.begin.connect ((seq) => rotate_last = 0);
            rotate.angle_changed.connect ((angle, delta) => {
                camera.yaw -= delta - rotate_last;
                rotate_last = delta;
                interacting = true;
                queue_draw ();
            });
            rotate.end.connect ((seq) => settle ());
            add_controller (rotate);
            var click = new GestureClick ();
            click.released.connect ((n, x, y) => {
                if (plane_mode != "") return;
                int mi, vi;
                int px = (int) (x * pick_scale), py = (int) (y * pick_scale);
                if (renderer.pick (px, py, out mi, out vi)) {
                    var cpu = renderer as CpuRenderer;
                    pick (mi, vi, cpu != null ? cpu.picked_triangle (px, py) : -1);
                }
            });
            add_controller (click);
        }

        private void pan_by (Camera start, double dx, double dy) {
            Vec3 r, u, f;
            start.basis (out r, out u, out f);
            int h = int.max (1, get_height ());
            double k = start.distance * Math.tan (start.fov * Math.PI / 360) * 2 / h;
            camera.target = start.target.sub (r.scale (dx * k)).add (u.scale (dy * k));
        }

        private void settle () {
            if (settle_id != 0) Source.remove (settle_id);
            settle_id = Timeout.add (180, () => {
                settle_id = 0;
                interacting = false;
                queue_draw ();
                return Source.REMOVE;
            });
        }

        public void set_meshes (Gee.List<Mesh> list, bool frame = false) {
            bool first = meshes.size == 0;
            meshes = new Gee.ArrayList<Mesh> ();
            meshes.add_all (list);
            if (first || frame) camera.frame (meshes);
            queue_draw ();
        }

        public Gee.List<Mesh> get_meshes () {
            return meshes;
        }

        public void reset_camera () {
            camera = new Camera ();
            camera.frame (meshes);
            queue_draw ();
        }

        public bool ray_plane (double x, double y, string plane, double offset, out double a, out double b) {
            a = 0;
            b = 0;
            int w = int.max (1, get_width ()), h = int.max (1, get_height ());
            Vec3 r, u, f;
            camera.basis (out r, out u, out f);
            double focal = (h / 2.0) / Math.tan (camera.fov * Math.PI / 360);
            var dir = f.add (r.scale ((x - w / 2.0) / focal)).add (u.scale (-(y - h / 2.0) / focal)).normalized ();
            var eye = camera.eye ();
            Vec3 n;
            switch (plane) {
                case "yz": n = Vec3 (1, 0, 0); break;
                case "xz": n = Vec3 (0, 1, 0); break;
                default: n = Vec3 (0, 0, 1); break;
            }
            double den = dir.dot (n);
            if (den.abs () < 1e-6) return false;
            double t = (offset - eye.dot (n)) / den;
            if (t <= 0) return false;
            var p = eye.add (dir.scale (t));
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

        private void draw (DrawingArea area, Cairo.Context cr, int width, int height) {
            if (width <= 0 || height <= 0) return;
            double scale = interacting ? 0.5 : 1.0;
            int sw = int.max (1, (int) (width * scale * get_scale_factor ()));
            int sh = int.max (1, (int) (height * scale * get_scale_factor ()));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, sw, sh);
            renderer.render (surf, meshes, camera, options);
            cr.save ();
            cr.scale ((double) width / sw, (double) height / sh);
            cr.set_source_surface (surf, 0, 0);
            cr.paint ();
            cr.restore ();
            pick_scale = (double) sw / width;
        }

        public Cairo.ImageSurface snapshot_image (int w, int h, double yaw_deg) {
            var cam = camera.copy ();
            cam.yaw = yaw_deg * Math.PI / 180;
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var r = new CpuRenderer ();
            var opt = new RenderOptions ();
            opt.shading = options.shading;
            opt.wireframe = options.wireframe;
            r.render (surf, meshes, cam, opt);
            return surf;
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
