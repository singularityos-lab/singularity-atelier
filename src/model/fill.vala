using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class RegionFill {
        public static PathData? region (Sketch sketch, SketchLayer? only, Point seed, double tolerance, double resolution = 1.0) {
            var area = only != null ? only.bounds () : sketch.bounds ();
            if (area.is_empty () || !area.contains (seed.x, seed.y)) return null;
            area = area.inflate (4);
            double sc = 1.0 / resolution;
            int w = (int) Math.ceil (area.w * sc) + 2;
            int h = (int) Math.ceil (area.h * sc) + 2;
            if (w * h > 16000000) {
                sc = Math.sqrt (16000000.0 / (area.w * area.h));
                w = (int) Math.ceil (area.w * sc) + 2;
                h = (int) Math.ceil (area.h * sc) + 2;
            }
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surf);
            cr.scale (sc, sc);
            cr.translate (-area.x, -area.y);
            if (only != null) SketchRenderer.draw_layer (cr, only);
            else foreach (var l in sketch.layers) SketchRenderer.draw_layer (cr, l);
            surf.flush ();
            unowned uint8[] data = surf.get_data ();
            int stride = surf.get_stride ();
            int sx = (int) ((seed.x - area.x) * sc), sy = (int) ((seed.y - area.y) * sc);
            if (sx < 0 || sy < 0 || sx >= w || sy >= h) return null;
            int limit = (int) (tolerance.clamp (0, 1) * 255);
            var mask = new uint8[w * h];
            int seed_a = data[sy * stride + sx * 4 + 3];
            var stack = new Gee.ArrayList<int> ();
            stack.add (sy * w + sx);
            int count = 0;
            while (stack.size > 0) {
                int idx = stack.remove_at (stack.size - 1);
                if (mask[idx] != 0) continue;
                int x = idx % w, y = idx / w;
                int a = data[y * stride + x * 4 + 3];
                if ((a - seed_a).abs () > limit) continue;
                mask[idx] = 1;
                count++;
                if (x == 0 || y == 0 || x == w - 1 || y == h - 1) return null;
                stack.add (idx + 1);
                stack.add (idx - 1);
                stack.add (idx + w);
                stack.add (idx - w);
            }
            if (count < 4) return null;
            var grown = new uint8[w * h];
            for (int y = 1; y < h - 1; y++) {
                for (int x = 1; x < w - 1; x++) {
                    int i = y * w + x;
                    if (mask[i] != 0 || mask[i - 1] != 0 || mask[i + 1] != 0 || mask[i - w] != 0 || mask[i + w] != 0) grown[i] = 1;
                }
            }
            var rings = trace (grown, w, h);
            var path = new PathData ();
            foreach (var ring in rings) {
                if (ring.pts.length < 3) continue;
                Point[] docpts = new Point[ring.pts.length];
                for (int i = 0; i < ring.pts.length; i++) docpts[i] = Point (area.x + ring.pts[i].x / sc, area.y + ring.pts[i].y / sc);
                var simple = Polyline.simplify (docpts, 0.6 / sc);
                if (simple.length >= 3) path.add_polygon (simple, true);
            }
            return path.is_empty () ? null : path;
        }

        public static Gee.ArrayList<PointList> trace (uint8[] m, int w, int h) {
            var edges = new Gee.HashMap<int64?, int64?> ((k) => (uint) (k ^ (k >> 32)), (a, b) => a == b);
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    if (m[y * w + x] == 0) continue;
                    bool up = y > 0 && m[(y - 1) * w + x] != 0;
                    bool down = y < h - 1 && m[(y + 1) * w + x] != 0;
                    bool left = x > 0 && m[y * w + x - 1] != 0;
                    bool right = x < w - 1 && m[y * w + x + 1] != 0;
                    if (!up) edges[key (x, y)] = key (x + 1, y);
                    if (!right) edges[key (x + 1, y)] = key (x + 1, y + 1);
                    if (!down) edges[key (x + 1, y + 1)] = key (x, y + 1);
                    if (!left) edges[key (x, y + 1)] = key (x, y);
                }
            }
            var rings = new Gee.ArrayList<PointList> ();
            var used = new Gee.HashSet<int64?> ((k) => (uint) (k ^ (k >> 32)), (a, b) => a == b);
            foreach (var start in edges.keys) {
                if (used.contains (start)) continue;
                Point[] ring = {};
                int64 cur = start;
                int guard = 0;
                while (!used.contains (cur) && edges.has_key (cur) && guard++ < 4000000) {
                    used.add (cur);
                    ring += Point ((double) (cur >> 32), (double) (cur & 0xffffffff));
                    cur = edges[cur];
                }
                if (ring.length >= 3) rings.add (new PointList (ring));
            }
            return rings;
        }

        private static int64 key (int x, int y) {
            return ((int64) x << 32) | (int64) y;
        }
    }
}
