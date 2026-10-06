using Singularity.Vector;
using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

string load (string name) {
    string text = "";
    try {
        FileUtils.get_contents (Path.build_filename (fixtures (), "seamly", name), out text);
    } catch (Error e) {
        check (false, "fixture %s: %s".printf (name, e.message));
    }
    return text;
}

Pattern? open_pattern (string pattern_file, string measure_file, out SeamlyReport report) {
    report = null;
    try {
        var table = Seamly.read_measurements (load (measure_file));
        return Seamly.read_pattern (load (pattern_file), out report, table);
    } catch (FormatError e) {
        check (false, "%s: %s".printf (pattern_file, e.message));
        return null;
    }
}

void test_measurements () {
    try {
        var t = Seamly.read_measurements (load ("keiko.smis"));
        check (t.kind == TableKind.INDIVIDUAL, "individual table");
        check (t.items.size > 10, "measurements read");
        var gost = Seamly.read_measurements (load ("gost_man_ru.smms"));
        check (gost.kind == TableKind.MULTISIZE && gost.unit == "mm", "multisize table in mm");
        check (gost.sizes.size == 7 && gost.base_size == "50", "size run around base size 50: %s".printf (gost.base_size));
        check (near (gost.value ("bust_circ", "50"), 1044), "base value");
        check (near (gost.value ("bust_circ", "52"), 1082), "size increase applied");
        var written = Seamly.write_measurements (gost);
        var back = Seamly.read_measurements (written);
        check (back.items.size == gost.items.size, "multisize write and read keep the count");
        check (near (back.value ("bust_circ", "52"), 1082), "multisize round trip value");
        var iw = Seamly.write_measurements (t);
        var ib = Seamly.read_measurements (iw);
        check (ib.items.size == t.items.size && near (ib.value ("bust_circ"), t.value ("bust_circ")), "individual round trip");
    } catch (Error e) {
        check (false, e.message);
    }
}

void test_pattern (string file, string measures, int min_points, int pieces) {
    SeamlyReport rep;
    var p = open_pattern (file, measures, out rep);
    if (p == null) return;
    check (rep.points >= min_points, "%s: %d points read".printf (file, rep.points));
    check (rep.pieces == pieces, "%s: %d pieces (expected %d)".printf (file, rep.pieces, pieces));
    var r = p.evaluate ();
    int errs = r.errors.size;
    foreach (var e in r.errors.entries) stderr.printf ("  %s eval: %s %s\n", file, e.key, e.value);
    check (errs == 0, "%s: evaluates without errors (%d)".printf (file, errs));
    foreach (var g in r.pieces) {
        check (g.error == "" && g.seam.length > 3, "%s: piece %s has an outline %s".printf (file, g.piece.name, g.error));
        check (Polyline.signed_area (g.seam).abs () > 100, "%s: piece %s has a real area".printf (file, g.piece.name));
    }
    string back = Seamly.write_pattern (p, measures);
    SeamlyReport rep2;
    try {
        var p2 = Seamly.read_pattern (back, out rep2, p.table);
        var r2 = p2.evaluate ();
        check (r2.errors.size == 0, "%s: written pattern evaluates".printf (file));
        check (r2.pieces.size == r.pieces.size, "%s: pieces survive writing".printf (file));
        int moved = 0;
        foreach (var pt in p.points) {
            var q = p2.point_by_name (pt.name);
            if (q == null || !r.points.has_key (pt.id) || !r2.points.has_key (q.id)) continue;
            if (r.points[pt.id].distance (r2.points[q.id]) > 0.01) moved++;
        }
        check (moved == 0, "%s: %d points moved after writing".printf (file, moved));
    } catch (FormatError e) {
        check (false, e.message);
    }
}

int main () {
    test_measurements ();
    test_pattern ("keiko_skirt.sm2d", "keiko.smis", 35, 2);
    test_pattern ("male_shirt.sm2d", "male_shirt.smis", 120, 17);
    return finish ("seamly");
}
