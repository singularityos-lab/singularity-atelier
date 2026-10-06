using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

Gee.ArrayList<Mesh> sample () {
    var list = new Gee.ArrayList<Mesh> ();
    var pm = new ProductModel ();
    pm.make_cube (120);
    pm.material = "metal";
    var cube = pm.subdivided ();
    cube.name = "cube";
    list.add (cube);
    var avatar = Avatar.build (MeasurementTable.standard_women (), "38", "a-pose");
    list.add (avatar);
    var rev = Surfaces.revolve ({ 0, 0, 40, 0, 45, 50, 0, 90 }, 16);
    rev.color = Rgba (0.2, 0.4, 0.6, 1);
    list.add (rev);
    return list;
}

void compare (Gee.List<Mesh> a, Gee.List<Mesh> b, double tol, string what) {
    check (a.size == b.size, "%s: mesh count %d vs %d".printf (what, a.size, b.size));
    for (int i = 0; i < int.min (a.size, b.size); i++) {
        check (a[i].vertices.size == b[i].vertices.size, "%s: vertex count of %s".printf (what, a[i].name));
        check (a[i].triangles.size == b[i].triangles.size, "%s: triangle count of %s".printf (what, a[i].name));
        double worst = 0;
        for (int k = 0; k < int.min (a[i].vertices.size, b[i].vertices.size); k++) worst = double.max (worst, a[i].vertices[k].distance (b[i].vertices[k]));
        check (worst < tol, "%s: positions of %s differ by %f".printf (what, a[i].name, worst));
        bool same_idx = true;
        for (int k = 0; k < int.min (a[i].triangles.size, b[i].triangles.size); k++) if (a[i].triangles[k] != b[i].triangles[k]) same_idx = false;
        check (same_idx, "%s: indices of %s".printf (what, a[i].name));
        check (near (a[i].color.r, b[i].color.r, 1e-3) && near (a[i].roughness, b[i].roughness, 0.02), "%s: material of %s".printf (what, a[i].name));
    }
}

uint32 le32 (uint8[] d, int p) {
    return d[p] | ((uint32) d[p + 1] << 8) | ((uint32) d[p + 2] << 16) | ((uint32) d[p + 3] << 24);
}

void test_glb () throws Error {
    var meshes = sample ();
    var data = Gltf.write (meshes, true);
    check (le32 (data, 0) == 0x46546C67, "glb magic");
    check (le32 (data, 4) == 2, "glb version");
    check (le32 (data, 8) == data.length, "glb total length");
    uint32 jlen = le32 (data, 12);
    check (le32 (data, 16) == 0x4E4F534A, "first chunk is JSON");
    check (jlen % 4 == 0, "json chunk padded");
    int bin_at = 20 + (int) jlen;
    check (le32 (data, bin_at + 4) == 0x004E4942, "second chunk is BIN");
    check (bin_at + 8 + le32 (data, bin_at) == data.length, "bin chunk fills the file");
    var parser = new Json.Parser ();
    parser.load_from_data ((string) data[20:20 + jlen], jlen);
    var root = parser.get_root ().get_object ();
    check (root.get_object_member ("asset").get_string_member ("version") == "2.0", "asset version");
    var acc = root.get_array_member ("accessors").get_object_element (0);
    check (acc.has_member ("min") && acc.has_member ("max"), "position accessor has bounds");
    string dir = tmp_dir ();
    string path = Path.build_filename (dir, "garment.glb");
    Gltf.save (path, meshes);
    compare (meshes, Gltf.load (path), 0.01, "glb");
    FileUtils.remove (path);
    string gpath = Path.build_filename (dir, "garment.gltf");
    Gltf.save (gpath, meshes);
    string text;
    FileUtils.get_contents (gpath, out text);
    check (text.contains ("data:application/octet-stream;base64,"), "gltf embeds its buffer");
    compare (meshes, Gltf.load (gpath), 0.01, "gltf");
    FileUtils.remove (gpath);
    DirUtils.remove (dir);
}

void test_obj () throws Error {
    var meshes = sample ();
    string dir = tmp_dir ();
    string path = Path.build_filename (dir, "model.obj");
    Obj.save (path, meshes);
    check (FileUtils.test (Path.build_filename (dir, "model.mtl"), FileTest.EXISTS), "mtl written");
    var back = Obj.load (path);
    compare (meshes, back, 0.01, "obj");
    check (back[0].uvs.size == 0 || back[0].uvs.size == back[0].vertices.size * 2, "uvs consistent");
    check (back[2].uvs.size == back[2].vertices.size * 2, "revolve keeps uvs");
    var quad = Obj.parse ("v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1 2 3 4\nf -4 -2 -1\n");
    check (quad.size == 1 && quad[0].triangle_count () == 3, "polygon faces are triangulated and negative indices work");
    FileUtils.remove (path);
    FileUtils.remove (Path.build_filename (dir, "model.mtl"));
    DirUtils.remove (dir);
}

void step_sample (Gee.ArrayList<NurbsSurface> surfaces, Gee.ArrayList<NurbsCurve> curves) {
    var line = new Gee.ArrayList<Vec3?> ();
    line.add (Vec3 (50, 0, 0));
    line.add (Vec3 (50, 40, 0));
    line.add (Vec3 (50, 80, 0));
    line.add (Vec3 (50, 120, 0));
    var cyl = NurbsSurface.revolve (NurbsCurve.through (line, 3));
    cyl.name = "cylinder";
    surfaces.add (cyl);
    var prof = new Gee.ArrayList<Vec3?> ();
    prof.add (Vec3 (0, 0, 0));
    prof.add (Vec3 (40, 10, 0));
    prof.add (Vec3 (70, 60, 0));
    prof.add (Vec3 (90, 20, 0));
    prof.add (Vec3 (120, 0, 0));
    var bottle = NurbsSurface.revolve (NurbsCurve.through (prof, 3));
    bottle.name = "bottle's body";
    surfaces.add (bottle);
    surfaces.add (NurbsSurface.extrude (NurbsCurve.through (prof, 3), Vec3 (0, 0, 35)));
    var rows = new Gee.ArrayList<NurbsCurve> ();
    for (int k = 0; k < 4; k++) {
        var r = new Gee.ArrayList<Vec3?> ();
        for (int i = 0; i < 6; i++) r.add (Vec3 (i * 20, Math.sin (i + k) * 10, k * 30));
        rows.add (NurbsCurve.through (r, 3));
    }
    surfaces.add (NurbsSurface.loft (rows));
    curves.add (NurbsCurve.circle (Vec3 (10, 20, 30), 25, Vec3 (1, 0, 0), Vec3 (0, 1, 0)));
    curves.add (NurbsCurve.through (prof, 3));
}

void test_step () throws Error {
    var surfaces = new Gee.ArrayList<NurbsSurface> ();
    var curves = new Gee.ArrayList<NurbsCurve> ();
    step_sample (surfaces, curves);
    string text = Step.write ("Bottle è", surfaces, curves);
    check (text.has_prefix ("ISO-10303-21;\nHEADER;") && text.has_suffix ("END-ISO-10303-21;\n"), "part 21 envelope");
    check (text.contains ("FILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'))"), "AP214 schema");
    check (text.contains ("(BOUNDED_SURFACE() B_SPLINE_SURFACE(") && text.contains ("RATIONAL_B_SPLINE_SURFACE(("), "rational surface as a complex entity");
    check (text.contains ("B_SPLINE_SURFACE_WITH_KNOTS('extrude',3,1,"), "extrusion is a plain b-spline surface");
    check (text.contains ("RATIONAL_B_SPLINE_CURVE((1.,0.707106781186548,"), "exact circle weights");
    check (text.contains ("\\X2\\00E8\\X0\\") && text.contains ("'bottle''s body'"), "strings are encoded");
    check (text.contains ("SI_UNIT(.MILLI.,.METRE.)") && text.contains ("GEOMETRICALLY_BOUNDED_SURFACE_SHAPE_REPRESENTATION"), "units and representation");
    int last = 0;
    bool ordered = true;
    var ids = new Gee.HashSet<int> ();
    foreach (var l in text.split ("\n")) {
        if (!l.has_prefix ("#")) continue;
        int id = int.parse (l.substring (1, l.index_of ("=") - 1));
        if (id <= last || !l.has_suffix (";")) ordered = false;
        last = id;
        ids.add (id);
    }
    check (ordered, "entity ids increase and every record ends with a semicolon");
    bool refs_ok = true;
    try {
        var re = new Regex ("#([0-9]+)");
        MatchInfo mi;
        string data = text.substring (text.index_of ("DATA;"));
        re.match (data, 0, out mi);
        while (mi.matches ()) {
            if (!ids.contains (int.parse (mi.fetch (1)))) refs_ok = false;
            mi.next ();
        }
    } catch (RegexError e) {
        refs_ok = false;
    }
    check (refs_ok, "every reference points at a written entity");
    var s2 = new Gee.ArrayList<NurbsSurface> ();
    var c2 = new Gee.ArrayList<NurbsCurve> ();
    string schema;
    string dir = tmp_dir ();
    string path = Path.build_filename (dir, "bottle.stp");
    Step.save (path, "Bottle", surfaces, curves);
    string back_text;
    FileUtils.get_contents (path, out back_text);
    Step.read (back_text, s2, c2, out schema);
    check (schema.has_prefix ("AUTOMOTIVE_DESIGN"), "schema read back");
    check (s2.size == surfaces.size && c2.size == curves.size, "surface and curve count %d %d".printf (s2.size, c2.size));
    double worst = 0;
    for (int k = 0; k < int.min (s2.size, surfaces.size); k++) {
        var a = surfaces[k];
        var b = s2[k];
        check (a.degree_u == b.degree_u && a.degree_v == b.degree_v && a.count_u == b.count_u && a.count_v == b.count_v, "surface %d layout".printf (k));
        check (a.knots_u.length == b.knots_u.length && a.knots_v.length == b.knots_v.length, "surface %d knots".printf (k));
        for (int i = 0; i <= 10; i++) for (int j = 0; j <= 10; j++) worst = double.max (worst, a.eval (i / 10.0, j / 10.0).distance (b.eval (i / 10.0, j / 10.0)));
    }
    check (worst < 1e-9, "surfaces evaluate the same after reading (%g)".printf (worst));
    check (s2[1].name == "bottle's body", "surface name kept");
    double cw = 0;
    for (int k = 0; k < int.min (c2.size, curves.size); k++) for (int i = 0; i <= 50; i++) cw = double.max (cw, curves[k].eval (i / 50.0).distance (c2[k].eval (i / 50.0)));
    check (cw < 1e-9, "curves evaluate the same after reading (%g)".printf (cw));
    double rmax = 0;
    for (int i = 0; i <= 64; i++) for (int j = 0; j <= 8; j++) {
        var p = s2[0].eval (i / 64.0, j / 8.0);
        rmax = double.max (rmax, (Math.sqrt (p.x * p.x + p.z * p.z) - 50).abs ());
    }
    check (rmax < 1e-9, "revolved cylinder is exactly round (%g)".printf (rmax));
    var mesh = s2[1].to_mesh (24, 12);
    check (mesh.vertices.size == 25 * 13 && mesh.triangle_count () == 24 * 12 * 2, "surface tessellates");
    string? keep = Environment.get_variable ("ATELIER_EXPORT_DIR");
    if (keep != null) {
        Step.save (Path.build_filename (keep, "atelier.stp"), "Atelier sample", surfaces, curves);
        var js = new StringBuilder ("{\"surfaces\":[");
        for (int k = 0; k < surfaces.size; k++) {
            if (k > 0) js.append (",");
            js.append ("[");
            for (int i = 0; i <= 10; i++) for (int j = 0; j <= 10; j++) {
                var p = surfaces[k].eval (i / 10.0, j / 10.0);
                if (i + j > 0) js.append (",");
                js.append ("[%s,%s,%s,%s,%s]".printf (Step.real (i / 10.0), Step.real (j / 10.0), Step.real (p.x), Step.real (p.y), Step.real (p.z)));
            }
            js.append ("]");
        }
        js.append ("],\"curves\":[");
        for (int k = 0; k < curves.size; k++) {
            if (k > 0) js.append (",");
            js.append ("[");
            for (int i = 0; i <= 50; i++) {
                var p = curves[k].eval (i / 50.0);
                if (i > 0) js.append (",");
                js.append ("[%s,%s,%s,%s]".printf (Step.real (i / 50.0), Step.real (p.x), Step.real (p.y), Step.real (p.z)));
            }
            js.append ("]");
        }
        js.append ("]}");
        FileUtils.set_contents (Path.build_filename (keep, "atelier-stp-samples.json"), js.str.replace ("E", "e").replace (".,", ".0,").replace (".]", ".0]").replace (".e", ".0e"));
    }
    FileUtils.remove (path);
    DirUtils.remove (dir);
}

void test_fbx () throws Error {
    var meshes = sample ();
    meshes[0].metallic = 0.8;
    string ascii = Fbx.write_ascii (meshes);
    check (ascii.has_prefix ("; FBX 7.4.0 project file"), "ascii header");
    check (ascii.contains ("FBXVersion: 7400") && ascii.contains ("Vertices: *") && ascii.contains ("PolygonVertexIndex: *"), "ascii geometry");
    check (ascii.contains ("P: \"DiffuseColor\", \"Color\", \"\", \"A\",") && ascii.contains ("C: \"OO\","), "ascii materials and connections");
    var tree = Fbx.parse_ascii (ascii);
    var direct = Fbx.build (meshes);
    check (tree.size == direct.size, "ascii parses into the same top level nodes");
    string dir = tmp_dir ();
    string apath = Path.build_filename (dir, "scene.fbx");
    Fbx.save (apath, meshes);
    compare (meshes, Fbx.load (apath), 0.001, "fbx ascii");
    var bin = Fbx.write_binary (meshes);
    check (Memory.cmp (bin, "Kaydara FBX Binary  ".data, 20) == 0 && bin[20] == 0 && bin[21] == 0x1a, "binary magic");
    check (le32 (bin, 23) == 7400, "binary version");
    string bpath = Path.build_filename (dir, "scene-bin.fbx");
    Fbx.save (bpath, meshes, true);
    var back = Fbx.load (bpath);
    compare (meshes, back, 1e-9, "fbx binary");
    check (near (back[0].metallic, 0.8, 1e-9) && back[0].material == "metal", "material settings kept");
    check (back[1].name == meshes[1].name, "avatar name kept");
    check (back[2].uvs.size == meshes[2].uvs.size, "uvs kept");
    string? keep = Environment.get_variable ("ATELIER_EXPORT_DIR");
    if (keep != null) {
        Fbx.save (Path.build_filename (keep, "atelier-ascii.fbx"), meshes);
        Fbx.save (Path.build_filename (keep, "atelier-binary.fbx"), meshes, true);
        var js = new StringBuilder ("[");
        for (int k = 0; k < meshes.size; k++) {
            var m = meshes[k];
            Vec3 lo, hi;
            m.bounds (out lo, out hi);
            if (k > 0) js.append (",");
            js.append ("{\"name\":\"%s\",\"vertices\":%d,\"triangles\":%d,\"color\":[%.6f,%.6f,%.6f],\"min\":[%.6f,%.6f,%.6f],\"max\":[%.6f,%.6f,%.6f],\"uvs\":%s}".printf (
                m.name, m.vertices.size, m.triangle_count (), m.color.r, m.color.g, m.color.b, lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, m.uvs.size > 0 ? "true" : "false"));
        }
        js.append ("]");
        FileUtils.set_contents (Path.build_filename (keep, "atelier-fbx-ref.json"), js.str);
    }
    FileUtils.remove (apath);
    FileUtils.remove (bpath);
    DirUtils.remove (dir);
}

int main () {
    try {
        test_glb ();
        test_obj ();
        test_step ();
        test_fbx ();
    } catch (Error e) {
        check (false, e.message);
    }
    return finish ("mesh-io");
}
