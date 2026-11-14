#include "core.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

struct _AtSdf {
    int nx;
    int ny;
    int nz;
    float cell;
    float inv;
    float min[3];
    float band;
    float *d;
};

static float closest_on_triangle (const float *p, const float *a, const float *b, const float *c, float *out) {
    float ab[3] = { b[0] - a[0], b[1] - a[1], b[2] - a[2] };
    float ac[3] = { c[0] - a[0], c[1] - a[1], c[2] - a[2] };
    float ap[3] = { p[0] - a[0], p[1] - a[1], p[2] - a[2] };
    float d1 = ab[0] * ap[0] + ab[1] * ap[1] + ab[2] * ap[2];
    float d2 = ac[0] * ap[0] + ac[1] * ap[1] + ac[2] * ap[2];
    float u = 0, v = 0;
    if (d1 <= 0 && d2 <= 0) goto done;
    {
        float bp[3] = { p[0] - b[0], p[1] - b[1], p[2] - b[2] };
        float d3 = ab[0] * bp[0] + ab[1] * bp[1] + ab[2] * bp[2];
        float d4 = ac[0] * bp[0] + ac[1] * bp[1] + ac[2] * bp[2];
        if (d3 >= 0 && d4 <= d3) {
            u = 1;
            goto done;
        }
        float vc = d1 * d4 - d3 * d2;
        if (vc <= 0 && d1 >= 0 && d3 <= 0) {
            u = d1 / (d1 - d3);
            goto done;
        }
        float cp[3] = { p[0] - c[0], p[1] - c[1], p[2] - c[2] };
        float d5 = ab[0] * cp[0] + ab[1] * cp[1] + ab[2] * cp[2];
        float d6 = ac[0] * cp[0] + ac[1] * cp[1] + ac[2] * cp[2];
        if (d6 >= 0 && d5 <= d6) {
            v = 1;
            goto done;
        }
        float vb = d5 * d2 - d1 * d6;
        if (vb <= 0 && d2 >= 0 && d6 <= 0) {
            v = d2 / (d2 - d6);
            goto done;
        }
        float va = d3 * d6 - d5 * d4;
        if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) {
            float w = (d4 - d3) / ((d4 - d3) + (d5 - d6));
            u = 1 - w;
            v = w;
            goto done;
        }
        float den = 1.0f / (va + vb + vc);
        u = vb * den;
        v = vc * den;
    }
done:
    out[0] = a[0] + ab[0] * u + ac[0] * v;
    out[1] = a[1] + ab[1] * u + ac[1] * v;
    out[2] = a[2] + ab[2] * u + ac[2] * v;
    float dx = p[0] - out[0], dy = p[1] - out[1], dz = p[2] - out[2];
    return sqrtf (dx * dx + dy * dy + dz * dz);
}

AtSdf *at_sdf_build (const float *pos, int nv, const unsigned int *tri, int ntri, float cell, float margin) {
    if (nv <= 0 || ntri < 3) return NULL;
    AtSdf *s = calloc (1, sizeof (AtSdf));
    float lo[3] = { 1e30f, 1e30f, 1e30f }, hi[3] = { -1e30f, -1e30f, -1e30f };
    for (int i = 0; i < nv; i++)
        for (int k = 0; k < 3; k++) {
            float v = pos[i * 3 + k];
            if (v < lo[k]) lo[k] = v;
            if (v > hi[k]) hi[k] = v;
        }
    s->cell = cell;
    s->inv = 1.0f / cell;
    s->band = cell * 3.0f;
    for (int k = 0; k < 3; k++) s->min[k] = lo[k] - margin;
    s->nx = (int) ceilf ((hi[0] - lo[0] + 2 * margin) / cell) + 1;
    s->ny = (int) ceilf ((hi[1] - lo[1] + 2 * margin) / cell) + 1;
    s->nz = (int) ceilf ((hi[2] - lo[2] + 2 * margin) / cell) + 1;
    size_t n = (size_t) s->nx * s->ny * s->nz;
    s->d = malloc (n * sizeof (float));
    float *facing = calloc (n, sizeof (float));
    unsigned char *state = calloc (n, 1);
    for (size_t i = 0; i < n; i++) s->d[i] = 1e30f;
    int reach = 3;
    for (int t = 0; t + 2 < ntri; t += 3) {
        const float *a = pos + tri[t] * 3, *b = pos + tri[t + 1] * 3, *c = pos + tri[t + 2] * 3;
        float nrm[3] = {
            (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]),
            (b[2] - a[2]) * (c[0] - a[0]) - (b[0] - a[0]) * (c[2] - a[2]),
            (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        };
        float nl = sqrtf (nrm[0] * nrm[0] + nrm[1] * nrm[1] + nrm[2] * nrm[2]);
        if (nl < 1e-12f) continue;
        nrm[0] /= nl;
        nrm[1] /= nl;
        nrm[2] /= nl;
        int i0[3], i1[3];
        int dims[3] = { s->nx, s->ny, s->nz };
        for (int k = 0; k < 3; k++) {
            float mn = a[k] < b[k] ? (a[k] < c[k] ? a[k] : c[k]) : (b[k] < c[k] ? b[k] : c[k]);
            float mx = a[k] > b[k] ? (a[k] > c[k] ? a[k] : c[k]) : (b[k] > c[k] ? b[k] : c[k]);
            i0[k] = (int) floorf ((mn - s->min[k]) * s->inv) - reach;
            i1[k] = (int) ceilf ((mx - s->min[k]) * s->inv) + reach;
            if (i0[k] < 0) i0[k] = 0;
            if (i1[k] > dims[k] - 1) i1[k] = dims[k] - 1;
        }
        for (int z = i0[2]; z <= i1[2]; z++)
            for (int y = i0[1]; y <= i1[1]; y++)
                for (int x = i0[0]; x <= i1[0]; x++) {
                    float p[3] = { s->min[0] + x * cell, s->min[1] + y * cell, s->min[2] + z * cell };
                    float q[3];
                    float dist = closest_on_triangle (p, a, b, c, q);
                    if (dist > s->band) continue;
                    size_t idx = ((size_t) z * s->ny + y) * s->nx + x;
                    float cur = fabsf (s->d[idx]);
                    float dot = (p[0] - q[0]) * nrm[0] + (p[1] - q[1]) * nrm[1] + (p[2] - q[2]) * nrm[2];
                    float face = dist > 1e-6f ? fabsf (dot) / dist : 1;
                    if (dist < cur - 1e-3f || (dist < cur + 1e-3f && face > facing[idx])) {
                        s->d[idx] = dot >= 0 ? dist : -dist;
                        facing[idx] = face;
                        state[idx] = 1;
                    }
                }
    }
    size_t *queue = malloc (n * sizeof (size_t));
    size_t head = 0, tail = 0;
    queue[tail++] = 0;
    state[0] |= 2;
    int nx = s->nx, ny = s->ny, nz = s->nz;
    while (head < tail) {
        size_t idx = queue[head++];
        int x = (int) (idx % nx), y = (int) ((idx / nx) % ny), z = (int) (idx / ((size_t) nx * ny));
        int nb[6][3] = { { x - 1, y, z }, { x + 1, y, z }, { x, y - 1, z }, { x, y + 1, z }, { x, y, z - 1 }, { x, y, z + 1 } };
        for (int k = 0; k < 6; k++) {
            int ax = nb[k][0], ay = nb[k][1], az = nb[k][2];
            if (ax < 0 || ay < 0 || az < 0 || ax >= nx || ay >= ny || az >= nz) continue;
            size_t ni = ((size_t) az * ny + ay) * nx + ax;
            if (state[ni] & 2) continue;
            if ((state[ni] & 1) && s->d[ni] < cell * 0.9f) continue;
            state[ni] |= 2;
            queue[tail++] = ni;
        }
    }
    for (size_t i = 0; i < n; i++) {
        if (state[i] & 1) {
            if ((state[i] & 2) && s->d[i] < 0) s->d[i] = -s->d[i];
            else if (!(state[i] & 2) && s->d[i] > cell * 1.5f) s->d[i] = -s->d[i];
            continue;
        }
        s->d[i] = (state[i] & 2) ? 1e4f : -1e4f;
    }
    size_t sy = (size_t) nx, sz = (size_t) nx * ny;
    for (int pass = 0; pass < 4; pass++) {
        int fwd = (pass & 1) == 0;
        for (int zz = 0; zz < nz; zz++) {
            int z = fwd ? zz : nz - 1 - zz;
            for (int yy = 0; yy < ny; yy++) {
                int y = fwd ? yy : ny - 1 - yy;
                for (int xx = 0; xx < nx; xx++) {
                    int x = fwd ? xx : nx - 1 - xx;
                    size_t idx = ((size_t) z * ny + y) * nx + x;
                    if (state[idx] & 1) continue;
                    float v = s->d[idx];
                    float a = fwd ? (x > 0 ? s->d[idx - 1] : v) : (x < nx - 1 ? s->d[idx + 1] : v);
                    float b = fwd ? (y > 0 ? s->d[idx - sy] : v) : (y < ny - 1 ? s->d[idx + sy] : v);
                    float c = fwd ? (z > 0 ? s->d[idx - sz] : v) : (z < nz - 1 ? s->d[idx + sz] : v);
                    if (v > 0) {
                        float m = a < b ? (a < c ? a : c) : (b < c ? b : c);
                        if (m > 0 && m + cell < v) s->d[idx] = m + cell;
                    } else {
                        float m = a > b ? (a > c ? a : c) : (b > c ? b : c);
                        if (m < 0 && m - cell > v) s->d[idx] = m - cell;
                    }
                }
            }
        }
    }
    free (queue);
    free (facing);
    free (state);
    return s;
}

void at_sdf_free (AtSdf *s) {
    if (!s) return;
    free (s->d);
    free (s);
}

float at_sdf_sample (const AtSdf *s, float x, float y, float z, float *grad) {
    float fx = (x - s->min[0]) * s->inv, fy = (y - s->min[1]) * s->inv, fz = (z - s->min[2]) * s->inv;
    if (fx < 0 || fy < 0 || fz < 0 || fx >= s->nx - 1 || fy >= s->ny - 1 || fz >= s->nz - 1) {
        if (grad) {
            grad[0] = 0;
            grad[1] = 1;
            grad[2] = 0;
        }
        return 1e3f;
    }
    int ix = (int) fx, iy = (int) fy, iz = (int) fz;
    float tx = fx - ix, ty = fy - iy, tz = fz - iz;
    const float *d = s->d + ((size_t) iz * s->ny + iy) * s->nx + ix;
    size_t sy = (size_t) s->nx, sz = (size_t) s->nx * s->ny;
    float c000 = d[0], c100 = d[1], c010 = d[sy], c110 = d[sy + 1];
    float c001 = d[sz], c101 = d[sz + 1], c011 = d[sz + sy], c111 = d[sz + sy + 1];
    float c00 = c000 + (c100 - c000) * tx, c10 = c010 + (c110 - c010) * tx;
    float c01 = c001 + (c101 - c001) * tx, c11 = c011 + (c111 - c011) * tx;
    float c0 = c00 + (c10 - c00) * ty, c1 = c01 + (c11 - c01) * ty;
    if (grad) {
        float gx0 = (c100 - c000) + ((c110 - c010) - (c100 - c000)) * ty;
        float gx1 = (c101 - c001) + ((c111 - c011) - (c101 - c001)) * ty;
        float gx = gx0 + (gx1 - gx0) * tz;
        float gy = (c10 - c00) + ((c11 - c01) - (c10 - c00)) * tz;
        float gz = c1 - c0;
        float l = sqrtf (gx * gx + gy * gy + gz * gz);
        if (l > 1e-9f) {
            grad[0] = gx / l;
            grad[1] = gy / l;
            grad[2] = gz / l;
        } else {
            grad[0] = 0;
            grad[1] = 1;
            grad[2] = 0;
        }
    }
    return c0 + (c1 - c0) * tz;
}
