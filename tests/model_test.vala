using Singularity.Vector;
using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

void test_expr () {
    try {
        check (near (Expr.evaluate ("2 + 3 * 4", (n, out v) => { v = 0; return false; }), 14), "precedence");
        check (near (Expr.evaluate ("-2^2", (n, out v) => { v = 0; return false; }), -4), "unary and power");
        check (near (Expr.evaluate ("max(1, 5, 3) + min(4, 2)", (n, out v) => { v = 0; return false; }), 7), "functions");
        check (near (Expr.evaluate ("#a > 2 ? 10 : 20", (n, out v) => { v = n == "#a" ? 3 : 0; return n == "#a"; }), 10), "ternary with variable");
        check (near (Expr.evaluate ("sinD(90) + cosD(0)", (n, out v) => { v = 0; return false; }), 2), "degree trig");
        bool failed = false;
        try {
            Expr.evaluate ("1 +", (n, out v) => { v = 0; return false; });
        } catch (ExprError e) {
            failed = true;
        }
        check (failed, "syntax error detected");
    } catch (ExprError e) {
        check (false, "expr: " + e.message);
    }
}

void test_measurements () {
    var t = MeasurementTable.standard_women ();
    try {
        check (near (t.value ("bust_circ", "38"), 88), "base size value");
        check (near (t.value ("bust_circ", "42"), 96), "graded value two sizes up");
        check (near (t.value ("bust_circ", "34"), 80), "graded value two sizes down");
        t.find ("waist_circ").per_size["40"] = 75.5;
        check (near (t.value ("waist_circ", "40"), 75.5), "explicit size value wins");
        var m = new Measurement ("half_bust");
        m.formula = "bust_circ / 2";
        t.items.add (m);
        check (near (t.value ("half_bust", "38"), 44), "derived measurement");
        check (near (t.value_mm ("half_bust", "38"), 440), "mm conversion");
    } catch (ExprError e) {
        check (false, "measurements: " + e.message);
    }
}

void test_points () {
    var p = new Pattern ();
    p.unit = "cm";
    var a = p.add_point (PointKind.BASE, "A");
    a.fx = "0";
    a.fy = "0";
    var b = p.add_point (PointKind.END_LINE, "B");
    b.a = a.id;
    b.flength = "10";
    b.fangle = "0";
    var c = p.add_point (PointKind.END_LINE, "C");
    c.a = a.id;
    c.flength = "10";
    c.fangle = "270";
    var d = p.add_point (PointKind.ALONG_LINE, "D");
    d.a = a.id;
    d.b = b.id;
    d.flength = "Line_A_B / 4";
    var e = p.add_point (PointKind.NORMAL, "E");
    e.a = b.id;
    e.b = a.id;
    e.flength = "5";
    var f = p.add_point (PointKind.INTERSECT, "F");
    f.a = a.id;
    f.b = b.id;
    f.c = e.id;
    f.d = c.id;
    var g = p.add_point (PointKind.CIRCLE_LINE, "G");
    g.a = a.id;
    g.b = b.id;
    g.c = c.id;
    g.flength = "sqrt(200)";
    var h = p.add_point (PointKind.ROTATE, "H");
    h.a = b.id;
    h.b = a.id;
    h.fangle = "90";
    var i = p.add_point (PointKind.BISECTOR, "I");
    i.a = b.id;
    i.b = a.id;
    i.c = c.id;
    i.flength = "sqrt(2)";
    var r = p.evaluate ();
    check (r.errors.size == 0, "no evaluation errors");
    check (near (r.points[b.id].x, 100) && near (r.points[b.id].y, 0), "end line at 0 degrees");
    check (near (r.points[c.id].x, 0) && near (r.points[c.id].y, 100), "270 degrees points down on screen");
    check (near (r.points[d.id].x, 25), "along line with Line_ formula");
    check (near (r.points[e.id].distance (r.points[b.id]), 50), "normal length");
    check (near (r.points[g.id].x, 100) && near (r.points[g.id].y, 0), "circle and line");
    check (near (r.points[h.id].x, 0) && near (r.points[h.id].y, -100), "rotation counter clockwise is up");
    check (near (r.points[i.id].x, 10, 1e-3) && near (r.points[i.id].y, 10, 1e-3), "bisector");
    try {
        check (near (p.eval_formula ("AngleLine_A_C", "38"), 270), "angle variable");
    } catch (ExprError err) {
        check (false, err.message);
    }
    b.flength = "unknown_measure";
    var r2 = p.evaluate ();
    check (r2.errors.has_key (b.id), "error reported for bad formula");
    check (!r2.points.has_key (d.id) && r2.errors.has_key (d.id), "dependents are reported");
}

void test_tshirt_piece () {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var r = p.evaluate ("38");
    foreach (var e in r.errors.entries) check (false, "tshirt error %s: %s".printf (e.key, e.value));
    check (r.pieces.size == 3, "three pieces");
    foreach (var g in r.pieces) {
        check (g.error == "", "piece %s built: %s".printf (g.piece.name, g.error));
        check (g.seam.length > 4 && g.cut.length > 4, "piece %s has outlines".printf (g.piece.name));
        double sa = Polyline.signed_area (g.seam).abs ();
        double ca = Polyline.signed_area (g.cut).abs ();
        check (ca > sa, "cut line encloses seam line for %s".printf (g.piece.name));
    }
    var front = r.pieces[0];
    var b = front.bounds ();
    double expected_w = (88.0 / 4 + 1) * 10;
    check (b.w > expected_w && b.w < expected_w + 40, "front width follows bust %f".printf (b.w));
    check (front.notches.size == 1, "front has a notch");
    var big = p.evaluate ("46");
    check (big.pieces[0].bounds ().w > b.w + 30, "size 46 is wider");
}

void test_seam_allowance () {
    var p = new Pattern ();
    p.unit = "mm";
    string[] names = { "A", "B", "C", "D" };
    double[,] xy = { { 0, 0 }, { 100, 0 }, { 100, 50 }, { 0, 50 } };
    var piece = new Piece ("d1", "Square");
    for (int k = 0; k < 4; k++) {
        var pt = p.add_point (PointKind.BASE, names[k]);
        pt.fx = xy[k, 0].to_string ();
        pt.fy = xy[k, 1].to_string ();
        piece.nodes.add (new PieceNode (pt.id));
    }
    piece.seam_allowance = "10";
    piece.nodes[2].sa_after = "30";
    p.pieces.add (piece);
    var g = p.evaluate ().pieces[0];
    var r = Rect.empty ();
    foreach (var q in g.cut) r = r.include (q.x, q.y);
    check (near (r.x, -10) && near (r.y, -10) && near (r.x2 (), 110) && near (r.y2 (), 80), "per edge allowance %f %f %f %f".printf (r.x, r.y, r.x2 (), r.y2 ()));
    piece.nodes[0].corner = CornerStyle.BEVEL;
    var g2 = p.evaluate ().pieces[0];
    check (g2.cut.length == 5, "bevel corner adds a point");
    check (g.edges.size == 4, "four edges");
    check (near (g.edge_length (0), 100), "edge length");
}

void test_darts () {
    var p = new Pattern ();
    p.unit = "mm";
    var a = p.add_point (PointKind.BASE, "A");
    var b = p.add_point (PointKind.BASE, "B");
    b.fx = "100";
    var l1 = p.add_point (PointKind.BASE, "L1");
    l1.fx = "100";
    l1.fy = "40";
    var ap = p.add_point (PointKind.BASE, "AP");
    ap.fx = "60";
    ap.fy = "50";
    var l2 = p.add_point (PointKind.BASE, "L2");
    l2.fx = "100";
    l2.fy = "60";
    var c = p.add_point (PointKind.BASE, "C");
    c.fx = "100";
    c.fy = "100";
    var d = p.add_point (PointKind.BASE, "D");
    d.fy = "100";
    var x = p.add_point (PointKind.BASE, "X");
    x.fx = "50";
    x.fy = "100";
    var piece = new Piece ("d1", "Bodice");
    foreach (var id in new string[] { a.id, b.id, l1.id, ap.id, l2.id, c.id, x.id, d.id }) piece.nodes.add (new PieceNode (id));
    piece.seam_allowance = "0";
    p.pieces.add (piece);
    var before = p.evaluate ();
    double ang = DartTools.dart_angle (before, p, ap.id, l1.id, l2.id);
    check (ang.abs () > 10, "dart has an angle");
    try {
        DartTools.transfer (p, piece, ap.id, l1.id, l2.id, x.id);
    } catch (PatternOpError e) {
        check (false, e.message);
    }
    var after = p.evaluate ();
    foreach (var e in after.errors.entries) check (false, "dart error " + e.value);
    var g = after.pieces[0];
    check (g.error == "", "piece after transfer " + g.error);
    int apex_count = 0;
    foreach (var nd in piece.nodes) if (nd.ref_id == ap.id) apex_count++;
    check (apex_count == 1, "apex appears once");
    var first = after.points[piece.nodes[0].ref_id];
    check (near (first.distance (after.points[l1.id]), 40, 1e-6), "old dart closed: the rotated side meets leg one");
    bool opened = false;
    for (int i = 0; i < piece.nodes.size; i++) if (piece.nodes[i].ref_id == ap.id) opened = after.points[piece.nodes[(i + 1) % piece.nodes.size].ref_id].distance (after.points[x.id]) < 1e-6;
    check (opened, "new dart opens at the target");
}

void test_seam_walk () {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var r = p.evaluate ("38");
    var front = r.pieces[0];
    var back = r.pieces[1];
    var pair = new SeamPair (front.piece.id, 2, back.piece.id, 2);
    pair.reverse_b = false;
    var chk = Seams.walk (r, pair);
    check (chk != null, "seam walk result");
    check (near (chk.length_a, front.edge_length (2)), "walk length a");
    check (chk.matches (1.0), "shoulders match %f %f".printf (chk.length_a, chk.length_b));
    var guessed = Seams.guess_pairs (r);
    check (guessed.size >= 2, "guessed seams %d".printf (guessed.size));
}

void test_grading_rules () {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var by_size = Grading.nest (p);
    Grading.derive_rules (p, by_size);
    check (p.rules.rules.size > 0, "rules derived");
    p.grading = "rules";
    foreach (var size in p.table.sizes) {
        var rr = p.evaluate (size);
        var mm = by_size[size];
        foreach (var pt in p.points) {
            if (!rr.points.has_key (pt.id) || !mm.points.has_key (pt.id)) continue;
            if (pt.kind != PointKind.BASE && pt.kind != PointKind.END_LINE && pt.kind != PointKind.OFFSET) continue;
        }
        var ga = rr.pieces[0].bounds ();
        var gb = mm.pieces[0].bounds ();
        check (near (ga.w, gb.w, 15), "rule graded width close to measurement grading in %s: %f vs %f".printf (size, ga.w, gb.w));
    }
    var rule = new GradeRule (99);
    rule.set_uniform (p.table, 5, -2);
    p.rules.rules.add (rule);
    var dlt = p.rules.delta (99, "44", p.table);
    check (near (dlt.x, 15) && near (dlt.y, -6), "cumulative rule delta up");
    var dn = p.rules.delta (99, "34", p.table);
    check (near (dn.x, -10) && near (dn.y, 4), "cumulative rule delta down");
}

void test_marker () {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var s = new MarkerSettings ();
    s.fabric_width = 1500;
    s.resolution = 10;
    var res = Marker.compute (p, s);
    check (res.unplaced == 0, "all pieces placed");
    check (res.placements.size == 4, "front, back and two sleeves placed, got %d".printf (res.placements.size));
    check (res.efficiency () > 40 && res.efficiency () <= 100, "efficiency %f".printf (res.efficiency ()));
    for (int i = 0; i < res.placements.size; i++) {
        foreach (var q in res.placements[i].outline) check (q.y >= -1 && q.y <= s.fabric_width + 1, "inside fabric width");
    }
    for (int i = 0; i < res.placements.size; i++) for (int j = i + 1; j < res.placements.size; j++) {
        var a = new PathData ();
        a.add_polygon (res.placements[i].outline, true);
        var b = new PathData ();
        b.add_polygon (res.placements[j].outline, true);
        double overlap = PathBoolean.area (PathBoolean.apply (a, b, BoolOp.INTERSECT));
        check (overlap < 50, "pieces do not overlap (%f mm2)".printf (overlap));
    }
}

void test_solids () {
    var p = new Pattern ();
    var cone = Solid.truncated_cone (p, 200, 300, 250, 0);
    var body = cone[0].fixed.seam;
    double top = 0, bottom = 0;
    for (int i = 0; i < body.length / 2 - 1; i++) bottom += body[i].distance (body[i + 1]);
    for (int i = body.length / 2; i < body.length - 1; i++) top += body[i].distance (body[i + 1]);
    check (near (bottom, Math.PI * 300, 2), "cone outer arc equals the large circumference %f".printf (bottom));
    check (near (top, Math.PI * 200, 2), "cone inner arc equals the small circumference %f".printf (top));
    var cyl = Solid.cylinder (p, 100, 300, 10);
    check (near (cyl[0].fixed.seam[1].x, Math.PI * 100, 0.01), "cylinder wrap length");
}

void test_fixed_length () {
    var p = new Pattern ();
    p.unit = "mm";
    var a = p.add_point (PointKind.BASE, "A");
    var b = p.add_point (PointKind.BASE, "B");
    b.fx = "100";
    var m = p.add_point (PointKind.BASE, "M");
    m.fx = "50";
    m.fy = "20";
    var c = p.add_curve ({ a.id, m.id, b.id }, CurveKind.AUTO);
    c.target_length = "130";
    var r = p.evaluate ();
    check (!r.errors.has_key (c.id), "fixed length curve evaluates");
    double l = 0;
    foreach (var bz in r.curves[c.id]) l += bz.length ();
    check (near (l, 130, 0.05), "curve reaches its length %f".printf (l));
    c.target_length = "50";
    check (p.evaluate ().errors.has_key (c.id), "impossible length reported");
}

Piece square_piece (Pattern p, string id, double w, double h) {
    var piece = new Piece (id, "Panel");
    double[,] xy = { { 0, 0 }, { w, 0 }, { w, h }, { 0, h } };
    for (int k = 0; k < 4; k++) {
        var pt = p.add_point (PointKind.BASE, "%s%d".printf (id, k));
        pt.fx = xy[k, 0].to_string ();
        pt.fy = xy[k, 1].to_string ();
        piece.nodes.add (new PieceNode (pt.id));
    }
    p.pieces.add (piece);
    return piece;
}

Rect bounds_of (Point[] pts) {
    var r = Rect.empty ();
    foreach (var q in pts) r = r.include (q.x, q.y);
    return r;
}

void test_leather () {
    var p = new Pattern ();
    p.unit = "mm";
    var piece = square_piece (p, "L", 100, 50);
    piece.thickness = 2;
    Leather.apply_turn (p, piece, "8");
    var g = p.evaluate ().pieces[0];
    var r = bounds_of (g.cut);
    check (near (r.x, -11) && near (r.x2 (), 111) && near (r.y2 (), 61), "turn allowance adds one and a half thicknesses: %.1f to %.1f".printf (r.x, r.x2 ()));
    var re = Leather.reinforcement (p, g, 5);
    var rr = bounds_of (re.fixed.seam);
    check (near (rr.x, 5) && near (rr.y, 5) && near (rr.x2 (), 95) && near (rr.y2 (), 45) && re.material == "reinforcement", "reinforcement inset by 5 mm inside the seam line");
    var li = Leather.lining (p, g, 2);
    var lr = bounds_of (li.fixed.seam);
    var lc = bounds_of (li.fixed.cut);
    check (near (lr.x, 2) && near (lr.x2 (), 98) && near (lc.x, -8) && near (lc.x2 (), 108) && li.material == "lining", "lining eased by 2 mm with a 10 mm seam allowance");
    var skive = Leather.skive_line (g, 15);
    var sr = bounds_of (skive);
    check (skive.length >= 4 && near (sr.x, r.x + 15) && near (sr.x2 (), r.x2 () - 15), "skive line 15 mm inside the cut edge");
    double[] ink = {};
    foreach (string width in new string[] { "", "15" }) {
        piece.leather_skive = width;
        var surface = new Cairo.ImageSurface (Cairo.Format.RGB24, 300, 200);
        var cr = new Cairo.Context (surface);
        cr.set_source_rgb (1, 1, 1);
        cr.paint ();
        cr.scale (2, 2);
        cr.translate (20, 20);
        var st = new PatternStyle ();
        st.zoom = 2;
        PatternRenderer.draw_piece (cr, p.evaluate ().pieces[0], st, "M");
        surface.flush ();
        unowned uchar[] data = surface.get_data ();
        double dark = 0;
        for (int y = 70; y < 110; y++) {
            int o = y * surface.get_stride () + 48 * 4;
            dark += 255 - (data[o] + data[o + 1] + data[o + 2]) / 3.0;
        }
        ink += dark;
    }
    piece.leather_skive = "";
    check (ink[1] > ink[0] + 200, "skiving line drawn inside the piece (%.0f against %.0f)".printf (ink[1], ink[0]));
    var bag = Solid.box_bag (p, 200, 100, 50, "two-piece", 10);
    var wrap = bounds_of (bag[0].fixed.seam);
    var side = bounds_of (bag[1].fixed.seam);
    check (bag.size == 2 && bag[1].quantity == 2 && near (wrap.h, 2 * side.h + side.w), "box bag wrap panel matches the three sewn edges of the side panel (%.0f mm)".printf (wrap.h));
}

void test_proofing () {
    var profiles = ColorManager.system_profiles ();
    string? cmyk = null;
    foreach (var path in profiles) if (path.has_suffix ("default_cmyk.icc")) cmyk = path;
    if (cmyk == null || !ColorManager.available ()) {
        print ("skip proofing: no CMYK profile installed\n");
        return;
    }
    bool oog;
    var green = ColorManager.soft_proof (Rgba (0, 1, 0, 1), cmyk, out oog);
    check (oog && (green.g < 0.95 || green.r > 0.05), "pure screen green is out of the CMYK gamut (%.2f %.2f %.2f)".printf (green.r, green.g, green.b));
    bool oog2;
    var grey = ColorManager.soft_proof (Rgba (0.5, 0.5, 0.5, 1), cmyk, out oog2);
    check (!oog2, "mid grey stays inside the gamut (%.2f %.2f %.2f)".printf (grey.r, grey.g, grey.b));
}

int main () {
    test_fixed_length ();
    test_expr ();
    test_measurements ();
    test_points ();
    test_tshirt_piece ();
    test_seam_allowance ();
    test_leather ();
    test_proofing ();
    test_darts ();
    test_seam_walk ();
    test_grading_rules ();
    test_marker ();
    test_solids ();
    return finish ("model");
}
