using Gtk;

namespace Singularity.Apps.Atelier {

    public class AtelierApp : Singularity.Application {
        public GLib.Settings? settings;
        private string? new_trade;

        public AtelierApp () {
            Object (application_id: "dev.sinty.atelier", flags: ApplicationFlags.HANDLES_OPEN);
            add_main_option ("new", 0, OptionFlags.NONE, OptionArg.STRING, _("Start a new project: fashion, leather, product or automotive"), "TRADE");
            var schema = SettingsSchemaSource.get_default ()?.lookup ("dev.sinty.atelier", true);
            if (schema != null) settings = new GLib.Settings ("dev.sinty.atelier");
        }

        public int get_int (string key, int fallback) {
            return settings != null ? settings.get_int (key) : fallback;
        }

        public bool get_bool (string key, bool fallback) {
            return settings != null ? settings.get_boolean (key) : fallback;
        }

        public string get_str (string key, string fallback) {
            return settings != null ? settings.get_string (key) : fallback;
        }

        protected override int handle_local_options (VariantDict options) {
            string? t = null;
            if (options.contains ("new")) {
                options.lookup ("new", "s", out t);
                new_trade = t != null && t != "" ? t : "fashion";
            }
            return -1;
        }

        protected override void startup () {
            base.startup ();
            about_version = "0.1.0";
            about_license = _("GNU General Public License, version 3 only");
            Gtk.IconTheme.get_for_display (Gdk.Display.get_default ()).add_resource_path ("/dev/sinty/atelier/icons");
            Singularity.Application.add_app_css (CSS);
            var new_action = new SimpleAction ("new", VariantType.STRING);
            new_action.activate.connect ((v) => {
                var w = get_active_window () as AtelierWindow;
                if (w == null || w.project != null) {
                    w = new AtelierWindow (this);
                    w.present ();
                }
                w.new_project (v.get_string ());
            });
            add_action (new_action);
            var open_action = new SimpleAction ("open", null);
            open_action.activate.connect (() => {
                var w = get_active_window () as AtelierWindow;
                if (w == null) {
                    w = new AtelierWindow (this);
                    w.present ();
                }
                w.choose_open ();
            });
            add_action (open_action);
            var quit = new SimpleAction ("quit", null);
            quit.activate.connect (() => {
                var windows = new Gee.ArrayList<Gtk.Window> ();
                foreach (var w in get_windows ()) windows.add (w);
                foreach (var w in windows) w.close ();
            });
            add_action (quit);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.atelier");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            build_menu ();
            string[,] accels = {
                { "app.quit", "<Control>q" }, { "app.open", "<Control>o" }, { "app.settings", "<Control>comma" },
                { "win.save", "<Control>s" }, { "win.save-as", "<Control><Shift>s" }, { "win.close-project", "<Control>w" },
                { "win.undo", "<Control>z" }, { "win.print", "<Control>p" }, { "win.export-pdf", "<Control><Shift>e" },
                { "win.workspace::sketch", "<Alt>1" }, { "win.workspace::pattern", "<Alt>2" }, { "win.workspace::flats", "<Alt>3" },
                { "win.workspace::techpack", "<Alt>4" }, { "win.workspace::3d", "<Alt>5" },
                { "win.zoom-in", "<Control>plus" }, { "win.zoom-out", "<Control>minus" }, { "win.zoom-fit", "<Control>0" },
                { "win.toggle-sidebar", "F9" }, { "win.fullscreen", "F11" }, { "win.delete", "Delete" },
                { "win.tool::brush", "b" }, { "win.tool::eraser", "e" }, { "win.tool::select", "v" }, { "win.tool::fill", "g" }
            };
            for (int i = 0; i < accels.length[0]; i++) set_accels_for_action (accels[i, 0], { accels[i, 1] });
            set_accels_for_action ("win.redo", { "<Control><Shift>z", "<Control>y" });
            set_accels_for_action ("app.new::fashion", { "<Control>n" });
        }

        private static GLib.Menu section (string[,] items) {
            var m = new GLib.Menu ();
            for (int i = 0; i < items.length[0]; i++) m.append (items[i, 0], items[i, 1]);
            return m;
        }

        private static GLib.Menu submenu (string label, GLib.Menu sub) {
            var m = new GLib.Menu ();
            m.append_submenu (label, sub);
            return m;
        }

        private void build_menu () {
            var menu = new GLib.Menu ();
            var file = new GLib.Menu ();
            file.append_section (null, submenu (_("New"), section ({
                { _("Garment"), "app.new::fashion" }, { _("Leather Goods"), "app.new::leather" },
                { _("Product Concept"), "app.new::product" }, { _("Automotive Concept"), "app.new::automotive" }
            })));
            file.append_section (null, section ({ { _("Open…"), "app.open" }, { _("Open from Online Account…"), "win.open-online" } }));
            file.append_section (null, section ({ { _("Save"), "win.save" }, { _("Save As…"), "win.save-as" }, { _("Save to Online Account…"), "win.save-online" } }));
            file.append_section (null, submenu (_("Import"), section ({
                { _("DXF Pattern (AAMA or ASTM)…"), "win.import::dxf" }, { _("Seamly2D or Valentina Pattern…"), "win.import::seamly" },
                { _("Measurements (Seamly2D, CSV, XLSX)…"), "win.import::measurements" }, { _("Pattern from Photo…"), "win.import::photo" }, { _("Grade Rules (RUL)…"), "win.import::rul" },
                { _("Reference Image…"), "win.import::image" }, { _("OpenRaster Layers…"), "win.import::ora" }, { _("Photoshop Layers…"), "win.import::psd" },
                { _("SVG Drawing…"), "win.import::svg" }, { _("Colour Palette (GPL, ASE)…"), "win.import::palette" }, { _("3D Model (glTF, OBJ)…"), "win.import::mesh" }
            })));
            file.append_section (null, submenu (_("Export"), section ({
                { _("Tech Pack as PDF…"), "win.export-pdf" }, { _("Tech Pack as Text Document (ODT)…"), "win.export::odt" },
                { _("Tech Pack Tables as Spreadsheet (XLSX)…"), "win.export::xlsx" }, { _("Tech Pack Tables as OpenDocument Spreadsheet…"), "win.export::ods" },
                { _("Bill of Materials as CSV…"), "win.export::bom-csv" },
                { _("Pattern as DXF AAMA…"), "win.export::aama" }, { _("Pattern as DXF ASTM…"), "win.export::astm" },
                { _("Pattern for Seamly2D…"), "win.export::seamly" }, { _("Measurements for Seamly2D…"), "win.export::measurements" },
                { _("Pattern for Plotter (HPGL)…"), "win.export::hpgl" }, { _("Pattern as Large Format PDF…"), "win.export::pdf-large" },
                { _("Pattern as Tiled PDF…"), "win.export::pdf-tiled" }, { _("Pattern as SVG…"), "win.export::pattern-svg" },
                { _("Sketch as Image…"), "win.export::sketch-image" }, { _("Sketch as SVG…"), "win.export::sketch-svg" },
                { _("Sketch as PDF…"), "win.export::sketch-pdf" }, { _("Sketch as OpenRaster…"), "win.export::ora" },
                { _("Sketch Time-Lapse…"), "win.export::timelapse" },
                { _("Flats as SVG…"), "win.export::flats-svg" }, { _("Flats as PDF…"), "win.export::flats-pdf" }, { _("Flats as Image…"), "win.export::flats-image" },
                { _("Garment as glTF…"), "win.export::garment-gltf" }, { _("Garment as FBX…"), "win.export::garment-fbxbin" },
                { _("Product as glTF…"), "win.export::product-glb" }, { _("Product as STEP…"), "win.export::product-stp" }
            })));
            file.append_section (null, section ({ { _("Print…"), "win.print" } }));
            file.append_section (null, section ({ { _("Close Project"), "win.close-project" }, { _("Close Window"), "win.close" }, { _("Quit"), "app.quit" } }));
            menu.append_submenu (_("File"), file);
            var edit = new GLib.Menu ();
            edit.append_section (null, section ({ { _("Undo"), "win.undo" }, { _("Redo"), "win.redo" } }));
            edit.append_section (null, section ({ { _("Delete"), "win.delete" } }));
            edit.append_section (null, section ({ { _("Settings"), "app.settings" } }));
            menu.append_submenu (_("Edit"), edit);
            var view = new GLib.Menu ();
            view.append_section (null, section ({
                { _("Sketch"), "win.workspace::sketch" }, { _("Pattern"), "win.workspace::pattern" }, { _("Technical Drawing"), "win.workspace::flats" },
                { _("Tech Pack"), "win.workspace::techpack" }, { _("3D"), "win.workspace::3d" }
            }));
            view.append_section (null, section ({ { _("Side Panel"), "win.toggle-sidebar" }, { _("Full Screen"), "win.fullscreen" } }));
            view.append_section (null, section ({ { _("Zoom In"), "win.zoom-in" }, { _("Zoom Out"), "win.zoom-out" }, { _("Fit to Window"), "win.zoom-fit" } }));
            menu.append_submenu (_("View"), view);
            set_menubar (menu);
        }

        public override void activate () {
            var w = get_active_window () as AtelierWindow;
            if (w == null) {
                w = new AtelierWindow (this);
            }
            w.present ();
            if (new_trade != null) {
                w.new_project (new_trade);
                new_trade = null;
            }
            TestScript.maybe_run (w);
        }

        public override void open (File[] files, string hint) {
            foreach (var f in files) {
                var w = get_active_window () as AtelierWindow;
                if (w == null || w.project != null) w = new AtelierWindow (this);
                w.present ();
                w.open_file (f);
                TestScript.maybe_run (w);
            }
        }

        private const string CSS = """
.sx-tool-palette {
    background-color: @window_bg_color;
    color: @window_fg_color;
    border-radius: 14px;
    padding: 4px;
    box-shadow: 0 2px 10px alpha(black, 0.18), 0 0 0 1px alpha(@window_fg_color, 0.08);
}

.sx-tool {
    min-width: 32px;
    min-height: 32px;
    padding: 0;
    border-radius: 10px;
}

.sx-tool:checked {
    background-color: @accent_bg_color;
    color: @accent_fg_color;
}

.sx-control-strip {
    min-height: 36px;
}

.sx-control-strip-bar {
    background-color: @window_bg_color;
    border-top: 1px solid alpha(@window_fg_color, 0.08);
}

.sx-inspector .preferences-group {
    margin-bottom: 12px;
}

.sx-layer-list {
    padding-bottom: 2px;
}

.sx-layer-rows {
    background-color: transparent;
}

.sx-layer-row {
    border-radius: 8px;
    margin: 0 4px;
}

.sx-layer-row:selected {
    background-color: alpha(@accent_bg_color, 0.15);
    color: @window_fg_color;
}

.sx-layer-row:selected label {
    color: @window_fg_color;
}

.sx-layer-toggle {
    min-width: 26px;
    min-height: 26px;
    padding: 0;
    border-radius: 8px;
}

.sx-layer-toggle:checked {
    background-color: alpha(@window_fg_color, 0.1);
}

.sx-layer-name {
    font-weight: 500;
}

.atelier-swatch {
    min-width: 26px;
    min-height: 26px;
    padding: 0;
    border-radius: 13px;
    border: 1px solid alpha(@window_fg_color, 0.2);
}

.atelier-value {
    font-feature-settings: "tnum";
}

.atelier-error {
    color: @error_color;
}

.atelier-formula-error .subtitle {
    color: @error_color;
}

.atelier-notes {
    background-color: transparent;
    min-height: 96px;
}

.atelier-notes text {
    background-color: transparent;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-atelier", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-atelier", "UTF-8");
        Intl.textdomain ("singularity-atelier");
        return new AtelierApp ().run (args);
    }
}
