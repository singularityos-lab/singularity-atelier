using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class Export {
        public static Gdk.Pixbuf to_pixbuf (Cairo.ImageSurface surf, bool flatten_white) {
            int w = surf.get_width (), h = surf.get_height ();
            var target = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (target);
            if (flatten_white) {
                cr.set_source_rgb (1, 1, 1);
                cr.paint ();
            }
            cr.set_source_surface (surf, 0, 0);
            cr.paint ();
            target.flush ();
            var pb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, true, 8, w, h);
            unowned uint8[] src = target.get_data ();
            unowned uint8[] dst = pb.get_pixels_with_length ();
            int ss = target.get_stride (), ds = pb.rowstride;
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int so = y * ss + x * 4, d = y * ds + x * 4;
                    uint8 a = src[so + 3];
                    uint8 r = src[so + 2], g = src[so + 1], b = src[so];
                    if (a > 0 && a < 255) {
                        r = (uint8) (r * 255 / a);
                        g = (uint8) (g * 255 / a);
                        b = (uint8) (b * 255 / a);
                    }
                    dst[d] = r;
                    dst[d + 1] = g;
                    dst[d + 2] = b;
                    dst[d + 3] = a;
                }
            }
            return pb;
        }

        public static bool format_available (string type) {
            foreach (var f in Gdk.Pixbuf.get_formats ()) if (f.get_name () == type && f.is_writable ()) return true;
            return false;
        }

        public static void save_raster (Cairo.ImageSurface surf, string path) throws Error {
            string lower = path.down ();
            if (lower.has_suffix (".png")) {
                surf.write_to_png (path);
                return;
            }
            string type = lower.has_suffix (".jpg") || lower.has_suffix (".jpeg") ? "jpeg" : (lower.has_suffix (".tif") || lower.has_suffix (".tiff") ? "tiff" : (lower.has_suffix (".webp") ? "webp" : "png"));
            if (!format_available (type)) throw new FormatError.UNSUPPORTED (_("Saving %s images is not available on this system").printf (type.up ()));
            var pb = to_pixbuf (surf, type == "jpeg");
            if (type == "jpeg") {
                var rgb = new Gdk.Pixbuf (Gdk.Colorspace.RGB, false, 8, pb.width, pb.height);
                rgb.fill ((uint32) 0xffffffffU);
                pb.composite (rgb, 0, 0, pb.width, pb.height, 0, 0, 1, 1, Gdk.InterpType.NEAREST, 255);
                rgb.savev (path, "jpeg", { "quality" }, { "92" });
            } else {
                pb.savev (path, type, {}, {});
            }
        }

        public static void sketch_pdf (Sketch sk, string path) {
            var b = sk.bounds ();
            if (b.is_empty ()) b = Rect (0, 0, 800, 600);
            b = b.inflate (20);
            var surf = new Cairo.PdfSurface (path, b.w, b.h);
            var cr = new Cairo.Context (surf);
            cr.translate (-b.x, -b.y);
            SketchRenderer.draw (cr, sk);
            cr.show_page ();
            surf.finish ();
        }

        public static void flats_pdf (Project p, string path) {
            double pw = 841.89, ph = 595.28;
            var surf = new Cairo.PdfSurface (path, pw, ph);
            var cr = new Cairo.Context (surf);
            foreach (var sheet in p.flats) {
                TechPackLayout.draw_sheet_fit (cr, sheet, p.colorway (), 30, 30, pw - 60, ph - 60, true);
                cr.show_page ();
            }
            surf.finish ();
        }

        public static void write_text (string path, string text) throws Error {
            FileUtils.set_contents (path, text);
        }
    }
}
