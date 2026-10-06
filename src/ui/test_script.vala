using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class TestScript : Object {
        private static bool started = false;
        private AtelierWindow win;
        private string[] lines;
        private int index = 0;

        public static void maybe_run (AtelierWindow win) {
            string? path = Environment.get_variable ("SINGULARITY_ATELIER_TEST_SCRIPT");
            if (path == null || started) return;
            started = true;
            string text;
            try {
                FileUtils.get_contents (path, out text);
            } catch (Error e) {
                printerr ("script: %s\n", e.message);
                return;
            }
            var s = new TestScript ();
            s.win = win;
            s.lines = text.split ("\n");
            s.ref ();
            Timeout.add (900, () => {
                s.step ();
                return Source.REMOVE;
            });
        }

        private void step () {
            while (index < lines.length) {
                string line = lines[index++].strip ();
                if (line == "" || line.has_prefix ("#")) continue;
                uint wait = 400;
                try {
                    wait = run (line);
                } catch (Error e) {
                    printerr ("script: %s failed: %s\n", line, e.message);
                }
                printerr ("script: ok %s\n", line);
                Timeout.add (wait, () => {
                    step ();
                    return Source.REMOVE;
                });
                return;
            }
            printerr ("script: finished\n");
            unref ();
        }

        private static Gtk.Button? find_button (Gtk.Widget w, string label) {
            if (w is Gtk.Button && w.is_visible () && (((Gtk.Button) w).label == label || face_text (((Gtk.Button) w).child) == label)) return (Gtk.Button) w;
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
                var r = find_button (c, label);
                if (r != null) return r;
            }
            return null;
        }

        private static string? face_text (Gtk.Widget? w) {
            if (w == null) return null;
            if (w is Gtk.Label) return ((Gtk.Label) w).label;
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
                var t = face_text (c);
                if (t != null && t != "") return t;
            }
            return null;
        }

        private static Singularity.Widgets.ActionRow? find_row (Gtk.Widget w, string title) {
            if (w is Singularity.Widgets.ActionRow && ((Singularity.Widgets.ActionRow) w).title == title && w.get_mapped ()) return (Singularity.Widgets.ActionRow) w;
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
                var r = find_row (c, title);
                if (r != null) return r;
            }
            return null;
        }

        private static Gtk.ScrolledWindow? side_scroller (Gtk.Widget w) {
            Gtk.ScrolledWindow? best = null;
            if (w is Gtk.ScrolledWindow && w.get_mapped () && w.get_width () <= 420) best = (Gtk.ScrolledWindow) w;
            for (var c = w.get_first_child (); c != null; c = c.get_next_sibling ()) {
                var r = side_scroller (c);
                if (r != null && (best == null || r.vadjustment.upper - r.vadjustment.page_size > best.vadjustment.upper - best.vadjustment.page_size)) best = r;
            }
            return best;
        }

        private static Point point (string s) {
            string[] v = s.split (",");
            return Point (double.parse (v[0]), double.parse (v.length > 1 ? v[1] : "0"));
        }

        private uint run (string line) throws Error {
            string[] a = line.split (" ");
            string rest = line.length > a[0].length ? line.substring (a[0].length + 1) : "";
            switch (a[0]) {
                case "sleep":
                    return (uint) int.parse (a[1]);
                case "new":
                    win.new_project (a[1]);
                    return 900;
                case "open":
                    win.open_file (File.new_for_path (rest));
                    return 1200;
                case "workspace":
                    win.show_workspace (a[1]);
                    return 700;
                case "sidebar":
                    win.set_sidebar_visible (a[1] == "on");
                    return 300;
                case "fit":
                    win.activate_action ("zoom-fit", null);
                    return 300;
                case "tool":
                    if (win.workspace == "sketch") {
                        win.sketch_canvas.tool = a[1];
                        win.sketch_panel.sync_tool ();
                    } else if (win.workspace == "flats") {
                        win.flats_canvas.choose_tool (a[1]);
                        win.flats_panel.sync_tool ();
                    } else {
                        win.pattern_canvas.tool = a[1];
                        win.pattern_panel.sync_tool ();
                    }
                    return 200;
                case "brush":
                    foreach (var b in win.project.sketch.brushes) if (b.id == a[1]) win.sketch_canvas.brush = b.copy ();
                    if (a.length > 2) win.sketch_canvas.brush.size = double.parse (a[2]);
                    return 100;
                case "color":
                    win.sketch_canvas.color = Rgba.parse (a[1]);
                    return 100;
                case "stroke": {
                    var c = win.sketch_canvas;
                    var layer = c.layer ?? c.first_stroke_layer ();
                    var st = new Stroke.from_brush (c.brush, c.color);
                    for (int i = 1; i < a.length; i++) {
                        var p = point (a[i]);
                        double pr = 0.3 + 0.7 * Math.sin (Math.PI * i / a.length);
                        st.samples.add (StrokeSample (p.x, p.y, pr, 0.2, 0.1, i * 0.02));
                    }
                    c.history.checkpoint ();
                    layer.strokes.add (st);
                    foreach (var m in win.project.sketch.guides.symmetry_transforms ()) {
                        var cp = st.copy ();
                        cp.transform (m);
                        layer.strokes.add (cp);
                    }
                    win.project.sketch.timelapse.add (new TimelapseEvent (layer.id, layer.strokes.size - 1, 0));
                    win.project.touch ("sketch");
                    c.queue_draw ();
                    return 60;
                }
                case "curve": {
                    var c = win.sketch_canvas;
                    var layer = c.layer ?? c.first_stroke_layer ();
                    var st = new Stroke.from_brush (c.brush, c.color);
                    var p0 = point (a[1]);
                    var p1 = point (a[2]);
                    var p2 = point (a[3]);
                    var p3 = point (a[4]);
                    var bz = Bezier (p0, p1, p2, p3);
                    for (int i = 0; i <= 40; i++) {
                        var q = bz.at (i / 40.0);
                        st.samples.add (StrokeSample (q.x, q.y, 0.35 + 0.6 * Math.sin (Math.PI * i / 40), 0.1, 0.1, i * 0.01));
                    }
                    layer.strokes.add (st);
                    foreach (var m in win.project.sketch.guides.symmetry_transforms ()) {
                        var cp = st.copy ();
                        cp.transform (m);
                        layer.strokes.add (cp);
                    }
                    win.project.touch ("sketch");
                    c.queue_draw ();
                    return 40;
                }
                case "guide": {
                    var g = win.project.sketch.guides;
                    switch (a[1]) {
                        case "ruler":
                            g.ruler_on = true;
                            g.ruler_a = point (a[2]);
                            g.ruler_b = point (a[3]);
                            break;
                        case "ellipse":
                            g.ellipse_on = true;
                            g.ellipse_center = point (a[2]);
                            g.ellipse_rx = double.parse (a[3]);
                            g.ellipse_ry = double.parse (a[4]);
                            break;
                        case "curve":
                            g.curve_on = true;
                            g.curve_pos = point (a[2]);
                            break;
                        case "perspective":
                            g.perspective = int.parse (a[2]);
                            g.vp1 = point (a[3]);
                            if (a.length > 4) g.vp2 = point (a[4]);
                            break;
                        case "symmetry":
                            g.symmetry = SymmetryMode.from_id (a[2]);
                            g.symmetry_center = point (a[3]);
                            break;
                        case "off":
                            g.ruler_on = g.ellipse_on = g.curve_on = false;
                            g.perspective = 0;
                            g.symmetry = SymmetryMode.NONE;
                            break;
                    }
                    win.sketch_canvas.queue_draw ();
                    return 100;
                }
                case "fill": {
                    var p = point (a[1]);
                    var c = win.sketch_canvas;
                    var path = RegionFill.region (win.project.sketch, c.layer, p, 0.3, 1);
                    if (path != null) {
                        var f = new FillRegion ();
                        f.path = path;
                        f.color = Rgba.parse (a[2]);
                        f.opacity = a.length > 3 ? double.parse (a[3]) : 1;
                        c.layer.fills.add (f);
                    }
                    c.queue_draw ();
                    return 100;
                }
                case "vehicle":
                    win.sketch_canvas.add_vehicle_underlay (a[1]);
                    return 300;
                case "mode":
                    win.pattern_canvas.switch_mode (a[1]);
                    return 700;
                case "select-piece":
                    win.pattern_canvas.selected_piece = win.project.pattern.pieces[int.parse (a[1])].id;
                    win.pattern_canvas.selection_changed ();
                    win.pattern_canvas.queue_draw ();
                    return 300;
                case "select-point": {
                    var p = win.project.pattern.point_by_name (a[1]);
                    if (p != null) {
                        win.pattern_canvas.selection.clear ();
                        win.pattern_canvas.selection.add (p.id);
                        win.pattern_canvas.selection_changed ();
                        win.pattern_canvas.queue_draw ();
                    }
                    return 300;
                }
                case "size":
                    win.project.pattern.active_size = a[1];
                    win.pattern_canvas.reevaluate ();
                    win.pattern_panel.refresh ();
                    return 300;
                case "walk": {
                    var r = win.project.pattern.evaluate ();
                    var pairs = Seams.guess_pairs (r);
                    if (pairs.size > int.parse (a[1])) win.pattern_canvas.start_walk (pairs[int.parse (a[1])]);
                    return 2500;
                }
                case "sheet":
                    win.flats_canvas.sheet = win.project.flats[int.parse (a[1])];
                    win.flats_canvas.fit_all ();
                    return 300;
                case "select-flat":
                    win.flats_canvas.selection.clear ();
                    foreach (var it in win.flats_canvas.sheet.items) if (it.name == rest) win.flats_canvas.selection.add (it.id);
                    win.flats_canvas.selection_changed ();
                    win.flats_canvas.queue_draw ();
                    return 300;
                case "colorway":
                    win.project.active_colorway = rest;
                    win.flats_panel.refresh ();
                    win.flats_canvas.queue_draw ();
                    return 300;
                case "add-colorway": {
                    var cw = win.project.colorway ().copy (a[1]);
                    for (int i = 2; i + 1 < a.length; i += 2) cw.colors[a[i]] = new ColorRef (Rgba.parse (a[i + 1]), a[i]);
                    win.project.colorways.add (cw);
                    win.flats_panel.refresh ();
                    return 200;
                }
                case "callout": {
                    var sh = win.flats_canvas.sheet;
                    var it = new FlatItem (sh.new_id (), FlatItemKind.CALLOUT);
                    it.at = point (a[1]);
                    it.at2 = point (a[2]);
                    it.number = sh.next_callout ();
                    it.text = a.length > 3 ? string.joinv (" ", a[3:a.length]) : "";
                    sh.items.add (it);
                    win.flats_canvas.queue_draw ();
                    return 100;
                }
                case "dimension": {
                    var sh = win.flats_canvas.sheet;
                    var it = new FlatItem (sh.new_id (), FlatItemKind.DIMENSION);
                    it.at = point (a[1]);
                    it.at2 = point (a[2]);
                    it.offset = a.length > 3 ? double.parse (a[3]) : 12;
                    sh.items.add (it);
                    win.flats_canvas.queue_draw ();
                    return 100;
                }
                case "techpack":
                    win.show_workspace ("techpack");
                    win.techpack_view.show_section (a[1]);
                    return 500;
                case "garment":
                    win.show_workspace ("3d");
                    return 800;
                case "action":
                    win.activate_action (a[1], a.length > 2 ? new Variant.string (a[2]) : null);
                    return 1200;
                case "print":
                    win.print_current.begin ();
                    return 2500;
                case "save":
                    win.write_to (rest);
                    return 300;
                case "zoom":
                    var cv = win.workspace == "sketch" ? (ZoomCanvas) win.sketch_canvas : (win.workspace == "flats" ? (ZoomCanvas) win.flats_canvas : (ZoomCanvas) win.pattern_canvas);
                    cv.zoom_at (cv.get_width () / 2.0, cv.get_height () / 2.0, double.parse (a[1]));
                    return 200;
                case "shot": {
                    string dir = Environment.get_variable ("ATELIER_SHOTS") ?? Environment.get_tmp_dir ();
                    Process.spawn_command_line_async ("grim %s".printf (GLib.Shell.quote (Path.build_filename (dir, a[1] + ".png"))));
                    return 900;
                }
                case "click": {
                    var b = find_button (win, rest);
                    if (b == null) throw new FormatError.INVALID ("no button %s".printf (rest));
                    b.clicked ();
                    return 800;
                }
                case "spin": {
                    var row = find_row (win, a[1].replace ("_", " ")) as Singularity.Widgets.SpinRow;
                    if (row == null) throw new FormatError.INVALID ("no spin row %s".printf (a[1]));
                    row.value = double.parse (a[2]);
                    return 600;
                }
                case "choose": {
                    var row = find_row (win, a[1].replace ("_", " ")) as Singularity.Widgets.SelectionRow;
                    if (row == null) throw new FormatError.INVALID ("no selection row %s".printf (a[1]));
                    row.current_value = a[2].replace ("_", " ");
                    row.selected (row.current_value);
                    return 600;
                }
                case "scroll": {
                    var row = find_row (win, rest);
                    if (row == null) throw new FormatError.INVALID ("no row %s".printf (rest));
                    var scrolled = (Gtk.ScrolledWindow?) row.get_ancestor (typeof (Gtk.ScrolledWindow));
                    Graphene.Point at = Graphene.Point.zero ();
                    if (scrolled != null && row.compute_point (scrolled.child, Graphene.Point.zero (), out at)) scrolled.vadjustment.value = at.y - 12;
                    return 600;
                }
                case "side-page": {
                    var sc = side_scroller (win);
                    if (sc == null) throw new FormatError.INVALID ("no side panel");
                    var adj = sc.vadjustment;
                    adj.value = double.min (adj.upper - adj.page_size, int.parse (a[1]) * adj.page_size * 0.9);
                    printerr ("script: side panel %.0f of %.0f\n", adj.value, adj.upper);
                    return 500;
                }
                case "plane-stroke": {
                    var view = win.view3d;
                    string mode = view.plane_mode;
                    double offset = view.plane_offset;
                    view.plane_mode = a[1];
                    view.plane_offset = double.parse (a[2]);
                    for (int i = 3; i < a.length; i++) {
                        var q = point (a[i]);
                        view.plane_point (q.x, q.y, i == 3);
                    }
                    view.plane_stroke_done ();
                    view.plane_mode = mode;
                    view.plane_offset = offset;
                    return 600;
                }
                case "close-dialogs":
                    var others = new Gee.ArrayList<Gtk.Window> ();
                    foreach (var w in win.application.get_windows ()) if (w != win) others.add (w);
                    foreach (var w in others) {
                        var cancel = find_button (w, _("Cancel"));
                        if (cancel != null) cancel.clicked ();
                        else w.close ();
                    }
                    return 900;
                case "quit":
                    win.project.modified = false;
                    win.application.quit ();
                    return 100;
                default:
                    throw new FormatError.UNSUPPORTED ("unknown command");
            }
        }
    }
}
