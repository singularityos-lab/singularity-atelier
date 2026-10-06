using Singularity.Vector;
using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

void compare (Pattern src, Gee.List<Piece> imported, DxfFlavor flavor) {
    string label = flavor == DxfFlavor.AAMA ? "aama" : "astm";
    check (imported.size == src.pieces.size, "%s: piece count %d".printf (label, imported.size));
    foreach (var size in src.table.sizes) {
        var r = src.evaluate (size);
        foreach (var g in r.pieces) {
            Piece? im = null;
            foreach (var p in imported) if (p.name == g.piece.name) im = p;
            check (im != null, "%s: piece %s imported".printf (label, g.piece.name));
            if (im == null) continue;
            check (im.fixed_sizes.has_key (size), "%s: %s has size %s".printf (label, g.piece.name, size));
            if (!im.fixed_sizes.has_key (size)) continue;
            var fg = im.fixed_sizes[size];
            check (fg.cut.length == g.cut.length, "%s: %s %s cut point count %d vs %d".printf (label, g.piece.name, size, fg.cut.length, g.cut.length));
            double worst = 0;
            for (int i = 0; i < int.min (fg.cut.length, g.cut.length); i++) worst = double.max (worst, fg.cut[i].distance (g.cut[i]));
            check (worst < 0.001, "%s: %s %s cut points within 1 micron (%f)".printf (label, g.piece.name, size, worst));
            check (fg.seam.length == g.seam.length, "%s: sew line kept".printf (label));
            check (fg.notches.size == g.notches.size, "%s: notches %d vs %d".printf (label, fg.notches.size, g.notches.size));
            for (int i = 0; i < int.min (fg.notches.size, g.notches.size); i++) {
                check (fg.notches[i].at.distance (g.notches[i].cut_at) < 0.001, "%s: notch position".printf (label));
                double da = Math.remainder (fg.notches[i].angle - g.notches[i].angle, 2 * Math.PI).abs ();
                check (da < 0.001, "%s: notch angle %f".printf (label, da));
            }
            check (fg.has_grain && fg.grain_a.distance (g.grain_a) < 0.001 && fg.grain_b.distance (g.grain_b) < 0.001, "%s: grain line".printf (label));
            check (im.quantity == g.piece.quantity, "%s: quantity".printf (label));
            check (im.on_fold == g.piece.on_fold, "%s: fold".printf (label));
        }
    }
}

void test_round_trip (DxfFlavor flavor) {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var opts = new AamaExportOptions ();
    opts.flavor = flavor;
    string text = Aama.export (p, opts);
    check (text.has_prefix ("  0\nSECTION"), "dxf starts with a section");
    check (text.contains ("Piece Name: Front") && text.contains ("Size: 46"), "piece and size annotations");
    check (text.strip ().has_suffix ("EOF"), "dxf ends with EOF");
    string units;
    try {
        var imported = Aama.import (text, out units);
        check (units == "METRIC", "units metric");
        compare (p, imported, flavor);
        var proj = new Project ();
        Aama.import_into (text, proj, true);
        var res = proj.pattern.evaluate ("38");
        check (res.pieces.size == 3, "imported project evaluates three pieces");
        foreach (var g in res.pieces) check (g.cut.length > 3, "imported piece has geometry");
    } catch (FormatError e) {
        check (false, e.message);
    }
}

void test_english_units () {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var opts = new AamaExportOptions ();
    opts.metric = false;
    opts.all_sizes = false;
    string text = Aama.export (p, opts);
    string units;
    try {
        var imported = Aama.import (text, out units);
        check (units == "ENGLISH", "english units detected");
        var g = p.evaluate ().pieces[0];
        var fg = imported[0].fixed_sizes.has_key (p.active_size) ? imported[0].fixed_sizes[p.active_size] : imported[0].fixed;
        check (fg.cut[0].distance (g.cut[0]) < 0.01, "inch conversion round trip");
    } catch (FormatError e) {
        check (false, e.message);
    }
}

void test_foreign_dxf () {
    string text = "0\nSECTION\n2\nBLOCKS\n0\nBLOCK\n8\n0\n2\nCOLLAR\n70\n0\n10\n0\n20\n0\n0\nLWPOLYLINE\n8\n1\n90\n4\n70\n1\n10\n0\n20\n0\n10\n100\n20\n0\n10\n100\n20\n50\n10\n0\n20\n50\n0\nPOINT\n8\n4\n10\n50\n20\n0\n50\n270\n0\nPOINT\n8\n13\n10\n30\n20\n25\n0\nLINE\n8\n7\n10\n50\n20\n10\n11\n50\n21\n40\n0\nTEXT\n8\n1\n10\n10\n20\n10\n40\n2\n1\nPiece Name: Collar\n0\nTEXT\n8\n1\n10\n10\n20\n5\n40\n2\n1\nQuantity: 2\n0\nENDBLK\n0\nENDSEC\n0\nSECTION\n2\nENTITIES\n0\nINSERT\n8\n0\n2\nCOLLAR\n10\n0\n20\n0\n0\nENDSEC\n0\nEOF\n";
    string units;
    try {
        var pieces = Aama.import (text, out units);
        check (pieces.size == 1 && pieces[0].name == "Collar", "lwpolyline block read");
        var fg = pieces[0].fixed;
        check (fg.cut.length == 4, "four boundary points");
        check (near (fg.cut[2].y, -50), "y axis flipped into screen coordinates");
        check (fg.notches.size == 1 && fg.drills.size == 1 && fg.has_grain, "notch, drill and grain read");
        check (pieces[0].quantity == 2, "quantity read");
        check (pieces[0].built_in, "no sew line means allowance built in");
    } catch (FormatError e) {
        check (false, e.message);
    }
}

void test_rules () {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    Grading.derive_rules (p, Grading.nest (p));
    string rul = Aama.export_rules (p);
    check (rul.has_prefix ("ASTM/D6673/RUL"), "rule file header");
    var q = new Pattern ();
    q.table = p.table.copy ();
    Aama.import_rules (rul, q);
    check (q.rules.rules.size == p.rules.rules.size, "rule count round trip");
    foreach (var r in p.rules.rules) {
        var r2 = q.rules.find (r.number);
        check (r2 != null, "rule %d present".printf (r.number));
        if (r2 == null) continue;
        foreach (var s in p.table.sizes) check (r.step (s).distance (r2.step (s)) < 0.001, "rule step round trip");
    }
}

void test_hpgl () {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var r = p.evaluate ();
    var o = new Hpgl.Options ();
    string plt = Hpgl.export (r, o);
    check (plt.has_prefix ("IN;"), "hpgl init");
    Gee.ArrayList<string> labels;
    var paths = Hpgl.parse_paths (plt, out labels);
    check (labels.size == 3, "one label per piece");
    double best = 0;
    foreach (var pl in paths) best = double.max (best, Polyline.length (pl.pts));
    double cut_len = 0;
    foreach (var g in r.pieces) cut_len = double.max (cut_len, Polyline.length (g.cut, true));
    check ((best - cut_len).abs () < 1, "longest plotted path equals the longest cut line (%f vs %f)".printf (best, cut_len));
}

int main () {
    test_round_trip (DxfFlavor.AAMA);
    test_round_trip (DxfFlavor.ASTM);
    test_english_units ();
    test_foreign_dxf ();
    test_rules ();
    test_hpgl ();
    return finish ("dxf");
}
