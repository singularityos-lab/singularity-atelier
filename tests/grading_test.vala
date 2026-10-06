using Singularity.Vector;
using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

int main () {
    var p = new Pattern ();
    Samples.tshirt_pattern (p);
    var nest = Grading.nest (p);
    check (nest.size == p.table.sizes.size, "one result per size");
    double prev = 0;
    foreach (var s in p.table.sizes) {
        var g = nest[s].pieces[0];
        double w = g.bounds ().w;
        check (w > prev, "front grows with size %s".printf (s));
        prev = w;
    }
    var f38 = nest["38"].pieces[0].bounds ().w;
    var f40 = nest["40"].pieces[0].bounds ().w;
    check (near (f40 - f38, 10, 0.5), "one size step adds a quarter of 4 cm bust ease (%f mm)".printf (f40 - f38));
    var base_geom = nest["38"].pieces[0];
    var big = nest["46"].pieces[0];
    var off = Grading.anchor_offset (base_geom, big, "grain");
    check (near (big.grain_a.x + off.x, base_geom.grain_a.x) && near (big.grain_a.y + off.y, base_geom.grain_a.y), "nest aligned on the grain line");
    Grading.derive_rules (p, nest);
    p.grading = "rules";
    foreach (var s in p.table.sizes) {
        var rr = p.evaluate (s);
        foreach (var pt in p.points) {
            if (!rr.points.has_key (pt.id) || !nest[s].points.has_key (pt.id)) continue;
            check (rr.points[pt.id].distance (nest[s].points[pt.id]) < 0.01, "rule grading reproduces point %s in %s".printf (pt.name, s));
        }
    }
    p.grading = "measurements";
    p.table.find ("hip_circ").per_size["44"] = 130;
    var r44 = p.evaluate ("44");
    check (r44.pieces[0].bounds ().w > nest["44"].pieces[0].bounds ().w + 20, "graduazione per misure uses the individual size value");
    return finish ("grading");
}
