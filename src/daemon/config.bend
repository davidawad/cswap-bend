import Base
import ../json.bend as Json
import ../fmt/code.bend as Code

# The autoswitch settings (the `autoswitch` block of settings.json, loaded the
# lenient way of settings.py) and the flags of `cswap auto`, which override
# them. Percentages are centi-percent U32 (90 % = 9000); times are whole seconds.

type Cfg is Data:
  Cfg{threshold: U32, interval: U32, cooldown: U32, hysteresis: U32, strategy: String, include_api: Bool, unhealthy: U32, models: List<&2, String>}

type Flags is Data:
  Flags{once: Bool, fmt: U32, dry_run: Bool, threshold: Maybe<&2, U32>, interval: Maybe<&2, U32>, cooldown: Maybe<&2, U32>, strategy: Maybe<&2, String>, models: Maybe<&2, String>, include_api: Bool}

def defaults() -> Cfg:
  Cfg{9000, 60, 300, 1000, "best", False{}, 3, []}

def sel_u(+c: Bool, +x: U32, +y: U32) -> U32:
  match c:
    case True{}:
      x
    case False{}:
      y

def clamp(+v: U32, +lo: U32, +hi: U32) -> U32:
  sel_u(U32.is_lt(v, lo), lo, sel_u(U32.is_gt(v, hi), hi, v))

# ---- numbers ----------------------------------------------------------------------------------

def digits(+s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Char.is_digit(c) && digits(t)

def read_u32b(+ok: Bool, +s: String) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      U32.read(s)
    case False{}:
      None{}

def read_u32(+s: String) -> Maybe<&2, U32>:
  read_u32b(digits(s) && Bool.not(String.is_empty(s)), s)

def cents2(+i: Maybe<&2, U32>, +f: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match i f:
    case Some{a} Some{b}:
      Some{(a * 100 + b : U32)}
    case _ _:
      None{}

def centi2(+parts: List<&2, String>) -> Maybe<&2, U32>:
  match parts:
    case Con{i, Nil{}}:
      cents2(read_u32(i), Some{0})
    case Con{i, Con{f, Nil{}}}:
      cents2(read_u32(i), read_u32(String.take(f ++ "00", 2n)))
    case _:
      None{}

# "12.34" -> 1234, "7" -> 700, "5.5" -> 550; None for anything else (signs,
# exponents, text). Digits past the second decimal are dropped.
def centi(+t: String) -> Maybe<&2, U32>:
  centi2(String.split(t, '.'))

def num_text(+m: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match m:
    case Some{Json.JNum{t}}:
      Some{t}
    case _:
      None{}

def centi_of(+m: Maybe<&2, String>) -> Maybe<&2, U32>:
  match m:
    case Some{t}:
      centi(t)
    case None{}:
      None{}

def field_centi2(+m: Maybe<&2, U32>, +d: U32, +lo: U32, +hi: U32) -> U32:
  match m:
    case Some{v}:
      clamp(v, lo, hi)
    case None{}:
      d

# A numeric settings field, centi, clamped; the default when absent or not a number.
def field_centi(+j: Json.Json, +key: String, +d: U32, +lo: U32, +hi: U32) -> U32:
  field_centi2(centi_of(num_text(Json.get(key, j))), d, lo, hi)

# Whole seconds from a centi field (the fraction is dropped).
def field_secs(+j: Json.Json, +key: String, +d: U32, +lo: U32, +hi: U32) -> U32:
  (field_centi(j, key, (d * 100 : U32), (lo * 100 : U32), (hi * 100 : U32)) / 100 : U32)

# A bool field is read by truthiness: the string "false" is true.
def truthy(+m: Maybe<&2, Json.Json>, +d: Bool) -> Bool:
  match m:
    case Some{Json.JBool{b}}:
      b
    case Some{Json.JNull{}}:
      False{}
    case Some{Json.JStr{s}}:
      Bool.not(String.is_empty(s))
    case Some{Json.JNum{t}}:
      Bool.not(String.eq(t, "0") || String.eq(t, "0.0"))
    case Some{j}:
      True{}
    case None{}:
      d

def pick_strategy(+ok: Bool, +s: String, +d: String) -> String:
  match ok:
    case True{}:
      s
    case False{}:
      d

# ---- model names: comma list, trimmed, de-duplicated without regard to case ---------------------

def strategy_of(+m: Maybe<&2, Json.Json>, +d: String) -> String:
  match m:
    case Some{Json.JStr{s}}:
      pick_strategy(String.eq(s, "best") || String.eq(s, "consume-first"), s, d)
    case _:
      d

def has_ci(+x: String, +xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      String.eq(String.to_lower(h), String.to_lower(x)) || has_ci(x, t)

def keep_name(+h: String, +seen: List<&2, String>) -> Bool:
  Bool.not(String.is_empty(h)) && Bool.not(has_ci(h, seen))

def seen_after(+keep: Bool, +h: String, +seen: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      List.append(&2, String, seen, [h])
    case False{}:
      seen

def out_name(+keep: Bool, +h: String, +rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      h <> rest
    case False{}:
      rest

def dedupe(+xs: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      out_name(keep_name(h, seen), h, dedupe(t, seen_after(keep_name(h, seen), h, seen)))

def trim_all(+xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      String.trim(h) <> trim_all(t)

def parse_models(+s: String) -> List<&2, String>:
  dedupe(trim_all(String.split(s, ',')), [])

def models_of(+m: Maybe<&2, Json.Json>) -> List<&2, String>:
  match m:
    case Some{Json.JStr{s}}:
      parse_models(s)
    case _:
      []

# ---- settings.json ------------------------------------------------------------------------------

def block_of(+m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case Some{b}:
      b
    case None{}:
      Json.JNull{}

def autoswitch_block(+j: Json.Json) -> Json.Json:
  block_of(Json.get("autoswitch", j))

def from_block(+b: Json.Json) -> Cfg:
  Cfg{field_centi(b, "threshold", 9000, 5000, 9990), field_secs(b, "intervalSeconds", 60, 15, 3600), field_secs(b, "cooldownSeconds", 300, 0, 86400),
    field_centi(b, "hysteresisPct", 1000, 0, 5000), strategy_of(Json.get("strategy", b), "best"), truthy(Json.get("includeApiKeyAccounts", b), False{}),
    (field_centi(b, "unhealthyTicks", 300, 100, 10000) / 100 : U32), models_of(Json.get("model", b))}

# The lenient load: anything unreadable is the default, numbers are clamped.
def from_settings(+j: Json.Json) -> Cfg:
  from_block(autoswitch_block(j))

def from_result(r: Result<&2, &2, String, Json.Json>) -> Cfg:
  match r:
    case Done{j}:
      from_settings(j)
    case Fail{e}:
      defaults()

# ---- flags --------------------------------------------------------------------------------------

def from_text(+t: String) -> Cfg:
  from_result(Json.parse(t))

def no_flags() -> Flags:
  Flags{False{}, 0, False{}, None{}, None{}, None{}, None{}, None{}, False{}}

def split_eq2(+parts: List<&2, String>) -> List<&2, String>:
  match parts:
    case Con{k, Con{v, rest}}:
      k <> String.join(Con{v, rest}, "=") <> []
    case _:
      parts

# `--flag value` and `--flag=value`.
def split_eq_b(+eq: Bool, +a: String) -> List<&2, String>:
  match eq:
    case True{}:
      split_eq2(String.split(a, '='))
    case False{}:
      [a]

def split_eq(+a: String) -> List<&2, String>:
  split_eq_b(String.starts_with(a, "--") && String.contains(a, "="), a)

def normalize(+xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      List.append(&2, String, split_eq(h), normalize(t))

def bad_value(+flag: String, +kind: String, +v: String) -> String:
  "argument " ++ flag ++ ": invalid " ++ kind ++ " value: '" ++ v ++ "'"

def with_num2(+is_th: Bool, +is_iv: Bool, +f: Flags, +n: U32) -> Flags:
  match is_th is_iv f:
    case True{} _ Flags{o, j, d, th, iv, cd, st, md, ia}:
      Flags{o, j, d, Some{clamp(n, 5000, 9990)}, iv, cd, st, md, ia}
    case False{} True{} Flags{o, j, d, th, iv, cd, st, md, ia}:
      Flags{o, j, d, th, Some{clamp((n / 100 : U32), 15, 3600)}, cd, st, md, ia}
    case False{} False{} Flags{o, j, d, th, iv, cd, st, md, ia}:
      Flags{o, j, d, th, iv, Some{clamp((n / 100 : U32), 0, 86400)}, st, md, ia}

def with_num(+f: Flags, +which: String, +n: U32) -> Flags:
  with_num2(String.eq(which, "--threshold"), String.eq(which, "--interval"), f, n)

def set_num2(+f: Flags, +which: String, +v: String, +c: Maybe<&2, U32>) -> Result<&2, &2, String, Flags>:
  match c:
    case None{}:
      Fail{bad_value(which, "float", v)}
    case Some{n}:
      Done{with_num(f, which, n)}

def set_num(+f: Flags, +which: String, +v: String) -> Result<&2, &2, String, Flags>:
  set_num2(f, which, v, centi(v))

def set_flag(+f: Flags, +name: String) -> Flags:
  match f:
    case Flags{o, j, d, th, iv, cd, st, md, ia}:
      Flags{o || String.eq(name, "--once"), Bool.pick(U32, String.eq(name, "--json"), 1, j), d || String.eq(name, "--dry-run"), th, iv, cd, st, md, ia || String.eq(name, "--include-api-key-accounts")}

def set_str2(+is_strategy: Bool, +ok: Bool, +f: Flags, +v: String) -> Result<&2, &2, String, Flags>:
  match is_strategy ok f:
    case True{} True{} Flags{o, j, d, th, iv, cd, st, md, ia}:
      Done{Flags{o, j, d, th, iv, cd, Some{v}, md, ia}}
    case True{} False{} Flags{o, j, d, th, iv, cd, st, md, ia}:
      Fail{"argument --strategy: invalid choice: '" ++ v ++ "' (choose from 'best', 'consume-first')"}
    case False{} _ Flags{o, j, d, th, iv, cd, st, md, ia}:
      Done{Flags{o, j, d, th, iv, cd, st, Some{v}, ia}}

def set_str(+f: Flags, +which: String, +v: String) -> Result<&2, &2, String, Flags>:
  set_str2(String.eq(which, "--strategy"), String.eq(v, "best") || String.eq(v, "consume-first"), f, v)

def takes_value(+a: String) -> Bool:
  String.eq(a, "--format") || String.eq(a, "--threshold") || String.eq(a, "--interval") || String.eq(a, "--cooldown") || String.eq(a, "--strategy") || String.eq(a, "--model")

def is_bool_flag(+a: String) -> Bool:
  String.eq(a, "--once") || String.eq(a, "--json") || String.eq(a, "--dry-run") || String.eq(a, "--include-api-key-accounts")

def apply_value2(+str_flag: Bool, +f: Flags, +a: String, +v: String) -> Result<&2, &2, String, Flags>:
  match str_flag:
    case True{}:
      set_str(f, a, v)
    case False{}:
      set_num(f, a, v)

# `--format NAME`: the output format of the event stream (src/fmt/code.bend).
def set_fmt2(m: Maybe<&2, U32>, +f: Flags, +v: String) -> Result<&2, &2, String, Flags>:
  match m f:
    case Some{n} Flags{o, j, d, th, iv, cd, st, md, ia}:
      Done{Flags{o, n, d, th, iv, cd, st, md, ia}}
    case None{} _:
      Fail{Code.invalid("--format", v)}

def apply_value3(+is_fmt: Bool, +f: Flags, +a: String, +v: String) -> Result<&2, &2, String, Flags>:
  match is_fmt:
    case True{}:
      set_fmt2(Code.of_name(v), f, v)
    case False{}:
      apply_value2(String.eq(a, "--strategy") || String.eq(a, "--model"), f, a, v)

def apply_value(+f: Flags, +a: String, +v: String) -> Result<&2, &2, String, Flags>:
  apply_value3(String.eq(a, "--format"), f, a, v)

def rest_after2(+valued: Bool, +rest: List<&2, String>) -> List<&2, String>:
  match valued:
    case True{}:
      List.drop(&2, String, rest, 1n)
    case False{}:
      rest

def rest_after(+a: String, +rest: List<&2, String>) -> List<&2, String>:
  rest_after2(takes_value(a), rest)

def valued_flag(+a: String, +rest: List<&2, String>, +f: Flags) -> Result<&2, &2, String, Flags>:
  match rest:
    case Nil{}:
      Fail{"argument " ++ a ++ ": expected one argument"}
    case Con{v, more}:
      apply_value(f, a, v)

def advance2(+bool_flag: Bool, +valued: Bool, +a: String, +rest: List<&2, String>, +f: Flags) -> Result<&2, &2, String, Flags>:
  match bool_flag valued:
    case True{} _:
      Done{set_flag(f, a)}
    case False{} True{}:
      valued_flag(a, rest, f)
    case False{} False{}:
      Fail{"unrecognized arguments: " ++ a}

def advance(+a: String, +rest: List<&2, String>, +f: Flags) -> Result<&2, &2, String, Flags>:
  advance2(is_bool_flag(a), takes_value(a), a, rest, f)

def step(+fuel: Nat, +xs: List<&2, String>, fr: Result<&2, &2, String, Flags>) -> Result<&2, &2, String, Flags>:
  match fuel xs fr:
    case 1n++p Con{a, rest} Done{f}:
      step(p, rest_after(a, rest), advance(a, rest, f))
    case _ _ _:
      fr

# The flags of `cswap auto` (after the verb). Exit 2 territory on Fail.
def parse_flags(+args: List<&2, String>) -> Result<&2, &2, String, Flags>:
  step(Nat.add(List.length(&2, String, args), 1n), normalize(args), Done{no_flags()})

# ---- flags over settings ------------------------------------------------------------------------

def over_u(+m: Maybe<&2, U32>, +d: U32) -> U32:
  match m:
    case Some{v}:
      v
    case None{}:
      d

def over_s(+m: Maybe<&2, String>, +d: String) -> String:
  match m:
    case Some{v}:
      v
    case None{}:
      d

def over_models(+m: Maybe<&2, String>, +d: List<&2, String>) -> List<&2, String>:
  match m:
    case Some{v}:
      parse_models(v)
    case None{}:
      d

def merge(+c: Cfg, +f: Flags) -> Cfg:
  match c f:
    case Cfg{th, iv, cd, hy, st, ia, ut, ms} Flags{o, j, d, fth, fiv, fcd, fst, fmd, fia}:
      Cfg{over_u(fth, th), over_u(fiv, iv), over_u(fcd, cd), hy, over_s(fst, st), ia || fia, ut, over_models(fmd, ms)}

def cfg_threshold(+c: Cfg) -> U32:
  match c:
    case Cfg{th, iv, cd, hy, st, ia, ut, ms}:
      th

def cfg_models(+c: Cfg) -> List<&2, String>:
  match c:
    case Cfg{th, iv, cd, hy, st, ia, ut, ms}:
      ms

def cfg_interval(+c: Cfg) -> U32:
  match c:
    case Cfg{th, iv, cd, hy, st, ia, ut, ms}:
      iv

def cfg_strategy(+c: Cfg) -> String:
  match c:
    case Cfg{th, iv, cd, hy, st, ia, ut, ms}:
      st

def cfg_cooldown(+c: Cfg) -> U32:
  match c:
    case Cfg{th, iv, cd, hy, st, ia, ut, ms}:
      cd

def cfg_include_api(+c: Cfg) -> Bool:
  match c:
    case Cfg{th, iv, cd, hy, st, ia, ut, ms}:
      ia
