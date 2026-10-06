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
            p.increments.add (new Increment ("ease", "4"));
            p.increments.add (new Increment ("armhole", "bust_circ / 8 + 8"));
            p.increments.add (new Increment ("length", "back_waist_length + waist_to_hip + 4"));

            var a = base_pt (p, "A", "0", "0");
            var c = end_line (p, "C", a, "neck_circ / 6 + 2", "270");
            var d = end_line (p, "D", a, "neck_circ / 6", "0");
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
            var bc = end_line (p, "C1", ba, "2", "270");
            var bd = end_line (p, "D1", ba, "neck_circ / 6", "0");
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

            p.increments.add (new Increment ("cap", "#armhole * 0.55"));
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
            panel.seam_allowance = "1";
            panel.thickness = 1.4;
            panel.leather_turn = "1.2";
            var g0 = base_pt (p, "G", "50", "0");
            var g1 = end_line (p, "G2", g0, "#depth", "0");
            var g2 = end_line (p, "G3", g1, "#height * 2 + #width", "270");
            var g3 = end_line (p, "G4", g0, "#height * 2 + #width", "270");
            var gusset = piece (p, _("Gusset"), { g0.id, g1.id, g2.id, g3.id }, { false, false, false, false });
            gusset.material = "leather";
            gusset.seam_allowance = "1";
            gusset.thickness = 1.4;
            var h0 = base_pt (p, "H", "70", "0");
            var h1 = end_line (p, "H2", h0, "3", "0");
            var h2 = end_line (p, "H3", h1, "60", "270");
            var h3 = end_line (p, "H4", h0, "60", "270");
            var handle = piece (p, _("Handle"), { h0.id, h1.id, h2.id, h3.id }, { false, false, false, false });
            handle.material = "leather";
            handle.quantity = 2;
            handle.built_in = true;
            handle.thickness = 2.5;
            handle.leather_skive = "0.8";
        }
    }
}
