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

# A fresh row at time 3000 (fetched 30 s ago).
def row2(slot: Nat, five: Nat, seven: Nat) -> T.Usage:
  T.Usage{slot, Some{five}, Some{8200n}, Some{seven}, Some{262800n}, Nil{}, Some{2970n}, 0n, T.ErrNone{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

# Failover, the idle hold, the engine counters, API-key accounts and
# consume-first. Clock 1000; rows fetched at 970 unless built otherwise.

# A fresh row with explicit reset times.
def rowr(slot: Nat, five: Nat, five_reset: Nat, seven: Nat, seven_reset: Nat) -> T.Usage:
  T.Usage{slot, Some{five}, Some{five_reset}, Some{seven}, Some{seven_reset}, Nil{}, Some{970n}, 0n, T.ErrNone{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

def row_sentinel(slot: Nat, s: T.Sentinel) -> T.Usage:
  T.Usage{slot, None{}, None{}, None{}, None{}, Nil{}, None{}, 0n, T.ErrNone{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, s}

def tok_expired(slot: Nat) -> T.Usage:
  row_sentinel(slot, T.TokenExpired{})

def mem_at(unhealthy: Nat, idle_since: Nat) -> T.Mem:
  T.Mem{unhealthy, Some{idle_since}}

def dec(active: Nat, as: List<&2, T.Account>, us: List<&2, T.Usage>, now: Nat, cfg: T.Config, st: T.State, mem: T.Mem) -> T.Decision:
  D.decide(active, as, us, now, cfg, st, mem)

def cfg_cf() -> T.Config:
  T.Config{8500n, Nil{}, T.ConsumeFirst{}, 60n, 300n, 1000n, 180n, 3n, False{}}

def cfg_api() -> T.Config:
  T.Config{8500n, Nil{}, T.Best{}, 60n, 300n, 1000n, 180n, 3n, True{}}

# --- the idle hold and failover (patch 0002: only an expired token fails over)

# Fresh process, expired token: hold (idle), never fail over.
def idle_hold_first_tick() -> {dec(1n, six(), Con{tok_expired(1n), others()}, now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.ActiveIdle{}, "token expired while Claude Code is idle; resumes on next use"} : T.Decision}:
  {==}

# Held 900 s of the 1800 s allowance: still idle.
def idle_hold_continues() -> {dec(1n, six(), Con{tok_expired(1n), others()}, 1000n, cfg85(), T.fresh_state(), mem_at(2n, 100n)) == T.NoSwitch{T.ActiveIdle{}, "token expired while Claude Code is idle; resumes on next use"} : T.Decision}:
  {==}

# Hold exhausted, second unhealthy tick of three: counted, no failover yet.
def failover_counting() -> {dec(1n, six(), Con{tok_expired(1n), others()}, 3000n, cfg85(), T.fresh_state(), mem_at(1n, 0n)) == T.NoSwitch{T.ActiveUsageUnknown{}, "2/3 before failover"} : T.Decision}:
  {==}

def others3000() -> List<&2, T.Usage>:
  [row2(2n, 1000n, 3000n), row2(3n, 500n, 1000n), row2(4n, 5000n, 6000n), row2(5n, 7000n, 2000n), row2(6n, 100n, 9500n)]

# Third unhealthy tick: failover to the most headroom, cooldown ignored.
def failover_fires() -> {dec(1n, six(), Con{tok_expired(1n), others3000()}, 3000n, cfg85(), st_at(2990n), mem_at(2n, 0n)) == T.Switch{3n, T.Failover{}, "failover", 9000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# Any other sentinel is "unknown": never counted, never a failover.
def other_sentinel_never_fails_over() -> {dec(1n, six(), Con{row_sentinel(1n, T.OtherSentinel{}), others3000()}, 3000n, cfg85(), T.fresh_state(), mem_at(9n, 0n)) == T.NoSwitch{T.ActiveUsageUnknown{}, "headroom unknown; not counted toward failover"} : T.Decision}:
  {==}

# The counters.
def mem_known_resets() -> {D.mem_after(1n, six(), seeded(2000n, 4000n), now(), cfg85(), mem_at(2n, 5n)) == T.fresh_mem() : T.Mem}:
  {==}

def mem_expired_starts_hold() -> {D.mem_after(1n, six(), Con{tok_expired(1n), others()}, now(), cfg85(), T.fresh_mem()) == T.Mem{0n, Some{1000n}} : T.Mem}:
  {==}

def mem_expired_counts_after_hold() -> {D.mem_after(1n, six(), Con{tok_expired(1n), others3000()}, 3000n, cfg85(), mem_at(1n, 0n)) == T.Mem{2n, Some{0n}} : T.Mem}:
  {==}

def mem_other_sentinel_resets() -> {D.mem_after(1n, six(), Con{row_sentinel(1n, T.OtherSentinel{}), others()}, now(), cfg85(), mem_at(2n, 5n)) == T.fresh_mem() : T.Mem}:
  {==}

def mem_unmanaged_untouched() -> {D.mem_after(9n, six(), seeded(2000n, 4000n), now(), cfg85(), mem_at(2n, 5n)) == mem_at(2n, 5n) : T.Mem}:
  {==}

# --- API-key accounts

def api_accts() -> List<&2, T.Account>:
  [acct(1n, "a", T.FullLogin{}), acct(2n, "b", T.SetupToken{}), acct(3n, "c", T.ApiKey{})]

# Every OAuth candidate exhausted: with the flag, the API-key account is the
# last resort; without it, all-exhausted.
def api_last_resort() -> {dec(1n, api_accts(), [row(1n, 10000n, 0n), row(2n, 10000n, 0n)], now(), cfg_api(), T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.AtLimit{}, "at-limit", 0n, T.MApiLast{}, None{}, None{}} : T.Decision}:
  {==}

def api_not_without_flag() -> {dec(1n, api_accts(), [row(1n, 10000n, 0n), row(2n, 10000n, 0n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.AllExhausted{Some{8200n}}, ""} : T.Decision}:
  {==}

# A healthy OAuth candidate beats the API-key account.
def api_after_oauth() -> {dec(1n, api_accts(), [row(1n, 10000n, 0n), row(2n, 1000n, 0n)], now(), cfg_api(), T.fresh_state(), T.fresh_mem()) == T.Switch{2n, T.AtLimit{}, "at-limit", 9000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# An API-key active account is watched only with the flag, and has no windows.
def api_active_with_flag() -> {dec(1n, [acct(1n, "a", T.ApiKey{}), acct(2n, "b", T.SetupToken{})], [row(2n, 0n, 0n)], now(), cfg_api(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.ActiveUsageUnknown{}, "headroom unknown; not counted toward failover"} : T.Decision}:
  {==}

# --- consume-first: rank by the weekly reset, below the threshold too

def cf_rows() -> List<&2, T.Usage>:
  [rowr(1n, 2000n, 8200n, 4000n, 18000n), rowr(2n, 1000n, 8200n, 3000n, 10000n), rowr(3n, 500n, 8200n, 1000n, 14000n), rowr(4n, 5000n, 8200n, 6000n, 20000n)]

def cf_accts() -> List<&2, T.Account>:
  [acct(1n, "a", T.FullLogin{}), acct(2n, "b", T.SetupToken{}), acct(3n, "c", T.SetupToken{}), acct(4n, "d", T.SetupToken{})]

# Healthy active, but slot 2's weekly window resets first and has room.
def cf_moves_to_soonest() -> {dec(1n, cf_accts(), cf_rows(), now(), cfg_cf(), T.fresh_state(), T.fresh_mem()) == T.Switch{2n, T.ConsumeFirstT{}, "consume-first", 7000n, T.MReset{}, Some{10000n}, None{}} : T.Decision}:
  {==}

# Nobody resets sooner than the active account.
def cf_already_soonest() -> {dec(1n, cf_accts(), [rowr(1n, 2000n, 8200n, 4000n, 5000n), rowr(2n, 1000n, 8200n, 3000n, 10000n), rowr(3n, 500n, 8200n, 1000n, 14000n), rowr(4n, 5000n, 8200n, 6000n, 20000n)], now(), cfg_cf(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.AlreadyConsumingSoonest{}, "no sooner-resetting account with room to spare"} : T.Decision}:
  {==}

# The active account's weekly reset is unknown.
def cf_reset_unknown() -> {dec(1n, cf_accts(), Con{T.Usage{1n, Some{2000n}, Some{8200n}, Some{4000n}, None{}, Nil{}, Some{970n}, 0n, T.ErrNone{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}, Con{rowr(2n, 1000n, 8200n, 3000n, 10000n), Nil{}}}, now(), cfg_cf(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.ResetUnknown{}, "active account's weekly reset time is unknown; consume-first is idle until it is reported"} : T.Decision}:
  {==}

# Cooldown bounds consume-first moves.
def cf_cooldown() -> {dec(1n, cf_accts(), cf_rows(), now(), cfg_cf(), st_at(940n), T.fresh_mem()) == T.NoSwitch{T.Cooldown{}, ""} : T.Decision}:
  {==}

# Healthy and alone: below the threshold, as under best.
def cf_alone_below_threshold() -> {dec(1n, [acct(1n, "a", T.FullLogin{})], [rowr(1n, 2000n, 8200n, 4000n, 18000n)], now(), cfg_cf(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.BelowThreshold{}, "40% < 85%"} : T.Decision}:
  {==}

# Past the threshold consume-first still ranks by weekly reset, not headroom:
# slot 2 resets first although slot 3 has more headroom; hysteresis does not
# apply under consume-first.
def cf_proactive_by_reset() -> {dec(1n, cf_accts(), Con{rowr(1n, 9000n, 8200n, 4000n, 18000n), Con{rowr(2n, 1000n, 8200n, 3000n, 10000n), Con{rowr(3n, 500n, 8200n, 1000n, 14000n), Nil{}}}}, now(), cfg_cf(), T.fresh_state(), T.fresh_mem()) == T.Switch{2n, T.Proactive{}, "proactive", 7000n, T.MReset{}, Some{10000n}, None{}} : T.Decision}:
  {==}

# --- the no-return bar
