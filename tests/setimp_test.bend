import Base
import ../src/json.bend as J
import ../src/setimp.bend as Imp

# Ground equations for the pure half of config/profile import.

def res_str(r: Result<&2, &2, String, String>) -> String:
  match r:
    case Done{s}:
      s
    case Fail{m}:
      "!" ++ m

def fmt_of(explicit: Maybe<&2, String>, path: String) -> String:
  res_str(Imp.pick_format(explicit, path))

def f_json() -> {fmt_of(None{}, "a/b/settings.json") == "json" : String}:
  {==}

def f_yaml() -> {fmt_of(None{}, "s.yaml") == "yaml" : String}:
  {==}

def f_yml_upper() -> {fmt_of(None{}, "S.YML") == "yaml" : String}:
  {==}

def f_toon() -> {fmt_of(None{}, "s.toon") == "toon" : String}:
  {==}

def f_csv() -> {fmt_of(None{}, "s.csv") == "csv" : String}:
  {==}

def f_explicit_wins() -> {fmt_of(Some{"yml"}, "s.json") == "yaml" : String}:
  {==}

def f_unknown_ext() -> {fmt_of(None{}, "settings") == "!cannot tell the format of 'settings' from its extension; pass --format json|yaml|toon|csv" : String}:
  {==}

def f_bad_name() -> {fmt_of(Some{"xml"}, "s.json") == "!unknown format 'xml' (json, yaml, toon, csv)" : String}:
  {==}

# ---- parse_doc -------------------------------------------------------------------

def doc.of(r: Result<&2, &2, String, J.Json>) -> String:
  match r:
    case Done{j}:
      J.emit(j)
    case Fail{m}:
      "!" ++ m

def doc(f: String, t: String) -> String:
  doc.of(Imp.parse_doc(f, t))

def p_json() -> {doc("json", "{\"autoswitch\":{\"threshold\":85}}") == "{\"autoswitch\":{\"threshold\":85}}" : String}:
  {==}

def p_yaml() -> {doc("yaml", "autoswitch:\n  threshold: 85\nprofiles:\n  night:\n    models: [opus, sonnet]\n") == "{\"autoswitch\":{\"threshold\":85},\"profiles\":{\"night\":{\"models\":[\"opus\",\"sonnet\"]}}}" : String}:
  {==}

def p_toon() -> {doc("toon", "autoswitch:\n  threshold: 85\nx: 1") == "{\"autoswitch\":{\"threshold\":85},\"x\":1}" : String}:
  {==}

def p_csv() -> {doc("csv", "key,value\nautoswitch.threshold,85\nautoswitch.model,\"opus,sonnet\"\nprofiles.night.threshold,95\nextra,{}\nflag,true\n") == "{\"autoswitch\":{\"threshold\":85,\"model\":\"opus,sonnet\"},\"profiles\":{\"night\":{\"threshold\":95}},\"extra\":{},\"flag\":true}" : String}:
  {==}

def p_csv_no_header() -> {doc("csv", "autoswitch.threshold,85\n") == "!a csv settings file starts with the header key,value" : String}:
  {==}

def p_csv_bad_row() -> {doc("csv", "key,value\na,b,c\n") == "!every csv row must be key,value" : String}:
  {==}

def p_not_mapping() -> {doc("json", "[1,2]") == "!the settings document must be a mapping of keys to values" : String}:
  {==}

# ---- normalize ------------------------------------------------------------------------

def norm.of(r: Result<&2, &2, String, J.Json>) -> String:
  match r:
    case Done{j}:
      J.emit(j)
    case Fail{m}:
      "!" ++ m

def norm(js: String) -> String:
  norm.of(Imp.normalize(J.unwrap(J.parse(js))))

def n_known_ok() -> {norm("{\"autoswitch\":{\"threshold\":85,\"strategy\":\"best\",\"includeApiKeyAccounts\":true,\"model\":[\"opus\",\"sonnet\"]},\"ui\":{\"theme\":\"dark\"}}") == "{\"autoswitch\":{\"threshold\":85.0,\"strategy\":\"best\",\"includeApiKeyAccounts\":true,\"model\":\"opus,sonnet\"},\"ui\":{\"theme\":\"dark\"}}" : String}:
  {==}

def n_strings_become_typed() -> {norm("{\"autoswitch\":{\"threshold\":\"85\",\"includeApiKeyAccounts\":\"yes\"}}") == "{\"autoswitch\":{\"threshold\":85.0,\"includeApiKeyAccounts\":true}}" : String}:
  {==}

def n_unknown_preserved() -> {norm("{\"zzz\":{\"a\":[1,2]},\"autoswitch\":{\"future\":1,\"threshold\":60},\"version\":3}") == "{\"zzz\":{\"a\":[1,2]},\"autoswitch\":{\"future\":1,\"threshold\":60.0},\"version\":3}" : String}:
  {==}

def n_threshold_range() -> {norm("{\"autoswitch\":{\"threshold\":10}}") == "!autoswitch.threshold must be between 50 and 99.9" : String}:
  {==}

def n_bad_choice() -> {norm("{\"ui\":{\"theme\":\"disco\"}}") == "!ui.theme must be one of: dark, light, auto" : String}:
  {==}

def n_null_is_unset() -> {norm("{\"autoswitch\":{\"threshold\":null}}") == "{\"autoswitch\":{\"threshold\":null}}" : String}:
  {==}

def n_section_not_map() -> {norm("{\"autoswitch\":5}") == "!autoswitch must be a mapping of settings" : String}:
  {==}

def n_profile_ok() -> {norm("{\"profiles\":{\"night\":{\"strategy\":\"drain-first\",\"threshold\":\"95\",\"models\":\"opus;sonnet\",\"cooldown_s\":60,\"interval_s\":null,\"note\":\"x\"}},\"active_profile\":\"night\"}") == "{\"profiles\":{\"night\":{\"strategy\":\"drain-first\",\"threshold\":95.0,\"models\":[\"opus\",\"sonnet\"],\"cooldown_s\":60.0,\"interval_s\":null,\"note\":\"x\"}},\"active_profile\":\"night\"}" : String}:
  {==}

def n_profile_bad_strategy() -> {norm("{\"profiles\":{\"x\":{\"strategy\":\"nope\"}}}") == "!strategy must be one of: best, round-robin, soonest-reset, sticky, drain-first" : String}:
  {==}

def n_profile_bad_threshold() -> {norm("{\"profiles\":{\"x\":{\"threshold\":5}}}") == "!threshold must be between 50 and 99.9" : String}:
  {==}

def n_profile_default() -> {norm("{\"profiles\":{\"default\":{}}}") == "!profile 'default' follows the autoswitch settings and cannot be changed" : String}:
  {==}

def n_profile_bad_name() -> {norm("{\"profiles\":{\"bad name\":{}}}") == "!invalid profile name 'bad name': use letters, digits, '-' and '_', starting with a letter or digit" : String}:
  {==}

def n_profile_not_map() -> {norm("{\"profiles\":{\"x\":3}}") == "!profile 'x' must be a mapping" : String}:
  {==}

def n_active_not_name() -> {norm("{\"active_profile\":3}") == "!active_profile must be a profile name" : String}:
  {==}

# ---- merge ------------------------------------------------------------------------------

def mg(over: String, base: String) -> String:
  J.emit(Imp.merge(J.unwrap(J.parse(over)), J.unwrap(J.parse(base))))

def m_adds_and_replaces() -> {mg("{\"a\":2,\"c\":3}", "{\"a\":1,\"b\":1}") == "{\"a\":2,\"b\":1,\"c\":3}" : String}:
  {==}

def m_nested() -> {mg("{\"autoswitch\":{\"threshold\":80}}", "{\"autoswitch\":{\"threshold\":70,\"strategy\":\"best\"},\"x\":1}") == "{\"autoswitch\":{\"threshold\":80,\"strategy\":\"best\"},\"x\":1}" : String}:
  {==}

def m_profiles_per_key() -> {mg("{\"profiles\":{\"a\":{\"threshold\":95}}}", "{\"profiles\":{\"a\":{\"threshold\":90,\"models\":[\"m\"]},\"b\":{\"threshold\":60}}}") == "{\"profiles\":{\"a\":{\"threshold\":95,\"models\":[\"m\"]},\"b\":{\"threshold\":60}}}" : String}:
  {==}

def m_null_removes() -> {mg("{\"a\":null,\"p\":{\"k\":null}}", "{\"a\":1,\"b\":2,\"p\":{\"k\":1,\"j\":2}}") == "{\"b\":2,\"p\":{\"j\":2}}" : String}:
  {==}

def m_new_object_drops_nulls() -> {mg("{\"p\":{\"k\":null,\"j\":1}}", "{}") == "{\"p\":{\"j\":1}}" : String}:
  {==}

def m_array_replaces() -> {mg("{\"l\":[3]}", "{\"l\":[1,2]}") == "{\"l\":[3]}" : String}:
  {==}

def m_object_over_scalar() -> {mg("{\"a\":{\"b\":1}}", "{\"a\":5}") == "{\"a\":{\"b\":1}}" : String}:
  {==}

def m_empty_over() -> {mg("{}", "{\"a\":1}") == "{\"a\":1}" : String}:
  {==}

def m_strip() -> {J.emit(Imp.strip(J.unwrap(J.parse("{\"a\":null,\"b\":{\"c\":null,\"d\":1},\"e\":[null]}")))) == "{\"b\":{\"d\":1},\"e\":[null]}" : String}:
  {==}

# ---- profile import key check ------------------------------------------------------------

def po.of(r: Result<&2, &2, String, Unit>) -> String:
  match r:
    case Done{u}:
      "ok"
    case Fail{m}:
      m

def po(js: String) -> String:
  po.of(Imp.profile_only(J.keys(J.unwrap(J.parse(js)))))

def po_ok() -> {po("{\"profiles\":{},\"active_profile\":null}") == "ok" : String}:
  {==}

def po_bad() -> {po("{\"profiles\":{},\"autoswitch\":{}}") == "profile import takes profiles and active_profile only; found 'autoswitch'" : String}:
  {==}
