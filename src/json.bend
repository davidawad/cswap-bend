import Base
import ./json/lex.bend as Lex
import ./json/quote.bend as Quote
import ./json/scan.bend as Scan

# JSON values, a parser and emitters that match Python's json module.
#
# Arrays and objects are chains inside Json itself (JNil, JCons, JField), not
# `List`s: Bend accepts structural recursion over one type only, and a value
# nested in a list would need two mutually recursive emitters. A chain keeps
# the emitter a single self-recursive def. Json is Data (reusable), which a
# `List<(String & Json)>` of pairs could not be. `arr`, `obj`, `to_pairs` and
# `of_pairs` convert at the edge.
#
# Numbers stay their source text, so `90.0` and `1e5` round-trip unchanged.

type Json is Data:
  JNull{}
  JBool{b: Bool}
  JNum{text: String}
  JStr{s: String}
  JArr{items: Json}
  JObj{fields: Json}
  JNil{}
  JCons{head: Json, tail: Json}
  JField{key: String, val: Json, tail: Json}

# ---- parser ------------------------------------------------------------------

type Mode is Data:
  MVal{}
  MAFirst{}
  MANext{}
  MAAfter{}
  MOFirst{}
  MONext{}
  MOAfter{}

def only(t: List<&2, Lex.Tok>, v: Json) -> Result<&2, &2, String, Json>:
  match t:
    case Nil{}:
      Done{v}
    case Con{h, r}:
      Fail{"trailing data after the value"}

def wrap.arr(ok: Bool, r: Result<&2, &2, String, Json>) -> Result<&2, &2, String, Json>:
  match ok r:
    case True{} Done{items}:
      Done{JArr{items}}
    case True{} Fail{e}:
      Fail{e}
    case False{} _:
      Fail{"unclosed array"}

def wrap.obj(ok: Bool, r: Result<&2, &2, String, Json>) -> Result<&2, &2, String, Json>:
  match ok r:
    case True{} Done{fields}:
      Done{JObj{fields}}
    case True{} Fail{e}:
      Fail{e}
    case False{} _:
      Fail{"unclosed object"}

def item.cons(x: Result<&2, &2, String, Json>, rest: Result<&2, &2, String, Json>) -> Result<&2, &2, String, Json>:
  match x rest:
    case Done{a} Done{b}:
      Done{JCons{a, b}}
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

def field.cons(k: String, x: Result<&2, &2, String, Json>, rest: Result<&2, &2, String, Json>) -> Result<&2, &2, String, Json>:
  match x rest:
    case Done{a} Done{b}:
      Done{JField{k, a, b}}
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

# What one parser step decides, before it recurses: a finished result, a
# bracketed body, two parts to parse (array item and rest, object field and
# rest), or one more step in another mode. Splitting "decide" from "recurse"
# keeps `val` a single self-recursive def (Bend has no mutual recursion) with
# few arms.
type Plan is Data:
  PRes{r: Result<&2, &2, String, Json>}
  PArr{t: List<&2, Lex.Tok>}
  PObj{t: List<&2, Lex.Tok>}
  PItems{first: List<&2, Lex.Tok>, rest: List<&2, Lex.Tok>}
  PFields{k: String, vt: List<&2, Lex.Tok>, rest: List<&2, Lex.Tok>}
  PNext{mode: Mode, t: List<&2, Lex.Tok>}

def plan.val(+toks: List<&2, Lex.Tok>) -> Plan:
  match toks:
    case Con{Lex.TNull{}, t}:
      PRes{only(t, JNull{})}
    case Con{Lex.TTrue{}, t}:
      PRes{only(t, JBool{True{}})}
    case Con{Lex.TFalse{}, t}:
      PRes{only(t, JBool{False{}})}
    case Con{Lex.TNum{x}, t}:
      PRes{only(t, JNum{x})}
    case Con{Lex.TStr{x}, t}:
      PRes{only(t, JStr{x})}
    case Con{Lex.TLBrack{}, +t}:
      PArr{t}
    case Con{Lex.TLBrace{}, +t}:
      PObj{t}
    case Nil{}:
      PRes{Fail{"unexpected end of input"}}
    case _:
      PRes{Fail{"unexpected token"}}

def plan.items(+toks: List<&2, Lex.Tok>) -> Plan:
  match toks:
    case Nil{}:
      PRes{Fail{"unexpected end of input"}}
    case Con{+h, +t}:
      PItems{List.take(&2, Lex.Tok, Con{h, t}, Scan.scan(Con{h, t}, 0)), List.drop(&2, Lex.Tok, Con{h, t}, Scan.scan(Con{h, t}, 0))}

def plan.arr_first(+toks: List<&2, Lex.Tok>) -> Plan:
  match toks:
    case Nil{}:
      PRes{Done{JNil{}}}
    case _:
      plan.items(toks)

def plan.arr_next(+toks: List<&2, Lex.Tok>) -> Plan:
  match toks:
    case Nil{}:
      PRes{Fail{"trailing comma in array"}}
    case _:
      plan.items(toks)

def plan.arr_after(+toks: List<&2, Lex.Tok>) -> Plan:
  match toks:
    case Nil{}:
      PRes{Done{JNil{}}}
    case Con{Lex.TComma{}, t}:
      PNext{MANext{}, t}
    case _:
      PRes{Fail{"expected , or ] in array"}}

def plan.field(k: String, +t: List<&2, Lex.Tok>) -> Plan:
  PFields{k, List.take(&2, Lex.Tok, t, Scan.scan(t, 0)), List.drop(&2, Lex.Tok, t, Scan.scan(t, 0))}

def plan.obj_first(+toks: List<&2, Lex.Tok>) -> Plan:
  match toks:
    case Nil{}:
      PRes{Done{JNil{}}}
    case Con{Lex.TStr{k}, Con{Lex.TColon{}, +t}}:
      plan.field(k, t)
    case _:
      PRes{Fail{"expected a string key and :"}}

def plan.obj_next(+toks: List<&2, Lex.Tok>) -> Plan:
  match toks:
    case Nil{}:
      PRes{Fail{"trailing comma in object"}}
    case Con{Lex.TStr{k}, Con{Lex.TColon{}, +t}}:
      plan.field(k, t)
    case _:
      PRes{Fail{"expected a string key and :"}}

def plan.obj_after(+toks: List<&2, Lex.Tok>) -> Plan:
  match toks:
    case Nil{}:
      PRes{Done{JNil{}}}
    case Con{Lex.TComma{}, t}:
      PNext{MONext{}, t}
    case _:
      PRes{Fail{"expected , or } in object"}}

def plan(mode: Mode, +toks: List<&2, Lex.Tok>) -> Plan:
  match mode:
    case MVal{}:
      plan.val(toks)
    case MAFirst{}:
      plan.arr_first(toks)
    case MANext{}:
      plan.arr_next(toks)
    case MAAfter{}:
      plan.arr_after(toks)
    case MOFirst{}:
      plan.obj_first(toks)
    case MONext{}:
      plan.obj_next(toks)
    case MOAfter{}:
      plan.obj_after(toks)

def body(+t: List<&2, Lex.Tok>) -> List<&2, Lex.Tok>:
  List.take(&2, Lex.Tok, t, Nat.sub(List.length(&2, Lex.Tok, t), 1n))

# One def for values, array items and object fields: `plan` says which step
# this is. `fuel` bounds the work (3 * tokens + 5). An item's tokens are those
# up to the next comma or closer at depth 0.
def val(fuel: Nat, pl: Plan) -> Result<&2, &2, String, Json>:
  match fuel pl:
    case 0n _:
      Fail{"nesting too deep"}
    case 1n++p PRes{r}:
      r
    case 1n++p PArr{+t}:
      wrap.arr(Scan.closed_by(t, 22), val(p, plan(MAFirst{}, body(t))))
    case 1n++p PObj{+t}:
      wrap.obj(Scan.closed_by(t, 21), val(p, plan(MOFirst{}, body(t))))
    case 1n++p PItems{f, r}:
      item.cons(val(p, plan(MVal{}, f)), val(p, plan(MAAfter{}, r)))
    case 1n++p PFields{k, vt, r}:
      field.cons(k, val(p, plan(MVal{}, vt)), val(p, plan(MOAfter{}, r)))
    case 1n++p PNext{m, t}:
      val(p, plan(m, t))

def parse.pick(msg: String, r: Result<&2, &2, String, Json>) -> Result<&2, &2, String, Json>:
  match msg r:
    case SNil{} _:
      r
    case _ _:
      Fail{msg}

def parse.toks(+toks: List<&2, Lex.Tok>) -> Result<&2, &2, String, Json>:
  parse.pick(Scan.err.of(toks), val(Nat.add(Nat.mul(3n, List.length(&2, Lex.Tok, toks)), 5n), plan(MVal{}, toks)))

# Parse JSON text; Fail carries a message.
def parse(+s: String) -> Result<&2, &2, String, Json>:
  parse.toks(Lex.lex(String.length(s), s))

# ---- emitters ----------------------------------------------------------------

def sep.of(next: Json, +style: U32, d: Nat) -> String:
  match next:
    case JNil{}:
      ""
    case _:
      Quote.sep(style, d)

def bool.show(b: Bool) -> String:
  Lex.sel.s(b, "true", "false")

# A bracketed body: `[]` or `{}` when empty, else the body on its own lines.
def emit.wrap(open: String, close: String, items: Json, inner: String, +style: U32, +d: Nat) -> String:
  match items:
    case JNil{}:
      open ++ close
    case _:
      open ++ Quote.nl(style, Nat.add(d, 1n)) ++ inner ++ Quote.nl(style, d) ++ close

# The emitter. `j` shrinks on every call; `d` is the nesting depth.
def emit.go(j: Json, +style: U32, +ascii: Bool, +d: Nat) -> String:
  match j:
    case JNull{}:
      "null"
    case JBool{b}:
      bool.show(b)
    case JNum{t}:
      t
    case JStr{s}:
      Quote.quote(s, ascii)
    case JArr{+items}:
      emit.wrap("[", "]", items, emit.go(items, style, ascii, Nat.add(d, 1n)), style, d)
    case JObj{+fields}:
      emit.wrap("{", "}", fields, emit.go(fields, style, ascii, Nat.add(d, 1n)), style, d)
    case JNil{}:
      ""
    case JCons{h, +t}:
      emit.go(h, style, ascii, d) ++ sep.of(t, style, d) ++ emit.go(t, style, ascii, d)
    case JField{k, v, +t}:
      Quote.quote(k, ascii) ++ Quote.colon(style) ++ emit.go(v, style, ascii, d) ++ sep.of(t, style, d) ++ emit.go(t, style, ascii, d)

# Compact, no spaces, UTF-8 left as is.
def emit(j: Json) -> String:
  emit.go(j, 0, False{}, 0n)

# json.dumps(j): `, ` and `: ` separators, ensure_ascii.
def emit_py(j: Json) -> String:
  emit.go(j, 1, True{}, 0n)

# json.dumps(j, indent=2), as the reference writes sequence.json and
# settings: ensure_ascii on (the reference never passes ensure_ascii=False
# for its own files), no trailing newline.
def emit_pretty(j: Json) -> String:
  emit.go(j, 2, True{}, 0n)

# json.dumps(j, indent=2, ensure_ascii=False).
def emit_pretty_utf8(j: Json) -> String:
  emit.go(j, 2, False{}, 0n)

def field.pick(hit: Bool, v: Json, rest: Maybe<&2, Json>) -> Maybe<&2, Json>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

# ---- accessors and builders ----------------------------------------------------

def field.get(+key: String, fields: Json) -> Maybe<&2, Json>:
  match fields:
    case JField{k, v, t}:
      field.pick(String.eq(k, key), v, field.get(key, t))
    case _:
      None{}

# The value under `key` of an object; None for a missing key or a non-object.
def get(key: String, j: Json) -> Maybe<&2, Json>:
  match j:
    case JObj{fields}:
      field.get(key, fields)
    case _:
      None{}

def as_string(j: Json) -> Maybe<&2, String>:
  match j:
    case JStr{s}:
      Some{s}
    case _:
      None{}

def as_bool(j: Json) -> Maybe<&2, Bool>:
  match j:
    case JBool{b}:
      Some{b}
    case _:
      None{}

# A non-negative integer that fits U32; `5.0`, `-1` and `1e3` are None.
def as_u32(j: Json) -> Maybe<&2, U32>:
  match j:
    case JNum{t}:
      U32.read(t)
    case _:
      None{}

# Array of the values, in order.
def arr.chain(xs: List<&2, Json>) -> Json:
  match xs:
    case Nil{}:
      JNil{}
    case Con{h, t}:
      JCons{h, arr.chain(t)}

def arr(xs: List<&2, Json>) -> Json:
  JArr{arr.chain(xs)}

# The elements of an array; empty for any other value.
def items.list(items: Json) -> List<&2, Json>:
  match items:
    case JCons{h, t}:
      h <> items.list(t)
    case _:
      []

def to_list(j: Json) -> List<&2, Json>:
  match j:
    case JArr{items}:
      items.list(items)
    case _:
      []

def field.of(kv: String & Json, rest: Json) -> Json:
  (k, v) = kv
  JField{k, v, rest}

def obj.chain(kvs: List<(String & Json)>) -> Json:
  match kvs:
    case Nil{}:
      JNil{}
    case Con{kv, t}:
      field.of(kv, obj.chain(t))

# Object from ordered (key, value) pairs.
def of_pairs(kvs: List<(String & Json)>) -> Json:
  JObj{obj.chain(kvs)}

def pairs.list(fields: Json) -> List<(String & Json)>:
  match fields:
    case JField{k, v, t}:
      (k, v) <> pairs.list(t)
    case _:
      []

# The (key, value) pairs of an object, in file order.
def to_pairs(j: Json) -> List<(String & Json)>:
  match j:
    case JObj{fields}:
      pairs.list(fields)
    case _:
      []

def keys.list(fields: Json) -> List<&2, String>:
  match fields:
    case JField{k, v, t}:
      k <> keys.list(t)
    case _:
      []

def keys(j: Json) -> List<&2, String>:
  match j:
    case JObj{fields}:
      keys.list(fields)
    case _:
      []

def set.pick(hit: Bool, key: String, val: Json, v: Json, t: Json, rest: Json) -> Json:
  match hit:
    case True{}:
      JField{key, val, t}
    case False{}:
      JField{key, v, rest}

def set.go(+key: String, +val: Json, fields: Json) -> Json:
  match fields:
    case JField{+k, v, +t}:
      set.pick(String.eq(k, key), k, val, v, t, set.go(key, val, t))
    case _:
      JField{key, val, JNil{}}

# Replace the value under `key` in place, or append the field.
def set(+key: String, +val: Json, j: Json) -> Json:
  match j:
    case JObj{fields}:
      JObj{set.go(key, val, fields)}
    case _:
      j

def del.pick(hit: Bool, k: String, v: Json, t: Json, rest: Json) -> Json:
  match hit:
    case True{}:
      t
    case False{}:
      JField{k, v, rest}

def del.go(+key: String, fields: Json) -> Json:
  match fields:
    case JField{+k, v, +t}:
      del.pick(String.eq(k, key), k, v, t, del.go(key, t))
    case _:
      JNil{}

# The object without `key`.
def del(+key: String, j: Json) -> Json:
  match j:
    case JObj{fields}:
      JObj{del.go(key, fields)}
    case _:
      j

# The value of a parse that must have worked; JNull when it did not. For
# tests and constants, not for untrusted text.
def unwrap(+r: Result<&2, &2, String, Json>) -> Json:
  match r:
    case Done{v}:
      v
    case Fail{e}:
      JNull{}
