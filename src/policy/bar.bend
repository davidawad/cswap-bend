import Base
import ./types.bend as T
import ./usage.bend as U
import ./rank.bend as R

# The no-return bar: after a proactive switch away from account A, A is not
# a target until it has recovered. `recovered` asks whether A is a better
# proposition than when the engine left it; `no_return` names the barred
# slot while the bar stands.

def is_none(+m: Maybe<&2, Nat>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{x}:
      False{}

def trig.is_failover(+t: T.Trigger) -> Bool:
  match t:
    case T.Failover{}:
      True{}
    case o:
      False{}

# A failover departure: by the recorded trigger, else by the two nulls.
def snap.fail(+lt: Maybe<&2, T.Trigger>, +lh: Maybe<&2, Nat>, +lr: Maybe<&2, Nat>) -> Bool:
  match lt:
    case Some{t}:
      trig.is_failover(t)
    case None{}:
      is_none(lh) && is_none(lr)

# h > 100 - threshold: would the ranking accept it as a landing spot?
def gt_land(+h: Maybe<&2, Nat>, +thr: Nat) -> Bool:
  match h:
    case None{}:
      False{}
    case Some{x}:
      Nat.is_gt(x, Nat.sub(T.full(), thr))

def rec.finite(+a: Maybe<&2, Nat>) -> Bool:
  match a:
    case None{}:
      False{}
    case Some{x}:
      True{}

# Failover departure: no baseline, so read only the present. Landing spot, or
# its binding reset is meaningfully sooner than the active one's.
def recov.fail(+h: Maybe<&2, Nat>, +peer: Maybe<&2, Nat>, +act: Maybe<&2, Nat>, +thr: Nat, +now: Nat) -> Bool:
  gt_land(h, thr) || ((rec.finite(act) || R.rec.within(peer, now)) && R.rec.lt_minus(peer, act))

# Dominance over the active account.
def recov.dom(+h: Maybe<&2, Nat>, +ah: Maybe<&2, Nat>, +thr: Nat) -> Bool:
  match h ah:
    case None{} _:
      False{}
    case Some{x} Some{a}:
      Nat.is_gt(x, Nat.add(Nat.mul(2n, a), 300n))
    case Some{x} None{}:
      Nat.is_gt(x, Nat.sub(T.full(), thr))

# Headroom risen three points past the departure baseline.
def recov.self(+h: Maybe<&2, Nat>, +lh: Maybe<&2, Nat>) -> Bool:
  match h lh:
    case Some{x} Some{l}:
      Nat.is_ge(x, Nat.min(Nat.add(l, 300n), T.full()))
    case o _:
      False{}

# Ordinary departure: dominance, headroom rise, or a sooner binding reset.
def recov.ord(+h: Maybe<&2, Nat>, +ah: Maybe<&2, Nat>, +lh: Maybe<&2, Nat>, +lr: Maybe<&2, Nat>, +peer: Maybe<&2, Nat>, +thr: Nat) -> Bool:
  recov.dom(h, ah, thr) || recov.self(h, lh) || R.rec.lt_minus(peer, lr)

def recov.pick(+isf: Bool, +h: Maybe<&2, Nat>, +ah: Maybe<&2, Nat>, +lh: Maybe<&2, Nat>, +lr: Maybe<&2, Nat>, +peer: Maybe<&2, Nat>, +act: Maybe<&2, Nat>, +thr: Nat, +now: Nat) -> Bool:
  match isf:
    case True{}:
      recov.fail(h, peer, act, thr, now)
    case False{}:
      recov.ord(h, ah, lh, lr, peer, thr)

def recov.snap(+sn: T.Snap, +f: Nat, +current: Nat, +us: List<&2, T.Usage>, +ah: Maybe<&2, Nat>, +thr: Nat, +now: Nat, +ms: List<&2, String>) -> Bool:
  match sn:
    case T.NoSnap{}:
      True{}
    case T.Snap{lh, lr, ltr}:
      recov.pick(snap.fail(ltr, lh, lr), U.head.row(U.usage.of(f, us), now, ms), ah, lh, lr, R.rec.row(U.usage.of(f, us), now, ms), R.rec.row(U.usage.of(current, us), now, ms), thr, now)

# Is the account the engine left a better proposition than when it left it?
# No record of the departure means release.
def recovered(+st: T.State, +current: Nat, +us: List<&2, T.Usage>, +ah: Maybe<&2, Nat>, +thr: Nat, +now: Nat, +ms: List<&2, String>) -> Bool:
  match st:
    case T.State{la, lt, lf, sn}:
      match lf:
        case None{}:
          True{}
        case Some{f}:
          recov.snap(sn, f, current, us, ah, thr, now, ms)

# The bar lifts when the account we left beats us outright.
def nr.release(+hb: Maybe<&2, Nat>, +ah: Maybe<&2, Nat>, +thr: Nat) -> Bool:
  match hb ah:
    case None{} _:
      False{}
    case Some{l} Some{a}:
      Nat.is_ge(l, Nat.mul(2n, a))
    case Some{l} None{}:
      Nat.is_gt(l, Nat.sub(T.full(), thr))

def nr.rel(+rel: Bool, +f: Nat) -> Maybe<&2, Nat>:
  match rel:
    case True{}:
      None{}
    case False{}:
      Some{f}

def nr.rec(+rec: Bool, +f: Nat, +hb: Maybe<&2, Nat>, +ah: Maybe<&2, Nat>, +thr: Nat) -> Maybe<&2, Nat>:
  match rec:
    case False{}:
      Some{f}
    case True{}:
      nr.rel(nr.release(hb, ah, thr), f)

# Only while the engine still stands where its switch put it.
def landed_away(+lt: Maybe<&2, Nat>, +current: Nat) -> Bool:
  match lt:
    case None{}:
      False{}
    case Some{x}:
      Bool.not(Nat.is_eq(x, current))

def nr.landed(+away: Bool, +f: Nat, +rec: Bool, +hb: Maybe<&2, Nat>, +ah: Maybe<&2, Nat>, +thr: Nat) -> Maybe<&2, Nat>:
  match away:
    case True{}:
      None{}
    case False{}:
      nr.rec(rec, f, hb, ah, thr)

def nr.state(+st: T.State, +current: Nat, +rec: Bool, +us: List<&2, T.Usage>, +ah: Maybe<&2, Nat>, +thr: Nat, +now: Nat, +ms: List<&2, String>) -> Maybe<&2, Nat>:
  match st:
    case T.State{la, lt, lf, sn}:
      match lf:
        case None{}:
          None{}
        case Some{f}:
          nr.landed(landed_away(lt, current), f, rec, U.head.row(U.usage.of(f, us), now, ms), ah, thr)

# The account this engine most recently left, while it is still barred.
# Proactive and consume-first triggers only: at-limit and failover escape.
def no_return(+t: T.Trigger, +st: T.State, +current: Nat, +rec: Bool, +us: List<&2, T.Usage>, +ah: Maybe<&2, Nat>, +thr: Nat, +now: Nat, +ms: List<&2, String>) -> Maybe<&2, Nat>:
  match t:
    case T.Proactive{}:
      nr.state(st, current, rec, us, ah, thr, now, ms)
    case T.ConsumeFirstT{}:
      nr.state(st, current, rec, us, ah, thr, now, ms)
    case o:
      None{}
