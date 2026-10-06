using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class VehicleTemplate {
        public string kind = "sedan";
        public double wheelbase = 2800;
        public double length = 4700;
        public double height = 1450;
        public double wheel = 680;
        public double front_overhang = 900;
        public double ground = 140;

        public const string[] KINDS = { "sedan", "hatchback", "suv", "coupe", "sports", "van", "pickup" };

        public static string label (string kind) {
            switch (kind) {
                case "hatchback": return _("Hatchback");
                case "suv": return _("SUV");
                case "coupe": return _("Coupé");
                case "sports": return _("Sports Car");
                case "van": return _("Van");
                case "pickup": return _("Pickup");
                default: return _("Sedan");
            }
        }

        public static VehicleTemplate preset (string kind) {
            var t = new VehicleTemplate ();
            t.kind = kind;
            switch (kind) {
                case "hatchback":
                    t.wheelbase = 2600; t.length = 4100; t.height = 1480; t.wheel = 640; t.front_overhang = 850;
                    break;
                case "suv":
                    t.wheelbase = 2850; t.length = 4750; t.height = 1720; t.wheel = 760; t.front_overhang = 920; t.ground = 200;
                    break;
                case "coupe":
                    t.wheelbase = 2700; t.length = 4600; t.height = 1360; t.wheel = 680; t.front_overhang = 880;
                    break;
                case "sports":
                    t.wheelbase = 2450; t.length = 4380; t.height = 1180; t.wheel = 670; t.front_overhang = 1000; t.ground = 110;
                    break;
                case "van":
                    t.wheelbase = 3300; t.length = 5300; t.height = 2000; t.wheel = 700; t.front_overhang = 900; t.ground = 180;
                    break;
                case "pickup":
                    t.wheelbase = 3300; t.length = 5400; t.height = 1850; t.wheel = 800; t.front_overhang = 950; t.ground = 230;
                    break;
                default:
                    break;
            }
            return t;
        }

        public double rear_overhang () {
            return length - wheelbase - front_overhang;
        }

        public PathData ground_line () {
            var p = new PathData ();
            p.move_to (-200, 0);
            p.line_to (length + 200, 0);
            return p;
        }

        public PathData wheels () {
            var p = new PathData ();
            double r = wheel / 2;
            p.add_ellipse (front_overhang, -r, r, r);
            p.add_ellipse (front_overhang + wheelbase, -r, r, r);
            p.add_ellipse (front_overhang, -r, r * 0.6, r * 0.6);
            p.add_ellipse (front_overhang + wheelbase, -r, r * 0.6, r * 0.6);
            return p;
        }

        public PathData body () {
            double r = wheel / 2;
            double belt = -height * (kind == "sports" ? 0.62 : 0.58);
            double roof = -height;
            double f = front_overhang, b = front_overhang + wheelbase;
            double hood_y = belt - (kind == "suv" || kind == "van" || kind == "pickup" ? 120 : 40);
            double a_pillar = f + wheelbase * (kind == "sports" ? 0.28 : (kind == "van" ? 0.02 : 0.18));
            double c_pillar = b - wheelbase * (kind == "hatchback" || kind == "suv" ? -0.05 : (kind == "coupe" || kind == "sports" ? 0.05 : 0.12));
            if (kind == "van") c_pillar = length - 60;
            var p = new PathData ();
            p.move_to (0, -ground - 150);
            p.curve_to (0, -ground - 350, 60, hood_y + 60, 180, hood_y);
            p.line_to (a_pillar - 150, hood_y - 20);
            p.curve_to (a_pillar + 40, roof + 180, a_pillar + 120, roof + 30, a_pillar + 400, roof);
            if (kind == "pickup") {
                p.line_to (b - 700, roof);
                p.curve_to (b - 600, roof + 20, b - 600, belt, b - 600, belt);
                p.line_to (length, belt);
            } else {
                p.line_to (c_pillar - 300, roof);
                p.curve_to (c_pillar - 60, roof + 20, c_pillar + 80, roof + 200, kind == "hatchback" || kind == "suv" || kind == "van" ? length - 40 : c_pillar + 380, kind == "hatchback" || kind == "suv" || kind == "van" ? roof + 250 : belt + 20);
                p.curve_to (length - 60, belt, length, belt + 60, length, belt + 180);
            }
            p.line_to (length, -ground - 150);
            p.line_to (b + r + 80, -ground - 100);
            p.arc_to (b, -r, r + 60, r + 60, 0, -Math.PI, true);
            p.line_to (f + r + 60, -ground - 100);
            p.arc_to (f, -r, r + 60, r + 60, 0, -Math.PI, true);
            p.line_to (0, -ground - 150);
            p.close ();
            return p;
        }

        public PathData guides () {
            var p = new PathData ();
            p.move_to (front_overhang, 50);
            p.line_to (front_overhang, -height - 150);
            p.move_to (front_overhang + wheelbase, 50);
            p.line_to (front_overhang + wheelbase, -height - 150);
            p.move_to (-100, -height);
            p.line_to (length + 100, -height);
            return p;
        }
    }
}
