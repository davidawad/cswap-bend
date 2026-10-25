import Base
import ./json.bend as Json
import ./policy/safe.bend as SF
import ./daemon/config.bend as Cfg
import ./setload.bend as Setload
import ./setwrite.bend as Setwrite

# Behaviour profiles: a named bundle of a strategy, a threshold, a model list,
# a cooldown and an interval, kept in settings.json next to the `autoswitch`
# block as
#
#   "profiles": {"night": {"strategy": "drain-first", "threshold": 95.0,
#                          "models": ["opus"], "cooldown_s": 60.0, "interval_s": 30.0}},
#   "active_profile": "night"
#
# Every key but `strategy` is optional: a missing key inherits the matching
# `autoswitch` setting. The built-in profiles need no entry: `default` is
# today's behaviour from settings (strategy best, or consume-first when the
# setting says so), and one per strategy named after it. A stored profile with
# a built-in's name replaces that built-in; `default` cannot be replaced.
# Unknown keys of the file, of `profiles` and of a profile survive a write.

type Prof is Data:
  Prof{name: String, algo: SF.Algo, threshold: Maybe<&2, String>, models: Maybe<&2, String>, cooldown: Maybe<&2, String>, interval: Maybe<&2, String>}

# Which profile a run uses: none (the legacy behaviour), a found one, or a
# name that matches nothing.
type Res is Data:
  RNone{}
  ROk{prof: Prof}
  RUnknown{name: String}

type Upd is Data:
  UBad{msg: String}
  UOk{prof: Prof}

def keys() -> List<&2, String>:
  ["strategy", "threshold", "models", "cooldown_s", "interval_s"]

def builtin_names() -> List<&2, String>:
  ["default", "best", "round-robin", "soonest-reset", "sticky", "drain-first"]

def bare(+name: String, +algo: SF.Algo) -> Prof:
  Prof{name, algo, None{}, None{}, None{}, None{}}

def builtin.of(+name: String, +m: Maybe<&2, SF.Algo>) -> Maybe<&2, Prof>:
  match m:
    case Some{a}:
      Some{bare(name, a)}
    case None{}:
      None{}

def builtin.pick(+is_default: Bool, +name: String) -> Maybe<&2, Prof>:
  match is_default:
    case True{}:
      Some{bare(name, SF.ABest{})}
    case False{}:
      builtin.of(name, SF.parse(name))

def builtin(+name: String) -> Maybe<&2, Prof>:
  builtin.pick(String.eq(name, "default"), name)

def is_builtin(+name: String) -> Bool:
  Setload.has_str(builtin_names(), name)

# ------------------------------------------------------------------ reading

def num_text(+m: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match m:
    case Some{Json.JNum{t}}:
      Some{t}
    case _:
      None{}

def join_strs(+xs: List<&2, Json.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{Json.JStr{s}, t}:
      s <> join_strs(t)
    case Con{h, t}:
      join_strs(t)

def models_text(+m: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match m:
    case Some{Json.JStr{s}}:
      Some{s}
    case Some{Json.JArr{items}}:
      Some{String.join(join_strs(Json.to_list(Json.JArr{items})), ",")}
    case _:
      None{}

def algo_of(+m: Maybe<&2, Json.Json>, +dflt: SF.Algo) -> SF.Algo:
  match m:
    case Some{Json.JStr{s}}:
      Maybe.default(&2, SF.Algo, SF.parse(s), dflt)
    case _:
      dflt

def algo_base(+p: Prof) -> SF.Algo:
  match p:
    case Prof{n, a, th, ms, cd, iv}:
      a

# A stored profile over the algorithm of the built-in it replaces.
def of_json(+name: String, +j: Json.Json, +base: SF.Algo) -> Prof:
  Prof{name, algo_of(Json.get("strategy", j), base), num_text(Json.get("threshold", j)), models_text(Json.get("models", j)),
    num_text(Json.get("cooldown_s", j)), num_text(Json.get("interval_s", j))}

def stored_in(+m: Maybe<&2, Json.Json>, +name: String) -> Maybe<&2, Json.Json>:
  match m:
    case Some{ps}:
      Json.get(name, ps)
    case None{}:
      None{}

def stored(+raw: Json.Json, +name: String) -> Maybe<&2, Json.Json>:
  stored_in(Json.get("profiles", raw), name)

def found(+s: Maybe<&2, Json.Json>, +b: Maybe<&2, Prof>, +name: String) -> Maybe<&2, Prof>:
  match s:
    case Some{j}:
      Some{of_json(name, j, algo_base(Maybe.default(&2, Prof, b, bare(name, SF.ABest{}))))}
    case None{}:
      b

def find.pick(+is_default: Bool, +raw: Json.Json, +name: String) -> Maybe<&2, Prof>:
  match is_default:
    case True{}:
      builtin(name)
    case False{}:
      found(stored(raw, name), builtin(name), name)

def find(+raw: Json.Json, +name: String) -> Maybe<&2, Prof>:
  find.pick(String.eq(name, "default"), raw, name)

def extra_keep(+skip: Bool, +k: String, +rest: List<&2, String>) -> List<&2, String>:
  match skip:
    case True{}:
      rest
    case False{}:
      k <> rest

def extra_names(+ks: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}:
      []
    case Con{k, t}:
      extra_keep(is_builtin(k), k, extra_names(t))

def profiles_keys(+m: Maybe<&2, Json.Json>) -> List<&2, String>:
  match m:
    case Some{ps}:
      Json.keys(ps)
    case None{}:
      []

# The built-ins, then the stored profiles that are not built-ins, file order.
def names(+raw: Json.Json) -> List<&2, String>:
  List.append(&2, String, builtin_names(), extra_names(profiles_keys(Json.get("profiles", raw))))

def active.pick(+empty: Bool, +s: String) -> Maybe<&2, String>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Some{s}

def active.of(+m: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match m:
    case Some{Json.JStr{s}}:
      active.pick(String.is_empty(s), s)
    case _:
      None{}

def active(+raw: Json.Json) -> Maybe<&2, String>:
  active.of(Json.get("active_profile", raw))

def resolve.found(+m: Maybe<&2, Prof>, +name: String) -> Res:
  match m:
    case Some{p}:
      ROk{p}
    case None{}:
      RUnknown{name}

def resolve.name(+raw: Json.Json, +n: Maybe<&2, String>) -> Res:
  match n:
    case None{}:
      RNone{}
    case Some{name}:
      resolve.found(find(raw, name), name)

def pick_name(+over: Maybe<&2, String>, +act: Maybe<&2, String>) -> Maybe<&2, String>:
  match over:
    case Some{o}:
      over
    case None{}:
      act

# `--profile NAME` over `active_profile` over nothing.
def resolve(+raw: Json.Json, +over: Maybe<&2, String>) -> Res:
  resolve.name(raw, pick_name(over, active(raw)))

# ------------------------------------------------------- over the settings

def over_thr(+m: Maybe<&2, String>, +d: U32) -> U32:
  match m:
    case Some{t}:
      Cfg.field_centi2(Cfg.centi(t), d, 5000, 9990)
    case None{}:
      d

def over_secs(+m: Maybe<&2, String>, +d: U32, +lo: U32, +hi: U32) -> U32:
  match m:
    case Some{t}:
      (Cfg.field_centi2(Cfg.centi(t), (d * 100 : U32), (lo * 100 : U32), (hi * 100 : U32)) / 100 : U32)
    case None{}:
      d

# `best` keeps the engine strategy of the settings (best or consume-first);
# any other strategy replaces it.
def strat_of(+algo: SF.Algo, +st: String) -> String:
  match algo:
    case SF.ABest{}:
      st
    case o:
      SF.name(o)

# The autoswitch settings with the profile's keys laid over them.
def with_prof(+c: Cfg.Cfg, +p: Prof) -> Cfg.Cfg:
  match c p:
    case Cfg.Cfg{th, iv, cd, hy, st, ia, ut, ms} Prof{n, algo, pth, pms, pcd, piv}:
      Cfg.Cfg{over_thr(pth, th), over_secs(piv, iv, 15, 3600), over_secs(pcd, cd, 0, 86400), hy, strat_of(algo, st), ia, ut, Cfg.over_models(pms, ms)}

# ----------------------------------------------------------------- writing

def num_json(+m: Maybe<&2, String>) -> Maybe<&2, Json.Json>:
  match m:
    case Some{t}:
      Some{Json.JNum{t}}
    case None{}:
      None{}

def strs_json(+xs: List<&2, String>) -> List<&2, Json.Json>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      Json.JStr{h} <> strs_json(t)

def models_json(+m: Maybe<&2, String>) -> Maybe<&2, Json.Json>:
  match m:
    case Some{t}:
      Some{Json.arr(strs_json(Cfg.parse_models(t)))}
    case None{}:
      None{}

def opt_set(+key: String, +m: Maybe<&2, Json.Json>, +o: Json.Json) -> Json.Json:
  match m:
    case Some{v}:
      Json.set(key, v, o)
    case None{}:
      Json.del(key, o)

# The profile as a JSON object laid over `base` (the stored object, so keys we
# do not know survive).
def to_json(+p: Prof, +base: Json.Json) -> Json.Json:
  match p:
    case Prof{n, algo, th, ms, cd, iv}:
      opt_set("interval_s", num_json(iv), opt_set("cooldown_s", num_json(cd), opt_set("models", models_json(ms), opt_set("threshold", num_json(th), Json.set("strategy", Json.JStr{SF.name(algo)}, base)))))

def name_of(+p: Prof) -> String:
  match p:
    case Prof{n, a, th, ms, cd, iv}:
      n

def obj_of(+m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case Some{Json.JObj{f}}:
      Json.JObj{f}
    case _:
      Setload.empty()

def store.at(+p: Prof, +ps: Json.Json) -> Json.Json:
  Json.set(name_of(p), to_json(p, obj_of(Json.get(name_of(p), ps))), ps)

# settings.json with the profile stored (created or replaced).
def store(+raw: Json.Json, +p: Prof) -> Json.Json:
  Json.set("profiles", store.at(p, obj_of(Json.get("profiles", raw))), Setload.with_version(raw))

def drop.empty(+ps: Json.Json, +raw: Json.Json) -> Json.Json:
  match ps:
    case Json.JObj{Json.JNil{}}:
      Json.del("profiles", raw)
    case o:
      Json.set("profiles", ps, raw)

def drop.active(+is_active: Bool, +raw: Json.Json) -> Json.Json:
  match is_active:
    case True{}:
      Json.del("active_profile", raw)
    case False{}:
      raw

# settings.json without the stored profile; the active profile is cleared if
# it was this one.
def remove(+raw: Json.Json, +name: String) -> Json.Json:
  drop.active(String.eq(Maybe.default(&2, String, active(raw), ""), name), drop.empty(Json.del(name, obj_of(Json.get("profiles", raw))), raw))

def use(+raw: Json.Json, +name: String) -> Json.Json:
  Json.set("active_profile", Json.JStr{name}, Setload.with_version(raw))

def has_stored(+raw: Json.Json, +name: String) -> Bool:
  Setload.has_str(profiles_keys(Json.get("profiles", raw)), name)

# ---------------------------------------------------------------- updating

type NumRes is Data:
  NBad{msg: String}
  NSet{t: Maybe<&2, String>}

def num.good(+p: Setwrite.Parsed) -> NumRes:
  match p:
    case Setwrite.Bad{m}:
      NBad{m}
    case Setwrite.Good{Json.JNum{t}}:
      NSet{Some{t}}
    case Setwrite.Good{j}:
      NBad{"expected a number"}

def num.pick(+inherit: Bool, +key: String, +raw: String, +lo: String, +hi: String) -> NumRes:
  match inherit:
    case True{}:
      NSet{None{}}
    case False{}:
      num.good(Setwrite.parse.number(False{}, key, raw, lo, hi))

# A number key: "inherit" clears it, anything else is range-checked as
# `cswap config set` checks the matching setting.
def num.of(+key: String, +raw: String, +lo: String, +hi: String) -> NumRes:
  num.pick(String.eq(raw, "inherit"), key, raw, lo, hi)

def upd.th(+p: Prof, +n: NumRes) -> Upd:
  match p n:
    case Prof{nm, a, th, ms, cd, iv} NBad{m}:
      UBad{m}
    case Prof{nm, a, th, ms, cd, iv} NSet{t}:
      UOk{Prof{nm, a, t, ms, cd, iv}}

def upd.cd(+p: Prof, +n: NumRes) -> Upd:
  match p n:
    case Prof{nm, a, th, ms, cd, iv} NBad{m}:
      UBad{m}
    case Prof{nm, a, th, ms, cd, iv} NSet{t}:
      UOk{Prof{nm, a, th, ms, t, iv}}

def upd.iv(+p: Prof, +n: NumRes) -> Upd:
  match p n:
    case Prof{nm, a, th, ms, cd, iv} NBad{m}:
      UBad{m}
    case Prof{nm, a, th, ms, cd, iv} NSet{t}:
      UOk{Prof{nm, a, th, ms, cd, t}}

def upd.algo(+p: Prof, +m: Maybe<&2, SF.Algo>) -> Upd:
  match p m:
    case Prof{nm, a, th, ms, cd, iv} Some{x}:
      UOk{Prof{nm, x, th, ms, cd, iv}}
    case Prof{nm, a, th, ms, cd, iv} None{}:
      UBad{"strategy must be one of: " ++ String.join(SF.names(), ", ")}

# An empty list is an explicit "no model filter"; `inherit` follows settings.
def models.pick(+inherit: Bool, +raw: String) -> Maybe<&2, String>:
  match inherit:
    case True{}:
      None{}
    case False{}:
      Some{String.join(Setload.model_names(raw), ",")}

def models.of(+raw: String) -> Maybe<&2, String>:
  models.pick(String.eq(raw, "inherit"), raw)

def upd.models(+p: Prof, +raw: String) -> Upd:
  match p:
    case Prof{nm, a, th, ms, cd, iv}:
      UOk{Prof{nm, a, th, models.of(raw), cd, iv}}

def upd.key(+k_strat: Bool, +k_thr: Bool, +k_mod: Bool, +k_cd: Bool, +k_iv: Bool, +key: String, +p: Prof, +raw: String) -> Upd:
  match k_strat k_thr k_mod k_cd k_iv:
    case True{} _ _ _ _:
      upd.algo(p, SF.parse(raw))
    case False{} True{} _ _ _:
      upd.th(p, num.of("threshold", raw, "50", "99.9"))
    case False{} False{} True{} _ _:
      upd.models(p, raw)
    case False{} False{} False{} True{} _:
      upd.cd(p, num.of("cooldown_s", raw, "0", "86400"))
    case False{} False{} False{} False{} True{}:
      upd.iv(p, num.of("interval_s", raw, "15", "3600"))
    case _ _ _ _ _:
      UBad{"unknown profile key '" ++ key ++ "'; valid keys: " ++ String.join(keys(), ", ")}

# `profile set NAME KEY VALUE` on `p`.
def update(+p: Prof, +key: String, +raw: String) -> Upd:
  upd.key(String.eq(key, "strategy"), String.eq(key, "threshold"), String.eq(key, "models"), String.eq(key, "cooldown_s"), String.eq(key, "interval_s"), key, p, raw)

# ------------------------------------------------------------------- names

def chars_ok(+s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      (Char.is_alpha(c) || Char.is_digit(c) || Char.is_eq(c, '-') || Char.is_eq(c, '_')) && chars_ok(t)

def first_ok(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      Char.is_alpha(c) || Char.is_digit(c)

# Letters, digits, `-` and `_`, starting with a letter or digit.
def valid_name(+s: String) -> Bool:
  first_ok(s) && chars_ok(s)
