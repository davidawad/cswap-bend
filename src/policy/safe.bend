import Base
import ./types.bend as T
import ./usage.bend as U
import ./rank.bend as R

# Behaviour profiles, part 1: the strategies other than `best`, and the one
# candidate picker they share. A strategy only chooses a ranking key; whether
# a candidate may be chosen at all is `safe`, the same for every strategy.
#
# `safe`: an OAuth account that is enabled and not the live slot, with a
# trusted reading whose headroom is above zero, and not in backoff. Unlike
# `best` (which keeps a backoff row with a still-trusted reading eligible to
# stay byte-identical with the reference), these strategies skip an account
# in backoff.

type Algo is Data:
  ABest{}
  ARoundRobin{}
  ASoonestReset{}
  ASticky{}
  ADrainFirst{}

# A candidate with its ranking key (smaller wins: `k1`, then `k2`) and its
# headroom. `k1` None is infinity.
type Cd is Data:
  Cd{slot: Nat, k1: Maybe<&2, Nat>, k2: Nat, h: Nat}

# The reading is decision-grade and carries a headroom.
def known(+m: Maybe<&2, Nat>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      True{}

def exhausted(+m: Maybe<&2, Nat>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      Nat.is_eq(x, 0n)

def backed_off(+m: Maybe<&2, T.Usage>, +now: Nat) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{u}:
      U.in_backoff(u, now)

# A row with a trusted headroom above zero, not in backoff.
def row.safe(+m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  known(U.head.row(m, now, ms)) && Bool.not(exhausted(U.head.row(m, now, ms))) && Bool.not(backed_off(m, now))

def safe(+a: T.Account, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  R.isc(a, active) && row.safe(U.usage.of(U.account.slot(a), us), now, ms)

def h.of(+m: Maybe<&2, Nat>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{x}:
      x

# ---------------------------------------------------------------- ranking keys

def rr.group.at(+after: Bool) -> Nat:
  match after:
    case True{}:
      0n
    case False{}:
      1n

def rr.group(+slot: Nat, +active: Nat) -> Nat:
  rr.group.at(Nat.is_gt(slot, active))

# round-robin: the next slot after the live one, wrapping to the lowest.
# soonest-reset: the weekly window that resets first (unknown last), then more
# headroom. drain-first: the least headroom (the most used). best, sticky: the
# most headroom. Ties go to the first account in sequence order.
def key1(+algo: Algo, +active: Nat, +slot: Nat, +reset: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match algo:
    case ARoundRobin{}:
      Some{rr.group(slot, active)}
    case ASoonestReset{}:
      reset
    case o:
      Some{0n}

def key2(+algo: Algo, +slot: Nat, +h: Nat) -> Nat:
  match algo:
    case ARoundRobin{}:
      slot
    case ADrainFirst{}:
      h
    case o:
      Nat.sub(T.full(), h)

def key(+algo: Algo, +active: Nat, +slot: Nat, +h: Nat, +reset: Maybe<&2, Nat>) -> Cd:
  Cd{slot, key1(algo, active, slot, reset), key2(algo, slot, h), h}

def lt1(+a: Maybe<&2, Nat>, +b: Maybe<&2, Nat>) -> Bool:
  R.rec.rle(a, b) && Bool.not(R.rec.req(a, b))

# c ranks strictly before d.
def cd.lt(+c: Cd, +d: Cd) -> Bool:
  match c d:
    case Cd{s1, a1, a2, h1} Cd{s2, b1, b2, h2}:
      lt1(a1, b1) || (R.rec.req(a1, b1) && Nat.is_lt(a2, b2))

# ------------------------------------------------------------- the candidates

def cand.need(+ok: Bool, +c: Cd) -> Maybe<&2, Cd>:
  match ok:
    case True{}:
      Some{c}
    case False{}:
      None{}

def cand.rows(+algo: Algo, +a: T.Account, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +need: Nat, +m: Maybe<&2, T.Usage>) -> Maybe<&2, Cd>:
  cand.need(Nat.is_ge(h.of(U.head.row(m, now, ms)), need), key(algo, active, U.account.slot(a), h.of(U.head.row(m, now, ms)), R.seven.row(m, now, ms)))

# The candidate `a` is when it is safe and has the headroom the landing needs.
def cand.go(+sf: Bool, +algo: Algo, +a: T.Account, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +need: Nat) -> Maybe<&2, Cd>:
  match sf:
    case True{}:
      cand.rows(algo, a, active, us, now, ms, need, U.usage.of(U.account.slot(a), us))
    case False{}:
      None{}

def cand(+algo: Algo, +a: T.Account, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +need: Nat) -> Maybe<&2, Cd>:
  cand.go(safe(a, active, us, now, ms), algo, a, active, us, now, ms, need)

def merge.at(+tail_first: Bool, +c: Cd, +d: Cd) -> Maybe<&2, Cd>:
  match tail_first:
    case True{}:
      Some{d}
    case False{}:
      Some{c}

def merge.some(+c: Cd, +tail: Maybe<&2, Cd>) -> Maybe<&2, Cd>:
  match tail:
    case None{}:
      Some{c}
    case Some{d}:
      merge.at(cd.lt(d, c), c, d)

# The head's candidate against the best of the rest; the head keeps a tie.
def merge(+m: Maybe<&2, Cd>, +tail: Maybe<&2, Cd>) -> Maybe<&2, Cd>:
  match m:
    case None{}:
      tail
    case Some{c}:
      merge.some(c, tail)

# The best candidate in sequence order.
def pick(+algo: Algo, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +need: Nat) -> Maybe<&2, Cd>:
  match as:
    case Nil{}:
      None{}
    case Con{a, t}:
      merge(cand(algo, a, active, us, now, ms, need), pick(algo, t, active, us, now, ms, need))

# ----------------------------------------------------------------------- names

def name.pick(+hit: Bool, +a: Algo, +rest: Maybe<&2, Algo>) -> Maybe<&2, Algo>:
  match hit:
    case True{}:
      Some{a}
    case False{}:
      rest

# The strategy a name stands for.
def parse(+s: String) -> Maybe<&2, Algo>:
  name.pick(String.eq(s, "best"), ABest{},
    name.pick(String.eq(s, "round-robin"), ARoundRobin{},
      name.pick(String.eq(s, "soonest-reset"), ASoonestReset{},
        name.pick(String.eq(s, "sticky"), ASticky{},
          name.pick(String.eq(s, "drain-first"), ADrainFirst{}, None{})))))

def name(+algo: Algo) -> String:
  match algo:
    case ABest{}:
      "best"
    case ARoundRobin{}:
      "round-robin"
    case ASoonestReset{}:
      "soonest-reset"
    case ASticky{}:
      "sticky"
    case ADrainFirst{}:
      "drain-first"

def names() -> List<&2, String>:
  ["best", "round-robin", "soonest-reset", "sticky", "drain-first"]

# `best` keeps the reference's engine (and its looser eligibility); the rest
# use `pick`.
def strict(+algo: Algo) -> Bool:
  match algo:
    case ABest{}:
      False{}
    case o:
      True{}
