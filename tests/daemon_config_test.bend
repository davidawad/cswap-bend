import Base
import ../src/json.bend as Json
import ../src/daemon/config.bend as Cfg

# The lenient settings load and the flags over it (contract 1.6 and 4.4).

def d() -> Cfg.Cfg:
  Cfg.defaults()

def s_missing_file() -> {Cfg.from_text("") == d() : Cfg.Cfg}:
  {==}

def s_not_an_object() -> {Cfg.from_text("[1]") == d() : Cfg.Cfg}:
  {==}

def s_empty_object() -> {Cfg.from_text("{}") == d() : Cfg.Cfg}:
  {==}

def s_threshold_80() -> {Cfg.from_text("{\"autoswitch\": {\"threshold\": 80, \"cooldownSeconds\": 5}}") == Cfg.Cfg{8000, 60, 5, 1000, "best", False{}, 3, []} : Cfg.Cfg}:
  {==}

def s_clamps_high() -> {Cfg.from_text("{\"autoswitch\": {\"threshold\": 120.0, \"intervalSeconds\": 99999, \"cooldownSeconds\": 99999999, \"hysteresisPct\": 70, \"unhealthyTicks\": 500}}") == Cfg.Cfg{9990, 3600, 86400, 5000, "best", False{}, 100, []} : Cfg.Cfg}:
  {==}

def s_clamps_low() -> {Cfg.from_text("{\"autoswitch\": {\"threshold\": 10, \"intervalSeconds\": 1, \"unhealthyTicks\": 0}}") == Cfg.Cfg{5000, 15, 300, 1000, "best", False{}, 1, []} : Cfg.Cfg}:
  {==}

def s_fraction() -> {Cfg.from_text("{\"autoswitch\": {\"threshold\": 87.55}}") == Cfg.Cfg{8755, 60, 300, 1000, "best", False{}, 3, []} : Cfg.Cfg}:
  {==}

def s_wrong_types_are_defaults() -> {Cfg.from_text("{\"autoswitch\": {\"threshold\": true, \"intervalSeconds\": \"x\", \"hysteresisPct\": null}}") == d() : Cfg.Cfg}:
  {==}

def s_bool_by_truthiness() -> {Cfg.from_text("{\"autoswitch\": {\"includeApiKeyAccounts\": \"false\"}}") == Cfg.Cfg{9000, 60, 300, 1000, "best", True{}, 3, []} : Cfg.Cfg}:
  {==}

def s_bool_false() -> {Cfg.from_text("{\"autoswitch\": {\"includeApiKeyAccounts\": false}}") == d() : Cfg.Cfg}:
  {==}

def s_strategy() -> {Cfg.from_text("{\"autoswitch\": {\"strategy\": \"consume-first\"}}") == Cfg.Cfg{9000, 60, 300, 1000, "consume-first", False{}, 3, []} : Cfg.Cfg}:
  {==}

def s_unknown_strategy() -> {Cfg.from_text("{\"autoswitch\": {\"strategy\": \"sideways\"}}") == d() : Cfg.Cfg}:
  {==}

def s_models() -> {Cfg.from_text("{\"autoswitch\": {\"model\": \"Fable, opus ,FABLE,,\"}}") == Cfg.Cfg{9000, 60, 300, 1000, "best", False{}, 3, ["Fable", "opus"]} : Cfg.Cfg}:
  {==}

def f(args: List<&2, String>) -> Result<&2, &2, String, Cfg.Flags>:
  Cfg.parse_flags(args)

def f_none() -> {f([]) == Done{Cfg.no_flags()} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_once_json() -> {f(["--once", "--json"]) == Done{Cfg.Flags{True{}, 1, False{}, None{}, None{}, None{}, None{}, None{}, False{}}} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_values() -> {f(["--threshold", "85", "--strategy", "best", "--interval", "300", "--model", "Fable,Opus", "--dry-run"]) == Done{Cfg.Flags{False{}, 0, True{}, Some{8500}, Some{300}, None{}, Some{"best"}, Some{"Fable,Opus"}, False{}}} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_equals_form() -> {f(["--threshold=85.5", "--cooldown=60"]) == Done{Cfg.Flags{False{}, 0, False{}, Some{8550}, None{}, Some{60}, None{}, None{}, False{}}} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_clamped() -> {f(["--threshold", "120", "--interval", "5"]) == Done{Cfg.Flags{False{}, 0, False{}, Some{9990}, Some{15}, None{}, None{}, None{}, False{}}} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_api_keys() -> {f(["--include-api-key-accounts"]) == Done{Cfg.Flags{False{}, 0, False{}, None{}, None{}, None{}, None{}, None{}, True{}}} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_bad_number() -> {f(["--threshold", "high"]) == Fail{"argument --threshold: invalid float value: 'high'"} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_missing_value() -> {f(["--interval"]) == Fail{"argument --interval: expected one argument"} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_bad_strategy() -> {f(["--strategy", "nope"]) == Fail{"argument --strategy: invalid choice: 'nope' (choose from 'best', 'consume-first')"} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_unknown() -> {f(["--bogus"]) == Fail{"unrecognized arguments: --bogus"} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def m_flags_win() -> {Cfg.merge(Cfg.from_text("{\"autoswitch\": {\"threshold\": 80, \"strategy\": \"consume-first\", \"model\": \"Opus\"}}"), Cfg.Flags{False{}, 0, False{}, Some{8500}, None{}, None{}, Some{"best"}, Some{"Fable"}, False{}}) == Cfg.Cfg{8500, 60, 300, 1000, "best", False{}, 3, ["Fable"]} : Cfg.Cfg}:
  {==}

def m_settings_when_no_flags() -> {Cfg.merge(Cfg.from_text("{\"autoswitch\": {\"threshold\": 80}}"), Cfg.no_flags()) == Cfg.Cfg{8000, 60, 300, 1000, "best", False{}, 3, []} : Cfg.Cfg}:
  {==}

# `--format NAME` is the event stream's format (src/fmt/code.bend): 0 text, 1 json, 2 csv, 3 yaml, 4 toon;
# a later `--json` wins over an earlier `--format`.
def f_format_csv() -> {f(["--once", "--format", "csv"]) == Done{Cfg.Flags{True{}, 2, False{}, None{}, None{}, None{}, None{}, None{}, False{}}} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_format_equals_yaml() -> {f(["--format=yaml"]) == Done{Cfg.Flags{False{}, 3, False{}, None{}, None{}, None{}, None{}, None{}, False{}}} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_format_toon_then_json() -> {f(["--format", "toon", "--json"]) == Done{Cfg.Flags{False{}, 1, False{}, None{}, None{}, None{}, None{}, None{}, False{}}} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_format_bad() -> {f(["--format", "xml"]) == Fail{"argument --format: invalid choice: 'xml' (choose from 'text', 'json', 'csv', 'yaml', 'toon')"} : Result<&2, &2, String, Cfg.Flags>}:
  {==}

def f_format_missing() -> {f(["--format"]) == Fail{"argument --format: expected one argument"} : Result<&2, &2, String, Cfg.Flags>}:
  {==}
