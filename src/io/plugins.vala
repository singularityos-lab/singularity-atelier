namespace Singularity.Apps.Atelier {

    public class PluginHost : Object {
        private static PluginHost? instance;
        private Peas.Engine engine;
        public Gee.ArrayList<AtelierPlugin.Exporter> exporters = new Gee.ArrayList<AtelierPlugin.Exporter> ();
        public Gee.ArrayList<AtelierPlugin.GradeRuleProvider> rule_providers = new Gee.ArrayList<AtelierPlugin.GradeRuleProvider> ();
        public Gee.ArrayList<string> loaded = new Gee.ArrayList<string> ();

        public static PluginHost get_default () {
            if (instance == null) instance = new PluginHost ();
            return instance;
        }

        public static string[] search_dirs () {
            string[] dirs = {};
            string? env = Environment.get_variable ("SINGULARITY_ATELIER_PLUGIN_PATH");
            if (env != null) foreach (var p in env.split (":")) if (p != "") dirs += p;
            try {
                string exe = FileUtils.read_link ("/proc/self/exe");
                string prefix = Path.get_dirname (Path.get_dirname (exe));
                foreach (string libdir in new string[] { "lib", "lib64", "lib/x86_64-linux-gnu", "lib/aarch64-linux-gnu" }) dirs += Path.build_filename (prefix, libdir, "singularity-atelier", "plugins");
            } catch (Error e) {
            }
            dirs += Path.build_filename (Environment.get_user_data_dir (), "singularity-atelier", "plugins");
            return dirs;
        }

        private PluginHost () {
            engine = new Peas.Engine ();
            foreach (var d in search_dirs ()) {
                if (!FileUtils.test (d, FileTest.IS_DIR)) continue;
                engine.add_search_path (d, d);
                try {
                    var dir = Dir.open (d);
                    string? name;
                    while ((name = dir.read_name ()) != null) {
                        string sub = Path.build_filename (d, name);
                        if (FileUtils.test (sub, FileTest.IS_DIR)) engine.add_search_path (sub, sub);
                    }
                } catch (Error e) {
                }
            }
            engine.rescan_plugins ();
            var model = (ListModel) engine;
            for (uint i = 0; i < model.get_n_items (); i++) {
                var info = (Peas.PluginInfo) model.get_item (i);
                if (!info.is_loaded ()) engine.load_plugin (info);
                if (!info.is_loaded ()) continue;
                loaded.add (info.get_module_name ());
                if (engine.provides_extension (info, typeof (AtelierPlugin.Exporter))) {
                    var ext = engine.create_extension_with_properties (info, typeof (AtelierPlugin.Exporter), {}, {});
                    if (ext != null) exporters.add ((AtelierPlugin.Exporter) ext);
                }
                if (engine.provides_extension (info, typeof (AtelierPlugin.GradeRuleProvider))) {
                    var ext = engine.create_extension_with_properties (info, typeof (AtelierPlugin.GradeRuleProvider), {}, {});
                    if (ext != null) rule_providers.add ((AtelierPlugin.GradeRuleProvider) ext);
                }
            }
        }

        public AtelierPlugin.Exporter? find_exporter (string id) {
            foreach (var e in exporters) if (e.id == id) return e;
            return null;
        }

        public string pattern_json (Pattern p) {
            var b = new Json.Builder ();
            b.begin_object ();
            b.set_member_name ("unit").add_string_value (p.unit);
            b.set_member_name ("base_size").add_string_value (p.table.base_size);
            b.set_member_name ("sizes").begin_array ();
            foreach (var s in p.table.sizes) b.add_string_value (s);
            b.end_array ();
            b.set_member_name ("points").begin_array ();
            var r = p.evaluate (p.table.base_size);
            foreach (var pt in p.points) {
                if (!r.points.has_key (pt.id)) continue;
                b.begin_object ();
                b.set_member_name ("name").add_string_value (pt.name);
                b.set_member_name ("rule").add_int_value (pt.rule);
                b.set_member_name ("x").add_double_value (r.points[pt.id].x);
                b.set_member_name ("y").add_double_value (r.points[pt.id].y);
                b.end_object ();
            }
            b.end_array ();
            b.set_member_name ("measurements").begin_object ();
            foreach (var m in p.table.items) {
                b.set_member_name (m.name).begin_object ();
                foreach (var s in p.table.sizes) {
                    double v = 0;
                    try {
                        v = p.table.value (m.name, s);
                    } catch (ExprError e) {
                    }
                    b.set_member_name (s).add_double_value (v);
                }
                b.end_object ();
            }
            b.end_object ();
            b.end_object ();
            var g = new Json.Generator ();
            g.set_root (b.get_root ());
            return g.to_data (null);
        }
    }
}
