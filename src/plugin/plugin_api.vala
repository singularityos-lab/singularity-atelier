namespace AtelierPlugin {

    public interface Exporter : Object {
        public abstract string id { owned get; }
        public abstract string title { owned get; }
        public abstract string suffix { owned get; }
        public abstract uint8[] export (string project_json) throws Error;
    }

    public interface GradeRuleProvider : Object {
        public abstract string id { owned get; }
        public abstract string title { owned get; }
        public abstract string rules (string pattern_json) throws Error;
    }
}
