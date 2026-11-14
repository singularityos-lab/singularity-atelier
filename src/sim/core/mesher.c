#include "core.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    int v[3];
    int adj[3];
    int alive;
} Tri;

typedef struct {
    double *p;
    int np;
    Tri *t;
    int nt;
    int cap;
    int *free_list;
    int nfree;
    int last;
} Dt;

void at_free (void *p) {
    free (p);
}

static double orient (const double *p, int a, int b, int c) {
    return (p[b * 2] - p[a * 2]) * (p[c * 2 + 1] - p[a * 2 + 1]) - (p[b * 2 + 1] - p[a * 2 + 1]) * (p[c * 2] - p[a * 2]);
}

static int in_circle (const double *p, const Tri *t, int q) {
    double ax = p[t->v[0] * 2] - p[q * 2], ay = p[t->v[0] * 2 + 1] - p[q * 2 + 1];
    double bx = p[t->v[1] * 2] - p[q * 2], by = p[t->v[1] * 2 + 1] - p[q * 2 + 1];
    double cx = p[t->v[2] * 2] - p[q * 2], cy = p[t->v[2] * 2 + 1] - p[q * 2 + 1];
    double det = (ax * ax + ay * ay) * (bx * cy - cx * by) - (bx * bx + by * by) * (ax * cy - cx * ay) + (cx * cx + cy * cy) * (ax * by - bx * ay);
    return det > 0;
}

static int tri_new (Dt *d, int a, int b, int c) {
    int id;
    if (d->nfree > 0) id = d->free_list[--d->nfree];
    else {
        if (d->nt == d->cap) {
            d->cap *= 2;
            d->t = realloc (d->t, (size_t) d->cap * sizeof (Tri));
            d->free_list = realloc (d->free_list, (size_t) d->cap * sizeof (int));
        }
        id = d->nt++;
    }
    Tri *t = &d->t[id];
    t->v[0] = a;
    t->v[1] = b;
    t->v[2] = c;
    t->adj[0] = t->adj[1] = t->adj[2] = -1;
    t->alive = 1;
    return id;
}

static int locate (Dt *d, int q) {
    int cur = d->last;
    if (cur < 0 || cur >= d->nt || !d->t[cur].alive) {
        for (cur = 0; cur < d->nt; cur++) if (d->t[cur].alive) break;
    }
    for (int guard = 0; guard < d->nt * 2 + 16; guard++) {
        Tri *t = &d->t[cur];
        int moved = 0;
        for (int e = 0; e < 3; e++) {
            if (orient (d->p, t->v[e], t->v[(e + 1) % 3], q) < 0 && t->adj[e] >= 0) {
                cur = t->adj[e];
                moved = 1;
                break;
            }
        }
        if (!moved) return cur;
    }
    for (int i = 0; i < d->nt; i++) if (d->t[i].alive && in_circle (d->p, &d->t[i], q)) return i;
    return cur;
}

static void insert (Dt *d, int q, int *stack, int *cavity, int *ea, int *eb, int *en, int *fresh) {
    int start = locate (d, q);
    if (!in_circle (d->p, &d->t[start], q)) {
        int found = -1;
        for (int e = 0; e < 3 && found < 0; e++) {
            int n = d->t[start].adj[e];
            if (n >= 0 && in_circle (d->p, &d->t[n], q)) found = n;
        }
        if (found < 0) return;
        start = found;
    }
    int ns = 0, nc = 0, ne = 0;
    stack[ns++] = start;
    d->t[start].alive = 2;
    while (ns > 0) {
        int ti = stack[--ns];
        cavity[nc++] = ti;
        for (int e = 0; e < 3; e++) {
            int n = d->t[ti].adj[e];
            if (n >= 0 && d->t[n].alive == 2) continue;
            if (n >= 0 && d->t[n].alive == 1 && in_circle (d->p, &d->t[n], q)) {
                d->t[n].alive = 2;
                stack[ns++] = n;
                continue;
            }
            ea[ne] = d->t[ti].v[e];
            eb[ne] = d->t[ti].v[(e + 1) % 3];
            en[ne] = n;
            ne++;
        }
    }
    for (int i = 0; i < nc; i++) {
        d->t[cavity[i]].alive = 0;
        d->free_list[d->nfree++] = cavity[i];
    }
    for (int i = 0; i < ne; i++) {
        int id = tri_new (d, ea[i], eb[i], q);
        fresh[i] = id;
        d->t[id].adj[0] = en[i];
        if (en[i] >= 0) {
            Tri *o = &d->t[en[i]];
            for (int e = 0; e < 3; e++) if (o->v[e] == eb[i] && o->v[(e + 1) % 3] == ea[i]) o->adj[e] = id;
        }
    }
    for (int i = 0; i < ne; i++) {
        for (int j = 0; j < ne; j++) {
            if (ea[j] == eb[i]) d->t[fresh[i]].adj[1] = fresh[j];
            if (eb[j] == ea[i]) d->t[fresh[i]].adj[2] = fresh[j];
        }
    }
    d->last = fresh[0];
}

static int inside (const double *b, const int *loops, int nloops, int nb, double x, double y) {
    int in = 0;
    for (int l = 0; l < nloops; l++) {
        int s = loops[l], e = l + 1 < nloops ? loops[l + 1] : nb;
        for (int i = s, j = e - 1; i < e; j = i++) {
            double yi = b[i * 2 + 1], yj = b[j * 2 + 1];
            if ((yi > y) != (yj > y) && x < (b[j * 2] - b[i * 2]) * (y - yi) / (yj - yi) + b[i * 2]) in = !in;
        }
    }
    return in;
}

static double boundary_dist2 (const double *b, const int *loops, int nloops, int nb, double x, double y) {
    double best = 1e300;
    for (int l = 0; l < nloops; l++) {
        int s = loops[l], e = l + 1 < nloops ? loops[l + 1] : nb;
        for (int i = s, j = e - 1; i < e; j = i++) {
            double ax = b[j * 2], ay = b[j * 2 + 1], dx = b[i * 2] - ax, dy = b[i * 2 + 1] - ay;
            double l2 = dx * dx + dy * dy;
            double t = l2 > 0 ? ((x - ax) * dx + (y - ay) * dy) / l2 : 0;
            if (t < 0) t = 0;
            if (t > 1) t = 1;
            double qx = ax + dx * t - x, qy = ay + dy * t - y;
            double d2 = qx * qx + qy * qy;
            if (d2 < best) best = d2;
        }
    }
    return best;
}

int at_triangulate (const double *boundary, int nb, const int *loops, int nloops, double spacing,
                    double **out_points, int *out_npoints, int **out_tris, int *out_ntris) {
    *out_points = NULL;
    *out_tris = NULL;
    *out_npoints = 0;
    *out_ntris = 0;
    if (nb < 3 || spacing <= 0) return 0;
    int one[1] = { 0 };
    if (nloops <= 0 || !loops) {
        loops = one;
        nloops = 1;
    }
    double minx = 1e300, miny = 1e300, maxx = -1e300, maxy = -1e300;
    for (int i = 0; i < nb; i++) {
        double x = boundary[i * 2], y = boundary[i * 2 + 1];
        if (x < minx) minx = x;
        if (y < miny) miny = y;
        if (x > maxx) maxx = x;
        if (y > maxy) maxy = y;
    }
    double row = spacing * 0.8660254;
    int cols = (int) ((maxx - minx) / spacing) + 3, rows = (int) ((maxy - miny) / row) + 3;
    int cap = nb + cols * rows + 3;
    double *p = malloc ((size_t) cap * 2 * sizeof (double));
    memcpy (p, boundary, (size_t) nb * 2 * sizeof (double));
    int np = nb;
    double keep = spacing * 0.62;
    unsigned int seed = 12345;
    for (int r = 0; r < rows; r++) {
        double y = miny + r * row + row * 0.5;
        for (int c = 0; c < cols; c++) {
            double x = minx + c * spacing + ((r & 1) ? spacing * 0.5 : 0) + spacing * 0.25;
            if (!inside (boundary, loops, nloops, nb, x, y)) continue;
            if (boundary_dist2 (boundary, loops, nloops, nb, x, y) < keep * keep) continue;
            seed = seed * 1664525u + 1013904223u;
            double jx = ((seed >> 8) & 0xffff) / 65535.0 - 0.5;
            seed = seed * 1664525u + 1013904223u;
            double jy = ((seed >> 8) & 0xffff) / 65535.0 - 0.5;
            p[np * 2] = x + jx * spacing * 0.02;
            p[np * 2 + 1] = y + jy * spacing * 0.02;
            np++;
        }
    }
    double span = (maxx - minx > maxy - miny ? maxx - minx : maxy - miny) * 20 + 1000;
    double cx = (minx + maxx) / 2, cy = (miny + maxy) / 2;
    p[np * 2] = cx - span;
    p[np * 2 + 1] = cy - span;
    p[(np + 1) * 2] = cx + span;
    p[(np + 1) * 2 + 1] = cy - span;
    p[(np + 2) * 2] = cx;
    p[(np + 2) * 2 + 1] = cy + span;

    Dt d;
    memset (&d, 0, sizeof d);
    d.p = p;
    d.np = np;
    d.cap = np * 2 + 64;
    d.t = malloc ((size_t) d.cap * sizeof (Tri));
    d.free_list = malloc ((size_t) d.cap * sizeof (int));
    tri_new (&d, np, np + 1, np + 2);
    int work = np * 2 + 64;
    int *stack = malloc ((size_t) work * sizeof (int));
    int *cavity = malloc ((size_t) work * sizeof (int));
    int *ea = malloc ((size_t) work * 3 * sizeof (int));
    int *eb = malloc ((size_t) work * 3 * sizeof (int));
    int *en = malloc ((size_t) work * 3 * sizeof (int));
    int *fresh = malloc ((size_t) work * 3 * sizeof (int));
    for (int i = nb; i < np; i++) insert (&d, i, stack, cavity, ea, eb, en, fresh);
    for (int i = 0; i < nb; i++) insert (&d, i, stack, cavity, ea, eb, en, fresh);

    int *tris = malloc ((size_t) (d.nt > 0 ? d.nt : 1) * 3 * sizeof (int));
    int ntri = 0;
    for (int i = 0; i < d.nt; i++) {
        Tri *t = &d.t[i];
        if (!t->alive || t->v[0] >= np || t->v[1] >= np || t->v[2] >= np) continue;
        double mx = (p[t->v[0] * 2] + p[t->v[1] * 2] + p[t->v[2] * 2]) / 3;
        double my = (p[t->v[0] * 2 + 1] + p[t->v[1] * 2 + 1] + p[t->v[2] * 2 + 1]) / 3;
        if (!inside (boundary, loops, nloops, nb, mx, my)) continue;
        if (fabs (orient (p, t->v[0], t->v[1], t->v[2])) < 1e-9) continue;
        tris[ntri * 3] = t->v[0];
        tris[ntri * 3 + 1] = t->v[1];
        tris[ntri * 3 + 2] = t->v[2];
        ntri++;
    }
    free (stack);
    free (cavity);
    free (ea);
    free (eb);
    free (en);
    free (fresh);
    free (d.t);
    free (d.free_list);
    *out_points = p;
    *out_npoints = np;
    *out_tris = tris;
    *out_ntris = ntri;
    return ntri;
}
