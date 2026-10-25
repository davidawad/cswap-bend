import Base
import ../src/json.bend as Json
import ../src/policy/safe.bend as SF
import ../src/daemon/config.bend as Cfg
import ../src/profile.bend as P

# Ground equations for behaviour profiles: lookup (built-in and stored),
# which profile a run uses, the keys laid over the settings, `profile set`
# validation, and the writes that must keep every key they do not own.

def raw(t: String) -> Json.Json:
  Json.unwrap(Json.parse(t))

def night() -> Json.Json:
  raw("{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 80}, \"profiles\": {\"night\": {\"strategy\": \"drain-first\", \"threshold\": 95.0, \"models\": [\"opus\"], \"cooldown_s\": 60.0, \"interval_s\": 30.0, \"note\": \"x\"}, \"sticky\": {\"threshold\": 70}}, \"active_profile\": \"night\", \"extra\": [1]}")

def bare(n: String, a: SF.Algo) -> P.Prof:
  P.bare(n, a)

def night_prof() -> P.Prof:
  P.Prof{"night", SF.ADrainFirst{}, Some{"95.0"}, Some{"opus"}, Some{"60.0"}, Some{"30.0"}}

# ---- lookup
def f_default() -> {P.find(raw("{}"), "default") == Some{bare("default", SF.ABest{})} : Maybe<&2, P.Prof>}:
  {==}

def f_builtin_strategy() -> {P.find(raw("{}"), "round-robin") == Some{bare("round-robin", SF.ARoundRobin{})} : Maybe<&2, P.Prof>}:
  {==}

def f_unknown() -> {P.find(raw("{}"), "nope") == None{} : Maybe<&2, P.Prof>}:
  {==}

def f_stored() -> {P.find(night(), "night") == Some{night_prof()} : Maybe<&2, P.Prof>}:
  {==}

# A stored profile named like a built-in keeps the built-in's strategy unless it sets one.
def f_override_builtin() -> {P.find(night(), "sticky") == Some{P.Prof{"sticky", SF.ASticky{}, Some{"70"}, None{}, None{}, None{}}} : Maybe<&2, P.Prof>}:
  {==}

# `default` follows the settings and cannot be replaced.
def f_default_not_replaceable() -> {P.find(raw("{\"profiles\": {\"default\": {\"strategy\": \"sticky\"}}}"), "default") == Some{bare("default", SF.ABest{})} : Maybe<&2, P.Prof>}:
  {==}

def f_bad_strategy_in_file() -> {P.find(raw("{\"profiles\": {\"x\": {\"strategy\": \"fastest\"}}}"), "x") == Some{bare("x", SF.ABest{})} : Maybe<&2, P.Prof>}:
  {==}

def f_models_as_text() -> {P.find(raw("{\"profiles\": {\"x\": {\"models\": \"opus,fable\"}}}"), "x") == Some{P.Prof{"x", SF.ABest{}, None{}, Some{"opus,fable"}, None{}, None{}}} : Maybe<&2, P.Prof>}:
  {==}

def n_names() -> {P.names(night()) == ["default", "best", "round-robin", "soonest-reset", "sticky", "drain-first", "night"] : List<&2, String>}:
  {==}

def n_names_empty() -> {P.names(raw("{}")) == ["default", "best", "round-robin", "soonest-reset", "sticky", "drain-first"] : List<&2, String>}:
  {==}

# ---- which profile a run uses
def r_none() -> {P.resolve(raw("{}"), None{}) == P.RNone{} : P.Res}:
  {==}

def r_active() -> {P.resolve(night(), None{}) == P.ROk{night_prof()} : P.Res}:
  {==}

def r_override_wins() -> {P.resolve(night(), Some{"best"}) == P.ROk{bare("best", SF.ABest{})} : P.Res}:
  {==}

def r_unknown_active() -> {P.resolve(raw("{\"active_profile\": \"gone\"}"), None{}) == P.RUnknown{"gone"} : P.Res}:
  {==}

def r_empty_active_is_none() -> {P.resolve(raw("{\"active_profile\": \"\"}"), None{}) == P.RNone{} : P.Res}:
  {==}

# ---- over the settings (threshold, interval, cooldown, hysteresis, strategy, include-api, unhealthy, models)
def base_cfg() -> Cfg.Cfg:
  Cfg.Cfg{8000, 120, 300, 1000, "best", False{}, 3, ["fable"]}

def o_all_keys() -> {P.with_prof(base_cfg(), night_prof()) == Cfg.Cfg{9500, 30, 60, 1000, "drain-first", False{}, 3, ["opus"]} : Cfg.Cfg}:
  {==}

def o_inherits() -> {P.with_prof(base_cfg(), bare("round-robin", SF.ARoundRobin{})) == Cfg.Cfg{8000, 120, 300, 1000, "round-robin", False{}, 3, ["fable"]} : Cfg.Cfg}:
  {==}

# best keeps the engine strategy of the settings.
def o_best_keeps_consume_first() -> {P.with_prof(Cfg.Cfg{8000, 60, 300, 1000, "consume-first", False{}, 3, []}, bare("default", SF.ABest{})) == Cfg.Cfg{8000, 60, 300, 1000, "consume-first", False{}, 3, []} : Cfg.Cfg}:
  {==}

# Out-of-range file values are clamped, as the settings are.
def o_clamps() -> {P.with_prof(base_cfg(), P.Prof{"x", SF.ABest{}, Some{"120"}, Some{""}, Some{"999999"}, Some{"1"}}) == Cfg.Cfg{9990, 15, 86400, 1000, "best", False{}, 3, []} : Cfg.Cfg}:
  {==}

# ---- profile set
def u_threshold() -> {P.update(bare("x", SF.ABest{}), "threshold", "92.5") == P.UOk{P.Prof{"x", SF.ABest{}, Some{"92.5"}, None{}, None{}, None{}}} : P.Upd}:
  {==}

def u_threshold_range() -> {P.update(bare("x", SF.ABest{}), "threshold", "120") == P.UBad{"threshold must be between 50 and 99.9"} : P.Upd}:
  {==}

def u_threshold_text() -> {P.update(bare("x", SF.ABest{}), "threshold", "high") == P.UBad{"threshold expects a number, got 'high'"} : P.Upd}:
  {==}

def u_inherit() -> {P.update(night_prof(), "threshold", "inherit") == P.UOk{P.Prof{"night", SF.ADrainFirst{}, None{}, Some{"opus"}, Some{"60.0"}, Some{"30.0"}}} : P.Upd}:
  {==}

def u_strategy() -> {P.update(bare("x", SF.ABest{}), "strategy", "sticky") == P.UOk{bare("x", SF.ASticky{})} : P.Upd}:
  {==}

def u_strategy_bad() -> {P.update(bare("x", SF.ABest{}), "strategy", "fastest") == P.UBad{"strategy must be one of: best, round-robin, soonest-reset, sticky, drain-first"} : P.Upd}:
  {==}

def u_models() -> {P.update(bare("x", SF.ABest{}), "models", " Opus , fable,OPUS") == P.UOk{P.Prof{"x", SF.ABest{}, None{}, Some{"Opus,fable"}, None{}, None{}}} : P.Upd}:
  {==}

def u_models_empty() -> {P.update(bare("x", SF.ABest{}), "models", "") == P.UOk{P.Prof{"x", SF.ABest{}, None{}, Some{""}, None{}, None{}}} : P.Upd}:
  {==}

def u_cooldown_range() -> {P.update(bare("x", SF.ABest{}), "cooldown_s", "-5") == P.UBad{"cooldown_s must be between 0 and 86400"} : P.Upd}:
  {==}

def u_interval_range() -> {P.update(bare("x", SF.ABest{}), "interval_s", "5") == P.UBad{"interval_s must be between 15 and 3600"} : P.Upd}:
  {==}

def u_unknown_key() -> {P.update(bare("x", SF.ABest{}), "color", "red") == P.UBad{"unknown profile key 'color'; valid keys: strategy, threshold, models, cooldown_s, interval_s"} : P.Upd}:
  {==}

# ---- writes keep what they do not own
def w_store_new() -> {Json.emit_py(P.store(raw("{\"autoswitch\": {\"threshold\": 80}, \"zzz\": true}"), night_prof())) == "{\"autoswitch\": {\"threshold\": 80}, \"zzz\": true, \"schemaVersion\": 1, \"profiles\": {\"night\": {\"strategy\": \"drain-first\", \"threshold\": 95.0, \"models\": [\"opus\"], \"cooldown_s\": 60.0, \"interval_s\": 30.0}}}" : String}:
  {==}

# An existing profile is updated in place; its unknown keys survive.
def w_store_update() -> {Json.emit_py(P.store(night(), P.Prof{"night", SF.ASticky{}, Some{"95.0"}, Some{"opus"}, Some{"60.0"}, Some{"30.0"}})) == "{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 80}, \"profiles\": {\"night\": {\"strategy\": \"sticky\", \"threshold\": 95.0, \"models\": [\"opus\"], \"cooldown_s\": 60.0, \"interval_s\": 30.0, \"note\": \"x\"}, \"sticky\": {\"threshold\": 70}}, \"active_profile\": \"night\", \"extra\": [1]}" : String}:
  {==}

def w_remove_active() -> {Json.emit_py(P.remove(night(), "night")) == "{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 80}, \"profiles\": {\"sticky\": {\"threshold\": 70}}, \"extra\": [1]}" : String}:
  {==}

def w_remove_last_drops_profiles() -> {Json.emit_py(P.remove(raw("{\"profiles\": {\"a\": {\"strategy\": \"best\"}}, \"k\": 1}"), "a")) == "{\"k\": 1}" : String}:
  {==}

def w_remove_other_keeps_active() -> {Json.emit_py(P.remove(night(), "sticky")) == "{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 80}, \"profiles\": {\"night\": {\"strategy\": \"drain-first\", \"threshold\": 95.0, \"models\": [\"opus\"], \"cooldown_s\": 60.0, \"interval_s\": 30.0, \"note\": \"x\"}}, \"active_profile\": \"night\", \"extra\": [1]}" : String}:
  {==}

def w_use() -> {Json.emit_py(P.use(raw("{\"k\": 1}"), "best")) == "{\"k\": 1, \"schemaVersion\": 1, \"active_profile\": \"best\"}" : String}:
  {==}

# ---- names
def v_ok() -> {P.valid_name("night-2_x") == True{} : Bool}:
  {==}

def v_empty() -> {P.valid_name("") == False{} : Bool}:
  {==}

def v_flag_like() -> {P.valid_name("--clear") == False{} : Bool}:
  {==}

def v_space() -> {P.valid_name("a b") == False{} : Bool}:
  {==}
