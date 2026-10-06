using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class Sheet {
        public string name;
        public Gee.ArrayList<Gee.ArrayList<string>> rows = new Gee.ArrayList<Gee.ArrayList<string>> ();
        public Gee.HashSet<int> header_rows = new Gee.HashSet<int> ();

        public Sheet (string name) {
            this.name = name;
        }

        public void add (string[] cells, bool header = false) {
            var r = new Gee.ArrayList<string> ();
            foreach (var c in cells) r.add (c);
            if (header) header_rows.add (rows.size);
            rows.add (r);
        }
    }

    public class Tables {
        public static string csv_cell (string s) {
            if (s.contains (",") || s.contains ("\"") || s.contains ("\n") || s.contains (";")) return "\"" + s.replace ("\"", "\"\"") + "\"";
            return s;
        }

        public static string to_csv (Sheet sh) {
            var sb = new StringBuilder ();
            foreach (var r in sh.rows) {
                var cells = new Gee.ArrayList<string> ();
                foreach (var c in r) cells.add (csv_cell (c));
                sb.append (string.joinv (",", cells.to_array ()));
                sb.append ("\n");
            }
            return sb.str;
        }

        public static Gee.ArrayList<Gee.ArrayList<string>> parse_csv (string text) {
            var rows = new Gee.ArrayList<Gee.ArrayList<string>> ();
            char sep = ',';
            string first = text.split ("\n")[0];
            if (first.split (";").length > first.split (",").length) sep = ';';
            else if (first.split ("\t").length > first.split (",").length) sep = '\t';
            var row = new Gee.ArrayList<string> ();
            var cell = new StringBuilder ();
            bool quoted = false;
            for (int i = 0; i < text.length; i++) {
                char c = text[i];
                if (quoted) {
                    if (c == '"') {
                        if (i + 1 < text.length && text[i + 1] == '"') {
                            cell.append_c ('"');
                            i++;
                        } else {
                            quoted = false;
                        }
                    } else {
                        cell.append_c (c);
                    }
                } else if (c == '"') {
                    quoted = true;
                } else if (c == sep) {
                    row.add (cell.str);
                    cell.truncate ();
                } else if (c == '\n' || c == '\r') {
                    if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
                    row.add (cell.str);
                    cell.truncate ();
                    if (!(row.size == 1 && row[0] == "")) rows.add (row);
                    row = new Gee.ArrayList<string> ();
                } else {
                    cell.append_c (c);
                }
            }
            if (cell.len > 0 || row.size > 0) {
                row.add (cell.str);
                rows.add (row);
            }
            return rows;
        }

        public static Sheet measurements_sheet (MeasurementTable t) {
            var sh = new Sheet (_("Measurements"));
            string[] header = { "name", "full_name" };
            foreach (var s in t.sizes) header += s;
            header += "formula";
            sh.add (header, true);
            foreach (var m in t.items) {
                string[] r = { m.name, m.full_name };
                foreach (var s in t.sizes) {
                    double v = 0;
                    try {
                        v = t.value (m.name, s);
                    } catch (ExprError e) {
                    }
                    r += PathData.fmt (v, 2);
                }
                r += m.formula;
                sh.add (r);
            }
            return sh;
        }

        public static string measurements_csv (MeasurementTable t) {
            return to_csv (measurements_sheet (t));
        }

        public static MeasurementTable measurements_from_rows (Gee.List<Gee.ArrayList<string>> rows, string unit = "cm") throws FormatError {
            if (rows.size < 2) throw new FormatError.INVALID (_("The table has no measurements"));
            var header = rows[0];
            var t = new MeasurementTable ();
            t.unit = unit;
            int name_col = 0, full_col = -1, formula_col = -1;
            var size_cols = new Gee.ArrayList<int> ();
            for (int i = 0; i < header.size; i++) {
                string h = header[i].strip ();
                string hl = h.down ();
                if (hl == "name" || hl == "measurement") name_col = i;
                else if (hl == "full_name" || hl == "description") full_col = i;
                else if (hl == "formula") formula_col = i;
                else if (h != "") {
                    size_cols.add (i);
                    t.sizes.add (h);
                }
            }
            if (t.sizes.size == 0) {
                t.sizes.add ("base");
                t.kind = TableKind.INDIVIDUAL;
            }
            t.base_size = t.sizes[t.sizes.size / 2];
            for (int r = 1; r < rows.size; r++) {
                var row = rows[r];
                if (row.size <= name_col || row[name_col].strip () == "") continue;
                var m = new Measurement (row[name_col].strip ().replace (" ", "_"));
                if (full_col >= 0 && full_col < row.size) m.full_name = row[full_col];
                if (formula_col >= 0 && formula_col < row.size) m.formula = row[formula_col].strip ();
                for (int k = 0; k < size_cols.size; k++) {
                    int c = size_cols[k];
                    if (c >= row.size) continue;
                    double v;
                    if (double.try_parse (row[c].strip ().replace (",", "."), out v)) {
                        m.per_size[t.sizes[k]] = v;
                        if (t.sizes[k] == t.base_size) m.base_value = v;
                    }
                }
                if (m.per_size.has_key (t.base_size) && m.formula == "") m.base_value = m.per_size[t.base_size];
                t.items.add (m);
            }
            return t;
        }

        public static Sheet bom_sheet (TechPack tp, Gee.List<Colorway> colorways) {
            var sh = new Sheet (_("Bill of Materials"));
            string[] header = { _("Category"), _("Item"), _("Code"), _("Supplier"), _("Placement"), _("Composition"), _("Quantity"), _("Unit"), _("Waste %"), _("Unit Cost"), _("Cost"), _("Currency") };
            foreach (var cw in colorways) header += cw.name;
            sh.add (header, true);
            foreach (var b in tp.bom) {
                string[] r = { b.category, b.name, b.code, b.supplier, b.placement, b.composition, PathData.fmt (b.quantity, 3), b.unit, PathData.fmt (b.waste, 2), PathData.fmt (b.unit_cost, 4), PathData.fmt (b.cost (), 2), b.currency };
                foreach (var cw in colorways) r += b.colors.has_key (cw.name) ? b.colors[cw.name] : "";
                sh.add (r);
            }
            string[] total = { "", _("Total"), "", "", "", "", "", "", "", "", PathData.fmt (tp.total_cost (), 2), tp.bom.size > 0 ? tp.bom[0].currency : "" };
            sh.add (total, true);
            return sh;
        }

        public static string bom_csv (TechPack tp, Gee.List<Colorway> colorways) {
            return to_csv (bom_sheet (tp, colorways));
        }

        public static Sheet pom_sheet (TechPack tp, Pattern p) {
            var sh = new Sheet (_("Points of Measure"));
            string[] header = { _("Code"), _("Description"), _("How to Measure"), _("Tol -"), _("Tol +") };
            foreach (var s in p.all_sizes ()) header += s;
            sh.add (header, true);
            foreach (var pom in tp.poms) {
                string[] r = { pom.code, pom.description, pom.method, PathData.fmt (pom.tol_minus, 2), PathData.fmt (pom.tol_plus, 2) };
                foreach (var s in p.all_sizes ()) {
                    string? err;
                    var v = pom.value_for (p, s, out err);
                    r += v != null ? PathData.fmt (v, 1) : "";
                }
                sh.add (r);
            }
            return sh;
        }

        public static Sheet operations_sheet (TechPack tp) {
            var sh = new Sheet (_("Construction"));
            sh.add ({ _("Step"), _("Operation"), _("Stitch"), _("SPI"), _("Machine"), _("Seam"), _("Callout"), _("Minutes"), _("Notes") }, true);
            foreach (var o in tp.operations) sh.add ({ o.seq.to_string (), o.description, o.stitch, PathData.fmt (o.spi, 1), o.machine, o.seam, o.callout > 0 ? o.callout.to_string () : "", PathData.fmt (o.minutes, 2), o.notes });
            return sh;
        }

        private static string col_name (int c) {
            string s = "";
            int n = c + 1;
            while (n > 0) {
                int m = (n - 1) % 26;
                s = ((char) ('A' + m)).to_string () + s;
                n = (n - 1) / 26;
            }
            return s;
        }

        private static bool numeric (string s, out double v) {
            v = 0;
            string t = s.strip ();
            if (t == "" || t.has_prefix ("0") && t.length > 1 && !t.has_prefix ("0.")) return false;
            return double.try_parse (t, out v);
        }

        public static uint8[] xlsx (Gee.List<Sheet> sheets) throws Error {
            var zip = new ZipWriter ();
            var ct = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>");
            for (int i = 0; i < sheets.size; i++) ct.append ("<Override PartName=\"/xl/worksheets/sheet%d.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>".printf (i + 1));
            ct.append ("</Types>");
            zip.add_text ("[Content_Types].xml", ct.str);
            zip.add_text ("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>");
            var wb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>");
            var rels = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">");
            for (int i = 0; i < sheets.size; i++) {
                string nm = sheets[i].name.replace ("/", " ").replace ("?", "").replace ("*", "").replace ("[", "(").replace ("]", ")");
                if (nm.char_count () > 31) nm = nm.substring (0, nm.index_of_nth_char (31));
                wb.append ("<sheet name=\"%s\" sheetId=\"%d\" r:id=\"rId%d\"/>".printf (Markup.escape_text (nm), i + 1, i + 1));
                rels.append ("<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet%d.xml\"/>".printf (i + 1, i + 1));
            }
            wb.append ("</sheets></workbook>");
            rels.append ("<Relationship Id=\"rId%d\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>".printf (sheets.size + 1));
            zip.add_text ("xl/workbook.xml", wb.str);
            zip.add_text ("xl/_rels/workbook.xml.rels", rels.str);
            zip.add_text ("xl/styles.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/></cellXfs></styleSheet>");
            for (int i = 0; i < sheets.size; i++) {
                var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>");
                var sh = sheets[i];
                for (int r = 0; r < sh.rows.size; r++) {
                    sb.append ("<row r=\"%d\">".printf (r + 1));
                    bool hdr = sh.header_rows.contains (r);
                    for (int c = 0; c < sh.rows[r].size; c++) {
                        string v = sh.rows[r][c];
                        if (v == "") continue;
                        string refn = "%s%d".printf (col_name (c), r + 1);
                        double num;
                        if (!hdr && numeric (v, out num)) sb.append ("<c r=\"%s\"><v>%s</v></c>".printf (refn, v.strip ()));
                        else sb.append ("<c r=\"%s\" t=\"inlineStr\"%s><is><t xml:space=\"preserve\">%s</t></is></c>".printf (refn, hdr ? " s=\"1\"" : "", Markup.escape_text (v)));
                    }
                    sb.append ("</row>");
                }
                sb.append ("</sheetData></worksheet>");
                zip.add_text ("xl/worksheets/sheet%d.xml".printf (i + 1), sb.str);
            }
            return zip.finish ();
        }

        public static Gee.ArrayList<Gee.ArrayList<string>> read_xlsx (uint8[] data, int sheet_index = 0) throws Error {
            var zip = new ZipReader (data);
            var shared = new Gee.ArrayList<string> ();
            string? ss = zip.read_text ("xl/sharedStrings.xml");
            if (ss != null) {
                var doc = Xml.Parser.read_memory (ss, ss.length, null, null, Xml.ParserOption.NONET);
                if (doc != null) {
                    for (Xml.Node* si = doc->get_root_element ()->children; si != null; si = si->next) {
                        if (si->type == Xml.ElementType.ELEMENT_NODE && si->name == "si") shared.add (si->get_content ());
                    }
                    delete doc;
                }
            }
            string? sx = zip.read_text ("xl/worksheets/sheet%d.xml".printf (sheet_index + 1));
            if (sx == null) throw new FormatError.INVALID (_("The workbook has no such sheet"));
            var rows = new Gee.ArrayList<Gee.ArrayList<string>> ();
            var doc = Xml.Parser.read_memory (sx, sx.length, null, null, Xml.ParserOption.NONET);
            if (doc == null) throw new FormatError.INVALID (_("The sheet is damaged"));
            Xml.Node* data_node = null;
            for (Xml.Node* c = doc->get_root_element ()->children; c != null; c = c->next) if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == "sheetData") data_node = c;
            if (data_node != null) {
                for (Xml.Node* r = data_node->children; r != null; r = r->next) {
                    if (r->type != Xml.ElementType.ELEMENT_NODE || r->name != "row") continue;
                    var row = new Gee.ArrayList<string> ();
                    for (Xml.Node* c = r->children; c != null; c = c->next) {
                        if (c->type != Xml.ElementType.ELEMENT_NODE || c->name != "c") continue;
                        string refn = c->get_prop ("r") ?? "";
                        int col = 0;
                        int k = 0;
                        while (k < refn.length && refn[k].isalpha ()) {
                            col = col * 26 + (refn[k].toupper () - 'A' + 1);
                            k++;
                        }
                        col = col > 0 ? col - 1 : row.size;
                        while (row.size < col) row.add ("");
                        string t = c->get_prop ("t") ?? "";
                        string val = "";
                        for (Xml.Node* v = c->children; v != null; v = v->next) {
                            if (v->type != Xml.ElementType.ELEMENT_NODE) continue;
                            if (v->name == "v") val = v->get_content ();
                            else if (v->name == "is") val = v->get_content ();
                        }
                        if (t == "s") {
                            int idx = int.parse (val);
                            val = idx >= 0 && idx < shared.size ? shared[idx] : "";
                        }
                        row.add (val);
                    }
                    rows.add (row);
                }
            }
            delete doc;
            return rows;
        }

        public static uint8[] ods (Gee.List<Sheet> sheets) throws Error {
            var zip = new ZipWriter ();
            zip.add_text ("mimetype", "application/vnd.oasis.opendocument.spreadsheet", false);
            zip.add_text ("META-INF/manifest.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.2\"><manifest:file-entry manifest:full-path=\"/\" manifest:media-type=\"application/vnd.oasis.opendocument.spreadsheet\"/><manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/></manifest:manifest>");
            var sb = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" office:version=\"1.2\"><office:body><office:spreadsheet>");
            foreach (var sh in sheets) {
                sb.append ("<table:table table:name=\"%s\">".printf (Markup.escape_text (sh.name)));
                foreach (var r in sh.rows) {
                    sb.append ("<table:table-row>");
                    foreach (var c in r) {
                        double num;
                        if (numeric (c, out num)) sb.append ("<table:table-cell office:value-type=\"float\" office:value=\"%s\"><text:p>%s</text:p></table:table-cell>".printf (c.strip (), Markup.escape_text (c)));
                        else sb.append ("<table:table-cell office:value-type=\"string\"><text:p>%s</text:p></table:table-cell>".printf (Markup.escape_text (c)));
                    }
                    sb.append ("</table:table-row>");
                }
                sb.append ("</table:table>");
            }
            sb.append ("</office:spreadsheet></office:body></office:document-content>");
            zip.add_text ("content.xml", sb.str);
            return zip.finish ();
        }
    }
}
