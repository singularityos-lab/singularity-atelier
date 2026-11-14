#include "core.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int v[3];
    int fabric;
    float inv[4];
    float area;
} CTri;

typedef struct {
    int v[4];
    float k[4];
    float scale;
    float rigidity;
} CBend;

typedef struct {
    int i;
    int j;
    int k;
    float w;
    float gap;
} CSeam;

typedef struct {
    int a;
    int b;
    int opp;
    int tri;
} CEdge;

struct _AtCloth {
    int n;
    int cap;
    float *x;
    float *p;
    float *v;
    float *uv;
    float *w;
    float *w0;
    int *piece;
    unsigned char *pinned;
    unsigned char *stitched;
    float *thick;
    float *fric;
    float *damp;

    CTri *tri;
    int ntri;
    int tri_cap;
    CBend *bend;
    int nbend;
    CSeam *seam;
    int nseam;
    int seam_cap;
    AtFabric *fabric;
    int nfabric;

    const AtSdf *sdf;
    float offset;
    float gravity;
    float drag;
    float edge;

    int *grab_i;
    float *grab_off;
    float *grab_wt;
    int ngrab;
    float grab_at[3];

    int *nb_start;
    int *nb;
    float *vs;
    int *cell_start;
    int *cell_tri;
    int ncell;
    float cell;
    float *tn;
};

AtCloth *at_cloth_new (void) {
    AtCloth *c = calloc (1, sizeof (AtCloth));
    c->gravity = 9810.0f;
    c->drag = 1.0f;
    c->offset = 2.0f;
    return c;
}

void at_cloth_free (AtCloth *c) {
    if (!c) return;
    free (c->x);
    free (c->p);
    free (c->v);
    free (c->uv);
    free (c->w);
    free (c->w0);
    free (c->piece);
    free (c->pinned);
    free (c->stitched);
    free (c->thick);
    free (c->fric);
    free (c->damp);
    free (c->tri);
    free (c->bend);
    free (c->seam);
    free (c->fabric);
    free (c->grab_i);
    free (c->grab_off);
    free (c->grab_wt);
    free (c->nb_start);
    free (c->nb);
    free (c->vs);
    free (c->cell_start);
    free (c->cell_tri);
    free (c->tn);
    free (c);
}

int at_cloth_add_fabric (AtCloth *c, const AtFabric *f) {
    c->fabric = realloc (c->fabric, (size_t) (c->nfabric + 1) * sizeof (AtFabric));
    c->fabric[c->nfabric] = *f;
    return c->nfabric++;
}

int at_cloth_add_particle (AtCloth *c, float x, float y, float z, float u, float v, int piece) {
    if (c->n == c->cap) {
        c->cap = c->cap ? c->cap * 2 : 1024;
        size_t n = (size_t) c->cap;
        c->x = realloc (c->x, n * 3 * sizeof (float));
        c->p = realloc (c->p, n * 3 * sizeof (float));
        c->v = realloc (c->v, n * 3 * sizeof (float));
        c->uv = realloc (c->uv, n * 2 * sizeof (float));
        c->w = realloc (c->w, n * sizeof (float));
        c->w0 = realloc (c->w0, n * sizeof (float));
        c->piece = realloc (c->piece, n * sizeof (int));
        c->pinned = realloc (c->pinned, n);
        c->stitched = realloc (c->stitched, n);
        c->thick = realloc (c->thick, n * sizeof (float));
        c->fric = realloc (c->fric, n * sizeof (float));
        c->damp = realloc (c->damp, n * sizeof (float));
    }
    int i = c->n++;
    c->x[i * 3] = c->p[i * 3] = x;
    c->x[i * 3 + 1] = c->p[i * 3 + 1] = y;
    c->x[i * 3 + 2] = c->p[i * 3 + 2] = z;
    c->v[i * 3] = c->v[i * 3 + 1] = c->v[i * 3 + 2] = 0;
    c->uv[i * 2] = u;
    c->uv[i * 2 + 1] = v;
    c->w[i] = c->w0[i] = 0;
    c->piece[i] = piece;
    c->pinned[i] = 0;
    c->stitched[i] = 0;
    c->thick[i] = 1;
    c->fric[i] = 0.3f;
    c->damp[i] = 0.02f;
    return i;
}

void at_cloth_add_triangle (AtCloth *c, int a, int b, int d, int fabric) {
    if (c->ntri == c->tri_cap) {
        c->tri_cap = c->tri_cap ? c->tri_cap * 2 : 2048;
        c->tri = realloc (c->tri, (size_t) c->tri_cap * sizeof (CTri));
    }
    CTri *t = &c->tri[c->ntri++];
    t->v[0] = a;
    t->v[1] = b;
    t->v[2] = d;
    t->fabric = fabric;
}

void at_cloth_add_seam (AtCloth *c, int i, int j, int k, float w, float gap) {
    if (c->nseam == c->seam_cap) {
        c->seam_cap = c->seam_cap ? c->seam_cap * 2 : 512;
        c->seam = realloc (c->seam, (size_t) c->seam_cap * sizeof (CSeam));
    }
    CSeam *s = &c->seam[c->nseam++];
    s->i = i;
    s->j = j;
    s->k = k;
    s->w = w;
    s->gap = gap;
    c->stitched[i] = c->stitched[j] = c->stitched[k] = 1;
}

void at_cloth_clear_seams (AtCloth *c) {
    c->nseam = 0;
    if (c->n > 0) memset (c->stitched, 0, (size_t) c->n);
}

static int edge_cmp (const void *pa, const void *pb) {
    const CEdge *a = pa, *b = pb;
    if (a->a != b->a) return a->a < b->a ? -1 : 1;
    if (a->b != b->b) return a->b < b->b ? -1 : 1;
    return 0;
}

static float cot2 (float ax, float ay, float bx, float by) {
    float cr = fabsf (ax * by - ay * bx);
    return cr > 1e-9f ? (ax * bx + ay * by) / cr : 0;
}

static void apply_fabric (AtCloth *c) {
    for (int i = 0; i < c->n; i++) c->w0[i] = 0;
    float edge_sum = 0;
    for (int t = 0; t < c->ntri; t++) {
        CTri *tr = &c->tri[t];
        const AtFabric *f = &c->fabric[tr->fabric];
        float m = tr->area * f->density * 1e-9f / 3.0f;
        for (int k = 0; k < 3; k++) {
            int i = tr->v[k];
            c->w0[i] += m;
            c->thick[i] = f->thickness;
            c->fric[i] = f->friction;
            c->damp[i] = f->damping;
        }
        edge_sum += sqrtf (tr->area * 2.3094f);
    }
    c->edge = c->ntri > 0 ? edge_sum / c->ntri : 20;
    for (int i = 0; i < c->n; i++) {
        c->w0[i] = c->w0[i] > 0 ? 1.0f / c->w0[i] : 0;
        c->w[i] = c->pinned[i] ? 0 : c->w0[i];
    }
}

void at_cloth_finalize (AtCloth *c) {
    for (int t = 0; t < c->ntri; t++) {
        CTri *tr = &c->tri[t];
        const float *u0 = c->uv + tr->v[0] * 2, *u1 = c->uv + tr->v[1] * 2, *u2 = c->uv + tr->v[2] * 2;
        float a = u1[0] - u0[0], b = u2[0] - u0[0], cc = u1[1] - u0[1], d = u2[1] - u0[1];
        float det = a * d - b * cc;
        tr->area = fabsf (det) * 0.5f;
        if (fabsf (det) < 1e-12f) det = 1e-12f;
        tr->inv[0] = d / det;
        tr->inv[1] = -b / det;
        tr->inv[2] = -cc / det;
        tr->inv[3] = a / det;
    }
    CEdge *edges = malloc ((size_t) (c->ntri > 0 ? c->ntri : 1) * 3 * sizeof (CEdge));
    int ne = 0;
    for (int t = 0; t < c->ntri; t++) {
        for (int e = 0; e < 3; e++) {
            int a = c->tri[t].v[e], b = c->tri[t].v[(e + 1) % 3];
            edges[ne].a = a < b ? a : b;
            edges[ne].b = a < b ? b : a;
            edges[ne].opp = c->tri[t].v[(e + 2) % 3];
            edges[ne].tri = t;
            ne++;
        }
    }
    qsort (edges, (size_t) ne, sizeof (CEdge), edge_cmp);
    free (c->bend);
    c->bend = malloc ((size_t) (ne > 0 ? ne : 1) * sizeof (CBend));
    c->nbend = 0;
    for (int i = 0; i + 1 < ne; i++) {
        if (edges[i].a != edges[i + 1].a || edges[i].b != edges[i + 1].b) continue;
        CBend *bd = &c->bend[c->nbend];
        int i0 = edges[i].a, i1 = edges[i].b, i2 = edges[i].opp, i3 = edges[i + 1].opp;
        const float *x0 = c->uv + i0 * 2, *x1 = c->uv + i1 * 2, *x2 = c->uv + i2 * 2, *x3 = c->uv + i3 * 2;
        float e0x = x1[0] - x0[0], e0y = x1[1] - x0[1];
        float e1x = x2[0] - x0[0], e1y = x2[1] - x0[1];
        float e2x = x3[0] - x0[0], e2y = x3[1] - x0[1];
        float e3x = x2[0] - x1[0], e3y = x2[1] - x1[1];
        float e4x = x3[0] - x1[0], e4y = x3[1] - x1[1];
        float c01 = cot2 (e0x, e0y, e1x, e1y), c02 = cot2 (e0x, e0y, e2x, e2y);
        float c03 = cot2 (-e0x, -e0y, e3x, e3y), c04 = cot2 (-e0x, -e0y, e4x, e4y);
        float area = 0.5f * (fabsf (e0x * e1y - e0y * e1x) + fabsf (e0x * e2y - e0y * e2x));
        if (area < 1e-9f) continue;
        bd->v[0] = i0;
        bd->v[1] = i1;
        bd->v[2] = i2;
        bd->v[3] = i3;
        bd->k[0] = c03 + c04;
        bd->k[1] = c01 + c02;
        bd->k[2] = -c01 - c03;
        bd->k[3] = -c02 - c04;
        bd->scale = 3.0f / area;
        float l = sqrtf (e0x * e0x + e0y * e0y);
        float px = l > 1e-9f ? -e0y / l : 0, py = l > 1e-9f ? e0x / l : 1;
        const AtFabric *f = &c->fabric[c->tri[edges[i].tri].fabric];
        bd->rigidity = f->bend_u * px * px + f->bend_v * py * py;
        c->nbend++;
        i++;
    }
    free (c->nb_start);
    free (c->nb);
    free (c->vs);
    c->nb_start = calloc ((size_t) c->n + 1, sizeof (int));
    int unique = 0;
    for (int i = 0; i < ne; i++) {
        if (i > 0 && edges[i].a == edges[i - 1].a && edges[i].b == edges[i - 1].b) continue;
        c->nb_start[edges[i].a + 1]++;
        c->nb_start[edges[i].b + 1]++;
        unique++;
    }
    for (int i = 0; i < c->n; i++) c->nb_start[i + 1] += c->nb_start[i];
    c->nb = malloc ((size_t) (unique > 0 ? unique : 1) * 2 * sizeof (int));
    int *fill = malloc ((size_t) (c->n > 0 ? c->n : 1) * sizeof (int));
    memcpy (fill, c->nb_start, (size_t) c->n * sizeof (int));
    for (int i = 0; i < ne; i++) {
        if (i > 0 && edges[i].a == edges[i - 1].a && edges[i].b == edges[i - 1].b) continue;
        c->nb[fill[edges[i].a]++] = edges[i].b;
        c->nb[fill[edges[i].b]++] = edges[i].a;
    }
    free (fill);
    c->vs = malloc ((size_t) (c->n > 0 ? c->n : 1) * 3 * sizeof (float));
    free (edges);
    apply_fabric (c);
    free (c->tn);
    c->tn = malloc ((size_t) (c->ntri > 0 ? c->ntri : 1) * 4 * sizeof (float));
}

void at_cloth_set_fabric (AtCloth *c, int fabric, const AtFabric *f) {
    if (fabric < 0 || fabric >= c->nfabric) return;
    c->fabric[fabric] = *f;
    at_cloth_finalize (c);
}

void at_cloth_set_collider (AtCloth *c, const AtSdf *sdf, float offset) {
    c->sdf = sdf;
    c->offset = offset;
}

void at_cloth_separate (AtCloth *c, float extra) {
    if (!c->sdf) return;
    for (int pass = 0; pass < 24; pass++) {
        int moved = 0;
        for (int i = 0; i < c->n; i++) {
            float *q = c->x + i * 3, n[3];
            float limit = c->offset + c->thick[i] * 0.5f + extra;
            float d = at_sdf_sample (c->sdf, q[0], q[1], q[2], n);
            if (d >= limit) continue;
            float push = limit - d;
            if (push > 8) push = 8;
            q[0] += n[0] * push;
            q[1] += n[1] * push;
            q[2] += n[2] * push;
            moved++;
        }
        if (!moved) break;
    }
    memcpy (c->p, c->x, (size_t) c->n * 3 * sizeof (float));
    memset (c->v, 0, (size_t) c->n * 3 * sizeof (float));
}

void at_cloth_set_drag (AtCloth *c, float keep) {
    c->drag = keep;
}

void at_cloth_set_gravity (AtCloth *c, float g) {
    c->gravity = g;
}

void at_cloth_pin (AtCloth *c, int i, int pinned) {
    if (i < 0 || i >= c->n) return;
    c->pinned[i] = pinned ? 1 : 0;
    c->w[i] = pinned ? 0 : c->w0[i];
    if (pinned) c->v[i * 3] = c->v[i * 3 + 1] = c->v[i * 3 + 2] = 0;
}

void at_cloth_grab (AtCloth *c, int i, float x, float y, float z, float radius) {
    at_cloth_release (c);
    if (i < 0 || i >= c->n) return;
    int count = 0;
    for (int j = 0; j < c->n; j++) {
        if (c->piece[j] != c->piece[i]) continue;
        float du = c->uv[j * 2] - c->uv[i * 2], dv = c->uv[j * 2 + 1] - c->uv[i * 2 + 1];
        if (du * du + dv * dv <= radius * radius) count++;
    }
    c->grab_i = malloc ((size_t) count * sizeof (int));
    c->grab_off = malloc ((size_t) count * 3 * sizeof (float));
    c->grab_wt = malloc ((size_t) count * sizeof (float));
    for (int j = 0; j < c->n; j++) {
        if (c->piece[j] != c->piece[i]) continue;
        float du = c->uv[j * 2] - c->uv[i * 2], dv = c->uv[j * 2 + 1] - c->uv[i * 2 + 1];
        float d2 = du * du + dv * dv;
        if (d2 > radius * radius) continue;
        int g = c->ngrab++;
        c->grab_i[g] = j;
        for (int k = 0; k < 3; k++) c->grab_off[g * 3 + k] = c->x[j * 3 + k] - c->x[i * 3 + k];
        float t = 1 - sqrtf (d2) / (radius > 1e-6f ? radius : 1);
        c->grab_wt[g] = j == i ? 1 : t * t * 0.6f;
    }
    c->grab_at[0] = x;
    c->grab_at[1] = y;
    c->grab_at[2] = z;
}

void at_cloth_grab_move (AtCloth *c, float x, float y, float z) {
    c->grab_at[0] = x;
    c->grab_at[1] = y;
    c->grab_at[2] = z;
}

void at_cloth_release (AtCloth *c) {
    free (c->grab_i);
    free (c->grab_off);
    free (c->grab_wt);
    c->grab_i = NULL;
    c->grab_off = NULL;
    c->grab_wt = NULL;
    c->ngrab = 0;
}

static void solve_seams (AtCloth *c, float pull) {
    float *x = c->x;
    for (int s = 0; s < c->nseam; s++) {
        const CSeam *sm = &c->seam[s];
        int i = sm->i * 3, j = sm->j * 3, k = sm->k * 3;
        float wj = 1 - sm->w, wk = sm->w;
        float dx = x[i] - (x[j] * wj + x[k] * wk);
        float dy = x[i + 1] - (x[j + 1] * wj + x[k + 1] * wk);
        float dz = x[i + 2] - (x[j + 2] * wj + x[k + 2] * wk);
        float len = sqrtf (dx * dx + dy * dy + dz * dz);
        float cst = len - sm->gap;
        if (len < 1e-9f || cst <= 0) continue;
        if (cst > pull) cst = pull;
        float wi = c->w[sm->i], wjj = c->w[sm->j] * wj * wj, wkk = c->w[sm->k] * wk * wk;
        float sum = wi + wjj + wkk;
        if (sum < 1e-20f) continue;
        float l = -cst / (sum * len);
        x[i] += dx * l * wi;
        x[i + 1] += dy * l * wi;
        x[i + 2] += dz * l * wi;
        float lj = -l * c->w[sm->j] * wj, lk = -l * c->w[sm->k] * wk;
        x[j] += dx * lj;
        x[j + 1] += dy * lj;
        x[j + 2] += dz * lj;
        x[k] += dx * lk;
        x[k + 1] += dy * lk;
        x[k + 2] += dz * lk;
    }
}

static void solve_triangles (AtCloth *c, float inv_h2) {
    float *x = c->x;
    const float *w = c->w;
    for (int t = 0; t < c->ntri; t++) {
        const CTri *tr = &c->tri[t];
        const AtFabric *f = &c->fabric[tr->fabric];
        int i0 = tr->v[0] * 3, i1 = tr->v[1] * 3, i2 = tr->v[2] * 3;
        float w0 = w[tr->v[0]], w1 = w[tr->v[1]], w2 = w[tr->v[2]];
        float a = tr->inv[0], b = tr->inv[1], cc = tr->inv[2], d = tr->inv[3];
        float area = tr->area > 1e-6f ? tr->area : 1e-6f;
        for (int pass = 0; pass < 3; pass++) {
            float e1x = x[i1] - x[i0], e1y = x[i1 + 1] - x[i0 + 1], e1z = x[i1 + 2] - x[i0 + 2];
            float e2x = x[i2] - x[i0], e2y = x[i2 + 1] - x[i0 + 1], e2z = x[i2 + 2] - x[i0 + 2];
            float fux = e1x * a + e2x * cc, fuy = e1y * a + e2y * cc, fuz = e1z * a + e2z * cc;
            float fvx = e1x * b + e2x * d, fvy = e1y * b + e2y * d, fvz = e1z * b + e2z * d;
            float g1x, g1y, g1z, g2x, g2y, g2z, cst, alpha;
            if (pass < 2) {
                float qx = pass == 0 ? fux : fvx, qy = pass == 0 ? fuy : fvy, qz = pass == 0 ? fuz : fvz;
                float ka = pass == 0 ? a : b, kc = pass == 0 ? cc : d;
                float len = sqrtf (qx * qx + qy * qy + qz * qz);
                if (len < 1e-9f) continue;
                cst = len - (pass == 0 ? f->shrink_u : f->shrink_v);
                float stiff = pass == 0 ? f->stretch_u : f->stretch_v;
                alpha = 1.0f / (stiff * area) * (cst < 0 ? 6.0f : 1.0f);
                qx /= len;
                qy /= len;
                qz /= len;
                g1x = qx * ka;
                g1y = qy * ka;
                g1z = qz * ka;
                g2x = qx * kc;
                g2y = qy * kc;
                g2z = qz * kc;
            } else {
                cst = fux * fvx + fuy * fvy + fuz * fvz;
                alpha = 1.0f / (f->shear * area);
                g1x = fvx * a + fux * b;
                g1y = fvy * a + fuy * b;
                g1z = fvz * a + fuz * b;
                g2x = fvx * cc + fux * d;
                g2y = fvy * cc + fuy * d;
                g2z = fvz * cc + fuz * d;
            }
            float g0x = -(g1x + g2x), g0y = -(g1y + g2y), g0z = -(g1z + g2z);
            float sum = w0 * (g0x * g0x + g0y * g0y + g0z * g0z) + w1 * (g1x * g1x + g1y * g1y + g1z * g1z) + w2 * (g2x * g2x + g2y * g2y + g2z * g2z);
            float den = sum + alpha * inv_h2;
            if (den < 1e-20f) continue;
            float l = -cst / den;
            x[i0] += g0x * l * w0;
            x[i0 + 1] += g0y * l * w0;
            x[i0 + 2] += g0z * l * w0;
            x[i1] += g1x * l * w1;
            x[i1 + 1] += g1y * l * w1;
            x[i1 + 2] += g1z * l * w1;
            x[i2] += g2x * l * w2;
            x[i2 + 1] += g2y * l * w2;
            x[i2 + 2] += g2z * l * w2;
        }
    }
}

static void solve_bends (AtCloth *c, float inv_h2) {
    float *x = c->x;
    const float *w = c->w;
    for (int b = 0; b < c->nbend; b++) {
        const CBend *bd = &c->bend[b];
        float cx = 0, cy = 0, cz = 0, sum = 0;
        for (int k = 0; k < 4; k++) {
            int i = bd->v[k] * 3;
            cx += bd->k[k] * x[i];
            cy += bd->k[k] * x[i + 1];
            cz += bd->k[k] * x[i + 2];
            sum += w[bd->v[k]] * bd->k[k] * bd->k[k];
        }
        float den = sum * bd->scale + inv_h2 / (bd->rigidity > 1e-9f ? bd->rigidity : 1e-9f);
        if (den < 1e-20f) continue;
        float l = -bd->scale / den;
        for (int k = 0; k < 4; k++) {
            int i = bd->v[k] * 3;
            float s = l * w[bd->v[k]] * bd->k[k];
            x[i] += cx * s;
            x[i + 1] += cy * s;
            x[i + 2] += cz * s;
        }
    }
}

static void collide_body (AtCloth *c) {
    float *x = c->x;
    const float *p = c->p;
    for (int i = 0; i < c->n; i++) {
        if (c->w[i] == 0) continue;
        float *q = x + i * 3;
        float limit = c->offset + c->thick[i] * 0.5f;
        float push = 0, n[3] = { 0, 1, 0 };
        if (c->sdf) {
            float d = at_sdf_sample (c->sdf, q[0], q[1], q[2], n);
            if (d < limit) push = limit - d;
        }
        float floor = c->thick[i] * 0.5f + 0.5f;
        if (q[1] < floor && floor - q[1] > push) {
            push = floor - q[1];
            n[0] = 0;
            n[1] = 1;
            n[2] = 0;
        }
        if (push <= 0) continue;
        q[0] += n[0] * push;
        q[1] += n[1] * push;
        q[2] += n[2] * push;
        float dx = q[0] - p[i * 3], dy = q[1] - p[i * 3 + 1], dz = q[2] - p[i * 3 + 2];
        float dn = dx * n[0] + dy * n[1] + dz * n[2];
        float tx = dx - n[0] * dn, ty = dy - n[1] * dn, tz = dz - n[2] * dn;
        float tl = sqrtf (tx * tx + ty * ty + tz * tz);
        if (tl < 1e-9f) continue;
        float k = c->fric[i] * push / tl;
        if (k > 1) k = 1;
        q[0] -= tx * k;
        q[1] -= ty * k;
        q[2] -= tz * k;
    }
}

static unsigned int cell_hash (int x, int y, int z, int n) {
    unsigned int h = (unsigned int) x * 73856093u ^ (unsigned int) y * 19349663u ^ (unsigned int) z * 83492791u;
    return h % (unsigned int) n;
}

static void build_hash (AtCloth *c) {
    c->cell = c->edge * 2.0f;
    if (c->cell < 4) c->cell = 4;
    int ncell = c->ntri * 2 + 17;
    if (ncell != c->ncell) {
        c->ncell = ncell;
        c->cell_start = realloc (c->cell_start, (size_t) (ncell + 1) * sizeof (int));
        c->cell_tri = realloc (c->cell_tri, (size_t) (c->ntri > 0 ? c->ntri : 1) * sizeof (int));
    }
    memset (c->cell_start, 0, (size_t) (ncell + 1) * sizeof (int));
    float inv = 1.0f / c->cell;
    int *key = malloc ((size_t) (c->ntri > 0 ? c->ntri : 1) * sizeof (int));
    for (int t = 0; t < c->ntri; t++) {
        const CTri *tr = &c->tri[t];
        float mx = (c->x[tr->v[0] * 3] + c->x[tr->v[1] * 3] + c->x[tr->v[2] * 3]) / 3;
        float my = (c->x[tr->v[0] * 3 + 1] + c->x[tr->v[1] * 3 + 1] + c->x[tr->v[2] * 3 + 1]) / 3;
        float mz = (c->x[tr->v[0] * 3 + 2] + c->x[tr->v[1] * 3 + 2] + c->x[tr->v[2] * 3 + 2]) / 3;
        key[t] = (int) cell_hash ((int) floorf (mx * inv), (int) floorf (my * inv), (int) floorf (mz * inv), ncell);
        c->cell_start[key[t] + 1]++;
    }
    for (int i = 0; i < ncell; i++) c->cell_start[i + 1] += c->cell_start[i];
    int *fill = malloc ((size_t) ncell * sizeof (int));
    memcpy (fill, c->cell_start, (size_t) ncell * sizeof (int));
    for (int t = 0; t < c->ntri; t++) c->cell_tri[fill[key[t]]++] = t;
    free (fill);
    free (key);
}

static float tri_closest (const float *p, const float *a, const float *b, const float *cc, float *bary) {
    float ab[3] = { b[0] - a[0], b[1] - a[1], b[2] - a[2] };
    float ac[3] = { cc[0] - a[0], cc[1] - a[1], cc[2] - a[2] };
    float ap[3] = { p[0] - a[0], p[1] - a[1], p[2] - a[2] };
    float d00 = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
    float d01 = ab[0] * ac[0] + ab[1] * ac[1] + ab[2] * ac[2];
    float d11 = ac[0] * ac[0] + ac[1] * ac[1] + ac[2] * ac[2];
    float d20 = ap[0] * ab[0] + ap[1] * ab[1] + ap[2] * ab[2];
    float d21 = ap[0] * ac[0] + ap[1] * ac[1] + ap[2] * ac[2];
    float den = d00 * d11 - d01 * d01;
    if (fabsf (den) < 1e-12f) return 1e30f;
    float v = (d11 * d20 - d01 * d21) / den;
    float w = (d00 * d21 - d01 * d20) / den;
    if (v < -0.02f || w < -0.02f || v + w > 1.02f) return 1e30f;
    bary[0] = 1 - v - w;
    bary[1] = v;
    bary[2] = w;
    float qx = a[0] + ab[0] * v + ac[0] * w - p[0];
    float qy = a[1] + ab[1] * v + ac[1] * w - p[1];
    float qz = a[2] + ab[2] * v + ac[2] * w - p[2];
    return sqrtf (qx * qx + qy * qy + qz * qz);
}

static void collide_self (AtCloth *c) {
    if (!c->cell_start || c->ntri == 0) return;
    float *x = c->x;
    const float *p = c->p;
    float inv = 1.0f / c->cell;
    float near_uv = c->edge * 2.2f;
    for (int t = 0; t < c->ntri; t++) {
        const CTri *tr = &c->tri[t];
        const float *a = p + tr->v[0] * 3, *b = p + tr->v[1] * 3, *d = p + tr->v[2] * 3;
        float *n = c->tn + t * 4;
        n[0] = (b[1] - a[1]) * (d[2] - a[2]) - (b[2] - a[2]) * (d[1] - a[1]);
        n[1] = (b[2] - a[2]) * (d[0] - a[0]) - (b[0] - a[0]) * (d[2] - a[2]);
        n[2] = (b[0] - a[0]) * (d[1] - a[1]) - (b[1] - a[1]) * (d[0] - a[0]);
        float l = sqrtf (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
        if (l > 1e-12f) {
            n[0] /= l;
            n[1] /= l;
            n[2] /= l;
        }
    }
    for (int i = 0; i < c->n; i++) {
        float wi = c->w[i];
        float *q = x + i * 3;
        float reach = c->thick[i] + 1.5f;
        float gx = q[0] * inv, gy = q[1] * inv, gz = q[2] * inv;
        int cx = (int) floorf (gx), cy = (int) floorf (gy), cz = (int) floorf (gz);
        int sx = gx - cx < 0.5f ? -1 : 0, sy = gy - cy < 0.5f ? -1 : 0, sz = gz - cz < 0.5f ? -1 : 0;
        float far2 = (c->cell * 0.5f + reach) * (c->cell * 0.5f + reach);
        for (int oz = sz; oz <= sz + 1; oz++)
            for (int oy = sy; oy <= sy + 1; oy++)
                for (int ox = sx; ox <= sx + 1; ox++) {
                    unsigned int h = cell_hash (cx + ox, cy + oy, cz + oz, c->ncell);
                    for (int s = c->cell_start[h]; s < c->cell_start[h + 1]; s++) {
                        int t = c->cell_tri[s];
                        const CTri *tr = &c->tri[t];
                        int v0 = tr->v[0], v1 = tr->v[1], v2 = tr->v[2];
                        if (v0 == i || v1 == i || v2 == i) continue;
                        if (c->stitched[i] && (c->stitched[v0] || c->stitched[v1] || c->stitched[v2])) continue;
                        {
                            float mx = (x[v0 * 3] + x[v1 * 3] + x[v2 * 3]) * 0.33333334f - q[0];
                            float my = (x[v0 * 3 + 1] + x[v1 * 3 + 1] + x[v2 * 3 + 1]) * 0.33333334f - q[1];
                            float mz = (x[v0 * 3 + 2] + x[v1 * 3 + 2] + x[v2 * 3 + 2]) * 0.33333334f - q[2];
                            if (mx * mx + my * my + mz * mz > far2) continue;
                        }
                        if (c->piece[v0] == c->piece[i]) {
                            float mu = (c->uv[v0 * 2] + c->uv[v1 * 2] + c->uv[v2 * 2]) / 3 - c->uv[i * 2];
                            float mv = (c->uv[v0 * 2 + 1] + c->uv[v1 * 2 + 1] + c->uv[v2 * 2 + 1]) / 3 - c->uv[i * 2 + 1];
                            if (mu * mu + mv * mv < near_uv * near_uv) continue;
                        }
                        float bary[3];
                        float dist = tri_closest (q, x + v0 * 3, x + v1 * 3, x + v2 * 3, bary);
                        if (dist >= reach) continue;
                        const float *n = c->tn + t * 4;
                        const float *pa = p + v0 * 3;
                        float side = (p[i * 3] - pa[0]) * n[0] + (p[i * 3 + 1] - pa[1]) * n[1] + (p[i * 3 + 2] - pa[2]) * n[2];
                        float sg = side >= 0 ? 1.0f : -1.0f;
                        const float *ca = x + v0 * 3;
                        float cur = ((q[0] - ca[0]) * n[0] + (q[1] - ca[1]) * n[1] + (q[2] - ca[2]) * n[2]) * sg;
                        float need = reach - cur;
                        if (need <= 0) continue;
                        if (need > reach * 2) need = reach * 2;
                        float w0 = c->w[v0], w1 = c->w[v1], w2 = c->w[v2];
                        float sum = wi + w0 * bary[0] * bary[0] + w1 * bary[1] * bary[1] + w2 * bary[2] * bary[2];
                        if (sum < 1e-20f) continue;
                        float l = need / sum * 0.5f;
                        q[0] += n[0] * sg * l * wi;
                        q[1] += n[1] * sg * l * wi;
                        q[2] += n[2] * sg * l * wi;
                        int vs[3] = { v0, v1, v2 };
                        float ws[3] = { w0, w1, w2 };
                        for (int k = 0; k < 3; k++) {
                            float m = -sg * l * ws[k] * bary[k];
                            x[vs[k] * 3] += n[0] * m;
                            x[vs[k] * 3 + 1] += n[1] * m;
                            x[vs[k] * 3 + 2] += n[2] * m;
                        }
                    }
                }
    }
}

static void smooth_velocity (AtCloth *c, float k) {
    if (!c->nb_start) return;
    const float *v = c->v;
    float *o = c->vs;
    for (int i = 0; i < c->n; i++) {
        int a = c->nb_start[i], b = c->nb_start[i + 1];
        if (c->w[i] == 0 || b == a) {
            o[i * 3] = v[i * 3];
            o[i * 3 + 1] = v[i * 3 + 1];
            o[i * 3 + 2] = v[i * 3 + 2];
            continue;
        }
        float sx = 0, sy = 0, sz = 0;
        for (int j = a; j < b; j++) {
            int n = c->nb[j] * 3;
            sx += v[n];
            sy += v[n + 1];
            sz += v[n + 2];
        }
        float inv = 1.0f / (b - a);
        o[i * 3] = v[i * 3] + (sx * inv - v[i * 3]) * k;
        o[i * 3 + 1] = v[i * 3 + 1] + (sy * inv - v[i * 3 + 1]) * k;
        o[i * 3 + 2] = v[i * 3 + 2] + (sz * inv - v[i * 3 + 2]) * k;
    }
    memcpy (c->v, o, (size_t) c->n * 3 * sizeof (float));
}

void at_cloth_step (AtCloth *c, float dt, int substeps) {
    if (c->n == 0 || substeps < 1) return;
    float h = dt / substeps;
    float inv_h2 = 1.0f / (h * h);
    float max_move = 5.0f;
    build_hash (c);
    for (int s = 0; s < substeps; s++) {
        float *x = c->x, *p = c->p, *v = c->v;
        for (int i = 0; i < c->n; i++) {
            if (c->w[i] == 0) {
                p[i * 3] = x[i * 3];
                p[i * 3 + 1] = x[i * 3 + 1];
                p[i * 3 + 2] = x[i * 3 + 2];
                continue;
            }
            float keep = (1.0f - c->damp[i] * h * 60.0f) * c->drag;
            if (keep < 0) keep = 0;
            v[i * 3] *= keep;
            v[i * 3 + 1] = (v[i * 3 + 1] - c->gravity * h) * keep;
            v[i * 3 + 2] *= keep;
            for (int k = 0; k < 3; k++) {
                p[i * 3 + k] = x[i * 3 + k];
                x[i * 3 + k] += v[i * 3 + k] * h;
            }
        }
        for (int g = 0; g < c->ngrab; g++) {
            int i = c->grab_i[g];
            if (c->w[i] == 0) continue;
            float wt = c->grab_wt[g];
            for (int k = 0; k < 3; k++) {
                float target = c->grab_at[k] + c->grab_off[g * 3 + k];
                x[i * 3 + k] += (target - x[i * 3 + k]) * wt * 0.35f;
            }
        }
        solve_seams (c, 1.6f);
        solve_triangles (c, inv_h2);
        solve_bends (c, inv_h2);
        solve_seams (c, 0.35f);
        if (s % 3 == 0) collide_self (c);
        collide_body (c);
        for (int i = 0; i < c->n; i++) {
            if (c->w[i] == 0) continue;
            float dx = x[i * 3] - p[i * 3], dy = x[i * 3 + 1] - p[i * 3 + 1], dz = x[i * 3 + 2] - p[i * 3 + 2];
            float l = sqrtf (dx * dx + dy * dy + dz * dz);
            if (l > max_move) {
                float k = max_move / l;
                dx *= k;
                dy *= k;
                dz *= k;
                x[i * 3] = p[i * 3] + dx;
                x[i * 3 + 1] = p[i * 3 + 1] + dy;
                x[i * 3 + 2] = p[i * 3 + 2] + dz;
            }
            v[i * 3] = dx / h;
            v[i * 3 + 1] = dy / h;
            v[i * 3 + 2] = dz / h;
        }
        if ((s & 3) == 3) smooth_velocity (c, 0.12f);
    }
}

int at_cloth_count (const AtCloth *c) {
    return c->n;
}

int at_cloth_triangle_count (const AtCloth *c) {
    return c->ntri;
}

const float *at_cloth_positions (const AtCloth *c) {
    return c->x;
}

void at_cloth_set_position (AtCloth *c, int i, float x, float y, float z) {
    if (i < 0 || i >= c->n) return;
    c->x[i * 3] = c->p[i * 3] = x;
    c->x[i * 3 + 1] = c->p[i * 3 + 1] = y;
    c->x[i * 3 + 2] = c->p[i * 3 + 2] = z;
    c->v[i * 3] = c->v[i * 3 + 1] = c->v[i * 3 + 2] = 0;
}

void at_cloth_strain (const AtCloth *c, float *out) {
    float *cnt = calloc ((size_t) (c->n > 0 ? c->n : 1), sizeof (float));
    memset (out, 0, (size_t) c->n * sizeof (float));
    const float *x = c->x;
    for (int t = 0; t < c->ntri; t++) {
        const CTri *tr = &c->tri[t];
        int i0 = tr->v[0] * 3, i1 = tr->v[1] * 3, i2 = tr->v[2] * 3;
        float e1x = x[i1] - x[i0], e1y = x[i1 + 1] - x[i0 + 1], e1z = x[i1 + 2] - x[i0 + 2];
        float e2x = x[i2] - x[i0], e2y = x[i2 + 1] - x[i0 + 1], e2z = x[i2 + 2] - x[i0 + 2];
        float a = tr->inv[0], b = tr->inv[1], cc = tr->inv[2], d = tr->inv[3];
        float fux = e1x * a + e2x * cc, fuy = e1y * a + e2y * cc, fuz = e1z * a + e2z * cc;
        float fvx = e1x * b + e2x * d, fvy = e1y * b + e2y * d, fvz = e1z * b + e2z * d;
        float su = sqrtf (fux * fux + fuy * fuy + fuz * fuz) - 1, sv = sqrtf (fvx * fvx + fvy * fvy + fvz * fvz) - 1;
        float s = su > sv ? su : sv;
        for (int k = 0; k < 3; k++) {
            out[tr->v[k]] += s;
            cnt[tr->v[k]] += 1;
        }
    }
    for (int i = 0; i < c->n; i++) if (cnt[i] > 0) out[i] /= cnt[i];
    free (cnt);
}

void at_cloth_distance (const AtCloth *c, float *out) {
    for (int i = 0; i < c->n; i++) {
        out[i] = c->sdf ? at_sdf_sample (c->sdf, c->x[i * 3], c->x[i * 3 + 1], c->x[i * 3 + 2], NULL) : 1e3f;
    }
}

float at_cloth_seam_gap (const AtCloth *c) {
    float worst = 0;
    const float *x = c->x;
    for (int s = 0; s < c->nseam; s++) {
        const CSeam *sm = &c->seam[s];
        int i = sm->i * 3, j = sm->j * 3, k = sm->k * 3;
        float wj = 1 - sm->w, wk = sm->w;
        float dx = x[i] - (x[j] * wj + x[k] * wk), dy = x[i + 1] - (x[j + 1] * wj + x[k + 1] * wk), dz = x[i + 2] - (x[j + 2] * wj + x[k + 2] * wk);
        float d = sqrtf (dx * dx + dy * dy + dz * dz) - sm->gap;
        if (d > worst) worst = d;
    }
    return worst;
}

float at_cloth_kinetic (const AtCloth *c) {
    double sum = 0;
    for (int i = 0; i < c->n; i++) sum += c->v[i * 3] * c->v[i * 3] + c->v[i * 3 + 1] * c->v[i * 3 + 1] + c->v[i * 3 + 2] * c->v[i * 3 + 2];
    return c->n > 0 ? (float) sqrt (sum / c->n) : 0;
}
