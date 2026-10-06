namespace Singularity.Apps.Atelier {

    public struct Vec3 {
        public double x;
        public double y;
        public double z;

        public Vec3 (double x, double y, double z) {
            this.x = x;
            this.y = y;
            this.z = z;
        }

        public Vec3 add (Vec3 o) {
            return Vec3 (x + o.x, y + o.y, z + o.z);
        }

        public Vec3 sub (Vec3 o) {
            return Vec3 (x - o.x, y - o.y, z - o.z);
        }

        public Vec3 scale (double s) {
            return Vec3 (x * s, y * s, z * s);
        }

        public double dot (Vec3 o) {
            return x * o.x + y * o.y + z * o.z;
        }

        public Vec3 cross (Vec3 o) {
            return Vec3 (y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
        }

        public double length () {
            return Math.sqrt (x * x + y * y + z * z);
        }

        public Vec3 normalized () {
            double l = length ();
            return l > 1e-12 ? scale (1 / l) : Vec3 (0, 0, 0);
        }

        public double distance (Vec3 o) {
            return sub (o).length ();
        }

        public Vec3 lerp (Vec3 o, double t) {
            return Vec3 (x + (o.x - x) * t, y + (o.y - y) * t, z + (o.z - z) * t);
        }

        public Vec3 neg () {
            return Vec3 (-x, -y, -z);
        }

        public Vec3 rotate_y (double a) {
            double c = Math.cos (a), s = Math.sin (a);
            return Vec3 (x * c + z * s, y, -x * s + z * c);
        }

        public Vec3 rotate_x (double a) {
            double c = Math.cos (a), s = Math.sin (a);
            return Vec3 (x, y * c - z * s, y * s + z * c);
        }

        public static Vec3 zero () {
            return Vec3 (0, 0, 0);
        }

        public Vec3 any_perpendicular () {
            var a = x.abs () < 0.9 ? Vec3 (1, 0, 0) : Vec3 (0, 1, 0);
            return cross (a).normalized ();
        }
    }
}
