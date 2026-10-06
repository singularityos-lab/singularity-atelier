using Singularity.Vector;
using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

Project sample () {
    var p = Project.create ("fashion");
    p.title = "Test Tee";
    var layer = p.sketch.layers[0];
    var st = new Stroke.from_brush (p.sketch.brushes[0], Rgba (0.2, 0.1, 0.05, 1));
    for (int i = 0; i < 20; i++) st.samples.add (StrokeSample (10 + i * 5, 20 + Math.sin (i * 0.3) * 10, 0.2 + i * 0.03, 0.1, 0.2, i * 0.01));
    layer.strokes.add (st);
    var fill = new FillRegion ();
    fill.path = new PathData.rect (0, 0, 50, 50);
    fill.mode = "linear";
    layer.fills.add (fill);
    var cw = p.colorway ().copy ("Night");
    cw.colors["Body"] = new ColorRef (Rgba (0.1, 0.1, 0.3), "Navy");
    p.colorways.add (cw);
    var call = new FlatItem (p.flats[0].new_id (), FlatItemKind.CALLOUT);
    call.at = Point (300, 300);
    call.at2 = Point (500, 250);
    call.number = 1;
    call.text = "Coverstitch hem";
    p.flats[0].items.add (call);
    p.techpack.revisions.add (new Revision (1, "First sample"));
    var cm = new Comment ("k1", "Check the neck width");
    cm.replies.add (new Comment ("k2", "Done"));
    p.techpack.comments.add (cm);
    p.garment.seams.add (new SeamPair ("d1", 2, "d2", 2));
    p.marker.ratio["38"] = 2;
    p.product.make_cube (100);
    var sketch3d = new PlaneCurve ("xz", 12);
    sketch3d.closed = true;
    sketch3d.add (2, 4);
    sketch3d.add (6, 8);
    p.product.sketches.add (sketch3d);
    var mesh = new Mesh ();
    mesh.name = "Surface mesh";
    mesh.add_vertex (Vec3 (0, 0, 0));
    mesh.add_vertex (Vec3 (10, 0, 0));
    mesh.add_vertex (Vec3 (0, 10, 0));
    mesh.add_triangle (0, 1, 2);
    p.product.surfaces.add (mesh);
    var surface = new NurbsSurface (1, 1, 2, 2);
    surface.name = "NURBS panel";
    surface.set_point (0, 0, Vec3 (0, 0, 0), 1);
    surface.set_point (0, 1, Vec3 (0, 10, 0), 0.8);
    surface.set_point (1, 0, Vec3 (10, 0, 2), 1.2);
    surface.set_point (1, 1, Vec3 (10, 10, 3), 1);
    surface.knots_u = { 0, 0, 1, 1 };
    surface.knots_v = { 0, 0, 1, 1 };
    p.product.nurbs.add (surface);
    return p;
}

void test_native () {
    var p = sample ();
    try {
        var data = NativeFormat.save (p);
        var zip = new ZipReader (data);
        check (zip.read_text ("mimetype") == NativeFormat.MIME, "mimetype entry");
        foreach (var n in new string[] { "project.json", "flats/front.svg", "pattern/pattern.svg", "pattern/measurements.csv", "techpack/bom.csv", "sketch/sketch.svg" }) check (zip.has (n), "zip has " + n);
        var q = NativeFormat.load_data (data);
        check (NativeFormat.to_json (q) == NativeFormat.to_json (p), "native round trip is lossless");
        var r1 = p.pattern.evaluate ("40");
        var r2 = q.pattern.evaluate ("40");
        check (r1.pieces.size == r2.pieces.size, "pattern pieces survive");
        for (int i = 0; i < r1.pieces.size; i++) check (r1.pieces[i].cut.length == r2.pieces[i].cut.length && r1.pieces[i].cut[3].distance (r2.pieces[i].cut[3]) < 1e-6, "cut lines identical");
        check (q.sketch.layers[0].strokes[0].samples.size == 20, "stroke samples kept");
        check (near (q.sketch.layers[0].strokes[0].samples[5].pressure, 0.35), "pressure kept");
        check (q.techpack.comments[0].replies.size == 1, "comment replies kept");
        check (q.product.faces.size == 6, "product cage kept");
        check (q.product.sketches.size == 1 && q.product.sketches[0].plane == "xz" && q.product.sketches[0].closed, "3D sketch kept");
        check (q.product.sketches[0].count () == 2 && near (q.product.sketches[0].offset, 12), "3D sketch points kept");
        check (q.product.surfaces.size == 1 && q.product.surfaces[0].name == "Surface mesh", "surface mesh kept");
        check (q.product.surfaces[0].vertices.size == 3 && q.product.surfaces[0].triangles.size == 3, "surface mesh geometry kept");
        check (q.product.nurbs.size == 1 && q.product.nurbs[0].name == "NURBS panel", "NURBS surface kept");
        check (q.product.nurbs[0].ctrl.length == 4 && near (q.product.nurbs[0].ctrl[3].z, 3) && near (q.product.nurbs[0].weights[1], 0.8), "NURBS controls and weights kept");
    } catch (Error e) {
        check (false, "native: " + e.message);
    }
}

Project product_sample () {
    var p = Project.create ("product");
    p.title = "NURBS Flask";
    p.product.clear ();
    p.product.material = "metal";
    var profile = new PlaneCurve ("xy", 0);
    foreach (var point in new Vec3[] { Vec3 (60, -140, 0), Vec3 (95, -130, 0), Vec3 (110, -30, 0), Vec3 (35, 55, 0), Vec3 (35, 125, 0) }) profile.add (point.x, point.y);
    profile.exact = new NurbsCurve (2);
    for (int i = 0; i < profile.count (); i++) {
        profile.exact.ctrl.add (profile.point3d (i));
        profile.exact.weights.add (1 + i * 0.15);
    }
    profile.exact.knots = { 0, 0, 0, 0.2, 0.65, 1, 1, 1 };
    p.product.sketches.add (profile);
    var circle = new PlaneCurve ("xz", -140);
    circle.exact = NurbsCurve.circle (Vec3 (0, 0, 0), 60, Vec3 (1, 0, 0), Vec3 (0, 1, 0));
    foreach (var point in circle.exact.sample (48)) circle.add (point.x, point.y);
    circle.closed = true;
    p.product.sketches.add (circle);
    var surface = NurbsSurface.revolve (profile.exact);
    surface.name = "Rational flask";
    p.product.nurbs.add (surface);
    var mesh = surface.to_mesh (32, 24);
    ProductModel.apply_material (mesh, "metal");
    mesh.add_line (0, 1);
    for (int i = 0; i < mesh.vertices.size; i++) mesh.scalars.add ((double) i / mesh.vertices.size);
    p.product.surfaces.add (mesh);
    return p;
}

void compare_product (ProductModel a, ProductModel b) {
    check (a.levels == b.levels && a.material == b.material && a.cage.vertices.size == b.cage.vertices.size && a.faces.size == b.faces.size && a.creases.size == b.creases.size, "cage properties kept");
    for (int i = 0; i < int.min (a.cage.vertices.size, b.cage.vertices.size); i++) check (a.cage.vertices[i].distance (b.cage.vertices[i]) < 1e-10, "cage precision kept");
    for (int i = 0; i < int.min (a.faces.size, b.faces.size); i++) {
        check (a.faces[i].size == b.faces[i].size, "cage face size kept");
        for (int j = 0; j < int.min (a.faces[i].size, b.faces[i].size); j++) check (a.faces[i][j] == b.faces[i][j], "cage face indices kept");
    }
    foreach (var crease in a.creases) check (b.creases.contains (crease), "cage crease kept");
    check (a.nurbs.size == b.nurbs.size && a.sketches.size == b.sketches.size && a.surfaces.size == b.surfaces.size, "product collections kept");
    for (int k = 0; k < int.min (a.nurbs.size, b.nurbs.size); k++) {
        var x = a.nurbs[k];
        var y = b.nurbs[k];
        check (x.degree_u == y.degree_u && x.degree_v == y.degree_v && x.count_u == y.count_u && x.count_v == y.count_v, "surface degrees and counts kept");
        check (x.knots_u.length == y.knots_u.length && x.knots_v.length == y.knots_v.length, "surface knot counts kept");
        if (x.knots_u.length != y.knots_u.length || x.knots_v.length != y.knots_v.length) continue;
        for (int i = 0; i < x.knots_u.length; i++) check (near (x.knots_u[i], y.knots_u[i], 1e-14), "U knots kept");
        for (int i = 0; i < x.knots_v.length; i++) check (near (x.knots_v[i], y.knots_v[i], 1e-14), "V knots kept");
        for (int i = 0; i < x.ctrl.length; i++) {
            check (x.ctrl[i].distance (y.ctrl[i]) < 1e-10, "surface controls kept");
            check (near (x.weights[i], y.weights[i], 1e-14), "surface weights kept");
        }
        for (int i = 0; i <= 12; i++) for (int j = 0; j <= 12; j++) check (x.eval ((double) i / 12, (double) j / 12).distance (y.eval ((double) i / 12, (double) j / 12)) < 1e-9, "evaluated surface unchanged");
    }
    for (int k = 0; k < int.min (a.sketches.size, b.sketches.size); k++) {
        var x = a.sketches[k];
        var y = b.sketches[k];
        check (x.plane == y.plane && x.closed == y.closed && near (x.offset, y.offset, 1e-14) && x.points.size == y.points.size, "plane sketch kept");
        for (int i = 0; i < int.min (x.points.size, y.points.size); i++) check (near (x.points[i], y.points[i], 1e-14), "plane sketch coordinates kept");
        check ((x.exact == null) == (y.exact == null), "exact sketch preserved");
        if (x.exact != null && y.exact != null) {
            check (x.exact.degree == y.exact.degree && x.exact.ctrl.size == y.exact.ctrl.size, "exact curve degree and controls kept");
            check (x.exact.weights.size == y.exact.weights.size && x.exact.knots.length == y.exact.knots.length, "exact curve weights and knot counts kept");
            for (int i = 0; i < int.min (x.exact.ctrl.size, y.exact.ctrl.size); i++) check (x.exact.ctrl[i].distance (y.exact.ctrl[i]) < 1e-10 && near (x.exact.weights[i], y.exact.weights[i], 1e-14), "exact curve controls and weights kept");
            for (int i = 0; i < int.min (x.exact.knots.length, y.exact.knots.length); i++) check (near (x.exact.knots[i], y.exact.knots[i], 1e-14), "exact curve knots kept");
            for (int i = 0; i <= 64; i++) check (x.to_nurbs (60).eval ((double) i / 64).distance (y.to_nurbs (60).eval ((double) i / 64)) < 1e-9, "evaluated exact sketch unchanged");
        }
    }
    for (int k = 0; k < int.min (a.surfaces.size, b.surfaces.size); k++) {
        var x = a.surfaces[k];
        var y = b.surfaces[k];
        check (x.name == y.name && x.vertices.size == y.vertices.size && x.triangles.size == y.triangles.size, "mesh geometry counts kept");
        check (x.normals.size == y.normals.size && x.uvs.size == y.uvs.size && x.scalars.size == y.scalars.size && x.lines.size == y.lines.size, "mesh attribute counts kept");
        check (x.material == y.material && near (x.roughness, y.roughness, 1e-14) && near (x.metallic, y.metallic, 1e-14), "mesh material kept");
        check (x.visible == y.visible && x.double_sided == y.double_sided, "mesh visibility kept");
        for (int i = 0; i < int.min (x.vertices.size, y.vertices.size); i++) check (x.vertices[i].distance (y.vertices[i]) < 1e-10, "mesh position kept");
        for (int i = 0; i < int.min (x.normals.size, y.normals.size); i++) check (x.normals[i].distance (y.normals[i]) < 1e-10, "mesh normal kept");
        for (int i = 0; i < int.min (x.uvs.size, y.uvs.size); i++) check (near (x.uvs[i], y.uvs[i], 1e-14), "mesh UV kept");
        for (int i = 0; i < int.min (x.scalars.size, y.scalars.size); i++) check (near (x.scalars[i], y.scalars[i], 1e-14), "mesh scalar kept");
        for (int i = 0; i < int.min (x.triangles.size, y.triangles.size); i++) check (x.triangles[i] == y.triangles[i], "mesh triangle index kept");
        for (int i = 0; i < int.min (x.lines.size, y.lines.size); i++) check (x.lines[i] == y.lines[i], "mesh line index kept");
        check (near (x.color.r, y.color.r, 1e-14) && near (x.color.g, y.color.g, 1e-14) && near (x.color.b, y.color.b, 1e-14) && near (x.color.a, y.color.a, 1e-14), "mesh colour kept");
    }
}

void test_product_native () {
    var p = product_sample ();
    p.product.make_cube (123.456789);
    p.product.creases.add (ProductModel.edge_key (0, 1));
    var original = p.product;
    var rows = new Gee.ArrayList<NurbsCurve> ();
    rows.add (p.product.sketches[0].to_nurbs (60));
    var second = p.product.sketches[0].to_nurbs (60);
    for (int i = 0; i < second.ctrl.size; i++) second.ctrl[i] = second.ctrl[i].add (Vec3 (0, 0, 80));
    rows.add (second);
    p.product.nurbs.add (NurbsSurface.loft (rows));
    p.product.nurbs.add (NurbsSurface.extrude (rows[0], Vec3 (0, 0, 50)));
    p.product.nurbs.add (NurbsSurface.sweep_circle (rows[0], 10));
    try {
        string path = Path.build_filename (tmp_dir (), "product.atelier");
        for (int pass = 0; pass < 3; pass++) {
            NativeFormat.save_to (p, path);
            p = NativeFormat.load (path);
            compare_product (original, p.product);
            check (!p.modified && p.path == path, "reopened project is saved");
        }
        string step_path = path + ".stp";
        Step.save (step_path, "Reopened", p.product.nurbs, p.product.curves ());
        var surfaces = new Gee.ArrayList<NurbsSurface> ();
        var curves = new Gee.ArrayList<NurbsCurve> ();
        string step_text;
        FileUtils.get_contents (step_path, out step_text);
        string schema;
        Step.read (step_text, surfaces, curves, out schema);
        var exported = new ProductModel ();
        exported.nurbs = surfaces;
        var expected = new ProductModel ();
        expected.nurbs = original.nurbs;
        compare_product (expected, exported);
        check (curves.size == original.sketches.size, "STEP keeps every sketch curve");
        if (curves.size == original.sketches.size) check (curves[1].eval (0.137).distance (original.sketches[1].to_nurbs (60).eval (0.137)) < 1e-9, "exact circle STEP after native reopen");
        var history = new History (p);
        history.checkpoint ();
        p.product.nurbs[0].weights[1] = 2.75;
        p.product.sketches.remove_at (1);
        history.undo ();
        compare_product (original, p.product);
        history.redo ();
        check (near (p.product.nurbs[0].weights[1], 2.75) && p.product.sketches.size == 1, "product redo restores edit");
    } catch (Error e) {
        check (false, "product native: " + e.message);
    }
}

string damage (string json, string kind) throws Error {
    var parser = new Json.Parser ();
    parser.load_from_data (json);
    var product = parser.get_root ().get_object ().get_object_member ("product");
    var surface = product.get_array_member ("nurbs").get_object_element (0);
    var mesh = product.get_array_member ("surfaces").get_object_element (0);
    var exact = product.get_array_member ("sketches").get_object_element (0).get_object_member ("exact");
    switch (kind) {
        case "knot count":
            surface.get_array_member ("knots_u").remove_element (0);
            break;
        case "knot order":
            surface.get_array_member ("knots_v").remove_element (0);
            surface.get_array_member ("knots_v").add_double_element (0);
            break;
        case "weight count":
            surface.get_array_member ("weights").remove_element (0);
            break;
        case "zero weight":
            exact.get_array_member ("weights").remove_element (0);
            exact.get_array_member ("weights").add_double_element (0);
            break;
        case "control count":
            surface.get_array_member ("ctrl").remove_element (0);
            break;
        case "text coordinate":
            surface.get_array_member ("ctrl").remove_element (0);
            surface.get_array_member ("ctrl").add_string_element ("x");
            break;
        case "triangle index":
            mesh.get_array_member ("triangles").remove_element (0);
            mesh.get_array_member ("triangles").add_int_element (99999);
            break;
        case "normal count":
            mesh.get_array_member ("normals").remove_element (0);
            mesh.get_array_member ("normals").remove_element (0);
            mesh.get_array_member ("normals").remove_element (0);
            break;
        case "cage index":
            var face = product.get_array_member ("faces").get_array_element (0);
            face.remove_element (0);
            face.add_int_element (8);
            break;
        case "curve degree":
            exact.set_int_member ("degree", 0);
            break;
    }
    var generator = new Json.Generator ();
    generator.set_root (parser.get_root ());
    return generator.to_data (null);
}

void test_product_invalid () {
    var p = product_sample ();
    p.product.make_cube (50);
    string json = NativeFormat.to_json (p);
    foreach (var kind in new string[] { "knot count", "knot order", "weight count", "zero weight", "control count", "text coordinate", "triangle index", "normal count", "cage index", "curve degree" }) {
        bool rejected = false;
        try {
            NativeFormat.from_json (damage (json, kind));
        } catch (FormatError e) {
            rejected = true;
        } catch (Error e) {
            check (false, "damaged product %s: %s".printf (kind, e.message));
        }
        check (rejected, "damaged product rejected: " + kind);
    }
    try {
        NativeFormat.from_json (damage (json, "none"));
    } catch (Error e) {
        check (false, "undamaged product: " + e.message);
    }
    try {
        var legacy = NativeFormat.from_json ("{\"format\":\"atelier\",\"version\":1,\"product\":{\"material\":\"metal\",\"vertices\":[0,0,0,1,0,0,0,1,0],\"faces\":[[0,1,2]],\"creases\":[],\"nurbs\":[{\"degree_u\":1,\"degree_v\":1,\"count_u\":2,\"count_v\":2,\"ctrl\":[0,0,0,1,0,0,0,1,0,1,1,0],\"weights\":[1,1,1,1]}]}}");
        check (legacy.product.material == "metal" && legacy.product.faces.size == 1 && legacy.product.sketches.size == 0, "older product without sketches opens");
        check (legacy.product.nurbs.size == 1 && legacy.product.nurbs[0].knots_u.length == 4 && near (legacy.product.nurbs[0].eval (0.5, 0.5).x, 0.5), "older NURBS surface without knots gets clamped knots");
    } catch (Error e) {
        check (false, "older product: " + e.message);
    }
}

void test_svg () {
    var p = sample ();
    string svg = SvgExport.flat_sheet (p.flats[0], p.colorway ());
    Rect b;
    try {
        var paths = SvgImport.paths (svg, out b);
        check (paths.size > 5, "flat svg paths parse back (%d)".printf (paths.size));
        string pat = SvgExport.pattern (p.pattern, p.pattern.evaluate ());
        check (pat.contains ("width=\"") && pat.contains ("mm\""), "pattern svg in millimetres");
        FileUtils.set_contents ("pattern.svg", pat);
        var pp = SvgImport.paths (pat, out b);
        check (pp.size >= 10, "pattern svg parses");
        var sk = SvgExport.sketch (p.sketch);
        var sp = SvgImport.paths (sk, out b);
        check (sp.size >= 3, "sketch svg has stroke outlines");
        var layer = SvgImport.to_layer (pp, "l9", "Imported");
        check (layer.strokes.size >= 10, "svg import to editable strokes");
    } catch (Error e) {
        check (false, "svg: " + e.message);
    }
}

void test_ora () {
    var p = sample ();
    try {
        var data = OraFormat.export (p.sketch, 1.0);
        var zip = new ZipReader (data);
        check (zip.read_text ("mimetype") == "image/openraster", "ora mimetype");
        check (zip.has ("stack.xml") && zip.has ("mergedimage.png") && zip.has ("data/layer0.png"), "ora entries");
        var layers = OraFormat.import (data, p.sketch);
        check (layers.size == 1 && layers[0].image () != null, "ora layer decoded");
        check (layers[0].image ().get_width () > 10, "ora layer has pixels");
    } catch (Error e) {
        check (false, "ora: " + e.message);
    }
}

void test_tables () {
    var p = sample ();
    var sheets = new Gee.ArrayList<Sheet> ();
    sheets.add (Tables.bom_sheet (p.techpack, p.colorways));
    sheets.add (Tables.measurements_sheet (p.pattern.table));
    try {
        var x = Tables.xlsx (sheets);
        var rows = Tables.read_xlsx (x, 1);
        check (rows.size == p.pattern.table.items.size + 1, "xlsx measurement rows %d".printf (rows.size));
        var t = Tables.measurements_from_rows (rows);
        check (near (t.value ("bust_circ", "42"), 96), "xlsx measurements round trip");
        var bom = Tables.read_xlsx (x, 0);
        check (bom[1][1] == p.techpack.bom[0].name, "bom item name in xlsx");
        string csv = Tables.measurements_csv (p.pattern.table);
        var t2 = Tables.measurements_from_rows (Tables.parse_csv (csv));
        check (near (t2.value ("hip_circ", "36"), 92), "csv measurements round trip");
        var odsz = new ZipReader (Tables.ods (sheets));
        check (odsz.read_text ("mimetype") == "application/vnd.oasis.opendocument.spreadsheet", "ods mimetype");
        var tricky = Tables.parse_csv ("a,\"b,c\",\"say \"\"hi\"\"\"\n1,2,3\n");
        check (tricky[0][1] == "b,c" && tricky[0][2] == "say \"hi\"", "csv quoting");
    } catch (Error e) {
        check (false, "tables: " + e.message);
    }
}

void test_odt () {
    var p = sample ();
    try {
        var data = TechPackOdt.export (p);
        var z = new ZipReader (data);
        check (z.read_text ("mimetype") == "application/vnd.oasis.opendocument.text", "odt mimetype");
        string content = z.read_text ("content.xml");
        var doc = Xml.Parser.read_memory (content, content.length);
        check (doc != null, "odt content is well formed");
        delete doc;
        check (content.contains ("Points of Measure") && content.contains ("Bill of Materials"), "odt sections");
        check (z.has ("Pictures/image1.png"), "odt embeds flats");
        string styles = z.read_text ("styles.xml");
        var sd = Xml.Parser.read_memory (styles, styles.length);
        check (sd != null, "odt styles well formed");
        delete sd;
    } catch (Error e) {
        check (false, "odt: " + e.message);
    }
}

void test_palettes () {
    var book = ColorBook.textile ();
    var gpl = ColorBook.parse_gpl (book.to_gpl (), "x");
    check (gpl.colors.size == book.colors.size && gpl.name == book.name, "gpl round trip");
    try {
        var ase = ColorBook.parse_ase (ColorBook.write_ase (book), "ase");
        check (ase.colors.size == book.colors.size, "ase round trip count");
        check (ase.colors[3].color.r - book.colors[3].color.r < 0.01, "ase colour kept");
    } catch (Error e) {
        check (false, e.message);
    }
    var red = ColorManager.lab_to_rgb (53.24, 80.09, 67.2);
    check (red.r > 0.95 && red.g < 0.1 && red.b < 0.1, "lab to srgb red (%f %f %f)".printf (red.r, red.g, red.b));
}

uint8[] psd_fixture (int w, int h, uint8 rr, uint8 gg, uint8 bb) {
    var o = new ByteArray ();
    put (o, "8BPS".data);
    p16 (o, 1);
    put (o, { 0, 0, 0, 0, 0, 0 });
    p16 (o, 3);
    p32 (o, h);
    p32 (o, w);
    p16 (o, 8);
    p16 (o, 3);
    p32 (o, 0);
    p32 (o, 0);
    var layer = new ByteArray ();
    p16 (layer, 1);
    p32 (layer, 2);
    p32 (layer, 3);
    p32 (layer, 2 + h);
    p32 (layer, 3 + w);
    p16 (layer, 4);
    int16[] ids = { -1, 0, 1, 2 };
    foreach (var id in ids) {
        p16 (layer, (uint16) id);
        p32 (layer, 2 + w * h);
    }
    put (layer, "8BIMnorm".data);
    put (layer, { 200, 0, 0, 0 });
    var extra = new ByteArray ();
    p32 (extra, 0);
    p32 (extra, 0);
    put (extra, { 3, 'T', 'o', 'p' });
    p32 (layer, extra.len);
    put (layer, extra.data);
    foreach (var id in ids) {
        p16 (layer, 0);
        uint8 v = id == -1 ? 255 : (id == 0 ? rr : (id == 1 ? gg : bb));
        for (int i = 0; i < w * h; i++) put (layer, { v });
    }
    var li = new ByteArray ();
    p32 (li, layer.len);
    put (li, layer.data);
    p32 (o, li.len);
    put (o, li.data);
    p16 (o, 0);
    return o.data;
}

void put (ByteArray b, uint8[] v) {
    b.append (v);
}

void p16 (ByteArray b, uint16 v) {
    b.append ({ (uint8) (v >> 8), (uint8) v });
}

void p32 (ByteArray b, uint32 v) {
    b.append ({ (uint8) (v >> 24), (uint8) (v >> 16), (uint8) (v >> 8), (uint8) v });
}

void test_psd () {
    var sk = new Sketch ();
    try {
        var layers = Psd.read (psd_fixture (5, 4, 200, 100, 50), sk);
        check (layers.size == 1 && layers[0].name == "Top", "psd layer read");
        var img = layers[0].image ();
        check (img != null && img.get_width () == 5 && img.get_height () == 4, "psd layer size");
        img.flush ();
        unowned uint8[] px = img.get_data ();
        check (px[2] == 200 && px[1] == 100 && px[0] == 50, "psd pixel colour");
        check (near (layers[0].opacity, 200.0 / 255, 0.01), "psd opacity");
        check (near (layers[0].image_matrix.x0, 3) && near (layers[0].image_matrix.y0, 2), "psd layer position");
    } catch (Error e) {
        check (false, "psd: " + e.message);
    }
}

int main () {
    test_psd ();
    test_native ();
    test_product_native ();
    test_product_invalid ();
    test_svg ();
    test_ora ();
    test_tables ();
    test_odt ();
    test_palettes ();
    return finish ("formats");
}
