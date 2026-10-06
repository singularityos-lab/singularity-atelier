namespace Singularity.Apps.Atelier {

    public class GarmentSettings {
        public string fabric_preset = "cotton";
        public Gee.HashMap<string, string> piece_fabrics = new Gee.HashMap<string, string> ();
        public Gee.ArrayList<SeamPair> seams = new Gee.ArrayList<SeamPair> ();
        public string pose = "a-pose";
        public string avatar_gender = "female";
        public int resolution = 18;
        public string environment = "studio";
    }

    public class SeamPair {
        public string piece_a;
        public int edge_a;
        public string piece_b;
        public int edge_b;
        public bool reverse_b = true;
        public double ease;

        public SeamPair (string piece_a, int edge_a, string piece_b, int edge_b) {
            this.piece_a = piece_a;
            this.edge_a = edge_a;
            this.piece_b = piece_b;
            this.edge_b = edge_b;
        }
    }

    public class Project : Object {
        public string title { get; set; default = ""; }
        public string? path { get; set; }
        public bool modified { get; set; }
        public string trade = "fashion";
        public Sketch sketch = new Sketch ();
        public Pattern pattern = new Pattern ();
        public Gee.ArrayList<FlatSheet> flats = new Gee.ArrayList<FlatSheet> ();
        public TechPack techpack = new TechPack ();
        public Gee.ArrayList<Colorway> colorways = new Gee.ArrayList<Colorway> ();
        public string active_colorway = "";
        public Gee.ArrayList<string> slots = new Gee.ArrayList<string> ();
        public GarmentSettings garment = new GarmentSettings ();
        public MarkerSettings marker = new MarkerSettings ();
        public ProductModel product = new ProductModel ();

        public signal void changed (string what);

        public Project () {
            foreach (var s in new string[] { "Body", "Trim", "Stitching", "Outline", "Lining" }) slots.add (s);
            var cw = Colorway.default_colorway ();
            colorways.add (cw);
            active_colorway = cw.name;
        }

        public Colorway colorway () {
            foreach (var c in colorways) if (c.name == active_colorway) return c;
            if (colorways.size == 0) colorways.add (Colorway.default_colorway ());
            return colorways[0];
        }

        public Colorway? find_colorway (string name) {
            foreach (var c in colorways) if (c.name == name) return c;
            return null;
        }

        public FlatSheet? find_sheet (string id) {
            foreach (var s in flats) if (s.id == id) return s;
            return null;
        }

        public void touch (string what) {
            modified = true;
            changed (what);
        }

        public void assign_from (Project o) {
            var images = new Gee.HashMap<string, Bytes> ();
            foreach (var l in sketch.all_layers ()) if (l.image_data != null) images[l.id] = l.image_data;
            trade = o.trade;
            sketch = o.sketch;
            pattern = o.pattern;
            flats = o.flats;
            techpack = o.techpack;
            colorways = o.colorways;
            active_colorway = o.active_colorway;
            slots = o.slots;
            garment = o.garment;
            marker = o.marker;
            product = o.product;
            foreach (var l in sketch.all_layers ()) if (l.kind == LayerKind.IMAGE && l.image_data == null && images.has_key (l.id)) l.image_data = images[l.id];
        }

        public static Project create (string trade) {
            var p = new Project ();
            p.trade = trade;
            p.title = _("Untitled");
            switch (trade) {
                case "leather":
                    p.flats.add_all (Flats.build ("tote"));
                    Samples.tote_pattern (p.pattern);
                    p.techpack = TechPack.sample ();
                    p.techpack.poms.clear ();
                    p.techpack.style_name = _("Tote Bag");
                    break;
                case "product":
                case "automotive":
                    p.flats.add_all (Flats.build (trade == "automotive" ? "sneaker" : "backpack"));
                    p.techpack = TechPack.sample ();
                    break;
                default:
                    p.flats.add_all (Flats.build ("tshirt"));
                    Samples.tshirt_pattern (p.pattern);
                    p.techpack = TechPack.sample ();
                    break;
            }
            p.modified = false;
            return p;
        }
    }
}

namespace Singularity.Apps.Atelier {

    public class History : Object {
        private Project project;
        private Gee.ArrayList<string> undo_stack = new Gee.ArrayList<string> ();
        private Gee.ArrayList<string> redo_stack = new Gee.ArrayList<string> ();
        private Gee.HashMap<string, Bytes> images = new Gee.HashMap<string, Bytes> ();
        public int limit = 80;
        public signal void restored ();
        public signal void changed ();

        public History (Project project) {
            this.project = project;
        }

        public bool can_undo {
            get { return undo_stack.size > 0; }
        }

        public bool can_redo {
            get { return redo_stack.size > 0; }
        }

        private void keep_images () {
            foreach (var l in project.sketch.all_layers ()) if (l.image_data != null) images[l.id] = l.image_data;
        }

        public string snapshot () {
            keep_images ();
            return NativeFormat.to_json (project);
        }

        public void checkpoint () {
            commit (snapshot ());
        }

        public void commit (string state) {
            undo_stack.add (state);
            if (undo_stack.size > limit) undo_stack.remove_at (0);
            redo_stack.clear ();
            project.modified = true;
            changed ();
        }

        private void restore (string json) {
            try {
                var p = NativeFormat.from_json (json);
                foreach (var l in p.sketch.all_layers ()) if (l.kind == LayerKind.IMAGE && images.has_key (l.id)) l.image_data = images[l.id];
                project.assign_from (p);
                project.modified = true;
                restored ();
                changed ();
            } catch (Error e) {
                warning ("history: %s", e.message);
            }
        }

        public void undo () {
            if (undo_stack.size == 0) return;
            keep_images ();
            redo_stack.add (NativeFormat.to_json (project));
            restore (undo_stack.remove_at (undo_stack.size - 1));
        }

        public void redo () {
            if (redo_stack.size == 0) return;
            keep_images ();
            undo_stack.add (NativeFormat.to_json (project));
            restore (redo_stack.remove_at (redo_stack.size - 1));
        }

        public void clear () {
            undo_stack.clear ();
            redo_stack.clear ();
            changed ();
        }
    }
}
