import Base
import ../src/policy/types.bend as T
import ../src/policy/usage.bend as U
import ../src/policy/decide.bend as D

# Ground equations mirroring parity/fixtures/2*-auto-* and 33-*: the same
# seeded accounts and usage, the decision the reference makes. Percentages
# are centi-percent (9000 = 90 %), times unix seconds. Clock: now = 1000;
# every seeded row was fetched at 970 ("epoch:-30") and resets in 7200 s (5h)
# and 259200 s (7d).

def st_at(t: Nat) -> T.State:
  T.State{Some{t}, None{}, None{}, T.NoSnap{}}

def now() -> Nat:
  1000n

def acct(slot: Nat, email: String, kind: T.AcctKind) -> T.Account:
  T.Account{slot, email, kind, False{}}

# Fixture 21-28 seed: slot 1 the full login, 2-6 setup tokens.
def six() -> List<&2, T.Account>:
  [
    acct(1n, "owner@example.test", T.FullLogin{}),
    acct(2n, "st2@example.test", T.SetupToken{}),
    acct(3n, "st3@example.test", T.SetupToken{}),
    acct(4n, "st4@example.test", T.SetupToken{}),
    acct(5n, "st5@example.test", T.SetupToken{}),
    acct(6n, "st6@example.test", T.SetupToken{})
  ]

# A fresh row with 5h / 7d utilization, no scoped windows.
def row(slot: Nat, five: Nat, seven: Nat) -> T.Usage:
  T.Usage{slot, Some{five}, Some{8200n}, Some{seven}, Some{262800n}, Nil{}, Some{970n}, 0n, T.ErrNone{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

def row_scoped(slot: Nat, five: Nat, seven: Nat, ss: List<&2, T.Scoped>) -> T.Usage:
  T.Usage{slot, Some{five}, Some{8200n}, Some{seven}, Some{262800n}, ss, Some{970n}, 0n, T.ErrNone{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

# Never fetched, failing with a 500: no reading.
def row_cold(slot: Nat) -> T.Usage:
  T.Usage{slot, None{}, None{}, None{}, None{}, Nil{}, None{}, 1030n, T.ErrOther{}, T.failing(T.ErrOther{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

def others() -> List<&2, T.Usage>:
  [row(2n, 1000n, 3000n), row(3n, 500n, 1000n), row(4n, 5000n, 6000n), row(5n, 7000n, 2000n), row(6n, 100n, 9500n)]

def seeded(five: Nat, seven: Nat) -> List<&2, T.Usage>:
  Con{row(1n, five, seven), others()}

def cfg85() -> T.Config:
  T.Config{8500n, Nil{}, T.Best{}, 60n, 300n, 1000n, 180n, 3n, False{}}

# 21: active 5h 20 / 7d 40, threshold 85 -> below-threshold "40% < 85%".
def fx21_below_threshold() -> {D.decide(1n, six(), seeded(2000n, 4000n), now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.BelowThreshold{}, "40% < 85%"} : T.Decision}:
  {==}

# 22: active 5h 90 -> proactive switch to slot 3 (headroom 90).
def fx22_proactive_best() -> {D.decide(1n, six(), seeded(9000n, 4000n), now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 9000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# 23: active usage read failed, cold cache -> active-usage-unknown, no failover.
def fx23_unknown_headroom() -> {D.decide(1n, six(), Con{row_cold(1n), others()}, now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.ActiveUsageUnknown{}, "headroom unknown; not counted toward failover"} : T.Decision}:
  {==}

# 24: proactive inside the 300 s cooldown (last switch 60 s ago) -> cooldown.
def fx24_cooldown() -> {D.decide(1n, six(), seeded(9000n, 4000n), now(), cfg85(), st_at(940n), T.fresh_mem()) == T.NoSwitch{T.Cooldown{}, ""} : T.Decision}:
  {==}

# 25: active at 100 % -> at-limit switch even inside the cooldown.
def fx25_at_limit_ignores_cooldown() -> {D.decide(1n, six(), seeded(10000n, 4000n), now(), cfg85(), st_at(940n), T.fresh_mem()) == T.Switch{3n, T.AtLimit{}, "at-limit", 9000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

def exhausted() -> List<&2, T.Usage>:
  [row(1n, 10000n, 5100n), row(2n, 10000n, 5200n), row(3n, 10000n, 5300n), row(4n, 10000n, 5400n), row(5n, 10000n, 5500n), row(6n, 10000n, 5600n)]

# 26: every account at 100 % -> all-exhausted, earliest reset = the 5h reset.
def fx26_all_exhausted() -> {D.decide(1n, six(), exhausted(), now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.AllExhausted{Some{8200n}}, ""} : T.Decision}:
  {==}

def opus_fable() -> List<&2, String>:
  ["Fable", "Opus"]

def cfg_models() -> T.Config:
  T.Config{8500n, opus_fable(), T.Best{}, 60n, 300n, 1000n, 180n, 3n, False{}}

def opus97() -> List<&2, T.Scoped>:
  [T.Scoped{"Opus", 9700n, Some{262800n}}, T.Scoped{"Fable", 300n, Some{262800n}}]

# 27: --model Fable,Opus: Opus weekly 97 % binds though 5h/7d are low.
def fx27_model_binding() -> {D.decide(1n, six(), Con{row_scoped(1n, 500n, 1000n, opus97()), others()}, now(), cfg_models(), T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 9000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# Without --model the scoped Opus window is ignored: 5h 5 / 7d 10 is below.
def fx27_model_ignored_without_flag() -> {D.decide(1n, six(), Con{row_scoped(1n, 500n, 1000n, opus97()), others()}, now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.BelowThreshold{}, "10% < 85%"} : T.Decision}:
  {==}

# Model names compare case-insensitively.
def fx27_model_case_insensitive() -> {D.decide(1n, six(), Con{row_scoped(1n, 500n, 1000n, opus97()), others()}, now(), T.Config{8500n, ["oPuS"], T.Best{}, 60n, 300n, 1000n, 180n, 3n, False{}}, T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 9000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# 28: --dry-run decides exactly as 22; the dry-run flag is the CLI's.
def fx28_dry_run_same_decision() -> {D.decide(1n, six(), seeded(9000n, 4000n), now(), cfg85(), T.fresh_state(), T.fresh_mem()) == D.decide(1n, six(), seeded(9000n, 4000n), now(), cfg85(), T.fresh_state(), T.fresh_mem()) : T.Decision}:
  {==}

# 29: a single managed account at its limit -> no-candidates.
def fx29_no_candidates() -> {D.decide(1n, [acct(1n, "owner@example.test", T.FullLogin{})], [row(1n, 10000n, 4000n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.NoCandidates{}, ""} : T.Decision}:
  {==}

# 30: the live login is not managed -> unmanaged-active-account.
def fx30_unmanaged_active() -> {D.decide(1n, [acct(2n, "st2@example.test", T.SetupToken{}), acct(3n, "st3@example.test", T.SetupToken{})], [row(2n, 1000n, 1000n), row(3n, 1000n, 1000n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.UnmanagedActive{}, "run 'cswap --add-account' to include it in rotation"} : T.Decision}:
  {==}

# 31: settings supply threshold 80; active at 82 % -> proactive switch.
def fx31_settings_threshold() -> {D.decide(1n, six(), seeded(8200n, 4000n), now(), T.Config{8000n, Nil{}, T.Best{}, 60n, 300n, 1000n, 180n, 3n, False{}}, T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 9000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

def hysteresis_rows() -> List<&2, T.Usage>:
  [row(1n, 8600n, 4000n), row(2n, 8000n, 2000n), row(3n, 1000n, 7900n), row(4n, 9000n, 1000n), row(5n, 10000n, 1000n), row(6n, 500n, 9500n)]

# 33: active at 86 % (headroom 14); no candidate is below 85 % and 10 points
# better -> no-qualifying-candidate.
def fx33_hysteresis_blocks() -> {D.decide(1n, six(), hysteresis_rows(), now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.NoQualifyingCandidate{}, "no candidate is below the threshold and better than the active account by the hysteresis margin, or usage is unreadable this tick"} : T.Decision}:
  {==}

# Same rows but the active account is at its limit: at-limit skips the gate
# and takes the best remaining headroom (slot 3 has 21).
def fx33_at_limit_skips_gate() -> {D.decide(1n, six(), Con{row(1n, 10000n, 4000n), Con{row(2n, 8000n, 2000n), Con{row(3n, 1000n, 7900n), Nil{}}}}, now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.AtLimit{}, "at-limit", 2100n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# Hysteresis edge: a candidate exactly 10 points better qualifies, 9.99 does not.
def hysteresis_edge_in() -> {D.decide(1n, [acct(1n, "a", T.FullLogin{}), acct(2n, "b", T.SetupToken{})], [row(1n, 8600n, 0n), row(2n, 7600n, 0n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{2n, T.Proactive{}, "proactive", 2400n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

def hysteresis_edge_out() -> {D.decide(1n, [acct(1n, "a", T.FullLogin{}), acct(2n, "b", T.SetupToken{})], [row(1n, 8600n, 0n), row(2n, 7601n, 0n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.NoQualifyingCandidate{}, "no candidate is below the threshold and better than the active account by the hysteresis margin, or usage is unreadable this tick"} : T.Decision}:
  {==}

# Patch 0002 / unknown candidates: an unreadable candidate is never chosen.
def unknown_candidate_skipped() -> {D.decide(1n, six(), Con{row(1n, 9000n, 4000n), Con{row_cold(2n), Con{row(3n, 500n, 1000n), Nil{}}}}, now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 9000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

def backed_off(slot: Nat, five: Nat) -> T.Usage:
  T.Usage{slot, Some{five}, Some{8200n}, Some{0n}, Some{262800n}, Nil{}, Some{970n}, 1100n, T.ErrOther{}, T.failing(T.ErrOther{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

# A fresh row at time 3000 (fetched 30 s ago).
def row2(slot: Nat, five: Nat, seven: Nat) -> T.Usage:
  T.Usage{slot, Some{five}, Some{8200n}, Some{seven}, Some{262800n}, Nil{}, Some{2970n}, 0n, T.ErrNone{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

# Backoff only throttles polling: a candidate in backoff whose reading is
# still trusted (it is failing, so trust extends to 3600 s) stays eligible and
# wins with the most headroom.
def backoff_candidate_stays_eligible() -> {D.decide(1n, six(), Con{row(1n, 9000n, 4000n), Con{backed_off(2n, 0n), Con{row(3n, 3000n, 1000n), Nil{}}}}, now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{2n, T.Proactive{}, "proactive", 10000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# The reference case: in backoff after an http-500, reading 20 minutes old.
def old_failing_row(slot: Nat) -> T.Usage:
  T.Usage{slot, Some{0n}, None{}, Some{0n}, None{}, Nil{}, Some{1800n}, 3100n, T.ErrOther{}, T.failing(T.ErrOther{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

def backoff_trusted_old_reading_eligible() -> {D.decide(1n, six(), Con{row2(1n, 9000n, 4000n), Con{old_failing_row(2n), Nil{}}}, 3000n, cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{2n, T.Proactive{}, "proactive", 10000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# The same old reading without a failure is stale: unknown, never chosen.
def old_quiet_row(slot: Nat) -> T.Usage:
  T.Usage{slot, Some{0n}, None{}, Some{0n}, None{}, Nil{}, Some{1800n}, 0n, T.ErrNone{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

def old_quiet_reading_ignored() -> {D.decide(1n, six(), Con{row2(1n, 9000n, 4000n), Con{old_quiet_row(2n), Nil{}}}, 3000n, cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.NoComparison{}, "no candidate has readable usage"} : T.Decision}:
  {==}

# Nothing readable among the candidates -> no-comparison.
def no_comparison() -> {D.decide(1n, six(), Con{row(1n, 9000n, 4000n), Con{row_cold(2n), Con{row_cold(3n), Nil{}}}}, now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.NoComparison{}, "no candidate has readable usage"} : T.Decision}:
  {==}

# A disabled account is not a target.
def disabled_skipped() -> {D.decide(1n, [acct(1n, "a", T.FullLogin{}), T.Account{2n, "b", T.SetupToken{}, True{}}, acct(3n, "c", T.SetupToken{})], [row(1n, 9000n, 0n), row(2n, 0n, 0n), row(3n, 3000n, 0n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 7000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# An API-key candidate is never a target.
def api_key_skipped() -> {D.decide(1n, [acct(1n, "a", T.FullLogin{}), acct(2n, "b", T.ApiKey{})], [row(1n, 9000n, 0n), row(2n, 0n, 0n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.NoCandidates{}, ""} : T.Decision}:
  {==}

# An API-key active account has no quota to watch.
def active_api_key() -> {D.decide(1n, [acct(1n, "a", T.ApiKey{}), acct(2n, "b", T.SetupToken{})], [row(2n, 0n, 0n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.ActiveApiKey{}, "API-key accounts have no quota to watch"} : T.Decision}:
  {==}

# Stale beyond trust (fetched 400 s ago, no failure): unknown, never switches.
def stale_active_unknown() -> {D.decide(1n, six(), Con{T.Usage{1n, Some{9000n}, None{}, Some{0n}, None{}, Nil{}, Some{600n}, 0n, T.ErrNone{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}, others()}, now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.ActiveUsageUnknown{}, "headroom unknown; not counted toward failover"} : T.Decision}:
  {==}

# Same age but the row is failing: trust is extended to 3600 s, so it counts.
def failing_active_trusted() -> {D.decide(1n, six(), Con{T.Usage{1n, Some{9000n}, None{}, Some{0n}, None{}, Nil{}, Some{600n}, 1030n, T.ErrOther{}, T.failing(T.ErrOther{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}, others()}, now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 9000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# Equal headroom: sequence order breaks the tie.
def tie_first_wins() -> {D.decide(1n, [acct(1n, "a", T.FullLogin{}), acct(2n, "b", T.SetupToken{}), acct(3n, "c", T.SetupToken{})], [row(1n, 9000n, 0n), row(2n, 2000n, 0n), row(3n, 2000n, 0n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{2n, T.Proactive{}, "proactive", 8000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

def reason_names() -> {T.reason.name(T.NoQualifyingCandidate{}) == "no-qualifying-candidate" : String}:
  {==}

def exit_switch() -> {T.exit_code(T.Switch{3n, T.Proactive{}, "proactive", 9000n, T.MHead{}, None{}, None{}}) == 0 : U32}:
  {==}

def exit_blocked() -> {T.exit_code(T.NoSwitch{T.AllExhausted{None{}}, ""}) == 3 : U32}:
  {==}

def label_fraction() -> {U.pct.label(8550n) == "85.5" : String}:
  {==}

def label_two_digits() -> {U.pct.label(8505n) == "85.05" : String}:
  {==}

# --- poll_due

def due_row(next_at: Maybe<&2, Nat>, fetched: Maybe<&2, Nat>, backoff_until: Nat) -> T.Usage:
  T.Usage{1n, Some{1000n}, None{}, None{}, None{}, Nil{}, fetched, backoff_until, T.ErrNone{}, T.failing(T.ErrNone{}), next_at, 180n, 0n, 0n, 0n, T.NoSentinel{}}

def due_planned() -> {U.poll_due(due_row(Some{900n}, Some{990n}, 0n), 1000n, cfg85()) == True{} : Bool}:
  {==}

def not_due_planned_future() -> {U.poll_due(due_row(Some{1100n}, Some{990n}, 0n), 1000n, cfg85()) == False{} : Bool}:
  {==}

def due_never_fetched() -> {U.poll_due(due_row(None{}, None{}, 0n), 1000n, cfg85()) == True{} : Bool}:
  {==}

def not_due_fresh_unplanned() -> {U.poll_due(due_row(None{}, Some{900n}, 0n), 1000n, cfg85()) == False{} : Bool}:
  {==}

def due_stale_unplanned() -> {U.poll_due(due_row(None{}, Some{700n}, 0n), 1000n, cfg85()) == True{} : Bool}:
  {==}

def not_due_inside_backoff() -> {U.poll_due(due_row(Some{900n}, None{}, 1100n), 1000n, cfg85()) == False{} : Bool}:
  {==}

def due_after_backoff() -> {U.poll_due(due_row(Some{900n}, None{}, 1000n), 1000n, cfg85()) == True{} : Bool}:
  {==}

# Overslept plan: next poll 2000 s out with a 180 s interval (> 600*1.1+60).
def due_overslept_plan() -> {U.poll_due(due_row(Some{3000n}, Some{700n}, 0n), 1000n, cfg85()) == True{} : Bool}:
  {==}

def not_due_far_plan_but_fresh() -> {U.poll_due(due_row(Some{3000n}, Some{900n}, 0n), 1000n, cfg85()) == False{} : Bool}:
  {==}

# --- backoff_for (fixture 09: 429 + Retry-After 120 -> 120, 401/500 -> 30)

def backoff_first() -> {U.backoff_for(1n, T.ErrOther{}, None{}) == 30n : Nat}:
  {==}

def backoff_doubles() -> {U.backoff_for(3n, T.ErrOther{}, None{}) == 120n : Nat}:
  {==}

def backoff_caps() -> {U.backoff_for(9n, T.ErrOther{}, None{}) == 600n : Nat}:
  {==}

def backoff_retry_after() -> {U.backoff_for(1n, T.ErrHttp429{}, Some{120n}) == 120n : Nat}:
  {==}

def backoff_retry_after_zero_429() -> {U.backoff_for(1n, T.ErrHttp429{}, Some{0n}) == 300n : Nat}:
  {==}

def backoff_retry_after_big_429() -> {U.backoff_for(1n, T.ErrHttp429{}, Some{700n}) == 1600n : Nat}:
  {==}

def backoff_retry_after_capped() -> {U.backoff_for(1n, T.ErrOther{}, Some{9000n}) == 3600n : Nat}:
  {==}

def backoff_never_below_computed() -> {U.backoff_for(5n, T.ErrOther{}, Some{10n}) == 480n : Nat}:
  {==}

def reason_names_new() -> {T.reason.name(T.ActiveIdle{}) == "active-idle" : String}:
  {==}

def reason_names_reset_unknown() -> {T.reason.name(T.ResetUnknown{}) == "reset-unknown" : String}:
  {==}

def reason_names_soonest() -> {T.reason.name(T.AlreadyConsumingSoonest{}) == "already-consuming-soonest" : String}:
  {==}

def reason_names_exhausted() -> {T.reason.name(T.AllExhausted{None{}}) == "all-exhausted" : String}:
  {==}

def trigger_names() -> {T.trigger.name(T.ConsumeFirstT{}) == "consume-first" : String}:
  {==}

def trigger_names_failover() -> {T.trigger.name(T.Failover{}) == "failover" : String}:
  {==}
