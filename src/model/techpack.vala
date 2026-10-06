namespace Singularity.Apps.Atelier {

    public class Pom {
        public string code;
        public string description = "";
        public string method = "";
        public double tol_plus = 0.5;
        public double tol_minus = 0.5;
        public string link = "";
        public Gee.HashMap<string, double?> values = new Gee.HashMap<string, double?> ();

        public Pom (string code, string description = "") {
            this.code = code;
            this.description = description;
        }

        public double? value_for (Pattern pattern, string size, out string? error) {
            error = null;
            if (values.has_key (size)) return values[size];
            if (link == "") return null;
            try {
                return pattern.eval_formula (link, size);
            } catch (ExprError e) {
                error = e.message;
                return null;
            }
        }
    }

    public class BomItem {
        public string id;
        public string category = "fabric";
        public string name = "";
        public string code = "";
        public string supplier = "";
        public string asset_id = "";
        public string placement = "";
        public string composition = "";
        public double quantity = 1;
        public string unit = "pcs";
        public bool from_marker;
        public double waste = 0;
        public double unit_cost;
        public string currency = "EUR";
        public double width_cm;
        public Gee.HashMap<string, string> colors = new Gee.HashMap<string, string> ();

        public BomItem (string id) {
            this.id = id;
        }

        public double total_quantity () {
            return quantity * (1 + waste / 100.0);
        }

        public double cost () {
            return total_quantity () * unit_cost;
        }
    }

    public class Operation {
        public int seq;
        public string description = "";
        public string stitch = "";
        public double spi = 10;
        public string machine = "";
        public string seam = "";
        public int callout;
        public double minutes;
        public string notes = "";

        public Operation (int seq, string description) {
            this.seq = seq;
            this.description = description;
        }
    }

    public class Revision {
        public int number;
        public string date;
        public string author = "";
        public string note = "";
        public string snapshot = "";

        public Revision (int number, string note) {
            this.number = number;
            this.note = note;
            date = new DateTime.now_local ().format ("%Y-%m-%d %H:%M");
        }
    }

    public class Comment {
        public string id;
        public string author = "";
        public string date;
        public string text = "";
        public string sheet = "";
        public double x;
        public double y;
        public bool resolved;
        public Gee.ArrayList<Comment> replies = new Gee.ArrayList<Comment> ();

        public Comment (string id, string text) {
            this.id = id;
            this.text = text;
            date = new DateTime.now_local ().format ("%Y-%m-%d %H:%M");
        }
    }

    public class TechPack {
        public string style_number = "";
        public string style_name = "";
        public string season = "";
        public string brand = "";
        public string designer = "";
        public string category = "";
        public string status = "Development";
        public string notes = "";
        public Gee.ArrayList<Pom> poms = new Gee.ArrayList<Pom> ();
        public Gee.ArrayList<BomItem> bom = new Gee.ArrayList<BomItem> ();
        public Gee.ArrayList<Operation> operations = new Gee.ArrayList<Operation> ();
        public Gee.ArrayList<Revision> revisions = new Gee.ArrayList<Revision> ();
        public Gee.ArrayList<Comment> comments = new Gee.ArrayList<Comment> ();
        private int next_id = 1;

        public string new_id (string prefix) {
            return "%s%d".printf (prefix, next_id++);
        }

        public void bump (string id) {
            int i = 0;
            while (i < id.length && !id[i].isdigit ()) i++;
            int n = int.parse (id.substring (i));
            if (n >= next_id) next_id = n + 1;
        }

        public double total_cost () {
            double t = 0;
            foreach (var b in bom) t += b.cost ();
            return t;
        }

        public double total_minutes () {
            double t = 0;
            foreach (var o in operations) t += o.minutes;
            return t;
        }

        public BomItem? find_bom (string id) {
            foreach (var b in bom) if (b.id == id) return b;
            return null;
        }

        public static TechPack sample () {
            var t = new TechPack ();
            t.style_name = _("New Style");
            t.season = new DateTime.now_local ().format ("%Y");
            var p1 = new Pom ("A", _("Chest width"));
            p1.method = _("1 cm below the armhole, edge to edge");
            p1.link = "bust_circ / 2 + 5";
            t.poms.add (p1);
            var p2 = new Pom ("B", _("Waist width"));
            p2.method = _("At the narrowest point");
            p2.link = "waist_circ / 2 + 5";
            t.poms.add (p2);
            var p3 = new Pom ("C", _("Body length from HPS"));
            p3.method = _("From the high point of the shoulder to the hem");
            p3.link = "back_waist_length + waist_to_hip + 8";
            p3.tol_plus = 1;
            p3.tol_minus = 1;
            t.poms.add (p3);
            var b = new BomItem (t.new_id ("b"));
            b.category = "fabric";
            b.name = _("Main fabric");
            b.unit = "m";
            b.from_marker = true;
            b.width_cm = 150;
            b.quantity = 1.2;
            b.waste = 5;
            b.unit_cost = 9.5;
            t.bom.add (b);
            var th = new BomItem (t.new_id ("b"));
            th.category = "trim";
            th.name = _("Sewing thread");
            th.unit = "m";
            th.quantity = 180;
            th.unit_cost = 0.004;
            t.bom.add (th);
            var lb = new BomItem (t.new_id ("b"));
            lb.category = "label";
            lb.name = _("Main label");
            lb.quantity = 1;
            lb.unit_cost = 0.12;
            t.bom.add (lb);
            var o1 = new Operation (1, _("Join shoulders"));
            o1.stitch = "504";
            o1.machine = _("Overlock");
            o1.minutes = 0.6;
            t.operations.add (o1);
            var o2 = new Operation (2, _("Attach sleeves"));
            o2.stitch = "504";
            o2.machine = _("Overlock");
            o2.minutes = 1.1;
            t.operations.add (o2);
            var o3 = new Operation (3, _("Close side seams"));
            o3.stitch = "504";
            o3.machine = _("Overlock");
            o3.minutes = 0.9;
            t.operations.add (o3);
            var o4 = new Operation (4, _("Hem with coverstitch"));
            o4.stitch = "406";
            o4.machine = _("Coverstitch");
            o4.minutes = 0.8;
            t.operations.add (o4);
            return t;
        }
    }
}
