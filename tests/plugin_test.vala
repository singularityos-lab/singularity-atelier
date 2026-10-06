using Singularity.Apps.Atelier;
using Singularity.Apps.Atelier.Test;

int main () {
    var host = PluginHost.get_default ();
    check (host.loaded.contains ("atelier-cut-list"), "sample plugin loaded (%s)".printf (string.joinv (",", host.loaded.to_array ())));
    var p = Project.create ("fashion");
    p.pattern.pieces[0].name = "Front, \"left\"";
    var ex = host.find_exporter ("cut-list");
    check (ex != null, "exporter found");
    if (ex != null) {
        check (ex.title == "Cut List (CSV)" && ex.suffix == "csv", "exporter metadata");
        try {
            string csv = (string) ex.export (NativeFormat.to_json (p));
            string[] lines = csv.strip ().split ("\n");
            check (lines[0] == "piece,code,material,quantity,pair,on_fold", "cut list header");
            check (lines.length == p.pattern.pieces.size + 1, "one row per piece");
            check (lines[1].has_prefix ("\"Front, \"\"left\"\"\","), "names with commas and quotes are quoted: " + lines[1]);
            check (csv.contains ("Sleeve,03,fabric,2,yes,no"), "pair and quantity columns: " + csv);
        } catch (Error e) {
            check (false, e.message);
        }
    }
    check (host.rule_providers.size == 1, "grade rule provider found");
    if (host.rule_providers.size == 1) {
        var provider = host.rule_providers[0];
        check (provider.id == "company-rules" && provider.title == "Example Company Rules", "grade rule provider metadata");
        try {
            Aama.import_rules (provider.rules (host.pattern_json (p.pattern)), p.pattern);
            var r = p.pattern.rules.find (900);
            check (r != null && near (r.step ("40").x, 5), "company rule imported from the plugin");
        } catch (Error e) {
            check (false, e.message);
        }
    }
    return finish ("plugin");
}
