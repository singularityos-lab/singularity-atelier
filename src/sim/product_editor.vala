namespace Singularity.Apps.Atelier {

    public errordomain ProductError {
        NEEDS_CURVE
    }

    public class ProductEditor : Object {
        private Project project;
        private History history;
        private PlaneCurve? stroke;
        private string? stroke_snapshot;

        public ProductModel model {
            get { return project.product; }
        }

        public bool drawing {
            get { return stroke != null; }
        }

        public ProductEditor (Project project, History history) {
            this.project = project;
            this.history = history;
            history.restored.connect (() => {
                stroke = null;
                stroke_snapshot = null;
            });
        }

        private void edited () {
            project.touch ("product");
        }

        public void primitive (string kind) {
            history.checkpoint ();
            switch (kind) {
                case "cylinder":
                    model.make_cylinder (100, 240, 8);
                    break;
                case "sphere":
                    model.make_sphere (120, 8);
                    break;
                default:
                    model.make_cube (200);
                    break;
            }
            edited ();
        }

        public bool set_levels (int levels) {
            if (levels == model.levels) return false;
            history.checkpoint ();
            model.levels = levels;
            edited ();
            return true;
        }

        public bool set_material (string id) {
            if (id == model.material || !(id in ProductModel.MATERIALS)) return false;
            history.checkpoint ();
            model.material = id;
            foreach (var mesh in model.surfaces) ProductModel.apply_material (mesh, id);
            edited ();
            return true;
        }

        private bool face_exists (int face) {
            return face >= 0 && face < model.faces.size;
        }

        public bool extrude_face (int face, double amount) {
            if (!face_exists (face)) return false;
            history.checkpoint ();
            model.extrude_face (face, amount);
            edited ();
            return true;
        }

        public bool inset_face (int face, double amount) {
            if (!face_exists (face)) return false;
            history.checkpoint ();
            model.inset_face (face, amount);
            edited ();
            return true;
        }

        public bool delete_face (int face) {
            if (!face_exists (face)) return false;
            history.checkpoint ();
            model.delete_face (face);
            edited ();
            return true;
        }

        public bool crease_face (int face, bool sharp) {
            if (!face_exists (face)) return false;
            history.checkpoint ();
            model.crease_face (face, sharp);
            edited ();
            return true;
        }

        public bool move_face (int face, Vec3 delta) {
            if (!face_exists (face) || delta.length () == 0) return false;
            history.checkpoint ();
            model.move_face (face, delta);
            edited ();
            return true;
        }

        public void begin_stroke (string plane, double offset) {
            end_stroke ();
            stroke_snapshot = history.snapshot ();
            stroke = new PlaneCurve (plane, offset);
            model.sketches.add (stroke);
        }

        public bool stroke_point (double a, double b) {
            if (stroke == null) return false;
            int n = stroke.count ();
            if (n > 0 && Math.hypot (a - stroke.points[(n - 1) * 2], b - stroke.points[(n - 1) * 2 + 1]) < 4) return false;
            stroke.add (a, b);
            return true;
        }

        public bool end_stroke () {
            if (stroke == null) return false;
            bool kept = stroke.count () >= 2;
            if (kept) {
                history.commit (stroke_snapshot);
                edited ();
            } else {
                model.sketches.remove (stroke);
            }
            stroke = null;
            stroke_snapshot = null;
            return kept;
        }

        public void add_circle (string plane, double offset, double radius) {
            history.checkpoint ();
            var exact = NurbsCurve.circle (Vec3 (0, 0, 0), radius, Vec3 (1, 0, 0), Vec3 (0, 1, 0));
            var curve = new PlaneCurve (plane, offset);
            foreach (var p in exact.sample (96)) curve.add (p.x, p.y);
            curve.closed = true;
            curve.exact = exact;
            model.sketches.add (curve);
            edited ();
        }

        public bool remove_last_curve () {
            if (model.sketches.size == 0) return false;
            history.checkpoint ();
            model.sketches.remove_at (model.sketches.size - 1);
            edited ();
            return true;
        }

        public bool clear_surfaces () {
            if (model.surfaces.size == 0 && model.nurbs.size == 0) return false;
            history.checkpoint ();
            model.surfaces.clear ();
            model.nurbs.clear ();
            edited ();
            return true;
        }

        private PlaneCurve last_curve () throws ProductError {
            var curve = model.sketches.size > 0 ? model.sketches[model.sketches.size - 1] : null;
            if (curve == null || curve.count () < 2) throw new ProductError.NEEDS_CURVE (_("Draw a curve on a plane first"));
            return curve;
        }

        private static double[] profile (PlaneCurve curve, int samples) {
            double[] pts = new double[curve.points.size];
            for (int i = 0; i < pts.length; i++) pts[i] = curve.points[i];
            return Surfaces.bspline (Polyline2.reduce (pts, 60), 3, samples);
        }

        private void add_surface (Mesh mesh, NurbsSurface? exact) {
            ProductModel.apply_material (mesh, model.material);
            model.surfaces.add (mesh);
            if (exact != null) model.nurbs.add (exact);
        }

        public void revolve () throws ProductError {
            var curve = last_curve ();
            var prof = profile (curve, 48);
            for (int i = 0; i < prof.length; i += 2) prof[i] = prof[i].abs ();
            var flat = curve.to_nurbs_2d (60);
            var axis_side = new NurbsCurve (flat.degree);
            foreach (var p in flat.ctrl) axis_side.ctrl.add (Vec3 (p.x.abs (), p.y, 0));
            foreach (var w in flat.weights) axis_side.weights.add (w);
            axis_side.knots = flat.knots;
            history.checkpoint ();
            add_surface (Surfaces.revolve (prof, 48), NurbsSurface.revolve (axis_side));
            edited ();
        }

        public void extrude (double depth) throws ProductError {
            var curve = last_curve ();
            var mesh = Surfaces.extrude (profile (curve, 48), depth, true);
            for (int i = 0; i < mesh.vertices.size; i++) {
                var v = mesh.vertices[i];
                mesh.vertices[i] = PlaneCurve.to3d (curve.plane, curve.offset + v.z, v.x, v.y);
            }
            mesh.compute_normals ();
            history.checkpoint ();
            add_surface (mesh, NurbsSurface.extrude (curve.to_nurbs (60), curve.normal ().scale (depth)));
            edited ();
        }

        public void sweep (double diameter) throws ProductError {
            var curve = last_curve ();
            var prof = profile (curve, 48);
            var path = new Gee.ArrayList<Vec3?> ();
            for (int i = 0; i < prof.length; i += 2) path.add (PlaneCurve.to3d (curve.plane, curve.offset, prof[i], prof[i + 1]));
            double r = diameter / 2;
            double[] circle = {};
            for (int i = 0; i < 16; i++) {
                double a = 2 * Math.PI * i / 16;
                circle += r * Math.cos (a);
                circle += r * Math.sin (a);
            }
            history.checkpoint ();
            add_surface (Surfaces.sweep (circle, path, true), NurbsSurface.sweep_circle (curve.to_nurbs (60), r));
            edited ();
        }

        public void loft () throws ProductError {
            var sections = new Gee.ArrayList<Gee.ArrayList<Vec3?>> ();
            var rows = new Gee.ArrayList<NurbsCurve> ();
            foreach (var curve in model.sketches) {
                if (curve.count () < 2) continue;
                var smooth = profile (curve, 40);
                var section = new Gee.ArrayList<Vec3?> ();
                for (int i = 0; i < smooth.length; i += 2) section.add (PlaneCurve.to3d (curve.plane, curve.offset, smooth[i], smooth[i + 1]));
                sections.add (section);
                rows.add (curve.to_nurbs (16, true));
            }
            if (sections.size < 2) throw new ProductError.NEEDS_CURVE (_("Draw at least two curves to loft between"));
            history.checkpoint ();
            add_surface (Surfaces.loft (sections, false), NurbsSurface.loft (rows));
            edited ();
        }
    }

    namespace Polyline2 {
        public double[] reduce (double[] pts, int max_points) {
            int n = pts.length / 2;
            if (n <= max_points) return pts;
            double[] r = {};
            for (int i = 0; i < max_points; i++) {
                int k = (int) Math.round ((double) i / (max_points - 1) * (n - 1));
                r += pts[k * 2];
                r += pts[k * 2 + 1];
            }
            return r;
        }
    }
}
