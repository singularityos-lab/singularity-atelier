using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class DxfEntity {
        public string type;
        public string layer = "0";
        public Gee.ArrayList<Point?> points = new Gee.ArrayList<Point?> ();
        public bool closed;
        public string text = "";
        public double angle;
        public double radius;
        public double height = 2.5;
        public string block = "";
        public Gee.HashMap<int, string> codes = new Gee.HashMap<int, string> ();

        public DxfEntity (string type) {
            this.type = type;
        }
    }

    public class DxfBlock {
        public string name;
        public Point base_point = Point (0, 0);
        public Gee.ArrayList<DxfEntity> entities = new Gee.ArrayList<DxfEntity> ();

        public DxfBlock (string name) {
            this.name = name;
        }
    }

    public class DxfDocument {
        public Gee.HashMap<string, string> header = new Gee.HashMap<string, string> ();
        public Gee.ArrayList<DxfBlock> blocks = new Gee.ArrayList<DxfBlock> ();
        public Gee.ArrayList<DxfEntity> entities = new Gee.ArrayList<DxfEntity> ();
        public Gee.ArrayList<string> layers = new Gee.ArrayList<string> ();

        public DxfBlock? find_block (string name) {
            foreach (var b in blocks) if (b.name == name) return b;
            return null;
        }

        private class Pair {
            public int code;
            public string value;

            public Pair (int code, string value) {
                this.code = code;
                this.value = value;
            }
        }

        public static DxfDocument parse (string text) throws FormatError {
            var pairs = new Gee.ArrayList<Pair> ();
            var lines = text.replace ("\r\n", "\n").replace ("\r", "\n").split ("\n");
            for (int i = 0; i + 1 < lines.length; i += 2) {
                string c = lines[i].strip ();
                if (c == "") {
                    i--;
                    continue;
                }
                int code;
                if (!int.try_parse (c, out code)) throw new FormatError.INVALID (_("Line %d is not a DXF group code").printf (i + 1));
                pairs.add (new Pair (code, lines[i + 1].strip ()));
            }
            var doc = new DxfDocument ();
            int pos = 0;
            while (pos < pairs.size) {
                var p = pairs[pos];
                if (p.code == 0 && p.value == "SECTION" && pos + 1 < pairs.size) {
                    string name = pairs[pos + 1].value;
                    pos += 2;
                    if (name == "HEADER") {
                        string? var_name = null;
                        while (pos < pairs.size && !(pairs[pos].code == 0 && pairs[pos].value == "ENDSEC")) {
                            if (pairs[pos].code == 9) var_name = pairs[pos].value;
                            else if (var_name != null && !doc.header.has_key (var_name)) doc.header[var_name] = pairs[pos].value;
                            pos++;
                        }
                    } else if (name == "BLOCKS") {
                        while (pos < pairs.size && !(pairs[pos].code == 0 && pairs[pos].value == "ENDSEC")) {
                            if (pairs[pos].code == 0 && pairs[pos].value == "BLOCK") {
                                pos++;
                                var blk = new DxfBlock ("");
                                while (pos < pairs.size && pairs[pos].code != 0) {
                                    if (pairs[pos].code == 2) blk.name = pairs[pos].value;
                                    else if (pairs[pos].code == 10) blk.base_point.x = double.parse (pairs[pos].value);
                                    else if (pairs[pos].code == 20) blk.base_point.y = double.parse (pairs[pos].value);
                                    pos++;
                                }
                                pos = read_entities (pairs, pos, blk.entities, "ENDBLK");
                                while (pos < pairs.size && pairs[pos].code != 0) pos++;
                                doc.blocks.add (blk);
                            } else {
                                pos++;
                            }
                        }
                    } else if (name == "ENTITIES") {
                        pos = read_entities (pairs, pos, doc.entities, "ENDSEC");
                    } else if (name == "TABLES") {
                        while (pos < pairs.size && !(pairs[pos].code == 0 && pairs[pos].value == "ENDSEC")) {
                            if (pairs[pos].code == 0 && pairs[pos].value == "LAYER") {
                                pos++;
                                while (pos < pairs.size && pairs[pos].code != 0) {
                                    if (pairs[pos].code == 2) doc.layers.add (pairs[pos].value);
                                    pos++;
                                }
                            } else {
                                pos++;
                            }
                        }
                    } else {
                        while (pos < pairs.size && !(pairs[pos].code == 0 && pairs[pos].value == "ENDSEC")) pos++;
                    }
                    pos++;
                } else {
                    pos++;
                }
            }
            return doc;
        }

        private static int read_entities (Gee.ArrayList<Pair> pairs, int pos, Gee.List<DxfEntity> into, string end) {
            DxfEntity? poly = null;
            while (pos < pairs.size) {
                var p = pairs[pos];
                if (p.code == 0 && (p.value == end || p.value == "ENDSEC")) break;
                if (p.code != 0) {
                    pos++;
                    continue;
                }
                string type = p.value;
                pos++;
                var e = new DxfEntity (type);
                double x = 0, y = 0;
                bool have_x = false;
                int flags = 0;
                while (pos < pairs.size && pairs[pos].code != 0) {
                    var q = pairs[pos];
                    switch (q.code) {
                        case 8: e.layer = q.value; break;
                        case 1: e.text = e.text == "" ? q.value : e.text + q.value; break;
                        case 3: e.text += q.value; break;
                        case 2: e.block = q.value; break;
                        case 40: e.radius = double.parse (q.value); e.height = e.radius; break;
                        case 50: e.angle = double.parse (q.value); break;
                        case 70: flags = int.parse (q.value); break;
                        case 10:
                            if (have_x) e.points.add (Point (x, y));
                            x = double.parse (q.value);
                            y = 0;
                            have_x = true;
                            break;
                        case 20: y = double.parse (q.value); break;
                        case 11:
                            if (have_x) e.points.add (Point (x, y));
                            x = double.parse (q.value);
                            y = 0;
                            have_x = true;
                            break;
                        case 21: y = double.parse (q.value); break;
                        default:
                            e.codes[q.code] = q.value;
                            break;
                    }
                    pos++;
                }
                if (have_x) e.points.add (Point (x, y));
                e.closed = (flags & 1) != 0;
                if (type == "POLYLINE") {
                    poly = e;
                    poly.points.clear ();
                    into.add (poly);
                } else if (type == "VERTEX") {
                    if (poly != null && e.points.size > 0) poly.points.add (e.points[0]);
                } else if (type == "SEQEND") {
                    poly = null;
                } else {
                    into.add (e);
                }
            }
            return pos;
        }
    }

    public class DxfWriter {
        private StringBuilder sb = new StringBuilder ();

        private string num (double v) {
            return PathData.fmt (v, 4);
        }

        public void pair (int code, string value) {
            sb.append ("%3d\n%s\n".printf (code, value));
        }

        public void header (Gee.Map<string, string> vars) {
            pair (0, "SECTION");
            pair (2, "HEADER");
            pair (9, "$ACADVER");
            pair (1, "AC1009");
            foreach (var e in vars.entries) {
                pair (9, e.key);
                pair (e.key == "$INSUNITS" || e.key == "$MEASUREMENT" ? 70 : 1, e.value);
            }
            pair (0, "ENDSEC");
        }

        public void tables (string[] layers) {
            pair (0, "SECTION");
            pair (2, "TABLES");
            pair (0, "TABLE");
            pair (2, "LAYER");
            pair (70, layers.length.to_string ());
            foreach (var l in layers) {
                pair (0, "LAYER");
                pair (2, l);
                pair (70, "0");
                pair (62, "7");
                pair (6, "CONTINUOUS");
            }
            pair (0, "ENDTAB");
            pair (0, "ENDSEC");
        }

        public void begin_section (string name) {
            pair (0, "SECTION");
            pair (2, name);
        }

        public void end_section () {
            pair (0, "ENDSEC");
        }

        public void begin_block (string name) {
            pair (0, "BLOCK");
            pair (8, "0");
            pair (2, name);
            pair (70, "0");
            pair (10, "0.0");
            pair (20, "0.0");
            pair (30, "0.0");
            pair (3, name);
        }

        public void end_block () {
            pair (0, "ENDBLK");
            pair (8, "0");
        }

        public void polyline (string layer, Point[] pts, bool closed) {
            pair (0, "POLYLINE");
            pair (8, layer);
            pair (66, "1");
            pair (10, "0.0");
            pair (20, "0.0");
            pair (30, "0.0");
            pair (70, closed ? "1" : "0");
            foreach (var p in pts) {
                pair (0, "VERTEX");
                pair (8, layer);
                pair (10, num (p.x));
                pair (20, num (p.y));
                pair (30, "0.0");
            }
            pair (0, "SEQEND");
            pair (8, layer);
        }

        public void line (string layer, Point a, Point b) {
            pair (0, "LINE");
            pair (8, layer);
            pair (10, num (a.x));
            pair (20, num (a.y));
            pair (30, "0.0");
            pair (11, num (b.x));
            pair (21, num (b.y));
            pair (31, "0.0");
        }

        public void point (string layer, Point p, double? angle = null) {
            pair (0, "POINT");
            pair (8, layer);
            pair (10, num (p.x));
            pair (20, num (p.y));
            pair (30, "0.0");
            if (angle != null) pair (50, num (angle));
        }

        public void text (string layer, Point at, string value, double height = 2.5) {
            pair (0, "TEXT");
            pair (8, layer);
            pair (10, num (at.x));
            pair (20, num (at.y));
            pair (30, "0.0");
            pair (40, num (height));
            pair (1, value);
        }

        public void insert (string block) {
            pair (0, "INSERT");
            pair (8, "0");
            pair (2, block);
            pair (10, "0.0");
            pair (20, "0.0");
            pair (30, "0.0");
        }

        public string finish () {
            pair (0, "EOF");
            return sb.str;
        }
    }
}
