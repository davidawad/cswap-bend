import Base
import ../src/policy/types.bend as T
import ../src/policy/safe.bend as SF
import ../src/policy/algo.bend as A

# Ground equations for the behaviour-profile strategies on concrete fake
# scenarios. The world is the six-account one of tests/policy_test.bend
# (now = 1000, rows fetched at 970), centi-percent (9000 = 90 %), threshold 85.
#
# Others (utilization = the busier of 5h / 7d, headroom = 100 - that):
#   slot 2: 30 % (headroom 7000)   slot 3: 10 % (9000)   slot 4: 60 % (4000)
#   slot 5: 70 % (3000)            slot 6: 95 % (500)
# A proactive switch must land below the threshold (headroom >= 1501), so slot
# 6 is only a target when the active account is at its limit.

def now() -> Nat:
  1000n

def acct(slot: Nat, email: String, kind: T.AcctKind) -> T.Account:
  T.Account{slot, email, kind, False{}}

def six() -> List<&2, T.Account>:
  [
    acct(1n, "owner@example.test", T.FullLogin{}),
    acct(2n, "st2@example.test", T.SetupToken{}),
    acct(3n, "st3@example.test", T.SetupToken{}),
    acct(4n, "st4@example.test", T.SetupToken{}),
    acct(5n, "st5@example.test", T.SetupToken{}),
    acct(6n, "st6@example.test", T.SetupToken{})
  ]

# A fresh row: 5h and 7d utilization and the 7d reset.
def rowr(slot: Nat, five: Nat, seven: Nat, reset: Nat) -> T.Usage:
  T.Usage{slot, Some{five}, Some{8200n}, Some{seven}, Some{reset}, Nil{}, Some{970n}, 0n, T.ErrNone{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

def row(slot: Nat, five: Nat, seven: Nat) -> T.Usage:
  rowr(slot, five, seven, 262800n)

def row_backoff(slot: Nat, five: Nat, seven: Nat) -> T.Usage:
  T.Usage{slot, Some{five}, Some{8200n}, Some{seven}, Some{262800n}, Nil{}, Some{970n}, 1030n, T.ErrOther{}, T.failing(T.ErrNone{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

def row_cold(slot: Nat) -> T.Usage:
  T.Usage{slot, None{}, None{}, None{}, None{}, Nil{}, None{}, 1030n, T.ErrOther{}, T.failing(T.ErrOther{}), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

def others() -> List<&2, T.Usage>:
  [row(2n, 1000n, 3000n), row(3n, 500n, 1000n), row(4n, 5000n, 6000n), row(5n, 7000n, 2000n), row(6n, 100n, 9500n)]

def world(active: T.Usage) -> List<&2, T.Usage>:
  Con{active, others()}

def cfg85() -> T.Config:
  T.Config{8500n, Nil{}, T.Best{}, 60n, 300n, 1000n, 180n, 3n, False{}}

def st_at(t: Nat) -> T.State:
  T.State{Some{t}, None{}, None{}, T.NoSnap{}}

def sw(slot: Nat, t: T.Trigger, name: String, h: Nat) -> T.Decision:
  T.Switch{slot, t, name, h, T.MHead{}, None{}, None{}}

def auto(algo: SF.Algo, active: Nat, us: List<&2, T.Usage>) -> T.Decision:
  A.decide(algo, active, six(), us, now(), cfg85(), T.fresh_state(), T.fresh_mem())

def rot(algo: SF.Algo, active: Nat, us: List<&2, T.Usage>) -> T.Decision:
  A.rotate(algo, active, six(), us, now(), cfg85())

def at90() -> List<&2, T.Usage>:
  world(row(1n, 9000n, 4000n))

def at100() -> List<&2, T.Usage>:
  world(row(1n, 10000n, 4000n))

def at20() -> List<&2, T.Usage>:
  world(row(1n, 2000n, 4000n))

# ---- best: the reference engine, untouched
def best_proactive() -> {auto(SF.ABest{}, 1n, at90()) == sw(3n, T.Proactive{}, "proactive", 9000n) : T.Decision}:
  {==}

def best_below() -> {auto(SF.ABest{}, 1n, at20()) == T.NoSwitch{T.BelowThreshold{}, "40% < 85%"} : T.Decision}:
  {==}

# ---- round-robin: the next slot after the live one, wrapping
def rr_next() -> {auto(SF.ARoundRobin{}, 1n, at90()) == sw(2n, T.Proactive{}, "proactive", 7000n) : T.Decision}:
  {==}

def rr_next_from_2() -> {auto(SF.ARoundRobin{}, 2n, world(row(2n, 9000n, 4000n)) ) == sw(3n, T.Proactive{}, "proactive", 9000n) : T.Decision}:
  {==}

# The row for slot 1 is `others`-free here: slot 2 plays the active account.
def rr_wraps_past_the_end() -> {auto(SF.ARoundRobin{}, 5n, Con{row(1n, 1000n, 3000n), Con{row(2n, 1000n, 3000n), Con{row(3n, 500n, 1000n), Con{row(4n, 5000n, 6000n), Con{row(5n, 9000n, 2000n), [row(6n, 100n, 9500n)]}}}}}) == sw(1n, T.Proactive{}, "proactive", 7000n) : T.Decision}:
  {==}

# Slot 6 (headroom 500) is below the landing floor for a proactive switch...
def rr_skips_unfit_for_proactive() -> {auto(SF.ARoundRobin{}, 5n, Con{row(1n, 9500n, 3000n), Con{row(2n, 1000n, 3000n), Con{row(3n, 500n, 1000n), Con{row(4n, 5000n, 6000n), Con{row(5n, 9000n, 2000n), [row(6n, 100n, 9500n)]}}}}}) == sw(2n, T.Proactive{}, "proactive", 7000n) : T.Decision}:
  {==}

# ...but at the limit any headroom will do.
def rr_at_limit_takes_slot_6() -> {auto(SF.ARoundRobin{}, 5n, Con{row(1n, 9500n, 3000n), Con{row(2n, 1000n, 3000n), Con{row(3n, 500n, 1000n), Con{row(4n, 5000n, 6000n), Con{row(5n, 10000n, 2000n), [row(6n, 100n, 9500n)]}}}}}) == sw(6n, T.AtLimit{}, "at-limit", 500n) : T.Decision}:
  {==}

def rr_below() -> {auto(SF.ARoundRobin{}, 1n, at20()) == T.NoSwitch{T.BelowThreshold{}, "40% < 85%"} : T.Decision}:
  {==}

# ---- sticky: stay until the threshold, then the most headroom
def sticky_stays() -> {auto(SF.ASticky{}, 1n, at20()) == T.NoSwitch{T.BelowThreshold{}, "40% < 85%"} : T.Decision}:
  {==}

def sticky_leaves_for_most_headroom() -> {auto(SF.ASticky{}, 1n, at90()) == sw(3n, T.Proactive{}, "proactive", 9000n) : T.Decision}:
  {==}

def sticky_at_limit() -> {auto(SF.ASticky{}, 1n, at100()) == sw(3n, T.AtLimit{}, "at-limit", 9000n) : T.Decision}:
  {==}

# ---- drain-first: the busiest account still under the threshold
def drain_picks_busiest_under() -> {auto(SF.ADrainFirst{}, 1n, at90()) == sw(5n, T.Proactive{}, "proactive", 3000n) : T.Decision}:
  {==}

# At the limit it still refuses an account at or over the threshold (slot 6).
def drain_at_limit_stays_under() -> {auto(SF.ADrainFirst{}, 1n, at100()) == sw(5n, T.AtLimit{}, "at-limit", 3000n) : T.Decision}:
  {==}

def drain_nothing_under() -> {auto(SF.ADrainFirst{}, 1n, Con{row(1n, 9000n, 4000n), [row(2n, 9000n, 9000n), row(3n, 9500n, 9000n), row(6n, 100n, 9500n)]}) == T.NoSwitch{T.NoQualifyingCandidate{}, "no candidate is below the threshold and better than the active account by the hysteresis margin, or usage is unreadable this tick"} : T.Decision}:
  {==}

# ---- soonest-reset: the weekly window that resets first (use it or lose it)
def tail_of(us: List<&2, T.Usage>) -> List<&2, T.Usage>:
  match us:
    case Con{h, t}:
      t
    case Nil{}:
      Nil{}

def with_resets(r2: Nat, r3: Nat, r4: Nat, r5: Nat) -> List<&2, T.Usage>:
  [row(1n, 9000n, 4000n), rowr(2n, 1000n, 3000n, r2), rowr(3n, 500n, 1000n, r3), rowr(4n, 5000n, 6000n, r4), rowr(5n, 7000n, 2000n, r5), row(6n, 100n, 9500n)]

def soonest_picks_earliest_reset() -> {auto(SF.ASoonestReset{}, 1n, with_resets(262800n, 180000n, 120000n, 200000n)) == T.Switch{4n, T.Proactive{}, "proactive", 4000n, T.MReset{}, None{}, None{}} : T.Decision}:
  {==}

# A reset already past counts as unknown, which ranks last.
def soonest_past_reset_is_last() -> {auto(SF.ASoonestReset{}, 1n, with_resets(262800n, 180000n, 900n, 200000n)) == T.Switch{3n, T.Proactive{}, "proactive", 9000n, T.MReset{}, None{}, None{}} : T.Decision}:
  {==}

# Equal resets: more headroom wins (slot 3 over slot 2).
def soonest_tie_goes_to_headroom() -> {auto(SF.ASoonestReset{}, 1n, with_resets(180000n, 180000n, 262800n, 262800n)) == T.Switch{3n, T.Proactive{}, "proactive", 9000n, T.MReset{}, None{}, None{}} : T.Decision}:
  {==}

def soonest_below() -> {auto(SF.ASoonestReset{}, 1n, at20()) == T.NoSwitch{T.BelowThreshold{}, "40% < 85%"} : T.Decision}:
  {==}

# ---- safety: backoff, exhausted and unreadable candidates are never chosen
def backoff_world() -> List<&2, T.Usage>:
  [row(1n, 9000n, 4000n), row_backoff(2n, 1000n, 3000n), row(3n, 500n, 1000n), row(4n, 5000n, 6000n), row(5n, 7000n, 2000n), row(6n, 100n, 9500n)]

def rr_skips_backoff() -> {auto(SF.ARoundRobin{}, 1n, backoff_world()) == sw(3n, T.Proactive{}, "proactive", 9000n) : T.Decision}:
  {==}

def exhausted_world() -> List<&2, T.Usage>:
  [row(1n, 9000n, 4000n), row(2n, 10000n, 3000n), row(3n, 500n, 1000n), row(4n, 5000n, 6000n), row(5n, 7000n, 2000n), row(6n, 100n, 9500n)]

def rr_skips_exhausted() -> {auto(SF.ARoundRobin{}, 1n, exhausted_world()) == sw(3n, T.Proactive{}, "proactive", 9000n) : T.Decision}:
  {==}

def cold_world() -> List<&2, T.Usage>:
  [row(1n, 9000n, 4000n), row_cold(2n), row(3n, 500n, 1000n), row(4n, 5000n, 6000n), row(5n, 7000n, 2000n), row(6n, 100n, 9500n)]

def rr_skips_unknown() -> {auto(SF.ARoundRobin{}, 1n, cold_world()) == sw(3n, T.Proactive{}, "proactive", 9000n) : T.Decision}:
  {==}

# best keeps the reference's looser rule: a candidate in backoff stays eligible.
def best_backoff_still_eligible() -> {auto(SF.ABest{}, 1n, Con{row(1n, 9000n, 4000n), Con{row_backoff(3n, 500n, 1000n), [row(2n, 1000n, 3000n)]}}) == sw(3n, T.Proactive{}, "proactive", 9000n) : T.Decision}:
  {==}

def only_unsafe_left() -> {auto(SF.ARoundRobin{}, 1n, Con{row(1n, 9000n, 4000n), [row_cold(2n), row_backoff(3n, 500n, 1000n), row(4n, 10000n, 6000n)]}) == T.NoSwitch{T.NoQualifyingCandidate{}, "no candidate is below the threshold and better than the active account by the hysteresis margin, or usage is unreadable this tick"} : T.Decision}:
  {==}

# ---- the gates every strategy shares
def unknown_active_never_switches() -> {auto(SF.ASticky{}, 1n, Con{row_cold(1n), others()}) == T.NoSwitch{T.ActiveUsageUnknown{}, "headroom unknown; a profile strategy never switches away from an account it cannot read (use 'cswap switch NUM')"} : T.Decision}:
  {==}

def proactive_honours_cooldown() -> {A.decide(SF.ARoundRobin{}, 1n, six(), at90(), now(), cfg85(), st_at(940n), T.fresh_mem()) == T.NoSwitch{T.Cooldown{}, ""} : T.Decision}:
  {==}

def at_limit_ignores_cooldown() -> {A.decide(SF.ARoundRobin{}, 1n, six(), at100(), now(), cfg85(), st_at(940n), T.fresh_mem()) == sw(2n, T.AtLimit{}, "at-limit", 7000n) : T.Decision}:
  {==}

def unmanaged_active() -> {auto(SF.ASticky{}, 9n, at90()) == T.NoSwitch{T.UnmanagedActive{}, "run 'cswap --add-account' to include it in rotation"} : T.Decision}:
  {==}

def api_key_active() -> {A.decide(SF.ARoundRobin{}, 7n, Con{acct(7n, "k@x.test", T.ApiKey{}), six()}, at90(), now(), cfg85(), T.fresh_state(), T.fresh_mem()) == T.NoSwitch{T.ActiveApiKey{}, "API-key accounts have no quota to watch"} : T.Decision}:
  {==}

# An API-key account is never a target of these strategies.
def api_key_never_target() -> {auto(SF.ARoundRobin{}, 1n, Con{row(1n, 9000n, 4000n), [row(7n, 0n, 0n), row(3n, 500n, 1000n)]}) == sw(3n, T.Proactive{}, "proactive", 9000n) : T.Decision}:
  {==}

# ---- manual rotation: now, whatever the active's utilization
def rotate_rr() -> {rot(SF.ARoundRobin{}, 1n, at20()) == sw(2n, T.Proactive{}, "proactive", 7000n) : T.Decision}:
  {==}

def rotate_best_is_most_headroom() -> {rot(SF.ABest{}, 1n, at20()) == sw(3n, T.Proactive{}, "proactive", 9000n) : T.Decision}:
  {==}

def rotate_drain_first() -> {rot(SF.ADrainFirst{}, 1n, at20()) == sw(5n, T.Proactive{}, "proactive", 3000n) : T.Decision}:
  {==}

def rotate_soonest() -> {rot(SF.ASoonestReset{}, 1n, Con{row(1n, 2000n, 4000n), tail_of(with_resets(262800n, 180000n, 120000n, 200000n))}) == T.Switch{4n, T.Proactive{}, "proactive", 4000n, T.MReset{}, None{}, None{}} : T.Decision}:
  {==}

# Rotation still refuses an unreadable active account.
def rotate_unknown_active() -> {rot(SF.ARoundRobin{}, 1n, Con{row_cold(1n), others()}) == T.NoSwitch{T.ActiveUsageUnknown{}, "headroom unknown; a profile strategy never switches away from an account it cannot read (use 'cswap switch NUM')"} : T.Decision}:
  {==}

# ---- names
def parse_names() -> {SF.parse("drain-first") == Some{SF.ADrainFirst{}} : Maybe<&2, SF.Algo>}:
  {==}

def parse_unknown() -> {SF.parse("fastest") == None{} : Maybe<&2, SF.Algo>}:
  {==}

def name_round_trip() -> {SF.name(SF.ASoonestReset{}) == "soonest-reset" : String}:
  {==}
