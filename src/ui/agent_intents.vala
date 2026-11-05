namespace Singularity.Apps.Atelier {

    internal class AtelierIntents : Object {
        private const string[] TRADES = { "fashion", "leather", "product", "automotive" };
        private const string[] WORKSPACES = { "sketch", "pattern", "flats", "techpack", "3d" };
        private const string[] EXPORTS = {
            "sketch-svg", "sketch-pdf", "ora", "aama", "astm", "seamly", "measurements", "hpgl",
            "pdf-large", "pdf-tiled", "pattern-svg", "flats-svg", "flats-pdf", "flats-image",
            "techpack-pdf", "odt", "xlsx", "ods", "bom-csv"
        };
        private const string[] TECHPACK_FIELDS = { "style_name", "season", "brand", "designer", "category", "status", "notes" };

        private static string text (Json.Object args, string key) {
            return args.has_member (key) ? args.get_string_member (key) : "";
        }

        private static Json.Node obj (Json.Object o) {
            var node = new Json.Node (Json.NodeType.OBJECT);
            node.set_object (o);
            return node;
        }

        private static string list (string[] values) {
            var b = new StringBuilder ("[");
            for (int i = 0; i < values.length; i++) {
                if (i > 0) b.append (",");
                b.append ("\"").append (values[i]).append ("\"");
            }
            return b.append ("]").str;
        }

        private static AtelierWindow window (AtelierApp app, bool need_project = true) {
            AtelierWindow? found = app.get_active_window () as AtelierWindow;
            if (found == null || found.is_empty ()) {
                foreach (var w in app.get_windows ()) {
                    var aw = w as AtelierWindow;
                    if (aw != null && !aw.is_empty ()) {
                        found = aw;
                        break;
                    }
                }
            }
            if (found == null) {
                found = new AtelierWindow (app);
            }
            if (need_project && found.is_empty ()) found.new_project ("fashion");
            found.present ();
            return found;
        }

        private static string techpack_field (TechPack t, string name) {
            switch (name) {
                case "style_name": return t.style_name;
                case "season": return t.season;
                case "brand": return t.brand;
                case "designer": return t.designer;
                case "category": return t.category;
                case "status": return t.status;
                default: return t.notes;
            }
        }

        private static void set_techpack_field (TechPack t, string name, string value) {
            switch (name) {
                case "style_name": t.style_name = value; break;
                case "season": t.season = value; break;
                case "brand": t.brand = value; break;
                case "designer": t.designer = value; break;
                case "category": t.category = value; break;
                case "status": t.status = value; break;
                default: t.notes = value; break;
            }
        }

        private static Json.Node outline (AtelierWindow w) {
            var p = w.project;
            var o = new Json.Object ();
            o.set_string_member ("title", p.title);
            o.set_string_member ("trade", p.trade);
            o.set_string_member ("path", p.path ?? "");
            o.set_boolean_member ("modified", p.modified);

            var pieces = new Json.Array ();
            foreach (var piece in p.pattern.pieces) {
                var po = new Json.Object ();
                po.set_string_member ("id", piece.id);
                po.set_string_member ("name", piece.name);
                po.set_string_member ("code", piece.code);
                po.set_string_member ("material", piece.material);
                po.set_int_member ("quantity", piece.quantity);
                po.set_boolean_member ("pair", piece.pair);
                po.set_boolean_member ("on_fold", piece.on_fold);
                pieces.add_object_element (po);
            }
            o.set_array_member ("pieces", pieces);

            var table = p.pattern.table;
            var m = new Json.Object ();
            if (table != null) {
                m.set_string_member ("name", table.name);
                m.set_string_member ("unit", table.unit);
                var sizes = new Json.Array ();
                foreach (var s in table.sizes) sizes.add_string_element (s);
                m.set_array_member ("sizes", sizes);
                m.set_string_member ("base_size", table.base_size);
                m.set_string_member ("active_size", p.pattern.active_size);
                var items = new Json.Array ();
                foreach (var it in table.items) {
                    var io = new Json.Object ();
                    io.set_string_member ("name", it.name);
                    io.set_string_member ("full_name", it.full_name);
                    io.set_double_member ("base_value", it.base_value);
                    io.set_double_member ("size_step", it.size_step);
                    items.add_object_element (io);
                }
                m.set_array_member ("items", items);
            }
            o.set_object_member ("measurements", m);

            var sheets = new Json.Array ();
            foreach (var s in p.flats) {
                var so = new Json.Object ();
                so.set_string_member ("id", s.id);
                so.set_string_member ("name", s.name);
                so.set_int_member ("items", s.items.size);
                sheets.add_object_element (so);
            }
            o.set_array_member ("flats", sheets);

            var colorways = new Json.Array ();
            foreach (var c in p.colorways) colorways.add_string_element (c.name);
            o.set_array_member ("colorways", colorways);
            o.set_string_member ("active_colorway", p.active_colorway);

            var t = new Json.Object ();
            foreach (var f in TECHPACK_FIELDS) t.set_string_member (f, techpack_field (p.techpack, f));
            t.set_int_member ("materials", p.techpack.bom.size);
            t.set_int_member ("points_of_measure", p.techpack.poms.size);
            t.set_int_member ("operations", p.techpack.operations.size);
            o.set_object_member ("techpack", t);
            return obj (o);
        }

        private static Json.Node saved (AtelierWindow w) {
            var o = new Json.Object ();
            o.set_string_member ("path", w.project.path ?? "");
            o.set_string_member ("title", w.project.title);
            return obj (o);
        }

        internal static void install (AtelierApp app) {
            var agent = app.agent;
            agent.add_intent ("atelier_outline", "Read the open project: trade, pattern pieces, measurement table and sizes, technical drawing sheets, colorways and tech pack fields.",
                "{\"type\":\"object\",\"properties\":{}}",
                Singularity.AppIntentRisk.READ, (args) => outline (window (app)));

            agent.add_intent ("atelier_new", "Start a new project from a trade template.",
                "{\"type\":\"object\",\"properties\":{\"trade\":{\"type\":\"string\",\"enum\":" + list (TRADES) + "}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    string trade = text (args, "trade");
                    if (!(trade in TRADES)) trade = "fashion";
                    var w = window (app, false);
                    if (!w.is_empty ()) {
                        w = new AtelierWindow (app);
                        w.present ();
                    }
                    w.new_project (trade);
                    return outline (w);
                });

            agent.add_intent ("atelier_open", "Open a project or pattern file: Atelier, DXF (AAMA/ASTM), Seamly2D or Valentina.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}},\"required\":[\"path\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    string path = text (args, "path");
                    if (!FileUtils.test (path, FileTest.IS_REGULAR)) throw new IOError.NOT_FOUND ("%s does not exist", path);
                    var w = window (app, false);
                    if (!w.is_empty ()) {
                        w = new AtelierWindow (app);
                        w.present ();
                    }
                    w.open_file (File.new_for_path (path));
                    if (w.is_empty ()) throw new IOError.FAILED ("%s could not be opened", path);
                    return outline (w);
                });

            agent.add_intent ("atelier_save", "Save the project as an Atelier file, to its file, a given path, or the Documents folder.",
                "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    var w = window (app);
                    string target = text (args, "path");
                    if (target == "") target = w.project.path ?? "";
                    if (target == "" || !target.down ().has_suffix (".atelier")) {
                        if (target == "") {
                            string dir = Environment.get_user_special_dir (UserDirectory.DOCUMENTS) ?? Environment.get_home_dir ();
                            target = Path.build_filename (dir, (w.project.title != "" ? w.project.title : _("Untitled")) + ".atelier");
                        } else {
                            target += ".atelier";
                        }
                    }
                    w.write_to (target);
                    return saved (w);
                });

            agent.add_intent ("atelier_export", "Export the project to a file: sketch, pattern (DXF, Seamly2D, HPGL, PDF, SVG), technical drawings, tech pack (PDF, ODT, spreadsheets) or bill of materials.",
                "{\"type\":\"object\",\"properties\":{\"format\":{\"type\":\"string\",\"enum\":" + list (EXPORTS) + "},\"path\":{\"type\":\"string\"}},\"required\":[\"format\",\"path\"]}",
                Singularity.AppIntentRisk.IRREVERSIBLE, (args) => {
                    string format = text (args, "format");
                    if (!(format in EXPORTS)) throw new IOError.INVALID_ARGUMENT ("unknown export format %s", format);
                    string path = text (args, "path");
                    if (path == "") throw new IOError.INVALID_ARGUMENT ("a path is required");
                    window (app).export_to (format, path);
                    var o = new Json.Object ();
                    o.set_string_member ("format", format);
                    o.set_string_member ("path", path);
                    return obj (o);
                });

            agent.add_intent ("atelier_techpack", "Change the tech pack header: style name, season, brand, designer, category, status and notes.",
                "{\"type\":\"object\",\"properties\":{\"style_name\":{\"type\":\"string\"},\"season\":{\"type\":\"string\"},\"brand\":{\"type\":\"string\"},\"designer\":{\"type\":\"string\"},\"category\":{\"type\":\"string\"},\"status\":{\"type\":\"string\"},\"notes\":{\"type\":\"string\"}}}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    w.history.checkpoint ();
                    foreach (var f in TECHPACK_FIELDS) if (args.has_member (f)) set_techpack_field (w.project.techpack, f, text (args, f));
                    w.project.touch ("techpack");
                    w.refresh_all ();
                    return outline (w);
                });

            agent.add_intent ("atelier_colorway", "Switch the active colorway, or add a new one copied from the active colorway.",
                "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"create\":{\"type\":\"boolean\"}},\"required\":[\"name\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var p = w.project;
                    string name = text (args, "name");
                    bool create = args.has_member ("create") && args.get_boolean_member ("create");
                    var found = p.find_colorway (name);
                    if (found == null && !create) throw new IOError.NOT_FOUND ("there is no colorway named %s", name);
                    w.history.checkpoint ();
                    if (found == null) p.colorways.add (p.colorway ().copy (name));
                    p.active_colorway = name;
                    p.touch ("colorway");
                    w.refresh_all ();
                    return outline (w);
                });

            agent.add_intent ("atelier_size", "Show the pattern in one of the sizes of its measurement table.",
                "{\"type\":\"object\",\"properties\":{\"size\":{\"type\":\"string\"}},\"required\":[\"size\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    var w = window (app);
                    var p = w.project;
                    string size = text (args, "size");
                    if (p.pattern.table == null || !p.pattern.table.sizes.contains (size)) throw new IOError.NOT_FOUND ("the measurement table has no size %s", size);
                    p.pattern.active_size = size;
                    p.touch ("measurements");
                    w.refresh_all ();
                    return outline (w);
                });

            agent.add_intent ("atelier_workspace", "Show one workspace of the project: sketch, pattern, technical drawings, tech pack or 3D.",
                "{\"type\":\"object\",\"properties\":{\"workspace\":{\"type\":\"string\",\"enum\":" + list (WORKSPACES) + "}},\"required\":[\"workspace\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    string name = text (args, "workspace");
                    if (!(name in WORKSPACES)) throw new IOError.INVALID_ARGUMENT ("unknown workspace %s", name);
                    var w = window (app);
                    w.show_workspace (name);
                    var o = new Json.Object ();
                    o.set_string_member ("workspace", name);
                    return obj (o);
                });
        }
    }
}
