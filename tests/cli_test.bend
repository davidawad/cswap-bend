import Base
import ../src/collectrun.bend as Collectrun
import ../src/urec.bend as Urec
import ../src/args.bend as Args
import ../src/json.bend as Json
import ../src/view.bend as View
import ../src/render.bend as Render
import ../src/ustore.bend as Ustore
import ../src/poll.bend as Poll
import ../src/collect.bend as Collect
import ../src/cliops.bend as Cliops

# Ground equations for the command line: argument parsing, the usage
# projection with its pace fields, the human view, the usage.json row edits.

def j(s: String) -> Json.Json:
  Json.unwrap(Json.parse(s))

def now() -> U32:
  1792756800

def utc() -> U32:
  86400

def bad(msg: String) -> Args.Parsed:
  Args.PBad{"usage: cswap <command> [args] [options]\ncswap: error: " ++ msg}

# ---- arguments ------------------------------------------------------------------------

def a_list_json() -> {Args.parse(["list", "--json"]) == Args.PList{True{}, False{}} : Args.Parsed}:
  {==}

def a_ls_alias() -> {Args.parse(["ls"]) == Args.PList{False{}, False{}} : Args.Parsed}:
  {==}

def a_legacy_flag() -> {Args.parse(["--list", "--json"]) == Args.PList{True{}, False{}} : Args.Parsed}:
  {==}

def a_status() -> {Args.parse(["status", "--json"]) == Args.PStatus{True{}} : Args.Parsed}:
  {==}

def a_token_status_json() -> {Args.parse(["list", "--token-status", "--json"]) == bad("--token-status cannot be combined with --json") : Args.Parsed}:
  {==}

def a_json_on_add() -> {Args.parse(["add", "--json"]) == bad("--json can only be used with 'list', 'status', or 'switch'") : Args.Parsed}:
  {==}

def a_add_token() -> {Args.parse(["add-token", "-", "--email", "a@b.test", "--slot", "3"]) == Args.PAddToken{Some{"-"}, Some{"a@b.test"}, Some{3}} : Args.Parsed}:
  {==}

def a_add_token_eq() -> {Args.parse(["add-token", "--slot=4"]) == Args.PAddToken{None{}, None{}, Some{4}} : Args.Parsed}:
  {==}

def a_add_slot_text() -> {Args.parse(["add", "--slot", "x"]) == bad("argument --slot: invalid int value: 'x'") : Args.Parsed}:
  {==}

def a_add_alias() -> {Args.parse(["add", "--alias", "work"]) == Args.PAdd{None{}, Some{"work"}} : Args.Parsed}:
  {==}

def a_alias_elsewhere() -> {Args.parse(["list", "--alias", "x"]) == bad("--alias can only be used with 'add'") : Args.Parsed}:
  {==}

def a_remove() -> {Args.parse(["remove", "6"]) == Args.PRemove{"6"} : Args.Parsed}:
  {==}

def a_short_remove() -> {Args.parse(["rm", "a@b.test"]) == Args.PRemove{"a@b.test"} : Args.Parsed}:
  {==}

def a_remove_bare() -> {Args.parse(["remove"]) == bad("argument --remove-account: expected one argument") : Args.Parsed}:
  {==}

def a_extra() -> {Args.parse(["list", "extra"]) == bad("unrecognized arguments: extra") : Args.Parsed}:
  {==}

def a_import() -> {Args.parse(["import-usage", "u.json", "--hold", "600"]) == Args.PImportUsage{"u.json", Some{600}} : Args.Parsed}:
  {==}

def a_import_hold_zero() -> {Args.parse(["import-usage", "-", "--hold", "0"]) == Args.PImportUsage{"-", Some{0}} : Args.Parsed}:
  {==}

def a_import_hold_negative() -> {Args.parse(["import-usage", "u.json", "--hold", "-1"]) == bad("--hold must be a non-negative number of seconds") : Args.Parsed}:
  {==}

def a_hold_elsewhere() -> {Args.parse(["list", "--hold", "5"]) == bad("--hold can only be used with 'import-usage'") : Args.Parsed}:
  {==}

def a_config() -> {Args.parse(["config", "set", "autoswitch.threshold", "85", "--json"]) == Args.PConfig{["set", "autoswitch.threshold", "85"], True{}} : Args.Parsed}:
  {==}

def a_config_bare() -> {Args.parse(["config"]) == Args.PConfig{[], False{}} : Args.Parsed}:
  {==}

def a_auto_args() -> {Args.parse(["auto", "--once", "--threshold", "80"]) == Args.PAuto{["--once", "--threshold", "80"]} : Args.Parsed}:
  {==}

def a_none() -> {Args.parse([]) == bad("no command given - try 'cswap help'") : Args.Parsed}:
  {==}

def a_unknown() -> {Args.parse(["bogus"]) == bad("unrecognized arguments: bogus") : Args.Parsed}:
  {==}

def a_version() -> {Args.parse(["--version"]) == Args.PVersion{} : Args.Parsed}:
  {==}

def a_help() -> {Args.parse(["help"]) == Args.PHelp{} : Args.Parsed}:
  {==}

# ---- the usage projection (pace fields from fixture 07) ----------------------------------------

def week40() -> String:
  "{\"five_hour\":{\"pct\":20.0,\"resets_at\":\"2026-10-23T14:00:00+00:00\"},\"seven_day\":{\"pct\":40.0,\"resets_at\":\"2026-10-26T12:00:00+00:00\"}}"

def v_projection() -> {View.usage_to_json(j(week40()), Some{1792756770}, now(), utc()) == j("{\"fiveHour\":{\"pct\":20.0,\"resetsAt\":\"2026-10-23T14:00:00+00:00\",\"countdown\":\"2h 0m\",\"clock\":\"14:00\"},\"sevenDay\":{\"pct\":40.0,\"resetsAt\":\"2026-10-26T12:00:00+00:00\",\"countdown\":\"3d 0h\",\"clock\":\"Oct 26 12:00\",\"expectedPct\":57.1,\"aheadOfPace\":false,\"projectedExhaustionAt\":\"2026-10-29T11:58:45Z\",\"willLastToReset\":true}}") : Json.Json}:
  {==}

def v_ahead() -> {View.usage_to_json(j("{\"seven_day\":{\"pct\":95.0,\"resets_at\":\"2026-10-26T12:00:00+00:00\"}}"), Some{1792756770}, now(), utc()) == j("{\"sevenDay\":{\"pct\":95.0,\"resetsAt\":\"2026-10-26T12:00:00+00:00\",\"countdown\":\"3d 0h\",\"clock\":\"Oct 26 12:00\",\"expectedPct\":57.1,\"aheadOfPace\":true,\"projectedExhaustionAt\":\"2026-10-23T17:02:37Z\",\"willLastToReset\":false}}") : Json.Json}:
  {==}

def v_no_pace_without_fetch() -> {View.usage_to_json(j("{\"seven_day\":{\"pct\":40.0,\"resets_at\":\"2026-10-26T12:00:00+00:00\"}}"), None{}, now(), utc()) == j("{\"sevenDay\":{\"pct\":40.0,\"resetsAt\":\"2026-10-26T12:00:00+00:00\",\"countdown\":\"3d 0h\",\"clock\":\"Oct 26 12:00\"}}") : Json.Json}:
  {==}

def v_pace_first_day() -> {View.usage_to_json(j("{\"seven_day\":{\"pct\":40.0,\"resets_at\":\"2026-10-30T11:00:00+00:00\"}}"), Some{1792756770}, now(), utc()) == j("{\"sevenDay\":{\"pct\":40.0,\"resetsAt\":\"2026-10-30T11:00:00+00:00\",\"countdown\":\"6d 23h\",\"clock\":\"Oct 30 11:00\"}}") : Json.Json}:
  {==}

def v_scoped_and_spend() -> {View.usage_to_json(j("{\"spend\":{\"used\":12.34,\"limit\":50.0,\"pct\":24.68,\"currency\":\"USD\"},\"scoped\":[{\"name\":\"Opus\",\"pct\":30.0}]}"), None{}, now(), utc()) == j("{\"spend\":{\"used\":12.34,\"limit\":50.0,\"pct\":24.68,\"currency\":\"USD\"},\"scoped\":[{\"pct\":30.0,\"name\":\"Opus\"}]}") : Json.Json}:
  {==}

# ---- the human view ------------------------------------------------------------------------------

def r_pct() -> {Render.pct_text(425) == " 42%" : String}:
  {==}

def r_pct_up() -> {Render.pct_text(436) == " 44%" : String}:
  {==}

def r_pct_half_odd() -> {Render.pct_text(435) == " 44%" : String}:
  {==}

def r_pct_full() -> {Render.pct_text(1000) == "100%" : String}:
  {==}

def r_money() -> {Render.money(j("1234.5")) == "1,234.50" : String}:
  {==}

def r_money_small() -> {Render.money(j("0.07")) == "0.07" : String}:
  {==}

def r_age() -> {Render.age_text(7300) == "2h ago" : String}:
  {==}

def r_lines() -> {Render.measured(j(week40()), Some{1792756770}, Some{30}, now(), utc()) == ["\u{251C} 5h:  20%   resets 14:00         in 2h 0m", "\u{2514} 7d:  40%   resets Oct 26 12:00  in 3d 0h"] : List<&2, String>}:
  {==}

def r_lines_old() -> {Render.measured(j("{\"five_hour\":{\"pct\":5.0}}"), Some{1792756000}, Some{800}, now(), utc()) == ["\u{2514} 5h:   5% \u{B7} 13m ago"] : List<&2, String>}:
  {==}

def r_unavailable() -> {Render.unavailable(Some{"http-429"}) == ["usage unavailable (http-429)"] : List<&2, String>}:
  {==}

# ---- usage.json rows ------------------------------------------------------------------------------

def u_ok() -> {Urec.apply_ok(j("{\"email\":\"a\",\"organizationUuid\":\"\",\"claimId\":\"c1\",\"claimUntil\":1792756890.0,\"consecutiveFailures\":2,\"lastError\":\"http-429\",\"backoffUntil\":1792757000.0,\"authDeadStrikes\":1}"), j("{\"five_hour\":{\"pct\":1.0}}"), Some{Poll.Sched{1792756980, 180}}, now()) == j("{\"email\":\"a\",\"organizationUuid\":\"\",\"claimId\":null,\"claimUntil\":0.0,\"consecutiveFailures\":0,\"lastError\":null,\"backoffUntil\":null,\"authDeadStrikes\":0,\"lastAttemptAt\":1792756800.0,\"lastGood\":{\"five_hour\":{\"pct\":1.0}},\"fetchedAt\":1792756800.0,\"nextPollAt\":1792756980.0,\"pollIntervalS\":180.0,\"rejectedFingerprint\":null}") : Json.Json}:
  {==}

def u_fail_429() -> {Urec.apply_fail(j("{\"email\":\"a\",\"organizationUuid\":\"\",\"claimId\":\"c1\",\"claimUntil\":1792756890.0}"), "http-429", Some{120}, Json.JNull{}, now()) == j("{\"email\":\"a\",\"organizationUuid\":\"\",\"claimId\":null,\"claimUntil\":0.0,\"lastAttemptAt\":1792756800.0,\"consecutiveFailures\":1,\"lastError\":\"http-429\",\"last429At\":1792756800.0,\"backoffUntil\":1792756920.0}") : Json.Json}:
  {==}

def u_fail_dead() -> {Urec.apply_fail(j("{\"email\":\"a\",\"organizationUuid\":\"\",\"authDeadStrikes\":0}"), "invalid_grant", None{}, Json.JStr{"sha256:x"}, now()) == j("{\"email\":\"a\",\"organizationUuid\":\"\",\"authDeadStrikes\":1,\"claimId\":null,\"claimUntil\":0.0,\"lastAttemptAt\":1792756800.0,\"consecutiveFailures\":1,\"lastError\":\"invalid_grant\",\"backoffUntil\":1792756830.0,\"struckFingerprint\":\"sha256:x\"}") : Json.Json}:
  {==}

def u_rows_v2() -> {Ustore.rows_of(j("{\"schemaVersion\":2,\"accounts\":{\"1\":{\"email\":\"a\"}}}")) == j("{\"1\":{\"email\":\"a\"}}") : Json.Json}:
  {==}

def u_rows_other_version() -> {Ustore.rows_of(j("{\"schemaVersion\":1,\"accounts\":{\"1\":{\"email\":\"a\"}}}")) == j("{}") : Json.Json}:
  {==}

def u_identity_guard() -> {Ustore.row_of(j("{\"1\":{\"email\":\"a\",\"organizationUuid\":\"o\"}}"), Ustore.Id{"1", "a", "p"}) == None{} : Maybe<&2, Json.Json>}:
  {==}

def u_identity_match() -> {Ustore.row_of(j("{\"1\":{\"email\":\"a\"}}"), Ustore.Id{"1", "a", ""}) == Some{j("{\"email\":\"a\"}")} : Maybe<&2, Json.Json>}:
  {==}

# ---- collect ----------------------------------------------------------------------------------------

def c_api_key() -> {Collect.static_of("sk-ant-api03-FAKE") == Some{"api_key"} : Maybe<&2, String>}:
  {==}

def c_no_creds() -> {Collect.static_of("") == Some{"no_credentials"} : Maybe<&2, String>}:
  {==}

def c_setup_token() -> {Collect.static_of("{\"claudeAiOauth\":{\"accessToken\":\"sk-ant-oat01-FAKE\"}}") == None{} : Maybe<&2, String>}:
  {==}

def c_login_expires() -> {Collectrun.login_expires("{\"claudeAiOauth\":{\"accessToken\":\"x\",\"refreshTokenExpiresAt\":1792756800000}}") == Some{"2026-10-23T12:00:00Z"} : Maybe<&2, String>}:
  {==}

def c_login_missing() -> {Collectrun.login_expires("{\"claudeAiOauth\":{\"accessToken\":\"x\"}}") == None{} : Maybe<&2, String>}:
  {==}

def c_touched_added() -> {Cliops.touched(["Added Account 3: a@b.test [personal] (from token)"]) == Some{"3"} : Maybe<&2, String>}:
  {==}

def c_touched_updated() -> {Cliops.touched(["Notice: x", "Updated credentials for Account 12 (a@b.test)"]) == Some{"12"} : Maybe<&2, String>}:
  {==}

def c_touched_none() -> {Cliops.touched(["Cancelled"]) == None{} : Maybe<&2, String>}:
  {==}

# ---- switch ---------------------------------------------------------------------------------------

def s_bare() -> {Args.parse(["switch", "--json"]) == Args.PSwitch{None{}, False{}, None{}, None{}, True{}} : Args.Parsed}:
  {==}

def s_target() -> {Args.parse(["switch", "3", "--force"]) == Args.PSwitch{Some{"3"}, True{}, None{}, None{}, False{}} : Args.Parsed}:
  {==}

def s_strategy() -> {Args.parse(["switch", "--strategy", "best", "--model", "Opus", "--json"]) == Args.PSwitch{None{}, False{}, Some{"best"}, Some{"Opus"}, True{}} : Args.Parsed}:
  {==}

def s_legacy() -> {Args.parse(["--switch-to", "a@b.test"]) == Args.PSwitch{Some{"a@b.test"}, False{}, None{}, None{}, False{}} : Args.Parsed}:
  {==}

def s_strategy_with_target() -> {Args.parse(["switch", "3", "--strategy", "best"]) == bad("--strategy can only be used with bare 'switch'") : Args.Parsed}:
  {==}

def s_bad_strategy() -> {Args.parse(["switch", "--strategy", "fast"]) == bad("argument --strategy: invalid choice: 'fast' (choose from 'best', 'next-available')") : Args.Parsed}:
  {==}

def s_model_alone() -> {Args.parse(["switch", "--model", "Opus"]) == bad("--model can only be used with 'switch --strategy best' or 'switch --strategy next-available'") : Args.Parsed}:
  {==}

def s_force_bare() -> {Args.parse(["switch", "--force"]) == bad("--force can only be used with 'import' or 'switch <num|email>'") : Args.Parsed}:
  {==}

def a_watch_is_tui() -> {Args.parse(["watch", "--once"]) == Args.PTui{["--once"]} : Args.Parsed}:
  {==}

def a_update_defers_as_upgrade() -> {Args.parse(["update"]) == Args.PDeferred{"upgrade"} : Args.Parsed}:
  {==}

def a_menubar_defers() -> {Args.parse(["menubar"]) == Args.PDeferred{"menubar"} : Args.Parsed}:
  {==}
