namespace Singularity.Apps.Atelier {

    public class Camera {
        public Vec3 target = Vec3 (0, 1000, 0);
        public double yaw;
        public double pitch = 0.12;
        public double distance = 3200;
        public double fov = 35;

        public Camera copy () {
            var c = new Camera ();
            c.target = target;
            c.yaw = yaw;
            c.pitch = pitch;
            c.distance = distance;
            c.fov = fov;
            return c;
        }

        public Vec3 eye () {
            return target.add (Vec3 (Math.cos (pitch) * Math.sin (yaw), Math.sin (pitch), Math.cos (pitch) * Math.cos (yaw)).scale (distance));
        }

        public void basis (out Vec3 right, out Vec3 up, out Vec3 forward) {
            forward = target.sub (eye ()).normalized ();
            right = forward.cross (Vec3 (0, 1, 0)).normalized ();
            if (right.length () < 0.5) right = Vec3 (1, 0, 0);
            up = right.cross (forward).normalized ();
        }

        public bool project (Vec3 p, int w, int h, out double sx, out double sy, out double depth) {
            Vec3 r, u, f;
            basis (out r, out u, out f);
            var d = p.sub (eye ());
            double x = d.dot (r), y = d.dot (u), z = d.dot (f);
            double focal = (h / 2.0) / Math.tan (fov * Math.PI / 360);
            depth = z;
            if (z < 1) {
                sx = 0;
                sy = 0;
                return false;
            }
            sx = w / 2.0 + x / z * focal;
            sy = h / 2.0 - y / z * focal;
            return true;
        }

        public void frame (Gee.List<Mesh> meshes) {
            var min = Vec3 (double.INFINITY, double.INFINITY, double.INFINITY);
            var max = Vec3 (-double.INFINITY, -double.INFINITY, -double.INFINITY);
            bool any = false;
            foreach (var m in meshes) {
                if (!m.visible || m.vertices.size == 0) continue;
                Vec3 a, b;
                m.bounds (out a, out b);
                min = Vec3 (double.min (min.x, a.x), double.min (min.y, a.y), double.min (min.z, a.z));
                max = Vec3 (double.max (max.x, b.x), double.max (max.y, b.y), double.max (max.z, b.z));
                any = true;
            }
            if (!any) return;
            target = min.add (max).scale (0.5);
            double radius = max.sub (min).length () / 2;
            distance = double.max (100, radius / Math.sin (fov * Math.PI / 360) * 1.05);
        }
    }

    public class RenderOptions {
        public string shading = "material";
        public bool shadow = true;
        public bool wireframe;
        public Rgba top = Rgba (0.93, 0.93, 0.94, 1);
        public Rgba bottom = Rgba (0.78, 0.78, 0.8, 1);
        public double strain_min = -0.02;
        public double strain_max = 0.12;
        public double distance_max = 60;
        public bool transparent;
    }

    public abstract class Renderer3D {
        public abstract string name { get; }
        public abstract void render (Cairo.ImageSurface target, Gee.List<Mesh> meshes, Camera camera, RenderOptions options);
        public abstract bool pick (int x, int y, out int mesh_index, out int vertex);
    }

    public class CpuRenderer : Renderer3D {
        private float[] depth = {};
        private int[] ids = {};
        private int[] tri_ids = {};
        private int width;
        private int height;
        private Gee.List<Mesh>? last_meshes;

        public override string name {
            get { return "cpu"; }
        }

        private static double lin (double c) {
            return Math.pow (c.clamp (0, 1), 2.2);
        }

        private static double enc (double c) {
            return Math.pow (c.clamp (0, 1), 1 / 2.2);
        }

        public static Rgba ramp (double t) {
            t = t.clamp (0, 1);
            if (t < 0.25) return Rgba (0.1, 0.3 + t * 2.4, 0.95, 1);
            if (t < 0.5) return Rgba (0.1, 0.9, 0.95 - (t - 0.25) * 3.4, 1);
            if (t < 0.75) return Rgba (0.1 + (t - 0.5) * 3.6, 0.9, 0.1, 1);
            return Rgba (1, 0.9 - (t - 0.75) * 3.2, 0.1, 1);
        }

        public static double[] curvature (Mesh m) {
            int n = m.vertices.size;
            var sum = new double[n];
            var cnt = new int[n];
            if (m.normals.size != n) m.compute_normals ();
            for (int t = 0; t + 2 < m.triangles.size; t += 3) {
                for (int e = 0; e < 3; e++) {
                    int a = m.triangles[t + e], b = m.triangles[t + (e + 1) % 3];
                    double len = m.vertices[a].distance (m.vertices[b]);
                    if (len < 1e-9) continue;
                    double ang = Math.acos (m.normals[a].dot (m.normals[b]).clamp (-1, 1));
                    sum[a] += ang / len;
                    sum[b] += ang / len;
                    cnt[a]++;
                    cnt[b]++;
                }
            }
            for (int i = 0; i < n; i++) if (cnt[i] > 0) sum[i] /= cnt[i];
            return sum;
        }

        public override void render (Cairo.ImageSurface target, Gee.List<Mesh> meshes, Camera cam, RenderOptions opt) {
            width = target.get_width ();
            height = target.get_height ();
            last_meshes = meshes;
            int npx = width * height;
            depth = new float[npx];
            ids = new int[npx];
            tri_ids = new int[npx];
            for (int i = 0; i < npx; i++) {
                depth[i] = float.MAX;
                ids[i] = -1;
            }
            var cr = new Cairo.Context (target);
            if (opt.transparent) {
                cr.set_operator (Cairo.Operator.CLEAR);
                cr.paint ();
                cr.set_operator (Cairo.Operator.OVER);
            } else {
                var bg = new Cairo.Pattern.linear (0, 0, 0, height);
                bg.add_color_stop_rgb (0, opt.top.r, opt.top.g, opt.top.b);
                bg.add_color_stop_rgb (1, opt.bottom.r, opt.bottom.g, opt.bottom.b);
                cr.set_source (bg);
                cr.paint ();
            }
            if (opt.shadow) draw_shadow (cr, meshes, cam);
            target.flush ();
            unowned uint8[] data = target.get_data ();
            int stride = target.get_stride ();
            Vec3 right, up, fwd;
            cam.basis (out right, out up, out fwd);
            var eye = cam.eye ();
            double focal = (height / 2.0) / Math.tan (cam.fov * Math.PI / 360);
            var key = Vec3 (-0.45, 0.8, 0.55).normalized ();
            var fill = Vec3 (0.7, 0.3, 0.45).normalized ();
            var rim = Vec3 (0.1, 0.45, -1).normalized ();
            for (int mi = 0; mi < meshes.size; mi++) {
                var m = meshes[mi];
                if (!m.visible || m.triangles.size == 0) continue;
                if (m.normals.size != m.vertices.size) m.compute_normals ();
                double[]? curv = opt.shading == "curvature" ? curvature (m) : null;
                double cmax = 0;
                if (curv != null) foreach (var c in curv) cmax = double.max (cmax, c);
                int nv = m.vertices.size;
                var sx = new double[nv];
                var sy = new double[nv];
                var sz = new double[nv];
                var ok = new bool[nv];
                for (int i = 0; i < nv; i++) {
                    var d = m.vertices[i].sub (eye);
                    double x = d.dot (right), y = d.dot (up), z = d.dot (fwd);
                    sz[i] = z;
                    ok[i] = z > 1;
                    if (ok[i]) {
                        sx[i] = width / 2.0 + x / z * focal;
                        sy[i] = height / 2.0 - y / z * focal;
                    }
                }
                var base_col = Rgba (lin (m.color.r), lin (m.color.g), lin (m.color.b), 1);
                bool has_scalars = m.scalars.size == nv;
                for (int t = 0; t + 2 < m.triangles.size; t += 3) {
                    int a = m.triangles[t], b = m.triangles[t + 1], c = m.triangles[t + 2];
                    if (!ok[a] || !ok[b] || !ok[c]) continue;
                    double x0 = sx[a], y0 = sy[a], x1 = sx[b], y1 = sy[b], x2 = sx[c], y2 = sy[c];
                    double area = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0);
                    if (area.abs () < 1e-9) continue;
                    if (!m.double_sided && area > 0) continue;
                    int minx = int.max (0, (int) Math.floor (double.min (x0, double.min (x1, x2))));
                    int maxx = int.min (width - 1, (int) Math.ceil (double.max (x0, double.max (x1, x2))));
                    int miny = int.max (0, (int) Math.floor (double.min (y0, double.min (y1, y2))));
                    int maxy = int.min (height - 1, (int) Math.ceil (double.max (y0, double.max (y1, y2))));
                    if (minx > maxx || miny > maxy) continue;
                    double iz0 = 1 / sz[a], iz1 = 1 / sz[b], iz2 = 1 / sz[c];
                    for (int py = miny; py <= maxy; py++) {
                        double fy = py + 0.5;
                        for (int px = minx; px <= maxx; px++) {
                            double fx = px + 0.5;
                            double w0 = ((x1 - fx) * (y2 - fy) - (y1 - fy) * (x2 - fx)) / area;
                            double w1 = ((x2 - fx) * (y0 - fy) - (y2 - fy) * (x0 - fx)) / area;
                            double w2 = 1 - w0 - w1;
                            if (w0 < -1e-6 || w1 < -1e-6 || w2 < -1e-6) continue;
                            double iz = w0 * iz0 + w1 * iz1 + w2 * iz2;
                            float zz = (float) (1 / iz);
                            int idx = py * width + px;
                            if (zz >= depth[idx]) continue;
                            depth[idx] = zz;
                            ids[idx] = mi;
                            tri_ids[idx] = t / 3;
                            double p0 = w0 * iz0 / iz, p1 = w1 * iz1 / iz, p2 = w2 * iz2 / iz;
                            var nrm = m.normals[a].scale (p0).add (m.normals[b].scale (p1)).add (m.normals[c].scale (p2)).normalized ();
                            var pos = m.vertices[a].scale (p0).add (m.vertices[b].scale (p1)).add (m.vertices[c].scale (p2));
                            var view = eye.sub (pos).normalized ();
                            if (nrm.dot (view) < 0) nrm = nrm.neg ();
                            Rgba col = base_col;
                            double rough = m.roughness, metal = m.metallic;
                            if ((opt.shading == "strain" || opt.shading == "distance") && has_scalars) {
                                double s = m.scalars[a] * p0 + m.scalars[b] * p1 + m.scalars[c] * p2;
                                double tt = opt.shading == "strain" ? (s - opt.strain_min) / (opt.strain_max - opt.strain_min) : 1 - s / opt.distance_max;
                                var rc = ramp (tt);
                                col = Rgba (lin (rc.r), lin (rc.g), lin (rc.b), 1);
                                rough = 0.8;
                                metal = 0;
                            } else if (opt.shading == "curvature" && curv != null) {
                                double s = curv[a] * p0 + curv[b] * p1 + curv[c] * p2;
                                var rc = ramp (cmax > 0 ? Math.sqrt (s / cmax) : 0);
                                col = Rgba (lin (rc.r), lin (rc.g), lin (rc.b), 1);
                                rough = 0.7;
                                metal = 0;
                            }
                            double r, g, bl;
                            if (opt.shading == "zebra") {
                                var refl = nrm.scale (2 * nrm.dot (view)).sub (view);
                                int stripe = (int) Math.floor ((refl.y * 0.5 + 0.5) * 14);
                                double v = stripe % 2 == 0 ? 0.95 : 0.08;
                                double lam = 0.75 + 0.25 * double.max (0, nrm.dot (key));
                                r = g = bl = v * lam;
                            } else if (opt.shading == "wireframe") {
                                double lam = 0.55 + 0.45 * double.max (0, nrm.dot (key));
                                r = g = bl = lin (0.92) * lam;
                            } else {
                                shade (nrm, view, col, rough, metal, key, fill, rim, out r, out g, out bl);
                            }
                            int o = py * stride + px * 4;
                            data[o] = (uint8) (enc (bl) * 255);
                            data[o + 1] = (uint8) (enc (g) * 255);
                            data[o + 2] = (uint8) (enc (r) * 255);
                            data[o + 3] = 255;
                        }
                    }
                }
            }
            target.mark_dirty ();
            if (opt.wireframe || opt.shading == "wireframe") draw_edges (cr, meshes, cam, true);
            draw_lines (cr, meshes, cam);
        }

        private static void shade (Vec3 n, Vec3 v, Rgba c, double rough, double metal, Vec3 key, Vec3 fill, Vec3 rim, out double r, out double g, out double b) {
            double sky = 0.5 + 0.5 * n.y;
            double amb_r = 0.36 * sky + 0.16 * (1 - sky);
            double amb_g = 0.37 * sky + 0.14 * (1 - sky);
            double amb_b = 0.40 * sky + 0.12 * (1 - sky);
            double diff = 1.0 * double.max (0, n.dot (key)) + 0.35 * double.max (0, n.dot (fill)) + 0.45 * Math.pow (double.max (0, n.dot (rim)), 1.5);
            double kd = 1 - metal;
            r = c.r * kd * (amb_r + diff);
            g = c.g * kd * (amb_g + diff);
            b = c.b * kd * (amb_b + diff);
            double expo = Math.pow (2, 11 * (1 - rough.clamp (0.02, 1))) + 1;
            double norm = (expo + 8) / (8 * Math.PI);
            double f0r = 0.04 + (c.r - 0.04) * metal, f0g = 0.04 + (c.g - 0.04) * metal, f0b = 0.04 + (c.b - 0.04) * metal;
            double spec = 0;
            Vec3[] lights = { key, fill };
            for (int li = 0; li < 2; li++) {
                var l = lights[li];
                var hv = l.add (v).normalized ();
                spec += Math.pow (double.max (0, n.dot (hv)), expo) * norm * double.max (0, n.dot (l)) * (li == 0 ? 1.0 : 0.3);
            }
            spec = double.min (spec, 8);
            var refl = n.scale (2 * n.dot (v)).sub (v);
            double env = 0.25 + 0.55 * (0.5 + 0.5 * refl.y);
            double fres = Math.pow (1 - double.max (0, n.dot (v)), 5);
            double envk = (1 - rough * 0.8) * (metal + (1 - metal) * (0.04 + 0.5 * fres));
            r += f0r * spec + env * envk * (metal > 0 ? c.r : 1) * (metal > 0 ? 1 : 0.6);
            g += f0g * spec + env * envk * (metal > 0 ? c.g : 1) * (metal > 0 ? 1 : 0.6);
            b += f0b * spec + env * envk * (metal > 0 ? c.b : 1) * (metal > 0 ? 1 : 0.6);
        }

        private void draw_shadow (Cairo.Context cr, Gee.List<Mesh> meshes, Camera cam) {
            var min = Vec3 (double.INFINITY, double.INFINITY, double.INFINITY);
            var max = Vec3 (-double.INFINITY, -double.INFINITY, -double.INFINITY);
            bool any = false;
            foreach (var m in meshes) {
                if (!m.visible || m.triangles.size == 0) continue;
                Vec3 a, b;
                m.bounds (out a, out b);
                min = Vec3 (double.min (min.x, a.x), double.min (min.y, a.y), double.min (min.z, a.z));
                max = Vec3 (double.max (max.x, b.x), double.max (max.y, b.y), double.max (max.z, b.z));
                any = true;
            }
            if (!any) return;
            double rx = (max.x - min.x) * 0.55 + 40, rz = (max.z - min.z) * 0.55 + 40;
            double cx = (min.x + max.x) / 2, cz = (min.z + max.z) / 2;
            cr.save ();
            for (int ring = 6; ring >= 1; ring--) {
                double k = ring / 6.0;
                bool first = true;
                for (int i = 0; i <= 48; i++) {
                    double a = 2 * Math.PI * i / 48;
                    double sx, sy, d;
                    if (!cam.project (Vec3 (cx + rx * k * Math.cos (a), min.y, cz + rz * k * Math.sin (a)), width, height, out sx, out sy, out d)) continue;
                    if (first) cr.move_to (sx, sy);
                    else cr.line_to (sx, sy);
                    first = false;
                }
                cr.close_path ();
                cr.set_source_rgba (0, 0, 0, 0.05);
                cr.fill ();
            }
            cr.restore ();
        }

        private void draw_edges (Cairo.Context cr, Gee.List<Mesh> meshes, Camera cam, bool depth_test) {
            cr.save ();
            cr.set_line_width (0.6);
            foreach (var m in meshes) {
                if (!m.visible) continue;
                cr.set_source_rgba (0.15, 0.2, 0.3, 0.55);
                for (int t = 0; t + 2 < m.triangles.size; t += 3) {
                    for (int e = 0; e < 3; e++) {
                        var a = m.vertices[m.triangles[t + e]];
                        var b = m.vertices[m.triangles[t + (e + 1) % 3]];
                        double ax = 0, ay = 0, ad = 0, bx = 0, by = 0, bd = 0;
                        if (!cam.project (a, width, height, out ax, out ay, out ad) || !cam.project (b, width, height, out bx, out by, out bd)) continue;
                        if (depth_test && !visible_at ((ax + bx) / 2, (ay + by) / 2, (ad + bd) / 2)) continue;
                        cr.move_to (ax, ay);
                        cr.line_to (bx, by);
                    }
                }
                cr.stroke ();
            }
            cr.restore ();
        }

        private bool visible_at (double x, double y, double d) {
            int px = (int) x, py = (int) y;
            if (px < 0 || py < 0 || px >= width || py >= height) return false;
            float z = depth[py * width + px];
            return z == float.MAX || d <= z * 1.01 + 2;
        }

        private void draw_lines (Cairo.Context cr, Gee.List<Mesh> meshes, Camera cam) {
            cr.save ();
            cr.set_line_width (1.6);
            cr.set_line_cap (Cairo.LineCap.ROUND);
            foreach (var m in meshes) {
                if (!m.visible || m.lines.size == 0) continue;
                cr.set_source_rgba (m.color.r, m.color.g, m.color.b, 0.9);
                for (int i = 0; i + 1 < m.lines.size; i += 2) {
                    double ax = 0, ay = 0, ad = 0, bx = 0, by = 0, bd = 0;
                    if (!cam.project (m.vertices[m.lines[i]], width, height, out ax, out ay, out ad) || !cam.project (m.vertices[m.lines[i + 1]], width, height, out bx, out by, out bd)) continue;
                    cr.move_to (ax, ay);
                    cr.line_to (bx, by);
                }
                cr.stroke ();
                if (m.name == "cage") {
                    foreach (var v in m.vertices) {
                        double x, y, d;
                        if (!cam.project (v, width, height, out x, out y, out d)) continue;
                        cr.arc (x, y, 2.5, 0, 2 * Math.PI);
                        cr.fill ();
                    }
                }
            }
            cr.restore ();
        }

        public override bool pick (int x, int y, out int mesh_index, out int vertex) {
            mesh_index = -1;
            vertex = -1;
            if (x < 0 || y < 0 || x >= width || y >= height || ids.length != width * height) return false;
            int idx = y * width + x;
            if (ids[idx] < 0 || last_meshes == null) return false;
            mesh_index = ids[idx];
            var m = last_meshes[mesh_index];
            int t = tri_ids[idx] * 3;
            vertex = m.triangles[t];
            return true;
        }

        public int picked_triangle (int x, int y) {
            if (x < 0 || y < 0 || x >= width || y >= height || ids.length != width * height) return -1;
            return ids[y * width + x] < 0 ? -1 : tri_ids[y * width + x];
        }
    }
}
