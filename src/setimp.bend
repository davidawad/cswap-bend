import Base
import ./json.bend as Json
import ./setload.bend as Setload
import ./settings.bend as Settings
import ./setwrite.bend as Setwrite
import ./profile.bend as P
import ./policy/safe.bend as SF
import ./fmt/yaml.bend as Yaml
import ./fmt/toon.bend as Toon
import ./fmt/csv.bend as Csv
import ./fmt/ylex.bend as L
import ./fmt/yscal.bend as S

# The pure half of `config import` / `profile import`: the format of the input,
# the document it holds, the checks `config set` and `profile set` make on
# each known key (unknown keys pass through), and the merge into the settings
# already on disk. No effects.

def or_null(m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case Some{v}:
      v
    case None{}:
      Json.JNull{}

# ---- which format is the input? -------------------------------------------------------

def last_part(ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{h, Nil{}}:
      h
    case Con{h, Con{h2, t}}:
      last_part(Con{h2, t})

def ext_of2(ps: List<&2, String>) -> String:
  match ps:
    case Con{h, Con{h2, t}}:
      String.to_lower(last_part(Con{h2, t}))
    case _:
      ""

# The lower-case extension of a path ("" when there is none).
def ext_of(+path: String) -> String:
  ext_of2(String.split(path, '.'))

def known_name(+n: String) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, String.eq(n, "json"), Some{"json"},
  Bool.pick(Maybe<&2, String>, String.eq(n, "yaml") || String.eq(n, "yml"), Some{"yaml"},
  Bool.pick(Maybe<&2, String>, String.eq(n, "toon"), Some{"toon"},
  Bool.pick(Maybe<&2, String>, String.eq(n, "csv"), Some{"csv"}, None{}))))

def fmt.named(m: Maybe<&2, String>, +n: String) -> Result<&2, &2, String, String>:
  match m:
    case Some{f}:
      Done{f}
    case None{}:
      Fail{"unknown format '" ++ n ++ "' (json, yaml, toon, csv)"}

def fmt.ext(m: Maybe<&2, String>, +path: String) -> Result<&2, &2, String, String>:
  match m:
    case Some{f}:
      Done{f}
    case None{}:
      Fail{"cannot tell the format of '" ++ path ++ "' from its extension; pass --format json|yaml|toon|csv"}

# `--format NAME` when given, else the file's extension.
def pick_format(explicit: Maybe<&2, String>, +path: String) -> Result<&2, &2, String, String>:
  match explicit:
    case Some{+n}:
      fmt.named(known_name(n), n)
    case None{}:
      fmt.ext(known_name(ext_of(path)), path)

# ---- the document -----------------------------------------------------------------------

def set_path(ks: List<&2, String>, v: Json.Json, +j: Json.Json) -> Json.Json:
  match ks:
    case Nil{}:
      v
    case Con{+k, t}:
      Json.set(k, set_path(t, v, Setload.obj_or_empty(or_null(Json.get(k, j)))), j)

# A CSV cell as a value: `{}` and `[]` are the empty collections; everything
# else reads as a YAML plain word (null, true/false, a number, a string).
def typed(+v: String) -> Json.Json:
  Bool.pick(Json.Json, String.eq(v, "{}"), Json.JObj{Json.JNil{}},
  Bool.pick(Json.Json, String.eq(v, "[]"), Json.JArr{Json.JNil{}}, L.resolve(v)))

def csv_rows(rows: List<&2, List<&2, String>>, +doc: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match rows:
    case Nil{}:
      Done{doc}
    case Con{Con{k, Con{v, Nil{}}}, t}:
      csv_rows(t, set_path(String.split(k, '.'), typed(v), doc))
    case Con{r, t}:
      Fail{"every csv row must be key,value"}

def csv_head_ok(h: List<&2, String>) -> Bool:
  match h:
    case Con{a, Con{b, Nil{}}}:
      String.eq(a, "key") && String.eq(b, "value")
    case _:
      False{}

def csv_body(ok: Bool, t: List<&2, List<&2, String>>) -> Result<&2, &2, String, Json.Json>:
  match ok:
    case True{}:
      csv_rows(t, Setload.empty())
    case False{}:
      Fail{"a csv settings file starts with the header key,value"}

def csv_doc(rows: Result<&2, &2, String, List<&2, List<&2, String>>>) -> Result<&2, &2, String, Json.Json>:
  match rows:
    case Fail{e}:
      Fail{"csv: " ++ e}
    case Done{Con{h, t}}:
      csv_body(csv_head_ok(h), t)
    case Done{Nil{}}:
      Done{Setload.empty()}

def parse_named(+f: String, +text: String) -> Result<&2, &2, String, Json.Json>:
  Bool.pick(Result<&2, &2, String, Json.Json>, String.eq(f, "json"), Json.parse(text),
  Bool.pick(Result<&2, &2, String, Json.Json>, String.eq(f, "yaml"), Yaml.parse(text),
  Bool.pick(Result<&2, &2, String, Json.Json>, String.eq(f, "toon"), Toon.parse(text), csv_doc(Csv.parse(text)))))

def must_obj(r: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  match r:
    case Done{Json.JObj{f}}:
      Done{Json.JObj{f}}
    case Done{x}:
      Fail{"the settings document must be a mapping of keys to values"}
    case Fail{e}:
      Fail{e}

# The document in `text`, which is in format `f` (json, yaml, toon or csv).
def parse_doc(+f: String, +text: String) -> Result<&2, &2, String, Json.Json>:
  must_obj(parse_named(f, text))

# ---- checking the values ----------------------------------------------------------------------

def join_more(+s: String, r: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  match r:
    case Done{rest}:
      Done{s ++ "," ++ rest}
    case Fail{e}:
      Fail{e}

def list_text(items: Json.Json) -> Result<&2, &2, String, String>:
  match items:
    case Json.JNil{}:
      Done{""}
    case Json.JCons{Json.JStr{s}, Json.JNil{}}:
      Done{s}
    case Json.JCons{Json.JStr{s}, t}:
      join_more(s, list_text(t))
    case _:
      Fail{"expected a list of names"}

def scal_text(+j: Json.Json) -> Result<&2, &2, String, String>:
  match j:
    case Json.JStr{s}:
      Done{s}
    case Json.JNum{t}:
      Done{t}
    case Json.JBool{b}:
      Done{Json.bool.show(b)}
    case Json.JArr{items}:
      list_text(items)
    case _:
      Fail{"expected a single value"}

def parsed_json(p: Setwrite.Parsed) -> Result<&2, &2, String, Json.Json>:
  match p:
    case Setwrite.Bad{m}:
      Fail{m}
    case Setwrite.Good{j}:
      Done{j}

def known_val2(sp: Settings.Spec, r: Result<&2, &2, String, String>) -> Result<&2, &2, String, Json.Json>:
  match r:
    case Fail{e}:
      Fail{Settings.dotted(sp) ++ ": " ++ e}
    case Done{t}:
      parsed_json(Setwrite.parse_value(sp, t))

# A value of a known setting, checked as `config set` checks it (null stays null: unset).
def known_val(sp: Settings.Spec, +v: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match v:
    case Json.JNull{}:
      Done{Json.JNull{}}
    case _:
      known_val2(sp, scal_text(v))

def sec_val(m: Maybe<&2, Settings.Spec>, +v: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match m:
    case None{}:
      Done{v}
    case Some{sp}:
      known_val(sp, v)

def sec_fields(+sec: String, fields: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match fields:
    case Json.JField{+k, v, t}:
      S.field.cons(k, sec_val(Settings.find(sec ++ "." ++ k, Settings.specs()), v), sec_fields(sec, t))
    case _:
      Done{fields}

def sec_obj(+sec: String, +v: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match v:
    case Json.JObj{f}:
      S.wrap.obj(sec_fields(sec, f))
    case Json.JNull{}:
      Done{Json.JNull{}}
    case _:
      Fail{sec ++ " must be a mapping of settings"}

# ---- profiles ------------------------------------------------------------------------------------

# One profile key, checked as `profile set` checks it; the stored value comes
# back as the profile file would hold it ("inherit" and null are null).
def prof_upd(+k: String, u: P.Upd) -> Result<&2, &2, String, Json.Json>:
  match u:
    case P.UBad{m}:
      Fail{m}
    case P.UOk{p}:
      Done{or_null(Json.get(k, P.to_json(p, Setload.empty())))}

def semi(+t: String) -> String:
  String.join(String.split(t, ';'), ",")

def prof_text(+k: String, r: Result<&2, &2, String, String>) -> Result<&2, &2, String, Json.Json>:
  match r:
    case Fail{e}:
      Fail{k ++ ": " ++ e}
    case Done{+t}:
      prof_upd(k, P.update(P.bare("x", SF.ABest{}), k, Bool.pick(String, String.eq(k, "models"), semi(t), t)))

def prof_known(+k: String, +v: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match v:
    case Json.JNull{}:
      Done{Json.JNull{}}
    case _:
      prof_text(k, scal_text(v))

def prof_key(+k: String, +v: Json.Json) -> Result<&2, &2, String, Json.Json>:
  Bool.pick(Result<&2, &2, String, Json.Json>, Setload.has_str(P.keys(), k), prof_known(k, v), Done{v})

def prof_fields(fields: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match fields:
    case Json.JField{+k, v, t}:
      S.field.cons(k, prof_key(k, v), prof_fields(t))
    case _:
      Done{fields}

def name_msg(+name: String) -> String:
  "invalid profile name '" ++ name ++ "': use letters, digits, '-' and '_', starting with a letter or digit"

def prof_body(+name: String, +v: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match v:
    case Json.JObj{f}:
      S.wrap.obj(prof_fields(f))
    case Json.JNull{}:
      Done{Json.JNull{}}
    case _:
      Fail{"profile '" ++ name ++ "' must be a mapping"}

def prof_one(+name: String, +v: Json.Json) -> Result<&2, &2, String, Json.Json>:
  Bool.pick(Result<&2, &2, String, Json.Json>, String.eq(name, "default"), Fail{"profile 'default' follows the autoswitch settings and cannot be changed"},
  Bool.pick(Result<&2, &2, String, Json.Json>, P.valid_name(name), prof_body(name, v), Fail{name_msg(name)}))

def prof_list(fields: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match fields:
    case Json.JField{+name, v, t}:
      S.field.cons(name, prof_one(name, v), prof_list(t))
    case _:
      Done{fields}

def profiles_val(+v: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match v:
    case Json.JObj{f}:
      S.wrap.obj(prof_list(f))
    case Json.JNull{}:
      Done{Json.JNull{}}
    case _:
      Fail{"profiles must be a mapping of names to profiles"}

def active_val(+v: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match v:
    case Json.JStr{s}:
      Done{v}
    case Json.JNull{}:
      Done{v}
    case _:
      Fail{"active_profile must be a profile name"}

# ---- the whole document -------------------------------------------------------------------------------

def top_val(+k: String, +v: Json.Json) -> Result<&2, &2, String, Json.Json>:
  Bool.pick(Result<&2, &2, String, Json.Json>, String.eq(k, "autoswitch") || String.eq(k, "ui"), sec_obj(k, v),
  Bool.pick(Result<&2, &2, String, Json.Json>, String.eq(k, "profiles"), profiles_val(v),
  Bool.pick(Result<&2, &2, String, Json.Json>, String.eq(k, "active_profile"), active_val(v), Done{v})))

def top(fields: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match fields:
    case Json.JField{+k, v, t}:
      S.field.cons(k, top_val(k, v), top(t))
    case _:
      Done{fields}

def top_obj(+doc: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match doc:
    case Json.JObj{f}:
      S.wrap.obj(top(f))
    case _:
      Fail{"the settings document must be a mapping of keys to values"}

# The document with every known key checked and written the way
# `config set` / `profile set` would write it. A bad value is the Fail.
# Unknown keys, sections and profile keys pass through.
def normalize(+doc: Json.Json) -> Result<&2, &2, String, Json.Json>:
  top_obj(doc)

# `profile import` takes only these top-level keys.
def profile_key_ok(ok: Bool, +k: String, rest: Result<&2, &2, String, Unit>) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}:
      rest
    case False{}:
      Fail{"profile import takes profiles and active_profile only; found '" ++ k ++ "'"}

def profile_only(ks: List<&2, String>) -> Result<&2, &2, String, Unit>:
  match ks:
    case Nil{}:
      Done{Unit{}}
    case Con{+k, t}:
      profile_key_ok(Setload.has_str(["profiles", "active_profile", "schemaVersion"], k), k, profile_only(t))

# ---- merging --------------------------------------------------------------------------------------------

def is_obj(j: Json.Json) -> Bool:
  match j:
    case Json.JObj{f}:
      True{}
    case _:
      False{}

def is_null(j: Json.Json) -> Bool:
  match j:
    case Json.JNull{}:
      True{}
    case _:
      False{}

def strip.pick(skip: Bool, +k: String, v: Json.Json, rest: Json.Json) -> Json.Json:
  match skip:
    case True{}:
      rest
    case False{}:
      Json.JField{k, v, rest}

# The value without its null fields (a new profile, a replaced file: null means "not set").
def strip(j: Json.Json) -> Json.Json:
  match j:
    case Json.JObj{f}:
      Json.JObj{strip(f)}
    case Json.JField{k, +v, t}:
      strip.pick(is_null(v), k, strip(v), strip(t))
    case _:
      j

def put(+k: String, +v: Json.Json, +base: Json.Json, merged: Json.Json) -> Json.Json:
  Bool.pick(Json.Json, is_null(v), Json.del(k, base),
  Bool.pick(Json.Json, is_obj(v) && is_obj(or_null(Json.get(k, base))), Json.set(k, merged, base), Json.set(k, strip(v), base)))

# `over` laid on `base`: objects merge key by key, anything else replaces, and
# null removes the key.
def merge(over: Json.Json, +base: Json.Json) -> Json.Json:
  match over:
    case Json.JObj{f}:
      merge(f, base)
    case Json.JField{+k, +v, t}:
      merge(t, put(k, v, base, merge(v, or_null(Json.get(k, base)))))
    case Json.JNil{}:
      base
    case _:
      over
