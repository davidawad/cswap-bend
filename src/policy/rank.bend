import Base
import ./types.bend as T
import ./usage.bend as U

# Candidate ranking: recovery and reset times, eligibility, and the pickers
# for each ranking family (headroom, weekly reset, recovery).

# ------------------------------------------------ times, with None = inf

# Measured candidates: any, all at or over the threshold, best headroom.
type Meas is Data:
  Meas{any: Bool, all: Bool, best: Nat}

# What a tick selects with: the live slot, the bar, the least headroom a
# target needs, the usage rows, the clock and the wanted models.
type Sel is Data:
  Sel{active: Nat, bar: Maybe<&2, Nat>, need: Nat, us: List<&2, T.Usage>, now: Nat, ms: List<&2, String>}

def rec.within(+r: Maybe<&2, Nat>, +now: Nat) -> Bool:
  match r:
    case None{}:
      False{}
    case Some{t}:
      Nat.is_le(Nat.sub(t, now), 14400n)

# c >= a - 300 s (the recovery hysteresis), with inf for None.
def rec.ge_minus(+c: Maybe<&2, Nat>, +a: Maybe<&2, Nat>) -> Bool:
  match c a:
    case None{} _:
      True{}
    case Some{t} None{}:
      False{}
    case Some{t} Some{x}:
      Nat.is_ge(Nat.add(t, 300n), x)

def rec.lt_minus(+c: Maybe<&2, Nat>, +a: Maybe<&2, Nat>) -> Bool:
  Bool.not(rec.ge_minus(c, a))

def rec.req(+x: Maybe<&2, Nat>, +y: Maybe<&2, Nat>) -> Bool:
  match x y:
    case None{} None{}:
      True{}
    case None{} Some{b}:
      False{}
    case Some{a} None{}:
      False{}
    case Some{a} Some{b}:
      Nat.is_eq(a, b)

# x <= y.
def rec.rle(+x: Maybe<&2, Nat>, +y: Maybe<&2, Nat>) -> Bool:
  match x y:
    case None{} None{}:
      True{}
    case None{} Some{b}:
      False{}
    case Some{a} None{}:
      True{}
    case Some{a} Some{b}:
      Nat.is_le(a, b)

def rec.min(+x: Maybe<&2, Nat>, +y: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match x y:
    case None{} _:
      y
    case Some{a} None{}:
      x
    case Some{a} Some{b}:
      Some{Nat.min(a, b)}

def rec.after.at(+ok: Bool, +t: Nat) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      Some{t}
    case False{}:
      None{}

# A reset that is still ahead of us; past or unknown is inf.
def rec.after(+r: Maybe<&2, Nat>, +now: Nat) -> Maybe<&2, Nat>:
  match r:
    case None{}:
      None{}
    case Some{t}:
      rec.after.at(Nat.is_gt(t, now), t)

# ----------------------------------------------- binding window recovery

def win.pct(+w: T.Win) -> Nat:
  match w:
    case T.Win{p, r}:
      p

def win.bind.pick(+hit: Bool, +b: T.Win, +w: T.Win) -> Maybe<&2, T.Win>:
  match hit:
    case True{}:
      Some{w}
    case False{}:
      Some{b}

# The binding window: highest utilization, the first wins ties.
def win.bind.step(+acc: Maybe<&2, T.Win>, +w: T.Win) -> Maybe<&2, T.Win>:
  match acc:
    case None{}:
      Some{w}
    case Some{b}:
      win.bind.pick(Nat.is_gt(win.pct(w), win.pct(b)), b, w)

def win.bind(+ws: List<&2, T.Win>, +acc: Maybe<&2, T.Win>) -> Maybe<&2, T.Win>:
  match ws:
    case Nil{}:
      acc
    case Con{w, t}:
      win.bind(t, win.bind.step(acc, w))

def bind.rec.of(+m: Maybe<&2, T.Win>, +now: Nat) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{w}:
      match w:
        case T.Win{p, r}:
          rec.after(r, now)

# When the binding window comes back; inf when unknown or already past.
def bind.rec(+ws: List<&2, T.Win>, +now: Nat) -> Maybe<&2, Nat>:
  bind.rec.of(win.bind(ws, None{}), now)

def rec.row.at(+ok: Bool, +u: T.Usage, +now: Nat, +ms: List<&2, String>) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      bind.rec(U.windows(u, ms), now)
    case False{}:
      None{}

def rec.row(+m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{u}:
      rec.row.at(U.trusted(u, now, ms), u, now, ms)

def usage.seven_reset(+u: T.Usage) -> Maybe<&2, Nat>:
  match u:
    case T.Usage{slot, five, fr, seven, sr, ss, fa, bo, er, nfl, np, pi, ad, hu, cu, se}:
      sr

def seven.row.at(+ok: Bool, +u: T.Usage, +now: Nat) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      rec.after(usage.seven_reset(u), now)
    case False{}:
      None{}

# The weekly reset consume-first ranks by; past is unknown.
def seven.row(+m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{u}:
      seven.row.at(U.trusted(u, now, ms), u, now)

# ------------------------------------------------------- the census

def is_oauth(+k: T.AcctKind) -> Bool:
  match k:
    case T.ApiKey{}:
      False{}
    case o:
      True{}

def is_api(+k: T.AcctKind) -> Bool:
  match k:
    case T.ApiKey{}:
      True{}
    case o:
      False{}

# A switchable OAuth candidate: not disabled, not the live slot.
def isc(+a: T.Account, +active: Nat) -> Bool:
  match a:
    case T.Account{slot, email, kind, disabled}:
      is_oauth(kind) && Bool.not(disabled) && Bool.not(Nat.is_eq(slot, active))

# A last-resort API-key candidate.
def isapi(+a: T.Account, +active: Nat) -> Bool:
  match a:
    case T.Account{slot, email, kind, disabled}:
      is_api(kind) && Bool.not(disabled) && Bool.not(Nat.is_eq(slot, active))

def above.thr(+h: Nat, +thr: Nat) -> Bool:
  Nat.is_ge(Nat.sub(T.full(), h), thr)

def meas.step(+m: Meas, +h: Maybe<&2, Nat>, +thr: Nat) -> Meas:
  match m:
    case Meas{any, all, best}:
      match h:
        case None{}:
          m
        case Some{x}:
          Meas{True{}, all && above.thr(x, thr), Nat.max(best, x)}

def meas.acct(+ok: Bool, +h: Maybe<&2, Nat>, +thr: Nat, +m: Meas) -> Meas:
  match ok:
    case True{}:
      meas.step(m, h, thr)
    case False{}:
      m

def meas(+as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +thr: Nat, +m: Meas) -> Meas:
  match as:
    case Nil{}:
      m
    case Con{a, t}:
      meas(t, active, us, now, ms, thr, meas.acct(isc(a, active), U.head.row(U.usage.of(U.account.slot(a), us), now, ms), thr, m))

# Is the active account and every measured candidate at or over the threshold?
def all_above(+m: Meas, +ah: Maybe<&2, Nat>, +thr: Nat) -> Bool:
  match m:
    case Meas{any, all, best}:
      match ah:
        case None{}:
          False{}
        case Some{a}:
          above.thr(a, thr) && any && all

# --------------------------------------------------------- eligibility

def barred(+bar: Maybe<&2, Nat>, +slot: Nat) -> Bool:
  match bar:
    case None{}:
      False{}
    case Some{b}:
      Nat.is_eq(b, slot)

# A candidate that may be chosen: OAuth, enabled, not live, not barred.
def target.base(+a: T.Account, +active: Nat, +bar: Maybe<&2, Nat>) -> Bool:
  match a:
    case T.Account{slot, email, kind, disabled}:
      is_oauth(kind) && Bool.not(disabled) && Bool.not(Nat.is_eq(slot, active)) && Bool.not(barred(bar, slot))

def elig.pos.at(+x: Nat) -> Maybe<&2, Nat>:
  match x:
    case 0n:
      None{}
    case 1n+p:
      Some{x}

def elig.pos(+h: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match h:
    case None{}:
      None{}
    case Some{x}:
      elig.pos.at(x)

# A usable reading for a candidate: a row with a trusted headroom above zero.
# Backoff is not a condition: it throttles polling, not trust.
def elig.row(+m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{u}:
      elig.pos(U.headroom(u, now, ms))

def sel.ok(+b: Bool, +m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Maybe<&2, Nat>:
  match b:
    case True{}:
      elig.row(m, now, ms)
    case False{}:
      None{}

# The headroom of a candidate that may be chosen, or None.
def elig(+a: T.Account, +s: Sel) -> Maybe<&2, Nat>:
  match s:
    case Sel{active, bar, need, us, now, ms}:
      sel.ok(target.base(a, active, bar), U.usage.of(U.account.slot(a), us), now, ms)

def sel.need(+s: Sel) -> Nat:
  match s:
    case Sel{active, bar, need, us, now, ms}:
      need

def cand.gate.at(+ok: Bool, +h: Nat) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      Some{h}
    case False{}:
      None{}

def cand.gate(+m: Maybe<&2, Nat>, +need: Nat) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{h}:
      cand.gate.at(Nat.is_ge(h, need), h)

# A candidate that also clears the headroom gate (landing and hysteresis).
def cand(+a: T.Account, +s: Sel) -> Maybe<&2, Nat>:
  cand.gate(elig(a, s), sel.need(s))
