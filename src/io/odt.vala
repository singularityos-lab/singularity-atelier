using Singularity.Vector;

namespace Singularity.Apps.Atelier {

    public class TechPackOdt {
        private StringBuilder body = new StringBuilder ();
        private ZipWriter zip = new ZipWriter ();
        private Gee.ArrayList<string> pictures = new Gee.ArrayList<string> ();
        private int table_count = 0;

        private static string esc (string s) {
            return Markup.escape_text (s);
        }

        private void heading (string text, int level) {
            body.append ("<text:h text:style-name=\"Heading_20_%d\" text:outline-level=\"%d\">%s</text:h>\n".printf (level, level, esc (text)));
        }

        private void para (string text) {
            foreach (var line in text.split ("\n")) body.append ("<text:p text:style-name=\"Standard\">%s</text:p>\n".printf (esc (line)));
        }

        private void table (Sheet sh) {
            int cols = 0;
            foreach (var r in sh.rows) cols = int.max (cols, r.size);
            if (cols == 0) return;
            table_count++;
            body.append ("<table:table table:name=\"%s %d\" table:style-name=\"Table\">\n".printf (esc (sh.name), table_count));
            body.append ("<table:table-column table:number-columns-repeated=\"%d\"/>\n".printf (cols));
            for (int r = 0; r < sh.rows.size; r++) {
                bool hdr = sh.header_rows.contains (r);
                body.append (hdr && r == 0 ? "<table:table-header-rows><table:table-row>" : "<table:table-row>");
                for (int c = 0; c < cols; c++) {
                    string v = c < sh.rows[r].size ? sh.rows[r][c] : "";
                    body.append ("<table:table-cell table:style-name=\"Cell\" office:value-type=\"string\"><text:p text:style-name=\"%s\">%s</text:p></table:table-cell>".printf (hdr ? "TableHeading" : "TableContents", esc (v)));
                }
                body.append (hdr && r == 0 ? "</table:table-row></table:table-header-rows>\n" : "</table:table-row>\n");
            }
            body.append ("</table:table>\n");
        }

        private void image (Cairo.ImageSurface surf, double width_cm) throws Error {
            string name = "Pictures/image%d.png".printf (pictures.size + 1);
            zip.add (name, OraFormat.png_bytes (surf), false);
            pictures.add (name);
            double h = width_cm * surf.get_height () / double.max (1, surf.get_width ());
            body.append ("<text:p text:style-name=\"Standard\"><draw:frame draw:name=\"img%d\" text:anchor-type=\"as-char\" svg:width=\"%scm\" svg:height=\"%scm\"><draw:image xlink:href=\"%s\" xlink:type=\"simple\" xlink:show=\"embed\" xlink:actuate=\"onLoad\"/></draw:frame></text:p>\n".printf (
                pictures.size, PathData.fmt (width_cm, 2), PathData.fmt (h, 2), name));
        }

        public static uint8[] export (Project p, string colorway = "") throws Error {
            var o = new TechPackOdt ();
            o.build (p, colorway);
            return o.finish ();
        }

        private void build (Project p, string colorway) throws Error {
            var tp = p.techpack;
            var cw = colorway != "" ? (p.find_colorway (colorway) ?? p.colorway ()) : p.colorway ();
            heading (tp.style_name != "" ? tp.style_name : p.title, 1);
            var info = new Sheet (_("Style"));
            info.add ({ _("Style Number"), tp.style_number });
            info.add ({ _("Season"), tp.season });
            info.add ({ _("Brand"), tp.brand });
            info.add ({ _("Designer"), tp.designer });
            info.add ({ _("Category"), tp.category });
            info.add ({ _("Status"), tp.status });
            info.add ({ _("Base Size"), p.pattern.table.base_size });
            info.add ({ _("Colorway"), cw.name });
            table (info);
            if (tp.notes != "") para (tp.notes);
            foreach (var sheet in p.flats) {
                heading (_("Technical Drawing: %s").printf (sheet.name), 2);
                image (FlatRenderer.render_sheet (sheet, cw, 1400), 16);
                var legend = new Sheet (_("Callouts"));
                legend.add ({ "#", _("Detail") }, true);
                foreach (var it in sheet.items) if (it.kind == FlatItemKind.CALLOUT) legend.add ({ it.number.to_string (), it.text });
                if (legend.rows.size > 1) table (legend);
            }
            if (tp.poms.size > 0) {
                heading (_("Points of Measure"), 2);
                table (Tables.pom_sheet (tp, p.pattern));
            }
            if (tp.bom.size > 0) {
                heading (_("Bill of Materials"), 2);
                table (Tables.bom_sheet (tp, p.colorways));
            }
            if (tp.operations.size > 0) {
                heading (_("Construction"), 2);
                table (Tables.operations_sheet (tp));
            }
            if (tp.revisions.size > 0) {
                heading (_("Revisions"), 2);
                var rev = new Sheet (_("Revisions"));
                rev.add ({ _("Revision"), _("Date"), _("Author"), _("Change") }, true);
                foreach (var r in tp.revisions) rev.add ({ r.number.to_string (), r.date, r.author, r.note });
                table (rev);
            }
        }

        private uint8[] finish () throws Error {
            var z = new ZipWriter ();
            z.add_text ("mimetype", "application/vnd.oasis.opendocument.text", false);
            var manifest = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.2\">\n<manifest:file-entry manifest:full-path=\"/\" manifest:version=\"1.2\" manifest:media-type=\"application/vnd.oasis.opendocument.text\"/>\n<manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/>\n<manifest:file-entry manifest:full-path=\"styles.xml\" manifest:media-type=\"text/xml\"/>\n");
            foreach (var pic in pictures) manifest.append ("<manifest:file-entry manifest:full-path=\"%s\" manifest:media-type=\"image/png\"/>\n".printf (pic));
            manifest.append ("</manifest:manifest>\n");
            z.add_text ("META-INF/manifest.xml", manifest.str);
            string ns = "xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:draw=\"urn:oasis:names:tc:opendocument:xmlns:drawing:1.0\" xmlns:fo=\"urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" xmlns:svg=\"urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0\"";
            z.add_text ("styles.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-styles %s office:version=\"1.2\"><office:styles>".printf (ns) +
                "<style:style style:name=\"Standard\" style:family=\"paragraph\"><style:text-properties fo:font-size=\"10pt\"/></style:style>" +
                "<style:style style:name=\"Heading_20_1\" style:display-name=\"Heading 1\" style:family=\"paragraph\" style:default-outline-level=\"1\"><style:paragraph-properties fo:margin-top=\"0.3cm\" fo:margin-bottom=\"0.2cm\"/><style:text-properties fo:font-size=\"18pt\" fo:font-weight=\"bold\"/></style:style>" +
                "<style:style style:name=\"Heading_20_2\" style:display-name=\"Heading 2\" style:family=\"paragraph\" style:default-outline-level=\"2\"><style:paragraph-properties fo:margin-top=\"0.4cm\" fo:margin-bottom=\"0.2cm\"/><style:text-properties fo:font-size=\"14pt\" fo:font-weight=\"bold\"/></style:style>" +
                "<style:style style:name=\"TableContents\" style:family=\"paragraph\"><style:text-properties fo:font-size=\"8.5pt\"/></style:style>" +
                "<style:style style:name=\"TableHeading\" style:family=\"paragraph\"><style:text-properties fo:font-size=\"8.5pt\" fo:font-weight=\"bold\"/></style:style>" +
                "</office:styles><office:automatic-styles><style:page-layout style:name=\"pm1\"><style:page-layout-properties fo:page-width=\"29.7cm\" fo:page-height=\"21cm\" style:print-orientation=\"landscape\" fo:margin-top=\"1.5cm\" fo:margin-bottom=\"1.5cm\" fo:margin-left=\"1.5cm\" fo:margin-right=\"1.5cm\"/></style:page-layout></office:automatic-styles><office:master-styles><style:master-page style:name=\"Standard\" style:page-layout-name=\"pm1\"/></office:master-styles></office:document-styles>");
            z.add_text ("content.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-content %s office:version=\"1.2\"><office:automatic-styles><style:style style:name=\"Table\" style:family=\"table\"><style:table-properties style:width=\"26.7cm\" table:align=\"margins\"/></style:style><style:style style:name=\"Cell\" style:family=\"table-cell\"><style:table-cell-properties fo:padding=\"0.08cm\" fo:border=\"0.5pt solid #b8bcc4\"/></style:style></office:automatic-styles><office:body><office:text>\n%s</office:text></office:body></office:document-content>".printf (ns, body.str));
            var inner = zip.finish ();
            var reader = new ZipReader (inner);
            foreach (var name in reader.names ()) z.add (name, reader.read (name), false);
            return z.finish ();
        }
    }
}
