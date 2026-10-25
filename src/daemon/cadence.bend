import Base

# How long the loop sleeps after a tick (autoswitch.py _next_delay and
# _respect_poll_plan). Bend has no random source, so the +-10 % jitter of the
# normal cadence is not applied: the delay is the interval itself.

# What a tick came to; the `--once` exit code is `exit_code`.

type Outcome is Data:
  Switched{}
  NoAction{}
  Blocked{}
  Failed{}

# What the tick tells the sleeper: when the soonest reset is (all exhausted),
# whether waiting a long time is right (no candidates), whether the active
# token is expired on an idle Claude Code, and the active row's next poll.
type Info is Data:
  Info{outcome: Outcome, sleep_until: Maybe<&2, U32>, blocked_long: Bool, idle_slow: Bool, next_poll_at: Maybe<&2, U32>}

def exit_code(o: Outcome) -> U32:
  match o:
    case Switched{}:
      0
    case Failed{}:
      1
    case NoAction{}:
      2
    case Blocked{}:
      3

def no_reset_fallback() -> U32:
  300

def max_sleep() -> U32:
  600

def urgent() -> U32:
  60

def sel(+c: Bool, +x: U32, +y: U32) -> U32:
  match c:
    case True{}:
      x
    case False{}:
      y

def max_u(+a: U32, +b: U32) -> U32:
  sel(U32.is_gt(a, b), a, b)

def min_u(+a: U32, +b: U32) -> U32:
  sel(U32.is_lt(a, b), a, b)

# a - b, 0 when b is later.
def since(+a: U32, +b: U32) -> U32:
  sel(U32.is_gt(a, b), (a - b : U32), 0)

# Shorten a normal sleep to the active row's own next poll, never under 60 s.
def respect_plan(+next_poll: Maybe<&2, U32>, +now: U32, +delay: U32) -> U32:
  match next_poll:
    case None{}:
      delay
    case Some{t}:
      min_u(delay, max_u(since(t, now), urgent()))

def blocked_delay(+until: Maybe<&2, U32>, +long: Bool, +now: U32, +interval: U32, +normal: U32) -> U32:
  match until:
    case Some{t}:
      min_u(max_u(since(t, now), interval), max_sleep())
    case None{}:
      sel(long, max_u(interval, no_reset_fallback()), normal)

def next_delay2(o: Outcome, info: Info, +now: U32, +interval: U32) -> U32:
  match o info:
    case Blocked{} Info{oc, until, long, idle, np}:
      blocked_delay(until, long, now, interval, respect_plan(np, now, interval))
    case NoAction{} Info{oc, until, long, idle, np}:
      sel(idle, max_u(interval, no_reset_fallback()), respect_plan(np, now, interval))
    case _ Info{oc, until, long, idle, np}:
      respect_plan(np, now, interval)

def next_delay(info: Info, +now: U32, +interval: U32) -> U32:
  match info:
    case Info{+oc, until, long, idle, np}:
      next_delay2(oc, info, now, interval)

# A `sleep` event is emitted only when the delay is over 1.5 intervals.
def announce(+delay: U32, +interval: U32) -> Bool:
  U32.is_gt((delay * 2 : U32), (interval * 3 : U32))
