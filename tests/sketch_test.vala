using Singularity.Vector;
using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

void test_brush () {
    var b = new Brush ("t", "t", BrushKind.INK);
    b.size = 4;
    b.min_size = 1;
    check (b.width_for (StrokeSample (0, 0, 1), 0) > b.width_for (StrokeSample (0, 0, 0.2), 0), "pressure widens the line");
    b.tilt_size = 1;
    check (b.width_for (StrokeSample (0, 0, 0.5, 0.8, 0), 0) > b.width_for (StrokeSample (0, 0, 0.5), 0), "tilt widens the line");
    b.velocity_thin = 0.5;
    check (b.width_for (StrokeSample (0, 0, 0.5), 2000) < b.width_for (StrokeSample (0, 0, 0.5), 0), "speed thins the line");
    var pencil = Brush.presets ()[0];
    check (pencil.alpha_for (StrokeSample (0, 0, 0.1)) < pencil.alpha_for (StrokeSample (0, 0, 1)), "pencil opacity follows pressure");
}

void test_guides () {
    var g = new Guides ();
    g.ruler_on = true;
    g.ruler_a = Point (0, 100);
    g.ruler_b = Point (100, 100);
    var sn = new GuideSnapper (g, Point (10, 105), 1);
    check (sn.active, "stroke near the ruler snaps");
    var q = sn.apply (Point (50, 130));
    check (near (q.y, 100) && near (q.x, 50), "points are projected on the ruler");
    var far = new GuideSnapper (g, Point (10, 300), 1);
    check (!far.active, "stroke far from guides is free");
    g.ruler_on = false;
    g.ellipse_on = true;
    g.ellipse_center = Point (0, 0);
    g.ellipse_rx = 100;
    g.ellipse_ry = 50;
    var e = g.project_ellipse (Point (0, 80));
    check (near (e.y, 50, 0.01) && near (e.x, 0, 0.01), "ellipse projection");
    var e2 = g.project_ellipse (Point (150, 0));
    check (near (e2.x, 100, 0.01), "ellipse projection on major axis");
    g.ellipse_on = false;
    g.perspective = 2;
    g.vp1 = Point (-1000, 0);
    g.vp2 = Point (1000, 0);
    var ps = new GuideSnapper (g, Point (0, 200), 1);
    ps.apply (Point (0, 200));
    var pa = ps.apply (Point (0, 260));
    check (near (pa.x, 0, 0.5), "vertical axis in two point perspective");
    var ps2 = new GuideSnapper (g, Point (0, 200), 1);
    ps2.apply (Point (0, 200));
    var pb = ps2.apply (Point (80, 186));
    var pc = ps2.apply (Point (200, 160));
    double t1 = (pb.y - 200) / pb.x, t2 = (pc.y - 200) / pc.x;
    check (near (t1, t2, 1e-6) && near (t1, -0.2, 1e-6), "stroke converges to the vanishing point");
    g.perspective = 0;
    g.curve_on = true;
    var cp = g.curve_path ();
    var near_pt = g.project_path (cp, Point (g.curve_pos.x + 5, g.curve_pos.y + 5));
    check (cp.distance_to (near_pt.x, near_pt.y) < 0.5, "french curve projection lands on the template");
}

void test_symmetry () {
    var g = new Guides ();
    g.symmetry = SymmetryMode.VERTICAL;
    g.symmetry_center = Point (100, 0);
    var m = g.symmetry_transforms ();
    check (m.size == 1, "one mirror");
    double x = 30, y = 5;
    m[0].transform_point (ref x, ref y);
    check (near (x, 170) && near (y, 5), "mirrored across the axis");
    g.symmetry = SymmetryMode.RADIAL;
    g.radial_count = 6;
    check (g.symmetry_transforms ().size == 5, "radial copies");
}

void test_recognizer () {
    Point[] line = {};
    for (int i = 0; i <= 40; i++) line += Point (i * 5, i * 2 + Math.sin (i) * 0.8);
    Point[] res;
    check (StrokeRecognizer.guess (line, out res) == ShapeGuess.LINE && res.length == 2, "wobbly line becomes a straight line");
    Point[] arc = {};
    for (int i = 0; i <= 40; i++) {
        double a = Math.PI * i / 60;
        arc += Point (100 * Math.cos (a), 100 * Math.sin (a));
    }
    check (StrokeRecognizer.guess (arc, out res) == ShapeGuess.ARC, "arc recognised");
    foreach (var p in res) check (near (Math.hypot (p.x, p.y), 100, 0.5), "arc radius");
    Point[] ell = {};
    for (int i = 0; i <= 60; i++) {
        double a = 2 * Math.PI * i / 60;
        ell += Point (80 * Math.cos (a) + 3, 40 * Math.sin (a));
    }
    check (StrokeRecognizer.guess (ell, out res) == ShapeGuess.ELLIPSE, "ellipse recognised");
    Point[] scrib = {};
    for (int i = 0; i <= 60; i++) scrib += Point (i * 3, (i % 7) * 12);
    check (StrokeRecognizer.guess (scrib, out res) == ShapeGuess.NONE, "scribble left alone");
    var smooth = StrokeRecognizer.predictive (line, 1.5);
    check (smooth.length >= 2, "predictive stroke produces a curve");
}

void test_stabilizer () {
    var sm = new Smoother (0.8);
    double maxdev = 0;
    for (int i = 0; i < 100; i++) {
        var o = sm.push (StrokeSample (i, (i % 2 == 0 ? 5 : -5), 1));
        if (i > 10) maxdev = double.max (maxdev, o.y.abs ());
    }
    check (maxdev < 2, "stabilizer removes jitter (%f)".printf (maxdev));
}

void test_render () {
    var sk = new Sketch ();
    var layer = sk.layers[0];
    foreach (var b in sk.brushes) {
        var st = new Stroke.from_brush (b, Rgba (0, 0, 0, 1));
        for (int i = 0; i < 30; i++) st.samples.add (StrokeSample (20 + i * 4, 50 + sk.brushes.index_of (b) * 20, 0.8, 0, 0, i * 0.01));
        layer.strokes.add (st);
    }
    var eraser = layer.strokes[layer.strokes.size - 1];
    Rect area;
    var img = SketchRenderer.render_image (sk, 1, out area);
    img.flush ();
    unowned uint8[] d = img.get_data ();
    int dark = 0;
    int total = img.get_stride () * img.get_height ();
    for (int i = 0; i < total; i += 4) if (d[i] < 128) dark++;
    check (dark > 150, "strokes painted pixels (%d)".printf (dark));
    check (eraser.kind == BrushKind.ERASER, "eraser stroke present");
    var st = layer.strokes[0];
    var copy = st.copy ();
    copy.transform (Cairo.Matrix (2, 0, 0, 2, 0, 0));
    check (near (copy.samples[3].x, st.samples[3].x * 2) && near (copy.size, st.size * 2), "strokes stay editable vectors");
}

void test_digitize () {
    var photo = new Cairo.ImageSurface (Cairo.Format.ARGB32, 800, 600);
    var cr = new Cairo.Context (photo);
    cr.set_source_rgb (0.25, 0.3, 0.28);
    cr.paint ();
    Point[] quad = { Point (120, 80), Point (690, 110), Point (650, 520), Point (150, 500) };
    var h = Digitizer.homography ({ Point (0, 0), Point (297, 0), Point (297, 210), Point (0, 210) }, quad);
    Point[] piece = { Point (60, 40), Point (220, 40), Point (220, 150), Point (60, 150) };
    cr.set_source_rgb (0.95, 0.93, 0.88);
    for (int i = 0; i < 4; i++) {
        var q = Digitizer.apply (h, piece[i]);
        if (i == 0) cr.move_to (q.x, q.y);
        else cr.line_to (q.x, q.y);
    }
    cr.close_path ();
    cr.fill ();
    var d = new Digitizer (photo);
    d.markers = quad;
    string err;
    var outline = d.outline_at (Point (140, 95), out err);
    check (outline != null, "digitized outline: " + err);
    if (outline != null) {
        double area = Polyline.signed_area (outline).abs ();
        check ((area - 160 * 110).abs () / (160 * 110) < 0.03, "digitized area within 3%% (%f)".printf (area));
        var r = Rect.empty ();
        foreach (var p in outline) r = r.include (p.x, p.y);
        check (near (r.x, 60, 1.5) && near (r.x2 (), 220, 1.5) && near (r.y, 40, 1.5), "digitized position in millimetres");
    }
}

void test_fill () {
    var sk = new Sketch ();
    var st = new Stroke.from_brush (sk.brushes[1], Rgba (0, 0, 0, 1));
    st.size = 2;
    st.pressure_size = false;
    st.smooth_curve = false;
    foreach (var p in new Point[] { Point (10, 10), Point (110, 10), Point (110, 80), Point (10, 80), Point (10, 10) }) st.samples.add (StrokeSample (p.x, p.y, 1));
    sk.layers[0].strokes.add (st);
    var path = RegionFill.region (sk, sk.layers[0], Point (50, 40), 0.3, 0.5);
    check (path != null, "closed area filled");
    if (path != null) check ((PathBoolean.area (path) - 100 * 70).abs () < 700, "fill area close to the inside (%f)".printf (PathBoolean.area (path)));
    check (RegionFill.region (sk, sk.layers[0], Point (200, 200), 0.3, 0.5) == null, "outside fill refused");
}

void test_nurbs () {
    var c = NurbsCurve.circle (Vec3 (0, 0, 0), 50, Vec3 (1, 0, 0), Vec3 (0, 1, 0));
    double worst = 0;
    for (int i = 0; i <= 200; i++) worst = double.max (worst, (c.eval (i / 200.0).length () - 50).abs ());
    check (worst < 1e-9, "rational circle is exact (%g)".printf (worst));
    check (near (c.length (2000), 2 * Math.PI * 50, 0.01), "circle length");
    check (near (c.curvature (0.3), 1.0 / 50, 1e-4), "circle curvature");
    var pts = new Gee.ArrayList<Vec3?> ();
    foreach (var x in new double[] { 0, 10, 20, 30, 40 }) pts.add (Vec3 (x, 0, 0));
    var line = NurbsCurve.through (pts);
    check (near (line.eval (0.5).x, 20, 1e-9) && near (line.curvature (0.5), 0, 1e-9), "clamped spline through collinear points");
    var q1 = new Gee.ArrayList<Vec3?> ();
    q1.add (Vec3 (0, 0, 0)); q1.add (Vec3 (10, 0, 0)); q1.add (Vec3 (20, 0, 0));
    var q2 = new Gee.ArrayList<Vec3?> ();
    q2.add (Vec3 (20, 0, 0)); q2.add (Vec3 (30, 0, 0)); q2.add (Vec3 (40, 0, 0));
    check (ContinuityCheck.between (NurbsCurve.through (q1, 2), NurbsCurve.through (q2, 2)) == Continuity.G2, "straight join is G2");
    var q3 = new Gee.ArrayList<Vec3?> ();
    q3.add (Vec3 (20, 0, 0)); q3.add (Vec3 (20, 10, 0)); q3.add (Vec3 (20, 20, 0));
    check (ContinuityCheck.between (NurbsCurve.through (q1, 2), NurbsCurve.through (q3, 2)) == Continuity.G0, "corner join is G0");
    var arc = NurbsCurve.circle (Vec3 (20, 50, 0), 50, Vec3 (0, -1, 0), Vec3 (1, 0, 0));
    check (ContinuityCheck.between (NurbsCurve.through (q1, 2), arc) == Continuity.G1, "line into arc is only G1");
}

void test_timelapse () {
    var sk = new Sketch ();
    for (int k = 0; k < 6; k++) {
        var st = new Stroke.from_brush (sk.brushes[1], Rgba (0, 0, 0, 1));
        for (int i = 0; i < 10; i++) st.samples.add (StrokeSample (10 + i * 10, 20 + k * 15, 0.8));
        sk.layers[0].strokes.add (st);
        sk.timelapse.add (new TimelapseEvent (sk.layers[0].id, k, k));
    }
    check (Timelapse.ordered (sk).size == 6, "time-lapse order covers every stroke");
    string dir = tmp_dir ();
    var loop = new MainLoop ();
    string? result = null;
    string? error = null;
    Timelapse.export.begin (sk, dir, null, (o, r) => {
        try {
            result = Timelapse.export.end (r);
        } catch (Error e) {
            error = e.message;
        }
        loop.quit ();
    });
    loop.run ();
    if (error != null && error.contains ("not available")) {
        stderr.printf ("time-lapse video skipped: %s\n", error);
        return;
    }
    check (result != null && FileUtils.test (result, FileTest.EXISTS), "time-lapse video written: %s".printf (error ?? ""));
    if (result != null) {
        uint8[] data;
        try {
            FileUtils.get_data (result, out data);
            check (data.length > 200 && data[0] == 0x1a && data[1] == 0x45 && data[2] == 0xdf && data[3] == 0xa3, "webm header");
        } catch (Error e) {
            check (false, e.message);
        }
    }
}

int main () {
    test_timelapse ();
    test_nurbs ();
    test_digitize ();
    test_fill ();
    test_brush ();
    test_guides ();
    test_symmetry ();
    test_recognizer ();
    test_stabilizer ();
    test_render ();
    return finish ("sketch");
}
