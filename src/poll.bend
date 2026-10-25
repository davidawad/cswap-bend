import Base
import ./json.bend as Json
import ./clock.bend as Clock
import ./policy/usage.bend as PUsage
import ./policy/types.bend as PT

# Usage windows, poll planning, failure backoff and decision trust: the pure
# rules of usage_store.py and poll_policy.py (claude-swap 0.27.2).
# Epochs are unix seconds (U32). Percentages are tenths of a percent (U32),
# so `42.5` is 425 and `100.0` is 1000. There is no jitter on the poll
# deadline (Bend has no random source); the reference's is +-10%.

def serve_ttl() -> U32:
  180

def decision_trust() -> U32:
  300

def trust_ceiling() -> U32:
  3600

def rate_limit_trust_ceiling() -> U32:
  7200

def claim_ttl() -> U32:
  90

def min_interval() -> U32:
  180

def urgent_interval() -> U32:
  60

def active_ceiling() -> U32:
  300

def candidate_default() -> U32:
  300

def candidate_ceiling() -> U32:
  600

def exhausted_interval() -> U32:
  600

def reset_slack() -> U32:
  60

def recent_429_window() -> U32:
  3600

def post_429_min() -> U32:
  360

def post_429_cap() -> U32:
  1800

def edge_backoff() -> U32:
  300

def backoff_base() -> U32:
  30

def backoff_cap() -> U32:
  600

def retry_margin() -> U32:
  900

def retry_floor_cap() -> U32:
  4500

def escalation_margin() -> U32:
  150

def min_u(+a: U32, +b: U32) -> U32:
  Clock.sel(U32.is_lt(a, b), a, b)

def max_u(+a: U32, +b: U32) -> U32:
  Clock.sel(U32.is_gt(a, b), a, b)

# a - b, floored at 0.
def sub0(+a: U32, +b: U32) -> U32:
  Clock.sel(U32.is_gt(a, b), (a - b : U32), 0)

def absdiff(+a: U32, +b: U32) -> U32:
  Clock.sel(U32.is_gt(a, b), (a - b : U32), (b - a : U32))

def tenths.mk(+i: String, +f: String) -> Maybe<&2, U32>:
  do Maybe<&2, U32>:
    ip : U32 <- U32.read(i)
    f1 : U32 <- Clock.num(f ++ "00", 0n, 1n)
    f2 : U32 <- Clock.num(f ++ "00", 1n, 1n)
    return (ip * 10 + f1 + Clock.sel(U32.is_ge(f2, 5), 1, 0) : U32)

def tenths.pick(ok: Bool, +i: String, +f: String) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      tenths.mk(i, f)
    case False{}:
      None{}

def tenths.parts(ps: List<&2, String>) -> Maybe<&2, U32>:
  match ps:
    case Con{+i, Nil{}}:
      tenths.pick(Clock.all_digits(i) && Bool.not(String.is_empty(i)) && Nat.is_le(String.length(i), 7n), i, "")
    case Con{+i, Con{+f, Nil{}}}:
      tenths.pick(Clock.all_digits(i) && Clock.all_digits(f) && Bool.not(String.is_empty(i)) && Nat.is_le(String.length(i), 7n), i, f)
    case _:
      None{}

# `42.5` -> 425, rounded to a tenth; None for anything but a plain decimal.
def tenths(s: String) -> Maybe<&2, U32>:
  tenths.parts(String.split(s, '.'))

def tenths.json(j: Json.Json) -> Maybe<&2, U32>:
  match j:
    case Json.JNum{t}:
      tenths(t)
    case _:
      None{}

# One usage window: its percentage (tenths) and when it resets.
type Win is Data:
  Win{pct: U32, reset: Maybe<&2, U32>}

def win.parse(m: Maybe<&2, String>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      Clock.parse_iso8601(s)

def win.reset(+w: Json.Json) -> Maybe<&2, U32>:
  win.parse(Json.as_string(Maybe.default(&2, Json.Json, Json.get("resets_at", w), Json.JNull{})))
def min_acc(acc: Maybe<&2, U32>, +p: U32) -> Maybe<&2, U32>:
  match acc:
    case None{}:
      Some{p}
    case Some{a}:
      Some{min_u(a, p)}

def any.step(r: Maybe<&2, U32>, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match r:
    case Some{x}:
      min_acc(acc, x)
    case None{}:
      acc

# The earliest reset of any relevant window (past or future): trust ends there.
def earliest_reset(ws: List<&2, Win>, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ws:
    case Nil{}:
      acc
    case Con{Win{p, r}, t}:
      earliest_reset(t, any.step(r, acc))

# When to poll next and the interval it came from.
type Sched is Data:
  Sched{next: U32, interval: U32}

def interval.moving(+base: U32) -> U32:
  max_u(min_interval(), (base / 2 : U32))

def interval.still(+base: U32, +ceil: U32) -> U32:
  min_u(ceil, max_u(min_interval(), (base * 3 / 2 : U32)))

# Default for unknown utilization, halve on movement, back off x1.5 otherwise.
def interval.base(prev: Maybe<&2, U32>, +dflt: U32) -> U32:
  match prev:
    case Some{+b}:
      Clock.sel(U32.is_eq(b, 0), dflt, b)
    case None{}:
      dflt

def interval.pick(known: Bool, moving: Bool, +dflt: U32, +base: U32, +ceil: U32) -> U32:
  match known moving:
    case False{} _:
      dflt
    case True{} True{}:
      interval.moving(base)
    case True{} False{}:
      interval.still(base, ceil)

def is_moving(prev: Maybe<&2, U32>, new: Maybe<&2, U32>) -> Bool:
  match prev new:
    case Some{a} Some{b}:
      U32.is_ge(absdiff(a, b), 10)
    case _ _:
      False{}

def is_known(prev: Maybe<&2, U32>, new: Maybe<&2, U32>) -> Bool:
  Maybe.is_some(&2, U32, prev) && Maybe.is_some(&2, U32, new)

def new_ge(new: Maybe<&2, U32>, +floor: U32) -> Bool:
  match new:
    case Some{n}:
      U32.is_ge(n, floor)
    case None{}:
      False{}

def exhausted(new: Maybe<&2, U32>) -> Bool:
  match new:
    case Some{n}:
      U32.is_ge(n, 1000)
    case None{}:
      False{}

def plan.r429(recent: Bool, +base: U32, +i: U32) -> U32:
  Clock.sel(recent, min_u(post_429_cap(), max_u(i, max_u((base * 3 / 2 : U32), post_429_min()))), i)

def plan.exh(ex: Bool, +i: U32) -> U32:
  Clock.sel(ex, max_u(i, exhausted_interval()), i)

def plan.interval(+i0: U32, +urgent: Bool, +recent: Bool, +base: U32, +ex: Bool) -> U32:
  plan.exh(ex, plan.r429(recent, base, Clock.sel(urgent, urgent_interval(), i0)))

def plan.cap(+next: U32, r: Maybe<&2, U32>) -> U32:
  match r:
    case Some{x}:
      min_u(next, (x + reset_slack() : U32))
    case None{}:
      next

def keep.m(ok: Bool, m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      m
    case False{}:
      None{}

def plan.reset.pick(ex: Bool, lim: Maybe<&2, U32>, fut: Maybe<&2, U32>, +now: U32) -> Maybe<&2, U32>:
  match ex lim:
    case True{} Some{+x}:
      keep.m(U32.is_gt(x, now), Some{x})
    case True{} None{}:
      None{}
    case False{} _:
      fut

def plan.fin(+now: U32, +interval: U32, r: Maybe<&2, U32>) -> Sched:
  Sched{plan.cap((now + interval : U32), r), interval}

def nat_maybe(m: Maybe<&2, U32>) -> Maybe<&2, Nat>:
  match m:
    case Some{x}:
      Some{U32.to_nat(x)}
    case None{}:
      None{}

def reset_nat(+w: Json.Json) -> Maybe<&2, Nat>:
  nat_maybe(win.reset(w))

def centi(m: Maybe<&2, U32>) -> Maybe<&2, Nat>:
  match m:
    case Some{t}:
      Some{U32.to_nat((t * 10 : U32))}
    case None{}:
      None{}

def pct_centi(+w: Json.Json) -> Maybe<&2, Nat>:
  centi(tenths.json(Maybe.default(&2, Json.Json, Json.get("pct", w), Json.JNull{})))

def scoped.mk(n: Maybe<&2, String>, p: Maybe<&2, Nat>, r: Maybe<&2, Nat>) -> Maybe<&2, PT.Scoped>:
  match n p:
    case Some{name} Some{x}:
      Some{PT.Scoped{name, x, r}}
    case _ _:
      None{}

def scoped.item(+w: Json.Json) -> Maybe<&2, PT.Scoped>:
  scoped.mk(Json.as_string(Maybe.default(&2, Json.Json, Json.get("name", w), Json.JNull{})), pct_centi(w), reset_nat(w))

def scoped.cons(m: Maybe<&2, PT.Scoped>, rest: List<&2, PT.Scoped>) -> List<&2, PT.Scoped>:
  match m:
    case Some{x}:
      x <> rest
    case None{}:
      rest

def scoped.all(ws: List<&2, Json.Json>) -> List<&2, PT.Scoped>:
  match ws:
    case Nil{}:
      []
    case Con{+w, t}:
      scoped.cons(scoped.item(w), scoped.all(t))

def window_of(+u: Json.Json, +k: String) -> Json.Json:
  Maybe.default(&2, Json.Json, Json.get(k, u), Json.JNull{})

# The policy core's view of a `usage` object (centi-percent windows).
def policy_usage(+u: Json.Json) -> PT.Usage:
  PT.Usage{0n, pct_centi(window_of(u, "five_hour")), reset_nat(window_of(u, "five_hour")), pct_centi(window_of(u, "seven_day")), reset_nat(window_of(u, "seven_day")), scoped.all(Json.to_list(window_of(u, "scoped"))), None{}, 0n, PT.ErrNone{}, 0n, None{}, 0n, 0n, 0n, 0n, PT.NoSentinel{}}

def maybe_u32(m: Maybe<&2, Nat>) -> Maybe<&2, U32>:
  match m:
    case Some{x}:
      Some{U32.from_nat(x)}
    case None{}:
      None{}

def win.back(ws: List<&2, PT.Win>) -> List<&2, Win>:
  match ws:
    case Nil{}:
      []
    case Con{PT.Win{p, r}, t}:
      Win{U32.from_nat(Nat.div(p, 10n)), maybe_u32(r)} <> win.back(t)

# Every window that gates an account (5h, 7d, and the scoped windows of the
# named models): policy's `windows`, back as tenths for the planner.
def relevant(+usage: Json.Json, +models: List<&2, String>) -> List<&2, Win>:
  win.back(PUsage.windows(policy_usage(usage), models))

def future.pick(ok: Bool, +x: U32, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      min_acc(acc, x)
    case False{}:
      acc

def future.step(r: Maybe<&2, U32>, +now: U32, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match r:
    case Some{+x}:
      future.pick(U32.is_gt(x, now), x, acc)
    case None{}:
      acc

def earliest_future(ws: List<&2, Win>, +now: U32, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ws:
    case Nil{}:
      acc
    case Con{Win{p, r}, t}:
      earliest_future(t, now, future.step(r, now, acc))

def max_acc(acc: Maybe<&2, U32>, +p: U32) -> Maybe<&2, U32>:
  match acc:
    case None{}:
      Some{p}
    case Some{a}:
      Some{max_u(a, p)}

def limiting.step(full: Bool, r: Maybe<&2, U32>, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match full r:
    case True{} Some{x}:
      max_acc(acc, x)
    case _ _:
      acc

def limiting_reset(ws: List<&2, Win>, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ws:
    case Nil{}:
      acc
    case Con{Win{p, r}, t}:
      limiting_reset(t, limiting.step(U32.is_ge(p, 1000), r, acc))

def plan.go(+usage: Json.Json, +models: List<&2, String>, +now: U32, +interval: U32, +ex: Bool) -> Sched:
  plan.fin(now, interval, plan.reset.pick(ex, limiting_reset(relevant(usage, models), None{}), earliest_future(relevant(usage, models), now, None{}), now))

def plan.with(+base: U32, +known: Bool, +moving: Bool, +ex: Bool, +in_band: Bool, +usage: Json.Json, +active: Bool, +models: List<&2, String>, +recent: Bool, +now: U32, +ceil: U32, +dflt: U32) -> Sched:
  plan.go(usage, models, now,
    plan.interval(interval.pick(known, moving, dflt, base, ceil), active && moving && Bool.not(recent) && in_band, recent, base, ex),
    ex)

def dflt_of(active: Bool) -> U32:
  Clock.sel(active, min_interval(), candidate_default())

def ceil_of(active: Bool) -> U32:
  Clock.sel(active, active_ceiling(), candidate_ceiling())

def plan.start(prev_interval: Maybe<&2, U32>, +prev: Maybe<&2, U32>, +new: Maybe<&2, U32>, +usage: Json.Json, +active: Bool, +threshold: U32, +models: List<&2, String>, recent: Bool, +now: U32) -> Sched:
  plan.with(interval.base(prev_interval, dflt_of(active)), is_known(prev, new), is_moving(prev, new), exhausted(new), new_ge(new, sub0(threshold, escalation_margin())),
    usage, active, models, recent, now, ceil_of(active), dflt_of(active))

def max_pct(ws: List<&2, Win>, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ws:
    case Nil{}:
      acc
    case Con{Win{p, r}, t}:
      max_pct(t, max_acc(acc, p))

def binding(usage: Json.Json, models: List<&2, String>) -> Maybe<&2, U32>:
  max_pct(relevant(usage, models), None{})

# plan_after_fetch (no jitter): `threshold` in tenths, `models` the scoped
# names that gate the account, times in unix seconds.
def plan_after_fetch(prev_interval: Maybe<&2, U32>, prev_usage: Json.Json, +new_usage: Json.Json, is_active: Bool, +threshold: U32, +models: List<&2, String>, recent_429: Bool, +now: U32) -> Sched:
  plan.start(prev_interval, binding(prev_usage, models), binding(new_usage, models), new_usage, is_active, threshold, models, recent_429, now)
