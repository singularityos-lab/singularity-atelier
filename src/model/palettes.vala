namespace Singularity.Apps.Atelier {

    public class ColorBook {
        public string name;
        public Gee.ArrayList<ColorRef> colors = new Gee.ArrayList<ColorRef> ();

        public ColorBook (string name) {
            this.name = name;
        }

        public ColorRef? find_code (string code) {
            foreach (var c in colors) if (c.code == code) return c;
            return null;
        }

        public string to_gpl () {
            var sb = new StringBuilder ();
            sb.append ("GIMP Palette\nName: %s\nColumns: 8\n#\n".printf (name));
            foreach (var c in colors) {
                sb.append ("%3d %3d %3d\t%s%s\n".printf ((int) Math.round (c.color.r * 255), (int) Math.round (c.color.g * 255), (int) Math.round (c.color.b * 255),
                    c.code != "" ? c.code + " " : "", c.name));
            }
            return sb.str;
        }

        public static ColorBook parse_gpl (string text, string fallback_name) {
            var book = new ColorBook (fallback_name);
            foreach (var raw in text.split ("\n")) {
                string line = raw.strip ();
                if (line == "" || line.has_prefix ("#") || line == "GIMP Palette" || line.has_prefix ("Columns:")) continue;
                if (line.has_prefix ("Name:")) {
                    book.name = line.substring (5).strip ();
                    continue;
                }
                var parts = Regex.split_simple ("\\s+", line);
                if (parts.length < 3) continue;
                int r = int.parse (parts[0]), g = int.parse (parts[1]), b = int.parse (parts[2]);
                string label = parts.length > 3 ? string.joinv (" ", parts[3:parts.length]) : "";
                var c = new ColorRef (Rgba (r / 255.0, g / 255.0, b / 255.0), label);
                c.book = book.name;
                book.colors.add (c);
            }
            return book;
        }

        public static ColorBook parse_ase (uint8[] data, string fallback_name) throws Error {
            var book = new ColorBook (fallback_name);
            if (data.length < 12 || data[0] != 'A' || data[1] != 'S' || data[2] != 'E' || data[3] != 'F') throw new IOError.INVALID_DATA (_("Not an Adobe swatch exchange file"));
            int pos = 8;
            uint32 blocks = be32 (data, pos);
            pos += 4;
            for (uint32 i = 0; i < blocks && pos + 6 <= data.length; i++) {
                uint16 type = be16 (data, pos);
                uint32 len = be32 (data, pos + 2);
                int start = pos + 6;
                int next = start + (int) len;
                if (next > data.length) break;
                if (type == 0x0001) {
                    int p = start;
                    uint16 name_len = be16 (data, p);
                    p += 2;
                    var name = new StringBuilder ();
                    for (int k = 0; k < name_len; k++) {
                        uint16 ch = be16 (data, p + k * 2);
                        if (ch != 0) name.append_unichar ((unichar) ch);
                    }
                    p += name_len * 2;
                    string model = ((string) data[p:p + 4]).substring (0, 4);
                    p += 4;
                    Rgba col = Rgba (0, 0, 0, 1);
                    if (model.has_prefix ("RGB")) {
                        col = Rgba (bef (data, p), bef (data, p + 4), bef (data, p + 8), 1);
                    } else if (model.has_prefix ("CMYK")) {
                        col = ColorManager.cmyk_to_rgb (bef (data, p), bef (data, p + 4), bef (data, p + 8), bef (data, p + 12));
                    } else if (model.has_prefix ("LAB")) {
                        col = ColorManager.lab_to_rgb (bef (data, p) * 100, bef (data, p + 4), bef (data, p + 8));
                    } else if (model.has_prefix ("Gray")) {
                        double g = bef (data, p);
                        col = Rgba (g, g, g, 1);
                    }
                    var c = new ColorRef (col, name.str);
                    c.book = book.name;
                    c.code = name.str;
                    book.colors.add (c);
                }
                pos = next;
            }
            return book;
        }

        private static uint16 be16 (uint8[] d, int p) {
            return (uint16) ((d[p] << 8) | d[p + 1]);
        }

        private static uint32 be32 (uint8[] d, int p) {
            return ((uint32) d[p] << 24) | ((uint32) d[p + 1] << 16) | ((uint32) d[p + 2] << 8) | d[p + 3];
        }

        private static double bef (uint8[] d, int p) {
            uint32 bits = be32 (d, p);
            float f = 0;
            Memory.copy (&f, &bits, 4);
            return f;
        }

        public static uint8[] write_ase (ColorBook book) {
            var out_bytes = new ByteArray ();
            out_bytes.append ("ASEF".data);
            put16 (out_bytes, 1);
            put16 (out_bytes, 0);
            put32 (out_bytes, book.colors.size);
            foreach (var c in book.colors) {
                var block = new ByteArray ();
                string nm = c.code != "" ? c.code : c.name;
                long n = nm.char_count () + 1;
                put16 (block, (uint16) n);
                unichar ch;
                int idx = 0;
                while (nm.get_next_char (ref idx, out ch)) put16 (block, (uint16) ch);
                put16 (block, 0);
                block.append ("RGB ".data);
                putf (block, (float) c.color.r);
                putf (block, (float) c.color.g);
                putf (block, (float) c.color.b);
                put16 (block, 2);
                put16 (out_bytes, 0x0001);
                put32 (out_bytes, block.len);
                out_bytes.append (block.data);
            }
            return out_bytes.data;
        }

        private static void put16 (ByteArray b, uint16 v) {
            uint8[] d = { (uint8) (v >> 8), (uint8) v };
            b.append (d);
        }

        private static void put32 (ByteArray b, uint32 v) {
            uint8[] d = { (uint8) (v >> 24), (uint8) (v >> 16), (uint8) (v >> 8), (uint8) v };
            b.append (d);
        }

        private static void putf (ByteArray b, float f) {
            uint32 bits = 0;
            Memory.copy (&bits, &f, 4);
            put32 (b, bits);
        }

        public static ColorBook textile () {
            var book = new ColorBook ("Singularity Textile");
            string[,] entries = {
                { "ST-0101", "Optic White", "#f7f7f2" }, { "ST-0102", "Ecru", "#efe6d2" }, { "ST-0103", "Sand", "#d8c3a0" },
                { "ST-0104", "Camel", "#b98a57" }, { "ST-0105", "Tobacco", "#8a5a2b" }, { "ST-0106", "Chocolate", "#4a2e1f" },
                { "ST-0201", "Ash Grey", "#c7c7c2" }, { "ST-0202", "Stone", "#9d9a92" }, { "ST-0203", "Charcoal", "#44464a" },
                { "ST-0204", "Jet Black", "#16171a" }, { "ST-0301", "Navy", "#1f2b4a" }, { "ST-0302", "Indigo", "#2c3e75" },
                { "ST-0303", "Denim Blue", "#4f6d9a" }, { "ST-0304", "Sky", "#9cc3e6" }, { "ST-0305", "Teal", "#1d7a7a" },
                { "ST-0401", "Forest", "#2f4f36" }, { "ST-0402", "Olive", "#6b6b3a" }, { "ST-0403", "Sage", "#a5b39a" },
                { "ST-0404", "Mint", "#bfe3cf" }, { "ST-0501", "Burgundy", "#6d1f2c" }, { "ST-0502", "Brick", "#a3432f" },
                { "ST-0503", "Scarlet", "#c8202f" }, { "ST-0504", "Coral", "#ef7a64" }, { "ST-0505", "Blush", "#efc3c0" },
                { "ST-0601", "Mustard", "#d4a02a" }, { "ST-0602", "Saffron", "#f0b33b" }, { "ST-0603", "Lemon", "#f4e27a" },
                { "ST-0701", "Plum", "#5b2c55" }, { "ST-0702", "Lavender", "#b8a8d6" }, { "ST-0703", "Fuchsia", "#c42d7d" }
            };
            for (int i = 0; i < entries.length[0]; i++) {
                var c = new ColorRef (Rgba.parse (entries[i, 2]), entries[i, 1]);
                c.code = entries[i, 0];
                c.book = book.name;
                book.colors.add (c);
            }
            return book;
        }
    }

    public class ColorManager {
        public static Rgba lab_to_rgb (double l, double a, double b) {
#if HAVE_LCMS
            var lab = new Lcms.Profile.lab4 ();
            var srgb = new Lcms.Profile.srgb ();
            var xf = new Lcms.Transform (lab, Lcms.TYPE_LAB_DBL, srgb, Lcms.TYPE_RGB_DBL, Lcms.INTENT_RELATIVE_COLORIMETRIC, 0);
            double[] input = { l, a, b };
            double[] output = { 0, 0, 0 };
            xf.apply (input, output, 1);
            return Rgba (output[0].clamp (0, 1), output[1].clamp (0, 1), output[2].clamp (0, 1), 1);
#else
            double fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200;
            double x = 0.9642 * finv (fx), y = finv (fy), z = 0.8249 * finv (fz);
            double r = 3.1339 * x - 1.6169 * y - 0.4906 * z;
            double g = -0.9785 * x + 1.9160 * y + 0.0334 * z;
            double bl = 0.0720 * x - 0.2290 * y + 1.4057 * z;
            return Rgba (gamma (r), gamma (g), gamma (bl), 1);
#endif
        }

        private static double finv (double t) {
            return t > 6.0 / 29 ? t * t * t : 3 * (6.0 / 29) * (6.0 / 29) * (t - 4.0 / 29);
        }

        private static double gamma (double v) {
            v = v.clamp (0, 1);
            return v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow (v, 1 / 2.4) - 0.055;
        }

        public static Rgba cmyk_to_rgb (double c, double m, double y, double k) {
            return Rgba ((1 - c) * (1 - k), (1 - m) * (1 - k), (1 - y) * (1 - k), 1);
        }

        public static bool available () {
#if HAVE_LCMS
            return true;
#else
            return false;
#endif
        }

        public static Rgba soft_proof (Rgba c, string? profile_path, out bool out_of_gamut) {
            out_of_gamut = false;
#if HAVE_LCMS
            if (profile_path == null || !FileUtils.test (profile_path, FileTest.EXISTS)) return c;
            var srgb = new Lcms.Profile.srgb ();
            var target = new Lcms.Profile.from_file (profile_path);
            if (target == null) return c;
            var xf = new Lcms.Transform.proofing (srgb, Lcms.TYPE_RGB_DBL, srgb, Lcms.TYPE_RGB_DBL, target, Lcms.INTENT_PERCEPTUAL, Lcms.INTENT_RELATIVE_COLORIMETRIC, Lcms.FLAGS_SOFTPROOFING);
            double[] input = { c.r, c.g, c.b };
            double[] output = { 0, 0, 0 };
            xf.apply (input, output, 1);
            var r = Rgba (output[0].clamp (0, 1), output[1].clamp (0, 1), output[2].clamp (0, 1), c.a);
            out_of_gamut = (r.r - c.r).abs () + (r.g - c.g).abs () + (r.b - c.b).abs () > 0.08;
            return r;
#else
            return c;
#endif
        }

        public static Gee.List<string> system_profiles () {
            var list = new Gee.ArrayList<string> ();
            string[] dirs = { "/usr/share/color/icc", "/usr/local/share/color/icc", Path.build_filename (Environment.get_user_data_dir (), "color", "icc"), Path.build_filename (Environment.get_home_dir (), ".color", "icc") };
            foreach (var d in dirs) scan (d, list, 0);
            return list;
        }

        private static void scan (string dir, Gee.List<string> list, int depth) {
            if (depth > 3) return;
            try {
                var dh = Dir.open (dir);
                string? name;
                while ((name = dh.read_name ()) != null) {
                    string p = Path.build_filename (dir, name);
                    if (FileUtils.test (p, FileTest.IS_DIR)) scan (p, list, depth + 1);
                    else if (name.down ().has_suffix (".icc") || name.down ().has_suffix (".icm")) list.add (p);
                }
            } catch (Error e) {
            }
        }
    }
}
