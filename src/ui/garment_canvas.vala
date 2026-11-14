using Gtk;
using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class GarmentCanvas : ZoomCanvas {
        public string tool = "select";
        public string selected_piece = "";
        public int selected_seam = -1;
        private Project project;
        private PatternResult? result;
        private string size = "";
        private string hover_piece = "";
        private int hover_edge = -1;
        private double hover_t;
        private string pending_piece = "";
        private int pending_edge = -1;
        private double pending_t;
        private double pending_t2 = -1;
        private int free_step;
        private Gee.HashMap<string, Point?> offsets = new Gee.HashMap<string, Point?> ();
        private Point[] draft = {};
        private Point draft_at;
        private bool dragging_rect;
        private string node_piece = "";
        private int node_index = -1;
        private bool node_moved;

        public signal void selection_changed ();
        public signal void seams_changed ();
        public signal void pattern_changed ();
        public signal void tool_changed ();
        public signal void message (string text);

        public GarmentCanvas (Project project) {
            this.project = project;
            allow_rotation = false;
            wheel_zooms = true;
        }

        public void reset_project (Project p) {
            project = p;
            selected_piece = "";
            selected_seam = -1;
            cancel ();
            result = null;
            queue_draw ();
        }

        public void show_size (string s) {
            size = s;
            result = project.pattern.evaluate (size);
            layout ();
            queue_draw ();
        }

        private bool fold_line (PieceGeometry g, out Point a, out Point b) {
            a = Point (0, 0);
            b = Point (0, 0);
            if (!g.piece.on_fold || g.piece.fold_edge < 0 || g.piece.fold_edge >= g.edges.size) return false;
            var fe = g.edges[g.piece.fold_edge].pts;
            a = fe[0];
            b = fe[fe.length - 1];
            return true;
        }

        private Rect full_bounds (PieceGeometry g) {
            var r = Rect.empty ();
            Point fa, fb;
            bool fold = fold_line (g, out fa, out fb);
            foreach (var p in g.seam) {
                r = r.include (p.x, p.y);
                if (fold) {
                    var q = mirror (p, fa, fb);
                    r = r.include (q.x, q.y);
                }
            }
            return r;
        }

        private void layout () {
            offsets.clear ();
            if (result == null) return;
            double x = 0;
            foreach (var g in result.pieces) {
                if (g.seam.length < 3) continue;
                var b = full_bounds (g);
                offsets[g.piece.id] = Point (x - b.x, -b.y);
                x += b.w + 50;
            }
        }

        private Point offset_of (string id) {
            return offsets.has_key (id) ? offsets[id] : Point (0, 0);
        }

        private Point to_piece (PieceGeometry g, Point p, out bool mirrored) {
            var o = offset_of (g.piece.id);
            var q = Point (p.x - o.x, p.y - o.y);
            mirrored = false;
            Point fa, fb;
            if (fold_line (g, out fa, out fb)) {
                double side = (fb.x - fa.x) * (q.y - fa.y) - (fb.y - fa.y) * (q.x - fa.x);
                double own = 0;
                foreach (var v in g.seam) own += (fb.x - fa.x) * (v.y - fa.y) - (fb.y - fa.y) * (v.x - fa.x);
                if (side * own < 0) {
                    q = mirror (q, fa, fb);
                    mirrored = true;
                }
            }
            return q;
        }

        public void choose_tool (string id) {
            tool = id;
            cancel ();
            tool_changed ();
            queue_draw ();
        }

        private void cancel () {
            draft = {};
            dragging_rect = false;
            pending_piece = "";
            pending_edge = -1;
            pending_t2 = -1;
            free_step = 0;
        }

        public void fit_all () {
            if (result == null || result.pieces.size == 0) return;
            var r = Rect.empty ();
            foreach (var g in result.pieces) {
                if (g.seam.length < 3) continue;
                var b = full_bounds (g);
                var o = offset_of (g.piece.id);
                r = r.include (b.x + o.x, b.y + o.y).include (b.x + o.x + b.w, b.y + o.y + b.h);
            }
            if (r.w > 0 && r.h > 0) fit (Rect (r.x - 40, r.y - 40, r.w + 80, r.h + 80));
        }

        private static Point[] outline (PieceGeometry g) {
            return g.seam;
        }

        public static Rgba seam_color (int index) {
            double h = Math.fmod (index * 0.381966 + 0.58, 1.0);
            double r = 0, gr = 0, b = 0;
            double x = h * 6;
            int k = (int) x;
            double f = x - k;
            double lo = 0.25, hi = 0.92;
            switch (k % 6) {
                case 0: r = hi; gr = lo + (hi - lo) * f; b = lo; break;
                case 1: r = hi - (hi - lo) * f; gr = hi; b = lo; break;
                case 2: r = lo; gr = hi; b = lo + (hi - lo) * f; break;
                case 3: r = lo; gr = hi - (hi - lo) * f; b = hi; break;
                case 4: r = lo + (hi - lo) * f; gr = lo; b = hi; break;
                default: r = hi; gr = lo; b = hi - (hi - lo) * f; break;
            }
            return Rgba (r, gr, b, 1);
        }

        private static Point[] span (Point[] pts, double t0, double t1) {
            double len = Polyline.length (pts);
            double a = double.min (t0, t1) * len, b = double.max (t0, t1) * len;
            Point[] o = {};
            double ang;
            o += Polyline.at_length (pts, a, out ang);
            double run = 0;
            for (int i = 1; i < pts.length; i++) {
                run += pts[i - 1].distance (pts[i]);
                if (run > a + 1e-6 && run < b - 1e-6) o += pts[i];
            }
            o += Polyline.at_length (pts, b, out ang);
            return o;
        }

        private static double param_on (Point[] pts, Point p) {
            double len = Polyline.length (pts);
            if (len < 1e-9) return 0;
            double best = double.INFINITY, at = 0, run = 0;
            for (int i = 1; i < pts.length; i++) {
                var a = pts[i - 1];
                var b = pts[i];
                double dx = b.x - a.x, dy = b.y - a.y;
                double l2 = dx * dx + dy * dy;
                double t = l2 > 0 ? (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).clamp (0, 1) : 0;
                double d = Math.hypot (a.x + dx * t - p.x, a.y + dy * t - p.y);
                if (d < best) {
                    best = d;
                    at = run + Math.sqrt (l2) * t;
                }
                run += Math.sqrt (l2);
            }
            return at / len;
        }

        private PieceGeometry? geometry (string id) {
            if (result == null) return null;
            foreach (var g in result.pieces) if (g.piece.id == id) return g;
            return null;
        }

        private bool edge_under (Point p, out string piece, out int edge, out double t) {
            piece = "";
            edge = -1;
            t = 0;
            if (result == null) return false;
            double best = 9 / zoom;
            PieceGeometry? hit = null;
            Point local = p;
            foreach (var g in result.pieces) {
                bool mirrored;
                var q = to_piece (g, p, out mirrored);
                for (int i = 0; i < g.edges.size; i++) {
                    if (g.piece.on_fold && g.piece.fold_edge == i) continue;
                    var e = g.edges[i].pts;
                    for (int k = 1; k < e.length; k++) {
                        double d = PathData.segment_distance (e[k - 1], e[k], q.x, q.y);
                        if (d < best) {
                            best = d;
                            piece = g.piece.id;
                            edge = i;
                            hit = g;
                            local = q;
                        }
                    }
                }
            }
            if (hit == null) return false;
            t = param_on (hit.edges[edge].pts, local);
            return true;
        }

        private string piece_under (Point at) {
            Point p = at;
            if (result == null) return "";
            for (int i = result.pieces.size - 1; i >= 0; i--) {
                var g = result.pieces[i];
                var pts = outline (g);
                bool mirrored;
                p = to_piece (g, p, out mirrored);
                bool inside = false;
                for (int a = 0, b = pts.length - 1; a < pts.length; b = a++) {
                    if ((pts[a].y > p.y) != (pts[b].y > p.y) && p.x < (pts[b].x - pts[a].x) * (p.y - pts[a].y) / (pts[b].y - pts[a].y) + pts[a].x) inside = !inside;
                }
                if (inside) return g.piece.id;
                p = at;
            }
            return "";
        }

        private int seam_under (Point p) {
            if (result == null) return -1;
            double best = 9 / zoom;
            int found = -1;
            for (int s = 0; s < project.garment.seams.size; s++) {
                var sp = project.garment.seams[s];
                for (int side = 0; side < 2; side++) {
                    var g = geometry (side == 0 ? sp.piece_a : sp.piece_b);
                    int e = side == 0 ? sp.edge_a : sp.edge_b;
                    if (g == null || e < 0 || e >= g.edges.size) continue;
                    var pts = span (g.edges[e].pts, side == 0 ? sp.a0 : sp.b0, side == 0 ? sp.a1 : sp.b1);
                    bool mirrored;
                    var q = to_piece (g, p, out mirrored);
                    for (int k = 1; k < pts.length; k++) {
                        double d = PathData.segment_distance (pts[k - 1], pts[k], q.x, q.y);
                        if (d < best) {
                            best = d;
                            found = s;
                        }
                    }
                }
            }
            return found;
        }

        protected override void draw_background (Cairo.Context cr, int w, int h) {
            paint_pasteboard (cr, 0.955);
        }

        private void path (Cairo.Context cr, Point[] pts, bool closed) {
            if (pts.length == 0) return;
            cr.move_to (pts[0].x, pts[0].y);
            for (int i = 1; i < pts.length; i++) cr.line_to (pts[i].x, pts[i].y);
            if (closed) cr.close_path ();
        }

        private static Point mirror (Point p, Point a, Point b) {
            double dx = b.x - a.x, dy = b.y - a.y;
            double l2 = dx * dx + dy * dy;
            if (l2 < 1e-12) return p;
            double t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2;
            return Point (2 * (a.x + dx * t) - p.x, 2 * (a.y + dy * t) - p.y);
        }

        private void seam_stroke (Cairo.Context cr, Point[] pts, Rgba c, bool selected, bool flip_ticks) {
            cr.set_source_rgba (c.r, c.g, c.b, 1);
            cr.set_line_width ((selected ? 4.5 : 3) / zoom);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            path (cr, pts, false);
            cr.stroke ();
            double len = Polyline.length (pts);
            cr.set_line_width (1.6 / zoom);
            for (int i = 1; i <= 3; i++) {
                double ang;
                var at = Polyline.at_length (pts, len * (flip_ticks ? 4 - i : i) / 4, out ang);
                double reach = (5 + i * 3) / zoom;
                cr.move_to (at.x, at.y);
                cr.line_to (at.x + Math.cos (ang + Math.PI / 2) * reach, at.y + Math.sin (ang + Math.PI / 2) * reach);
                cr.stroke ();
            }
        }

        private static Point[] mirrored (Point[] pts, Point a, Point b) {
            Point[] o = new Point[pts.length];
            for (int i = 0; i < pts.length; i++) o[i] = mirror (pts[i], a, b);
            return o;
        }

        private void both (Cairo.Context cr, PieceGeometry g, Point[] pts) {
            path (cr, pts, false);
            cr.stroke ();
            Point fa, fb;
            if (!fold_line (g, out fa, out fb)) return;
            path (cr, mirrored (pts, fa, fb), false);
            cr.stroke ();
        }

        private void seam_side (Cairo.Context cr, PieceGeometry g, Point[] pts, Rgba c, bool selected, bool flip) {
            var o = offset_of (g.piece.id);
            cr.save ();
            cr.translate (o.x, o.y);
            seam_stroke (cr, pts, c, selected, flip);
            Point fa, fb;
            if (fold_line (g, out fa, out fb)) seam_stroke (cr, mirrored (pts, fa, fb), c, selected, flip);
            cr.restore ();
        }

        protected override void draw_content (Cairo.Context cr) {
            if (result == null) return;
            bool dark = dark_theme ();
            draw_grid (cr, visible_doc (), 10, zoom, dark);
            double ink = dark ? 0.86 : 0.18;
            foreach (var g in result.pieces) {
                if (g.seam.length < 3) continue;
                var f = project.garment.fabric_for (g.piece.id);
                var pts = outline (g);
                var o = offset_of (g.piece.id);
                Point fa, fb;
                bool fold = fold_line (g, out fa, out fb);
                cr.save ();
                cr.translate (o.x, o.y);
                cr.set_source_rgba (f.color.r, f.color.g, f.color.b, 0.94);
                path (cr, pts, true);
                cr.fill ();
                if (fold) {
                    path (cr, mirrored (pts, fa, fb), true);
                    cr.fill ();
                }
                bool sel = g.piece.id == selected_piece;
                if (sel) cr.set_source_rgba (0.16, 0.5, 0.96, 1);
                else cr.set_source_rgba (ink, ink, ink + 0.02, 1);
                cr.set_line_width ((sel ? 2.4 : 1.3) / zoom);
                cr.set_line_join (Cairo.LineJoin.ROUND);
                cr.set_line_cap (Cairo.LineCap.ROUND);
                for (int i = 0; i < g.edges.size; i++) {
                    if (fold && g.piece.fold_edge == i) continue;
                    both (cr, g, g.edges[i].pts);
                }
                if (fold) {
                    cr.set_source_rgba (ink, ink, ink + 0.02, 0.45);
                    cr.set_line_width (1 / zoom);
                    cr.set_dash ({ 6 / zoom, 4 / zoom }, 0);
                    cr.move_to (fa.x, fa.y);
                    cr.line_to (fb.x, fb.y);
                    cr.stroke ();
                    cr.set_dash ({}, 0);
                }
                var b = full_bounds (g);
                var lay = Pango.cairo_create_layout (cr);
                var fd = Pango.FontDescription.from_string ("Sans");
                fd.set_absolute_size (12 / zoom * Pango.SCALE);
                lay.set_font_description (fd);
                lay.set_text (g.piece.pair && !g.piece.on_fold ? _("%s, cut 2").printf (g.piece.name) : g.piece.name, -1);
                Pango.Rectangle ink_rect, logical;
                lay.get_extents (out ink_rect, out logical);
                double tw = logical.width / (double) Pango.SCALE, th = logical.height / (double) Pango.SCALE;
                double lum = 0.299 * f.color.r + 0.587 * f.color.g + 0.114 * f.color.b;
                double tone = lum > 0.55 ? 0.15 : 0.95;
                cr.set_source_rgba (tone, tone, tone + 0.01, 0.75);
                cr.move_to (b.cx () - tw / 2, b.cy () - th / 2);
                Pango.cairo_show_layout (cr, lay);
                cr.restore ();
            }
            for (int s = 0; s < project.garment.seams.size; s++) {
                var sp = project.garment.seams[s];
                var ga = geometry (sp.piece_a);
                var gb = geometry (sp.piece_b);
                if (ga == null || gb == null || sp.edge_a >= ga.edges.size || sp.edge_b >= gb.edges.size) continue;
                var c = seam_color (s);
                bool sel = s == selected_seam;
                var pa = span (ga.edges[sp.edge_a].pts, sp.a0, sp.a1);
                var pb = span (gb.edges[sp.edge_b].pts, sp.b0, sp.b1);
                seam_side (cr, ga, pa, c, sel, sp.a0 > sp.a1);
                seam_side (cr, gb, pb, c, sel, (sp.b0 > sp.b1) != sp.reverse_b);
                if (sel) {
                    var oa = offset_of (sp.piece_a);
                    var ob = offset_of (sp.piece_b);
                    cr.set_source_rgba (c.r, c.g, c.b, 0.7);
                    cr.set_line_width (1 / zoom);
                    cr.set_dash ({ 4 / zoom, 4 / zoom }, 0);
                    double la = Polyline.length (pa), lb = Polyline.length (pb);
                    for (int i = 0; i <= 4; i++) {
                        double ang;
                        var qa = Polyline.at_length (pa, la * i / 4, out ang);
                        var qb = Polyline.at_length (pb, lb * (sp.reverse_b ? 4 - i : i) / 4, out ang);
                        cr.move_to (qa.x + oa.x, qa.y + oa.y);
                        cr.line_to (qb.x + ob.x, qb.y + ob.y);
                    }
                    cr.stroke ();
                    cr.set_dash ({}, 0);
                }
            }
            cr.set_line_cap (Cairo.LineCap.ROUND);
            if (tool != "select" && tool != "edit-sew" && hover_edge >= 0) {
                var g = geometry (hover_piece);
                if (g != null && hover_edge < g.edges.size) {
                    var o = offset_of (hover_piece);
                    cr.save ();
                    cr.translate (o.x, o.y);
                    cr.set_source_rgba (0.16, 0.5, 0.96, 0.85);
                    cr.set_line_width (4 / zoom);
                    var pts = g.edges[hover_edge].pts;
                    bool ranged = tool == "free-sew" && ((free_step == 1 && hover_piece == pending_piece && hover_edge == pending_edge) || (free_step == 3 && hover_piece == free_b_piece && hover_edge == free_b_edge));
                    if (ranged) pts = span (pts, free_step == 1 ? pending_t : free_b0, hover_t);
                    if (tool != "free-sew" || ranged) both (cr, g, pts);
                    if (tool == "free-sew") {
                        double ang;
                        var at = Polyline.at_length (g.edges[hover_edge].pts, hover_t * Polyline.length (g.edges[hover_edge].pts), out ang);
                        cr.arc (at.x, at.y, 4.5 / zoom, 0, 2 * Math.PI);
                        cr.fill ();
                    }
                    cr.restore ();
                }
            }
            if (pending_edge >= 0) {
                var g = geometry (pending_piece);
                if (g != null && pending_edge < g.edges.size) {
                    var o = offset_of (pending_piece);
                    cr.save ();
                    cr.translate (o.x, o.y);
                    cr.set_source_rgba (0.96, 0.55, 0.12, 1);
                    cr.set_line_width (4 / zoom);
                    var pts = g.edges[pending_edge].pts;
                    if (tool == "free-sew") pts = span (pts, pending_t, pending_t2 >= 0 ? pending_t2 : pending_t);
                    both (cr, g, pts);
                    double ang;
                    var at = Polyline.at_length (g.edges[pending_edge].pts, pending_t * Polyline.length (g.edges[pending_edge].pts), out ang);
                    cr.arc (at.x, at.y, 4.5 / zoom, 0, 2 * Math.PI);
                    cr.fill ();
                    cr.restore ();
                }
            }
        }

        protected override void draw_overlay (Cairo.Context cr, int w, int h) {
            cr.save ();
            cr.transform (view_matrix ());
            cr.set_source_rgba (0.16, 0.5, 0.96, 1);
            cr.set_line_width (1.6 / zoom);
            if (tool == "rect" && dragging_rect && draft.length == 1) {
                cr.rectangle (double.min (draft[0].x, draft_at.x), double.min (draft[0].y, draft_at.y), (draft_at.x - draft[0].x).abs (), (draft_at.y - draft[0].y).abs ());
                cr.stroke ();
            }
            if (tool == "polygon" && draft.length > 0) {
                path (cr, draft, false);
                cr.line_to (hover_at.x, hover_at.y);
                cr.stroke ();
                foreach (var q in draft) {
                    cr.arc (q.x, q.y, 4 / zoom, 0, 2 * Math.PI);
                    cr.fill ();
                }
            }
            if (tool == "edit" && result != null) {
                foreach (var g in result.pieces) {
                    var pc = free_piece (g.piece.id);
                    if (pc == null) continue;
                    var o = offset_of (pc.id);
                    for (int i = 0; i < pc.fixed.nodes.length; i++) {
                        var q = pc.fixed.nodes[i];
                        bool active = pc.id == node_piece && i == node_index;
                        cr.set_source_rgba (1, 1, 1, 1);
                        if (pc.fixed.smooth[i]) cr.arc (q.x + o.x, q.y + o.y, (active ? 5.5 : 4.5) / zoom, 0, 2 * Math.PI);
                        else cr.rectangle (q.x + o.x - 4.5 / zoom, q.y + o.y - 4.5 / zoom, 9 / zoom, 9 / zoom);
                        cr.fill_preserve ();
                        if (active) cr.set_source_rgba (0.96, 0.55, 0.12, 1);
                        else cr.set_source_rgba (0.16, 0.5, 0.96, 1);
                        cr.set_line_width (1.8 / zoom);
                        cr.stroke ();
                    }
                }
            }
            cr.restore ();
        }

        private Point hover_at;
        private double free_b0;
        private string free_b_piece = "";
        private int free_b_edge = -1;

        protected override void hover (Point p) {
            hover_at = p;
            if (tool == "polygon" && draft.length > 0) queue_draw ();
            string piece;
            int edge;
            double t;
            edge_under (p, out piece, out edge, out t);
            if (piece != hover_piece || edge != hover_edge || t != hover_t) {
                hover_piece = piece;
                hover_edge = edge;
                hover_t = t;
                queue_draw ();
            }
        }

        private void add_seam (SeamPair sp) {
            project.garment.seams.add (sp);
            selected_seam = project.garment.seams.size - 1;
            project.touch ("garment");
            seams_changed ();
            selection_changed ();
        }

        protected override void press (Point p, uint button, Gdk.ModifierType mods, StrokeSample s) {
            grab_focus ();
            if (button != Gdk.BUTTON_PRIMARY) return;
            string piece;
            int edge;
            double t;
            bool on_edge = edge_under (p, out piece, out edge, out t);
            switch (tool) {
                case "sew":
                    if (!on_edge) {
                        cancel ();
                        break;
                    }
                    if (pending_edge < 0) {
                        pending_piece = piece;
                        pending_edge = edge;
                        pending_t = t;
                        break;
                    }
                    if (pending_piece == piece && pending_edge == edge) {
                        cancel ();
                        break;
                    }
                    var sp = new SeamPair (pending_piece, pending_edge, piece, edge);
                    sp.reverse_b = (pending_t < 0.5) != (t < 0.5);
                    cancel ();
                    add_seam (sp);
                    break;
                case "free-sew":
                    if (!on_edge) {
                        cancel ();
                        break;
                    }
                    if (free_step == 0) {
                        pending_piece = piece;
                        pending_edge = edge;
                        pending_t = t;
                        pending_t2 = -1;
                        free_step = 1;
                    } else if (free_step == 1) {
                        if (piece != pending_piece || edge != pending_edge) break;
                        pending_t2 = t;
                        free_step = 2;
                    } else if (free_step == 2) {
                        free_b_piece = piece;
                        free_b_edge = edge;
                        free_b0 = t;
                        free_step = 3;
                    } else {
                        if (piece != free_b_piece || edge != free_b_edge) break;
                        var sp = new SeamPair (pending_piece, pending_edge, free_b_piece, free_b_edge);
                        sp.a0 = pending_t;
                        sp.a1 = pending_t2;
                        sp.b0 = free_b0;
                        sp.b1 = t;
                        sp.reverse_b = false;
                        cancel ();
                        add_seam (sp);
                    }
                    break;
                case "edit-sew":
                    selected_seam = seam_under (p);
                    selection_changed ();
                    break;
                case "rect":
                    draft = { p };
                    draft_at = p;
                    dragging_rect = true;
                    break;
                case "polygon":
                    if (draft.length >= 3 && draft[0].distance (p) < 10 / zoom) {
                        finish_polygon ();
                        break;
                    }
                    draft += p;
                    draft_at = p;
                    break;
                case "edit":
                    begin_edit (p);
                    break;
                default:
                    int seam = seam_under (p);
                    selected_seam = seam;
                    selected_piece = seam >= 0 ? "" : piece_under (p);
                    selection_changed ();
                    break;
            }
            queue_draw ();
        }

        private Piece? free_piece (string id) {
            var pc = project.pattern.find_piece (id);
            return pc != null && pc.fixed != null && pc.fixed.nodes.length >= 3 ? pc : null;
        }

        private void create_piece (Point[] nodes) {
            var pc = new Piece (project.pattern.new_id ("d"), _("Piece %d").printf (project.pattern.pieces.size + 1));
            pc.fixed = new FixedGeometry ();
            pc.fixed.nodes = nodes;
            pc.fixed.smooth = new bool[nodes.length];
            pc.fixed.rebuild ();
            pc.placement = "front";
            project.pattern.pieces.add (pc);
            selected_piece = pc.id;
            selected_seam = -1;
            commit_pattern ();
            selection_changed ();
        }

        private void commit_pattern () {
            project.touch ("pattern");
            result = project.pattern.evaluate (size);
            layout ();
            pattern_changed ();
            queue_draw ();
        }

        private void finish_polygon () {
            var nodes = draft;
            draft = {};
            if (nodes.length >= 3) create_piece (nodes);
        }

        private void drop_seams (string piece_id) {
            for (int i = project.garment.seams.size - 1; i >= 0; i--) {
                var sp = project.garment.seams[i];
                if (sp.piece_a == piece_id || sp.piece_b == piece_id) project.garment.seams.remove_at (i);
            }
            selected_seam = -1;
        }

        private void begin_edit (Point p) {
            node_piece = "";
            node_index = -1;
            node_moved = false;
            if (result == null) return;
            double best = 10 / zoom;
            foreach (var g in result.pieces) {
                var pc = free_piece (g.piece.id);
                if (pc == null) continue;
                var o = offset_of (pc.id);
                for (int i = 0; i < pc.fixed.nodes.length; i++) {
                    double d = Math.hypot (pc.fixed.nodes[i].x + o.x - p.x, pc.fixed.nodes[i].y + o.y - p.y);
                    if (d < best) {
                        best = d;
                        node_piece = pc.id;
                        node_index = i;
                    }
                }
            }
            if (node_index >= 0) {
                selected_piece = node_piece;
                selection_changed ();
                return;
            }
            string piece;
            int edge;
            double t;
            if (!edge_under (p, out piece, out edge, out t)) return;
            var pc = free_piece (piece);
            if (pc == null) {
                message (_("Only pieces drawn here can be reshaped, drafted pieces follow their formulas"));
                return;
            }
            var o = offset_of (piece);
            var local = Point (p.x - o.x, p.y - o.y);
            int n = pc.fixed.nodes.length;
            int after = 0;
            double near = double.INFINITY;
            for (int i = 0; i < n; i++) {
                double d = PathData.segment_distance (pc.fixed.nodes[i], pc.fixed.nodes[(i + 1) % n], local.x, local.y);
                if (d < near) {
                    near = d;
                    after = i;
                }
            }
            Point[] nodes = {};
            bool[] smooth = {};
            for (int i = 0; i < n; i++) {
                nodes += pc.fixed.nodes[i];
                smooth += pc.fixed.smooth[i];
                if (i == after) {
                    nodes += local;
                    smooth += true;
                }
            }
            pc.fixed.nodes = nodes;
            pc.fixed.smooth = smooth;
            pc.fixed.rebuild ();
            node_piece = piece;
            node_index = after + 1;
            node_moved = true;
            selected_piece = piece;
            result = project.pattern.evaluate (size);
            selection_changed ();
        }

        protected override void move (Point p, Gdk.ModifierType mods, StrokeSample s) {
            if (tool == "rect" && dragging_rect) {
                draft_at = p;
                queue_draw ();
                return;
            }
            if (tool != "edit" || node_index < 0) return;
            var pc = free_piece (node_piece);
            if (pc == null) return;
            var o = offset_of (node_piece);
            pc.fixed.nodes[node_index] = Point (p.x - o.x, p.y - o.y);
            pc.fixed.rebuild ();
            node_moved = true;
            result = project.pattern.evaluate (size);
            queue_draw ();
        }

        protected override void release (Point p, Gdk.ModifierType mods) {
            if (tool == "rect" && dragging_rect) {
                dragging_rect = false;
                var a = draft[0];
                draft = {};
                if ((p.x - a.x).abs () > 20 && (p.y - a.y).abs () > 20) {
                    double x0 = double.min (a.x, p.x), x1 = double.max (a.x, p.x), y0 = double.min (a.y, p.y), y1 = double.max (a.y, p.y);
                    create_piece ({ Point (x0, y0), Point (x1, y0), Point (x1, y1), Point (x0, y1) });
                }
                queue_draw ();
                return;
            }
            if (tool == "edit" && node_index >= 0 && node_moved) {
                node_moved = false;
                commit_pattern ();
            }
        }

        public void toggle_node () {
            var pc = free_piece (node_piece);
            if (pc == null || node_index < 0 || node_index >= pc.fixed.nodes.length) return;
            pc.fixed.smooth[node_index] = !pc.fixed.smooth[node_index];
            pc.fixed.rebuild ();
            drop_seams (pc.id);
            seams_changed ();
            commit_pattern ();
        }

        public void delete_node () {
            var pc = free_piece (node_piece);
            if (pc == null || node_index < 0 || pc.fixed.nodes.length <= 3) return;
            Point[] nodes = {};
            bool[] smooth = {};
            for (int i = 0; i < pc.fixed.nodes.length; i++) {
                if (i == node_index) continue;
                nodes += pc.fixed.nodes[i];
                smooth += pc.fixed.smooth[i];
            }
            bool corner = !pc.fixed.smooth[node_index];
            pc.fixed.nodes = nodes;
            pc.fixed.smooth = smooth;
            pc.fixed.rebuild ();
            node_index = -1;
            if (corner) {
                drop_seams (pc.id);
                seams_changed ();
            }
            commit_pattern ();
        }

        public void delete_piece (string id) {
            var pc = project.pattern.find_piece (id);
            if (pc == null) return;
            drop_seams (id);
            project.pattern.pieces.remove (pc);
            project.garment.piece_fabrics.unset (id);
            if (selected_piece == id) selected_piece = "";
            seams_changed ();
            commit_pattern ();
            selection_changed ();
        }

        public void piece_edited () {
            commit_pattern ();
        }

        public void drag_between (Point a, Point b) {
            hover (a);
            press (a, Gdk.BUTTON_PRIMARY, 0, StrokeSample (a.x, a.y, 1, 0, 0, 0));
            move (b, 0, StrokeSample (b.x, b.y, 1, 0, 0, 0));
            release (b, 0);
        }

        public void click_at (Point p) {
            hover (p);
            press (p, Gdk.BUTTON_PRIMARY, 0, StrokeSample (p.x, p.y, 1, 0, 0, 0));
        }

        public void delete_selected_seam () {
            if (selected_seam < 0 || selected_seam >= project.garment.seams.size) return;
            project.garment.seams.remove_at (selected_seam);
            selected_seam = -1;
            project.touch ("garment");
            seams_changed ();
            selection_changed ();
            queue_draw ();
        }

        public void reverse_selected_seam () {
            if (selected_seam < 0 || selected_seam >= project.garment.seams.size) return;
            var sp = project.garment.seams[selected_seam];
            sp.reverse_b = !sp.reverse_b;
            project.touch ("garment");
            seams_changed ();
            queue_draw ();
        }

        public string seam_title (int index) {
            if (index < 0 || index >= project.garment.seams.size) return "";
            var sp = project.garment.seams[index];
            var a = project.pattern.find_piece (sp.piece_a);
            var b = project.pattern.find_piece (sp.piece_b);
            return "%s %d, %s %d".printf (a != null ? a.name : "?", sp.edge_a + 1, b != null ? b.name : "?", sp.edge_b + 1);
        }

        public double seam_length (int index, bool second) {
            if (index < 0 || index >= project.garment.seams.size) return 0;
            var sp = project.garment.seams[index];
            var g = geometry (second ? sp.piece_b : sp.piece_a);
            int e = second ? sp.edge_b : sp.edge_a;
            if (g == null || e >= g.edges.size) return 0;
            return Polyline.length (g.edges[e].pts) * ((second ? sp.b1 - sp.b0 : sp.a1 - sp.a0).abs ());
        }

        protected override bool key_pressed (uint keyval, Gdk.ModifierType state) {
            switch (keyval) {
                case Gdk.Key.Escape:
                    cancel ();
                    queue_draw ();
                    return true;
                case Gdk.Key.Delete:
                case Gdk.Key.BackSpace:
                    if (tool == "edit") delete_node ();
                    else delete_selected_seam ();
                    return true;
                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    if (tool == "polygon") finish_polygon ();
                    return true;
                case Gdk.Key.c:
                case Gdk.Key.C:
                    if (tool == "edit") toggle_node ();
                    return true;
                case Gdk.Key.s:
                case Gdk.Key.S:
                    choose_tool ("rect");
                    return true;
                case Gdk.Key.h:
                case Gdk.Key.H:
                    choose_tool ("polygon");
                    return true;
                case Gdk.Key.z:
                case Gdk.Key.Z:
                    choose_tool ("edit");
                    return true;
                case Gdk.Key.a:
                case Gdk.Key.A:
                    choose_tool ("select");
                    return true;
                case Gdk.Key.n:
                case Gdk.Key.N:
                    choose_tool ("sew");
                    return true;
                case Gdk.Key.m:
                case Gdk.Key.M:
                    choose_tool ("free-sew");
                    return true;
                case Gdk.Key.b:
                case Gdk.Key.B:
                    choose_tool ("edit-sew");
                    return true;
            }
            return false;
        }

        public override string status_text () {
            switch (tool) {
                case "sew": return pending_edge < 0 ? _("Click the first edge to sew") : _("Click the edge to sew it to, near the matching end");
                case "free-sew":
                    if (free_step == 0) return _("Click where the seam starts");
                    if (free_step == 1) return _("Click where it ends on the same edge");
                    if (free_step == 2) return _("Click where it starts on the other edge");
                    return _("Click where it ends");
                case "edit-sew": return _("Click a seam to select it, Delete removes it");
                case "rect": return _("Drag to draw a rectangular piece");
                case "polygon": return _("Click the corners, close on the first one or press Enter");
                case "edit": return _("Drag a point, drag an edge to curve it, C toggles corner and curve, Delete removes a point");
                default: return _("Click a piece or a seam");
            }
        }
    }
}
