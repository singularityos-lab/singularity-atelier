using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

Project fresh (out History history, out ProductEditor editor) {
    var p = Project.create ("product");
    p.product.make_cube (200);
    history = new History (p);
    editor = new ProductEditor (p, history);
    return p;
}

void draw (ProductEditor editor, string plane, double offset, double[] pts) {
    editor.begin_stroke (plane, offset);
    for (int i = 0; i + 1 < pts.length; i += 2) editor.stroke_point (pts[i], pts[i + 1]);
    editor.end_stroke ();
}

void check_undo_redo (Project p, History history, string before, string what) {
    string after = NativeFormat.to_json (p);
    check (after != before, what + " changes the project");
    check (p.modified, what + " marks the project modified");
    history.undo ();
    check (NativeFormat.to_json (p) == before, what + " undo restores the project");
    history.redo ();
    check (NativeFormat.to_json (p) == after, what + " redo restores the edit");
}

void test_cage_edits () {
    History history;
    ProductEditor editor;
    var p = fresh (out history, out editor);
    string before = NativeFormat.to_json (p);
    editor.primitive ("cylinder");
    check (p.product.faces.size == 10, "cylinder cage has 10 faces");
    check_undo_redo (p, history, before, "primitive");

    history.clear ();
    p.modified = false;
    check (!editor.extrude_face (-1, 30) && !editor.inset_face (99, 10) && !editor.delete_face (99), "edits without a valid face are refused");
    check (!editor.move_face (0, Vec3 (0, 0, 0)), "a zero move is refused");
    check (!history.can_undo && !p.modified, "refused edits leave no undo step");

    before = NativeFormat.to_json (p);
    int faces = p.product.faces.size;
    int sides = p.product.faces[0].size;
    check (editor.extrude_face (0, 30) && p.product.faces.size == faces + sides, "extrude adds the side faces");
    check_undo_redo (p, history, before, "extrude");
    before = NativeFormat.to_json (p);
    check (editor.crease_face (1, true), "crease a face");
    check_undo_redo (p, history, before, "crease");
    before = NativeFormat.to_json (p);
    check (editor.move_face (1, Vec3 (0, 15, 0)), "move a face");
    check_undo_redo (p, history, before, "move");

    history.clear ();
    check (!editor.set_levels (p.product.levels), "same smoothness is not an edit");
    check (!editor.set_material (p.product.material) && !editor.set_material ("unobtainium"), "same or unknown material is not an edit");
    check (!history.can_undo, "no-op settings leave no undo step");
    before = NativeFormat.to_json (p);
    check (editor.set_levels (p.product.levels + 1), "smoothness changes");
    check_undo_redo (p, history, before, "smoothness");
    before = NativeFormat.to_json (p);
    check (editor.set_material ("leather") && p.product.material == "leather", "material changes");
    check_undo_redo (p, history, before, "material");
}

void test_strokes () {
    History history;
    ProductEditor editor;
    var p = fresh (out history, out editor);
    string before = NativeFormat.to_json (p);
    draw (editor, "xy", 10, { 0, 0, 1, 1, 10, 10, 20, 0 });
    check (p.product.sketches.size == 1 && p.product.sketches[0].count () == 3, "stroke keeps its points and drops jitter");
    check (near (p.product.sketches[0].offset, 10) && p.product.sketches[0].plane == "xy", "stroke keeps its plane");
    check (history.can_undo && !editor.drawing, "a finished stroke is one undo step");
    check_undo_redo (p, history, before, "stroke");

    history.undo ();
    check (history.can_redo, "redo available after undoing the stroke");
    p.modified = false;
    draw (editor, "xz", 0, { 5, 5 });
    check (p.product.sketches.size == 0, "a single click leaves no curve");
    check (history.can_redo && !p.modified, "a single click keeps redo and the saved state");

    history.redo ();
    editor.begin_stroke ("yz", 0);
    editor.stroke_point (0, 0);
    editor.stroke_point (40, 0);
    history.undo ();
    check (!editor.drawing && !editor.end_stroke (), "undo during a stroke abandons it");
    check (p.product.sketches.size == 0 && NativeFormat.to_json (p) == before, "undo during a stroke restores the state before the first stroke");
}

void test_curves_and_surfaces () {
    History history;
    ProductEditor editor;
    var p = fresh (out history, out editor);
    history.clear ();
    p.modified = false;
    foreach (var name in new string[] { "revolve", "extrude", "sweep", "loft" }) {
        bool refused = false;
        try {
            if (name == "revolve") editor.revolve ();
            else if (name == "extrude") editor.extrude (40);
            else if (name == "sweep") editor.sweep (40);
            else editor.loft ();
        } catch (ProductError e) {
            refused = e.message != "";
        }
        check (refused, name + " without curves explains what is missing");
    }
    check (!history.can_undo && !p.modified && p.product.surfaces.size == 0, "refused surface operations change nothing");
    check (!editor.remove_last_curve () && !editor.clear_surfaces (), "nothing to remove is not an edit");

    string before = NativeFormat.to_json (p);
    editor.add_circle ("xz", -20, 60);
    var circle = p.product.sketches[0];
    check (circle.closed && circle.exact != null && near (circle.exact.weights[1], Math.sqrt (0.5), 1e-15), "circle is an exact rational curve");
    check (near (circle.exact.eval (0.3).length (), 60, 1e-9), "circle radius is exact");
    check_undo_redo (p, history, before, "circle");

    try {
        before = NativeFormat.to_json (p);
        editor.revolve ();
        check (p.product.surfaces.size == 1 && p.product.nurbs.size == 1, "revolve builds a mesh and a NURBS surface");
        check (p.product.surfaces[0].material == p.product.material, "surface gets the product material");
        check_undo_redo (p, history, before, "revolve");
        before = NativeFormat.to_json (p);
        check (editor.set_material ("metal") && p.product.surfaces[0].material == "metal" && near (p.product.surfaces[0].metallic, 1), "material change restyles the built surfaces");
        check_undo_redo (p, history, before, "surface material");
        before = NativeFormat.to_json (p);
        editor.extrude (25);
        var ext = p.product.nurbs[1];
        check (near (ext.eval (0.2, 1).sub (ext.eval (0.2, 0)).length (), 25, 1e-9), "extrude depth is exact");
        check_undo_redo (p, history, before, "extrude surface");
        before = NativeFormat.to_json (p);
        editor.sweep (20);
        check (p.product.nurbs.size == 3, "sweep adds a surface");
        check_undo_redo (p, history, before, "sweep");
        draw (editor, "xz", 80, { -40, -40, 0, -50, 40, -40, 50, 0, 40, 40 });
        before = NativeFormat.to_json (p);
        editor.loft ();
        check (p.product.nurbs.size == 4 && p.product.surfaces.size == 4, "loft joins the curves");
        check_undo_redo (p, history, before, "loft");
    } catch (ProductError e) {
        check (false, "surface: " + e.message);
    }

    before = NativeFormat.to_json (p);
    check (editor.remove_last_curve () && p.product.sketches.size == 1, "remove the last curve");
    check_undo_redo (p, history, before, "remove curve");
    before = NativeFormat.to_json (p);
    check (editor.clear_surfaces () && p.product.surfaces.size == 0 && p.product.nurbs.size == 0, "clear the surfaces");
    check_undo_redo (p, history, before, "clear surfaces");

    history.undo ();
    try {
        string path = Path.build_filename (tmp_dir (), "edited.atelier");
        p.title = "edited";
        NativeFormat.save_to (p, path);
        var q = NativeFormat.load (path);
        check (NativeFormat.to_json (q) == NativeFormat.to_json (p), "edited product reopens unchanged");
        check (q.product.nurbs.size == 4 && q.product.sketches.size == 1 && q.product.surfaces.size == 4, "reopened product keeps every curve and surface");
    } catch (Error e) {
        check (false, "save edited product: " + e.message);
    }
}

int main () {
    test_cage_edits ();
    test_strokes ();
    test_curves_and_surfaces ();
    return finish ("product");
}
