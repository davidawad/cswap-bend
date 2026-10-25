import Base
import ../src/json.bend as Json
import ../src/daemon/cadence.bend as Cad
import ../src/daemon/state.bend as St
import ../src/daemon/status.bend as Stat
import ../src/daemon/config.bend as Cfg

# The pure parts of the daemon: cadence, the state file, the status file.

def info(o: Cad.Outcome, until: Maybe<&2, U32>, long: Bool, idle: Bool, np: Maybe<&2, U32>) -> Cad.Info:
  Cad.Info{o, until, long, idle, np}

# ---- exit codes and cadence ----

def x_codes() -> {[Cad.exit_code(Cad.Switched{}), Cad.exit_code(Cad.Failed{}), Cad.exit_code(Cad.NoAction{}), Cad.exit_code(Cad.Blocked{})] == [0, 1, 2, 3] : List<&2, U32>}:
  {==}

def d_normal_is_interval() -> {Cad.next_delay(info(Cad.NoAction{}, None{}, False{}, False{}, None{}), 1000, 300) == 300 : U32}:
  {==}

def d_shortened_to_plan() -> {Cad.next_delay(info(Cad.NoAction{}, None{}, False{}, False{}, Some{1100}), 1000, 300) == 100 : U32}:
  {==}

def d_never_under_floor() -> {Cad.next_delay(info(Cad.NoAction{}, None{}, False{}, False{}, Some{1010}), 1000, 300) == 60 : U32}:
  {==}

def d_past_plan_is_floor() -> {Cad.next_delay(info(Cad.NoAction{}, None{}, False{}, False{}, Some{900}), 1000, 300) == 60 : U32}:
  {==}

def d_plan_later_than_interval() -> {Cad.next_delay(info(Cad.NoAction{}, None{}, False{}, False{}, Some{9000}), 1000, 300) == 300 : U32}:
  {==}

def d_idle_hold_is_slow() -> {Cad.next_delay(info(Cad.NoAction{}, None{}, False{}, True{}, None{}), 1000, 60) == 300 : U32}:
  {==}

def d_idle_hold_keeps_longer_interval() -> {Cad.next_delay(info(Cad.NoAction{}, None{}, False{}, True{}, None{}), 1000, 900) == 900 : U32}:
  {==}

def d_blocked_until_reset() -> {Cad.next_delay(info(Cad.Blocked{}, Some{1500}, False{}, False{}, None{}), 1000, 60) == 500 : U32}:
  {==}

def d_blocked_reset_capped() -> {Cad.next_delay(info(Cad.Blocked{}, Some{9000}, False{}, False{}, None{}), 1000, 60) == 600 : U32}:
  {==}

def d_blocked_reset_soon_waits_interval() -> {Cad.next_delay(info(Cad.Blocked{}, Some{1010}, False{}, False{}, None{}), 1000, 60) == 60 : U32}:
  {==}

def d_blocked_no_candidates() -> {Cad.next_delay(info(Cad.Blocked{}, None{}, True{}, False{}, None{}), 1000, 60) == 300 : U32}:
  {==}

def d_blocked_otherwise_normal() -> {Cad.next_delay(info(Cad.Blocked{}, None{}, False{}, False{}, None{}), 1000, 60) == 60 : U32}:
  {==}

def d_error_normal() -> {Cad.next_delay(info(Cad.Failed{}, None{}, False{}, False{}, None{}), 1000, 60) == 60 : U32}:
  {==}

def a_announce_long() -> {Cad.announce(301, 200) == True{} : Bool}:
  {==}

def a_announce_short() -> {Cad.announce(300, 200) == False{} : Bool}:
  {==}

# ---- autoswitch_state.json ----

def sw() -> String:
  Json.emit(St.record_switch(Json.unwrap(Json.parse("{\"keep\": 1}")), 1792740000, "3", Some{1}, Some{1050}, Some{1792747200}, "proactive"))

def s_record_switch() -> {sw() == "{\"keep\":1,\"schemaVersion\":1,\"lastSwitchAt\":1792740000.0,\"lastSwitchTo\":\"3\",\"lastSwitchFrom\":1,\"leftHeadroom\":10.5,\"leftRecoveryAt\":1792747200.0,\"leftTrigger\":\"proactive\"}" : String}:
  {==}

def s_record_unknowns() -> {Json.emit(St.record_switch(St.empty(), 5, "2", None{}, None{}, None{}, "at-limit")) == "{\"schemaVersion\":1,\"lastSwitchAt\":5.0,\"lastSwitchTo\":\"2\",\"lastSwitchFrom\":null,\"leftHeadroom\":null,\"leftRecoveryAt\":null,\"leftTrigger\":\"at-limit\"}" : String}:
  {==}

def s_replaces_previous_record() -> {Json.emit(St.record_switch(St.record_switch(St.empty(), 5, "2", None{}, None{}, None{}, "at-limit"), 9, "4", Some{2}, None{}, None{}, "proactive")) == "{\"schemaVersion\":1,\"lastSwitchAt\":9.0,\"lastSwitchTo\":\"4\",\"lastSwitchFrom\":2,\"leftHeadroom\":null,\"leftRecoveryAt\":null,\"leftTrigger\":\"proactive\"}" : String}:
  {==}

def s_cooldown_inside() -> {St.in_cooldown(Json.unwrap(Json.parse("{\"lastSwitchAt\": 1000.5}")), 1200, 300) == True{} : Bool}:
  {==}

def s_cooldown_over() -> {St.in_cooldown(Json.unwrap(Json.parse("{\"lastSwitchAt\": 1000.5}")), 1300, 300) == False{} : Bool}:
  {==}

def s_cooldown_no_record() -> {St.in_cooldown(St.empty(), 1300, 300) == False{} : Bool}:
  {==}

def s_cooldown_not_a_number() -> {St.in_cooldown(Json.unwrap(Json.parse("{\"lastSwitchAt\": \"x\"}")), 1300, 300) == False{} : Bool}:
  {==}

def q() -> Json.Json:
  St.quarantine(St.empty(), "3", "c@x.test", "invalid_grant", "2026-10-23T12:00:00Z", Some{"sha256:ab"})

def s_quarantine() -> {Json.emit(q()) == "{\"schemaVersion\":1,\"quarantine\":{\"3\":{\"email\":\"c@x.test\",\"reason\":\"invalid_grant\",\"at\":\"2026-10-23T12:00:00Z\",\"refreshTokenFingerprint\":\"sha256:ab\"}}}" : String}:
  {==}

def s_quarantine_slots() -> {St.quarantined_slots(q()) == ["3"] : List<&2, String>}:
  {==}

def s_quarantine_fields() -> {[St.entry_email(q(), "3")] == ["c@x.test"] : List<&2, String>}:
  {==}

def s_quarantine_fp() -> {St.entry_fp(q(), "3") == Some{"sha256:ab"} : Maybe<&2, String>}:
  {==}

def s_release() -> {Json.emit(St.release(q(), "3")) == "{\"schemaVersion\":1,\"quarantine\":{}}" : String}:
  {==}

def s_quarantine_keeps_switch_record() -> {St.quarantined_slots(St.quarantine(St.record_switch(St.empty(), 5, "2", None{}, None{}, None{}, "x"), "7", "e", "r", "t", None{})) == ["7"] : List<&2, String>}:
  {==}

# ---- daemon-status.json ----

def stt() -> Stat.Status:
  Stat.Status{4242, "0.0.1", "2026-10-23T12:00:00Z", Some{"2026-10-23T12:05:00Z"}, None{}, Some{"1"}, [Stat.Entry{"1", Some{9000}, Some{4050}, Some{"2026-10-23T12:05:00Z"}, None{}, None{}}, Stat.Entry{"2", None{}, None{}, None{}, Some{"2026-10-23T12:10:00Z"}, Some{"http-429"}}], Cfg.Cfg{8500, 30, 300, 1000, "best", False{}, 3, ["opus", "sonnet"]}}

def t_status() -> {Json.emit(Stat.to_json(stt())) == "{\"schemaVersion\":1,\"pid\":4242,\"version\":\"0.0.1\",\"started_at\":\"2026-10-23T12:00:00Z\",\"last_poll_at\":\"2026-10-23T12:05:00Z\",\"next_poll_at\":null,\"active\":1,\"config\":{\"threshold\":85.0,\"interval_seconds\":30,\"cooldown_seconds\":300,\"strategy\":\"best\",\"models\":[\"opus\",\"sonnet\"],\"include_api_keys\":false},\"accounts\":{\"1\":{\"pct_5h\":90.0,\"pct_7d\":40.5,\"fetched_at\":\"2026-10-23T12:05:00Z\",\"backoff_until\":null,\"last_error\":null},\"2\":{\"pct_5h\":null,\"pct_7d\":null,\"fetched_at\":null,\"backoff_until\":\"2026-10-23T12:10:00Z\",\"last_error\":\"http-429\"}}}" : String}:
  {==}
