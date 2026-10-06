using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    namespace Perspective {
        public Point map_rect_to_quad (Rect r, Point[] q, Point p) {
            double u = r.w > 0 ? (p.x - r.x) / r.w : 0;
            double v = r.h > 0 ? (p.y - r.y) / r.h : 0;
            double[] h = homography (q);
            double x = h[0] * u + h[1] * v + h[2];
            double y = h[3] * u + h[4] * v + h[5];
            double w = h[6] * u + h[7] * v + 1;
            if (w.abs () < 1e-12) return p;
            return Point (x / w, y / w);
        }

        public double[] homography (Point[] q) {
            double x0 = q[0].x, y0 = q[0].y, x1 = q[1].x, y1 = q[1].y, x2 = q[2].x, y2 = q[2].y, x3 = q[3].x, y3 = q[3].y;
            double dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
            double sx = x0 - x1 + x2 - x3, sy = y0 - y1 + y2 - y3;
            double g = 0, hh = 0;
            double den = dx1 * dy2 - dx2 * dy1;
            if (den.abs () > 1e-12) {
                g = (sx * dy2 - dx2 * sy) / den;
                hh = (dx1 * sy - sx * dy1) / den;
            }
            double a = x1 - x0 + g * x1, b = x3 - x0 + hh * x3, c = x0;
            double d = y1 - y0 + g * y1, e = y3 - y0 + hh * y3, f = y0;
            return { a, b, c, d, e, f, g, hh };
        }
    }


    public class Digitizer {
        public Cairo.ImageSurface photo;
        public Point[] markers = {};
        public double ref_width = 297;
        public double ref_height = 210;
        public double resolution = 2;
        public int threshold = -1;

        public Digitizer (Cairo.ImageSurface photo) {
            this.photo = photo;
        }

        private static double[] solve8 (double[,] a, double[] b) {
            int n = 8;
            var m = new double[n, n + 1];
            for (int i = 0; i < n; i++) {
                for (int j = 0; j < n; j++) m[i, j] = a[i, j];
                m[i, n] = b[i];
            }
            for (int c = 0; c < n; c++) {
                int piv = c;
                for (int r = c + 1; r < n; r++) if (m[r, c].abs () > m[piv, c].abs ()) piv = r;
                for (int k = 0; k <= n; k++) {
                    double t = m[c, k];
                    m[c, k] = m[piv, k];
                    m[piv, k] = t;
                }
                double d = m[c, c];
                if (d.abs () < 1e-12) continue;
                for (int k = c; k <= n; k++) m[c, k] /= d;
                for (int r = 0; r < n; r++) {
                    if (r == c) continue;
                    double f = m[r, c];
                    for (int k = c; k <= n; k++) m[r, k] -= f * m[c, k];
                }
            }
            var x = new double[n];
            for (int i = 0; i < n; i++) x[i] = m[i, n];
            return x;
        }

        public static double[] homography (Point[] src, Point[] dst) {
            var a = new double[8, 8];
            var b = new double[8];
            for (int i = 0; i < 4; i++) {
                double x = src[i].x, y = src[i].y, u = dst[i].x, v = dst[i].y;
                a[2 * i, 0] = x;
                a[2 * i, 1] = y;
                a[2 * i, 2] = 1;
                a[2 * i, 6] = -x * u;
                a[2 * i, 7] = -y * u;
                b[2 * i] = u;
                a[2 * i + 1, 3] = x;
                a[2 * i + 1, 4] = y;
                a[2 * i + 1, 5] = 1;
                a[2 * i + 1, 6] = -x * v;
                a[2 * i + 1, 7] = -y * v;
                b[2 * i + 1] = v;
            }
            return solve8 (a, b);
        }

        public static Point apply (double[] h, Point p) {
            double w = h[6] * p.x + h[7] * p.y + 1;
            return Point ((h[0] * p.x + h[1] * p.y + h[2]) / w, (h[3] * p.x + h[4] * p.y + h[5]) / w);
        }

        private Point[] ref_rect () {
            return { Point (0, 0), Point (ref_width, 0), Point (ref_width, ref_height), Point (0, ref_height) };
        }

        public Rect plane_area () {
            var h = homography (markers, ref_rect ());
            var r = Rect.empty ();
            foreach (var c in new Point[] { Point (0, 0), Point (photo.get_width (), 0), Point (photo.get_width (), photo.get_height ()), Point (0, photo.get_height ()) }) {
                var q = apply (h, c);
                if (q.x.is_finite () && q.y.is_finite ()) r = r.include (q.x, q.y);
            }
            r = r.union (Rect (0, 0, ref_width, ref_height));
            double cx = ref_width / 2, cy = ref_height / 2;
            double lim = 3000;
            double x0 = double.max (r.x, cx - lim), y0 = double.max (r.y, cy - lim);
            double x1 = double.min (r.x2 (), cx + lim), y1 = double.min (r.y2 (), cy + lim);
            return Rect (x0, y0, x1 - x0, y1 - y0);
        }

        public uint8[] rectified_luma (out int w, out int h, out Rect area) {
            area = plane_area ();
            w = int.max (1, (int) (area.w * resolution));
            h = int.max (1, (int) (area.h * resolution));
            var inv = homography (ref_rect (), markers);
            photo.flush ();
            unowned uint8[] d = photo.get_data ();
            int stride = photo.get_stride (), pw = photo.get_width (), ph = photo.get_height ();
            var out_luma = new uint8[w * h];
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    var src = apply (inv, Point (area.x + (x + 0.5) / resolution, area.y + (y + 0.5) / resolution));
                    int sx = (int) src.x, sy = (int) src.y;
                    uint8 v = 255;
                    if (sx >= 0 && sy >= 0 && sx < pw && sy < ph) {
                        int o = sy * stride + sx * 4;
                        v = (uint8) ((d[o + 2] * 299 + d[o + 1] * 587 + d[o] * 114) / 1000);
                    }
                    out_luma[y * w + x] = v;
                }
            }
            return out_luma;
        }

        public static int otsu (uint8[] luma) {
            var hist = new int[256];
            foreach (var v in luma) hist[v]++;
            int total = luma.length;
            double sum = 0;
            for (int i = 0; i < 256; i++) sum += i * hist[i];
            double sum_b = 0, best = -1;
            int wb = 0, t = 128;
            for (int i = 0; i < 256; i++) {
                wb += hist[i];
                if (wb == 0) continue;
                int wf = total - wb;
                if (wf == 0) break;
                sum_b += i * hist[i];
                double mb = sum_b / wb, mf = (sum - sum_b) / wf;
                double between = (double) wb * wf * (mb - mf) * (mb - mf);
                if (between > best) {
                    best = between;
                    t = i;
                }
            }
            return t;
        }

        public Point[]? outline_at (Point seed_mm, out string error) {
            error = "";
            if (markers.length != 4) {
                error = _("Mark the four corners of the reference first");
                return null;
            }
            int w, h;
            Rect area;
            var luma = rectified_luma (out w, out h, out area);
            int t = threshold >= 0 ? threshold : otsu (luma);
            int sx = (int) ((seed_mm.x - area.x) * resolution), sy = (int) ((seed_mm.y - area.y) * resolution);
            if (sx < 0 || sy < 0 || sx >= w || sy >= h) {
                error = _("The point is outside the photo");
                return null;
            }
            bool seed_light = luma[sy * w + sx] > t;
            var mask = new uint8[w * h];
            var stack = new Gee.ArrayList<int> ();
            stack.add (sy * w + sx);
            int count = 0;
            while (stack.size > 0) {
                int idx = stack.remove_at (stack.size - 1);
                if (mask[idx] != 0) continue;
                if ((luma[idx] > t) != seed_light) continue;
                mask[idx] = 1;
                count++;
                int x = idx % w, y = idx / w;
                if (x == 0 || y == 0 || x == w - 1 || y == h - 1) {
                    error = _("The shape touches the edge of the photo");
                    return null;
                }
                stack.add (idx + 1);
                stack.add (idx - 1);
                stack.add (idx + w);
                stack.add (idx - w);
            }
            if (count < 16) {
                error = _("The shape is too small");
                return null;
            }
            var rings = RegionFill.trace (mask, w, h);
            PointList? best = null;
            foreach (var r in rings) if (best == null || Polyline.signed_area (r.pts).abs () > Polyline.signed_area (best.pts).abs ()) best = r;
            if (best == null) return null;
            Point[] mm = new Point[best.pts.length];
            for (int i = 0; i < best.pts.length; i++) mm[i] = Point (area.x + best.pts[i].x / resolution, area.y + best.pts[i].y / resolution);
            return Polyline.simplify (mm, 0.6);
        }

        public Point photo_to_mm (Point p) {
            return apply (homography (markers, ref_rect ()), p);
        }
    }
}
