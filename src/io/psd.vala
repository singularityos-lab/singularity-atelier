namespace Singularity.Apps.Atelier {

    public class Psd {
        private uint8[] d;
        private int pos;

        private Psd (uint8[] data) {
            d = data;
            pos = 0;
        }

        private void need (int n) throws FormatError {
            if (pos + n > d.length) throw new FormatError.INVALID (_("The Photoshop file is truncated"));
        }

        private uint32 u32 () throws FormatError {
            need (4);
            uint32 v = ((uint32) d[pos] << 24) | ((uint32) d[pos + 1] << 16) | ((uint32) d[pos + 2] << 8) | d[pos + 3];
            pos += 4;
            return v;
        }

        private int32 i32 () throws FormatError {
            return (int32) u32 ();
        }

        private uint16 u16 () throws FormatError {
            need (2);
            uint16 v = (uint16) ((d[pos] << 8) | d[pos + 1]);
            pos += 2;
            return v;
        }

        private uint8 u8 () throws FormatError {
            need (1);
            return d[pos++];
        }

        private class Channel {
            public int16 id;
            public uint32 length;
        }

        private class Layer {
            public int top;
            public int left;
            public int bottom;
            public int right;
            public Gee.ArrayList<Channel> channels = new Gee.ArrayList<Channel> ();
            public uint8 opacity;
            public bool hidden;
            public string name = "";
            public string blend = "norm";
        }

        private uint8[] read_channel (int w, int h) throws FormatError {
            var out_data = new uint8[w * h];
            uint16 comp = u16 ();
            if (comp == 0) {
                need (w * h);
                for (int i = 0; i < w * h; i++) out_data[i] = d[pos + i];
                pos += w * h;
            } else if (comp == 1) {
                var counts = new int[h];
                for (int r = 0; r < h; r++) counts[r] = u16 ();
                for (int r = 0; r < h; r++) {
                    int end = pos + counts[r];
                    int x = 0;
                    while (pos < end && x < w) {
                        int8 n = (int8) u8 ();
                        if (n >= 0) {
                            for (int k = 0; k <= n && x < w; k++) out_data[r * w + x++] = u8 ();
                        } else if (n != -128) {
                            uint8 v = u8 ();
                            for (int k = 0; k < 1 - n && x < w; k++) out_data[r * w + x++] = v;
                        }
                    }
                    pos = end;
                }
            } else {
                throw new FormatError.UNSUPPORTED (_("This Photoshop compression is not supported"));
            }
            return out_data;
        }

        public static Gee.ArrayList<SketchLayer> read (uint8[] data, Sketch target) throws FormatError {
            var p = new Psd (data);
            var result = new Gee.ArrayList<SketchLayer> ();
            if (data.length < 26 || data[0] != '8' || data[1] != 'B' || data[2] != 'P' || data[3] != 'S') throw new FormatError.INVALID (_("Not a Photoshop document"));
            p.pos = 4;
            uint16 version = p.u16 ();
            if (version != 1) throw new FormatError.UNSUPPORTED (_("Large Photoshop documents are not supported"));
            p.pos += 6;
            p.u16 ();
            p.u32 ();
            p.u32 ();
            uint16 depth = p.u16 ();
            uint16 mode = p.u16 ();
            if (depth != 8 || (mode != 3 && mode != 1)) throw new FormatError.UNSUPPORTED (_("Only 8 bit RGB and greyscale Photoshop documents are supported"));
            p.pos += (int) p.u32 ();
            p.pos += (int) p.u32 ();
            uint32 lm_len = p.u32 ();
            int lm_end = p.pos + (int) lm_len;
            if (lm_len == 0) return result;
            uint32 li_len = p.u32 ();
            if (li_len == 0) return result;
            int16 count = (int16) p.u16 ();
            if (count < 0) count = -count;
            var layers = new Gee.ArrayList<Layer> ();
            for (int i = 0; i < count; i++) {
                var l = new Layer ();
                l.top = p.i32 ();
                l.left = p.i32 ();
                l.bottom = p.i32 ();
                l.right = p.i32 ();
                int nch = p.u16 ();
                for (int c = 0; c < nch; c++) {
                    var ch = new Channel ();
                    ch.id = (int16) p.u16 ();
                    ch.length = p.u32 ();
                    l.channels.add (ch);
                }
                p.pos += 4;
                p.need (4);
                l.blend = ((string) data[p.pos:p.pos + 4]).substring (0, 4);
                p.pos += 4;
                l.opacity = p.u8 ();
                p.u8 ();
                uint8 flags = p.u8 ();
                l.hidden = (flags & 2) != 0;
                p.u8 ();
                uint32 extra = p.u32 ();
                int extra_end = p.pos + (int) extra;
                p.pos += (int) p.u32 ();
                p.pos += (int) p.u32 ();
                int nlen = p.u8 ();
                p.need (nlen);
                var sb = new StringBuilder ();
                for (int k = 0; k < nlen; k++) sb.append_c ((char) data[p.pos + k]);
                l.name = sb.str.validate () ? sb.str : _("Layer %d").printf (i + 1);
                p.pos = extra_end;
                layers.add (l);
            }
            foreach (var l in layers) {
                int w = l.right - l.left, h = l.bottom - l.top;
                var planes = new Gee.HashMap<int, Bytes> ();
                foreach (var ch in l.channels) {
                    int start = p.pos;
                    if (w > 0 && h > 0 && (ch.id >= -1 && ch.id <= 2)) {
                        try {
                            planes[ch.id] = new Bytes (p.read_channel (w, h));
                        } catch (FormatError e) {
                        }
                    }
                    p.pos = start + (int) ch.length;
                }
                if (w <= 0 || h <= 0) continue;
                var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
                surf.flush ();
                unowned uint8[] px = surf.get_data ();
                int stride = surf.get_stride ();
                unowned uint8[]? r = planes.has_key (0) ? planes[0].get_data () : null;
                unowned uint8[]? g = planes.has_key (1) ? planes[1].get_data () : r;
                unowned uint8[]? b = planes.has_key (2) ? planes[2].get_data () : r;
                unowned uint8[]? a = planes.has_key (-1) ? planes[-1].get_data () : null;
                for (int y = 0; y < h; y++) {
                    for (int x = 0; x < w; x++) {
                        int i = y * w + x;
                        uint alpha = a != null ? a[i] : 255;
                        uint rr = r != null ? r[i] : 0, gg = g != null ? g[i] : 0, bb = b != null ? b[i] : 0;
                        int o = y * stride + x * 4;
                        px[o] = (uint8) (bb * alpha / 255);
                        px[o + 1] = (uint8) (gg * alpha / 255);
                        px[o + 2] = (uint8) (rr * alpha / 255);
                        px[o + 3] = (uint8) alpha;
                    }
                }
                surf.mark_dirty ();
                var sl = new SketchLayer (target.new_id (), l.name, LayerKind.IMAGE);
                sl.image_data = new Bytes (OraFormat.png_bytes (surf));
                sl.image_name = l.name;
                sl.opacity = l.opacity / 255.0;
                sl.visible = !l.hidden;
                sl.locked = true;
                sl.blend = l.blend == "mul " ? "multiply" : (l.blend == "scrn" ? "screen" : (l.blend == "over" ? "overlay" : "normal"));
                var m = Cairo.Matrix.identity ();
                m.translate (l.left, l.top);
                sl.image_matrix = m;
                result.insert (0, sl);
            }
            if (lm_end > p.pos) p.pos = lm_end;
            return result;
        }
    }
}
