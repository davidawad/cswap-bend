import Base
import ./json.bend as Json
import ./clock.bend as Clock
import ./policy/usage.bend as PUsage
import ./policy/types.bend as PT
import ./poll.bend as Poll

# A stored usage.json row as the planner reads it: failures, claims, holds, trust and
# eligibility to fetch (the rules of src/policy where it has them).

# The fields of one usage.json row that planning and display read.
type Row is Data:
  Row{fetched: Maybe<&2, U32>, last_good: Json.Json, last_attempt: Maybe<&2, U32>, failures: U32,
      last_error: Maybe<&2, String>, backoff_until: Maybe<&2, U32>, next_poll: Maybe<&2, U32>,
      interval: Maybe<&2, U32>, last429: Maybe<&2, U32>, strikes: U32, struck_fp: Maybe<&2, String>,
      claim_until: Maybe<&2, U32>, held_until: Maybe<&2, U32>}

def is_err(m: Maybe<&2, String>, +s: String) -> Bool:
  match m:
    case Some{x}:
      String.eq(x, s)
    case None{}:
      False{}

# A 429 on this token is recent enough to keep the post-429 cadence: measured
# from when the honoured backoff lifts, for one hour.
def recent_429.anchor(+l: U32, bu: Maybe<&2, U32>, is429: Bool) -> U32:
  match bu is429:
    case Some{b} True{}:
      Poll.max_u(l, b)
    case _ _:
      l

def recent.of(l: Maybe<&2, U32>, bu: Maybe<&2, U32>, is429: Bool, +now: U32) -> Bool:
  match l:
    case None{}:
      False{}
    case Some{+x}:
      U32.is_lt(now, (recent_429.anchor(x, bu, is429) + Poll.recent_429_window() : U32))

def recent_429(+r: Row, +now: U32) -> Bool:
  match r:
    case Row{fetched, lg, la, fl, le, bu, np, iv, l429, st, sfp, cu, hu}:
      recent.of(l429, bu, is_err(le, "http-429"), now)

def num.int(ps: List<&2, String>) -> Maybe<&2, U32>:
  match ps:
    case Con{i, t}:
      U32.read(i)
    case Nil{}:
      None{}

# An integer second count from a JSON number (`1792740000.1` -> 1792740000).
def num.u(j: Json.Json) -> Maybe<&2, U32>:
  match j:
    case Json.JNum{t}:
      num.int(String.split(t, '.'))
    case _:
      None{}

def jget(+k: String, +row: Json.Json) -> Json.Json:
  Maybe.default(&2, Json.Json, Json.get(k, row), Json.JNull{})

def num.field(+k: String, +row: Json.Json) -> Maybe<&2, U32>:
  num.u(jget(k, row))

def str.field(+k: String, +row: Json.Json) -> Maybe<&2, String>:
  Json.as_string(jget(k, row))

def obj_or_null(j: Json.Json) -> Json.Json:
  match j:
    case Json.JObj{f}:
      Json.JObj{f}
    case _:
      Json.JNull{}

def last_good.of(+row: Json.Json) -> Json.Json:
  obj_or_null(jget("lastGood", row))

def row.of(+row: Json.Json) -> Row:
  Row{num.field("fetchedAt", row), last_good.of(row), num.field("lastAttemptAt", row),
    Maybe.default(&2, U32, num.field("consecutiveFailures", row), 0), str.field("lastError", row),
    num.field("backoffUntil", row), num.field("nextPollAt", row), num.field("pollIntervalS", row),
    num.field("last429At", row), Maybe.default(&2, U32, num.field("authDeadStrikes", row), 0),
    str.field("struckFingerprint", row), num.field("claimUntil", row), num.field("heldUntil", row)}

def before.m(m: Maybe<&2, U32>, +now: U32) -> Bool:
  match m:
    case Some{x}:
      U32.is_lt(now, x)
    case None{}:
      False{}

def legacy_claim(m: Maybe<&2, U32>, +now: U32) -> Bool:
  match m:
    case Some{a}:
      U32.is_lt(Poll.sub0(now, a), 10)
    case None{}:
      False{}

# A fetch lease is live: claimUntil when present, else the legacy 10 s after
# lastAttemptAt.
def live_claim(claim_until: Maybe<&2, U32>, last_attempt: Maybe<&2, U32>, +now: U32) -> Bool:
  match claim_until:
    case Some{c}:
      U32.is_lt(now, c)
    case None{}:
      legacy_claim(last_attempt, now)

def age_le(age: Maybe<&2, U32>, +max: U32) -> Bool:
  match age:
    case None{}:
      False{}
    case Some{a}:
      U32.is_le(a, max)

def age_of(fetched: Maybe<&2, U32>, +now: U32) -> Maybe<&2, U32>:
  match fetched:
    case Some{f}:
      Some{Poll.sub0(now, f)}
    case None{}:
      None{}

def err_kind(rl: Bool) -> PT.ErrKind:
  match rl:
    case True{}:
      PT.ErrHttp429{}
    case False{}:
      PT.ErrOther{}

# Seconds to stay in backoff after the n-th failure: src/policy's backoff_for
# (30 s * 2^(n-1) capped at 600 s; a Retry-After raises it).
def failure_backoff(+failures: U32, retry_after: Maybe<&2, U32>, rate_limited: Bool) -> U32:
  U32.from_nat(PUsage.backoff_for(U32.to_nat(failures), err_kind(rate_limited), Poll.nat_maybe(retry_after)))

def nat_of(m: Maybe<&2, U32>, +d: U32) -> Nat:
  U32.to_nat(Maybe.default(&2, U32, m, d))

def blocked(r: Row, +now: U32) -> Bool:
  match r:
    case Row{fetched, lg, la, fl, le, bu, np, iv, l429, st, sfp, cu, hu}:
      U32.is_ge(st, 1) || before.m(bu, now) || before.m(hu, now) || live_claim(cu, la, now)

def mode.pick(+respect: Bool, +repair: Bool, +stale: Bool, +due: Bool, +none: Bool, +over: Bool) -> Bool:
  match respect repair:
    case True{} _:
      stale && (due || none || over)
    case False{} True{}:
      due || (stale && (none || over))
    case False{} False{}:
      due || stale

def mode.go(+respect: Bool, +repair: Bool, +fa: Maybe<&2, Nat>, +np: Maybe<&2, Nat>, +pi: Nat, +now: Nat) -> Bool:
  mode.pick(respect, repair, PUsage.poll.stale(fa, now, 180n), PUsage.poll.planned_due(np, now), PUsage.poll.unplanned(np), repair && PUsage.poll.overslept(np, now, pi))

def mode.row(r: Row, +now: U32, +respect: Bool, +repair: Bool) -> Bool:
  match r:
    case Row{fetched, lg, la, fl, le, bu, np, iv, l429, st, sfp, cu, hu}:
      mode.go(respect, repair, Poll.nat_maybe(fetched), Poll.nat_maybe(np), nat_of(iv, 600), U32.to_nat(now))

# Whether a stored row may be fetched now: not dead, in backoff, held or
# claimed, then by caller mode (on-demand `respect` = stale and due; the
# scheduled tick is policy's poll_due).
def row_eligible(+r: Row, +now: U32, +respect_plans: Bool, +repair: Bool) -> Bool:
  Bool.not(blocked(r, now)) && mode.row(r, now, respect_plans, repair)

def nat0(m: Maybe<&2, U32>) -> Nat:
  match m:
    case Some{x}:
      U32.to_nat(x)
    case None{}:
      0n

def err_pick(rl: Bool) -> PT.ErrKind:
  match rl:
    case True{}:
      PT.ErrHttp429{}
    case False{}:
      PT.ErrOther{}

def kind_of_err(m: Maybe<&2, String>) -> PT.ErrKind:
  match m:
    case Some{e}:
      err_pick(String.eq(e, "http-429"))
    case None{}:
      PT.ErrNone{}

def legacy_until(la: Maybe<&2, U32>) -> Nat:
  match la:
    case Some{a}:
      U32.to_nat((a + 10 : U32))
    case None{}:
      0n

# A claim lease: claimUntil, else the legacy 10 s after lastAttemptAt.
def lease_until(cu: Maybe<&2, U32>, la: Maybe<&2, U32>) -> Nat:
  match cu:
    case Some{c}:
      U32.to_nat(c)
    case None{}:
      legacy_until(la)

def policy_with(+u: PT.Usage, +fetched: Maybe<&2, U32>, +bu: Maybe<&2, U32>, +le: Maybe<&2, String>, +nf: U32, +np: Maybe<&2, U32>, +iv: Maybe<&2, U32>, +st: U32, +hu: Maybe<&2, U32>, +lease: Nat) -> PT.Usage:
  match u:
    case PT.Usage{slot, five, fr, seven, sr, ss, fa, bo, er, nfl, npp, pi, ad, hh, cc, se}:
      PT.Usage{slot, five, fr, seven, sr, ss, Poll.nat_maybe(fetched), nat0(bu), kind_of_err(le), U32.to_nat(nf), Poll.nat_maybe(np), nat0(iv), U32.to_nat(st), nat0(hu), lease, PT.NoSentinel{}}

# The policy core's view of a stored row: its windows, freshness and holds.
def policy_row(+r: Row) -> PT.Usage:
  match r:
    case Row{fetched, lg, la, fl, le, bu, np, iv, l429, st, sfp, cu, hu}:
      policy_with(Poll.policy_usage(lg), fetched, bu, le, fl, np, iv, st, hu, lease_until(cu, la))

def decision.pick(ok: Bool, lg: Json.Json) -> Json.Json:
  match ok:
    case True{}:
      lg
    case False{}:
      Json.JNull{}

def last_good_of(+r: Row) -> Json.Json:
  match r:
    case Row{fetched, lg, la, fl, le, bu, np, iv, l429, st, sfp, cu, hu}:
      lg

# The value switch decisions run on: last-good while policy trusts it (at most
# 300 s old, or deliberately stale and inside the cap), JNull when unknown.
def decision_usage(+r: Row, models: List<&2, String>, +now: U32) -> Json.Json:
  decision.pick(PUsage.trusted(policy_row(r), U32.to_nat(now), models), last_good_of(r))
