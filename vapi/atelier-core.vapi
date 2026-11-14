[CCode (cheader_filename = "sim/core/core.h")]
namespace AtCore {
    [CCode (cname = "AtFabric", has_type_id = false, destroy_function = "")]
    public struct Fabric {
        public float stretch_u;
        public float stretch_v;
        public float shear;
        public float bend_u;
        public float bend_v;
        public float density;
        public float friction;
        public float thickness;
        public float damping;
        public float shrink_u;
        public float shrink_v;
    }

    [CCode (cname = "at_triangulate")]
    public int triangulate ([CCode (array_length = false)] double[] boundary, int nb, [CCode (array_length = false)] int[]? loops, int nloops, double spacing, out double* points, out int npoints, out int* tris, out int ntris);
    [CCode (cname = "at_free")]
    public void free (void* p);

    [Compact]
    [CCode (cname = "AtSdf", free_function = "at_sdf_free", cprefix = "at_sdf_")]
    public class Sdf {
        [CCode (cname = "at_sdf_build")]
        public static Sdf? build ([CCode (array_length = false)] float[] pos, int nv, [CCode (array_length = false)] uint[] tri, int ntri, float cell, float margin);
        public float sample (float x, float y, float z, [CCode (array_length = false)] float[]? grad);
    }

    [Compact]
    [CCode (cname = "AtCloth", free_function = "at_cloth_free", cprefix = "at_cloth_")]
    public class Cloth {
        [CCode (cname = "at_cloth_new")]
        public Cloth ();
        public int add_fabric (Fabric f);
        public void set_fabric (int fabric, Fabric f);
        public int add_particle (float x, float y, float z, float u, float v, int piece);
        public void add_triangle (int a, int b, int d, int fabric);
        public void add_seam (int i, int j, int k, float w, float gap);
        public void clear_seams ();
        public void finalize ();
        public void set_collider (Sdf? sdf, float offset);
        public void separate (float extra);
        public void set_gravity (float g);
        public void set_drag (float keep);
        public void pin (int i, int pinned);
        public void grab (int i, float x, float y, float z, float radius);
        public void grab_move (float x, float y, float z);
        public void release ();
        public void step (float dt, int substeps);
        public int count ();
        public int triangle_count ();
        [CCode (array_length = false)]
        public unowned float[] positions ();
        public void set_position (int i, float x, float y, float z);
        public void strain ([CCode (array_length = false)] float[] out_values);
        public void distance ([CCode (array_length = false)] float[] out_values);
        public float seam_gap ();
        public float kinetic ();
    }
}
