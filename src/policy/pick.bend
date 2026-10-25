import Base
import ./types.bend as T
import ./usage.bend as U
import ./rank.bend as R

# The pickers: one ranking family per tick (headroom, weekly reset, or
# recovery), each choosing the first account with the best key.

# The family a candidate is judged in: weekly reset (consume-first), the
# recovery tiers (back soon, back late, one-way fallback).
type Fam is Data:
  FReset{}
  FRec0{}
  FRec1{}
  FFall{}

# A candidate's ranking time (reset or recovery; None is inf) and headroom.
type RH is Data:
  RH{r: Maybe<&2, Nat>, h: Nat}

# A pick before it is tagged with its ranking mode: nothing, or a slot with
# the key it won on.
type Pm is Data:
  PmNone{}
  PmAt{slot: Nat, r: Maybe<&2, Nat>, h: Nat}

# The tagged pick.
type Pk is Data:
  PkNone{}
  PkAt{slot: Nat, r: Maybe<&2, Nat>, h: Nat, mode: T.Mode}

# Everything the pickers read: the trigger, whether the strategy is
# consume-first, whether this is recovery mode, the active headroom (0 when
# unknown), the best candidate headroom, the active account's binding recovery
# and weekly reset, the threshold, and the selection context.
type Rk is Data:
  Rk{t: T.Trigger, cf: Bool, rm: Bool, ah0: Nat, best: Nat, ar: Maybe<&2, Nat>, ars: Maybe<&2, Nat>, thr: Nat, s: R.Sel}

# The best ranking time so far among the family's candidates.
type Mn is Data:
  MnNone{}
  MnAt{r: Maybe<&2, Nat>}

# The least headroom a target needs: at-limit and failover take any
# headroom; proactive must land below the threshold and beat the active
# account by the hysteresis margin.
def need.of(+t: T.Trigger, +ah: Nat, +hy: Nat, +thr: Nat) -> Nat:
  match t:
    case T.Proactive{}:
      Nat.max(Nat.add(ah, hy), Nat.add(Nat.sub(T.full(), thr), 1n))
    case o:
      1n

def trig.pc(+t: T.Trigger) -> Bool:
  match t:
    case T.Proactive{}:
      True{}
    case T.ConsumeFirstT{}:
      True{}
    case o:
      False{}

def strat.cf(+st: T.Strategy) -> Bool:
  match st:
    case T.ConsumeFirst{}:
      True{}
    case T.Best{}:
      False{}

def ah.or0(+ah: Maybe<&2, Nat>) -> Nat:
  match ah:
    case None{}:
      0n
    case Some{x}:
      x

def rk.mk(+t: T.Trigger, +ah: Maybe<&2, Nat>, +ab: Bool, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +hy: Nat, +cf: Bool, +active: Nat, +bar: Maybe<&2, Nat>, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Rk:
  Rk{t, cf, ab && trig.pc(t), ah.or0(ah), best, ar, ars, thr, R.Sel{active, bar, need.of(t, ah.or0(ah), hy, thr), us, now, ms}}

def rk.bar(+rk: Rk, +bar: Maybe<&2, Nat>) -> Rk:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      match s:
        case R.Sel{active, b0, need, us, now, ms}:
          Rk{t, cf, rm, ah0, best, ar, ars, thr, R.Sel{active, bar, need, us, now, ms}}

# ---------------------------------------------------- family candidates

def land.gate(+t: T.Trigger, +h: Nat, +thr: Nat) -> Bool:
  match t:
    case T.AtLimit{}:
      True{}
    case T.Failover{}:
      True{}
    case o:
      Nat.is_ge(h, Nat.add(Nat.sub(T.full(), thr), 1n))

def reset.sooner(+rc: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>) -> Bool:
  match rc ars:
    case Some{a} Some{b}:
      Nat.is_lt(a, b)
    case o _:
      False{}

def reset.gate(+t: T.Trigger, +rc: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>) -> Bool:
  match t:
    case T.ConsumeFirstT{}:
      reset.sooner(rc, ars)
    case o:
      True{}

def rh.if(+ok: Bool, +rc: Maybe<&2, Nat>, +h: Nat) -> Maybe<&2, RH>:
  match ok:
    case True{}:
      Some{RH{rc, h}}
    case False{}:
      None{}

# Is this candidate ranked by recovery rather than by headroom?
def by_recovery(+rc: Maybe<&2, Nat>, +ar: Maybe<&2, Nat>, +ah0: Nat, +best: Nat, +now: Nat) -> Bool:
  (Nat.is_le(ah0, 300n) && Nat.is_le(best, 300n)) || R.rec.within(rc, now) || R.rec.within(ar, now)

def cdn.rec0(+h: Nat, +rc: Maybe<&2, Nat>, +rk: Rk) -> Maybe<&2, RH>:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      match s:
        case R.Sel{active, bar, need, us, now, ms}:
          rh.if(by_recovery(rc, ar, ah0, best, now) && R.rec.lt_minus(rc, ar), rc, h)

def cdn.rec1(+h: Nat, +rc: Maybe<&2, Nat>, +rk: Rk) -> Maybe<&2, RH>:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      match s:
        case R.Sel{active, bar, need, us, now, ms}:
          rh.if(Bool.not(by_recovery(rc, ar, ah0, best, now)) && Nat.is_ge(h, Nat.mul(2n, ah0)), rc, h)

def cdn.fall(+h: Nat, +rc: Maybe<&2, Nat>, +rk: Rk) -> Maybe<&2, RH>:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      match s:
        case R.Sel{active, bar, need, us, now, ms}:
          rh.if(Bool.not(by_recovery(rc, ar, ah0, best, now)) && Nat.is_lt(h, Nat.mul(2n, ah0)) && Nat.is_le(ah0, 300n) && Nat.is_ge(h, ah0) && R.rec.lt_minus(rc, ar), rc, h)

def cdn.reset(+h: Nat, +rc: Maybe<&2, Nat>, +rk: Rk) -> Maybe<&2, RH>:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      rh.if(land.gate(t, h, thr) && reset.gate(t, rc, ars), rc, h)

def cdn.fam(+rk: Rk, +f: Fam, +h: Nat, +a: T.Account) -> Maybe<&2, RH>:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      match s:
        case R.Sel{active, bar, need, us, now, ms}:
          match f:
            case FReset{}:
              cdn.reset(h, R.seven.row(U.usage.of(U.account.slot(a), us), now, ms), rk)
            case FRec0{}:
              cdn.rec0(h, R.rec.row(U.usage.of(U.account.slot(a), us), now, ms), rk)
            case FRec1{}:
              cdn.rec1(h, R.rec.row(U.usage.of(U.account.slot(a), us), now, ms), rk)
            case FFall{}:
              cdn.fall(h, R.rec.row(U.usage.of(U.account.slot(a), us), now, ms), rk)

def cdn.at(+m: Maybe<&2, Nat>, +f: Fam, +a: T.Account, +rk: Rk) -> Maybe<&2, RH>:
  match m:
    case None{}:
      None{}
    case Some{h}:
      cdn.fam(rk, f, h, a)

def rk.sel(+rk: Rk) -> R.Sel:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      s

# A candidate of family f, with its ranking time and headroom.
def cdn(+a: T.Account, +rk: Rk, +f: Fam) -> Maybe<&2, RH>:
  cdn.at(R.elig(a, rk.sel(rk)), f, a, rk)

# ------------------------------------------------- headroom family pickers

def top.step(+c: Maybe<&2, Nat>, +acc: Nat) -> Nat:
  match c:
    case None{}:
      acc
    case Some{h}:
      Nat.max(acc, h)

# The most headroom any candidate offers (0 when there is none).
def top(+as: List<&2, T.Account>, +s: R.Sel, +acc: Nat) -> Nat:
  match as:
    case Nil{}:
      acc
    case Con{a, t}:
      top(t, s, top.step(R.cand(a, s), acc))

def first.hit(+c: Maybe<&2, Nat>, +h: Nat) -> Bool:
  match c:
    case None{}:
      False{}
    case Some{x}:
      Nat.is_eq(x, h)

def first.pick(+hit: Bool, +slot: Nat, +rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{slot}
    case False{}:
      rest

# The first account (sequence order breaks ties) whose candidate headroom is h.
def first(+as: List<&2, T.Account>, +s: R.Sel, +h: Nat) -> Maybe<&2, Nat>:
  match as:
    case Nil{}:
      None{}
    case Con{a, t}:
      first.pick(first.hit(R.cand(a, s), h), U.account.slot(a), first(t, s, h))

def pk.slot(+m: Maybe<&2, Nat>, +r: Maybe<&2, Nat>, +h: Nat) -> Pm:
  match m:
    case None{}:
      PmNone{}
    case Some{slot}:
      PmAt{slot, r, h}

def pick.head.at(+h0: Nat, +as: List<&2, T.Account>, +s: R.Sel) -> Pm:
  match h0:
    case 0n:
      PmNone{}
    case 1n+p:
      pk.slot(first(as, s, h0), None{}, h0)

def pick.head(+as: List<&2, T.Account>, +s: R.Sel) -> Pm:
  pick.head.at(top(as, s, 0n), as, s)

# --------------------------------------------- reset / recovery pickers

def mn.min(+m: Mn, +r: Maybe<&2, Nat>) -> Mn:
  match m:
    case MnNone{}:
      MnAt{r}
    case MnAt{x}:
      MnAt{R.rec.min(x, r)}

def minr.step(+c: Maybe<&2, RH>, +m: Mn) -> Mn:
  match c:
    case None{}:
      m
    case Some{x}:
      match x:
        case RH{r, h}:
          mn.min(m, r)

# The earliest ranking time among the family's candidates.
def minr(+as: List<&2, T.Account>, +rk: Rk, +f: Fam, +m: Mn) -> Mn:
  match as:
    case Nil{}:
      m
    case Con{a, t}:
      minr(t, rk, f, minr.step(cdn(a, rk, f), m))

def maxh.pick(+hit: Bool, +h: Nat, +acc: Nat) -> Nat:
  match hit:
    case True{}:
      Nat.max(acc, h)
    case False{}:
      acc

def maxh.step(+c: Maybe<&2, RH>, +r0: Maybe<&2, Nat>, +acc: Nat) -> Nat:
  match c:
    case None{}:
      acc
    case Some{x}:
      match x:
        case RH{r, h}:
          maxh.pick(R.rec.req(r, r0), h, acc)

# The most headroom among the family's candidates whose time is r0.
def maxh(+as: List<&2, T.Account>, +rk: Rk, +f: Fam, +r0: Maybe<&2, Nat>, +acc: Nat) -> Nat:
  match as:
    case Nil{}:
      acc
    case Con{a, t}:
      maxh(t, rk, f, r0, maxh.step(cdn(a, rk, f), r0, acc))

def maxall.step(+c: Maybe<&2, RH>, +acc: Nat) -> Nat:
  match c:
    case None{}:
      acc
    case Some{x}:
      match x:
        case RH{r, h}:
          Nat.max(acc, h)

# The most headroom among the family's candidates.
def maxall(+as: List<&2, T.Account>, +rk: Rk, +f: Fam, +acc: Nat) -> Nat:
  match as:
    case Nil{}:
      acc
    case Con{a, t}:
      maxall(t, rk, f, maxall.step(cdn(a, rk, f), acc))

def minat.pick(+hit: Bool, +r: Maybe<&2, Nat>, +m: Mn) -> Mn:
  match hit:
    case True{}:
      mn.min(m, r)
    case False{}:
      m

def minat.step(+c: Maybe<&2, RH>, +h0: Nat, +m: Mn) -> Mn:
  match c:
    case None{}:
      m
    case Some{x}:
      match x:
        case RH{r, h}:
          minat.pick(Nat.is_eq(h, h0), r, m)

# The earliest time among the family's candidates with headroom h0.
def minat(+as: List<&2, T.Account>, +rk: Rk, +f: Fam, +h0: Nat, +m: Mn) -> Mn:
  match as:
    case Nil{}:
      m
    case Con{a, t}:
      minat(t, rk, f, h0, minat.step(cdn(a, rk, f), h0, m))

def firstrh.hit(+c: Maybe<&2, RH>, +r0: Maybe<&2, Nat>, +h0: Nat) -> Bool:
  match c:
    case None{}:
      False{}
    case Some{x}:
      match x:
        case RH{r, h}:
          R.rec.req(r, r0) && Nat.is_eq(h, h0)

# The first account whose key is exactly (r0, h0).
def firstrh(+as: List<&2, T.Account>, +rk: Rk, +f: Fam, +r0: Maybe<&2, Nat>, +h0: Nat) -> Maybe<&2, Nat>:
  match as:
    case Nil{}:
      None{}
    case Con{a, t}:
      first.pick(firstrh.hit(cdn(a, rk, f), r0, h0), U.account.slot(a), firstrh(t, rk, f, r0, h0))

def pick.rh.go(+h0: Nat, +r0: Maybe<&2, Nat>, +as: List<&2, T.Account>, +rk: Rk, +f: Fam) -> Pm:
  pk.slot(firstrh(as, rk, f, r0, h0), r0, h0)

def pick.rh.at(+m: Mn, +as: List<&2, T.Account>, +rk: Rk, +f: Fam) -> Pm:
  match m:
    case MnNone{}:
      PmNone{}
    case MnAt{r0}:
      pick.rh.go(maxh(as, rk, f, r0, 0n), r0, as, rk, f)

# Earliest time first, then most headroom, then sequence order.
def pick.rh(+as: List<&2, T.Account>, +rk: Rk, +f: Fam) -> Pm:
  pick.rh.at(minr(as, rk, f, MnNone{}), as, rk, f)

def pick.hr.go(+m: Mn, +h0: Nat, +as: List<&2, T.Account>, +rk: Rk, +f: Fam) -> Pm:
  match m:
    case MnNone{}:
      PmNone{}
    case MnAt{r0}:
      pk.slot(firstrh(as, rk, f, r0, h0), r0, h0)

def pick.hr.at(+h0: Nat, +as: List<&2, T.Account>, +rk: Rk, +f: Fam) -> Pm:
  match h0:
    case 0n:
      PmNone{}
    case 1n+p:
      pick.hr.go(minat(as, rk, f, h0, MnNone{}), h0, as, rk, f)

# Most headroom first, then earliest time, then sequence order.
def pick.hr(+as: List<&2, T.Account>, +rk: Rk, +f: Fam) -> Pm:
  pick.hr.at(maxall(as, rk, f, 0n), as, rk, f)

def pk.of(+mode: T.Mode, +p: Pm) -> Pk:
  match p:
    case PmNone{}:
      PkNone{}
    case PmAt{slot, r, h}:
      PkAt{slot, r, h, mode}

def pick.rec.late(+p1: Pm, +as: List<&2, T.Account>, +rk: Rk) -> Pk:
  match p1:
    case PmNone{}:
      pk.of(T.MFallback{}, pick.rh(as, rk, FFall{}))
    case PmAt{slot, r, h}:
      pk.of(T.MRec1{}, p1)

def pick.rec.mid(+p0: Pm, +as: List<&2, T.Account>, +rk: Rk) -> Pk:
  match p0:
    case PmNone{}:
      pick.rec.late(pick.hr(as, rk, FRec1{}), as, rk)
    case PmAt{slot, r, h}:
      pk.of(T.MRec0{}, p0)

# Recovery mode: back-soon candidates by soonest recovery, else back-late
# ones by headroom, else the one-way fallback.
def pick.rec(+as: List<&2, T.Account>, +rk: Rk) -> Pk:
  pick.rec.mid(pick.rh(as, rk, FRec0{}), as, rk)

def rk.cf(+rk: Rk) -> Bool:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      cf

def rk.rm(+rk: Rk) -> Bool:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      rm

def pick.cf(+cf: Bool, +as: List<&2, T.Account>, +rk: Rk) -> Pk:
  match cf:
    case True{}:
      pk.of(T.MReset{}, pick.rh(as, rk, FReset{}))
    case False{}:
      pk.of(T.MHead{}, pick.head(as, rk.sel(rk)))

def pick.fam(+rm: Bool, +as: List<&2, T.Account>, +rk: Rk) -> Pk:
  match rm:
    case True{}:
      pick.rec(as, rk)
    case False{}:
      pick.cf(rk.cf(rk), as, rk)

# The oauth pick for one ranking context.
def pick(+as: List<&2, T.Account>, +rk: Rk) -> Pk:
  pick.fam(rk.rm(rk), as, rk)

def rk.active(+rk: Rk) -> Nat:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      match s:
        case R.Sel{active, bar, need, us, now, ms}:
          active

def rk.us(+rk: Rk) -> List<&2, T.Usage>:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      match s:
        case R.Sel{active, bar, need, us, now, ms}:
          us

def rk.now(+rk: Rk) -> Nat:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      match s:
        case R.Sel{active, bar, need, us, now, ms}:
          now

def rk.ms(+rk: Rk) -> List<&2, String>:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      match s:
        case R.Sel{active, bar, need, us, now, ms}:
          ms

def rk.bar_of(+rk: Rk) -> Maybe<&2, Nat>:
  match rk:
    case Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      match s:
        case R.Sel{active, bar, need, us, now, ms}:
          bar
