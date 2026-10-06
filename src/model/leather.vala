using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class Leather {
        public static double turn_allowance (double turn, double thickness) {
            return turn + thickness * 1.5;
        }

        public static void apply_turn (Pattern pattern, Piece piece, string turn_formula) {
            piece.leather_turn = turn_formula;
            piece.built_in = false;
            string t = piece.thickness > 0 ? "(%s) + %s".printf (turn_formula, PathData.fmt (piece.thickness * 1.5 / pattern.unit_mm (), 4)) : turn_formula;
            piece.seam_allowance = t;
        }

        public static FixedGeometry inset (PieceGeometry g, double margin) {
            var fg = new FixedGeometry ();
            var edges = new Gee.ArrayList<OffsetEdge> ();
            foreach (var e in g.edges) edges.add (new OffsetEdge (e.pts, -margin));
            fg.seam = Offset.closed (edges);
            fg.cut = fg.seam;
            fg.grain_a = g.grain_a;
            fg.grain_b = g.grain_b;
            fg.has_grain = g.has_grain;
            return fg;
        }

        public static Piece reinforcement (Pattern pattern, PieceGeometry g, double margin, string material = "reinforcement") {
            var p = new Piece (pattern.new_id ("d"), _("%s Reinforcement").printf (g.piece.name));
            p.material = material;
            p.quantity = g.piece.quantity;
            p.fixed = inset (g, margin);
            p.built_in = true;
            pattern.pieces.add (p);
            return p;
        }

        public static Piece lining (Pattern pattern, PieceGeometry g, double ease) {
            var p = new Piece (pattern.new_id ("d"), _("%s Lining").printf (g.piece.name));
            p.material = "lining";
            p.quantity = g.piece.quantity;
            var fg = inset (g, ease);
            var edges = new Gee.ArrayList<OffsetEdge> ();
            edges.add (new OffsetEdge (fg.seam, 10));
            fg.cut = Offset.closed (split_edges (fg.seam, 10));
            p.fixed = fg;
            pattern.pieces.add (p);
            return p;
        }

        private static Gee.ArrayList<OffsetEdge> split_edges (Point[] ring, double w) {
            var list = new Gee.ArrayList<OffsetEdge> ();
            for (int i = 0; i < ring.length; i++) list.add (new OffsetEdge ({ ring[i], ring[(i + 1) % ring.length] }, w));
            return list;
        }

        public static Point[] skive_line (PieceGeometry g, double width) {
            return Offset.polyline (close (g.cut), -width * (Polyline.signed_area (g.cut) >= 0 ? 1 : -1));
        }

        private static Point[] close (Point[] ring) {
            if (ring.length == 0) return ring;
            Point[] r = ring;
            r += ring[0];
            return r;
        }
    }

    public class Solid {
        public static Gee.ArrayList<Piece> box_bag (Pattern pattern, double w, double h, double d, string style, double sa) {
            var list = new Gee.ArrayList<Piece> ();
            if (style == "boxed-corners") {
                double cut = d / 2;
                var body = fixed_piece (pattern, _("Body"), {
                    Point (0, 0), Point (w + d, 0), Point (w + d, h + cut), Point (w + d - cut, h + cut), Point (w + d - cut, h + cut + cut),
                    Point (cut, h + cut + cut), Point (cut, h + cut), Point (0, h + cut)
                }, sa);
                body.quantity = 2;
                list.add (body);
            } else if (style == "two-piece") {
                list.add (fixed_piece (pattern, _("Wrap Panel"), { Point (0, 0), Point (w, 0), Point (w, 2 * h + d), Point (0, 2 * h + d) }, sa));
                var side = fixed_piece (pattern, _("Side Panel"), { Point (0, 0), Point (d, 0), Point (d, h), Point (0, h) }, sa);
                side.quantity = 2;
                list.add (side);
            } else {
                var front = fixed_piece (pattern, _("Front and Back"), { Point (0, 0), Point (w, 0), Point (w, h), Point (0, h) }, sa);
                front.quantity = 2;
                list.add (front);
                list.add (fixed_piece (pattern, _("Gusset"), { Point (0, 0), Point (d, 0), Point (d, 2 * h + w), Point (0, 2 * h + w) }, sa));
            }
            return list;
        }

        public static Gee.ArrayList<Piece> cylinder (Pattern pattern, double diameter, double length, double sa) {
            var list = new Gee.ArrayList<Piece> ();
            double circ = Math.PI * diameter;
            list.add (fixed_piece (pattern, _("Body"), { Point (0, 0), Point (circ, 0), Point (circ, length), Point (0, length) }, sa));
            Point[] circle = {};
            for (int i = 0; i < 96; i++) {
                double a = 2 * Math.PI * i / 96;
                circle += Point (diameter / 2 + diameter / 2 * Math.cos (a), diameter / 2 + diameter / 2 * Math.sin (a));
            }
            var end = fixed_piece (pattern, _("End Panel"), circle, sa);
            end.quantity = 2;
            list.add (end);
            return list;
        }

        public static Gee.ArrayList<Piece> truncated_cone (Pattern pattern, double top_d, double bottom_d, double height, double sa) {
            var list = new Gee.ArrayList<Piece> ();
            double r1 = top_d / 2, r2 = bottom_d / 2;
            double slant = Math.sqrt (height * height + (r1 - r2) * (r1 - r2));
            Point[] ring = {};
            if ((r1 - r2).abs () < 1e-6) {
                double circ = 2 * Math.PI * r1;
                ring = { Point (0, 0), Point (circ, 0), Point (circ, slant), Point (0, slant) };
            } else {
                double big = double.max (r1, r2), small = double.min (r1, r2);
                double outer = slant * big / (big - small);
                double inner = outer - slant;
                double theta = 2 * Math.PI * big / outer;
                int steps = 96;
                for (int i = 0; i <= steps; i++) {
                    double a = -Math.PI / 2 - theta / 2 + theta * i / steps;
                    ring += Point (outer * Math.cos (a), outer * Math.sin (a) + outer);
                }
                for (int i = steps; i >= 0; i--) {
                    double a = -Math.PI / 2 - theta / 2 + theta * i / steps;
                    ring += Point (inner * Math.cos (a), inner * Math.sin (a) + outer);
                }
            }
            list.add (fixed_piece (pattern, _("Body"), ring, sa));
            Point[] circle = {};
            double rb = r2;
            for (int i = 0; i < 96; i++) {
                double a = 2 * Math.PI * i / 96;
                circle += Point (rb + rb * Math.cos (a), rb + rb * Math.sin (a));
            }
            list.add (fixed_piece (pattern, _("Base"), circle, sa));
            return list;
        }

        public static Piece fixed_piece (Pattern pattern, string name, Point[] seam, double sa) {
            var p = new Piece (pattern.new_id ("d"), name);
            var fg = new FixedGeometry ();
            fg.seam = seam;
            var edges = new Gee.ArrayList<OffsetEdge> ();
            for (int i = 0; i < seam.length; i++) edges.add (new OffsetEdge ({ seam[i], seam[(i + 1) % seam.length] }, sa));
            fg.cut = sa > 0 ? Offset.closed (edges) : seam;
            var b = Rect.empty ();
            foreach (var q in seam) b = b.include (q.x, q.y);
            fg.grain_a = Point (b.cx (), b.y + b.h * 0.2);
            fg.grain_b = Point (b.cx (), b.y + b.h * 0.8);
            fg.has_grain = true;
            p.fixed = fg;
            pattern.pieces.add (p);
            return p;
        }

        public static double area_of (Point[] ring) {
            return Polyline.signed_area (ring).abs ();
        }
    }
}
