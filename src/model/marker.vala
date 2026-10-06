using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class MarkerSettings {
        public double fabric_width = 1500;
        public double spacing = 3;
        public double resolution = 5;
        public string rotations = "180";
        public bool allow_flip;
        public Gee.HashMap<string, int> ratio = new Gee.HashMap<string, int> ();
        public string material = "fabric";
    }

    public class MarkerPlacement {
        public string piece_id;
        public string size;
        public Point[] outline;
        public double x;
        public double y;
        public double rotation;
        public bool flipped;
        public string label = "";
    }

    public class MarkerResult {
        public Gee.ArrayList<MarkerPlacement> placements = new Gee.ArrayList<MarkerPlacement> ();
        public double length;
        public double width;
        public double used_area;
        public int unplaced;

        public double efficiency () {
            if (length <= 0 || width <= 0) return 0;
            return used_area / (length * width) * 100;
        }

        public double length_m () {
            return length / 1000;
        }
    }

    public class Marker {
        private class Item {
            public string piece_id;
            public string size;
            public string label;
            public Point[] outline;
            public double area;
        }

        private class Grid {
            public int cols;
            public int rows;
            public uint8[] cells;

            public Grid (int cols, int rows) {
                this.cols = cols;
                this.rows = rows;
                cells = new uint8[cols * rows];
            }

            public bool get (int c, int r) {
                if (c < 0 || r < 0 || r >= rows) return true;
                if (c >= cols) return false;
                return cells[r * cols + c] != 0;
            }

            public void set (int c, int r) {
                if (c < 0 || r < 0 || c >= cols || r >= rows) return;
                cells[r * cols + c] = 1;
            }
        }

        public static MarkerResult compute (Pattern pattern, MarkerSettings s) {
            var items = new Gee.ArrayList<Item> ();
            var sizes = new Gee.ArrayList<string> ();
            if (s.ratio.size == 0) sizes.add (pattern.active_size != "" ? pattern.active_size : pattern.table.base_size);
            else foreach (var e in s.ratio.entries) for (int k = 0; k < e.value; k++) sizes.add (e.key);
            foreach (var size in sizes) {
                var res = pattern.evaluate (size);
                foreach (var g in res.pieces) {
                    if (g.cut.length < 3) continue;
                    if (s.material != "" && g.piece.material != s.material) continue;
                    int count = int.max (1, g.piece.quantity) * (g.piece.on_fold ? 1 : 1);
                    for (int q = 0; q < count; q++) {
                        var it = new Item ();
                        it.piece_id = g.piece.id;
                        it.size = size;
                        it.label = "%s %s".printf (g.piece.name, size);
                        Point[] outline = g.cut;
                        if (g.piece.on_fold && g.piece.fold_edge >= 0) outline = unfold (g);
                        if (g.piece.pair && q % 2 == 1) outline = mirror (outline);
                        it.outline = outline;
                        it.area = Polyline.signed_area (outline).abs ();
                        items.add (it);
                    }
                }
            }
            items.sort ((a, b) => a.area > b.area ? -1 : (a.area < b.area ? 1 : 0));
            var result = new MarkerResult ();
            result.width = s.fabric_width;
            double res = double.max (1, s.resolution);
            int rows = (int) Math.floor (s.fabric_width / res);
            double total = 0;
            foreach (var it in items) total += it.area;
            int cols = int.max (64, (int) (total / s.fabric_width / res * 3) + 64);
            var grid = new Grid (cols, rows);
            double[] rots = { 0 };
            if (s.rotations == "180") rots = { 0, 180 };
            else if (s.rotations == "90") rots = { 0, 90, 180, 270 };
            double max_x = 0;
            foreach (var it in items) {
                bool placed = false;
                int best_c = int.MAX, best_r = 0;
                double best_rot = 0;
                Point[] best_pts = {};
                foreach (var rot in rots) {
                    var pts = normalize (rotate (it.outline, rot), s.spacing);
                    var mask = rasterize (pts, res, s.spacing);
                    int mc, mr;
                    if (fit (grid, mask, out mc, out mr)) {
                        if (mc < best_c || (mc == best_c && mr < best_r)) {
                            best_c = mc;
                            best_r = mr;
                            best_rot = rot;
                            best_pts = pts;
                            placed = true;
                        }
                    }
                }
                if (!placed) {
                    result.unplaced++;
                    continue;
                }
                var m = rasterize (best_pts, res, s.spacing);
                stamp (grid, m, best_c, best_r);
                var pl = new MarkerPlacement ();
                pl.piece_id = it.piece_id;
                pl.size = it.size;
                pl.rotation = best_rot;
                pl.label = it.label;
                pl.x = best_c * res;
                pl.y = best_r * res;
                Point[] placed_pts = new Point[best_pts.length];
                for (int i = 0; i < best_pts.length; i++) {
                    placed_pts[i] = Point (best_pts[i].x + pl.x, best_pts[i].y + pl.y);
                    max_x = double.max (max_x, placed_pts[i].x);
                }
                pl.outline = placed_pts;
                result.placements.add (pl);
                result.used_area += it.area;
            }
            result.length = max_x + s.spacing;
            return result;
        }

        private static Point[] unfold (PieceGeometry g) {
            var e = g.edges[g.piece.fold_edge].pts;
            var a = e[0];
            var b = e[e.length - 1];
            double dx = b.x - a.x, dy = b.y - a.y;
            double l2 = dx * dx + dy * dy;
            if (l2 < 1e-9) return g.cut;
            Point[] m = {};
            foreach (var p in g.cut) {
                double t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2;
                var f = Point (a.x + dx * t, a.y + dy * t);
                m += Point (2 * f.x - p.x, 2 * f.y - p.y);
            }
            var poly = new PathData ();
            poly.add_polygon (g.cut, true);
            var other = new PathData ();
            other.add_polygon (Polyline.reversed (m), true);
            var u = PathBoolean.apply (poly, other, BoolOp.UNION);
            var flat = u.flatten (0.5);
            if (flat.size == 0) return g.cut;
            var best = flat[0];
            foreach (var pp in flat) if (pp.area ().abs () > best.area ().abs ()) best = pp;
            return best.pts;
        }

        private static Point[] mirror (Point[] pts) {
            Point[] r = new Point[pts.length];
            for (int i = 0; i < pts.length; i++) r[i] = Point (-pts[i].x, pts[i].y);
            return r;
        }

        private static Point[] rotate (Point[] pts, double deg) {
            double a = deg * Math.PI / 180;
            double c = Math.cos (a), s = Math.sin (a);
            Point[] r = new Point[pts.length];
            for (int i = 0; i < pts.length; i++) r[i] = Point (pts[i].x * c - pts[i].y * s, pts[i].x * s + pts[i].y * c);
            return r;
        }

        private static Point[] normalize (Point[] pts, double pad) {
            var r = Rect.empty ();
            foreach (var p in pts) r = r.include (p.x, p.y);
            Point[] o = new Point[pts.length];
            for (int i = 0; i < pts.length; i++) o[i] = Point (pts[i].x - r.x + pad / 2, pts[i].y - r.y + pad / 2);
            return o;
        }

        private static Grid rasterize (Point[] pts, double res, double pad) {
            var r = Rect.empty ();
            foreach (var p in pts) r = r.include (p.x, p.y);
            int cols = (int) Math.ceil ((r.x2 () + pad / 2) / res) + 1;
            int rows = (int) Math.ceil ((r.y2 () + pad / 2) / res) + 1;
            var surf = new Cairo.ImageSurface (Cairo.Format.A8, cols, rows);
            var cr = new Cairo.Context (surf);
            cr.scale (1 / res, 1 / res);
            cr.move_to (pts[0].x, pts[0].y);
            for (int i = 1; i < pts.length; i++) cr.line_to (pts[i].x, pts[i].y);
            cr.close_path ();
            cr.set_line_width (pad + res);
            cr.set_line_join (Cairo.LineJoin.ROUND);
            cr.fill_preserve ();
            cr.stroke ();
            surf.flush ();
            var g = new Grid (cols, rows);
            unowned uint8[] data = surf.get_data ();
            int stride = surf.get_stride ();
            for (int y = 0; y < rows; y++) for (int x = 0; x < cols; x++) if (data[y * stride + x] > 20) g.set (x, y);
            return g;
        }

        private static bool fit (Grid grid, Grid mask, out int col, out int row) {
            col = 0;
            row = 0;
            if (mask.rows > grid.rows) return false;
            int[] filled = {};
            for (int y = 0; y < mask.rows; y++) for (int x = 0; x < mask.cols; x++) if (mask.cells[y * mask.cols + x] != 0) filled += y * mask.cols + x;
            if (filled.length == 0) return true;
            int last_hit = 0;
            for (int c = 0; c < grid.cols; c++) {
                for (int r = 0; r + mask.rows <= grid.rows; r++) {
                    int k = filled[last_hit];
                    if (grid.get (c + k % mask.cols, r + k / mask.cols)) continue;
                    bool ok = true;
                    for (int i = 0; i < filled.length; i++) {
                        int f = filled[i];
                        if (grid.get (c + f % mask.cols, r + f / mask.cols)) {
                            ok = false;
                            last_hit = i;
                            break;
                        }
                    }
                    if (ok) {
                        col = c;
                        row = r;
                        return true;
                    }
                }
            }
            return false;
        }

        private static void stamp (Grid grid, Grid mask, int col, int row) {
            if (col + mask.cols > grid.cols) {
                var bigger = new uint8[(col + mask.cols + 64) * grid.rows];
                int nc = col + mask.cols + 64;
                for (int r = 0; r < grid.rows; r++) for (int c = 0; c < grid.cols; c++) bigger[r * nc + c] = grid.cells[r * grid.cols + c];
                grid.cells = bigger;
                grid.cols = nc;
            }
            for (int y = 0; y < mask.rows; y++) for (int x = 0; x < mask.cols; x++) if (mask.cells[y * mask.cols + x] != 0) grid.set (col + x, row + y);
        }

        public static double fabric_consumption_m (Pattern pattern, MarkerSettings s, int garments) {
            var r = compute (pattern, s);
            int per = 0;
            foreach (var e in s.ratio.values) per += e;
            if (per == 0) per = 1;
            return r.length_m () / double.max (1, per) * garments;
        }
    }
}
