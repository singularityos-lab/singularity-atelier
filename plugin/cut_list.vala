public class AtelierCutList : Object, AtelierPlugin.Exporter {
    public string id { owned get { return "cut-list"; } }
    public string title { owned get { return _("Cut List (CSV)"); } }
    public string suffix { owned get { return "csv"; } }

    private static string cell (string text) {
        if (text.contains (",") || text.contains ("\"") || text.contains ("\n")) return "\"" + text.replace ("\"", "\"\"") + "\"";
        return text;
    }

    public uint8[] export (string project_json) throws Error {
        var parser = new Json.Parser ();
        parser.load_from_data (project_json);
        var pieces = parser.get_root ().get_object ().get_object_member ("pattern").get_array_member ("pieces");
        var sb = new StringBuilder ("piece,code,material,quantity,pair,on_fold\n");
        foreach (var n in pieces.get_elements ()) {
            var o = n.get_object ();
            sb.append_printf ("%s,%s,%s,%lld,%s,%s\n", cell (o.get_string_member_with_default ("name", "")), cell (o.get_string_member_with_default ("code", "")),
                cell (o.get_string_member_with_default ("material", "")), o.get_int_member_with_default ("quantity", 1),
                o.get_boolean_member_with_default ("pair", false) ? "yes" : "no", o.get_boolean_member_with_default ("on_fold", false) ? "yes" : "no");
        }
        return sb.str.data;
    }
}

public class AtelierCompanyRules : Object, AtelierPlugin.GradeRuleProvider {
    public string id { owned get { return "company-rules"; } }
    public string title { owned get { return _("Example Company Rules"); } }

    public string rules (string pattern_json) throws Error {
        var parser = new Json.Parser ();
        parser.load_from_data (pattern_json);
        var sizes = parser.get_root ().get_object ().get_array_member ("sizes");
        var sb = new StringBuilder ("ASTM/D6673/RUL\nUNITS: METRIC\nSIZE LIST:");
        foreach (var s in sizes.get_elements ()) sb.append (" " + s.get_string ());
        sb.append ("\nRULE: DELTA 900\n");
        for (uint i = 0; i < sizes.get_length (); i++) sb.append (i == 0 ? "0,0" : " 5,0");
        sb.append ("\nEND\n");
        return sb.str;
    }
}

[ModuleInit]
public void peas_register_types (TypeModule module) {
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type (typeof (AtelierPlugin.Exporter), typeof (AtelierCutList));
    objmodule.register_extension_type (typeof (AtelierPlugin.GradeRuleProvider), typeof (AtelierCompanyRules));
}
