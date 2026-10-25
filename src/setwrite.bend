import Base
import ./setload.bend as Setload
import ./fs/write.bend as FWrite
import ./json.bend as Json
import ./fs.bend as Fs
import ./act.bend as Act
import ./cmd.bend as Cmd
import ./settings.bend as Settings

type Parsed is Data:
  Bad{msg: String}
  Good{value: Json.Json}

def strip_sign(+t: String) -> String:
  Settings.sel.s(String.starts_with(t, "-") || String.starts_with(t, "+"), String.drop(t, 1n), t)

def special.w(+w: String) -> Bool:
  String.eq(w, "inf") || String.eq(w, "infinity") || String.eq(w, "nan")

# float() accepts these and they are never inside a range.
def special(t: String) -> Bool:
  special.w(String.to_lower(strip_sign(t)))

def int.pick(ok: Bool, t: String) -> Maybe<&2, Settings.Dec>:
  match ok:
    case True{}:
      Settings.num(t)
    case False{}:
      None{}

# int(): an optional sign and digits only.
def int.cand(+t: String) -> Maybe<&2, Settings.Dec>:
  int.pick(Settings.all_digits(strip_sign(t)) && Bool.not(String.is_empty(strip_sign(t))), t)

def cand.pick(isint: Bool, t: String) -> Maybe<&2, Settings.Dec>:
  match isint:
    case True{}:
      int.cand(t)
    case False{}:
      Settings.num(t)

def range_msg(dot: String, lo: String, hi: String) -> String:
  dot ++ " must be between " ++ lo ++ " and " ++ hi

def parse.chk(bad: Bool, isint: Bool, msg: String, d: Settings.Dec) -> Parsed:
  match bad:
    case True{}:
      Bad{msg}
    case False{}:
      Good{Setload.norm.show(isint, d)}

def parse.dec(m: Maybe<&2, Settings.Dec>, isint: Bool, +dot: String, raw: String, +lo: String, +hi: String) -> Parsed:
  match m:
    case Some{+d}:
      parse.chk(Settings.below(d, Settings.lit(lo)) || Settings.above(d, Settings.lit(hi)), isint, range_msg(dot, lo, hi), d)
    case None{}:
      Bad{dot ++ " expects " ++ Settings.sel.s(isint, "an integer", "a number") ++ ", got '" ++ raw ++ "'"}

def parse.number2(inf: Bool, +isint: Bool, +dot: String, raw: String, +lo: String, +hi: String, t: String) -> Parsed:
  match inf:
    case True{}:
      Bad{range_msg(dot, lo, hi)}
    case False{}:
      parse.dec(cand.pick(isint, t), isint, dot, raw, lo, hi)

def parse.number(+isint: Bool, dot: String, +raw: String, lo: String, hi: String) -> Parsed:
  parse.number2(Bool.not(isint) && special(String.trim(raw)), isint, dot, raw, lo, hi, String.trim(raw))

def bool.word2(t: Bool, f: Bool) -> Maybe<&2, Bool>:
  match t f:
    case True{} _:
      Some{True{}}
    case False{} True{}:
      Some{False{}}
    case False{} False{}:
      None{}

def bool.word(+w: String) -> Maybe<&2, Bool>:
  bool.word2(String.eq(w, "true") || String.eq(w, "1") || String.eq(w, "yes"),
    String.eq(w, "false") || String.eq(w, "0") || String.eq(w, "no"))

def parse.bool2(m: Maybe<&2, Bool>, dot: String, raw: String) -> Parsed:
  match m:
    case Some{b}:
      Good{Json.JBool{b}}
    case None{}:
      Bad{dot ++ " expects true or false (or 1/0, yes/no), got '" ++ raw ++ "'"}

def parse.choice2(ok: Bool, dot: String, choices: String, raw: String) -> Parsed:
  match ok:
    case True{}:
      Good{Json.JStr{raw}}
    case False{}:
      Bad{dot ++ " must be one of: " ++ String.join(String.split(choices, ','), ", ")}

def parse.str2(Setload.empty: Bool, +dot: String, v: String) -> Parsed:
  match Setload.empty:
    case True{}:
      Bad{dot ++ " expects a non-empty value; use 'cswap config unset " ++ dot ++ "' to clear it"}
    case False{}:
      Good{Json.JStr{v}}

def parse.kind(kind: Settings.Sort, +dot: String, +raw: String, lo: String, hi: String, +choices: String) -> Parsed:
  match kind:
    case Settings.KFloat{}:
      parse.number(False{}, dot, raw, lo, hi)
    case Settings.KInt{}:
      parse.number(True{}, dot, raw, lo, hi)
    case Settings.KBool{}:
      parse.bool2(bool.word(String.to_lower(String.trim(raw))), dot, raw)
    case Settings.KChoice{}:
      parse.choice2(Setload.has_str(String.split(choices, ','), raw), dot, choices, raw)
    case Settings.KString{}:
      parse.str2(String.is_empty(String.trim(raw)), dot, String.trim(raw))

# Strictly parse the text given to `config set`: out of range or mistyped is a
# Bad{message}, never clamped.
def parse_value(sp: Settings.Spec, raw: String) -> Parsed:
  match sp:
    case Settings.Spec{section, key, kind, lo, hi, choices, dflt}:
      parse.kind(kind, section ++ "." ++ key, raw, lo, hi, choices)

def is_float.kind(k: Settings.Sort) -> Bool:
  match k:
    case Settings.KFloat{}:
      True{}
    case _:
      False{}

def is_float(sp: Settings.Spec) -> Bool:
  match sp:
    case Settings.Spec{section, key, kind, lo, hi, choices, dflt}:
      is_float.kind(kind)

def has.in(sec: Maybe<&2, Json.Json>, key: String) -> Bool:
  match sec:
    case Some{j}:
      Maybe.is_some(&2, Json.Json, Json.get(key, j))
    case None{}:
      False{}

# Is the key present in the raw file (an explicit default still counts)?
def is_set(raw: Json.Json, sp: Settings.Spec) -> Bool:
  match sp:
    case Settings.Spec{section, key, kind, lo, hi, choices, dflt}:
      has.in(Json.get(section, raw), key)

# raw[section][key] = v, with schemaVersion defaulted; only that key written.
def set_in(+raw: Json.Json, sp: Settings.Spec, v: Json.Json) -> Json.Json:
  match sp:
    case Settings.Spec{+section, key, kind, lo, hi, choices, dflt}:
      Json.set(section, Json.set(key, v, Setload.section_of(raw, section)), Setload.with_version(raw))

def obj_empty(j: Json.Json) -> Bool:
  match j:
    case Json.JObj{Json.JNil{}}:
      True{}
    case _:
      False{}

def unset.fin(gone: Bool, +section: String, +sect: Json.Json, r2: Json.Json) -> Json.Json:
  match gone:
    case True{}:
      Json.del(section, r2)
    case False{}:
      Json.set(section, sect, r2)

def unset.fin2(+sect: Json.Json, +section: String, r2: Json.Json) -> Json.Json:
  unset.fin(obj_empty(sect), section, sect, r2)

# del raw[section][key]; an emptied section goes too.
def unset_in(+raw: Json.Json, sp: Settings.Spec) -> Json.Json:
  match sp:
    case Settings.Spec{+section, +key, kind, lo, hi, choices, dflt}:
      unset.fin2(Json.del(key, Setload.section_of(raw, section)), section, Setload.with_version(raw))

type Row is Data:
  Row{sp: Settings.Spec, value: Json.Json, set: Bool}

def value_of(+norm: Json.Json, sp: Settings.Spec) -> Json.Json:
  match sp:
    case Settings.Spec{+section, key, kind, lo, hi, choices, dflt}:
      Setload.get_or_null(key, Setload.get_or_null(section, norm))

def rows(+raw: Json.Json, +norm: Json.Json, xs: List<&2, Settings.Spec>) -> List<&2, Row>:
  match xs:
    case Nil{}:
      []
    case Con{+h, t}:
      Row{h, value_of(norm, h), is_set(raw, h)} <> rows(raw, norm, t)

# (spec, effective value, explicitly set?) per key, registry order.
def effective(+raw: Json.Json) -> List<&2, Row>:
  rows(raw, Setload.normalize(raw), Settings.specs())

def fmt.num(isfloat: Bool, +t: String) -> String:
  Settings.sel.s(isfloat, Settings.fmt(Settings.lit(t)), t)

# format_setting_value
def fmt.val(isfloat: Bool, j: Json.Json) -> String:
  match j:
    case Json.JNull{}:
      "(none)"
    case Json.JBool{b}:
      Settings.sel.s(b, "true", "false")
    case Json.JNum{t}:
      fmt.num(isfloat, t)
    case Json.JStr{s}:
      s
    case _:
      ""

def row.key(r: Row) -> String:
  match r:
    case Row{sp, value, set}:
      Settings.dotted(sp)

def row.val(r: Row) -> String:
  match r:
    case Row{+sp, value, set}:
      fmt.val(is_float(sp), value)

def row.json(r: Row) -> Json.Json:
  match r:
    case Row{sp, value, set}:
      Json.of_pairs([("key", Json.JStr{Settings.dotted(sp)}), ("value", value), ("isSet", Json.JBool{set})])

def rows.json(rs: List<&2, Row>) -> List<&2, Json.Json>:
  match rs:
    case Nil{}:
      []
    case Con{+h, t}:
      row.json(h) <> rows.json(t)

def row.find.pick(hit: Bool, r: Row, rest: Maybe<&2, Row>) -> Maybe<&2, Row>:
  match hit:
    case True{}:
      Some{r}
    case False{}:
      rest

def row.find(+key: String, rs: List<&2, Row>) -> Maybe<&2, Row>:
  match rs:
    case Nil{}:
      None{}
    case Con{+h, t}:
      row.find.pick(String.eq(row.key(h), key), h, row.find(key, t))

def keys.of(rs: List<&2, Row>) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{+h, t}:
      row.key(h) <> keys.of(t)

def vals.of(rs: List<&2, Row>) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{+h, t}:
      row.val(h) <> vals.of(t)

def width(xs: List<&2, String>, acc: Nat) -> Nat:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      width(t, Nat.max(acc, String.length(h)))

def pad(+s: String, n: Nat) -> String:
  s ++ String.repeat(" ", Nat.sub(n, String.length(s)))

def line(kw: Nat, vw: Nat, +r: Row) -> String:
  match r:
    case Row{sp, value, +set}:
      pad(row.key(Row{sp, value, set}), kw) ++ "  " ++ pad(row.val(Row{sp, value, set}), vw) ++ Settings.sel.s(set, "", "  (default)")

def lines(+kw: Nat, +vw: Nat, rs: List<&2, Row>) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{h, t}:
      line(kw, vw, h) <> lines(kw, vw, t)

# The text of `config list`: padded key and value columns, `(default)` on
# the keys the file does not set.
def list.text(+rs: List<&2, Row>) -> String:
  String.join(lines(width(keys.of(rs), 0n), width(vals.of(rs), 0n), rs), "\n")

