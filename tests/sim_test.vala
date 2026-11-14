using Singularity.Vector;
using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

Body standard_body (string pose = "a-pose") {
    var table = MeasurementTable.standard_women ();
    var dims = BodyDims.from_table (table, "38");
    return Body.build (BodyFit.fit (dims, "female"), BodyPose.named (pose));
}

void test_body () {
    check (BodyData.get_default ().valid (), "avatar data loads");
    var table = MeasurementTable.standard_women ();
    var dims = BodyDims.from_table (table, "38");
    var t0 = get_monotonic_time ();
    var shape = BodyFit.fit (dims, "female");
    double secs = (get_monotonic_time () - t0) / 1e6;
    var body = Body.build (shape, BodyPose.named ("a-pose"));
    var m = body.measures;
    check ((m.height - dims.height).abs () < 3, "height %.0f wants %.0f".printf (m.height, dims.height));
    check ((m.bust - dims.bust).abs () < 15, "bust %.0f wants %.0f".printf (m.bust, dims.bust));
    check ((m.waist - dims.waist).abs () < 15, "waist %.0f wants %.0f".printf (m.waist, dims.waist));
    check ((m.hip - dims.hip).abs () < 15, "hip %.0f wants %.0f".printf (m.hip, dims.hip));
    check ((m.inseam - dims.inseam).abs () < 30, "inseam %.0f wants %.0f".printf (m.inseam, dims.inseam));
    check ((m.arm - dims.arm).abs () < 25, "arm %.0f wants %.0f".printf (m.arm, dims.arm));
    check (m.y_bust > m.y_waist && m.y_waist > m.y_hip && m.y_hip > m.y_crotch, "landmarks are ordered");
    check (body.mesh.vertex_count > 10000 && body.solid_triangles.length > 60000, "mesh has %d vertices".printf (body.mesh.vertex_count));
    check (secs < 6, "fit takes %.2f s".printf (secs));
    Singularity.Scene.Vec3 lo, hi;
    body.mesh.bounds (out lo, out hi);
    check (lo.y.abs () < 1, "feet on the floor %.2f".printf (lo.y));
    check ((lo.x + hi.x).abs () < 6, "body is centred %.1f".printf (lo.x + hi.x));
    var wl = body.joint ("wrist.L"), wr = body.joint ("wrist.R");
    check ((wl.x + wr.x).abs () < 3 && (wl.y - wr.y).abs () < 3, "arms are symmetric");
    Vec3[] ring;
    double taped = body.tape (Vec3 (0, m.y_waist, 200), out ring);
    check ((taped - m.waist).abs () < 25 && ring.length == 72, "tape at the waist reads %.0f for a %.0f waist".printf (taped, m.waist));
    var styled = new BodyLook ();
    styled.hair = "long01";
    styled.shoes = true;
    styled.hat = true;
    styled.gaze_x = 15;
    var dressed = Body.build (shape, BodyPose.named ("custom"), styled);
    check (dressed.extras.size >= 9, "styled avatar has eyes, lips, underwear, hair, shoes and hat (%d parts)".printf (dressed.extras.size));
    check (Body.hair_styles ().length == 10, "ten hair styles, got %d".printf (Body.hair_styles ().length));
    var tp = Body.build (shape, BodyPose.named ("t-pose"));
    check (tp.joint ("wrist.L").y > wl.y + 150, "t-pose raises the wrists");
    var relaxed = Body.build (shape, BodyPose.named ("relaxed"));
    check (relaxed.joint ("wrist.L").x < wl.x - 80, "relaxed pose lowers the arms");
    var men = MeasurementTable.standard_men ();
    var md = BodyDims.from_table (men, men.base_size);
    var man = Body.build (BodyFit.fit (md, "male"), BodyPose.named ("a-pose"));
    check ((man.measures.height - md.height).abs () < 3, "male height %.0f wants %.0f".printf (man.measures.height, md.height));
    check ((man.measures.bust - md.bust).abs () < 20, "male chest %.0f wants %.0f".printf (man.measures.bust, md.bust));
    check ((man.measures.waist - md.waist).abs () < 20, "male waist %.0f wants %.0f".printf (man.measures.waist, md.waist));
}

void test_fabrics () {
    check (FabricPreset.all ().size >= 6, "fabric presets");
    var denim = FabricPreset.find ("denim");
    var silk = FabricPreset.find ("silk");
    check (denim.bend_weft > silk.bend_weft * 10, "denim is much stiffer than silk");
    check (FabricPreset.find ("nope").id == "cotton", "unknown preset falls back");
}

void test_mesher () {
    double[] ring = {};
    for (int i = 0; i < 10; i++) { ring += i * 20; ring += 0; }
    for (int i = 0; i < 15; i++) { ring += 200; ring += i * 20; }
    for (int i = 0; i < 10; i++) { ring += 200 - i * 20; ring += 300; }
    for (int i = 0; i < 15; i++) { ring += 0; ring += 300 - i * 20; }
    double* pts;
    int* tris;
    int np, nt;
    AtCore.triangulate (ring, ring.length / 2, null, 0, 20, out pts, out np, out tris, out nt);
    check (nt > 200, "rectangle gives %d triangles".printf (nt));
    double area = 0;
    bool inside = true;
    var used = new bool[np];
    for (int t = 0; t < nt; t++) {
        int a = tris[t * 3], b = tris[t * 3 + 1], c = tris[t * 3 + 2];
        used[a] = used[b] = used[c] = true;
        area += ((pts[b * 2] - pts[a * 2]) * (pts[c * 2 + 1] - pts[a * 2 + 1]) - (pts[b * 2 + 1] - pts[a * 2 + 1]) * (pts[c * 2] - pts[a * 2])).abs () / 2;
    }
    for (int i = 0; i < np; i++) if (pts[i * 2] < -1e-6 || pts[i * 2] > 200 + 1e-6 || pts[i * 2 + 1] < -1e-6 || pts[i * 2 + 1] > 300 + 1e-6) inside = false;
    bool all_used = true;
    for (int i = 0; i < np; i++) if (!used[i]) all_used = false;
    check (near (area, 60000, 1), "triangles cover the rectangle %.1f".printf (area));
    check (inside, "points stay inside");
    check (all_used, "every point belongs to a triangle");
    bool kept = true;
    for (int i = 0; i < ring.length; i++) if (pts[i] != ring[i]) kept = false;
    check (kept, "boundary points come first and unchanged");
    AtCore.free (pts);
    AtCore.free (tris);
}

void test_collider () {
    var body = standard_body ();
    var mesh = body.mesh;
    var t0 = get_monotonic_time ();
    var sdf = AtCore.Sdf.build (mesh.positions, body.solid_vertices, body.solid_triangles, body.solid_triangles.length, 8, 70);
    double secs = (get_monotonic_time () - t0) / 1e6;
    check (sdf != null, "collider builds");
    check (secs < 5, "collider builds in %.2f s".printf (secs));
    var m = body.measures;
    var grad = new float[3];
    float inside = sdf.sample (0, (float) m.y_waist, 65, grad);
    check (inside < -40, "torso centre is deep inside %.1f".printf (inside));
    float front = sdf.sample (0, (float) m.y_bust, 260, grad);
    check (front > 20, "in front of the chest is outside %.1f".printf (front));
    float lo = 0, hi = 400;
    for (int i = 0; i < 40; i++) {
        float mid = (lo + hi) / 2;
        if (sdf.sample (0, (float) m.y_waist, mid, null) < 0) lo = mid;
        else hi = mid;
    }
    sdf.sample (0, (float) m.y_waist, hi + 4, grad);
    check (grad[2] > 0.7, "gradient points out of the belly %.2f".printf (grad[2]));
    check (sdf.sample (0, (float) m.y_waist, hi + 10, null) > 6, "distance grows outside");
    check (sdf.sample (700, 300, 0, null) > 100, "far away is far");
}

void test_hanging_patch () {
    var cloth = new AtCore.Cloth ();
    int fabric = cloth.add_fabric (GarmentSim.physical (FabricPreset.find ("cotton")));
    int n = 16;
    for (int j = 0; j < n; j++) for (int i = 0; i < n; i++) cloth.add_particle (i * 20, 1500, j * 20, i * 20, j * 20, 0);
    for (int j = 0; j + 1 < n; j++) for (int i = 0; i + 1 < n; i++) {
        int a = j * n + i;
        cloth.add_triangle (a, a + 1, a + n, fabric);
        cloth.add_triangle (a + 1, a + n + 1, a + n, fabric);
    }
    cloth.finalize ();
    for (int i = 0; i < n; i++) cloth.pin (i, 1);
    for (int f = 0; f < 240; f++) cloth.step (1.0f / 60, 14);
    unowned float[] x = cloth.positions ();
    check (near (x[1], 1500, 1e-3) && near (x[0], 0, 1e-3), "pinned corner stays");
    double low = x[((n - 1) * n + n / 2) * 3 + 1];
    check (low < 1500 - 280 && low > 1500 - 330, "free edge hangs %.0f below the pins".printf (1500 - low));
    var strain = new float[cloth.count ()];
    cloth.strain (strain);
    float worst = 0;
    foreach (var s in strain) if (s > worst) worst = s;
    check (worst < 0.06, "poplin barely stretches under its own weight %.3f".printf (worst));
    check (cloth.kinetic () < 60, "patch comes to rest %.1f".printf (cloth.kinetic ()));
}

void test_bending () {
    double[] droop = {};
    foreach (unowned string id in new string[] { "silk", "denim" }) {
        var cloth = new AtCore.Cloth ();
        int fabric = cloth.add_fabric (GarmentSim.physical (FabricPreset.find (id)));
        int n = 7;
        for (int j = 0; j < n; j++) for (int i = 0; i < n; i++) cloth.add_particle (i * 12, 1000, j * 12, i * 12, j * 12, 0);
        for (int j = 0; j + 1 < n; j++) for (int i = 0; i + 1 < n; i++) {
            int a = j * n + i;
            cloth.add_triangle (a, a + 1, a + n, fabric);
            cloth.add_triangle (a + 1, a + n + 1, a + n, fabric);
        }
        cloth.finalize ();
        for (int j = 0; j < n; j++) {
            cloth.pin (j * n, 1);
            cloth.pin (j * n + 1, 1);
        }
        for (int f = 0; f < 180; f++) cloth.step (1.0f / 60, 14);
        unowned float[] x = cloth.positions ();
        droop += 1000 - x[(n / 2 * n + n - 1) * 3 + 1];
    }
    check (droop[0] > droop[1] + 12, "silk droops more than denim (%.0f vs %.0f mm)".printf (droop[0], droop[1]));
}

void test_garment () {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var r = p.evaluate ("38");
    var settings = new GarmentSettings ();
    settings.resolution = 20;
    var body = standard_body ();
    var sim = new GarmentSim (r, settings, body);
    check (sim.pieces.size == 4, "front, back and two sleeves, got %d".printf (sim.pieces.size));
    check (settings.seams.size == 5, "shoulders, sides, underarm and two cap seams, got %d".printf (settings.seams.size));
    check (sim.stitch_count () > 100, "stitches %d".printf (sim.stitch_count ()));
    check (sim.min_body_distance () > 0, "starts outside the body %.2f".printf (sim.min_body_distance ()));
    double gap0 = sim.max_sew_gap ();
    var t0 = get_monotonic_time ();
    sim.run (240);
    double ms = (get_monotonic_time () - t0) / 1e3 / 240;
    double gap = sim.max_sew_gap ();
    check (gap < 20, "seams closed %.1f (from %.0f)".printf (gap, gap0));
    check (sim.max_stretch () < 0.2, "no wild stretching %.3f".printf (sim.max_stretch ()));
    check (sim.min_body_distance () > 0.5, "cloth stays outside the body %.2f".printf (sim.min_body_distance ()));
    check (sim.motion () < 30, "garment settles %.1f".printf (sim.motion ()));
    check (ms < 80, "%.1f ms per frame for %d particles".printf (ms, sim.particle_count ()));
    double hem = double.INFINITY, top = 0;
    foreach (var piece in sim.pieces) {
        Singularity.Scene.Vec3 lo, hi;
        piece.mesh.bounds (out lo, out hi);
        hem = double.min (hem, lo.y);
        top = double.max (top, hi.y);
    }
    var m = body.measures;
    check (top > m.y_shoulder && top < m.y_neck + 60, "collar sits at the neck %.0f".printf (top));
    check (hem > m.y_crotch - 80 && hem < m.y_waist, "hem hangs between waist and thigh %.0f".printf (hem));
    var again = new GarmentSim (r, settings, body);
    again.run (240);
    check (near (again.max_sew_gap (), gap, 1e-6), "simulation is repeatable");
    var meshes = sim.export_meshes ();
    check (meshes.size == 5 + body.extras.size && meshes[meshes.size - 1].triangles.size > 0, "export has the body, its parts and four pieces");
}

void test_scene_mesh () {
    var pm = new ProductModel ();
    pm.make_cube (100);
    var mesh = pm.subdivided ().to_scene (true);
    check (mesh.vertex_count > 0 && mesh.normals.length == mesh.positions.length, "scene mesh has normals");
    check (mesh.scalars.length == mesh.vertex_count, "curvature scalars are filled");
    var hit = Singularity.Scene.Hit () { mesh = null, triangle = -1, distance = double.INFINITY };
    var ray = Singularity.Scene.Ray () { origin = Singularity.Scene.Vec3 (0, 0, 500), direction = Singularity.Scene.Vec3 (0, 0, -1) };
    check (mesh.intersect (ray, ref hit) && hit.point.z > 0 && hit.point.z < 100, "ray hits the front of the model at %.1f".printf (hit.point.z));
    var miss = Singularity.Scene.Hit () { mesh = null, triangle = -1, distance = double.INFINITY };
    var away = Singularity.Scene.Ray () { origin = Singularity.Scene.Vec3 (500, 500, 500), direction = Singularity.Scene.Vec3 (0, 0, -1) };
    check (!mesh.intersect (away, ref miss), "ray beside the model misses");
    var back = Mesh.from_scene (mesh);
    check (back.vertices.size == mesh.vertex_count && back.triangles.size == mesh.triangles.length, "round trip keeps the topology");
}

void test_subdivision () {
    var pm = new ProductModel ();
    pm.make_cube (100);
    Gee.ArrayList<Vec3?> v;
    Gee.ArrayList<Gee.ArrayList<int>> f;
    pm.subdivide (1, out v, out f);
    check (v.size == 26 && f.size == 24, "level 1 counts %d %d".printf (v.size, f.size));
    pm.subdivide (2, out v, out f);
    check (v.size == 98 && f.size == 96, "level 2 counts %d %d".printf (v.size, f.size));
    double maxr = 0;
    foreach (var p in v) maxr = double.max (maxr, p.x.abs ());
    check (maxr < 50, "smooth cube shrinks");
    foreach (var face in pm.faces) for (int k = 0; k < face.size; k++) pm.set_crease (face[k], face[(k + 1) % face.size], true);
    pm.subdivide (2, out v, out f);
    for (int i = 0; i < 8; i++) check (v[i].distance (pm.cage.vertices[i]) < 1e-9, "creased corner stays");
    foreach (var p in v) {
        int on_face = 0;
        if (near (p.x.abs (), 50, 1e-6)) on_face++;
        if (near (p.y.abs (), 50, 1e-6)) on_face++;
        if (near (p.z.abs (), 50, 1e-6)) on_face++;
        check (on_face >= 1, "fully creased cube keeps flat faces");
    }
    var pm2 = new ProductModel ();
    pm2.make_cube (100);
    int faces0 = pm2.faces.size;
    pm2.extrude_face (1, 50);
    check (pm2.faces.size == faces0 + 4 && pm2.cage.vertices.size == 12, "extrude adds side faces");
    check (near (pm2.face_center (1).z, 100), "extruded face moved");
    pm2.inset_face (1, 10);
    check (pm2.faces.size == faces0 + 8, "inset adds a ring");
    pm2.delete_face (0);
    var mesh = pm2.subdivided ();
    check (mesh.triangle_count () > 0, "subdivided mesh");
    var prof = Surfaces.bspline ({ 0, 0, 40, 0, 50, 60, 20, 120, 0, 130 }, 3, 20);
    check (prof.length == 42 && near (prof[0], 0) && near (prof[prof.length - 2], 0), "bspline interpolates end points");
    var rev = Surfaces.revolve (prof, 24);
    check (rev.vertices.size == 24 * 21, "revolve grid");
    var ex = Surfaces.extrude ({ 0, 0, 10, 0, 10, 10, 0, 10 }, 5, true);
    check (near (ex.surface_area (), 4 * 50 + 200, 1e-6), "extrude area %f".printf (ex.surface_area ()));
    var path = new Gee.ArrayList<Vec3?> ();
    for (int i = 0; i <= 10; i++) path.add (Vec3 (i * 10, 0, 0));
    var sw = Surfaces.sweep ({ -5, -5, 5, -5, 5, 5, -5, 5 }, path, true);
    check (near (sw.surface_area (), 40 * 100, 1e-3), "sweep of a square along a line %f".printf (sw.surface_area ()));
    var curve = new PlaneCurve ("xz", 10);
    curve.add (1, 2);
    check (curve.point3d (0).y == 10 && curve.point3d (0).z == 2, "plane curve mapping");
}


int main () {
    test_fabrics ();
    test_mesher ();
    test_body ();
    test_collider ();
    test_hanging_patch ();
    test_bending ();
    test_subdivision ();
    test_scene_mesh ();
    test_garment ();
    return finish ("sim");
}
