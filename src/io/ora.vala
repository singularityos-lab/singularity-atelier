using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class OraFormat {
        public static uint8[] png_bytes (Cairo.ImageSurface surf) {
            var ba = new ByteArray ();
            surf.write_to_png_stream ((data) => {
                ba.append (data);
                return Cairo.Status.SUCCESS;
            });
            return ba.steal ();
        }

        public static uint8[] export (Sketch sk, double scale = 2.0) throws Error {
            Rect area;
            var merged = SketchRenderer.render_image (sk, scale, out area);
            var zip = new ZipWriter ();
            zip.add_text ("mimetype", "image/openraster", false);
            var stack = new StringBuilder ();
            stack.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<image version=\"0.0.5\" w=\"%d\" h=\"%d\" xres=\"%d\" yres=\"%d\">\n<stack>\n".printf (
                merged.get_width (), merged.get_height (), (int) (72 * scale), (int) (72 * scale)));
            int i = 0;
            var layers = new Gee.ArrayList<SketchLayer> ();
            foreach (var l in sk.layers) layers.insert (0, l);
            foreach (var l in layers) {
                var surf = SketchRenderer.render_layer (l, area, scale);
                string name = "data/layer%d.png".printf (i++);
                zip.add (name, png_bytes (surf), false);
                stack.append ("<layer name=\"%s\" src=\"%s\" x=\"0\" y=\"0\" opacity=\"%s\" visibility=\"%s\" composite-op=\"%s\"/>\n".printf (
                    Markup.escape_text (l.name), name, PathData.fmt (l.opacity, 3), l.visible ? "visible" : "hidden", comp_op (l.blend)));
            }
            stack.append ("</stack>\n</image>\n");
            zip.add_text ("stack.xml", stack.str);
            zip.add ("mergedimage.png", png_bytes (merged), false);
            double ts = double.min (256.0 / merged.get_width (), 256.0 / merged.get_height ());
            var thumb = new Cairo.ImageSurface (Cairo.Format.ARGB32, int.max (1, (int) (merged.get_width () * ts)), int.max (1, (int) (merged.get_height () * ts)));
            var tcr = new Cairo.Context (thumb);
            tcr.scale (ts, ts);
            tcr.set_source_surface (merged, 0, 0);
            tcr.paint ();
            zip.add ("Thumbnails/thumbnail.png", png_bytes (thumb), false);
            return zip.finish ();
        }

        private static string comp_op (string blend) {
            switch (blend) {
                case "multiply": return "svg:multiply";
                case "screen": return "svg:screen";
                case "overlay": return "svg:overlay";
                case "darken": return "svg:darken";
                case "lighten": return "svg:lighten";
                default: return "svg:src-over";
            }
        }

        private static string blend_of (string? op) {
            if (op == null) return "normal";
            string o = op.replace ("svg:", "");
            switch (o) {
                case "multiply":
                case "screen":
                case "overlay":
                case "darken":
                case "lighten":
                    return o;
                default:
                    return "normal";
            }
        }

        public static Gee.ArrayList<SketchLayer> import (uint8[] data, Sketch target) throws Error {
            var zip = new ZipReader (data);
            string? xml = zip.read_text ("stack.xml");
            if (xml == null) throw new FormatError.INVALID (_("The OpenRaster file has no layer list"));
            var doc = Xml.Parser.read_memory (xml, xml.length, null, null, Xml.ParserOption.NONET);
            if (doc == null) throw new FormatError.INVALID (_("The OpenRaster layer list is damaged"));
            var result = new Gee.ArrayList<SketchLayer> ();
            collect (doc->get_root_element (), zip, target, result);
            delete doc;
            return result;
        }

        private static void collect (Xml.Node* n, ZipReader zip, Sketch target, Gee.List<SketchLayer> out_list) throws Error {
            for (Xml.Node* c = n->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (c->name == "stack") {
                    collect (c, zip, target, out_list);
                } else if (c->name == "layer") {
                    string? src = c->get_prop ("src");
                    if (src == null || !zip.has (src)) continue;
                    var l = new SketchLayer (target.new_id (), c->get_prop ("name") ?? _("Layer"), LayerKind.IMAGE);
                    l.image_data = new Bytes (zip.read (src));
                    l.image_name = Path.get_basename (src);
                    l.opacity = double.parse (c->get_prop ("opacity") ?? "1");
                    l.visible = (c->get_prop ("visibility") ?? "visible") != "hidden";
                    l.blend = blend_of (c->get_prop ("composite-op"));
                    var m = Cairo.Matrix.identity ();
                    m.translate (double.parse (c->get_prop ("x") ?? "0"), double.parse (c->get_prop ("y") ?? "0"));
                    l.image_matrix = m;
                    out_list.insert (0, l);
                }
            }
        }
    }
}
