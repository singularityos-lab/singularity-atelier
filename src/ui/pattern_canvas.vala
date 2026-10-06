using Gtk;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class PatternCanvas : ZoomCanvas {
        public Project project;
        public History history;
        public string mode { get; set; default = "draft"; }
        public string tool { get; set; default = "select"; }
        public Gee.ArrayList<string> selection = new Gee.ArrayList<string> ();
        public string? selected_piece;
        public PatternResult? result;
        public Gee.HashMap<string, PatternResult>? nest;
        public MarkerResult? marker;
        public string nest_anchor = "grain";
        public SeamPair? walk_pair;
        public double walk_pos;
        public signal void selection_changed ();
        public signal void message (string text);
        public signal void request_point (double x, double y);
        public signal void evaluated ();
        private string drag_what = "";
        private Point drag_origin;
        private double orig_x;
        private double orig_y;
        private Point measure_a;
        private Point measure_b;
        private bool measuring;
        private uint anim_id;

        public PatternCanvas (Project project, History history) {
            this.project = project;
            this.history = history;
            allow_rotation = false;
            project.changed.connect ((w) => reevaluate ());
            reevaluate ();
        }

        public void reset_project (Project p) {
            project = p;
            project.changed.connect ((w) => reevaluate ());
            selection.clear ();
            selected_piece = null;
            reevaluate ();
        }

        public Pattern pattern {
            get { return project.pattern; }
        }

        public void reevaluate () {
            result = pattern.evaluate ();
            if (mode == "nest") nest = Grading.nest (pattern);
            evaluated ();
            queue_draw ();
        }

        public void switch_mode (string m) {
            mode = m;
            if (m == "nest") nest = Grading.nest (pattern);
            if (m == "marker" && marker == null) compute_marker ();
            queue_draw ();
            Idle.add (() => {
                fit_all ();
                return Source.REMOVE;
            });
        }

        public void compute_marker () {
            marker = Marker.compute (pattern, project.marker);
            queue_draw ();
        }

        public void fit_all () {
            if (result == null) return;
            Rect b;
            if (mode == "draft") {
                b = PatternRenderer.draft_bounds (result);
                b = b.union (PatternRenderer.pieces_bounds (result, false));
            } else if (mode == "marker" && marker != null) {
                b = Rect (0, 0, marker.length, marker.width);
            } else {
                b = PatternRenderer.pieces_bounds (result, true);
            }
            if (b.is_empty ()) b = Rect (0, 0, 600, 600);
            fit (b.inflate (30));
        }

        protected override void draw_background (Cairo.Context cr, int w, int h) {
            cr.set_source_rgb (0.97, 0.965, 0.955);
            cr.paint ();
        }

        protected override void draw_content (Cairo.Context cr) {
            if (result == null) return;
            var st = new PatternStyle ();
            st.zoom = zoom;
            draw_grid (cr, visible_doc (), 10, zoom, false);
            var sel = new Gee.HashSet<string> ();
            sel.add_all (selection);
            switch (mode) {
                case "draft":
                    foreach (var g in result.pieces) {
                        var ps = new PatternStyle ();
                        ps.zoom = zoom;
                        ps.piece_fill = Rgba (0.98, 0.95, 0.88, 0.35);
                        ps.show_labels = false;
                        PatternRenderer.draw_piece (cr, g, ps, result.size, g.piece.id == selected_piece);
                    }
                    PatternRenderer.draw_draft (cr, pattern, result, st, sel);
                    break;
                case "pieces":
                    foreach (var g in result.pieces) PatternRenderer.draw_piece (cr, g.transformed (g.placement_matrix ()), st, result.size, g.piece.id == selected_piece);
                    break;
                case "nest":
                    if (nest == null) nest = Grading.nest (pattern);
                    foreach (var g in result.pieces) {
                        cr.save ();
                        cr.transform (g.placement_matrix ());
                        PatternRenderer.draw_nest (cr, pattern, nest, g.piece.id, nest_anchor, st);
                        cr.restore ();
                    }
                    break;
                case "marker":
                    if (marker != null) PatternRenderer.draw_marker (cr, marker, st);
                    break;
                case "walk":
                    draw_walk (cr, st);
                    break;
            }
            if (measuring) {
                cr.set_source_rgba (0.85, 0.2, 0.2, 0.9);
                cr.set_line_width (1.5 / zoom);
                cr.move_to (measure_a.x, measure_a.y);
                cr.line_to (measure_b.x, measure_b.y);
                cr.stroke ();
                var lay = Pango.cairo_create_layout (cr);
                var fd = Pango.FontDescription.from_string ("Sans Bold");
                fd.set_absolute_size (12 / zoom * Pango.SCALE);
                lay.set_font_description (fd);
                lay.set_text ("%s %s".printf (PathData.fmt (measure_a.distance (measure_b) / pattern.unit_mm (), 2), pattern.unit), -1);
                cr.move_to ((measure_a.x + measure_b.x) / 2 + 6 / zoom, (measure_a.y + measure_b.y) / 2);
                Pango.cairo_show_layout (cr, lay);
            }
        }

        private void draw_walk (Cairo.Context cr, PatternStyle st) {
            if (walk_pair == null) return;
            var ga = result.piece (walk_pair.piece_a);
            var gb = result.piece (walk_pair.piece_b);
            if (ga == null || gb == null || walk_pair.edge_a >= ga.edges.size || walk_pair.edge_b >= gb.edges.size) return;
            PatternRenderer.draw_piece (cr, ga, st, result.size);
            var ea = ga.edges[walk_pair.edge_a].pts;
            var eb = gb.edges[walk_pair.edge_b].pts;
            if (walk_pair.reverse_b) eb = Polyline.reversed (eb);
            double la = Polyline.length (ea), lb = Polyline.length (eb);
            double s = walk_pos * double.min (la, lb);
            var m = Seams.walk_transform (ea, eb, s);
            cr.save ();
            cr.transform (m);
            var ws = new PatternStyle ();
            ws.zoom = zoom;
            ws.piece_fill = Rgba (0.8, 0.9, 1, 0.55);
            PatternRenderer.draw_piece (cr, gb, ws, result.size, false, Rgba (0.15, 0.4, 0.8, 1));
            cr.restore ();
            cr.new_path ();
            PatternRenderer.poly (cr, ea, false);
            cr.set_source_rgba (0.9, 0.3, 0.1, 0.9);
            cr.set_line_width (3 / zoom);
            cr.stroke ();
            double ang;
            var at = Polyline.at_length (ea, s, out ang);
            cr.arc (at.x, at.y, 5 / zoom, 0, 2 * Math.PI);
            cr.fill ();
        }

        public override string status_text () {
            string info = _("Size %s").printf (result != null ? result.size : "");
            if (mode == "marker" && marker != null) info = _("Marker length %s m, efficiency %s%%, %d pieces").printf (PathData.fmt (marker.length_m (), 3), PathData.fmt (marker.efficiency (), 1), marker.placements.size);
            if (mode == "walk" && walk_pair != null && result != null) {
                var chk = Seams.walk (result, walk_pair);
                if (chk != null) info = _("Seam lengths %s and %s %s, difference %s").printf (PathData.fmt (chk.length_a / pattern.unit_mm (), 2), PathData.fmt (chk.length_b / pattern.unit_mm (), 2), pattern.unit, PathData.fmt (chk.difference () / pattern.unit_mm (), 2));
            }
            if (result != null && result.errors.size > 0) info += ", " + ngettext ("%d formula has an error", "%d formulas have errors", result.errors.size).printf (result.errors.size);
            return info;
        }

        public string? point_at (Point p) {
            if (result == null) return null;
            string? best = null;
            double bd = 8 / zoom;
            foreach (var pt in pattern.points) {
                if (!result.points.has_key (pt.id)) continue;
                double d = result.points[pt.id].distance (p);
                if (d < bd) {
                    bd = d;
                    best = pt.id;
                }
            }
            return best;
        }

        public string? curve_at (Point p) {
            if (result == null) return null;
            string? best = null;
            double bd = 6 / zoom;
            foreach (var e in result.curves.entries) {
                foreach (var bz in e.value) {
                    double t = bz.nearest_t (p.x, p.y);
                    double d = bz.at (t).distance (p);
                    if (d < bd) {
                        bd = d;
                        best = e.key;
                    }
                }
            }
            return best;
        }

        public string? piece_at (Point p, bool placed) {
            if (result == null) return null;
            for (int i = result.pieces.size - 1; i >= 0; i--) {
                var g = placed ? result.pieces[i].transformed (result.pieces[i].placement_matrix ()) : result.pieces[i];
                var outline = g.cut.length > 2 ? g.cut : g.seam;
                if (outline.length < 3) continue;
                var pd = new PathData ();
                pd.add_polygon (outline, true);
                if (pd.contains (p.x, p.y)) return g.piece.id;
            }
            return null;
        }

        public int edge_at (PieceGeometry g, Point p) {
            int best = -1;
            double bd = 8 / zoom;
            for (int i = 0; i < g.edges.size; i++) {
                var e = g.edges[i].pts;
                for (int k = 1; k < e.length; k++) {
                    double d = PathData.segment_distance (e[k - 1], e[k], p.x, p.y);
                    if (d < bd) {
                        bd = d;
                        best = i;
                    }
                }
            }
            return best;
        }

        protected override void press (Point p, uint button, Gdk.ModifierType mods, StrokeSample s) {
            drag_what = "";
            drag_origin = p;
            if (mode == "pieces") {
                selected_piece = piece_at (p, true);
                if (selected_piece != null) {
                    var pc = pattern.find_piece (selected_piece);
                    history.checkpoint ();
                    drag_what = "piece";
                    orig_x = pc.place_x;
                    orig_y = pc.place_y;
                }
                selection_changed ();
                queue_draw ();
                return;
            }
            if (mode != "draft") return;
            switch (tool) {
                case "measure":
                    measuring = true;
                    string? pid = point_at (p);
                    measure_a = pid != null ? result.points[pid] : p;
                    measure_b = measure_a;
                    queue_draw ();
                    return;
                case "point":
                    request_point (p.x, p.y);
                    return;
                case "notch": {
                    string? pid = point_at (p);
                    if (pid == null) return;
                    foreach (var pc in pattern.pieces) {
                        foreach (var nd in pc.nodes) {
                            if (!nd.is_curve && nd.ref_id == pid) {
                                history.checkpoint ();
                                nd.notch = !nd.notch;
                                project.touch ("pattern");
                                return;
                            }
                        }
                    }
                    var pcid = piece_at (p, false);
                    if (pcid != null) {
                        var g = result.piece (pcid);
                        int e = edge_at (g, p);
                        if (e >= 0) {
                            double d = Seams.position_on (g.edges[e].pts, p, 8 / zoom);
                            if (d >= 0) {
                                history.checkpoint ();
                                g.piece.extra_notches.add (new ExtraNotch (e, d));
                                project.touch ("pattern");
                            }
                        }
                    }
                    return;
                }
                case "drill": {
                    string? pid = point_at (p);
                    var pcid = piece_at (p, false);
                    if (pid == null || pcid == null) {
                        message (_("Click a point inside a piece to place a drill hole"));
                        return;
                    }
                    history.checkpoint ();
                    var dh = new DrillHole ();
                    dh.point = pid;
                    pattern.find_piece (pcid).drills.add (dh);
                    project.touch ("pattern");
                    return;
                }
            }
            string? hit = point_at (p);
            string? hit_curve = hit == null ? curve_at (p) : null;
            bool add = (mods & Gdk.ModifierType.SHIFT_MASK) != 0 || tool == "curve" || tool == "piece" || tool == "grain" || tool == "dart" || tool == "pleat";
            if (hit == null && hit_curve == null) {
                if (!add) {
                    selection.clear ();
                    selected_piece = piece_at (p, false);
                    selection_changed ();
                    queue_draw ();
                }
                return;
            }
            string id = hit ?? hit_curve;
            if (!add) selection.clear ();
            if (selection.contains (id) && add && tool == "select") selection.remove (id);
            else selection.add (id);
            if (hit != null && tool == "select") {
                var pt = pattern.find_point (hit);
                if (pt.kind == PointKind.BASE || pt.kind == PointKind.OFFSET) {
                    double fx = 0, fy = 0;
                    if (double.try_parse (pt.fx, out fx) && double.try_parse (pt.fy, out fy)) {
                        history.checkpoint ();
                        drag_what = "point";
                        orig_x = fx;
                        orig_y = fy;
                    }
                }
            }
            selection_changed ();
            queue_draw ();
        }

        protected override void move (Point p, Gdk.ModifierType mods, StrokeSample s) {
            if (measuring) {
                string? pid = point_at (p);
                measure_b = pid != null ? result.points[pid] : p;
                queue_draw ();
                return;
            }
            if (drag_what == "piece" && selected_piece != null) {
                var pc = pattern.find_piece (selected_piece);
                pc.place_x = orig_x + p.x - drag_origin.x;
                pc.place_y = orig_y + p.y - drag_origin.y;
                result = pattern.evaluate ();
                queue_draw ();
                return;
            }
            if (drag_what == "point" && selection.size == 1) {
                var pt = pattern.find_point (selection[0]);
                double um = pattern.unit_mm ();
                double nx = orig_x + (p.x - drag_origin.x) / um;
                double ny = orig_y + (p.y - drag_origin.y) / um;
                if ((mods & Gdk.ModifierType.CONTROL_MASK) == 0) {
                    nx = Math.round (nx * 10) / 10;
                    ny = Math.round (ny * 10) / 10;
                }
                pt.fx = PathData.fmt (nx, 2);
                pt.fy = PathData.fmt (ny, 2);
                result = pattern.evaluate ();
                queue_draw ();
            }
        }

        protected override void release (Point p, Gdk.ModifierType mods) {
            if (measuring) {
                measuring = false;
                message (_("Distance %s %s").printf (PathData.fmt (measure_a.distance (measure_b) / pattern.unit_mm (), 2), pattern.unit));
                queue_draw ();
                return;
            }
            if (drag_what != "") {
                drag_what = "";
                project.touch ("pattern");
                selection_changed ();
            }
        }

        protected override void context_menu (Point p, double x, double y) {
            if (mode == "pieces") {
                var id = piece_at (p, true);
                if (id == null) return;
                selected_piece = id;
                var pc = pattern.find_piece (id);
                var m = new Singularity.Widgets.ContextMenu (this);
                m.add_item (_("Rotate 90°"), "object-rotate-right-symbolic", () => {
                    history.checkpoint ();
                    pc.rotation = (pc.rotation + 90) % 360;
                    project.touch ("pattern");
                });
                m.add_item (_("Rotate 180°"), "object-rotate-right-symbolic", () => {
                    history.checkpoint ();
                    pc.rotation = (pc.rotation + 180) % 360;
                    project.touch ("pattern");
                });
                m.add_item (_("Flip"), "object-flip-horizontal-symbolic", () => {
                    history.checkpoint ();
                    pc.flipped = !pc.flipped;
                    project.touch ("pattern");
                });
                popup (m, x, y);
                selection_changed ();
            }
        }

        private void popup (Singularity.Widgets.ContextMenu m, double x, double y) {
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

        protected override bool key_pressed (uint keyval, Gdk.ModifierType state) {
            if (keyval == Gdk.Key.Delete) {
                delete_selection ();
                return true;
            }
            if (keyval == Gdk.Key.Escape) {
                selection.clear ();
                selection_changed ();
                queue_draw ();
                return true;
            }
            return false;
        }

        public void delete_selection () {
            if (selection.size == 0 && selected_piece == null) return;
            history.checkpoint ();
            if (selection.size == 0 && selected_piece != null) {
                var pc = pattern.find_piece (selected_piece);
                if (pc != null) pattern.pieces.remove (pc);
                selected_piece = null;
                project.touch ("pattern");
                selection_changed ();
                return;
            }
            var doomed = new Gee.HashSet<string> ();
            foreach (var id in selection) {
                doomed.add (id);
                doomed.add_all (pattern.dependents_of (id));
            }
            var pts = new Gee.ArrayList<PatternPoint> ();
            foreach (var p in pattern.points) if (doomed.contains (p.id)) pts.add (p);
            pattern.points.remove_all (pts);
            var cvs = new Gee.ArrayList<PatternCurve> ();
            foreach (var c in pattern.curves) if (doomed.contains (c.id)) cvs.add (c);
            pattern.curves.remove_all (cvs);
            foreach (var pc in pattern.pieces) {
                var nodes = new Gee.ArrayList<PieceNode> ();
                foreach (var nd in pc.nodes) if (doomed.contains (nd.ref_id)) nodes.add (nd);
                pc.nodes.remove_all (nodes);
            }
            if (doomed.size > selection.size) message (ngettext ("%d dependent object was removed too", "%d dependent objects were removed too", doomed.size - selection.size).printf (doomed.size - selection.size));
            selection.clear ();
            project.touch ("pattern");
            selection_changed ();
        }

        public void start_walk (SeamPair pair) {
            walk_pair = pair;
            mode = "walk";
            walk_pos = 0;
            if (anim_id != 0) Source.remove (anim_id);
            anim_id = Timeout.add (30, () => {
                walk_pos += 0.01;
                if (walk_pos > 1) {
                    walk_pos = 1;
                    anim_id = 0;
                    queue_draw ();
                    return Source.REMOVE;
                }
                queue_draw ();
                return Source.CONTINUE;
            });
            Idle.add (() => {
                var ga = result.piece (pair.piece_a);
                if (ga != null) fit (ga.bounds ().inflate (ga.bounds ().w * 0.8));
                return Source.REMOVE;
            });
        }
    }
}
