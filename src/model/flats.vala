using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public enum StitchKind {
        NONE,
        SINGLE,
        DOUBLE,
        TRIPLE,
        ZIGZAG,
        COVERSTITCH,
        CHAIN,
        ZIPPER,
        BLIND,
        OVERLOCK;

        public string to_id () {
            switch (this) {
                case SINGLE: return "single";
                case DOUBLE: return "double";
                case TRIPLE: return "triple";
                case ZIGZAG: return "zigzag";
                case COVERSTITCH: return "coverstitch";
                case CHAIN: return "chain";
                case ZIPPER: return "zipper";
                case BLIND: return "blind";
                case OVERLOCK: return "overlock";
                default: return "none";
            }
        }

        public static StitchKind from_id (string? id) {
            switch (id) {
                case "single": return SINGLE;
                case "double": return DOUBLE;
                case "triple": return TRIPLE;
                case "zigzag": return ZIGZAG;
                case "coverstitch": return COVERSTITCH;
                case "chain": return CHAIN;
                case "zipper": return ZIPPER;
                case "blind": return BLIND;
                case "overlock": return OVERLOCK;
                default: return NONE;
            }
        }

        public string label () {
            switch (this) {
                case SINGLE: return _("Single Needle Topstitch");
                case DOUBLE: return _("Double Needle Topstitch");
                case TRIPLE: return _("Triple Needle Topstitch");
                case ZIGZAG: return _("Zigzag");
                case COVERSTITCH: return _("Coverstitch");
                case CHAIN: return _("Chain Stitch");
                case ZIPPER: return _("Zipper");
                case BLIND: return _("Blind Hem");
                case OVERLOCK: return _("Overlock");
                default: return _("Plain Line");
            }
        }

        public static StitchKind[] all () {
            return { NONE, SINGLE, DOUBLE, TRIPLE, ZIGZAG, COVERSTITCH, CHAIN, ZIPPER, BLIND, OVERLOCK };
        }
    }

    public class StitchStyle {
        public StitchKind kind = StitchKind.NONE;
        public double pitch = 3;
        public double gap = 6;
        public double offset;
        public double width = 3;
        public string color_slot = "Stitching";

        public StitchStyle copy () {
            var s = new StitchStyle ();
            s.kind = kind;
            s.pitch = pitch;
            s.gap = gap;
            s.offset = offset;
            s.width = width;
            s.color_slot = color_slot;
            return s;
        }
    }

    public enum FlatItemKind {
        SHAPE,
        TRIM,
        DIMENSION,
        CALLOUT,
        TEXT
    }

    public class FlatItem {
        public string id;
        public FlatItemKind kind = FlatItemKind.SHAPE;
        public string name = "";
        public PathData path = new PathData ();
        public bool mirror;
        public string fill_slot = "";
        public string line_slot = "Outline";
        public double line_width = 0.8;
        public bool dashed;
        public StitchStyle stitch = new StitchStyle ();
        public string trim = "button";
        public string asset_id = "";
        public Point at = Point (0, 0);
        public Point at2 = Point (0, 0);
        public double size = 12;
        public double rotation;
        public double offset = 12;
        public string text = "";
        public int number;
        public string link = "";
        public string fabric_id = "";
        public double pattern_scale = 1;
        public double pattern_angle;

        public FlatItem (string id, FlatItemKind kind) {
            this.id = id;
            this.kind = kind;
        }

        public FlatItem copy () {
            var f = new FlatItem (id, kind);
            f.name = name;
            f.path = path.copy ();
            f.mirror = mirror;
            f.fill_slot = fill_slot;
            f.line_slot = line_slot;
            f.line_width = line_width;
            f.dashed = dashed;
            f.stitch = stitch.copy ();
            f.trim = trim;
            f.asset_id = asset_id;
            f.at = at;
            f.at2 = at2;
            f.size = size;
            f.rotation = rotation;
            f.offset = offset;
            f.text = text;
            f.number = number;
            f.link = link;
            f.fabric_id = fabric_id;
            f.pattern_scale = pattern_scale;
            f.pattern_angle = pattern_angle;
            return f;
        }

        public double measured_length (double axis) {
            if (kind == FlatItemKind.DIMENSION) {
                if (!path.is_empty ()) {
                    double l = 0;
                    foreach (var poly in path.flatten (0.2)) l += poly.length ();
                    return l;
                }
                return at.distance (at2);
            }
            return 0;
        }
    }

    public class FlatSheet {
        public string id;
        public string name;
        public double axis_x = 400;
        public Gee.ArrayList<FlatItem> items = new Gee.ArrayList<FlatItem> ();
        public double scale_mm = 1;
        private int next_id = 1;

        public FlatSheet (string id, string name) {
            this.id = id;
            this.name = name;
        }

        public string new_id () {
            while (true) {
                string id = "f%d".printf (next_id++);
                bool used = false;
                foreach (var it in items) if (it.id == id) used = true;
                if (!used) return id;
            }
        }

        public FlatItem? find (string id) {
            foreach (var it in items) if (it.id == id) return it;
            return null;
        }

        public int next_callout () {
            int n = 1;
            foreach (var it in items) if (it.kind == FlatItemKind.CALLOUT) n = int.max (n, it.number + 1);
            return n;
        }

        public Rect bounds () {
            var r = Rect.empty ();
            foreach (var it in items) {
                if (!it.path.is_empty ()) {
                    var b = it.path.bounds ();
                    r = r.union (b);
                    if (it.mirror) r = r.include (2 * axis_x - b.x, b.y).include (2 * axis_x - b.x2 (), b.y2 ());
                }
                if (it.kind != FlatItemKind.SHAPE) r = r.include (it.at.x, it.at.y).include (it.at2.x, it.at2.y);
            }
            return r;
        }

        public PathData full_path (FlatItem it) {
            if (!it.mirror) return it.path;
            return Flats.mirror_close (it.path, axis_x);
        }
    }

    namespace Flats {
        public PathData mirror_close (PathData half, double axis) {
            var m = Cairo.Matrix (-1, 0, 0, 1, 2 * axis, 0);
            bool closed = half.has_closed_subpath ();
            if (closed) {
                var r = half.copy ();
                r.append (half.transformed (m));
                return r;
            }
            var other = half.transformed (m);
            other.reverse ();
            var r = half.copy ();
            bool first = true;
            foreach (var s in other.segs) {
                if (first && s.kind == SegKind.MOVE) {
                    r.line_to (s.x, s.y);
                    first = false;
                    continue;
                }
                first = false;
                r.segs.add (s.copy ());
            }
            r.close ();
            return r;
        }

        public const string[] TEMPLATES = { "tshirt", "shirt", "trousers", "skirt", "jacket", "dress", "hoodie", "tote", "backpack", "sneaker" };

        public string template_label (string id) {
            switch (id) {
                case "tshirt": return _("T-Shirt");
                case "shirt": return _("Shirt");
                case "trousers": return _("Trousers");
                case "skirt": return _("Skirt");
                case "jacket": return _("Jacket");
                case "dress": return _("Dress");
                case "hoodie": return _("Hoodie");
                case "tote": return _("Tote Bag");
                case "backpack": return _("Backpack");
                case "sneaker": return _("Sneaker");
            }
            return id;
        }

        private FlatItem shape (FlatSheet s, string name, string d, bool mirror, string fill, StitchKind stitch = StitchKind.NONE, double stitch_offset = 0) {
            var it = new FlatItem (s.new_id (), FlatItemKind.SHAPE);
            it.name = name;
            it.path = PathData.parse_svg (d);
            it.mirror = mirror;
            it.fill_slot = fill;
            it.stitch.kind = stitch;
            it.stitch.offset = stitch_offset;
            s.items.add (it);
            return it;
        }

        private FlatItem line (FlatSheet s, string name, string d, bool mirror, StitchKind stitch, double offset = 0) {
            var it = shape (s, name, d, mirror, "", stitch, offset);
            it.line_slot = stitch == StitchKind.NONE ? "Outline" : "Stitching";
            if (stitch != StitchKind.NONE) it.line_width = 0;
            return it;
        }

        private FlatItem trim (FlatSheet s, string kind, double x, double y, double size) {
            var it = new FlatItem (s.new_id (), FlatItemKind.TRIM);
            it.trim = kind;
            it.name = Trims.label (kind);
            it.at = Point (x, y);
            it.size = size;
            it.fill_slot = "Trim";
            s.items.add (it);
            return it;
        }

        public Gee.ArrayList<FlatSheet> build (string id) {
            var sheets = new Gee.ArrayList<FlatSheet> ();
            var front = new FlatSheet ("front", _("Front"));
            var back = new FlatSheet ("back", _("Back"));
            front.axis_x = 400;
            back.axis_x = 400;
            sheets.add (front);
            sheets.add (back);
            switch (id) {
                case "shirt":
                    shape (front, _("Body"), "M400 110 L360 118 L300 140 L230 170 L180 330 L225 342 L262 250 L262 640 L400 650", true, "Body");
                    shape (front, _("Collar"), "M400 110 L372 96 L352 104 L360 130 L400 158", true, "Trim");
                    line (front, _("Placket"), "M388 150 L388 650", false, StitchKind.SINGLE);
                    line (front, _("Placket Edge"), "M412 150 L412 650", false, StitchKind.NONE);
                    line (front, _("Yoke"), "M300 140 L262 250", true, StitchKind.SINGLE, 2);
                    for (int i = 0; i < 6; i++) trim (front, "button", 400, 190 + i * 80, 9);
                    shape (front, _("Pocket"), "M300 260 L360 260 L360 330 L330 342 L300 330 Z", false, "Body", StitchKind.SINGLE, 2);
                    shape (back, _("Body"), "M400 108 L360 116 L300 140 L230 170 L180 330 L225 342 L262 250 L262 640 L400 650", true, "Body");
                    line (back, _("Yoke Seam"), "M262 200 L400 210", true, StitchKind.DOUBLE, 2);
                    break;
                case "trousers":
                    shape (front, _("Leg"), "M400 120 L270 120 L240 420 L250 900 L360 900 L395 360 L400 360", true, "Body");
                    shape (front, _("Waistband"), "M400 120 L270 120 L270 90 L400 90 Z", true, "Body", StitchKind.SINGLE, 2);
                    line (front, _("Fly"), "M400 120 L400 330 C400 345 390 355 375 355 L375 150", false, StitchKind.SINGLE);
                    line (front, _("Pocket"), "M280 125 C300 190 330 205 350 205", true, StitchKind.DOUBLE, 2);
                    line (front, _("Crease"), "M305 360 L305 900", true, StitchKind.NONE);
                    trim (front, "button", 400, 105, 8);
                    trim (front, "zipper", 390, 240, 70);
                    for (int i = 0; i < 3; i++) trim (front, "rivet", 290 + i * 25, 140, 4);
                    shape (back, _("Leg"), "M400 120 L270 120 L240 420 L250 900 L360 900 L395 360 L400 360", true, "Body");
                    shape (back, _("Waistband"), "M400 120 L270 120 L270 90 L400 90 Z", true, "Body", StitchKind.SINGLE, 2);
                    shape (back, _("Back Pocket"), "M290 190 L360 185 L362 260 L327 280 L292 262 Z", true, "Body", StitchKind.DOUBLE, 2);
                    line (back, _("Yoke"), "M270 150 L400 175", true, StitchKind.DOUBLE, 2);
                    break;
                case "skirt":
                    shape (front, _("Skirt"), "M400 120 L300 120 L250 520 L400 530", true, "Body");
                    shape (front, _("Waistband"), "M400 120 L300 120 L300 90 L400 90 Z", true, "Body", StitchKind.SINGLE, 2);
                    line (front, _("Dart"), "M340 120 L345 200 L352 120", true, StitchKind.NONE);
                    line (front, _("Hem"), "M252 505 L400 515", true, StitchKind.BLIND);
                    shape (back, _("Skirt"), "M400 120 L300 120 L250 520 L400 530", true, "Body");
                    shape (back, _("Waistband"), "M400 120 L300 120 L300 90 L400 90 Z", true, "Body");
                    trim (back, "zipper", 400, 200, 140);
                    break;
                case "jacket":
                    shape (front, _("Body"), "M400 110 L355 118 L285 140 L215 175 L165 470 L215 480 L250 270 L255 640 L400 655", true, "Body");
                    shape (front, _("Lapel"), "M400 330 L360 125 L330 150 L352 210 L335 225 L400 360", true, "Trim");
                    line (front, _("Front Edge"), "M400 330 L400 655", false, StitchKind.SINGLE, -4);
                    shape (front, _("Welt Pocket"), "M280 470 L355 460 L356 474 L281 484 Z", true, "Trim");
                    for (int i = 0; i < 2; i++) trim (front, "button", 412, 410 + i * 70, 11);
                    shape (back, _("Body"), "M400 108 L355 116 L285 140 L215 175 L165 470 L215 480 L250 270 L255 640 L400 655", true, "Body");
                    line (back, _("Center Back Seam"), "M400 110 L400 655", false, StitchKind.NONE);
                    line (back, _("Vent"), "M400 560 L400 655", false, StitchKind.SINGLE, 5);
                    break;
                case "dress":
                    shape (front, _("Bodice"), "M400 140 L360 130 L330 140 L320 260 L335 330 L400 335", true, "Body");
                    shape (front, _("Skirt"), "M400 335 L335 330 L240 780 L400 800", true, "Body");
                    line (front, _("Waist Seam"), "M335 330 L400 335", true, StitchKind.NONE);
                    line (front, _("Neckline"), "M360 130 C370 190 390 205 400 205", true, StitchKind.SINGLE, 3);
                    shape (back, _("Bodice"), "M400 125 L360 130 L330 140 L320 260 L335 330 L400 335", true, "Body");
                    shape (back, _("Skirt"), "M400 335 L335 330 L240 780 L400 800", true, "Body");
                    trim (back, "zipper", 400, 250, 220);
                    break;
                case "hoodie":
                    shape (front, _("Body"), "M400 140 L350 128 L290 150 L220 185 L170 520 L220 530 L255 300 L255 600 L400 610", true, "Body");
                    shape (front, _("Hood"), "M400 140 L350 128 C330 60 360 20 400 15", true, "Body");
                    shape (front, _("Kangaroo Pocket"), "M300 430 L400 430 L400 540 L285 540 L318 470 Z", true, "Body", StitchKind.COVERSTITCH, 3);
                    shape (front, _("Rib Hem"), "M255 580 L400 585 L400 610 L255 600 Z", true, "Trim");
                    trim (front, "eyelet", 380, 150, 6);
                    trim (front, "cord", 380, 200, 60);
                    shape (back, _("Body"), "M400 140 L350 128 L290 150 L220 185 L170 520 L220 530 L255 300 L255 600 L400 610", true, "Body");
                    shape (back, _("Hood"), "M400 140 L350 128 C330 60 360 20 400 15", true, "Body");
                    break;
                case "tote":
                    shape (front, _("Bag Body"), "M400 250 L240 250 L250 620 L400 620", true, "Body", StitchKind.SINGLE, 5);
                    shape (front, _("Handle"), "M300 250 C300 110 400 100 400 100", true, "Trim");
                    shape (front, _("Top Band"), "M400 250 L240 250 L241 290 L400 290 Z", true, "Trim", StitchKind.DOUBLE, 3);
                    for (int i = 0; i < 2; i++) trim (front, "rivet", 290 + i * 220, 270, 5);
                    shape (back, _("Bag Body"), "M400 250 L240 250 L250 620 L400 620", true, "Body", StitchKind.SINGLE, 5);
                    shape (back, _("Slip Pocket"), "M300 330 L400 330 L400 470 L300 470 Z", true, "Body", StitchKind.SINGLE, 3);
                    break;
                case "backpack":
                    shape (front, _("Body"), "M400 140 C320 140 280 170 275 240 L270 620 L400 630", true, "Body", StitchKind.SINGLE, 4);
                    shape (front, _("Front Pocket"), "M400 400 L310 400 C300 480 305 560 320 580 L400 585", true, "Trim", StitchKind.SINGLE, 3);
                    trim (front, "zipper", 400, 400, 180);
                    trim (front, "buckle", 400, 330, 22);
                    shape (back, _("Back Panel"), "M400 140 C320 140 280 170 275 240 L270 620 L400 630", true, "Body");
                    shape (back, _("Strap"), "M330 170 C300 300 300 450 320 600 L345 600 C325 450 325 300 355 170 Z", true, "Trim", StitchKind.SINGLE, 2);
                    trim (back, "d-ring", 330, 610, 14);
                    break;
                case "sneaker":
                    front.name = _("Lateral");
                    back.name = _("Medial");
                    foreach (var sh in sheets) {
                        shape (sh, _("Sole"), "M120 520 L690 520 C720 520 730 500 720 480 L140 470 C110 480 105 515 120 520 Z", false, "Trim");
                        shape (sh, _("Upper"), "M140 470 C150 360 230 300 330 290 L430 250 C480 240 520 270 540 320 C600 330 680 380 720 480 Z", false, "Body", StitchKind.SINGLE, 3);
                        shape (sh, _("Heel Counter"), "M140 470 C140 400 170 350 220 330 L250 470 Z", false, "Trim", StitchKind.DOUBLE, 3);
                        line (sh, _("Toe Cap"), "M620 360 C600 400 610 450 650 480", false, StitchKind.SINGLE, 3);
                        for (int i = 0; i < 5; i++) trim (sh, "eyelet", 420 + i * 30, 285 + i * 12, 5);
                    }
                    break;
                default:
                    shape (front, _("Body"), "M400 120 L355 128 L290 150 L215 190 L185 290 L240 310 L265 250 L265 600 L400 610", true, "Body");
                    line (front, _("Neckline"), "M355 128 C365 170 385 180 400 180", true, StitchKind.COVERSTITCH, 3);
                    line (front, _("Hem"), "M265 585 L400 595", true, StitchKind.COVERSTITCH);
                    line (front, _("Sleeve Hem"), "M190 275 L245 294", true, StitchKind.COVERSTITCH);
                    shape (back, _("Body"), "M400 110 L355 128 L290 150 L215 190 L185 290 L240 310 L265 250 L265 600 L400 610", true, "Body");
                    line (back, _("Neckline"), "M355 128 C365 140 385 145 400 145", true, StitchKind.COVERSTITCH, 3);
                    line (back, _("Hem"), "M265 585 L400 595", true, StitchKind.COVERSTITCH);
                    break;
            }
            return sheets;
        }
    }

    namespace Trims {
        public const string[] KINDS = { "button", "snap", "rivet", "eyelet", "zipper", "buckle", "d-ring", "o-ring", "slider", "cord", "label" };

        public string label (string kind) {
            switch (kind) {
                case "button": return _("Button");
                case "snap": return _("Snap Fastener");
                case "rivet": return _("Rivet");
                case "eyelet": return _("Eyelet");
                case "zipper": return _("Zipper");
                case "buckle": return _("Buckle");
                case "d-ring": return _("D-Ring");
                case "o-ring": return _("O-Ring");
                case "slider": return _("Strap Slider");
                case "cord": return _("Drawcord");
                case "label": return _("Label");
            }
            return kind;
        }

        public void draw (Cairo.Context cr, string kind, double x, double y, double size, double rotation, Rgba fill, Rgba line) {
            cr.save ();
            cr.translate (x, y);
            cr.rotate (rotation * Math.PI / 180);
            cr.set_line_width (double.max (0.5, size * 0.06));
            double r = size / 2;
            switch (kind) {
                case "button":
                    cr.arc (0, 0, r, 0, 2 * Math.PI);
                    fill.apply (cr);
                    cr.fill_preserve ();
                    line.apply (cr);
                    cr.stroke ();
                    for (int i = 0; i < 4; i++) {
                        cr.arc ((i % 2 == 0 ? -1 : 1) * r * 0.28, (i < 2 ? -1 : 1) * r * 0.28, r * 0.1, 0, 2 * Math.PI);
                        cr.fill ();
                    }
                    break;
                case "snap":
                case "rivet":
                    cr.arc (0, 0, r, 0, 2 * Math.PI);
                    fill.apply (cr);
                    cr.fill_preserve ();
                    line.apply (cr);
                    cr.stroke ();
                    cr.arc (0, 0, r * 0.45, 0, 2 * Math.PI);
                    cr.stroke ();
                    break;
                case "eyelet":
                case "o-ring":
                    cr.arc (0, 0, r, 0, 2 * Math.PI);
                    cr.arc_negative (0, 0, r * 0.55, 2 * Math.PI, 0);
                    fill.apply (cr);
                    cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                    cr.fill_preserve ();
                    line.apply (cr);
                    cr.stroke ();
                    break;
                case "zipper": {
                    double len = size;
                    line.apply (cr);
                    cr.move_to (0, -len / 2);
                    cr.line_to (0, len / 2);
                    cr.stroke ();
                    for (double t = -len / 2; t <= len / 2; t += 3) {
                        cr.move_to (-2, t);
                        cr.line_to (2, t + 1.2);
                    }
                    cr.set_line_width (0.4);
                    cr.stroke ();
                    cr.rectangle (-3, -len / 2, 6, 10);
                    fill.apply (cr);
                    cr.fill_preserve ();
                    line.apply (cr);
                    cr.stroke ();
                    break;
                }
                case "buckle":
                case "slider":
                    cr.rectangle (-r, -r * 0.7, size, size * 0.7);
                    cr.rectangle (-r * 0.7, -r * 0.45, size * 0.7, size * 0.45);
                    cr.set_fill_rule (Cairo.FillRule.EVEN_ODD);
                    fill.apply (cr);
                    cr.fill_preserve ();
                    line.apply (cr);
                    cr.stroke ();
                    if (kind == "buckle") {
                        cr.move_to (0, -r * 0.7);
                        cr.line_to (0, r * 0.7);
                        cr.stroke ();
                    }
                    break;
                case "d-ring":
                    cr.move_to (-r, -r);
                    cr.line_to (-r, r);
                    cr.arc_negative (-r, 0, r, Math.PI / 2, -Math.PI / 2);
                    line.apply (cr);
                    cr.set_line_width (double.max (1, size * 0.14));
                    cr.stroke ();
                    break;
                case "cord":
                    line.apply (cr);
                    cr.move_to (0, 0);
                    cr.curve_to (-4, size * 0.3, 4, size * 0.6, 0, size);
                    cr.stroke ();
                    cr.arc (0, size, 2.5, 0, 2 * Math.PI);
                    fill.apply (cr);
                    cr.fill ();
                    break;
                default:
                    cr.rectangle (-r, -r * 0.5, size, size * 0.5);
                    fill.apply (cr);
                    cr.fill_preserve ();
                    line.apply (cr);
                    cr.stroke ();
                    break;
            }
            cr.restore ();
        }
    }

    public class ColorRef {
        public Rgba color;
        public string name = "";
        public string code = "";
        public string book = "";

        public ColorRef (Rgba color, string name = "") {
            this.color = color;
            this.name = name;
        }

        public ColorRef copy () {
            var c = new ColorRef (color, name);
            c.code = code;
            c.book = book;
            return c;
        }
    }

    public class Colorway {
        public string name;
        public Gee.HashMap<string, ColorRef> colors = new Gee.HashMap<string, ColorRef> ();

        public Colorway (string name) {
            this.name = name;
        }

        public Rgba color (string slot, Rgba fallback) {
            if (slot == "" || !colors.has_key (slot)) return fallback;
            return colors[slot].color;
        }

        public Colorway copy (string new_name) {
            var c = new Colorway (new_name);
            foreach (var e in colors.entries) c.colors[e.key] = e.value.copy ();
            return c;
        }

        public static Colorway default_colorway () {
            var c = new Colorway (_("Main"));
            c.colors["Body"] = new ColorRef (Rgba (0.93, 0.92, 0.89), _("Natural"));
            c.colors["Trim"] = new ColorRef (Rgba (0.18, 0.2, 0.25), _("Ink"));
            c.colors["Stitching"] = new ColorRef (Rgba (0.55, 0.42, 0.2), _("Tobacco"));
            c.colors["Outline"] = new ColorRef (Rgba (0.1, 0.1, 0.1), _("Black"));
            c.colors["Lining"] = new ColorRef (Rgba (0.72, 0.18, 0.2), _("Red"));
            return c;
        }
    }
}
