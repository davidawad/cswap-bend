import Base
import ./fs/write.bend as FWrite
import ./json.bend as Json
import ./fs.bend as Fs
import ./act.bend as Act
import ./cmd.bend as Cmd
import ./settings.bend as Settings

def truthy.items(j: Json.Json) -> Bool:
  match j:
    case Json.JNil{}:
      False{}
    case _:
      True{}

# Python truthiness of a JSON value.
def truthy(j: Json.Json) -> Bool:
  match j:
    case Json.JNull{}:
      False{}
    case Json.JBool{b}:
      b
    case Json.JNum{t}:
      Bool.not(Settings.is_zero(Settings.lit(t)))
    case Json.JStr{s}:
      Bool.not(String.is_empty(s))
    case Json.JArr{items}:
      truthy.items(items)
    case Json.JObj{fields}:
      truthy.items(fields)
    case _:
      False{}

def empty() -> Json.Json:
  Json.of_pairs([])

def obj_or_empty(j: Json.Json) -> Json.Json:
  match j:
    case Json.JObj{f}:
      Json.JObj{f}
    case _:
      empty()

def has_str(xs: List<&2, String>, +v: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      String.eq(h, v) || has_str(t, v)

def get_or_null(+key: String, +j: Json.Json) -> Json.Json:
  Maybe.default(&2, Json.Json, Json.get(key, j), Json.JNull{})

def int_text(d: Settings.Dec) -> String:
  match d:
    case Settings.Dec{neg, i, f}:
      i

def norm.show(+isint: Bool, +d: Settings.Dec) -> Json.Json:
  Json.JNum{Settings.sel.s(isint, int_text(d), Settings.repr(d))}

def norm.fin(m: Maybe<&2, Settings.Dec>, isint: Bool, lo: String, hi: String, dflt: Json.Json) -> Json.Json:
  match m:
    case Some{d}:
      norm.show(isint, Settings.clamp(d, Settings.lit(lo), Settings.lit(hi)))
    case None{}:
      dflt

def norm.numv(isint: Bool, lo: String, hi: String, dflt: Json.Json, v: Json.Json) -> Json.Json:
  match v:
    case Json.JNum{t}:
      norm.fin(Settings.num(t), isint, lo, hi, dflt)
    case _:
      dflt

def norm.pick(ok: Bool, v: Json.Json, dflt: Json.Json) -> Json.Json:
  match ok:
    case True{}:
      v
    case False{}:
      dflt

def norm.choice(choices: String, dflt: Json.Json, v: Json.Json) -> Json.Json:
  match v:
    case Json.JStr{+s}:
      norm.pick(has_str(String.split(choices, ','), s), Json.JStr{s}, dflt)
    case _:
      dflt

def norm.str(dflt: Json.Json, v: Json.Json) -> Json.Json:
  match v:
    case Json.JStr{+s}:
      norm.pick(Bool.not(String.is_empty(s)), Json.JStr{s}, dflt)
    case _:
      dflt

# One setting's lenient value: clamped into range, or the default for a value
# of the wrong type.
def norm.kind(kind: Settings.Sort, lo: String, hi: String, choices: String, dflt: Json.Json, v: Json.Json) -> Json.Json:
  match kind:
    case Settings.KFloat{}:
      norm.numv(False{}, lo, hi, dflt, v)
    case Settings.KInt{}:
      norm.numv(True{}, lo, hi, dflt, v)
    case Settings.KBool{}:
      Json.JBool{truthy(v)}
    case Settings.KChoice{}:
      norm.choice(choices, dflt, v)
    case Settings.KString{}:
      norm.str(dflt, v)

def norm.one2(hit: Bool, key: String, v: Json.Json, out: Json.Json) -> Json.Json:
  match hit:
    case True{}:
      Json.set(key, v, out)
    case False{}:
      out

def norm.one(sp: Settings.Spec, sec: String, src: Json.Json, out: Json.Json) -> Json.Json:
  match sp:
    case Settings.Spec{section, +key, kind, lo, hi, choices, dflt}:
      norm.one2(String.eq(section, sec), key, norm.kind(kind, lo, hi, choices, dflt, get_or_null(key, src)), out)

def norm.sec(xs: List<&2, Settings.Spec>, +sec: String, +src: Json.Json, out: Json.Json) -> Json.Json:
  match xs:
    case Nil{}:
      out
    case Con{h, t}:
      norm.sec(t, sec, src, norm.one(h, sec, src, out))

def sect_obj(m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case Some{j}:
      obj_or_empty(j)
    case None{}:
      empty()

# The section object (`{}` when missing or not an object).
def section_of(+raw: Json.Json, +sec: String) -> Json.Json:
  sect_obj(Json.get(sec, raw))

def norm.section2(+sec: String, base: Json.Json, +s: Json.Json) -> Json.Json:
  Json.set(sec, norm.sec(Settings.specs(), sec, s, s), base)

def norm.section(+sec: String, +base: Json.Json) -> Json.Json:
  norm.section2(sec, base, section_of(base, sec))

def ver.pick(m: Maybe<&2, Json.Json>, raw: Json.Json) -> Json.Json:
  match m:
    case Some{v}:
      raw
    case None{}:
      Json.set("schemaVersion", Json.JNum{"1"}, raw)

# raw.setdefault("schemaVersion", 1)
def with_version(+raw: Json.Json) -> Json.Json:
  ver.pick(Json.get("schemaVersion", raw), raw)

# The whole settings object with every known key present: defaults filled in,
# numbers clamped, wrong types replaced. Unknown keys and sections survive.
def normalize(raw: Json.Json) -> Json.Json:
  norm.section("ui", norm.section("autoswitch", with_version(obj_or_empty(raw))))

def path(+root: String) -> String:
  root ++ "/settings.json"

def raw.parsed(r: Result<&2, &2, String, Json.Json>) -> Json.Json:
  match r:
    case Fail{e}:
      empty()
    case Done{j}:
      obj_or_empty(j)

def raw.of(r: Fs.Res(String)) -> Json.Json:
  match r:
    case Fail{e}:
      empty()
    case Done{t}:
      raw.parsed(Json.parse(t))

# settings.json as read by the lenient paths: `{}` for a missing, unreadable,
# torn or non-object file.
def load_raw(+root: String) -> IO(Json.Json):
  IO.bind(Fs.Res(String), Json.Json, Fs.read_file(path(root)), r => IO.pure(Json.Json, raw.of(r)))

# Lenient load: the full object, defaults filled, numbers clamped.
def load(+root: String) -> IO(Json.Json):
  IO.bind(Json.Json, Json.Json, load_raw(root), raw => IO.pure(Json.Json, normalize(raw)))

def autoswitch(+s: Json.Json, +key: String) -> Json.Json:
  get_or_null(key, get_or_null("autoswitch", s))

def text_of(j: Json.Json) -> String:
  match j:
    case Json.JNum{t}:
      t
    case _:
      ""

# Decimal text as Python prints the float: "90.0".
def threshold(s: Json.Json) -> String:
  text_of(autoswitch(s, "threshold"))

def interval_seconds(s: Json.Json) -> String:
  text_of(autoswitch(s, "intervalSeconds"))

def cooldown_seconds(s: Json.Json) -> String:
  text_of(autoswitch(s, "cooldownSeconds"))

def hysteresis_pct(s: Json.Json) -> String:
  text_of(autoswitch(s, "hysteresisPct"))

def strategy.of(j: Json.Json) -> String:
  match j:
    case Json.JStr{s}:
      s
    case _:
      "best"

def strategy(s: Json.Json) -> String:
  strategy.of(autoswitch(s, "strategy"))

def include_api_key_accounts(s: Json.Json) -> Bool:
  truthy(autoswitch(s, "includeApiKeyAccounts"))

def unhealthy_ticks(s: Json.Json) -> U32:
  Maybe.default(&2, U32, U32.read(text_of(autoswitch(s, "unhealthyTicks"))), 3)

# Tenths of a percent or second (floored) for integer comparisons.
def threshold_tenths(s: Json.Json) -> U32:
  Settings.tenths(threshold(s))

def interval_tenths(s: Json.Json) -> U32:
  Settings.tenths(interval_seconds(s))

def cooldown_tenths(s: Json.Json) -> U32:
  Settings.tenths(cooldown_seconds(s))

def hysteresis_tenths(s: Json.Json) -> U32:
  Settings.tenths(hysteresis_pct(s))

def models.keep2(skip: Bool, +q: String, rest: List<&2, String>) -> List<&2, String>:
  match skip:
    case True{}:
      rest
    case False{}:
      q <> rest

def models.keep(+q: String, rest: List<&2, String>) -> List<&2, String>:
  models.keep2(String.is_empty(q), q, rest)

# Each part trimmed, empties dropped.
def models.clean(ps: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}:
      []
    case Con{p, t}:
      models.keep(String.trim(p), models.clean(t))

def models.without2(same: Bool, +h: String, rest: List<&2, String>) -> List<&2, String>:
  match same:
    case True{}:
      rest
    case False{}:
      h <> rest

# The list without the entries equal to `low` ignoring case.
def models.without(xs: List<&2, String>, +low: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{+h, t}:
      models.without2(String.eq(String.to_lower(h), low), h, models.without(t, low))

def models.dedup(fuel: Nat, xs: List<&2, String>) -> List<&2, String>:
  match fuel xs:
    case 0n _:
      xs
    case 1n+p Nil{}:
      []
    case 1n+p Con{+h, t}:
      h <> models.dedup(p, models.without(t, String.to_lower(h)))

def models.dedup2(+xs: List<&2, String>) -> List<&2, String>:
  models.dedup(List.length(&2, String, xs), xs)

# parse_model_names: split on `,`, trim, drop empties, de-duplicate
# case-insensitively (the first spelling wins).
def model_names(v: String) -> List<&2, String>:
  models.dedup2(models.clean(String.split(v, ',')))

def model.of(j: Json.Json) -> List<&2, String>:
  match j:
    case Json.JStr{s}:
      model_names(s)
    case _:
      []

# `autoswitch.model` as a list of names ([] = account-wide windows only).
def model(s: Json.Json) -> List<&2, String>:
  model.of(autoswitch(s, "model"))

# A numeric flag clamped into the setting's range, as Settings.repr text; None for
# text that is not a number.
def clamp_text.fin(m: Maybe<&2, Settings.Dec>, lo: String, hi: String) -> Maybe<&2, String>:
  match m:
    case Some{d}:
      Some{Settings.repr(Settings.clamp(d, Settings.lit(lo), Settings.lit(hi)))}
    case None{}:
      None{}

def clamp_text(+s: String, lo: String, hi: String) -> Maybe<&2, String>:
  clamp_text.fin(Settings.num(s), lo, hi)

# `--threshold 120` -> "99.9"
def clamp_threshold(s: String) -> Maybe<&2, String>:
  clamp_text(s, "50", "99.9")

# `--interval 5` -> "15.0"
def clamp_interval(s: String) -> Maybe<&2, String>:
  clamp_text(s, "15", "3600")

def clamp_cooldown(s: String) -> Maybe<&2, String>:
  clamp_text(s, "0", "86400")

def clamp_hysteresis(s: String) -> Maybe<&2, String>:
  clamp_text(s, "0", "50")

# A --strategy flag: an unknown value falls back to the default.
def clamp_strategy.pick(ok: Bool, s: String) -> String:
  match ok:
    case True{}:
      s
    case False{}:
      "best"

def clamp_strategy(+s: String) -> String:
  clamp_strategy.pick(has_str(["best", "consume-first"], s), s)

