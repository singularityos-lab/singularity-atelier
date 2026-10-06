using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class Timelapse {
        public static Gee.ArrayList<Stroke> ordered (Sketch sk) {
            var list = new Gee.ArrayList<Stroke> ();
            var seen = new Gee.HashSet<Stroke> ();
            foreach (var ev in sk.timelapse) {
                var l = sk.find_layer (ev.layer);
                if (l == null || ev.stroke_index < 0 || ev.stroke_index >= l.strokes.size) continue;
                var s = l.strokes[ev.stroke_index];
                if (seen.contains (s)) continue;
                seen.add (s);
                list.add (s);
            }
            foreach (var l in sk.all_layers ()) foreach (var s in l.strokes) if (!seen.contains (s)) list.add (s);
            return list;
        }

        public static int render_frames (Sketch sk, string dir, int max_frames = 240, int width = 1280) throws Error {
            var strokes = ordered (sk);
            var b = sk.bounds ();
            if (b.is_empty ()) b = Rect (0, 0, 800, 600);
            b = b.inflate (20);
            double sc = width / b.w;
            int h = ((int) (b.h * sc) / 2) * 2;
            int w = (width / 2) * 2;
            int frames = int.min (max_frames, int.max (1, strokes.size));
            var visible = new Gee.HashSet<Stroke> ();
            var hidden = new Gee.HashMap<SketchLayer, Gee.ArrayList<Stroke>> ();
            foreach (var l in sk.all_layers ()) {
                var copy = new Gee.ArrayList<Stroke> ();
                copy.add_all (l.strokes);
                hidden[l] = copy;
            }
            for (int f = 0; f < frames; f++) {
                int upto = (int) Math.ceil ((double) (f + 1) / frames * strokes.size);
                for (int i = 0; i < upto && i < strokes.size; i++) visible.add (strokes[i]);
                foreach (var e in hidden.entries) {
                    e.key.strokes.clear ();
                    foreach (var s in e.value) if (visible.contains (s)) e.key.strokes.add (s);
                }
                var surf = new Cairo.ImageSurface (Cairo.Format.RGB24, w, h);
                var cr = new Cairo.Context (surf);
                cr.scale (sc, sc);
                cr.translate (-b.x, -b.y);
                SketchRenderer.draw (cr, sk);
                surf.write_to_png (Path.build_filename (dir, "frame%05d.png".printf (f)));
            }
            foreach (var e in hidden.entries) {
                e.key.strokes.clear ();
                e.key.strokes.add_all (e.value);
            }
            return frames;
        }

        public static async string export (Sketch sk, string folder, Gtk.Window? parent) throws Error {
            string frames_dir = Path.build_filename (folder, "timelapse-frames");
            DirUtils.create_with_parents (frames_dir, 0755);
            int n = render_frames (sk, frames_dir);
            string out_path = Path.build_filename (folder, "timelapse.webm");
            if (!Gst.is_initialized ()) {
                unowned string[] args = null;
                Gst.init (ref args);
            }
            string desc = "multifilesrc location=\"%s\" index=0 caps=\"image/png,framerate=24/1\" ! pngdec ! videoconvert ! vp8enc deadline=1 ! webmmux ! filesink location=\"%s\"".printf (
                Path.build_filename (frames_dir, "frame%05d.png"), out_path);
            Gst.Element pipeline;
            try {
                pipeline = Gst.parse_launch (desc);
            } catch (Error e) {
                throw new FormatError.UNSUPPORTED (_("Video encoding is not available: %s. The %d frames are in %s").printf (e.message, n, frames_dir));
            }
            var bus = pipeline.get_bus ();
            string? error = null;
            bool finished = false;
            bus.add_signal_watch ();
            bus.message.connect ((m) => {
                if (finished) return;
                if (m.type == Gst.MessageType.EOS) {
                    finished = true;
                    Idle.add (export.callback);
                } else if (m.type == Gst.MessageType.ERROR) {
                    Error err;
                    string dbg;
                    m.parse_error (out err, out dbg);
                    error = err.message;
                    finished = true;
                    Idle.add (export.callback);
                }
            });
            pipeline.set_state (Gst.State.PLAYING);
            yield;
            pipeline.set_state (Gst.State.NULL);
            bus.remove_signal_watch ();
            if (error != null) throw new FormatError.UNSUPPORTED (_("Video encoding failed: %s. The frames are in %s").printf (error, frames_dir));
            for (int i = 0; i < n; i++) FileUtils.remove (Path.build_filename (frames_dir, "frame%05d.png".printf (i)));
            DirUtils.remove (frames_dir);
            return out_path;
        }
    }
}
