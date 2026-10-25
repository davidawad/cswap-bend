import Base
import ../src/setload.bend as Setload
import ../src/setwrite.bend as Setwrite
import ../src/setcmd.bend as Setcmd
import ../src/settings.bend as Settings
import ../src/json.bend as Json
import ../src/cmd.bend as Cmd

# Ground equations for the pure parts of src/settings.bend: decimals as text,
# clamping, the lenient load, key parsing and strict values, set/unset on JSON
# values, the text and JSON the config verbs print (fixture 32), and argv.

def j(s: String) -> Json.Json:
  Json.unwrap(Json.parse(s))

def sp2(r: Result<&2, &2, String, Settings.Spec>) -> Settings.Spec:
  match r:
    case Done{s}:
      s
    case Fail{e}:
      Settings.Spec{"", "", Settings.KBool{}, "", "", "", Json.JNull{}}

def sp(key: String) -> Settings.Spec:
  sp2(Settings.spec_of(key))

def cooked(s: String) -> String:
  Json.emit_py(Setload.normalize(j(s)))

# ---- decimals: Python's float repr from text --------------------------------

def repr_int() -> {Settings.repr(Settings.lit("85")) == "85.0" : String}:
  {==}

def repr_trim() -> {Settings.repr(Settings.lit("85.50")) == "85.5" : String}:
  {==}

def repr_exp() -> {Settings.repr(Settings.lit("8.5e1")) == "85.0" : String}:
  {==}

def repr_lead_point() -> {Settings.repr(Settings.lit(".5e2")) == "50.0" : String}:
  {==}

def repr_zeros() -> {Settings.repr(Settings.lit("0085.0")) == "85.0" : String}:
  {==}

def repr_small() -> {Settings.repr(Settings.lit("0.0001")) == "0.0001" : String}:
  {==}

def repr_tiny() -> {Settings.repr(Settings.lit("0.00001")) == "1e-05" : String}:
  {==}

def repr_tiny_digits() -> {Settings.repr(Settings.lit("1.5e-5")) == "1.5e-05" : String}:
  {==}

def repr_neg_zero() -> {Settings.repr(Settings.lit("-0")) == "-0.0" : String}:
  {==}

def fmt_whole() -> {Settings.fmt(Settings.lit("85.0")) == "85" : String}:
  {==}

def fmt_frac() -> {Settings.fmt(Settings.lit("99.9")) == "99.9" : String}:
  {==}

def fmt_neg_zero() -> {Settings.fmt(Settings.lit("-0")) == "0" : String}:
  {==}

def num_bad_word() -> {Settings.num("abc") == None{} : Maybe<&2, Settings.Dec>}:
  {==}

def num_bad_empty() -> {Settings.num("") == None{} : Maybe<&2, Settings.Dec>}:
  {==}

def num_bad_point() -> {Settings.num(".") == None{} : Maybe<&2, Settings.Dec>}:
  {==}

def num_bad_exp() -> {Settings.num("85e") == None{} : Maybe<&2, Settings.Dec>}:
  {==}

def num_bad_two_exp() -> {Settings.num("1e2e3") == None{} : Maybe<&2, Settings.Dec>}:
  {==}

def num_spaces() -> {Settings.repr(Settings.lit(" 85 ")) == "85.0" : String}:
  {==}

def num_plus() -> {Settings.repr(Settings.lit("+85")) == "85.0" : String}:
  {==}

def tenths_frac() -> {Settings.tenths("99.9") == 999 : U32}:
  {==}

def tenths_whole() -> {Settings.tenths("85.0") == 850 : U32}:
  {==}

def tenths_floor() -> {Settings.tenths("0.99") == 9 : U32}:
  {==}

# ---- clamping (CLI overrides use the same bounds) ------------------------------

def clamp_threshold_high() -> {Setload.clamp_threshold("120") == Some{"99.9"} : Maybe<&2, String>}:
  {==}

def clamp_threshold_low() -> {Setload.clamp_threshold("49.99") == Some{"50.0"} : Maybe<&2, String>}:
  {==}

def clamp_threshold_in() -> {Setload.clamp_threshold("85") == Some{"85.0"} : Maybe<&2, String>}:
  {==}

def clamp_threshold_edge() -> {Setload.clamp_threshold("99.9") == Some{"99.9"} : Maybe<&2, String>}:
  {==}

def clamp_threshold_just_over() -> {Setload.clamp_threshold("99.91") == Some{"99.9"} : Maybe<&2, String>}:
  {==}

def clamp_threshold_negative() -> {Setload.clamp_threshold("-5") == Some{"50.0"} : Maybe<&2, String>}:
  {==}

def clamp_threshold_huge() -> {Setload.clamp_threshold("1e999") == Some{"99.9"} : Maybe<&2, String>}:
  {==}

def clamp_threshold_junk() -> {Setload.clamp_threshold("abc") == None{} : Maybe<&2, String>}:
  {==}

def clamp_interval_low() -> {Setload.clamp_interval("5") == Some{"15.0"} : Maybe<&2, String>}:
  {==}

def clamp_interval_high() -> {Setload.clamp_interval("5000") == Some{"3600.0"} : Maybe<&2, String>}:
  {==}

def clamp_interval_frac() -> {Setload.clamp_interval("60.25") == Some{"60.25"} : Maybe<&2, String>}:
  {==}

def clamp_cooldown_neg() -> {Setload.clamp_cooldown("-4") == Some{"0.0"} : Maybe<&2, String>}:
  {==}

def clamp_cooldown_high() -> {Setload.clamp_cooldown("86400.5") == Some{"86400.0"} : Maybe<&2, String>}:
  {==}

def clamp_hysteresis_high() -> {Setload.clamp_hysteresis("99") == Some{"50.0"} : Maybe<&2, String>}:
  {==}

def clamp_strategy_ok() -> {Setload.clamp_strategy("consume-first") == "consume-first" : String}:
  {==}

def clamp_strategy_bad() -> {Setload.clamp_strategy("nope") == "best" : String}:
  {==}

def models_split() -> {Setload.model_names("Fable, opus,FABLE,,Opus ") == ["Fable", "opus"] : List<&2, String>}:
  {==}

def models_all() -> {Setload.model_names("all") == ["all"] : List<&2, String>}:
  {==}

def models_empty() -> {Setload.model_names("") == [] : List<&2, String>}:
  {==}

def models_commas() -> {Setload.model_names(" , ,") == [] : List<&2, String>}:
  {==}

# ---- lenient load -----------------------------------------------------------------

def defaults() -> {cooked("{}") == "{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 90.0, \"intervalSeconds\": 60.0, \"cooldownSeconds\": 300.0, \"hysteresisPct\": 10.0, \"strategy\": \"best\", \"includeApiKeyAccounts\": false, \"unhealthyTicks\": 3, \"model\": null}, \"ui\": {\"theme\": \"auto\"}}" : String}:
  {==}

def not_object_is_defaults() -> {cooked("[1, 2]") == cooked("{}") : String}:
  {==}

def section_not_object() -> {Setload.threshold(Setload.normalize(j("{\"autoswitch\": 4}"))) == "90.0" : String}:
  {==}

def clamps_high() -> {Setload.threshold(Setload.normalize(j("{\"autoswitch\": {\"threshold\": 120}}"))) == "99.9" : String}:
  {==}

def clamps_low() -> {Setload.interval_seconds(Setload.normalize(j("{\"autoswitch\": {\"intervalSeconds\": 5}}"))) == "15.0" : String}:
  {==}

def clamps_negative() -> {Setload.cooldown_seconds(Setload.normalize(j("{\"autoswitch\": {\"cooldownSeconds\": -4}}"))) == "0.0" : String}:
  {==}

def clamps_hysteresis() -> {Setload.hysteresis_pct(Setload.normalize(j("{\"autoswitch\": {\"hysteresisPct\": 99}}"))) == "50.0" : String}:
  {==}

def keeps_in_range() -> {Setload.threshold(Setload.normalize(j("{\"autoswitch\": {\"threshold\": 85}}"))) == "85.0" : String}:
  {==}

def exponent_number() -> {Setload.interval_seconds(Setload.normalize(j("{\"autoswitch\": {\"intervalSeconds\": 1e2}}"))) == "100.0" : String}:
  {==}

def bool_number_is_default() -> {Setload.threshold(Setload.normalize(j("{\"autoswitch\": {\"threshold\": true}}"))) == "90.0" : String}:
  {==}

def string_number_is_default() -> {Setload.interval_seconds(Setload.normalize(j("{\"autoswitch\": {\"intervalSeconds\": \"60\"}}"))) == "60.0" : String}:
  {==}

def null_number_is_default() -> {Setload.cooldown_seconds(Setload.normalize(j("{\"autoswitch\": {\"cooldownSeconds\": null}}"))) == "300.0" : String}:
  {==}

def ticks_truncate() -> {Setload.unhealthy_ticks(Setload.normalize(j("{\"autoswitch\": {\"unhealthyTicks\": 3.7}}"))) == 3 : U32}:
  {==}

def ticks_clamp_high() -> {Setload.unhealthy_ticks(Setload.normalize(j("{\"autoswitch\": {\"unhealthyTicks\": 1000}}"))) == 100 : U32}:
  {==}

def ticks_clamp_low() -> {Setload.unhealthy_ticks(Setload.normalize(j("{\"autoswitch\": {\"unhealthyTicks\": 0.5}}"))) == 1 : U32}:
  {==}

def strategy_unknown_is_default() -> {Setload.strategy(Setload.normalize(j("{\"autoswitch\": {\"strategy\": \"wat\"}}"))) == "best" : String}:
  {==}

def strategy_not_string_is_default() -> {Setload.strategy(Setload.normalize(j("{\"autoswitch\": {\"strategy\": 5}}"))) == "best" : String}:
  {==}

def strategy_consume_first() -> {Setload.strategy(Setload.normalize(j("{\"autoswitch\": {\"strategy\": \"consume-first\"}}"))) == "consume-first" : String}:
  {==}

def bool_string_false_is_true() -> {Setload.include_api_key_accounts(Setload.normalize(j("{\"autoswitch\": {\"includeApiKeyAccounts\": \"false\"}}"))) == True{} : Bool}:
  {==}

def bool_zero_is_false() -> {Setload.include_api_key_accounts(Setload.normalize(j("{\"autoswitch\": {\"includeApiKeyAccounts\": 0}}"))) == False{} : Bool}:
  {==}

def bool_list_is_true() -> {Setload.include_api_key_accounts(Setload.normalize(j("{\"autoswitch\": {\"includeApiKeyAccounts\": [1]}}"))) == True{} : Bool}:
  {==}

def bool_empty_object_is_false() -> {Setload.include_api_key_accounts(Setload.normalize(j("{\"autoswitch\": {\"includeApiKeyAccounts\": {}}}"))) == False{} : Bool}:
  {==}

def model_list() -> {Setload.model(Setload.normalize(j("{\"autoswitch\": {\"model\": \"Fable,Opus\"}}"))) == ["Fable", "Opus"] : List<&2, String>}:
  {==}

def model_empty_string_is_none() -> {Setload.model(Setload.normalize(j("{\"autoswitch\": {\"model\": \"\"}}"))) == [] : List<&2, String>}:
  {==}

def model_number_is_none() -> {Setload.model(Setload.normalize(j("{\"autoswitch\": {\"model\": 5}}"))) == [] : List<&2, String>}:
  {==}

def theme_unknown_is_default() -> {Json.get("ui", Setload.normalize(j("{\"ui\": {\"theme\": \"pink\"}}"))) == Some{j("{\"theme\": \"auto\"}")} : Maybe<&2, Json.Json>}:
  {==}

def theme_kept() -> {Json.get("ui", Setload.normalize(j("{\"ui\": {\"theme\": \"dark\"}}"))) == Some{j("{\"theme\": \"dark\"}")} : Maybe<&2, Json.Json>}:
  {==}

def unknown_keys_survive() -> {Json.get("extra", Setload.normalize(j("{\"extra\": {\"a\": [1, null]}, \"autoswitch\": {\"x\": 1}}"))) == Some{j("{\"a\": [1, null]}")} : Maybe<&2, Json.Json>}:
  {==}

def unknown_key_in_section_survives() -> {Json.get("x", Setload.section_of(Setload.normalize(j("{\"autoswitch\": {\"x\": 1}}")), "autoswitch")) == Some{j("1")} : Maybe<&2, Json.Json>}:
  {==}

def version_kept() -> {Json.get("schemaVersion", Setload.normalize(j("{\"schemaVersion\": 7}"))) == Some{j("7")} : Maybe<&2, Json.Json>}:
  {==}

def tenths_of_loaded() -> {Setload.threshold_tenths(Setload.normalize(j("{\"autoswitch\": {\"threshold\": 85.5}}"))) == 855 : U32}:
  {==}

def tenths_of_default_interval() -> {Setload.interval_tenths(Setload.normalize(j("{}"))) == 600 : U32}:
  {==}

# ---- key parsing -----------------------------------------------------------------

def key_known() -> {Settings.dotted(sp("autoswitch.intervalSeconds")) == "autoswitch.intervalSeconds" : String}:
  {==}

def key_ui() -> {Settings.dotted(sp("ui.theme")) == "ui.theme" : String}:
  {==}

def key_unknown() -> {Settings.spec_of("autoswitch.nope") == Fail{"unknown setting 'autoswitch.nope'\nValid keys: autoswitch.threshold, autoswitch.intervalSeconds, autoswitch.cooldownSeconds, autoswitch.hysteresisPct, autoswitch.strategy, autoswitch.includeApiKeyAccounts, autoswitch.unhealthyTicks, autoswitch.model, ui.theme"} : Result<&2, &2, String, Settings.Spec>}:
  {==}

def key_is_case_sensitive() -> {Settings.dotted(sp("autoswitch.Threshold")) == "." : String}:
  {==}

# ---- strict values -----------------------------------------------------------------

def parse_float_int() -> {Setwrite.parse_value(sp("autoswitch.threshold"), "85") == Setwrite.Good{Json.JNum{"85.0"}} : Setwrite.Parsed}:
  {==}

def parse_float_trims() -> {Setwrite.parse_value(sp("autoswitch.threshold"), "85.50") == Setwrite.Good{Json.JNum{"85.5"}} : Setwrite.Parsed}:
  {==}

def parse_float_spaces() -> {Setwrite.parse_value(sp("autoswitch.threshold"), " 85 ") == Setwrite.Good{Json.JNum{"85.0"}} : Setwrite.Parsed}:
  {==}

def parse_float_exp() -> {Setwrite.parse_value(sp("autoswitch.threshold"), "8.5e1") == Setwrite.Good{Json.JNum{"85.0"}} : Setwrite.Parsed}:
  {==}

def parse_float_edges() -> {Setwrite.parse_value(sp("autoswitch.threshold"), "99.9") == Setwrite.Good{Json.JNum{"99.9"}} : Setwrite.Parsed}:
  {==}

def parse_float_too_high() -> {Setwrite.parse_value(sp("autoswitch.threshold"), "120") == Setwrite.Bad{"autoswitch.threshold must be between 50 and 99.9"} : Setwrite.Parsed}:
  {==}

def parse_float_too_low() -> {Setwrite.parse_value(sp("autoswitch.threshold"), "49.99") == Setwrite.Bad{"autoswitch.threshold must be between 50 and 99.9"} : Setwrite.Parsed}:
  {==}

def parse_float_inf() -> {Setwrite.parse_value(sp("autoswitch.threshold"), "inf") == Setwrite.Bad{"autoswitch.threshold must be between 50 and 99.9"} : Setwrite.Parsed}:
  {==}

def parse_float_nan() -> {Setwrite.parse_value(sp("autoswitch.threshold"), "NaN") == Setwrite.Bad{"autoswitch.threshold must be between 50 and 99.9"} : Setwrite.Parsed}:
  {==}

def parse_float_word() -> {Setwrite.parse_value(sp("autoswitch.threshold"), "abc") == Setwrite.Bad{"autoswitch.threshold expects a number, got 'abc'"} : Setwrite.Parsed}:
  {==}

def parse_float_empty() -> {Setwrite.parse_value(sp("autoswitch.threshold"), "") == Setwrite.Bad{"autoswitch.threshold expects a number, got ''"} : Setwrite.Parsed}:
  {==}

def parse_cooldown_zero() -> {Setwrite.parse_value(sp("autoswitch.cooldownSeconds"), "0") == Setwrite.Good{Json.JNum{"0.0"}} : Setwrite.Parsed}:
  {==}

def parse_cooldown_tiny() -> {Setwrite.parse_value(sp("autoswitch.cooldownSeconds"), "0.00001") == Setwrite.Good{Json.JNum{"1e-05"}} : Setwrite.Parsed}:
  {==}

def parse_cooldown_negative() -> {Setwrite.parse_value(sp("autoswitch.cooldownSeconds"), "-1") == Setwrite.Bad{"autoswitch.cooldownSeconds must be between 0 and 86400"} : Setwrite.Parsed}:
  {==}

def parse_int() -> {Setwrite.parse_value(sp("autoswitch.unhealthyTicks"), "7") == Setwrite.Good{Json.JNum{"7"}} : Setwrite.Parsed}:
  {==}

def parse_int_plus_zeros() -> {Setwrite.parse_value(sp("autoswitch.unhealthyTicks"), " +007 ") == Setwrite.Good{Json.JNum{"7"}} : Setwrite.Parsed}:
  {==}

def parse_int_float_text() -> {Setwrite.parse_value(sp("autoswitch.unhealthyTicks"), "3.0") == Setwrite.Bad{"autoswitch.unhealthyTicks expects an integer, got '3.0'"} : Setwrite.Parsed}:
  {==}

def parse_int_zero() -> {Setwrite.parse_value(sp("autoswitch.unhealthyTicks"), "0") == Setwrite.Bad{"autoswitch.unhealthyTicks must be between 1 and 100"} : Setwrite.Parsed}:
  {==}

def parse_int_high() -> {Setwrite.parse_value(sp("autoswitch.unhealthyTicks"), "101") == Setwrite.Bad{"autoswitch.unhealthyTicks must be between 1 and 100"} : Setwrite.Parsed}:
  {==}

def parse_bool_true() -> {Setwrite.parse_value(sp("autoswitch.includeApiKeyAccounts"), "TRUE") == Setwrite.Good{Json.JBool{True{}}} : Setwrite.Parsed}:
  {==}

def parse_bool_yes() -> {Setwrite.parse_value(sp("autoswitch.includeApiKeyAccounts"), "yes") == Setwrite.Good{Json.JBool{True{}}} : Setwrite.Parsed}:
  {==}

def parse_bool_one() -> {Setwrite.parse_value(sp("autoswitch.includeApiKeyAccounts"), "1") == Setwrite.Good{Json.JBool{True{}}} : Setwrite.Parsed}:
  {==}

def parse_bool_false() -> {Setwrite.parse_value(sp("autoswitch.includeApiKeyAccounts"), " False ") == Setwrite.Good{Json.JBool{False{}}} : Setwrite.Parsed}:
  {==}

def parse_bool_zero() -> {Setwrite.parse_value(sp("autoswitch.includeApiKeyAccounts"), "0") == Setwrite.Good{Json.JBool{False{}}} : Setwrite.Parsed}:
  {==}

def parse_bool_no() -> {Setwrite.parse_value(sp("autoswitch.includeApiKeyAccounts"), "no") == Setwrite.Good{Json.JBool{False{}}} : Setwrite.Parsed}:
  {==}

def parse_bool_maybe() -> {Setwrite.parse_value(sp("autoswitch.includeApiKeyAccounts"), "maybe") == Setwrite.Bad{"autoswitch.includeApiKeyAccounts expects true or false (or 1/0, yes/no), got 'maybe'"} : Setwrite.Parsed}:
  {==}

def parse_choice() -> {Setwrite.parse_value(sp("autoswitch.strategy"), "consume-first") == Setwrite.Good{Json.JStr{"consume-first"}} : Setwrite.Parsed}:
  {==}

def parse_choice_case() -> {Setwrite.parse_value(sp("autoswitch.strategy"), "Best") == Setwrite.Bad{"autoswitch.strategy must be one of: best, consume-first"} : Setwrite.Parsed}:
  {==}

def parse_choice_space() -> {Setwrite.parse_value(sp("autoswitch.strategy"), "best ") == Setwrite.Bad{"autoswitch.strategy must be one of: best, consume-first"} : Setwrite.Parsed}:
  {==}

def parse_theme_bad() -> {Setwrite.parse_value(sp("ui.theme"), "blue") == Setwrite.Bad{"ui.theme must be one of: dark, light, auto"} : Setwrite.Parsed}:
  {==}

def parse_model() -> {Setwrite.parse_value(sp("autoswitch.model"), " Fable,Opus ") == Setwrite.Good{Json.JStr{"Fable,Opus"}} : Setwrite.Parsed}:
  {==}

def parse_model_empty() -> {Setwrite.parse_value(sp("autoswitch.model"), "   ") == Setwrite.Bad{"autoswitch.model expects a non-empty value; use 'cswap config unset autoswitch.model' to clear it"} : Setwrite.Parsed}:
  {==}

# ---- set / unset on JSON values ------------------------------------------------------

def set_fresh() -> {Json.emit_py(Setwrite.set_in(j("{}"), sp("autoswitch.threshold"), Json.JNum{"85.0"})) == "{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 85.0}}" : String}:
  {==}

def set_fixture_step_1_file() -> {Json.emit_pretty(Setwrite.set_in(j("{}"), sp("autoswitch.threshold"), Json.JNum{"85.0"})) == "{\n  \"schemaVersion\": 1,\n  \"autoswitch\": {\n    \"threshold\": 85.0\n  }\n}" : String}:
  {==}

def set_adds_to_section() -> {Json.emit_py(Setwrite.set_in(j("{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 85.0}}"), sp("autoswitch.strategy"), Json.JStr{"best"})) == "{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 85.0, \"strategy\": \"best\"}}" : String}:
  {==}

def set_replaces_in_place() -> {Json.emit_py(Setwrite.set_in(j("{\"autoswitch\": {\"threshold\": 85.0, \"strategy\": \"best\"}, \"schemaVersion\": 3}"), sp("autoswitch.threshold"), Json.JNum{"60.0"})) == "{\"autoswitch\": {\"threshold\": 60.0, \"strategy\": \"best\"}, \"schemaVersion\": 3}" : String}:
  {==}

def set_keeps_version() -> {Json.emit_py(Setwrite.set_in(j("{\"schemaVersion\": 9}"), sp("ui.theme"), Json.JStr{"dark"})) == "{\"schemaVersion\": 9, \"ui\": {\"theme\": \"dark\"}}" : String}:
  {==}

def set_keeps_unknown() -> {Json.emit_py(Setwrite.set_in(j("{\"extra\": [1], \"autoswitch\": {\"x\": null}}"), sp("autoswitch.unhealthyTicks"), Json.JNum{"5"})) == "{\"extra\": [1], \"autoswitch\": {\"x\": null, \"unhealthyTicks\": 5}, \"schemaVersion\": 1}" : String}:
  {==}

def set_replaces_non_object_section() -> {Json.emit_py(Setwrite.set_in(j("{\"schemaVersion\": 1, \"autoswitch\": 4}"), sp("autoswitch.threshold"), Json.JNum{"85.0"})) == "{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 85.0}}" : String}:
  {==}

def set_writes_only_touched_key() -> {Json.emit_py(Setwrite.set_in(j("{}"), sp("ui.theme"), Json.JStr{"light"})) == "{\"schemaVersion\": 1, \"ui\": {\"theme\": \"light\"}}" : String}:
  {==}

def unset_key() -> {Json.emit_py(Setwrite.unset_in(j("{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 85.0, \"strategy\": \"best\"}}"), sp("autoswitch.strategy"))) == "{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 85.0}}" : String}:
  {==}

def unset_fixture_step_6_file() -> {Json.emit_pretty(Setwrite.unset_in(j("{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 85.0, \"strategy\": \"best\"}}"), sp("autoswitch.strategy"))) == "{\n  \"schemaVersion\": 1,\n  \"autoswitch\": {\n    \"threshold\": 85.0\n  }\n}" : String}:
  {==}

def unset_last_key_drops_section() -> {Json.emit_py(Setwrite.unset_in(j("{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 85.0}}"), sp("autoswitch.threshold"))) == "{\"schemaVersion\": 1}" : String}:
  {==}

def unset_keeps_other_sections() -> {Json.emit_py(Setwrite.unset_in(j("{\"schemaVersion\": 1, \"ui\": {\"theme\": \"dark\"}, \"autoswitch\": {\"threshold\": 85.0}}"), sp("autoswitch.threshold"))) == "{\"schemaVersion\": 1, \"ui\": {\"theme\": \"dark\"}}" : String}:
  {==}

def unset_keeps_unknown_in_section() -> {Json.emit_py(Setwrite.unset_in(j("{\"autoswitch\": {\"threshold\": 85.0, \"x\": 1}}"), sp("autoswitch.threshold"))) == "{\"autoswitch\": {\"x\": 1}, \"schemaVersion\": 1}" : String}:
  {==}

def is_set_true() -> {Setwrite.is_set(j("{\"autoswitch\": {\"threshold\": 90.0}}"), sp("autoswitch.threshold")) == True{} : Bool}:
  {==}

def is_set_false() -> {Setwrite.is_set(j("{\"autoswitch\": {\"threshold\": 90.0}}"), sp("autoswitch.strategy")) == False{} : Bool}:
  {==}

def is_set_no_section() -> {Setwrite.is_set(j("{}"), sp("ui.theme")) == False{} : Bool}:
  {==}

def is_set_section_not_object() -> {Setwrite.is_set(j("{\"ui\": 5}"), sp("ui.theme")) == False{} : Bool}:
  {==}

# ---- what the verbs print (fixture 32) --------------------------------------------------

def step3_get_json() -> {Setcmd.get.spec(True{}, Settings.spec_of("autoswitch.threshold"), j("{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 85.0, \"strategy\": \"best\"}}")) == Cmd.Out{0, "{\n  \"schemaVersion\": 1,\n  \"key\": \"autoswitch.threshold\",\n  \"value\": 85.0,\n  \"isSet\": true\n}\n", ""} : Cmd.Out}:
  {==}

def get_text_whole_float() -> {Setcmd.get.spec(False{}, Settings.spec_of("autoswitch.threshold"), j("{\"autoswitch\": {\"threshold\": 85.0}}")) == Cmd.Out{0, "85\n", ""} : Cmd.Out}:
  {==}

def get_text_default() -> {Setcmd.get.spec(False{}, Settings.spec_of("autoswitch.model"), j("{}")) == Cmd.Out{0, "(none)\n", ""} : Cmd.Out}:
  {==}

def get_json_default_not_set() -> {Setcmd.get.spec(True{}, Settings.spec_of("ui.theme"), j("{}")) == Cmd.Out{0, "{\n  \"schemaVersion\": 1,\n  \"key\": \"ui.theme\",\n  \"value\": \"auto\",\n  \"isSet\": false\n}\n", ""} : Cmd.Out}:
  {==}

def get_unknown_key_text() -> {Setcmd.get.spec(False{}, Settings.spec_of("nope"), j("{}")) == Cmd.fail("unknown setting 'nope'\nValid keys: autoswitch.threshold, autoswitch.intervalSeconds, autoswitch.cooldownSeconds, autoswitch.hysteresisPct, autoswitch.strategy, autoswitch.includeApiKeyAccounts, autoswitch.unhealthyTicks, autoswitch.model, ui.theme") : Cmd.Out}:
  {==}

def get_unknown_key_json() -> {Setcmd.get.spec(True{}, Settings.spec_of("nope"), j("{}")) == Cmd.json_fail("ConfigError", "unknown setting 'nope'\nValid keys: autoswitch.threshold, autoswitch.intervalSeconds, autoswitch.cooldownSeconds, autoswitch.hysteresisPct, autoswitch.strategy, autoswitch.includeApiKeyAccounts, autoswitch.unhealthyTicks, autoswitch.model, ui.theme") : Cmd.Out}:
  {==}

def step4_list_json() -> {Setcmd.list.out("/h/.claude-swap-backup", True{}, j("{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 85.0, \"strategy\": \"best\"}}")) == Cmd.Out{0, "{\n  \"schemaVersion\": 1,\n  \"path\": \"/h/.claude-swap-backup/settings.json\",\n  \"settings\": [\n    {\n      \"key\": \"autoswitch.threshold\",\n      \"value\": 85.0,\n      \"isSet\": true\n    },\n    {\n      \"key\": \"autoswitch.intervalSeconds\",\n      \"value\": 60.0,\n      \"isSet\": false\n    },\n    {\n      \"key\": \"autoswitch.cooldownSeconds\",\n      \"value\": 300.0,\n      \"isSet\": false\n    },\n    {\n      \"key\": \"autoswitch.hysteresisPct\",\n      \"value\": 10.0,\n      \"isSet\": false\n    },\n    {\n      \"key\": \"autoswitch.strategy\",\n      \"value\": \"best\",\n      \"isSet\": true\n    },\n    {\n      \"key\": \"autoswitch.includeApiKeyAccounts\",\n      \"value\": false,\n      \"isSet\": false\n    },\n    {\n      \"key\": \"autoswitch.unhealthyTicks\",\n      \"value\": 3,\n      \"isSet\": false\n    },\n    {\n      \"key\": \"autoswitch.model\",\n      \"value\": null,\n      \"isSet\": false\n    },\n    {\n      \"key\": \"ui.theme\",\n      \"value\": \"auto\",\n      \"isSet\": false\n    }\n  ]\n}\n", ""} : Cmd.Out}:
  {==}

def list_text() -> {Setcmd.list.out("/h/.claude-swap-backup", False{}, j("{\"schemaVersion\": 1, \"autoswitch\": {\"threshold\": 85.0, \"strategy\": \"best\"}}")) == Cmd.Out{0, "autoswitch.threshold              85    \nautoswitch.intervalSeconds        60      (default)\nautoswitch.cooldownSeconds        300     (default)\nautoswitch.hysteresisPct          10      (default)\nautoswitch.strategy               best  \nautoswitch.includeApiKeyAccounts  false   (default)\nautoswitch.unhealthyTicks         3       (default)\nautoswitch.model                  (none)  (default)\nui.theme                          auto    (default)\n", ""} : Cmd.Out}:
  {==}

def set_text_out() -> {Setwrite.fmt.val(True{}, Json.JNum{"85.0"}) == "85" : String}:
  {==}

def set_text_out_frac() -> {Setwrite.fmt.val(True{}, Json.JNum{"85.5"}) == "85.5" : String}:
  {==}

def set_text_out_int() -> {Setwrite.fmt.val(False{}, Json.JNum{"3"}) == "3" : String}:
  {==}

def set_text_out_bool() -> {Setwrite.fmt.val(False{}, Json.JBool{True{}}) == "true" : String}:
  {==}

def dflt_text_model() -> {Setwrite.fmt.val(False{}, Setcmd.dflt_of(sp("autoswitch.model"))) == "(none)" : String}:
  {==}

def dflt_text_threshold() -> {Setwrite.fmt.val(True{}, Setcmd.dflt_of(sp("autoswitch.threshold"))) == "90" : String}:
  {==}

# ---- argv ---------------------------------------------------------------------------

def plan_bare() -> {Setcmd.plan.of([]) == Setcmd.PList{} : Setcmd.Plan}:
  {==}

def plan_list() -> {Setcmd.plan.of(["list"]) == Setcmd.PList{} : Setcmd.Plan}:
  {==}

def plan_get() -> {Setcmd.plan.of(["get", "autoswitch.threshold"]) == Setcmd.PGet{"autoswitch.threshold"} : Setcmd.Plan}:
  {==}

def plan_set() -> {Setcmd.plan.of(["set", "autoswitch.threshold", "85"]) == Setcmd.PSet{"autoswitch.threshold", "85"} : Setcmd.Plan}:
  {==}

def plan_set_negative_value() -> {Setcmd.plan.of(["set", "autoswitch.cooldownSeconds", "-1"]) == Setcmd.PSet{"autoswitch.cooldownSeconds", "-1"} : Setcmd.Plan}:
  {==}

def plan_unset() -> {Setcmd.plan.of(["unset", "ui.theme"]) == Setcmd.PUnset{"ui.theme"} : Setcmd.Plan}:
  {==}

def plan_path() -> {Setcmd.plan.of(["path"]) == Setcmd.PPath{} : Setcmd.Plan}:
  {==}

def plan_get_missing_key() -> {Setcmd.plan.of(["get"]) == Setcmd.PBad{"the following arguments are required: KEY"} : Setcmd.Plan}:
  {==}

def plan_set_missing_value() -> {Setcmd.plan.of(["set", "ui.theme"]) == Setcmd.PBad{"the following arguments are required: VALUE"} : Setcmd.Plan}:
  {==}

def plan_set_missing_both() -> {Setcmd.plan.of(["set"]) == Setcmd.PBad{"the following arguments are required: KEY, VALUE"} : Setcmd.Plan}:
  {==}

def plan_extra_args() -> {Setcmd.plan.of(["get", "a", "b", "c"]) == Setcmd.PBad{"unrecognized arguments: b c"} : Setcmd.Plan}:
  {==}

def plan_list_extra() -> {Setcmd.plan.of(["list", "x"]) == Setcmd.PBad{"unrecognized arguments: x"} : Setcmd.Plan}:
  {==}

def plan_bad_verb() -> {Setcmd.plan.of(["frob"]) == Setcmd.PBad{"argument action: invalid choice: 'frob' (choose from 'list', 'get', 'set', 'unset', 'path')"} : Setcmd.Plan}:
  {==}

def plan_json_with_set() -> {Setcmd.plan.json(True{}, Setcmd.PSet{"a", "b"}) == Setcmd.PBad{"--json can only be used with list or get"} : Setcmd.Plan}:
  {==}

def plan_json_with_unset() -> {Setcmd.plan.json(True{}, Setcmd.PUnset{"a"}) == Setcmd.PBad{"--json can only be used with list or get"} : Setcmd.Plan}:
  {==}

def plan_json_with_path() -> {Setcmd.plan.json(True{}, Setcmd.PPath{}) == Setcmd.PBad{"--json can only be used with list or get"} : Setcmd.Plan}:
  {==}

def plan_json_with_get() -> {Setcmd.plan.json(True{}, Setcmd.PGet{"a"}) == Setcmd.PGet{"a"} : Setcmd.Plan}:
  {==}

def plan_text_with_set() -> {Setcmd.plan.json(False{}, Setcmd.PSet{"a", "b"}) == Setcmd.PSet{"a", "b"} : Setcmd.Plan}:
  {==}

def path_of_root() -> {Setload.path("/h/.claude-swap-backup") == "/h/.claude-swap-backup/settings.json" : String}:
  {==}
