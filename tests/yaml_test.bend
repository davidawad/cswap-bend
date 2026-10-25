import Base
import ../src/json.bend as J
import ../src/fmt/yaml.bend as Y

# Ground equations for the YAML emitter and reader. `e(js)` emits the value of
# a JSON text; `rt(js)` is the round trip.

def e(js: String) -> String:
  Y.emit(J.unwrap(J.parse(js)))

def p(ys: String) -> String:
  J.emit(J.unwrap(Y.parse(ys)))

def fail_msg(r: Result<&2, &2, String, J.Json>) -> String:
  match r:
    case Fail{m}:
      m
    case Done{j}:
      "(parsed)"

def failed(ys: String) -> String:
  fail_msg(Y.parse(ys))

# ---- emitter: scalars --------------------------------------------------------------

def s_null() -> {e("null") == "null" : String}:
  {==}

def s_bool() -> {e("true") == "true" : String}:
  {==}

def s_num() -> {e("90.0") == "90.0" : String}:
  {==}

def s_plain() -> {e("\"hello world\"") == "hello world" : String}:
  {==}

def s_email() -> {e("\"owner@example.test's Organization\"") == "owner@example.test's Organization" : String}:
  {==}

def s_empty() -> {e("\"\"") == "\"\"" : String}:
  {==}

def s_word_true() -> {e("\"true\"") == "\"true\"" : String}:
  {==}

def s_word_null() -> {e("\"Null\"") == "\"Null\"" : String}:
  {==}

def s_word_yes() -> {e("\"yes\"") == "\"yes\"" : String}:
  {==}

def s_word_tilde() -> {e("\"~\"") == "\"~\"" : String}:
  {==}

def s_numlike() -> {e("\"123\"") == "\"123\"" : String}:
  {==}

def s_timestamp() -> {e("\"2026-10-24T05:11:30Z\"") == "\"2026-10-24T05:11:30Z\"" : String}:
  {==}

def s_colon_space() -> {e("\"a: b\"") == "\"a: b\"" : String}:
  {==}

def s_colon_inside() -> {e("\"http://x.test/a\"") == "http://x.test/a" : String}:
  {==}

def s_hash() -> {e("\"a #b\"") == "\"a #b\"" : String}:
  {==}

def s_hash_inside() -> {e("\"a#b\"") == "a#b" : String}:
  {==}

def s_lead_dash() -> {e("\"-x\"") == "\"-x\"" : String}:
  {==}

def s_lead_star() -> {e("\"*x\"") == "\"*x\"" : String}:
  {==}

def s_lead_space() -> {e("\" x\"") == "\" x\"" : String}:
  {==}

def s_trail_space() -> {e("\"x \"") == "\"x \"" : String}:
  {==}

def s_trail_colon() -> {e("\"x:\"") == "\"x:\"" : String}:
  {==}

def s_newline() -> {e("\"a\\nb\"") == "\"a\\nb\"" : String}:
  {==}

def s_quote() -> {e("\"say \\\"hi\\\"\"") == "say \"hi\"" : String}:
  {==}

def s_unicode() -> {e("\"caf\\u00e9\"") == "café" : String}:
  {==}

# ---- emitter: collections ------------------------------------------------------------

def c_empty_obj() -> {e("{}") == "{}" : String}:
  {==}

def c_empty_arr() -> {e("[]") == "[]" : String}:
  {==}

def c_map() -> {e("{\"a\":1,\"b\":\"x\"}") == "a: 1\nb: x" : String}:
  {==}

def c_nested_map() -> {e("{\"a\":{\"b\":{\"c\":1}},\"d\":2}") == "a:\n  b:\n    c: 1\nd: 2" : String}:
  {==}

def c_list() -> {e("[1,2,3]") == "- 1\n- 2\n- 3" : String}:
  {==}

def c_map_list() -> {e("{\"models\":[\"opus\",\"sonnet\"],\"n\":1}") == "models:\n  - opus\n  - sonnet\n\"n\": 1" : String}:
  {==}

def c_list_of_maps() -> {e("{\"accounts\":[{\"number\":1,\"email\":\"a@x.test\"},{\"number\":2,\"email\":\"b@x.test\"}]}") == "accounts:\n  - number: 1\n    email: a@x.test\n  - number: 2\n    email: b@x.test" : String}:
  {==}

def c_list_of_lists() -> {e("[[1,2],[3]]") == "- - 1\n  - 2\n- - 3" : String}:
  {==}

def c_item_with_nested() -> {e("[{\"a\":{\"b\":1},\"c\":[1]}]") == "- a:\n    b: 1\n  c:\n    - 1" : String}:
  {==}

def c_empty_values() -> {e("{\"a\":{},\"b\":[],\"c\":null}") == "a: {}\nb: []\nc: null" : String}:
  {==}

def c_numeric_key() -> {e("{\"1\":\"x\"}") == "\"1\": x" : String}:
  {==}

def c_event() -> {e("{\"schemaVersion\":1,\"event\":\"switch\",\"ts\":\"2026-10-24T05:11:30Z\",\"from\":{\"number\":1,\"email\":\"a@x.test\"},\"to\":null,\"warnings\":[],\"dryRun\":false}") == "schemaVersion: 1\nevent: switch\nts: \"2026-10-24T05:11:30Z\"\nfrom:\n  number: 1\n  email: a@x.test\nto: null\nwarnings: []\ndryRun: false" : String}:
  {==}

# ---- reader --------------------------------------------------------------------------

def r_map() -> {p("a: 1\nb: x\nc: true\nd: null\ne: \"1\"\n") == "{\"a\":1,\"b\":\"x\",\"c\":true,\"d\":null,\"e\":\"1\"}" : String}:
  {==}

def r_nested() -> {p("a:\n  b:\n    c: 1\nd: 2\n") == "{\"a\":{\"b\":{\"c\":1}},\"d\":2}" : String}:
  {==}

def r_list() -> {p("- 1\n- two\n- 3.5\n") == "[1,\"two\",3.5]" : String}:
  {==}

def r_map_list_indented() -> {p("models:\n  - opus\n  - sonnet\nn: 1\n") == "{\"models\":[\"opus\",\"sonnet\"],\"n\":1}" : String}:
  {==}

def r_map_list_flush() -> {p("models:\n- opus\n- sonnet\nn: 1\n") == "{\"models\":[\"opus\",\"sonnet\"],\"n\":1}" : String}:
  {==}

def r_list_of_maps() -> {p("- a: 1\n  b: 2\n- a: 3\n") == "[{\"a\":1,\"b\":2},{\"a\":3}]" : String}:
  {==}

def r_dash_spaces() -> {p("-   a: 1\n    b: 2\n") == "[{\"a\":1,\"b\":2}]" : String}:
  {==}

def r_nested_lists() -> {p("- - 1\n  - 2\n- - 3\n") == "[[1,2],[3]]" : String}:
  {==}

def r_empty_flow() -> {p("a: {}\nb: []\n") == "{\"a\":{},\"b\":[]}" : String}:
  {==}

def r_flow_seq() -> {p("models: [opus, \"son, net\", 3]\n") == "{\"models\":[\"opus\",\"son, net\",3]}" : String}:
  {==}

def r_flow_map() -> {p("m: {a: 1, b: x}\n") == "{\"m\":{\"a\":1,\"b\":\"x\"}}" : String}:
  {==}

def r_comments() -> {p("# top\na: 1 # trailing\n\n# mid\nb: \"x # y\"\nc:   # empty then\n  - 1\n") == "{\"a\":1,\"b\":\"x # y\",\"c\":[1]}" : String}:
  {==}

def r_doc_marker() -> {p("---\na: 1\n") == "{\"a\":1}" : String}:
  {==}

def r_single_quoted() -> {p("a: 'it''s'\nb: 'x: y'\n") == "{\"a\":\"it's\",\"b\":\"x: y\"}" : String}:
  {==}

def r_double_escapes() -> {p("a: \"l1\\nl2\\t\\u00e9\"\n") == "{\"a\":\"l1\\nl2\\té\"}" : String}:
  {==}

def r_quoted_key() -> {p("\"a: b\": 1\n'c': 2\n") == "{\"a: b\":1,\"c\":2}" : String}:
  {==}

def r_scalar_doc() -> {p("hello\n") == "\"hello\"" : String}:
  {==}

def r_empty_doc() -> {p("") == "null" : String}:
  {==}

def r_key_no_value() -> {p("a:\nb: 1\n") == "{\"a\":null,\"b\":1}" : String}:
  {==}

def r_url_value() -> {p("u: http://x.test/a\n") == "{\"u\":\"http://x.test/a\"}" : String}:
  {==}

def r_numbers() -> {p("a: -5\nb: 0\nc: 1.5e3\nd: 007\ne: 1.\nf: +1\n") == "{\"a\":-5,\"b\":0,\"c\":1.5e3,\"d\":\"007\",\"e\":\"1.\",\"f\":\"+1\"}" : String}:
  {==}

def r_bool_forms() -> {p("a: True\nb: FALSE\nc: yes\nd: Null\ne: ~\n") == "{\"a\":true,\"b\":false,\"c\":\"yes\",\"d\":null,\"e\":null}" : String}:
  {==}

# ---- reader: errors --------------------------------------------------------------------

def x_tab() -> {failed("a:\n\tb: 1\n") == "tabs are not allowed for indentation" : String}:
  {==}

def x_two_docs() -> {failed("a: 1\n---\nb: 2\n") == "several documents are not supported" : String}:
  {==}

def x_block_scalar() -> {failed("a: |\n  x\n") == "block scalars are not supported" : String}:
  {==}

def x_anchor() -> {failed("a: &x 1\n") == "anchors, aliases and tags are not supported" : String}:
  {==}

def x_indent_after_value() -> {failed("a: 1\n  b: 2\n") == "unexpected indented lines after the value of 'a'" : String}:
  {==}

def x_unterminated() -> {failed("a: \"x\n") == "unterminated quoted string" : String}:
  {==}

def x_after_quote() -> {failed("a: \"x\" y\n") == "unexpected text after a quoted string" : String}:
  {==}

def x_dedent() -> {failed("  a: 1\nb: 2\n") == "inconsistent indentation" : String}:
  {==}

def x_not_kv() -> {failed("a: 1\nfoo\n") == "expected 'key: value'" : String}:
  {==}

def x_not_dash() -> {failed("- 1\nfoo\n") == "expected '- ' to start a sequence item" : String}:
  {==}

# ---- round trips: parse(emit(v)) == v ----------------------------------------------------

def sc() -> String:
  "[null,true,false,0,-1,2.5,1e5,\"\",\"true\",\"123\",\"a: b\",\"x #y\",\"- z\",\" lead\",\"trail \",\"a\\nb\",\"q\\\"q\",\"é\",\"2026-10-24\",\"~\",\"null\",\"[x]\",\"{x}\",\"x:\"]"

def rt_scalars() -> {Y.parse(Y.emit(J.unwrap(J.parse(sc())))) == Done{J.unwrap(J.parse(sc()))} : Result<&2, &2, String, J.Json>}:
  {==}

def doc() -> String:
  "{\"schemaVersion\":1,\"accounts\":[{\"number\":1,\"email\":\"a@x.test\",\"usage\":{\"fiveHour\":{\"pct\":20.0,\"resetsAt\":\"2026-10-24T07:00:00+00:00\"},\"scoped\":[{\"name\":\"Opus\",\"pct\":30.0}]},\"flags\":[],\"x\":{}},{\"number\":2,\"email\":\"\",\"usage\":null}],\"nested\":[[1,[2,3]],[],{}],\"k: v\":\"a\\nb\"}"

def rt_doc() -> {Y.parse(Y.emit(J.unwrap(J.parse(doc())))) == Done{J.unwrap(J.parse(doc()))} : Result<&2, &2, String, J.Json>}:
  {==}


# ---- law over a corpus of awkward strings: parse(emit(v)) == v, as a value, a key and an item -------

def tricky() -> List<&2, String>:
  ["", " ", "a b", "- x", "-", "? x", ": x", "x: y", "x:", "#x", "x #y", "a#b", "'q'", "\"q\"", "[a]", "{a}", "a,b", "&a", "*a", "!a", "|", ">", "%a", "@a", "`a",
   "null", "Null", "NULL", "~", "true", "True", "TRUE", "false", "yes", "no", "on", "off", "y", "n", "Y", "N", "1", "-1", "1.5", "1e3", "0x1F", "007", ".5", ".inf", ".NaN",
   "2026-10-24", "2026-10-24T05:11:30Z", "12:30", "+1", "=", "<<", "é", "日本語", "a\nb", "a\tb", "a\\b", "a\"b", "a'b", "key: value # c", " lead", "trail ", "\u{1}", "\u{7f}",
   "http://x.test/a?b=c#d", "a@b.test", "owner@example.test's Organization", "~user", "...", "---", "- - -", "a: b: c"]

def str_back(r: Result<&2, &2, String, J.Json>, +s: String) -> Bool:
  match r:
    case Done{J.JStr{t}}:
      String.eq(s, t)
    case _:
      False{}

def key_back(r: Result<&2, &2, String, J.Json>, +s: String) -> Bool:
  match r:
    case Done{J.JObj{J.JField{k, J.JNum{n}, J.JNil{}}}}:
      String.eq(s, k) && String.eq(n, "1")
    case _:
      False{}

def item_back(r: Result<&2, &2, String, J.Json>, +s: String) -> Bool:
  match r:
    case Done{J.JArr{J.JCons{J.JStr{t}, J.JNil{}}}}:
      String.eq(s, t)
    case _:
      False{}

def rt_one(+s: String) -> Bool:
  str_back(Y.parse(Y.emit(J.JStr{s})), s) && key_back(Y.parse(Y.emit(J.JObj{J.JField{s, J.JNum{"1"}, J.JNil{}}})), s) && item_back(Y.parse(Y.emit(J.JArr{J.JCons{J.JStr{s}, J.JNil{}}})), s)

def rt_all(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      rt_one(h) && rt_all(t)

def law_strings_round_trip() -> {rt_all(tricky()) == True{} : Bool}:
  {==}
