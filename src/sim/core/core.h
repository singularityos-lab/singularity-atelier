#ifndef ATELIER_CORE_H
#define ATELIER_CORE_H

typedef struct _AtSdf AtSdf;
typedef struct _AtCloth AtCloth;

typedef struct {
    float stretch_u;
    float stretch_v;
    float shear;
    float bend_u;
    float bend_v;
    float density;
    float friction;
    float thickness;
    float damping;
    float shrink_u;
    float shrink_v;
} AtFabric;

int at_triangulate (const double *boundary, int nb, const int *loops, int nloops, double spacing,
                    double **out_points, int *out_npoints, int **out_tris, int *out_ntris);
void at_free (void *p);

AtSdf *at_sdf_build (const float *pos, int nv, const unsigned int *tri, int ntri, float cell, float margin);
void at_sdf_free (AtSdf *s);
float at_sdf_sample (const AtSdf *s, float x, float y, float z, float *grad);

AtCloth *at_cloth_new (void);
void at_cloth_free (AtCloth *c);
int at_cloth_add_fabric (AtCloth *c, const AtFabric *f);
void at_cloth_set_fabric (AtCloth *c, int fabric, const AtFabric *f);
int at_cloth_add_particle (AtCloth *c, float x, float y, float z, float u, float v, int piece);
void at_cloth_add_triangle (AtCloth *c, int a, int b, int d, int fabric);
void at_cloth_add_seam (AtCloth *c, int i, int j, int k, float w, float gap);
void at_cloth_clear_seams (AtCloth *c);
void at_cloth_finalize (AtCloth *c);
void at_cloth_set_collider (AtCloth *c, const AtSdf *sdf, float offset);
void at_cloth_separate (AtCloth *c, float extra);
void at_cloth_set_gravity (AtCloth *c, float g);
void at_cloth_set_drag (AtCloth *c, float keep);
void at_cloth_pin (AtCloth *c, int i, int pinned);
void at_cloth_grab (AtCloth *c, int i, float x, float y, float z, float radius);
void at_cloth_grab_move (AtCloth *c, float x, float y, float z);
void at_cloth_release (AtCloth *c);
void at_cloth_step (AtCloth *c, float dt, int substeps);
int at_cloth_count (const AtCloth *c);
int at_cloth_triangle_count (const AtCloth *c);
const float *at_cloth_positions (const AtCloth *c);
void at_cloth_set_position (AtCloth *c, int i, float x, float y, float z);
void at_cloth_strain (const AtCloth *c, float *out);
void at_cloth_distance (const AtCloth *c, float *out);
float at_cloth_seam_gap (const AtCloth *c);
float at_cloth_kinetic (const AtCloth *c);

#endif
