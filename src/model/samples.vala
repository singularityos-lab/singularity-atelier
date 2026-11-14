namespace Singularity.Apps.Atelier {

    namespace Samples {
        private PatternPoint base_pt (Pattern p, string name, string x, string y) {
            var pt = p.add_point (PointKind.BASE, name);
            pt.fx = x;
            pt.fy = y;
            return pt;
        }

        private PatternPoint end_line (Pattern p, string name, PatternPoint from, string length, string angle) {
            var pt = p.add_point (PointKind.END_LINE, name);
            pt.a = from.id;
            pt.flength = length;
            pt.fangle = angle;
            return pt;
        }

        private PatternPoint offset (Pattern p, string name, PatternPoint from, string dx, string dy) {
            var pt = p.add_point (PointKind.OFFSET, name);
            pt.a = from.id;
            pt.fx = dx;
            pt.fy = dy;
            return pt;
        }

        private PatternCurve path (Pattern p, PatternPoint a, string a_out, string l_out, PatternPoint b, string b_in, string l_in) {
            var c = p.add_curve ({ a.id, b.id }, CurveKind.PATH);
            c.knots[0].angle_out = a_out;
            c.knots[0].len_out = l_out;
            c.knots[1].angle_in = b_in;
            c.knots[1].len_in = l_in;
            return c;
        }

        private Piece piece (Pattern p, string name, string[] refs, bool[] curves) {
            var pc = new Piece (p.new_id ("d"), name);
            for (int i = 0; i < refs.length; i++) pc.nodes.add (new PieceNode (refs[i], curves[i]));
            p.pieces.add (pc);
            return pc;
        }

        public void tshirt_pattern (Pattern p) {
            p.increments.add (new Increment ("ease", "9"));
            p.increments.add (new Increment ("armhole", "bust_circ / 8 + 11.5"));
            p.increments.add (new Increment ("length", "back_waist_length + waist_to_hip + 4"));

            var a = base_pt (p, "A", "0", "0");
            var c = end_line (p, "C", a, "neck_circ / 6 + 4", "270");
            var d = end_line (p, "D", a, "neck_circ / 6 + 2", "0");
            var e = end_line (p, "E", d, "shoulder_length + 1", "340");
            var f = end_line (p, "F", a, "#armhole", "270");
            var g = end_line (p, "G", f, "bust_circ / 4 + #ease / 4", "0");
            var h = end_line (p, "H", a, "#length", "270");
            var i = end_line (p, "I", h, "hip_circ / 4 + #ease / 4", "0");
            var neck = path (p, d, "270", "neck_circ / 14", c, "0", "neck_circ / 12");
            neck.name = "Front_Neck";
            var arm = path (p, e, "255", "#armhole / 3", g, "180", "3");
            arm.name = "Front_Armhole";
            var front = piece (p, _("Front"), { h.id, c.id, neck.id, e.id, arm.id, i.id }, { false, false, true, false, true, false });
            front.code = "01";
            front.on_fold = true;
            front.fold_edge = 0;
            front.quantity = 1;
            front.nodes[5].sa_after = "2.5";
            front.nodes[1].notch = true;
            front.placement = "front";

            var ba = base_pt (p, "A1", "40", "0");
            var bc = end_line (p, "C1", ba, "2.5", "270");
            var bd = end_line (p, "D1", ba, "neck_circ / 6 + 2", "0");
            var be = end_line (p, "E1", bd, "shoulder_length + 1", "340");
            var bf = end_line (p, "F1", ba, "#armhole", "270");
            var bg = end_line (p, "G1", bf, "bust_circ / 4 + #ease / 4", "0");
            var bh = end_line (p, "H1", ba, "#length", "270");
            var bi = end_line (p, "I1", bh, "hip_circ / 4 + #ease / 4", "0");
            var bneck = path (p, bd, "250", "1", bc, "0", "neck_circ / 10");
            bneck.name = "Back_Neck";
            var barm = path (p, be, "260", "#armhole / 3", bg, "180", "4");
            barm.name = "Back_Armhole";
            var back = piece (p, _("Back"), { bh.id, bc.id, bneck.id, be.id, barm.id, bi.id }, { false, false, true, false, true, false });
            back.code = "02";
            back.on_fold = true;
            back.fold_edge = 0;
            back.nodes[5].sa_after = "2.5";
            back.placement = "back";

            p.increments.add (new Increment ("cap", "#armhole * 0.46"));
            p.increments.add (new Increment ("bicep", "upper_arm_circ + 5"));
            var t = base_pt (p, "T", "80", "0");
            var lb = offset (p, "L", t, "-#bicep / 2", "#cap");
            var rb = offset (p, "R", t, "#bicep / 2", "#cap");
            var lh = offset (p, "LH", t, "-#bicep / 2 + 1.5", "#cap + 12");
            var rh = offset (p, "RH", t, "#bicep / 2 - 1.5", "#cap + 12");
            var cap = p.add_curve ({ lb.id, t.id, rb.id }, CurveKind.PATH);
            cap.name = "Sleeve_Cap";
            cap.knots[0].angle_out = "20";
            cap.knots[0].len_out = "#cap / 2";
            cap.knots[1].angle_in = "180";
            cap.knots[1].len_in = "#bicep / 6";
            cap.knots[1].angle_out = "0";
            cap.knots[1].len_out = "#bicep / 6";
            cap.knots[2].angle_in = "160";
            cap.knots[2].len_in = "#cap / 2";
            var sleeve = piece (p, _("Sleeve"), { lh.id, lb.id, cap.id, rb.id, rh.id }, { false, false, true, false, false });
            sleeve.code = "03";
            sleeve.quantity = 2;
            sleeve.pair = true;
            sleeve.nodes[4].sa_after = "2.5";
            sleeve.placement = "sleeve";
            sleeve.grain_a = t.id;
            var mid = p.add_point (PointKind.MIDPOINT, "M");
            mid.a = lh.id;
            mid.b = rh.id;
            sleeve.grain_b = mid.id;
            var n = p.add_point (PointKind.ALONG_CURVE, "N");
            n.a = cap.id;
            n.flength = "Sleeve_Cap / 2";
            n.hidden = true;
        }

        private void clear (Project project) {
            var p = project.pattern;
            p.increments.clear ();
            p.points.clear ();
            p.curves.clear ();
            p.pieces.clear ();
            project.garment.seams.clear ();
            project.garment.piece_fabrics.clear ();
        }

        private void seam (Project project, Piece a, int ea, Piece b, int eb) {
            var sp = new SeamPair (a.id, ea, b.id, eb);
            sp.reverse_b = false;
            project.garment.seams.add (sp);
        }

        public string[] garments () {
            return { "tshirt", "skirt", "trousers" };
        }

        public string garment_label (string id) {
            switch (id) {
                case "skirt": return _("Straight Skirt");
                case "trousers": return _("Trousers");
                default: return _("T-Shirt");
            }
        }

        public void garment (Project project, string id) {
            clear (project);
            project.garment.auto_sew = id == "tshirt";
            switch (id) {
                case "skirt":
                    skirt_pattern (project);
                    break;
                case "trousers":
                    trousers_pattern (project);
                    break;
                default:
                    tshirt_pattern (project.pattern);
                    break;
            }
            project.touch ("pattern");
        }

        private Piece skirt_half (Pattern p, string name, string tag, string x0, string placement) {
            var a = base_pt (p, "A" + tag, x0, "0");
            var h = end_line (p, "H" + tag, a, "#skirt", "270");
            var s = offset (p, "S" + tag, a, "waist_circ / 4 + 1", "-1.2");
            var q = offset (p, "P" + tag, a, "hip_circ / 4 + 1", "waist_to_hip");
            var e = offset (p, "Q" + tag, a, "hip_circ / 4 + 1", "#skirt");
            var waist = path (p, a, "0", "waist_circ / 12", s, "187", "waist_circ / 12");
            waist.name = name + "_Waist";
            var side = path (p, s, "282", "waist_to_hip / 3", q, "90", "waist_to_hip / 3");
            side.name = name + "_Side";
            var pc = piece (p, name, { h.id, a.id, waist.id, side.id, e.id }, { false, false, true, true, false });
            pc.on_fold = true;
            pc.fold_edge = 0;
            pc.placement = placement;
            pc.nodes[4].sa_after = "3";
            return pc;
        }

        public void skirt_pattern (Project project) {
            var p = project.pattern;
            p.increments.add (new Increment ("skirt", "waist_to_knee"));
            var front = skirt_half (p, _("Front"), "", "0", "skirt-front");
            front.code = "01";
            var back = skirt_half (p, _("Back"), "1", "45", "skirt-back");
            back.code = "02";
            seam (project, front, 2, back, 2);
            seam (project, front, 3, back, 3);
        }

        private Piece trouser_leg (Pattern p, string name, string tag, string x0, string fork, string rise_up, string placement) {
            string mid = "(%s + hip_circ / 4 + 1) / 2".printf (fork);
            var wc = base_pt (p, "WC" + tag, "%s + %s + 1".printf (x0, fork), rise_up);
            var ws = base_pt (p, "WS" + tag, "%s + %s + waist_circ / 4 + 2.5".printf (x0, fork), "-1");
            var hs = base_pt (p, "HS" + tag, "%s + %s + hip_circ / 4 + 1".printf (x0, fork), "waist_to_hip");
            var hc = base_pt (p, "HC" + tag, "%s + %s".printf (x0, fork), "waist_to_hip");
            var cp = base_pt (p, "CP" + tag, x0, "#rise");
            var ko = base_pt (p, "KO" + tag, "%s + %s + #kneew".printf (x0, mid), "waist_to_knee");
            var ki = base_pt (p, "KI" + tag, "%s + %s - #kneew".printf (x0, mid), "waist_to_knee");
            var ho = base_pt (p, "HO" + tag, "%s + %s + #hem / 2".printf (x0, mid), "#rise + inseam - 7");
            var hi = base_pt (p, "HI" + tag, "%s + %s - #hem / 2".printf (x0, mid), "#rise + inseam - 7");
            var side = path (p, ws, "280", "waist_to_hip / 3", hs, "90", "waist_to_hip / 3");
            side.name = name + "_Side";
            var crotch = path (p, cp, "5", "%s * 0.6".printf (fork), hc, "270", "(#rise - waist_to_hip) * 0.6");
            crotch.name = name + "_Crotch";
            var pc = piece (p, name, { wc.id, ws.id, side.id, ko.id, ho.id, hi.id, ki.id, cp.id, crotch.id }, { false, false, true, false, false, false, false, false, true });
            pc.pair = true;
            pc.quantity = 2;
            pc.placement = placement;
            pc.nodes[4].sa_after = "3";
            return pc;
        }

        public void trousers_pattern (Project project) {
            var p = project.pattern;
            p.increments.add (new Increment ("rise", "crotch_depth + 3"));
            p.increments.add (new Increment ("forkf", "hip_circ / 16 + 0.5"));
            p.increments.add (new Increment ("forkb", "hip_circ / 8 + 2"));
            p.increments.add (new Increment ("kneew", "knee_circ / 4 + 3"));
            p.increments.add (new Increment ("hem", "ankle_circ / 2 + 7"));
            var front = trouser_leg (p, _("Front"), "", "0", "#forkf", "0", "leg-front");
            front.code = "01";
            var back = trouser_leg (p, _("Back"), "1", "60", "#forkb", "-2", "leg-back");
            back.code = "02";
            foreach (int e in new int[] { 1, 2, 3, 5, 6 }) seam (project, front, e, back, e);
            foreach (int e in new int[] { 7, 8 }) {
                seam (project, front, e, front, e);
                seam (project, back, e, back, e);
            }
        }

        public void tote_seams (Project project) {
            var p = project.pattern;
            if (p.pieces.size < 3) return;
            var panel = p.pieces[0];
            var gusset = p.pieces[1];
            var handle = p.pieces[2];
            double h = 38, w = 40, total = h * 2 + w;
            double[,] front = { { 3, 1 - h / total, 1 }, { 2, h / total, 1 - h / total }, { 1, 0, h / total } };
            double[,] back = { { 3, (h + w) / total, 1 }, { 2, h / total, (h + w) / total }, { 1, 0, h / total } };
            for (int i = 0; i < 3; i++) {
                var a = new SeamPair (panel.id, (int) front[i, 0], gusset.id, 3);
                a.reverse_b = false;
                a.b0 = front[i, 1];
                a.b1 = front[i, 2];
                a.copy_a = 0;
                a.copy_b = 0;
                project.garment.seams.add (a);
                var b = new SeamPair (panel.id, (int) back[i, 0], gusset.id, 1);
                b.reverse_b = false;
                b.b0 = back[i, 1];
                b.b1 = back[i, 2];
                b.copy_a = 1;
                b.copy_b = 0;
                project.garment.seams.add (b);
            }
            double[] at = { 0.25, 0.75 };
            int[] ends = { 0, 2 };
            for (int i = 0; i < 2; i++) {
                var sp = new SeamPair (handle.id, ends[i], panel.id, 0);
                sp.reverse_b = i == 1;
                sp.b0 = at[i] - 0.0375;
                sp.b1 = at[i] + 0.0375;
                project.garment.seams.add (sp);
            }
        }

        public void tote_pattern (Pattern p) {
            p.unit = "cm";
            p.increments.add (new Increment ("width", "40"));
            p.increments.add (new Increment ("height", "38"));
            p.increments.add (new Increment ("depth", "12"));
            var a = base_pt (p, "A", "0", "0");
            var b = end_line (p, "B", a, "#width", "0");
            var c = end_line (p, "C", b, "#height", "270");
            var d = end_line (p, "D", a, "#height", "270");
            var panel = piece (p, _("Front Panel"), { a.id, b.id, c.id, d.id }, { false, false, false, false });
            panel.material = "leather";
            panel.quantity = 2;
            panel.pair = true;
            panel.placement = "bag-panel";
            panel.seam_allowance = "1";
            panel.thickness = 1.4;
            panel.leather_turn = "1.2";
            var g0 = base_pt (p, "G", "50", "0");
            var g1 = end_line (p, "G2", g0, "#depth", "0");
            var g2 = end_line (p, "G3", g1, "#height * 2 + #width", "270");
            var g3 = end_line (p, "G4", g0, "#height * 2 + #width", "270");
            var gusset = piece (p, _("Gusset"), { g0.id, g1.id, g2.id, g3.id }, { false, false, false, false });
            gusset.material = "leather";
            gusset.placement = "bag-gusset";
            gusset.seam_allowance = "1";
            gusset.thickness = 1.4;
            var h0 = base_pt (p, "H", "70", "0");
            var h1 = end_line (p, "H2", h0, "3", "0");
            var h2 = end_line (p, "H3", h1, "60", "270");
            var h3 = end_line (p, "H4", h0, "60", "270");
            var handle = piece (p, _("Handle"), { h0.id, h1.id, h2.id, h3.id }, { false, false, false, false });
            handle.material = "leather";
            handle.quantity = 2;
            handle.pair = true;
            handle.placement = "bag-handle";
            handle.built_in = true;
            handle.thickness = 2.5;
            handle.leather_skive = "0.8";
        }
    }
}
