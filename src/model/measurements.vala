namespace Singularity.Apps.Atelier {

    public class Measurement {
        public string name;
        public string full_name = "";
        public string description = "";
        public string formula = "";
        public double base_value;
        public double size_step;
        public double height_step;
        public Gee.HashMap<string, double?> per_size = new Gee.HashMap<string, double?> ();

        public Measurement (string name, double base_value = 0) {
            this.name = name;
            this.base_value = base_value;
        }

        public Measurement copy () {
            var m = new Measurement (name, base_value);
            m.full_name = full_name;
            m.description = description;
            m.formula = formula;
            m.size_step = size_step;
            m.height_step = height_step;
            foreach (var e in per_size.entries) m.per_size[e.key] = e.value;
            return m;
        }
    }

    public enum TableKind {
        INDIVIDUAL,
        MULTISIZE
    }

    public class MeasurementTable {
        public TableKind kind = TableKind.MULTISIZE;
        public string name = "";
        public string unit = "cm";
        public Gee.ArrayList<string> sizes = new Gee.ArrayList<string> ();
        public string base_size = "";
        public Gee.ArrayList<Measurement> items = new Gee.ArrayList<Measurement> ();
        public string customer = "";
        public string gender = "";

        public double unit_mm () {
            switch (unit) {
                case "mm": return 1;
                case "inch": case "in": return 25.4;
                default: return 10;
            }
        }

        public Measurement? find (string name) {
            string n = name.has_prefix ("@") ? name.substring (1) : name;
            foreach (var m in items) if (m.name == n) return m;
            return null;
        }

        public int size_index (string size) {
            return sizes.index_of (size);
        }

        public int base_index () {
            int i = sizes.index_of (base_size);
            return i >= 0 ? i : 0;
        }

        public double value (string name, string? size = null) throws ExprError {
            var m = find (name);
            if (m == null) throw new ExprError.UNKNOWN ("Unknown measurement \"%s\"".printf (name));
            return value_of (m, size, 0);
        }

        private double value_of (Measurement m, string? size, int depth) throws ExprError {
            if (depth > 32) throw new ExprError.MATH ("Circular measurement \"%s\"".printf (m.name));
            string s = size ?? base_size;
            if (m.per_size.has_key (s)) return m.per_size[s];
            if (m.formula != "") {
                return Expr.evaluate (m.formula, (n, out v) => {
                    v = 0;
                    var other = find (n);
                    if (other == null || other == m) return false;
                    try {
                        v = value_of (other, size, depth + 1);
                        return true;
                    } catch (ExprError e) {
                        return false;
                    }
                });
            }
            if (kind == TableKind.MULTISIZE && sizes.size > 0) {
                int idx = size_index (s);
                if (idx < 0) idx = base_index ();
                return m.base_value + m.size_step * (idx - base_index ());
            }
            return m.base_value;
        }

        public double value_mm (string name, string? size = null) throws ExprError {
            return value (name, size) * unit_mm ();
        }

        public bool lookup (string name, string? size, out double v) {
            v = 0;
            var m = find (name);
            if (m == null) return false;
            try {
                v = value_of (m, size, 0) * unit_mm ();
                return true;
            } catch (ExprError e) {
                return false;
            }
        }

        public MeasurementTable copy () {
            var t = new MeasurementTable ();
            t.kind = kind;
            t.name = name;
            t.unit = unit;
            t.sizes.add_all (sizes);
            t.base_size = base_size;
            t.customer = customer;
            t.gender = gender;
            foreach (var m in items) t.items.add (m.copy ());
            return t;
        }

        public static MeasurementTable standard_women () {
            var t = new MeasurementTable ();
            t.name = "Women EU";
            t.unit = "cm";
            t.gender = "female";
            foreach (var s in new string[] { "34", "36", "38", "40", "42", "44", "46" }) t.sizes.add (s);
            t.base_size = "38";
            add (t, "height", "Height", 168, 0);
            add (t, "bust_circ", "Bust circumference", 88, 4);
            add (t, "waist_circ", "Waist circumference", 70, 4);
            add (t, "hip_circ", "Hip circumference", 96, 4);
            add (t, "neck_circ", "Neck circumference", 35, 1);
            add (t, "shoulder_length", "Shoulder length", 12.5, 0.3);
            add (t, "across_back", "Across back", 35, 1);
            add (t, "back_waist_length", "Neck to waist, back", 41, 0.5);
            add (t, "front_waist_length", "Neck to waist, front", 43, 0.6);
            add (t, "bust_point_distance", "Bust point to bust point", 19, 0.6);
            add (t, "bust_height", "Neck to bust point", 26, 0.5);
            add (t, "arm_length", "Shoulder to wrist", 60, 0.5);
            add (t, "upper_arm_circ", "Upper arm circumference", 28, 1.2);
            add (t, "wrist_circ", "Wrist circumference", 16, 0.5);
            add (t, "waist_to_hip", "Waist to hip", 20, 0.3);
            add (t, "waist_to_knee", "Waist to knee", 58, 0.5);
            add (t, "waist_to_floor", "Waist to floor", 104, 0.8);
            add (t, "inseam", "Inside leg", 78, 0.6);
            add (t, "crotch_depth", "Body rise", 27, 0.4);
            add (t, "thigh_circ", "Thigh circumference", 56, 2);
            add (t, "knee_circ", "Knee circumference", 37, 1);
            add (t, "ankle_circ", "Ankle circumference", 23, 0.5);
            add (t, "head_circ", "Head circumference", 56, 0.3);
            return t;
        }

        public static MeasurementTable standard_men () {
            var t = new MeasurementTable ();
            t.name = "Men EU";
            t.unit = "cm";
            t.gender = "male";
            foreach (var s in new string[] { "44", "46", "48", "50", "52", "54", "56" }) t.sizes.add (s);
            t.base_size = "50";
            add (t, "height", "Height", 180, 1);
            add (t, "bust_circ", "Chest circumference", 100, 4);
            add (t, "waist_circ", "Waist circumference", 88, 4);
            add (t, "hip_circ", "Hip circumference", 102, 4);
            add (t, "neck_circ", "Neck circumference", 40, 1);
            add (t, "shoulder_length", "Shoulder length", 15, 0.4);
            add (t, "across_back", "Across back", 40, 1);
            add (t, "back_waist_length", "Neck to waist, back", 46, 0.5);
            add (t, "front_waist_length", "Neck to waist, front", 44, 0.5);
            add (t, "bust_point_distance", "Nipple to nipple", 21, 0.6);
            add (t, "bust_height", "Neck to chest line", 25, 0.5);
            add (t, "arm_length", "Shoulder to wrist", 64, 0.6);
            add (t, "upper_arm_circ", "Upper arm circumference", 32, 1.2);
            add (t, "wrist_circ", "Wrist circumference", 18, 0.5);
            add (t, "waist_to_hip", "Waist to hip", 20, 0.3);
            add (t, "waist_to_knee", "Waist to knee", 60, 0.5);
            add (t, "waist_to_floor", "Waist to floor", 110, 1);
            add (t, "inseam", "Inside leg", 82, 0.8);
            add (t, "crotch_depth", "Body rise", 27, 0.3);
            add (t, "thigh_circ", "Thigh circumference", 58, 2);
            add (t, "knee_circ", "Knee circumference", 40, 1);
            add (t, "ankle_circ", "Ankle circumference", 25, 0.5);
            add (t, "head_circ", "Head circumference", 58, 0.3);
            return t;
        }

        private static void add (MeasurementTable t, string name, string full, double base_value, double step) {
            var m = new Measurement (name, base_value);
            m.full_name = full;
            m.size_step = step;
            t.items.add (m);
        }
    }
}
