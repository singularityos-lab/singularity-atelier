using Gtk;
using Singularity.Widgets;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class AtelierWindow : Singularity.Widgets.Window {
        public Project? project { get; private set; }
        public History? history;
        public AtelierApp app;
        public string workspace { get; private set; default = "sketch"; }
        private Stack content_stack;
        private Stack work_stack;
        private Stack side_stack;
        private AppSidebar sidebar;
        private BubbleSwitcher ws_switch;
        private PatternRibbon pattern_ribbon;
        private SidebarTabs mode3d_switch;
        private Gee.ArrayList<Widget> doc_bubbles = new Gee.ArrayList<Widget> ();
        private PreferencesGroup recent_group;
        private Box recent_wrap;
        private WelcomePage welcome_page;
        public SketchCanvas? sketch_canvas;
        public SketchPanel? sketch_panel;
        public PatternCanvas? pattern_canvas;
        public PatternPanel? pattern_panel;
        public FlatsCanvas? flats_canvas;
        public FlatsPanel? flats_panel;
        public TechPackView? techpack_view;
        public View3D? view3d;
        public GarmentPanel? garment_panel;
        public ProductPanel? product_panel;
        private Stack? panel3d_stack;
        private bool close_confirmed;
        private bool pattern_dirty;

        public AtelierWindow (AtelierApp app) {
            Object (application: app);
            this.app = app;
            set_default_size (1360, 860);
            set_title (_("Atelier"));
            content_stack = new Stack ();
            content_stack.transition_type = StackTransitionType.CROSSFADE;
            content_stack.add_named (build_welcome (), "welcome");
            work_stack = new Stack ();
            work_stack.transition_type = StackTransitionType.CROSSFADE;
            work_stack.hexpand = true;
            work_stack.vexpand = true;
            content_stack.add_named (work_stack, "work");
            set_content (content_stack);
            sidebar = new AppSidebar (310);
            side_stack = new Stack ();
            side_stack.transition_type = StackTransitionType.CROSSFADE;
            side_stack.vhomogeneous = false;
            side_stack.hhomogeneous = true;
            sidebar.box.append (side_stack);
            set_sidebar (sidebar);
            set_sidebar_visible (false);
            build_bubbles ();
            install_actions ();
            close_request.connect (on_close_request);
            var drop = new DropTarget (typeof (Gdk.FileList), Gdk.DragAction.COPY);
            drop.drop.connect ((value, x, y) => {
                var list = (Gdk.FileList) value.get_boxed ();
                foreach (var f in list.get_files ()) open_file (f);
                return true;
            });
            ((Widget) this).add_controller (drop);
            show_welcome ();
        }

        private Widget build_welcome () {
            var wp = new WelcomePage ();
            welcome_page = wp;
            wp.app_icon_name = "dev.sinty.atelier";
            wp.title = _("Atelier");
            wp.subtitle = _("Sketch, make patterns, grade sizes and prepare tech packs");
            wp.add_action ("atelier-new-garment", _("New Garment"), _("Sketch, pattern with sizes, flats, tech pack and 3D fitting"), () => new_project ("fashion"));
            wp.add_action ("atelier-new-leather", _("New Leather Goods"), _("Bags and small leather goods with thickness, turn allowances and developed pieces"), () => new_project ("leather"));
            wp.add_action ("atelier-new-product", _("New Product Concept"), _("Concept sketches, perspective grids and subdivision models"), () => new_project ("product"));
            wp.add_action ("atelier-new-automotive", _("New Automotive Concept"), _("Side view templates with proportions, tape drawing and sketching"), () => new_project ("automotive"));
            wp.add_action ("folder-open", _("Open"), _("Atelier projects, DXF AAMA and ASTM, Seamly2D and Valentina"), () => choose_open ());
            recent_wrap = new Box (Orientation.VERTICAL, 0);
            recent_group = new PreferencesGroup (_("Recent"));
            recent_wrap.append (recent_group);
            apply_view_edge (recent_wrap);
            wp.set_extra_widget (recent_wrap);
            return wp;
        }

        private void fill_recent () {
            recent_group.clear ();
            var items = new Gee.ArrayList<RecentInfo> ();
            foreach (var info in RecentManager.get_default ().get_items ()) {
                string u = info.get_uri ().down ();
                if ((u.has_suffix (".atelier") || u.has_suffix (".dxf") || u.has_suffix (".sm2d") || u.has_suffix (".val")) && info.exists ()) items.add (info);
            }
            items.sort ((a, b) => b.get_modified ().compare (a.get_modified ()));
            int count = 0;
            foreach (var info in items) {
                if (count++ >= 6) break;
                var file = File.new_for_uri (info.get_uri ());
                var parent = file.get_parent ();
                string p = parent != null ? (parent.get_path () ?? "") : "";
                string home = Environment.get_home_dir ();
                if (p.has_prefix (home)) p = "~" + p.substring (home.length);
                var row = new ActionRow (file.get_basename (), p, "dev.sinty.atelier");
                row.activatable = true;
                row.activated.connect (() => open_file (file));
                recent_group.add_row (row);
            }
            recent_wrap.visible = count > 0;
            welcome_page.set_extra_widget (count > 0 ? recent_wrap : null);
        }

        private void show_welcome () {
            fill_recent ();
            content_stack.visible_child_name = "welcome";
            foreach (var b in doc_bubbles) b.visible = false;
            pattern_ribbon.tabs.visible = false;
            mode3d_switch.visible = false;
            set_sidebar_visible (false);
            set_title (_("Atelier"));
        }

        private Widget track (Widget w) {
            doc_bubbles.add (w);
            return w;
        }

        private void popup_at (ContextMenu menu, Widget bubble) {
            Graphene.Rect bounds;
            if (bubble.compute_bounds (content_stack, out bounds)) {
                var rect = Gdk.Rectangle ();
                rect.x = (int) bounds.origin.x;
                rect.y = (int) bounds.origin.y;
                rect.width = (int) bounds.size.width;
                rect.height = (int) bounds.size.height;
                menu.pointing_to = rect;
            }
            menu.position = PositionType.BOTTOM;
            menu.closed.connect (() => Idle.add (() => {
                menu.unparent ();
                return Source.REMOVE;
            }));
            menu.popup ();
        }

        private void run (string action, Variant? param = null) {
            activate_action (action, param);
        }

        private void build_bubbles () {
            track (add_bubble_icon ("go-previous-symbolic", _("Close Project (Ctrl+W)"), () => run ("close-project")));
            track (add_bubble_icon ("sidebar-show-symbolic", _("Side Panel (F9)"), () => set_sidebar_visible (!get_sidebar_visible ())));
            var save = add_bubble_icon ("document-save-symbolic", _("Save and Export"), () => { });
            save.clicked.connect (() => {
                var m = new ContextMenu (content_stack);
                m.add_item (_("Save"), "document-save-symbolic", () => run ("save"));
                m.add_item (_("Save As"), "document-save-as-symbolic", () => run ("save-as"));
                m.add_item (_("Save to Online Account"), "folder-remote-symbolic", () => run ("save-online"));
                m.add_separator ();
                var t = export_table ();
                for (int i = 0; i < t.length[0]; i++) {
                    if (!(t[i, 3] == workspace || (workspace == "3d" && t[i, 3] == "3d-" + mode_3d))) continue;
                    string id = t[i, 0];
                    m.add_item (t[i, 1], t[i, 2], () => run ("export", new Variant.string (id)));
                }
                foreach (var ex in PluginHost.get_default ().exporters) {
                    string pid = "plugin:" + ex.id;
                    m.add_item (ex.title, "application-x-addon-symbolic", () => run ("export", new Variant.string (pid)));
                }
                popup_at (m, save);
            });
            track (save);
            track (add_bubble_icon ("edit-undo-symbolic", _("Undo (Ctrl+Z)"), () => run ("undo")));
            track (add_bubble_icon ("edit-redo-symbolic", _("Redo (Ctrl+Shift+Z)"), () => run ("redo")));
            ws_switch = new BubbleSwitcher ();
            ws_switch.add_option ("sketch", _("Sketch"));
            ws_switch.add_option ("pattern", _("Pattern"));
            ws_switch.add_option ("flats", _("Flats"));
            ws_switch.add_option ("techpack", _("Tech Pack"));
            ws_switch.add_option ("3d", _("3D"));
            ws_switch.selected.connect ((name) => show_workspace (name));
            add_bubble_widget (ws_switch);
            track (ws_switch);
            pattern_ribbon = new PatternRibbon (this);
            pattern_ribbon.context_changed.connect ((n) => {
                if (pattern_canvas != null && pattern_canvas.mode != n) pattern_canvas.switch_mode (n);
            });
            pattern_ribbon.attach (this);
            pattern_ribbon.tabs.visible = false;
            mode3d_switch = new SidebarTabs ();
            mode3d_switch.add_option ("garment", _("Garment"));
            mode3d_switch.add_option ("product", _("Product"));
            mode3d_switch.tooltip_text = _("3D Mode");
            mode3d_switch.selected.connect ((n) => show_3d_mode (n));
            sidebar.prepend (mode3d_switch);
            mode3d_switch.visible = false;
            track (add_bubble_icon ("document-print-symbolic", _("Print (Ctrl+P)"), () => run ("print")));
        }

        private string[,] export_table () {
            return {
                { "sketch-image", _("Export Sketch as Image"), "image-x-generic-symbolic", "sketch" },
                { "sketch-svg", _("Export Sketch as SVG"), "image-x-generic-symbolic", "sketch" },
                { "sketch-pdf", _("Export Sketch as PDF"), "x-office-document-symbolic", "sketch" },
                { "ora", _("Export Sketch as OpenRaster"), "image-x-generic-symbolic", "sketch" },
                { "timelapse", _("Export Time-Lapse"), "video-x-generic-symbolic", "sketch" },
                { "aama", _("Export DXF AAMA"), "x-office-drawing-symbolic", "pattern" },
                { "astm", _("Export DXF ASTM and Grade Rules"), "x-office-drawing-symbolic", "pattern" },
                { "seamly", _("Export for Seamly2D"), "x-office-drawing-symbolic", "pattern" },
                { "measurements", _("Export Measurements"), "x-office-spreadsheet-symbolic", "pattern" },
                { "hpgl", _("Export for Plotter (HPGL)"), "printer-symbolic", "pattern" },
                { "pdf-large", _("Export Large Format PDF"), "x-office-document-symbolic", "pattern" },
                { "pdf-tiled", _("Export Tiled PDF"), "x-office-document-symbolic", "pattern" },
                { "pattern-svg", _("Export Pattern as SVG"), "image-x-generic-symbolic", "pattern" },
                { "flats-svg", _("Export Flats as SVG"), "image-x-generic-symbolic", "flats" },
                { "flats-pdf", _("Export Flats as PDF"), "x-office-document-symbolic", "flats" },
                { "flats-image", _("Export Flats as Image"), "image-x-generic-symbolic", "flats" },
                { "techpack-pdf", _("Export Tech Pack as PDF"), "x-office-document-symbolic", "techpack" },
                { "odt", _("Export Tech Pack for Write (ODT)"), "x-office-document-symbolic", "techpack" },
                { "xlsx", _("Export Tables as Spreadsheet (XLSX)"), "x-office-spreadsheet-symbolic", "techpack" },
                { "ods", _("Export Tables as OpenDocument Spreadsheet"), "x-office-spreadsheet-symbolic", "techpack" },
                { "bom-csv", _("Export Bill of Materials as CSV"), "x-office-spreadsheet-symbolic", "techpack" },
                { "garment-gltf", _("Export Garment as glTF Scene"), "x-office-drawing-symbolic", "3d-garment" },
                { "garment-glb", _("Export Garment as Binary glTF"), "x-office-drawing-symbolic", "3d-garment" },
                { "garment-obj", _("Export Garment as OBJ"), "x-office-drawing-symbolic", "3d-garment" },
                { "garment-fbx", _("Export Garment as FBX"), "x-office-drawing-symbolic", "3d-garment" },
                { "garment-fbxbin", _("Export Garment as Binary FBX"), "x-office-drawing-symbolic", "3d-garment" },
                { "garment-png", _("Export Render as Image"), "image-x-generic-symbolic", "3d-garment" },
                { "garment-turntable", _("Export Turntable Frames"), "image-x-generic-symbolic", "3d-garment" },
                { "product-glb", _("Export Product as Binary glTF"), "x-office-drawing-symbolic", "3d-product" },
                { "product-gltf", _("Export Product as glTF Scene"), "x-office-drawing-symbolic", "3d-product" },
                { "product-obj", _("Export Product as OBJ"), "x-office-drawing-symbolic", "3d-product" },
                { "product-fbx", _("Export Product as FBX"), "x-office-drawing-symbolic", "3d-product" },
                { "product-fbxbin", _("Export Product as Binary FBX"), "x-office-drawing-symbolic", "3d-product" },
                { "product-stp", _("Export Product as STEP"), "x-office-drawing-symbolic", "3d-product" }
            };
        }

        public bool is_empty () {
            return project == null;
        }

        public void new_project (string trade) {
            var p = Project.create (trade);
            load_project (p);
            show_workspace (trade == "product" || trade == "automotive" ? "sketch" : "pattern");
            if (trade == "automotive" && sketch_canvas != null) {
                Idle.add (() => {
                    sketch_canvas.add_vehicle_underlay ("sedan");
                    history.clear ();
                    project.modified = false;
                    return Source.REMOVE;
                });
            }
        }

        public void load_project (Project p) {
            project = p;
            history = new History (p);
            history.restored.connect_after (() => refresh_all ());
            p.changed.connect ((what) => {
                update_title ();
                if (what == "pattern" || what == "measurements") {
                    pattern_dirty = true;
                    if (workspace == "3d" && garment_panel != null) {
                        pattern_dirty = false;
                        garment_panel.sync_pattern ();
                    }
                }
            });
            build_workspaces ();
            content_stack.visible_child_name = "work";
            foreach (var b in doc_bubbles) b.visible = true;
            set_sidebar_visible (true);
            show_workspace (workspace);
            update_title ();
        }

        private void build_workspaces () {
            Widget? c;
            while ((c = work_stack.get_first_child ()) != null) work_stack.remove (c);
            while ((c = side_stack.get_first_child ()) != null) side_stack.remove (c);
            sketch_canvas = new SketchCanvas (project, history);
            sketch_canvas.stabilizer = app.get_int ("stabilizer", 35) / 100.0;
            sketch_canvas.hold_to_shape = app.get_bool ("hold-to-shape", true);
            sketch_canvas.hold_delay = app.get_int ("hold-delay", 600);
            sketch_canvas.predictive = app.get_bool ("predictive-stroke", false);
            sketch_canvas.touch_drawing = app.get_bool ("touch-draws", false);
            project.sketch.record_timelapse = app.get_bool ("record-timelapse", true);
            sketch_canvas.bucket_failed.connect (() => add_toast (new Toast (_("Click inside a closed area to fill it"))));
            sketch_canvas.layer_needed.connect (() => add_toast (new Toast (_("Choose an unlocked drawing layer first"))));
            sketch_panel = new SketchPanel (this, sketch_canvas);
            work_stack.add_named (with_palette (sketch_canvas, sketch_panel.palette), "sketch");
            side_stack.add_named (sketch_panel, "sketch");
            pattern_canvas = new PatternCanvas (project, history);
            pattern_panel = new PatternPanel (this, pattern_canvas);
            var ribbon_parent = pattern_ribbon.get_parent () as Box;
            if (ribbon_parent != null) ribbon_parent.remove (pattern_ribbon);
            work_stack.add_named (with_palette (pattern_canvas, pattern_panel.palette, pattern_ribbon), "pattern");
            side_stack.add_named (pattern_panel, "pattern");
            string start_mode = pattern_ribbon.active_context ?? "draft";
            if (start_mode != pattern_canvas.mode) pattern_canvas.switch_mode (start_mode);
            pattern_ribbon.sync ();
            pattern_panel.refreshed.connect (() => pattern_ribbon.sync ());
            pattern_canvas.notify["mode"].connect (() => {
                string n = pattern_canvas.mode;
                if (pattern_ribbon.active_context != n && n != "walk") pattern_ribbon.active_context = n;
            });
            flats_canvas = new FlatsCanvas (project, history);
            flats_panel = new FlatsPanel (project, history, flats_canvas);
            flats_panel.message.connect ((m) => add_toast (new Toast (m)));
            work_stack.add_named (with_palette (flats_canvas, flats_panel.palette), "flats");
            side_stack.add_named (flats_panel, "flats");
            techpack_view = new TechPackView (project, history);
            techpack_view.message.connect ((m) => add_toast (new Toast (m)));
            work_stack.add_named (techpack_view, "techpack");
            side_stack.add_named (techpack_view.nav, "techpack");
            view3d = new View3D ();
            work_stack.add_named (view3d, "3d");
            var box3d = new Box (Orientation.VERTICAL, 0);
            panel3d_stack = new Stack ();
            panel3d_stack.vhomogeneous = false;
            garment_panel = new GarmentPanel (project, view3d);
            garment_panel.message.connect ((m) => add_toast (new Toast (m)));
            product_panel = new ProductPanel (project, history, view3d);
            product_panel.message.connect ((m) => add_toast (new Toast (m)));
            panel3d_stack.add_named (garment_panel, "garment");
            panel3d_stack.add_named (product_panel, "product");
            box3d.append (panel3d_stack);
            string start3d = project.trade == "product" || project.trade == "automotive" ? "product" : "garment";
            mode3d_switch.set_active (start3d);
            panel3d_stack.visible_child_name = start3d;
            side_stack.add_named (box3d, "3d");
            Idle.add (() => {
                sketch_canvas.fit_all ();
                pattern_canvas.fit_all ();
                flats_canvas.fit_all ();
                return Source.REMOVE;
            });
        }

        private Widget with_palette (ZoomCanvas canvas, Widget palette, ContextRibbon? ribbon = null) {
            var overlay = new Overlay ();
            overlay.child = canvas;
            overlay.hexpand = true;
            overlay.vexpand = true;
            overlay.add_overlay (palette);
            var box = new Box (Orientation.VERTICAL, 0);
            if (ribbon != null) {
                apply_view_edge (box);
                box.append (ribbon);
            }
            box.append (overlay);
            var strip = new ControlStrip (4, 4);
            var bar = new Box (Orientation.VERTICAL, 0);
            bar.add_css_class ("sx-control-strip-bar");
            bar.append (strip);
            var status = strip.add_status_label ();
            var out_btn = strip.add_icon_button ("zoom-out-symbolic", _("Zoom Out (Ctrl+Minus)"));
            out_btn.clicked.connect (() => canvas.zoom_out ());
            var zoom = strip.add_numeric_label ();
            zoom.width_chars = 5;
            var in_btn = strip.add_icon_button ("zoom-in-symbolic", _("Zoom In (Ctrl+Plus)"));
            in_btn.clicked.connect (() => canvas.zoom_in ());
            var fit = strip.add_text_button (_("Fit"), _("Fit to Window (Ctrl+0)"));
            fit.clicked.connect (() => activate_action ("zoom-fit", null));
            canvas.drawn.connect (() => {
                string t = canvas.status_text ();
                if (status.label != t) status.label = t;
                string z = "%d%%".printf ((int) Math.round (canvas.zoom * 100));
                if (zoom.label != z) zoom.label = z;
            });
            box.append (bar);
            return box;
        }

        public void show_3d_mode (string n) {
            if (panel3d_stack == null || project == null) return;
            if (mode3d_switch.active_option != n) mode3d_switch.set_active (n);
            if (panel3d_stack.visible_child_name == n) return;
            panel3d_stack.visible_child_name = n;
            if (n == "garment") garment_panel.refresh ();
            else product_panel.refresh ();
            view3d.reset_camera ();
        }

        public string mode_3d {
            get { return panel3d_stack != null ? panel3d_stack.visible_child_name : "garment"; }
        }

        public void refresh_all () {
            if (project == null) return;
            sketch_canvas.reset_project (project);
            sketch_panel.refresh ();
            pattern_canvas.reset_project (project);
            pattern_panel.refresh ();
            flats_canvas.reset_project (project);
            flats_panel.refresh ();
            techpack_view.refresh ();
            if (workspace == "3d" && panel3d_stack.visible_child_name == "product") product_panel.refresh ();
            update_title ();
        }

        public void show_workspace (string name) {
            workspace = name;
            if (project == null) return;
            work_stack.visible_child_name = name;
            side_stack.visible_child_name = name;
            if (ws_switch.active_option != name) ws_switch.set_active (name);
            pattern_ribbon.tabs.visible = name == "pattern";
            mode3d_switch.visible = name == "3d";
            if (name == "techpack") techpack_view.refresh ();
            if (name == "pattern") pattern_panel.refresh ();
            if (name == "3d") {
                if (panel3d_stack.visible_child_name == "garment") {
                    garment_panel.refresh ();
                    if (pattern_dirty) {
                        pattern_dirty = false;
                        garment_panel.sync_pattern ();
                    }
                } else {
                    product_panel.refresh ();
                }
            }
            var a = lookup_action ("workspace") as SimpleAction;
            if (a != null) a.set_state (new Variant.string (name));
        }

        private void update_title () {
            if (project == null) return;
            set_title (project.title != "" ? project.title : _("Untitled"));
        }

        public void show_error (string title, string message) {
            var dlg = new ConfirmDialog.message (app, title, "dialog-warning", message);
            dlg.transient_for = this;
            dlg.present ();
        }

        public void choose_open () {
            Dialogs.open.begin (this, _("Open"), _("Atelier and pattern files"), { "atelier", "dxf", "sm2d", "val" }, (o, r) => {
                var f = Dialogs.open.end (r);
                if (f != null) open_file (f);
            });
        }

        public void open_file (File file) {
            string? path = file.get_path ();
            if (path == null) return;
            string lower = path.down ();
            try {
                Project p;
                if (lower.has_suffix (".dxf")) {
                    string text;
                    FileUtils.get_contents (path, out text);
                    p = new Project ();
                    p.pattern.points.clear ();
                    Aama.import_into (text, p, true);
                    p.title = NativeFormat.title_from_path (path);
                    p.flats.add_all (Flats.build ("tshirt"));
                    p.techpack = TechPack.sample ();
                    p.modified = false;
                    load_project (p);
                    show_workspace ("pattern");
                } else if (lower.has_suffix (".sm2d") || lower.has_suffix (".val")) {
                    p = new Project ();
                    load_seamly (p, path);
                    p.title = NativeFormat.title_from_path (path);
                    p.modified = false;
                    load_project (p);
                    show_workspace ("pattern");
                } else {
                    p = NativeFormat.load (path);
                    load_project (p);
                }
                RecentManager.get_default ().add_item (file.get_uri ());
            } catch (Error e) {
                show_error (_("Could Not Open"), _("\"%s\" could not be opened: %s").printf (file.get_basename (), e.message));
            }
        }

        private void load_seamly (Project p, string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            SeamlyReport rep;
            var pat = Seamly.read_pattern (text, out rep);
            if (rep.measurements_file != "") {
                string mp = Path.is_absolute (rep.measurements_file) ? rep.measurements_file : Path.build_filename (Path.get_dirname (path), rep.measurements_file);
                if (FileUtils.test (mp, FileTest.EXISTS)) {
                    string mt;
                    FileUtils.get_contents (mp, out mt);
                    var table = Seamly.read_measurements (mt);
                    pat = Seamly.read_pattern (text, out rep, table);
                }
            }
            p.pattern = pat;
            p.flats.add_all (Flats.build ("shirt"));
            p.techpack = TechPack.sample ();
            if (rep.skipped.size > 0) add_toast (new Toast (_("Some Seamly2D tools are not supported yet and were skipped: %s").printf (string.joinv (", ", rep.skipped.to_array ()))));
        }

        private void write_project (string path) throws Error {
            NativeFormat.save_to (project, path);
            project.path = path;
            project.title = NativeFormat.title_from_path (path);
            project.modified = false;
            update_title ();
            RecentManager.get_default ().add_item (File.new_for_path (path).get_uri ());
        }

        public void save (bool as_new) {
            if (project == null) return;
            if (!as_new && project.path != null && project.path.down ().has_suffix (".atelier")) {
                try {
                    write_project (project.path);
                    CloudActions.sync_back (this, File.new_for_path (project.path));
                } catch (Error e) {
                    show_error (_("Could Not Save"), e.message);
                }
                return;
            }
            Dialogs.save.begin (this, _("Save Project"), (project.title != "" ? project.title : _("Untitled")) + ".atelier", _("Atelier projects"), { "atelier" }, (o, r) => {
                var f = Dialogs.save.end (r);
                if (f == null) return;
                try {
                    write_project (Dialogs.ensure_suffix (f.get_path (), "atelier"));
                } catch (Error e) {
                    show_error (_("Could Not Save"), e.message);
                }
            });
        }

        public void write_to (string path) throws Error {
            write_project (path);
        }

        private bool on_close_request () {
            if (close_confirmed || project == null || !project.modified) return false;
            Dialogs.confirm (this, _("Save Changes?"), _("The project has unsaved changes that will be lost."), _("Close Without Saving"), () => {
                close_confirmed = true;
                close ();
            });
            return true;
        }

        public void close_project () {
            if (project == null) return;
            if (project.modified) {
                Dialogs.confirm (this, _("Close Without Saving?"), _("The project has unsaved changes that will be lost."), _("Close"), () => {
                    project = null;
                    show_welcome ();
                });
                return;
            }
            project = null;
            show_welcome ();
        }

        private void install_actions () {
            var a = new SimpleAction ("save", null);
            a.activate.connect (() => save (false));
            add_action (a);
            a = new SimpleAction ("save-as", null);
            a.activate.connect (() => save (true));
            add_action (a);
            a = new SimpleAction ("save-online", null);
            a.activate.connect (() => CloudActions.save_project (this));
            add_action (a);
            a = new SimpleAction ("open-online", null);
            a.activate.connect (() => CloudActions.open.begin (this, (f) => open_file (f)));
            add_action (a);
            a = new SimpleAction ("close-project", null);
            a.activate.connect (() => close_project ());
            add_action (a);
            a = new SimpleAction ("undo", null);
            a.activate.connect (() => {
                if (history != null) history.undo ();
            });
            add_action (a);
            a = new SimpleAction ("redo", null);
            a.activate.connect (() => {
                if (history != null) history.redo ();
            });
            add_action (a);
            a = new SimpleAction ("delete", null);
            a.activate.connect (() => {
                if (project == null) return;
                if (workspace == "sketch") sketch_canvas.delete_selection ();
                else if (workspace == "pattern") pattern_canvas.delete_selection ();
                else if (workspace == "flats") flats_canvas.delete_selection ();
            });
            add_action (a);
            var ws = new SimpleAction.stateful ("workspace", VariantType.STRING, new Variant.string ("sketch"));
            ws.activate.connect ((v) => show_workspace (v.get_string ()));
            add_action (ws);
            var tool = new SimpleAction ("tool", VariantType.STRING);
            tool.activate.connect ((v) => {
                if (project == null || workspace != "sketch") return;
                sketch_canvas.tool = v.get_string ();
                sketch_panel.sync_tool ();
            });
            add_action (tool);
            a = new SimpleAction ("zoom-in", null);
            a.activate.connect (() => {
                var c = current_canvas ();
                if (c != null) c.zoom_in ();
            });
            add_action (a);
            a = new SimpleAction ("zoom-out", null);
            a.activate.connect (() => {
                var c = current_canvas ();
                if (c != null) c.zoom_out ();
            });
            add_action (a);
            a = new SimpleAction ("zoom-fit", null);
            a.activate.connect (() => {
                if (workspace == "sketch") sketch_canvas.fit_all ();
                else if (workspace == "pattern") pattern_canvas.fit_all ();
                else if (workspace == "flats") flats_canvas.fit_all ();
                else if (workspace == "3d") view3d.reset_camera ();
            });
            add_action (a);
            a = new SimpleAction ("fullscreen", null);
            a.activate.connect (() => {
                if (fullscreened) unfullscreen ();
                else fullscreen ();
            });
            add_action (a);
            a = new SimpleAction ("toggle-sidebar", null);
            a.activate.connect (() => set_sidebar_visible (!get_sidebar_visible ()));
            add_action (a);
            a = new SimpleAction ("print", null);
            a.activate.connect (() => print_current.begin ());
            add_action (a);
            a = new SimpleAction ("export-pdf", null);
            a.activate.connect (() => export ("techpack-pdf"));
            add_action (a);
            a = new SimpleAction ("export", VariantType.STRING);
            a.activate.connect ((v) => export (v.get_string ()));
            add_action (a);
            a = new SimpleAction ("import", VariantType.STRING);
            a.activate.connect ((v) => import (v.get_string ()));
            add_action (a);
        }

        private ZoomCanvas? current_canvas () {
            if (project == null) return null;
            switch (workspace) {
                case "sketch": return sketch_canvas;
                case "pattern": return pattern_canvas;
                case "flats": return flats_canvas;
            }
            return null;
        }

        public async void print_current () {
            if (project == null) return;
            Singularity.Print.PageSource src;
            switch (workspace) {
                case "sketch":
                    src = new SketchPrintSource (project.sketch, project.title);
                    break;
                case "pattern":
                    src = new PatternPrintSource (project.pattern, project.title, app.get_int ("print-overlap", 10));
                    break;
                case "flats":
                    src = new FlatsPrintSource (project, project.title);
                    break;
                default:
                    src = new TechPackPrintSource (project);
                    break;
            }
            yield Singularity.Print.run_source (this, src);
        }

        private string base_name () {
            return project.title != "" ? project.title : _("Untitled");
        }

        private void save_as (string title, string ext, string filter, owned SaveFunc writer) {
            Dialogs.save.begin (this, title, base_name () + "." + ext, filter, { ext }, (o, r) => {
                var f = Dialogs.save.end (r);
                if (f == null) return;
                string path = Dialogs.ensure_suffix (f.get_path (), ext);
                try {
                    writer (path);
                    add_toast (new Toast (_("Exported %s").printf (Path.get_basename (path))));
                } catch (Error e) {
                    show_error (_("Could Not Export"), e.message);
                }
            });
        }

        public delegate void SaveFunc (string path) throws Error;

        public void export (string what) {
            if (project == null) return;
            var p = project;
            if (what.has_prefix ("garment-")) {
                garment_panel.export_as (what.substring (8));
                return;
            }
            if (what.has_prefix ("product-")) {
                product_panel.export_as (what.substring (8));
                return;
            }
            if (what.has_prefix ("plugin:")) {
                var ex = PluginHost.get_default ().find_exporter (what.substring (7));
                if (ex == null) return;
                save_as (ex.title, ex.suffix, ex.title, (path) => FileUtils.set_data (path, ex.export (NativeFormat.to_json (p))));
                return;
            }
            switch (what) {
                case "sketch-image":
                    Dialogs.save.begin (this, _("Export Sketch as Image"), base_name () + ".png", _("Images"), { "png", "jpg", "jpeg", "tif", "tiff", "webp" }, (o, r) => {
                        var f = Dialogs.save.end (r);
                        if (f == null) return;
                        string path = f.get_path ();
                        if (!path.contains (".")) path += ".png";
                        try {
                            Rect area;
                            Export.save_raster (SketchRenderer.render_image (p.sketch, 3, out area), path);
                            add_toast (new Toast (_("Exported %s").printf (Path.get_basename (path))));
                        } catch (Error e) {
                            show_error (_("Could Not Export"), e.message);
                        }
                    });
                    break;
                case "sketch-svg":
                    save_as (_("Export Sketch as SVG"), "svg", _("SVG drawings"), (path) => Export.write_text (path, SvgExport.sketch (p.sketch)));
                    break;
                case "sketch-pdf":
                    save_as (_("Export Sketch as PDF"), "pdf", _("PDF documents"), (path) => Export.sketch_pdf (p.sketch, path));
                    break;
                case "ora":
                    save_as (_("Export Sketch as OpenRaster"), "ora", _("OpenRaster images"), (path) => FileUtils.set_data (path, OraFormat.export (p.sketch)));
                    break;
                case "timelapse":
                    Dialogs.folder.begin (this, _("Choose a Folder for the Time-Lapse"), (o, r) => {
                        var f = Dialogs.folder.end (r);
                        if (f == null) return;
                        Timelapse.export.begin (p.sketch, f.get_path (), this, (oo, rr) => {
                            try {
                                string result = Timelapse.export.end (rr);
                                add_toast (new Toast (_("Time-lapse saved as %s").printf (Path.get_basename (result))));
                            } catch (Error e) {
                                show_error (_("Could Not Export"), e.message);
                            }
                        });
                    });
                    break;
                case "aama":
                case "astm": {
                    bool astm = what == "astm";
                    save_as (astm ? _("Export DXF ASTM") : _("Export DXF AAMA"), "dxf", _("DXF patterns"), (path) => {
                        var o = new AamaExportOptions ();
                        o.flavor = astm ? DxfFlavor.ASTM : DxfFlavor.AAMA;
                        o.style = p.techpack.style_number != "" ? p.techpack.style_number : base_name ();
                        o.metric = p.pattern.unit != "inch";
                        Export.write_text (path, Aama.export (p.pattern, o));
                        if (astm) {
                            if (p.pattern.rules.rules.size == 0) Grading.derive_rules (p.pattern, Grading.nest_by_measurements (p.pattern));
                            Export.write_text (path.substring (0, path.length - 4) + ".rul", Aama.export_rules (p.pattern, o.metric));
                        }
                    });
                    break;
                }
                case "seamly":
                    save_as (_("Export for Seamly2D"), "sm2d", _("Seamly2D patterns"), (path) => {
                        string mname = Path.get_basename (path).replace (".sm2d", p.pattern.table.kind == TableKind.INDIVIDUAL ? ".smis" : ".smms");
                        Export.write_text (Path.build_filename (Path.get_dirname (path), mname), Seamly.write_measurements (p.pattern.table));
                        Export.write_text (path, Seamly.write_pattern (p.pattern, mname));
                    });
                    break;
                case "measurements":
                    save_as (_("Export Measurements"), p.pattern.table.kind == TableKind.INDIVIDUAL ? "smis" : "smms", _("Seamly2D measurements"), (path) => Export.write_text (path, Seamly.write_measurements (p.pattern.table)));
                    break;
                case "hpgl":
                    save_as (_("Export for Plotter"), "plt", _("HPGL plot files"), (path) => {
                        var o = new Hpgl.Options ();
                        o.paper_width_mm = app.get_int ("plotter-width", 91) * 10;
                        Export.write_text (path, Hpgl.export (p.pattern.evaluate (), o));
                    });
                    break;
                case "pdf-large":
                    save_as (_("Export Large Format PDF"), "pdf", _("PDF documents"), (path) => PatternPrint.write_large_pdf (p.pattern.evaluate (), path, true));
                    break;
                case "pdf-tiled":
                    save_as (_("Export Tiled PDF"), "pdf", _("PDF documents"), (path) => PatternPrint.write_tiled_pdf (p.pattern.evaluate (), path, true, 595.28, 841.89, 28, app.get_int ("print-overlap", 10)));
                    break;
                case "pattern-svg":
                    save_as (_("Export Pattern as SVG"), "svg", _("SVG drawings"), (path) => Export.write_text (path, SvgExport.pattern (p.pattern, p.pattern.evaluate ())));
                    break;
                case "flats-svg":
                    save_as (_("Export Flats as SVG"), "svg", _("SVG drawings"), (path) => {
                        var sheet = flats_canvas.sheet ?? (p.flats.size > 0 ? p.flats[0] : null);
                        if (sheet == null) throw new FormatError.INVALID (_("There is no technical drawing"));
                        Export.write_text (path, SvgExport.flat_sheet (sheet, p.colorway ()));
                    });
                    break;
                case "flats-pdf":
                    save_as (_("Export Flats as PDF"), "pdf", _("PDF documents"), (path) => Export.flats_pdf (p, path));
                    break;
                case "flats-image":
                    save_as (_("Export Flats as Image"), "png", _("PNG images"), (path) => {
                        var sheet = flats_canvas.sheet ?? (p.flats.size > 0 ? p.flats[0] : null);
                        if (sheet == null) throw new FormatError.INVALID (_("There is no technical drawing"));
                        Export.save_raster (FlatRenderer.render_sheet (sheet, p.colorway (), 2400), path);
                    });
                    break;
                case "techpack-pdf":
                    save_as (_("Export Tech Pack as PDF"), "pdf", _("PDF documents"), (path) => new TechPackLayout (p).write_pdf (path));
                    break;
                case "odt":
                    save_as (_("Export Tech Pack for Write"), "odt", _("OpenDocument text"), (path) => FileUtils.set_data (path, TechPackOdt.export (p)));
                    break;
                case "xlsx":
                case "ods": {
                    bool x = what == "xlsx";
                    save_as (_("Export Tables"), what, x ? _("Excel workbooks") : _("OpenDocument spreadsheets"), (path) => {
                        var sheets = new Gee.ArrayList<Sheet> ();
                        sheets.add (Tables.bom_sheet (p.techpack, p.colorways));
                        sheets.add (Tables.pom_sheet (p.techpack, p.pattern));
                        sheets.add (Tables.operations_sheet (p.techpack));
                        sheets.add (Tables.measurements_sheet (p.pattern.table));
                        FileUtils.set_data (path, x ? Tables.xlsx (sheets) : Tables.ods (sheets));
                    });
                    break;
                }
                case "bom-csv":
                    save_as (_("Export Bill of Materials"), "csv", _("CSV tables"), (path) => Export.write_text (path, Tables.bom_csv (p.techpack, p.colorways)));
                    break;
            }
        }

        private void open_for (string title, string filter, string[] suffixes, owned SaveFunc reader) {
            Dialogs.open.begin (this, title, filter, suffixes, (o, r) => {
                var f = Dialogs.open.end (r);
                if (f == null) return;
                try {
                    reader (f.get_path ());
                    refresh_all ();
                } catch (Error e) {
                    show_error (_("Could Not Import"), e.message);
                }
            });
        }

        public void import (string what) {
            if (project == null) {
                if (what == "dxf" || what == "seamly") {
                    choose_open ();
                }
                return;
            }
            var p = project;
            switch (what) {
                case "dxf":
                    open_for (_("Import DXF Pattern"), _("DXF patterns"), { "dxf" }, (path) => {
                        string text;
                        FileUtils.get_contents (path, out text);
                        history.checkpoint ();
                        Aama.import_into (text, p, false);
                        p.touch ("pattern");
                        show_workspace ("pattern");
                    });
                    break;
                case "seamly":
                    open_for (_("Import Seamly2D Pattern"), _("Seamly2D and Valentina patterns"), { "sm2d", "val" }, (path) => {
                        history.checkpoint ();
                        var tmp = new Project ();
                        load_seamly (tmp, path);
                        p.pattern = tmp.pattern;
                        p.touch ("pattern");
                        show_workspace ("pattern");
                    });
                    break;
                case "measurements":
                    open_for (_("Import Measurements"), _("Measurement tables"), { "vit", "vst", "smis", "smms", "csv", "xlsx" }, (path) => {
                        history.checkpoint ();
                        p.pattern.table = MeasurementsView.read_table_file (path);
                        p.pattern.active_size = p.pattern.table.base_size;
                        p.touch ("measurements");
                    });
                    break;
                case "rul":
                    open_for (_("Import Grade Rules"), _("ASTM grade rules"), { "rul" }, (path) => {
                        string text;
                        FileUtils.get_contents (path, out text);
                        history.checkpoint ();
                        Aama.import_rules (text, p.pattern);
                        p.touch ("pattern");
                    });
                    break;
                case "image":
                    open_for (_("Import Reference Image"), _("Images"), { "png", "jpg", "jpeg", "tif", "tiff", "webp", "bmp" }, (path) => {
                        sketch_canvas.add_reference (path);
                        show_workspace ("sketch");
                    });
                    break;
                case "ora":
                    open_for (_("Import OpenRaster Layers"), _("OpenRaster images"), { "ora" }, (path) => {
                        uint8[] data;
                        FileUtils.get_data (path, out data);
                        history.checkpoint ();
                        foreach (var l in OraFormat.import (data, p.sketch)) p.sketch.layers.insert (0, l);
                        p.touch ("layers");
                        show_workspace ("sketch");
                    });
                    break;
                case "photo":
                    open_for (_("Pattern from Photo"), _("Images"), { "png", "jpg", "jpeg", "tif", "tiff", "webp" }, (path) => {
                        var pb = new Gdk.Pixbuf.from_file (path);
                        double k = double.min (1, 2400.0 / int.max (pb.width, pb.height));
                        var sc = pb.scale_simple ((int) (pb.width * k), (int) (pb.height * k), Gdk.InterpType.BILINEAR);
                        var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, sc.width, sc.height);
                        var cr = new Cairo.Context (surf);
                        Gdk.cairo_set_source_pixbuf (cr, sc, 0, 0);
                        cr.paint ();
                        new DigitizeDialog (this, surf).present ();
                    });
                    break;
                case "psd":
                    open_for (_("Import Photoshop Layers"), _("Photoshop documents"), { "psd" }, (path) => {
                        uint8[] data;
                        FileUtils.get_data (path, out data);
                        var layers = Psd.read (data, p.sketch);
                        history.checkpoint ();
                        foreach (var l in layers) p.sketch.layers.insert (0, l);
                        p.touch ("layers");
                        show_workspace ("sketch");
                    });
                    break;
                case "svg":
                    open_for (_("Import SVG Drawing"), _("SVG drawings"), { "svg" }, (path) => {
                        string text;
                        FileUtils.get_contents (path, out text);
                        Rect b;
                        var paths = SvgImport.paths (text, out b);
                        history.checkpoint ();
                        if (workspace == "flats" && flats_canvas.sheet != null) {
                            foreach (var pd in paths) {
                                var it = new FlatItem (flats_canvas.sheet.new_id (), FlatItemKind.SHAPE);
                                it.path = pd;
                                it.name = _("Imported");
                                flats_canvas.sheet.items.add (it);
                            }
                            p.touch ("flats");
                        } else {
                            p.sketch.layers.add (SvgImport.to_layer (paths, p.sketch.new_id (), Path.get_basename (path)));
                            p.touch ("layers");
                            show_workspace ("sketch");
                        }
                    });
                    break;
                case "palette":
                    open_for (_("Import Colour Palette"), _("Colour palettes"), { "gpl", "ase" }, (path) => {
                        ColorBook book;
                        if (path.down ().has_suffix (".ase")) {
                            uint8[] data;
                            FileUtils.get_data (path, out data);
                            book = ColorBook.parse_ase (data, NativeFormat.title_from_path (path));
                        } else {
                            string text;
                            FileUtils.get_contents (path, out text);
                            book = ColorBook.parse_gpl (text, NativeFormat.title_from_path (path));
                        }
                        var lib = Singularity.Assets.AssetLibrary.get_default ();
                        foreach (var c in book.colors) {
                            var asset = new Singularity.Assets.Asset ();
                            asset.kind = "color";
                            asset.name = c.name;
                            asset.app = "dev.sinty.atelier";
                            asset.set_field ("color", c.color.to_hex ());
                            asset.set_field ("code", c.code);
                            asset.set_field ("book", book.name);
                            lib.add (asset);
                        }
                        add_toast (new Toast (_("Added %d colours to the library").printf (book.colors.size)));
                    });
                    break;
                case "mesh":
                    open_for (_("Import 3D Model"), _("3D models"), { "gltf", "glb", "obj" }, (path) => {
                        Gee.List<Mesh> meshes = path.down ().has_suffix (".obj") ? Obj.load (path) : Gltf.load (path);
                        view3d.set_meshes (meshes, true);
                        show_workspace ("3d");
                    });
                    break;
            }
        }
    }
}
