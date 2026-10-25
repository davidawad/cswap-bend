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

# The no-return bar and recovery mode. Clock 1000; rows fetched at 970.

# A fresh row with explicit reset times.
def rowr(slot: Nat, five: Nat, five_reset: Nat, seven: Nat, seven_reset: Nat) -> T.Usage:
  T.Usage{slot, Some{five}, Some{five_reset}, Some{seven}, Some{seven_reset}, Nil{}, Some{970n}, 0n, T.ErrNone{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

def dec(active: Nat, as: List<&2, T.Account>, us: List<&2, T.Usage>, now: Nat, cfg: T.Config, st: T.State, mem: T.Mem) -> T.Decision:
  D.decide(active, as, us, now, cfg, st, mem)

def bar_accts() -> List<&2, T.Account>:
  [acct(1n, "a", T.FullLogin{}), acct(2n, "b", T.SetupToken{}), acct(3n, "c", T.SetupToken{})]

# The engine moved 3 -> 1 and slot 3 has not recovered (same headroom as at
# departure, same reset): it is barred; slot 2 wins instead.
def st_moved_from_3() -> T.State:
  T.State{Some{200n}, Some{1n}, Some{3n}, T.Snap{Some{2300n}, Some{8200n}, Some{T.Proactive{}}}}

def bar_rows() -> List<&2, T.Usage>:
  [rowr(1n, 9000n, 8200n, 1000n, 262800n), rowr(2n, 7800n, 8200n, 1000n, 262800n), rowr(3n, 7700n, 8200n, 3000n, 262800n)]

def bar_blocks_the_way_back() -> {dec(1n, bar_accts(), bar_rows(), now(), cfg85(), st_moved_from_3(), T.fresh_mem()) == T.Switch{2n, T.Proactive{}, "proactive", 2200n, T.MHead{}, None{}, Some{3n}} : T.Decision}:
  {==}

# With nobody else to go to and no recovery, the bar leaves nothing.
def bar_leaves_nothing() -> {dec(1n, [acct(1n, "a", T.FullLogin{}), acct(3n, "c", T.SetupToken{})], [rowr(1n, 9000n, 8200n, 1000n, 262800n), rowr(3n, 7700n, 8200n, 3000n, 262800n)], now(), cfg85(), st_moved_from_3(), T.fresh_mem()) == T.NoSwitch{T.NoQualifyingCandidate{}, "no candidate is below the threshold and better than the active account by the hysteresis margin, or usage is unreadable this tick"} : T.Decision}:
  {==}

# At-limit escapes the bar.
def bar_at_limit_escapes() -> {dec(1n, bar_accts(), Con{rowr(1n, 10000n, 8200n, 1000n, 262800n), Con{rowr(2n, 9800n, 8200n, 1000n, 262800n), Con{rowr(3n, 7700n, 8200n, 3000n, 262800n), Nil{}}}}, now(), cfg85(), st_moved_from_3(), T.fresh_mem()) == T.Switch{3n, T.AtLimit{}, "at-limit", 2300n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# A hand switch away (live is 2, not 1) lifts the bar.
def bar_lifted_by_hand_switch() -> {dec(2n, bar_accts(), Con{rowr(1n, 9000n, 8200n, 1000n, 262800n), Con{rowr(2n, 9000n, 8200n, 1000n, 262800n), Con{rowr(3n, 7700n, 8200n, 3000n, 262800n), Nil{}}}}, now(), cfg85(), st_moved_from_3(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 2300n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# Recovered (headroom rose three points past the baseline) but not beating
# the active outright: the bar stands on the first ranking, which finds
# nothing, and the retry without the bar picks it.
def st_recovered_from_3() -> T.State:
  T.State{Some{200n}, Some{1n}, Some{3n}, T.Snap{Some{2000n}, Some{8200n}, Some{T.Proactive{}}}}

def bar_released_when_recovered_and_alone() -> {dec(1n, [acct(1n, "a", T.FullLogin{}), acct(3n, "c", T.SetupToken{})], [rowr(1n, 8600n, 8200n, 1000n, 262800n), rowr(3n, 7600n, 8200n, 3000n, 262800n)], now(), cfg85(), st_recovered_from_3(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 2400n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# A failover departure is released by a landing spot (headroom above 100 - threshold).
def st_failed_over_from_3() -> T.State:
  T.State{Some{200n}, Some{1n}, Some{3n}, T.Snap{None{}, None{}, Some{T.Failover{}}}}

def bar_failover_departure_landing() -> {dec(1n, [acct(1n, "a", T.FullLogin{}), acct(3n, "c", T.SetupToken{})], [rowr(1n, 8600n, 8200n, 1000n, 262800n), rowr(3n, 7600n, 8200n, 3000n, 262800n)], now(), cfg85(), st_failed_over_from_3(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 2400n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

# --- recovery mode: everything at or over the threshold

def rec_accts() -> List<&2, T.Account>:
  [acct(1n, "a", T.FullLogin{}), acct(2n, "b", T.SetupToken{}), acct(3n, "c", T.SetupToken{})]

# Active 95 %, back at 11000; slot 3 (92 %, back at 2000) returns first.
def rec_soonest_wins() -> {dec(1n, rec_accts(), [rowr(1n, 9500n, 11000n, 1000n, 262800n), rowr(2n, 9000n, 3000n, 1000n, 262800n), rowr(3n, 9200n, 2000n, 1000n, 262800n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 800n, T.MRec0{}, Some{2000n}, None{}} : T.Decision}:
  {==}

# A candidate that does not come back 300 s before the active one is out.
def rec_hysteresis() -> {dec(1n, rec_accts(), [rowr(1n, 9500n, 11000n, 1000n, 262800n), rowr(2n, 9000n, 10900n, 1000n, 262800n), rowr(3n, 9200n, 10800n, 1000n, 262800n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.NoQualifyingCandidate{}, "no candidate is below the threshold and better than the active account by the hysteresis margin, or usage is unreadable this tick"} : T.Decision}:
  {==}

# Equal recovery: the most headroom, then sequence order.
def rec_tie_most_headroom() -> {dec(1n, rec_accts(), [rowr(1n, 9500n, 11000n, 1000n, 262800n), rowr(2n, 9200n, 3000n, 1000n, 262800n), rowr(3n, 9000n, 3000n, 1000n, 262800n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 1000n, T.MRec0{}, Some{3000n}, None{}} : T.Decision}:
  {==}

# Active and candidates all far from resetting: rank by headroom, but only
# candidates holding twice the active headroom (400000 s is past the horizon).
def rec_far_by_headroom() -> {dec(1n, rec_accts(), [rowr(1n, 9900n, 25000n, 1000n, 262800n), rowr(2n, 9000n, 25000n, 1000n, 262800n), rowr(3n, 9200n, 25000n, 1000n, 262800n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{2n, T.Proactive{}, "proactive", 1000n, T.MRec1{}, Some{25000n}, None{}} : T.Decision}:
  {==}

# Not twice the active headroom: nobody qualifies, the active keeps the work.
def rec_far_ratio_blocks() -> {dec(1n, rec_accts(), [rowr(1n, 9000n, 25000n, 1000n, 262800n), rowr(2n, 9000n, 25000n, 1000n, 262800n), rowr(3n, 9200n, 25000n, 1000n, 262800n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.NoQualifyingCandidate{}, "no candidate is below the threshold and better than the active account by the hysteresis margin, or usage is unreadable this tick"} : T.Decision}:
  {==}

# The one-way fallback: below twice the active headroom, but at least the
# active's, back more than 300 s sooner, and the active nearly spent.
def rec_fallback() -> {dec(1n, rec_accts(), [rowr(1n, 9750n, 30000n, 1000n, 262800n), rowr(2n, 9600n, 25000n, 1000n, 262800n), rowr(3n, 9650n, 20000n, 1000n, 262800n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 350n, T.MFallback{}, Some{20000n}, None{}} : T.Decision}:
  {==}

# Everything spent (at most 3 %): recovery decides whatever the horizon.
def rec_all_spent() -> {dec(1n, rec_accts(), [rowr(1n, 9850n, 30000n, 1000n, 262800n), rowr(2n, 9900n, 25000n, 1000n, 262800n), rowr(3n, 9800n, 20000n, 1000n, 262800n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{3n, T.Proactive{}, "proactive", 200n, T.MRec0{}, Some{20000n}, None{}} : T.Decision}:
  {==}

# At-limit never uses recovery mode: the most headroom wins.
def rec_at_limit_by_headroom() -> {dec(1n, rec_accts(), [rowr(1n, 10000n, 11000n, 1000n, 262800n), rowr(2n, 9000n, 3000n, 1000n, 262800n), rowr(3n, 9200n, 2000n, 1000n, 262800n)], now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.Switch{2n, T.AtLimit{}, "at-limit", 1000n, T.MHead{}, None{}, None{}} : T.Decision}:
  {==}

