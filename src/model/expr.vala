namespace Singularity.Apps.Atelier {

    public errordomain ExprError {
        SYNTAX,
        UNKNOWN,
        MATH
    }

    public delegate bool VariableLookup (string name, out double value);

    public class Expr {
        private enum Kind {
            NUMBER,
            VARIABLE,
            UNARY,
            BINARY,
            CALL,
            TERNARY
        }

        private Kind kind;
        private double number;
        private string name = "";
        private char op;
        private Expr? left;
        private Expr? right;
        private Expr? third;
        private Gee.ArrayList<Expr> args;

        private Expr (Kind kind) {
            this.kind = kind;
        }

        public static Expr parse (string text) throws ExprError {
            var p = new Parser (text);
            var e = p.parse_ternary ();
            p.skip_ws ();
            if (!p.at_end ()) throw new ExprError.SYNTAX ("Unexpected \"%s\"".printf (p.rest ()));
            return e;
        }

        public static double evaluate (string text, VariableLookup lookup) throws ExprError {
            string t = text.strip ();
            if (t == "") return 0;
            double quick;
            if (double.try_parse (t, out quick)) return quick;
            return parse (t).eval (lookup);
        }

        public void collect_names (Gee.Collection<string> names) {
            switch (kind) {
                case Kind.VARIABLE:
                    names.add (name);
                    break;
                case Kind.UNARY:
                    left.collect_names (names);
                    break;
                case Kind.BINARY:
                    left.collect_names (names);
                    right.collect_names (names);
                    break;
                case Kind.TERNARY:
                    left.collect_names (names);
                    right.collect_names (names);
                    third.collect_names (names);
                    break;
                case Kind.CALL:
                    foreach (var a in args) a.collect_names (names);
                    break;
                default:
                    break;
            }
        }

        public double eval (VariableLookup lookup) throws ExprError {
            switch (kind) {
                case Kind.NUMBER:
                    return number;
                case Kind.VARIABLE: {
                    double v;
                    if (lookup (name, out v)) return v;
                    if (name == "pi" || name == "M_PI") return Math.PI;
                    if (name == "e" || name == "M_E") return Math.E;
                    throw new ExprError.UNKNOWN ("Unknown name \"%s\"".printf (name));
                }
                case Kind.UNARY: {
                    double v = left.eval (lookup);
                    if (op == '!') return v == 0 ? 1 : 0;
                    return op == '-' ? -v : v;
                }
                case Kind.TERNARY:
                    return left.eval (lookup) != 0 ? right.eval (lookup) : third.eval (lookup);
                case Kind.BINARY: {
                    double a = left.eval (lookup);
                    double b = right.eval (lookup);
                    switch (op) {
                        case '+': return a + b;
                        case '-': return a - b;
                        case '*': return a * b;
                        case '/':
                            if (b == 0) throw new ExprError.MATH ("Division by zero");
                            return a / b;
                        case '%':
                            if (b == 0) throw new ExprError.MATH ("Division by zero");
                            return Math.fmod (a, b);
                        case '^': return Math.pow (a, b);
                        case '<': return a < b ? 1 : 0;
                        case '>': return a > b ? 1 : 0;
                        case 'l': return a <= b ? 1 : 0;
                        case 'g': return a >= b ? 1 : 0;
                        case '=': return a == b ? 1 : 0;
                        case 'n': return a != b ? 1 : 0;
                        case '&': return (a != 0 && b != 0) ? 1 : 0;
                        case '|': return (a != 0 || b != 0) ? 1 : 0;
                        default: throw new ExprError.SYNTAX ("Bad operator");
                    }
                }
                case Kind.CALL:
                    return call (lookup);
            }
            return 0;
        }

        private double arg (int i, VariableLookup lookup) throws ExprError {
            if (i >= args.size) throw new ExprError.SYNTAX ("%s needs more arguments".printf (name));
            return args[i].eval (lookup);
        }

        private double call (VariableLookup lookup) throws ExprError {
            double d2r = Math.PI / 180;
            switch (name) {
                case "sqrt": return Math.sqrt (arg (0, lookup));
                case "abs": case "fabs": return arg (0, lookup).abs ();
                case "min": {
                    double m = arg (0, lookup);
                    for (int i = 1; i < args.size; i++) m = double.min (m, arg (i, lookup));
                    return m;
                }
                case "max": {
                    double m = arg (0, lookup);
                    for (int i = 1; i < args.size; i++) m = double.max (m, arg (i, lookup));
                    return m;
                }
                case "sum": {
                    double s = 0;
                    for (int i = 0; i < args.size; i++) s += arg (i, lookup);
                    return s;
                }
                case "avg": {
                    double s = 0;
                    for (int i = 0; i < args.size; i++) s += arg (i, lookup);
                    return args.size > 0 ? s / args.size : 0;
                }
                case "round": return Math.round (arg (0, lookup));
                case "floor": return Math.floor (arg (0, lookup));
                case "ceil": return Math.ceil (arg (0, lookup));
                case "pow": return Math.pow (arg (0, lookup), arg (1, lookup));
                case "exp": return Math.exp (arg (0, lookup));
                case "ln": case "log": return Math.log (arg (0, lookup));
                case "log10": return Math.log10 (arg (0, lookup));
                case "sin": return Math.sin (arg (0, lookup));
                case "cos": return Math.cos (arg (0, lookup));
                case "tan": return Math.tan (arg (0, lookup));
                case "asin": return Math.asin (arg (0, lookup));
                case "acos": return Math.acos (arg (0, lookup));
                case "atan": return Math.atan (arg (0, lookup));
                case "atan2": return Math.atan2 (arg (0, lookup), arg (1, lookup));
                case "sinD": return Math.sin (arg (0, lookup) * d2r);
                case "cosD": return Math.cos (arg (0, lookup) * d2r);
                case "tanD": return Math.tan (arg (0, lookup) * d2r);
                case "asinD": return Math.asin (arg (0, lookup)) / d2r;
                case "acosD": return Math.acos (arg (0, lookup)) / d2r;
                case "atanD": return Math.atan (arg (0, lookup)) / d2r;
                case "degTorad": case "rad": return arg (0, lookup) * d2r;
                case "radTodeg": case "deg": return arg (0, lookup) / d2r;
                case "sign": {
                    double v = arg (0, lookup);
                    return v > 0 ? 1 : (v < 0 ? -1 : 0);
                }
                case "if": return arg (0, lookup) != 0 ? arg (1, lookup) : arg (2, lookup);
                default: throw new ExprError.UNKNOWN ("Unknown function \"%s\"".printf (name));
            }
        }

        private class Parser {
            private string src;
            private int pos;

            public Parser (string s) {
                src = s;
                pos = 0;
            }

            public bool at_end () {
                return pos >= src.length;
            }

            public string rest () {
                return src.substring (pos);
            }

            public void skip_ws () {
                while (pos < src.length && src[pos].isspace ()) pos++;
            }

            private char peek () {
                skip_ws ();
                return pos < src.length ? src[pos] : 0;
            }

            private bool accept (string s) {
                skip_ws ();
                if (src.substring (pos).has_prefix (s)) {
                    pos += s.length;
                    return true;
                }
                return false;
            }

            public Expr parse_ternary () throws ExprError {
                var c = parse_or ();
                if (accept ("?")) {
                    var a = parse_ternary ();
                    if (!accept (":")) throw new ExprError.SYNTAX ("Missing \":\"");
                    var b = parse_ternary ();
                    var e = new Expr (Kind.TERNARY);
                    e.left = c;
                    e.right = a;
                    e.third = b;
                    return e;
                }
                return c;
            }

            private Expr bin (char op, Expr l, Expr r) {
                var e = new Expr (Kind.BINARY);
                e.op = op;
                e.left = l;
                e.right = r;
                return e;
            }

            private Expr parse_or () throws ExprError {
                var l = parse_and ();
                while (accept ("||")) l = bin ('|', l, parse_and ());
                return l;
            }

            private Expr parse_and () throws ExprError {
                var l = parse_cmp ();
                while (accept ("&&")) l = bin ('&', l, parse_cmp ());
                return l;
            }

            private Expr parse_cmp () throws ExprError {
                var l = parse_add ();
                while (true) {
                    if (accept ("<=")) l = bin ('l', l, parse_add ());
                    else if (accept (">=")) l = bin ('g', l, parse_add ());
                    else if (accept ("==")) l = bin ('=', l, parse_add ());
                    else if (accept ("!=")) l = bin ('n', l, parse_add ());
                    else if (accept ("<")) l = bin ('<', l, parse_add ());
                    else if (accept (">")) l = bin ('>', l, parse_add ());
                    else break;
                }
                return l;
            }

            private Expr parse_add () throws ExprError {
                var l = parse_mul ();
                while (true) {
                    char c = peek ();
                    if (c == '+' || c == '-') {
                        pos++;
                        l = bin (c, l, parse_mul ());
                    } else {
                        break;
                    }
                }
                return l;
            }

            private Expr parse_mul () throws ExprError {
                var l = parse_unary ();
                while (true) {
                    char c = peek ();
                    if (c == '*' || c == '/' || c == '%') {
                        pos++;
                        l = bin (c, l, parse_unary ());
                    } else {
                        break;
                    }
                }
                return l;
            }

            private Expr parse_unary () throws ExprError {
                char c = peek ();
                if (c == '-' || c == '+' || (c == '!' && !(pos + 1 < src.length && src[pos + 1] == '='))) {
                    pos++;
                    var e = new Expr (Kind.UNARY);
                    e.op = c;
                    e.left = parse_unary ();
                    return e;
                }
                return parse_pow ();
            }

            private Expr parse_pow () throws ExprError {
                var b = parse_primary ();
                if (peek () == '^') {
                    pos++;
                    return bin ('^', b, parse_unary ());
                }
                return b;
            }

            private static bool ident_start (char c) {
                return c.isalpha () || c == '_' || c == '#' || c == '@' || (uint8) c >= 0x80;
            }

            private static bool ident_char (char c) {
                return c.isalnum () || c == '_' || c == '#' || c == '@' || c == '.' || (uint8) c >= 0x80;
            }

            private Expr parse_primary () throws ExprError {
                char c = peek ();
                if (c == 0) throw new ExprError.SYNTAX ("Unexpected end of formula");
                if (c == '(') {
                    pos++;
                    var e = parse_ternary ();
                    if (!accept (")")) throw new ExprError.SYNTAX ("Missing \")\"");
                    return e;
                }
                if (c.isdigit () || c == '.') {
                    int start = pos;
                    while (pos < src.length && (src[pos].isdigit () || src[pos] == '.')) pos++;
                    if (pos < src.length && (src[pos] == 'e' || src[pos] == 'E')) {
                        int save = pos;
                        pos++;
                        if (pos < src.length && (src[pos] == '+' || src[pos] == '-')) pos++;
                        if (pos < src.length && src[pos].isdigit ()) {
                            while (pos < src.length && src[pos].isdigit ()) pos++;
                        } else {
                            pos = save;
                        }
                    }
                    var e = new Expr (Kind.NUMBER);
                    double v;
                    if (!double.try_parse (src.substring (start, pos - start), out v)) throw new ExprError.SYNTAX ("Bad number");
                    e.number = v;
                    return e;
                }
                if (ident_start (c)) {
                    int start = pos;
                    while (pos < src.length && ident_char (src[pos])) pos++;
                    string id = src.substring (start, pos - start);
                    if (peek () == '(') {
                        pos++;
                        var e = new Expr (Kind.CALL);
                        e.name = id;
                        e.args = new Gee.ArrayList<Expr> ();
                        if (!accept (")")) {
                            do {
                                e.args.add (parse_ternary ());
                            } while (accept (",") || accept (";"));
                            if (!accept (")")) throw new ExprError.SYNTAX ("Missing \")\"");
                        }
                        return e;
                    }
                    var v = new Expr (Kind.VARIABLE);
                    v.name = id;
                    return v;
                }
                throw new ExprError.SYNTAX ("Unexpected \"%c\"".printf (c));
            }
        }
    }
}
