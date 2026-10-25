import Base
import ../src/json.bend as J
import ../src/fmt/toon.bend as T

# Ground equations for the TOON adapter (the codec itself is bend-toon's,
# 389/389 on the spec's conformance suite).

def e(js: String) -> String:
  T.emit(J.unwrap(J.parse(js)))

def p(ts: String) -> String:
  J.emit(J.unwrap(T.parse(ts)))

def t_obj() -> {e("{\"id\":1,\"name\":\"Ada\"}") == "id: 1\nname: Ada" : String}:
  {==}

def t_table() -> {e("{\"users\":[{\"id\":1,\"name\":\"Alice\",\"role\":\"admin\"},{\"id\":2,\"name\":\"Bob\",\"role\":\"user\"}]}") == "users[2]{id,name,role}:\n  1,Alice,admin\n  2,Bob,user" : String}:
  {==}

def t_primitives() -> {e("{\"tags\":[\"a\",\"b\"],\"ok\":true,\"n\":null}") == "tags[2]: a,b\nok: true\nn: null" : String}:
  {==}

def t_quote() -> {e("{\"s\":\"a,b\",\"t\":\"true\",\"e\":\"\"}") == "s: \"a,b\"\nt: \"true\"\ne: \"\"" : String}:
  {==}

def t_decode() -> {p("users[2]{id,name}:\n  1,Alice\n  2,Bob\ncount: 2") == "{\"users\":[{\"id\":1,\"name\":\"Alice\"},{\"id\":2,\"name\":\"Bob\"}],\"count\":2}" : String}:
  {==}

def t_bad() -> {J.emit(J.unwrap(T.parse("a[2]: 1"))) == "null" : String}:
  {==}

def doc() -> String:
  "{\"schemaVersion\":1,\"accounts\":[{\"number\":1,\"email\":\"a@x.test\",\"active\":true,\"usage\":null},{\"number\":2,\"email\":\"b@x.test\",\"active\":false,\"usage\":{\"pct\":20.5}}],\"k\":\"a\\nb\"}"

def rt() -> {T.parse(T.emit(J.unwrap(J.parse(doc())))) == Done{J.unwrap(J.parse(doc()))} : Result<&2, &2, String, J.Json>}:
  {==}

# TOON writes numbers in canonical form (spec section 2): 20.0 is 20.
def t_canonical_number() -> {e("{\"pct\":20.0,\"x\":1e3}") == "pct: 20\nx: 1000" : String}:
  {==}

# ---- law: awkward strings read back as written, as a value, a field and an item (parse(emit(v)) == v) --

def tricky() -> List<&2, String>:
  ["", " ", "a b", "a,b", "a|b", "a\tb", "- x", "x: y", "x:", "#x", "[a]", "{a}", "\"q\"", "'q'", "null", "true", "false", "1", "-1", "1.5", "1e3", "007", "0x1F", "é", "日本語",
   "a\nb", "a\\b", " lead", "trail ", "-", "key: value", "2026-10-24T05:11:30Z", "a@b.test", "http://x.test/a?b=c#d"]

def str_back(r: Result<&2, &2, String, J.Json>, +s: String) -> Bool:
  match r:
    case Done{J.JStr{t}}:
      String.eq(s, t)
    case _:
      False{}

def field_back(r: Result<&2, &2, String, J.Json>, +s: String) -> Bool:
  match r:
    case Done{J.JObj{J.JField{k, J.JStr{t}, J.JNil{}}}}:
      String.eq(k, "k") && String.eq(s, t)
    case _:
      False{}

def item_back(r: Result<&2, &2, String, J.Json>, +s: String) -> Bool:
  match r:
    case Done{J.JArr{J.JCons{J.JStr{t}, J.JCons{J.JNum{n}, J.JNil{}}}}}:
      String.eq(s, t) && String.eq(n, "2")
    case _:
      False{}

def rt_one(+s: String) -> Bool:
  str_back(T.parse(T.emit(J.JStr{s})), s) && field_back(T.parse(T.emit(J.JObj{J.JField{"k", J.JStr{s}, J.JNil{}}})), s) && item_back(T.parse(T.emit(J.JArr{J.JCons{J.JStr{s}, J.JCons{J.JNum{"2"}, J.JNil{}}}})), s)

def rt_all(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      rt_one(h) && rt_all(t)

def law_strings_round_trip() -> {rt_all(tricky()) == True{} : Bool}:
  {==}
