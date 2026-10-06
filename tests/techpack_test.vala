using Singularity.Vector;
using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

string run (string[] argv) {
    string out_s = "";
    try {
        Process.spawn_sync (null, argv, null, SpawnFlags.SEARCH_PATH, null, out out_s, null, null);
    } catch (Error e) {
    }
    return out_s;
}

void test_pom () {
    var p = Project.create ("fashion");
    var pom = p.techpack.poms[0];
    string? err;
    var v38 = pom.value_for (p.pattern, "38", out err);
    var v42 = pom.value_for (p.pattern, "42", out err);
    check (v38 != null && near (v38, 88.0 / 2 + 5), "POM follows measurements");
    check (v42 != null && near (v42 - v38, 4), "POM graded with sizes");
    pom.values["42"] = 51;
    check (near (pom.value_for (p.pattern, "42", out err), 51), "manual POM value wins");
    var bad = new Pom ("X");
    bad.link = "nope * 2";
    check (bad.value_for (p.pattern, "38", out err) == null && err != null, "bad POM link reports an error");
}

void test_bom () {
    var p = Project.create ("fashion");
    var tp = p.techpack;
    double expected = 0;
    foreach (var b in tp.bom) expected += b.quantity * (1 + b.waste / 100) * b.unit_cost;
    check (near (tp.total_cost (), expected), "BOM total");
    var s = new MarkerSettings ();
    s.resolution = 10;
    s.ratio["38"] = 1;
    s.ratio["42"] = 1;
    double m = Marker.fabric_consumption_m (p.pattern, s, 1);
    check (m > 0.4 && m < 2.5, "fabric consumption from the marker %f m".printf (m));
}

void test_pdf () {
    var p = Project.create ("fashion");
    p.techpack.style_name = "Tee Basic";
    p.techpack.style_number = "AT-001";
    p.techpack.revisions.add (new Revision (1, "Proto"));
    string path = Path.build_filename (tmp_dir (), "techpack.pdf");
    var lay = new TechPackLayout (p);
    lay.write_pdf (path);
    check (FileUtils.test (path, FileTest.EXISTS), "pdf written");
    string info = run ({ "pdfinfo", path });
    if (info != "") {
        check (info.contains ("Pages:"), "pdfinfo reads the file");
        string text = run ({ "pdftotext", "-layout", path, "-" });
        foreach (var w in new string[] { "Tee Basic", "Points of Measure", "Chest width", "Bill of Materials", "Main fabric", "Construction", "Join shoulders", "Pattern Pieces", "Revisions" }) check (text.contains (w), "pdf contains " + w);
        check (text.contains ("48") && text.contains ("46"), "pom values for sizes");
    }
    check (lay.pages.size >= 6, "tech pack pages %d".printf (lay.pages.size));
}

void test_tiles () {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var r = p.evaluate ();
    var area = PatternPrint.print_area (r, true);
    var t = new PatternTiler (area, 539, 785, 10);
    check (t.count () == t.cols * t.rows && t.count () > 1, "pattern needs several A4 pages");
    var last = t.tile (t.count () - 1);
    check (last.x2 () >= area.x2 () - 0.01 && last.y2 () >= area.y2 () - 0.01, "tiles cover the whole pattern");
    var a = t.tile (0);
    var b = t.tile (1);
    check (near (a.x2 () - b.x, 10), "tiles overlap by 10 mm");
    string path = Path.build_filename (tmp_dir (), "large.pdf");
    PatternPrint.write_large_pdf (r, path, true);
    string info = run ({ "pdfinfo", path });
    if (info != "") {
        foreach (var line in info.split ("\n")) {
            if (!line.has_prefix ("Page size:")) continue;
            var parts = line.substring (10).strip ().split (" ");
            double w = double.parse (parts[0]);
            check (near (w / 72 * 25.4, area.w + 20, 1), "large format page is true scale (%f mm)".printf (w / 72 * 25.4));
        }
    }
    string tiled = Path.build_filename (tmp_dir (), "tiled.pdf");
    PatternPrint.write_tiled_pdf (r, tiled, true);
    string ti = run ({ "pdfinfo", tiled });
    if (ti != "") {
        int pages = 0;
        foreach (var line in ti.split ("\n")) if (line.has_prefix ("Pages:")) pages = int.parse (line.substring (6).strip ());
        check (pages == new PatternTiler (area, 595.28 - 56, 841.89 - 56, 10).count (), "tiled pdf page count %d".printf (pages));
    }
}

int main () {
    test_pom ();
    test_bom ();
    test_pdf ();
    test_tiles ();
    return finish ("techpack");
}
