using Gtk;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class FlatsCanvas : ZoomCanvas {
        public Project project;
        public History history;
        public FlatSheet? sheet;
        public string tool { get; set; default = "select"; }
        public Gee.HashSet<string> selection = new Gee.HashSet<string> ();
        public StitchStyle stitch = new StitchStyle ();
        public string trim_kind = "button";
        public string trim_asset = "";
        public string proof_profile = "";

        public Colorway shown_colorway () {
            var cw = project.colorway ();
            if (proof_profile == "") return cw;
            var c = cw.copy (cw.name);
            foreach (var e in c.colors.entries) {
                bool out_of_gamut;
                e.value.color = ColorManager.soft_proof (e.value.color, proof_profile, out out_of_gamut);
            }
            return c;
        }
        public signal void selection_changed ();
        public signal void message (string text);
        public signal void sheets_changed ();
        private PathData? building;
        private Point[] clicks = {};
        private string drag_mode = "";
        private Point drag_start;
        private Gee.HashMap<string, FlatItem> drag_orig = new Gee.HashMap<string, FlatItem> ();
        private int node_index = -1;
        private int node_part = 0;
        private Rect band;
        private bool banding;
        private Point hover_pt;

        public FlatsCanvas (Project project, History history) {
            this.project = project;
            this.history = history;
            allow_rotation = false;
            sheet = project.flats.size > 0 ? project.flats[0] : null;
            stitch.kind = StitchKind.SINGLE;
            stitch.offset = 3;
        }

        public void reset_project (Project p) {
            project = p;
            if (sheet == null || p.find_sheet (sheet.id) == null) sheet = p.flats.size > 0 ? p.flats[0] : null;
            else sheet = p.find_sheet (sheet.id);
            selection.clear ();
            queue_draw ();
        }

        public override string status_text () {
            return sheet != null ? sheet.name : _("No Drawing");
        }

        public void fit_all () {
            if (sheet == null) return;
            fit (FlatRenderer.sheet_bounds (sheet));
        }

        protected override void draw_background (Cairo.Context cr, int w, int h) {
            paint_pasteboard (cr, 0.9);
        }

        protected override void draw_content (Cairo.Context cr) {
            if (sheet == null) return;
            var b = FlatRenderer.sheet_bounds (sheet);
            cr.rectangle (b.x, b.y, b.w, b.h);
            cr.set_source_rgb (1, 1, 1);
            cr.fill ();
            var sel = new Gee.HashSet<string> ();
            sel.add_all (selection);
            FlatRenderer.draw_sheet (cr, sheet, shown_colorway (), zoom, sel, true);
            foreach (var c in project.techpack.comments) {
                if (c.sheet != sheet.id) continue;
                cr.save ();
                cr.translate (c.x, c.y);
                cr.scale (1 / zoom, 1 / zoom);
                cr.move_to (0, 0);
                cr.line_to (-8, -16);
                cr.arc (0, -20, 9, Math.PI * 0.8, Math.PI * 0.2);
                cr.close_path ();
                cr.set_source_rgba (c.resolved ? 0.4 : 0.95, c.resolved ? 0.7 : 0.65, 0.1, 0.95);
                cr.fill ();
                cr.restore ();
            }
            if (building != null && !building.is_empty ()) {
                cr.new_path ();
                building.to_cairo (cr);
                cr.line_to (hover_pt.x, hover_pt.y);
                cr.set_source_rgba (0.1, 0.45, 0.9, 0.9);
                cr.set_line_width (1.2 / zoom);
                cr.stroke ();
                foreach (var s in building.segs) {
                    if (s.kind == SegKind.CLOSE) continue;
                    cr.rectangle (s.x - 3 / zoom, s.y - 3 / zoom, 6 / zoom, 6 / zoom);
                    cr.fill ();
                }
            }
            if (clicks.length > 0) {
                cr.set_source_rgba (0.1, 0.45, 0.9, 0.9);
                cr.set_line_width (1 / zoom);
                cr.move_to (clicks[0].x, clicks[0].y);
                cr.line_to (hover_pt.x, hover_pt.y);
                cr.stroke ();
            }
            if (banding) {
                cr.rectangle (band.x, band.y, band.w, band.h);
                cr.set_source_rgba (0.1, 0.45, 0.9, 0.12);
                cr.fill_preserve ();
                cr.set_source_rgba (0.1, 0.45, 0.9, 0.8);
                cr.set_line_width (1 / zoom);
                cr.stroke ();
            }
            foreach (var id in selection) {
                var it = sheet.find (id);
                if (it == null || it.kind != FlatItemKind.SHAPE || tool != "select") continue;
                cr.set_line_width (0.8 / zoom);
                Point prev = Point (0, 0);
                foreach (var s in it.path.segs) {
                    if (s.kind == SegKind.CURVE) {
                        cr.set_source_rgba (0.95, 0.45, 0.1, 0.7);
                        cr.move_to (prev.x, prev.y);
                        cr.line_to (s.x1, s.y1);
                        cr.move_to (s.x, s.y);
                        cr.line_to (s.x2, s.y2);
                        cr.stroke ();
                        cr.arc (s.x1, s.y1, 2.5 / zoom, 0, 2 * Math.PI);
                        cr.fill ();
                        cr.arc (s.x2, s.y2, 2.5 / zoom, 0, 2 * Math.PI);
                        cr.fill ();
                    }
                    if (s.kind != SegKind.CLOSE) prev = Point (s.x, s.y);
                }
            }
        }

        private Point snap (Point p, Gdk.ModifierType mods) {
            if ((mods & Gdk.ModifierType.SHIFT_MASK) != 0 && building != null && building.segs.size > 0) {
                var last = building.segs[building.segs.size - 1];
                double dx = p.x - last.x, dy = p.y - last.y;
                if (dx.abs () > dy.abs ()) return Point (p.x, last.y);
                return Point (last.x, p.y);
            }
            if (sheet != null && (p.x - sheet.axis_x).abs () < 6 / zoom) return Point (sheet.axis_x, p.y);
            return p;
        }

        protected override void hover (Point p) {
            hover_pt = p;
            if (building != null || clicks.length > 0) queue_draw ();
        }

        private FlatItem? item_at (Point p) {
            if (sheet == null) return null;
            for (int i = sheet.items.size - 1; i >= 0; i--) {
                var it = sheet.items[i];
                double tol = 6 / zoom;
                switch (it.kind) {
                    case FlatItemKind.SHAPE: {
                        var full = sheet.full_path (it);
                        if (full.distance_to (p.x, p.y) < tol + it.line_width) return it;
                        break;
                    }
                    case FlatItemKind.TRIM:
                        if (p.distance (it.at) < it.size / 2 + tol) return it;
                        break;
                    case FlatItemKind.CALLOUT:
                        if (p.distance (it.at2) < 10 || PathData.segment_distance (it.at, it.at2, p.x, p.y) < tol) return it;
                        break;
                    case FlatItemKind.DIMENSION:
                        if (!it.path.is_empty () ? it.path.distance_to (p.x, p.y) < tol : PathData.segment_distance (it.at, it.at2, p.x, p.y) < tol + it.offset.abs ()) return it;
                        break;
                    case FlatItemKind.TEXT:
                        if (p.x >= it.at.x - 2 && p.y >= it.at.y - 2 && p.x <= it.at.x + it.text.length * it.size * 0.6 && p.y <= it.at.y + it.size * 1.4) return it;
                        break;
                }
            }
            for (int i = sheet.items.size - 1; i >= 0; i--) {
                var it = sheet.items[i];
                if (it.kind == FlatItemKind.SHAPE && sheet.full_path (it).has_closed_subpath () && sheet.full_path (it).contains (p.x, p.y)) return it;
            }
            return null;
        }

        private void add_item (FlatItem it) {
            history.checkpoint ();
            sheet.items.add (it);
            selection.clear ();
            selection.add (it.id);
            project.touch ("flats");
            selection_changed ();
            queue_draw ();
        }

        protected override void press (Point p, uint button, Gdk.ModifierType mods, StrokeSample s) {
            if (sheet == null || button == Gdk.BUTTON_SECONDARY) return;
            drag_start = p;
            var q = snap (p, mods);
            switch (tool) {
                case "pen":
                case "stitch":
                case "line":
                    if (building == null) {
                        building = new PathData ();
                        building.move_to (q.x, q.y);
                    } else {
                        var first = building.segs[0];
                        if (tool == "pen" && Math.hypot (q.x - first.x, q.y - first.y) < 8 / zoom && building.segs.size > 2) {
                            building.close ();
                            finish_path ();
                            return;
                        }
                        building.line_to (q.x, q.y);
                        if (tool == "line") finish_path ();
                    }
                    drag_mode = "handle";
                    queue_draw ();
                    return;
                case "trim": {
                    var it = new FlatItem (sheet.new_id (), FlatItemKind.TRIM);
                    it.trim = trim_kind;
                    it.asset_id = trim_asset;
                    it.name = Trims.label (trim_kind);
                    if (trim_asset != "") {
                        var a = Singularity.Assets.AssetLibrary.get_default ().find (trim_asset);
                        if (a != null) {
                            it.name = a.name;
                            it.trim = a.get_field ("trim", trim_kind);
                            it.size = a.get_number ("size", 10);
                        }
                    } else {
                        it.size = trim_kind == "zipper" ? 80 : (trim_kind == "cord" ? 50 : 10);
                    }
                    it.at = q;
                    it.fill_slot = "Trim";
                    add_item (it);
                    return;
                }
                case "dimension":
                case "callout":
                    if (clicks.length == 0) {
                        clicks = { q };
                        return;
                    }
                    var it = new FlatItem (sheet.new_id (), tool == "dimension" ? FlatItemKind.DIMENSION : FlatItemKind.CALLOUT);
                    it.at = clicks[0];
                    it.at2 = q;
                    it.offset = 12;
                    if (tool == "callout") {
                        it.number = sheet.next_callout ();
                        it.text = _("Detail %d").printf (it.number);
                    }
                    clicks = {};
                    add_item (it);
                    return;
                case "curve-dimension": {
                    var hit = item_at (p);
                    if (hit == null || hit.kind != FlatItemKind.SHAPE) {
                        message (_("Click a line or seam to measure along it"));
                        return;
                    }
                    var it = new FlatItem (sheet.new_id (), FlatItemKind.DIMENSION);
                    it.path = Offset.polyline (FlatRenderer.path_points (hit.path), -10).length > 1 ? offset_path (hit.path, -10) : hit.path.copy ();
                    it.at = p;
                    it.at2 = p;
                    add_item (it);
                    return;
                }
                case "text": {
                    var it = new FlatItem (sheet.new_id (), FlatItemKind.TEXT);
                    it.at = q;
                    it.text = _("Note");
                    it.size = 10;
                    add_item (it);
                    return;
                }
                case "comment": {
                    history.checkpoint ();
                    var c = new Comment (project.techpack.new_id ("k"), _("New comment"));
                    c.author = Environment.get_real_name () != "Unknown" ? Environment.get_real_name () : Environment.get_user_name ();
                    c.sheet = sheet.id;
                    c.x = p.x;
                    c.y = p.y;
                    project.techpack.comments.add (c);
                    project.touch ("techpack");
                    message (_("Comment added; write it in the Tech Pack"));
                    queue_draw ();
                    return;
                }
            }
            select_press (p, mods);
        }

        private PathData offset_path (PathData src, double d) {
            var out_path = new PathData ();
            foreach (var poly in src.flatten (0.3)) {
                Point[] pts = poly.pts;
                if (poly.closed && pts.length > 0) pts += pts[0];
                out_path.add_polygon (Offset.polyline (pts, d), false);
            }
            return out_path;
        }

        private void select_press (Point p, Gdk.ModifierType mods) {
            drag_mode = "";
            node_index = -1;
            if (selection.size == 1) {
                var it = sheet.find (selection.to_array ()[0]);
                if (it != null && it.kind == FlatItemKind.SHAPE) {
                    for (int i = 0; i < it.path.segs.size; i++) {
                        var s = it.path.segs[i];
                        if (s.kind == SegKind.CLOSE) continue;
                        if (Math.hypot (s.x - p.x, s.y - p.y) < 6 / zoom) {
                            node_index = i;
                            node_part = 0;
                        } else if (s.kind == SegKind.CURVE && Math.hypot (s.x1 - p.x, s.y1 - p.y) < 6 / zoom) {
                            node_index = i;
                            node_part = 1;
                        } else if (s.kind == SegKind.CURVE && Math.hypot (s.x2 - p.x, s.y2 - p.y) < 6 / zoom) {
                            node_index = i;
                            node_part = 2;
                        }
                        if (node_index >= 0) break;
                    }
                    if (node_index >= 0) {
                        history.checkpoint ();
                        drag_mode = "node";
                        return;
                    }
                }
                if (it != null && (it.kind == FlatItemKind.CALLOUT || it.kind == FlatItemKind.DIMENSION)) {
                    if (p.distance (it.at) < 7 / zoom) {
                        history.checkpoint ();
                        drag_mode = "at";
                        return;
                    }
                    if (p.distance (it.at2) < 9 / zoom) {
                        history.checkpoint ();
                        drag_mode = "at2";
                        return;
                    }
                }
            }
            var hit = item_at (p);
            if (hit == null) {
                if ((mods & Gdk.ModifierType.SHIFT_MASK) == 0) selection.clear ();
                banding = true;
                band = Rect (p.x, p.y, 0, 0);
                selection_changed ();
                queue_draw ();
                return;
            }
            if ((mods & Gdk.ModifierType.SHIFT_MASK) != 0) {
                if (selection.contains (hit.id)) selection.remove (hit.id);
                else selection.add (hit.id);
            } else if (!selection.contains (hit.id)) {
                selection.clear ();
                selection.add (hit.id);
            }
            history.checkpoint ();
            drag_mode = "move";
            drag_orig.clear ();
            foreach (var id in selection) {
                var it = sheet.find (id);
                if (it != null) drag_orig[id] = it.copy ();
            }
            selection_changed ();
            queue_draw ();
        }

        protected override void move (Point p, Gdk.ModifierType mods, StrokeSample s) {
            if (sheet == null) return;
            hover_pt = p;
            double dx = p.x - drag_start.x, dy = p.y - drag_start.y;
            if (drag_mode == "handle" && building != null && tool == "pen") {
                var last = building.segs[building.segs.size - 1];
                if (Math.hypot (dx, dy) > 3 / zoom) {
                    Point prev = building.segs.size > 1 ? Point (building.segs[building.segs.size - 2].x, building.segs[building.segs.size - 2].y) : Point (last.x, last.y);
                    if (building.segs.size > 1) {
                        last.kind = SegKind.CURVE;
                        last.x1 = prev.x + (last.x - prev.x) / 3;
                        last.y1 = prev.y + (last.y - prev.y) / 3;
                        last.x2 = last.x - dx;
                        last.y2 = last.y - dy;
                    }
                }
                queue_draw ();
                return;
            }
            if (banding) {
                band = Rect.from_points (drag_start.x, drag_start.y, p.x, p.y);
                queue_draw ();
                return;
            }
            if (drag_mode == "node" && selection.size == 1) {
                var it = sheet.find (selection.to_array ()[0]);
                var sg = it.path.segs[node_index];
                if (node_part == 0) {
                    double ox = sg.x, oy = sg.y;
                    sg.x = p.x;
                    sg.y = p.y;
                    if (sg.kind == SegKind.CURVE) {
                        sg.x2 += p.x - ox;
                        sg.y2 += p.y - oy;
                    }
                    if (node_index + 1 < it.path.segs.size && it.path.segs[node_index + 1].kind == SegKind.CURVE) {
                        it.path.segs[node_index + 1].x1 += p.x - ox;
                        it.path.segs[node_index + 1].y1 += p.y - oy;
                    }
                } else if (node_part == 1) {
                    sg.x1 = p.x;
                    sg.y1 = p.y;
                } else {
                    sg.x2 = p.x;
                    sg.y2 = p.y;
                }
                queue_draw ();
                return;
            }
            if (drag_mode == "at" || drag_mode == "at2") {
                var it = sheet.find (selection.to_array ()[0]);
                if (drag_mode == "at") it.at = p;
                else it.at2 = p;
                queue_draw ();
                return;
            }
            if (drag_mode == "move") {
                foreach (var e in drag_orig.entries) {
                    var it = sheet.find (e.key);
                    if (it == null) continue;
                    var o = e.value;
                    it.path = o.path.transformed (Cairo.Matrix (1, 0, 0, 1, dx, dy));
                    it.at = Point (o.at.x + dx, o.at.y + dy);
                    it.at2 = Point (o.at2.x + dx, o.at2.y + dy);
                }
                queue_draw ();
            }
        }

        protected override void release (Point p, Gdk.ModifierType mods) {
            if (banding) {
                banding = false;
                foreach (var it in sheet.items) {
                    Rect r = it.kind == FlatItemKind.SHAPE ? it.path.bounds () : Rect.from_points (it.at.x, it.at.y, it.at2.x, it.at2.y);
                    if (!r.is_empty () && band.contains_rect (r)) selection.add (it.id);
                }
                selection_changed ();
                queue_draw ();
                return;
            }
            if (drag_mode != "" && drag_mode != "handle") project.touch ("flats");
            drag_mode = "";
        }

        public void finish_path () {
            if (building == null || sheet == null) return;
            var path = building;
            building = null;
            if (path.node_count () < 2) {
                queue_draw ();
                return;
            }
            var it = new FlatItem (sheet.new_id (), FlatItemKind.SHAPE);
            it.path = path;
            bool closed = path.has_closed_subpath ();
            var first = path.segs[0];
            var last = path.segs[path.segs.size - 1];
            if (tool == "stitch") {
                it.name = stitch.kind.label ();
                it.stitch = stitch.copy ();
                it.line_width = 0;
                it.line_slot = "Stitching";
            } else {
                it.name = closed ? _("Shape") : _("Line");
                it.fill_slot = closed ? "Body" : "";
            }
            if (!closed && (first.x - sheet.axis_x).abs () < 0.5 && (last.x - sheet.axis_x).abs () < 0.5 && tool == "pen") {
                it.mirror = true;
                it.fill_slot = "Body";
            }
            add_item (it);
        }

        protected override bool key_pressed (uint keyval, Gdk.ModifierType state) {
            if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                finish_path ();
                return true;
            }
            if (keyval == Gdk.Key.Escape) {
                building = null;
                clicks = {};
                queue_draw ();
                return true;
            }
            if (keyval == Gdk.Key.Delete || keyval == Gdk.Key.BackSpace) {
                delete_selection ();
                return true;
            }
            return false;
        }

        protected override void context_menu (Point p, double x, double y) {
            if (building != null) {
                finish_path ();
                return;
            }
            var hit = item_at (p);
            if (hit == null) return;
            selection.clear ();
            selection.add (hit.id);
            selection_changed ();
            var m = new Singularity.Widgets.ContextMenu (this);
            m.add_item (_("Duplicate"), "edit-copy-symbolic", () => duplicate ());
            m.add_item (hit.mirror ? _("Stop Mirroring") : _("Mirror on the Centre Line"), "atelier-symmetry-symbolic", () => {
                history.checkpoint ();
                hit.mirror = !hit.mirror;
                project.touch ("flats");
                queue_draw ();
            });
            m.add_item (_("Bring to Front"), "go-top-symbolic", () => {
                history.checkpoint ();
                sheet.items.remove (hit);
                sheet.items.add (hit);
                project.touch ("flats");
                queue_draw ();
            });
            m.add_item (_("Send to Back"), "go-bottom-symbolic", () => {
                history.checkpoint ();
                sheet.items.remove (hit);
                sheet.items.insert (0, hit);
                project.touch ("flats");
                queue_draw ();
            });
            m.add_separator ();
            m.add_item (_("Delete"), "user-trash-symbolic", () => delete_selection ());
            var r = Gdk.Rectangle ();
            r.x = (int) x;
            r.y = (int) y;
            r.width = 1;
            r.height = 1;
            m.pointing_to = r;
            m.closed.connect (() => Idle.add (() => {
                m.unparent ();
                return Source.REMOVE;
            }));
            m.popup ();
        }

        public void duplicate () {
            if (sheet == null || selection.size == 0) return;
            history.checkpoint ();
            var fresh = new Gee.HashSet<string> ();
            foreach (var id in selection) {
                var it = sheet.find (id);
                if (it == null) continue;
                var c = it.copy ();
                c.id = sheet.new_id ();
                c.path.translate (10, 10);
                c.at = Point (c.at.x + 10, c.at.y + 10);
                c.at2 = Point (c.at2.x + 10, c.at2.y + 10);
                if (c.kind == FlatItemKind.CALLOUT) c.number = sheet.next_callout ();
                sheet.items.add (c);
                fresh.add (c.id);
            }
            selection.clear ();
            selection.add_all (fresh);
            project.touch ("flats");
            selection_changed ();
            queue_draw ();
        }

        public void delete_selection () {
            if (sheet == null || selection.size == 0) return;
            history.checkpoint ();
            var doomed = new Gee.ArrayList<FlatItem> ();
            foreach (var it in sheet.items) if (selection.contains (it.id)) doomed.add (it);
            sheet.items.remove_all (doomed);
            selection.clear ();
            project.touch ("flats");
            selection_changed ();
            queue_draw ();
        }

        public void choose_tool (string t) {
            if (building != null) finish_path ();
            clicks = {};
            tool = t;
            queue_draw ();
        }
    }
}
