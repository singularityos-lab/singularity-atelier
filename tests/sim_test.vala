using Singularity.Vector;
using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

void test_avatar () {
    var table = MeasurementTable.standard_women ();
    foreach (var size in new string[] { "34", "38", "46" }) {
        var model = Avatar.model (table, size, "a-pose");
        double bust, height;
        try {
            bust = table.value_mm ("bust_circ", size);
            height = table.value_mm ("height", size);
        } catch (ExprError e) {
            check (false, e.message);
            return;
        }
        var girth = Mesh.hull_perimeter_xz (model.torso_mesh.slice_y (model.dims.y_bust ()));
        check ((girth - bust).abs () / bust < 0.04, "bust girth %s: %f vs %f".printf (size, girth, bust));
        var waist = Mesh.hull_perimeter_xz (model.torso_mesh.slice_y (model.dims.y_waist ()));
        check ((waist - model.dims.waist).abs () / model.dims.waist < 0.04, "waist girth %s: %f".printf (size, waist));
        Vec3 min, max;
        model.mesh.bounds (out min, out max);
        check (near (max.y - min.y, height, height * 0.02), "avatar height %s: %f vs %f".printf (size, max.y - min.y, height));
        check (model.mesh.triangle_count () > 2000, "avatar has a real mesh");
        var col = new AvatarCollider (model);
        Vec3 n;
        check (col.distance (Vec3 (0, model.dims.y_waist (), 0), out n) < 0, "waist center is inside");
        check (col.distance (Vec3 (0, model.dims.y_waist (), 600), out n) > 300, "point in front is outside");
        double d = col.distance (Vec3 (0, model.dims.y_bust (), 400), out n);
        check (n.z > 0.9, "normal at the front points forward");
    }
    var tpose = Avatar.model (table, "38", "t-pose");
    Vec3 tmin, tmax;
    tpose.mesh.bounds (out tmin, out tmax);
    var apose = Avatar.model (table, "38", "a-pose");
    Vec3 amin, amax;
    apose.mesh.bounds (out amin, out amax);
    check (tmax.x - tmin.x > amax.x - amin.x + 300, "t-pose is wider than a-pose");
}

void test_fabrics () {
    check (FabricPreset.all ().size >= 6, "presets");
    foreach (var id in new string[] { "jersey", "cotton", "denim", "leather", "silk", "wool" }) check (FabricPreset.find (id).id == id, "preset " + id);
    check (FabricPreset.find ("denim").bend_compliance < FabricPreset.find ("silk").bend_compliance, "denim is stiffer than silk");
}

void test_hanging_patch () {
    Point[] ring = {};
    double w = 400, h = 400, sp = 20;
    for (double x = 0; x < w; x += sp) ring += Point (x, 0);
    for (double y = 0; y < h; y += sp) ring += Point (w, y);
    for (double x = w; x > 0; x -= sp) ring += Point (x, h);
    for (double y = h; y > 0; y -= sp) ring += Point (0, y);
    var interior = ClothMesher.lattice (ring, sp);
    int[] tris;
    ClothMesher.triangulate (ring, interior, out tris);
    Point[] pts = ring;
    foreach (var p in interior) pts += p;
    check (tris.length / 3 > pts.length, "triangulation has triangles %d for %d points".printf (tris.length / 3, pts.length));
    double area = 0;
    for (int t = 0; t < tris.length; t += 3) {
        var a = pts[tris[t]];
        var b = pts[tris[t + 1]];
        var c = pts[tris[t + 2]];
        area += ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)).abs () / 2;
    }
    check ((area - w * h).abs () / (w * h) < 0.02, "triangles cover the patch %f".printf (area));
    var fab = FabricPreset.find ("cotton");
    var s = new ClothState ();
    double mass = fab.density * w * h * 1e-6 / pts.length;
    foreach (var p in pts) {
        bool pin = p.y < 1e-6;
        s.add_particle (Vec3 (p.x, 1000, p.y), p.x, p.y, pin ? 0 : mass, 0.3, 1);
    }
    var seen = new Gee.HashSet<string> ();
    for (int t = 0; t < tris.length; t += 3) {
        for (int e = 0; e < 3; e++) {
            int a = tris[t + e], b = tris[t + (e + 1) % 3];
            string key = a < b ? "%d:%d".printf (a, b) : "%d:%d".printf (b, a);
            if (seen.contains (key)) continue;
            seen.add (key);
            s.add_constraint (a, b, pts[a].distance (pts[b]), fab.stretch_compliance, 0);
        }
    }
    var solver = new CpuXpbdSolver ();
    for (int f = 0; f < 240; f++) solver.step (s, null, 1.0 / 60, 12);
    double worst = 0;
    double speed = 0;
    for (int c = 0; c < s.m; c++) worst = double.max (worst, s.pos (s.ca[c]).distance (s.pos (s.cb[c])) / s.rest[c] - 1);
    for (int i = 0; i < s.n; i++) speed = double.max (speed, Math.sqrt (s.vx[i] * s.vx[i] + s.vy[i] * s.vy[i] + s.vz[i] * s.vz[i]));
    double low = 1000;
    for (int i = 0; i < s.n; i++) low = double.min (low, s.y[i]);
    check (low < 1000 - h * 0.8, "patch hangs down %f".printf (low));
    check (worst < 0.05, "edge stretch after settling %f".printf (worst));
}

void test_garment () {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var r = p.evaluate ("38");
    var settings = new GarmentSettings ();
    settings.resolution = 22;
    var sim = new GarmentSim (r, settings, p.table, "38");
    check (sim.instances.size == 4, "front, back and two sleeves, got %d".printf (sim.instances.size));
    check (sim.sew_a.size > 20, "seams found %d".printf (sim.sew_a.size));
    double gap0 = sim.max_sew_gap ();
    check (sim.min_collider_distance () > -1, "starts outside the body %f".printf (sim.min_collider_distance ()));
    var t0 = get_monotonic_time ();
    sim.run (150);
    double secs = (get_monotonic_time () - t0) / 1e6;
    double gap = sim.max_sew_gap ();
    check (gap < 10, "seams closed %f (from %f)".printf (gap, gap0));
    check (sim.mean_sew_gap () < 3, "mean seam gap %f".printf (sim.mean_sew_gap ()));
    double pen = sim.min_collider_distance ();
    check (pen > -2, "no vertex inside the body %f".printf (pen));
    var mesh = sim.garment_mesh ();
    check (mesh.vertices.size == sim.state.n && mesh.scalars.size == sim.state.n, "garment mesh with fit map");
    Vec3 min, max;
    mesh.bounds (out min, out max);
    check (min.y > sim.avatar.dims.y_crotch () - 350 && max.y < sim.avatar.dims.height, "garment hangs on the body %f %f".printf (min.y, max.y));
    check (sim.max_stretch () < 0.6, "stretch stays bounded %f".printf (sim.max_stretch ()));
    var strain = sim.strain_map ();
    int over = 0;
    foreach (var st in strain) if (st > 0.1) over++;
    check (over < strain.length / 20, "few vertices above 10 percent strain: %d".printf (over));
    var dist = sim.distance_map ();
    double mean = 0;
    foreach (var d in dist) mean += d;
    mean /= dist.length;
    check (mean < 120, "garment sits close to the body %f".printf (mean));
    print ("garment: %d particles, %d constraints, 150 frames in %.1f s, gap %.2f mm, min distance %.2f mm, max stretch %.3f\n", sim.state.n, sim.state.m, secs, gap, pen, sim.max_stretch ());
    p.find_piece (r.pieces[0].piece.id);
    var r2 = p.evaluate ("40");
    sim.rebuild (r2);
    check (sim.min_collider_distance () > -5, "rebuild keeps the pose");
    sim.run (20);
    check (sim.min_collider_distance () > -2, "rebuilt garment settles outside the body");
}

ClothState two_layers () {
    var s = new ClothState ();
    double h = 10;
    for (int layer = 0; layer < 2; layer++) {
        int n = layer == 0 ? 12 : 8;
        int base_i = s.n;
        for (int j = 0; j < n; j++) for (int i = 0; i < n; i++) {
            bool pinned = layer == 0 && (i == 0 || j == 0 || i == n - 1 || j == n - 1);
            s.add_particle (Vec3 (i * h + (layer == 1 ? 18 : 0), layer == 0 ? 0 : 40, j * h + (layer == 1 ? 18 : 0)), i * h, j * h, pinned ? 0 : 0.5, 0.3, 1.5);
        }
        for (int j = 0; j < n; j++) for (int i = 0; i < n; i++) {
            int a = base_i + j * n + i;
            if (i < n - 1) s.add_constraint (a, a + 1, h, 1e-7, 0);
            if (j < n - 1) s.add_constraint (a, a + n, h, 1e-7, 0);
            if (i < n - 1 && j < n - 1) {
                s.add_constraint (a, a + n + 1, h * Math.SQRT2, 1e-6, 1);
                s.add_tri (a, a + 1, a + n);
                s.add_tri (a + 1, a + n + 1, a + n);
            }
        }
    }
    s.group = new int[s.n];
    for (int i = 0; i < s.n; i++) s.group[i] = i < 144 ? 0 : 1;
    s.spacing = h;
    s.damping = 0.05;
    return s;
}

double layer_gap (ClothState s) {
    int n2 = 144;
    double worst = double.INFINITY;
    for (int i = n2; i < s.n; i++) {
        double below = -1e9;
        for (int j = 0; j < n2; j++) {
            if ((s.x[j] - s.x[i]).abs () < 6 && (s.z[j] - s.z[i]).abs () < 6) below = double.max (below, s.y[j]);
        }
        if (below > -1e9) worst = double.min (worst, s.y[i] - below);
    }
    return worst;
}

ClothState folded_sheet () {
    var s = new ClothState ();
    double h = 10;
    int n = 12, rows = 24;
    for (int j = 0; j < rows; j++) for (int i = 0; i < n; i++) {
        bool lower = j < n;
        bool pinned = lower && (i == 0 || i == n - 1 || j == 0);
        double z = lower ? j * h : (rows - 1 - j) * h + 5;
        s.add_particle (Vec3 (i * h + (lower ? 0 : 2), lower ? 0 : 40, z), i * h, j * h, pinned ? 0 : 0.5, 0.3, 1.5);
    }
    for (int j = 0; j < rows; j++) for (int i = 0; i < n; i++) {
        int a = j * n + i;
        if (i < n - 1) s.add_constraint (a, a + 1, h, 1e-7, 0);
        if (j < rows - 1) s.add_constraint (a, a + n, j == n - 1 ? s.pos (a).distance (s.pos (a + n)) : h, 1e-7, 0);
        if (i < n - 1 && j < rows - 1) {
            if (j != n - 1) s.add_constraint (a, a + n + 1, h * Math.SQRT2, 1e-6, 1);
            s.add_tri (a, a + 1, a + n);
            s.add_tri (a + 1, a + n + 1, a + n);
        }
    }
    s.group = new int[s.n];
    s.spacing = h;
    s.damping = 0.05;
    return s;
}

double fold_gap (ClothState s, out int wrong) {
    int n = 12;
    double worst = double.INFINITY;
    wrong = 0;
    for (int i = n * 15; i < s.n; i++) {
        if (i % n == 0 || i % n == n - 1) continue;
        double px = s.x[i], pz = s.z[i];
        for (int t = 0; t < s.nt; t++) {
            int a = s.tris[t * 3], b = s.tris[t * 3 + 1], c = s.tris[t * 3 + 2];
            if (a >= n * 12 || b >= n * 12 || c >= n * 12) continue;
            double x1 = s.x[b] - s.x[a], z1 = s.z[b] - s.z[a];
            double x2 = s.x[c] - s.x[a], z2 = s.z[c] - s.z[a];
            double det = x1 * z2 - x2 * z1;
            if (det.abs () < 1e-9) continue;
            double qx = px - s.x[a], qz = pz - s.z[a];
            double u = (qx * z2 - x2 * qz) / det;
            double v = (x1 * qz - qx * z1) / det;
            if (u < 0 || v < 0 || u + v > 1) continue;
            double y = s.y[a] + u * (s.y[b] - s.y[a]) + v * (s.y[c] - s.y[a]);
            double side = s.y[i] - y;
            worst = double.min (worst, side);
            if (side < 0) wrong++;
        }
    }
    return worst;
}

double upper_minus_lower (ClothState s) {
    int n = 12;
    double up = 0, lo = 0;
    for (int i = 0; i < n * 11; i++) lo += s.y[i];
    for (int i = n * 15; i < s.n; i++) up += s.y[i];
    return up / (s.n - n * 15) - lo / (n * 11);
}

void test_self_collision () {
    var fold = folded_sheet ();
    var fs = new ParallelXpbdSolver ();
    for (int f = 0; f < 90; f++) fs.step (fold, null, 1.0 / 60, 10);
    int wrong;
    double fg = fold_gap (fold, out wrong);
    check (wrong == 0 && upper_minus_lower (fold) > 0, "folded sheet does not pass through itself (%f mm, %d crossed)".printf (fg, wrong));
    var fold_off = folded_sheet ();
    var fs_off = new ParallelXpbdSolver ();
    fs_off.self_collision = false;
    for (int f = 0; f < 90; f++) fs_off.step (fold_off, null, 1.0 / 60, 10);
    check (upper_minus_lower (fold_off) < 0, "without self collision the fold passes through (%f mm)".printf (upper_minus_lower (fold_off)));
    var on = two_layers ();
    var solver = new ParallelXpbdSolver ();
    for (int f = 0; f < 90; f++) solver.step (on, null, 1.0 / 60, 10);
    double gap_on = layer_gap (on);
    check (gap_on > 0.5, "upper layer rests on the lower one (%f mm)".printf (gap_on));
    var off = two_layers ();
    var plain = new ParallelXpbdSolver ();
    plain.self_collision = false;
    for (int f = 0; f < 90; f++) plain.step (off, null, 1.0 / 60, 10);
    check (layer_gap (off) < 0, "without self collision the layers pass through (%f mm)".printf (layer_gap (off)));
}

double bench (ClothSolver solver, int frames, out double gap) {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var settings = new GarmentSettings ();
    settings.resolution = 14;
    var sim = new GarmentSim (p.evaluate ("38"), settings, p.table, "38");
    sim.solver = solver;
    var t0 = get_monotonic_time ();
    sim.run (frames);
    gap = sim.max_sew_gap ();
    return (get_monotonic_time () - t0) / 1e6;
}

double best_of (ClothSolver solver, int frames, int runs, out double gap) {
    double best = double.MAX;
    gap = 0;
    for (int r = 0; r < runs; r++) best = double.min (best, bench (solver, frames, out gap));
    return best;
}

void test_benchmark () {
    double g1, g2, g3, g4;
    int threads = ((int) get_num_processors ()).clamp (1, 16);
    int runs = Environment.get_variable ("ATELIER_BENCH") != null ? 3 : 1;
    double t_serial = best_of (new CpuXpbdSolver (), 120, runs, out g1);
    var nocoll = new ParallelXpbdSolver (new WorkPool (threads));
    nocoll.self_collision = false;
    nocoll.adaptive = false;
    double t_nocoll = best_of (nocoll, 120, runs, out g2);
    double t_one = best_of (new ParallelXpbdSolver (new WorkPool (1)), 120, runs, out g3);
    var fixed_many = new ParallelXpbdSolver (new WorkPool (threads));
    fixed_many.adaptive = false;
    double t_many = best_of (fixed_many, 120, runs, out g4);
    double g5;
    best_of (new ParallelXpbdSolver (new WorkPool (threads)), 120, 1, out g5);
    print ("benchmark t-shirt 14 mm, 120 frames, best of %d: before (serial, no self collision) %.2f s; after, %d threads without self collision %.2f s (%.2fx); with self and layer collision 1 thread %.2f s, %d threads %.2f s (%.2fx); seam gaps %.2f %.2f %.2f %.2f mm\n",
        runs, t_serial, threads, t_nocoll, t_serial / t_nocoll, t_one, threads, t_many, t_one / t_many, g1, g2, g3, g4);
    check (g2 < 8 && g4 < 8, "parallel solver closes the seams too");
    check (near (g5, g3, 1e-9), "adaptive solver gives the same seams");
    if (Environment.get_variable ("ATELIER_BENCH") != null) {
        int wins = 0;
        int serial_wins = 0;
        for (int r = 0; r < 3; r++) {
            double g;
            var one = new ParallelXpbdSolver (new WorkPool (1));
            var all = new ParallelXpbdSolver (new WorkPool (threads));
            all.adaptive = false;
            var auto = new ParallelXpbdSolver (new WorkPool (threads));
            var auto_free = new ParallelXpbdSolver (new WorkPool (threads));
            auto_free.self_collision = false;
            double a = bench (one, 40, out g), b = bench (all, 40, out g), c = bench (auto, 40, out g);
            double d = bench (new CpuXpbdSolver (), 40, out g), e = bench (auto_free, 40, out g);
            print ("adaptive round %d, 40 frames: one thread %.2f s, %d threads %.2f s, adaptive %.2f s; without collision serial %.2f s, adaptive %.2f s; load %s\n", r + 1, a, threads, b, c, d, e, load_average ());
            if (c <= 1.25 * double.min (a, b)) wins++;
            if (e <= 1.25 * d) serial_wins++;
        }
        check (wins >= 2, "adaptive solver keeps up with the faster of one thread and all threads");
        check (serial_wins >= 2, "adaptive solver is not slower than the serial solver");
    }
}

string load_average () {
    try {
        string text;
        FileUtils.get_contents ("/proc/loadavg", out text);
        return text.split (" ")[0];
    } catch (Error e) {
        return "unknown";
    }
}

void test_adaptive_workers () {
    var auto = new ParallelXpbdSolver (new WorkPool (4));
    auto.tune_period = 8;
    var one = new ParallelXpbdSolver (new WorkPool (1));
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var settings = new GarmentSettings ();
    settings.resolution = 20;
    var a = new GarmentSim (p.evaluate ("38"), settings, p.table, "38");
    var b = new GarmentSim (p.evaluate ("38"), settings, p.table, "38");
    a.solver = auto;
    b.solver = one;
    a.run (20);
    b.run (20);
    check (auto.workers == 1 || auto.workers == 4, "adaptive solver picks one thread or the whole pool (%d)".printf (auto.workers));
    bool same = a.state.n == b.state.n;
    for (int i = 0; same && i < a.state.n; i++) same = a.state.x[i] == b.state.x[i] && a.state.y[i] == b.state.y[i] && a.state.z[i] == b.state.z[i];
    check (same, "switching thread count during the run does not change the result");
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

void test_renderer () {
    var pm = new ProductModel ();
    pm.make_cube (100);
    var meshes = new Gee.ArrayList<Mesh> ();
    meshes.add (pm.subdivided ());
    var cam = new Camera ();
    cam.frame (meshes);
    var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, 160, 120);
    var r = new CpuRenderer ();
    foreach (var shading in new string[] { "material", "wireframe", "zebra", "curvature" }) {
        var opt = new RenderOptions ();
        opt.shading = shading;
        r.render (surf, meshes, cam, opt);
    }
    int mi, vi;
    check (r.pick (80, 60, out mi, out vi) && mi == 0, "center pixel hits the model");
    check (!r.pick (2, 2, out mi, out vi), "corner is background");
    surf.flush ();
    unowned uint8[] d = surf.get_data ();
    int o = 60 * surf.get_stride () + 80 * 4;
    int o2 = 2 * surf.get_stride () + 2 * 4;
    check (d[o] != d[o2] || d[o + 1] != d[o2 + 1], "model pixels differ from background");
}

int main () {
    test_self_collision ();
    test_adaptive_workers ();
    test_benchmark ();
    test_avatar ();
    test_fabrics ();
    test_hanging_patch ();
    test_subdivision ();
    test_renderer ();
    test_garment ();
    return finish ("sim");
}
