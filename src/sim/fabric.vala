namespace Singularity.Apps.Atelier {

    public class FabricPreset {
        public string id;
        public string name;
        public double stretch_compliance;
        public double shear_compliance;
        public double bend_compliance;
        public double density;
        public double friction;
        public double thickness;
        public double damping = 0.05;
        public Rgba color = Rgba (0.85, 0.85, 0.85, 1);
        public double roughness = 0.85;
        public double metallic = 0;
        public double stretch_weft = 9000;
        public double stretch_warp = 11000;
        public double shear = 500;
        public double bend_weft = 12;
        public double bend_warp = 12;
        public double shrink_weft = 1;
        public double shrink_warp = 1;
        public double sheen = 0.15;
        public double weave = 0.25;
        public double weave_scale = 1.8;

        public void physics (double weft, double warp, double shear, double bend_weft, double bend_warp) {
            stretch_weft = weft;
            stretch_warp = warp;
            this.shear = shear;
            this.bend_weft = bend_weft;
            this.bend_warp = bend_warp;
        }

        public FabricPreset (string id, string name, double stretch, double shear, double bend, double density, double friction, double thickness) {
            this.id = id;
            this.name = name;
            stretch_compliance = stretch;
            shear_compliance = shear;
            bend_compliance = bend;
            this.density = density;
            this.friction = friction;
            this.thickness = thickness;
        }

        private static Gee.ArrayList<FabricPreset>? cache;

        public static Gee.List<FabricPreset> all () {
            if (cache == null) {
                cache = new Gee.ArrayList<FabricPreset> ();
                var jersey = new FabricPreset ("jersey", _("Cotton Jersey"), 2e-5, 6e-5, 0.4, 180, 0.35, 0.8);
                jersey.color = Rgba (0.9, 0.9, 0.88, 1);
                jersey.physics (450, 700, 160, 3, 4);
                jersey.weave_scale = 1.2;
                cache.add (jersey);
                var cotton = new FabricPreset ("cotton", _("Cotton Poplin"), 4e-6, 2e-5, 0.15, 120, 0.4, 0.4);
                cotton.color = Rgba (0.93, 0.92, 0.89, 1);
                cotton.physics (9000, 11000, 520, 12, 14);
                cotton.weave_scale = 2.4;
                cache.add (cotton);
                var denim = new FabricPreset ("denim", _("Denim"), 1e-6, 6e-6, 0.02, 400, 0.5, 1.2);
                denim.color = Rgba (0.24, 0.33, 0.52, 1);
                denim.roughness = 0.9;
                denim.physics (26000, 32000, 2600, 110, 140);
                denim.weave = 0.45;
                denim.weave_scale = 1.1;
                cache.add (denim);
                var leather = new FabricPreset ("leather", _("Leather"), 4e-7, 2e-6, 0.004, 900, 0.6, 1.4);
                leather.color = Rgba (0.45, 0.28, 0.16, 1);
                leather.roughness = 0.45;
                leather.physics (42000, 42000, 16000, 900, 900);
                leather.weave = 0;
                leather.sheen = 0;
                cache.add (leather);
                var silk = new FabricPreset ("silk", _("Silk Charmeuse"), 6e-6, 3e-5, 0.8, 70, 0.15, 0.2);
                silk.color = Rgba (0.85, 0.75, 0.8, 1);
                silk.roughness = 0.3;
                silk.physics (6000, 7000, 240, 1.2, 1.6);
                silk.weave = 0.05;
                silk.weave_scale = 4;
                silk.sheen = 0.5;
                cache.add (silk);
                var wool = new FabricPreset ("wool", _("Wool Suiting"), 2e-6, 1e-5, 0.05, 280, 0.55, 0.9);
                wool.color = Rgba (0.3, 0.3, 0.33, 1);
                wool.physics (8000, 9000, 520, 24, 28);
                wool.weave = 0.35;
                wool.weave_scale = 1.4;
                wool.sheen = 0.25;
                cache.add (wool);
                var fleece = new FabricPreset ("fleece", _("Fleece"), 1e-5, 4e-5, 0.08, 300, 0.6, 2.5);
                fleece.color = Rgba (0.55, 0.6, 0.62, 1);
                fleece.physics (800, 1000, 320, 28, 30);
                fleece.weave = 0.5;
                fleece.weave_scale = 0.7;
                fleece.sheen = 0.4;
                cache.add (fleece);
            }
            return cache;
        }

        public static FabricPreset find (string? id) {
            foreach (var f in all ()) if (f.id == id) return f;
            return all ()[1];
        }
    }
}
