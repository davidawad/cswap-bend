import Base
import ./types.bend as T
import ./usage.bend as U
import ./rank.bend as R
import ./pick.bend as K
import ./exhaust.bend as E
import ./decide.bend as D

# Specification predicates: what LAWS.bend states about `decide`, written as
# Bool functions over the same inputs. They speak about eligibility (a
# trusted reading with headroom above zero) and ignore the headroom gate.

def is_switch(+d: T.Decision) -> Bool:
  match d:
    case T.NoSwitch{r, detail}:
      False{}
    case T.Switch{to, t, why, h, mode, rec, bar}:
      True{}

# The row exists and its trusted reading has a headroom. Backoff does not
# matter: it throttles polling, not trust.
def usable.row(+m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{u}:
      E.is_some(U.headroom(u, now, ms))

def trusted_acct(+a: T.Account, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  R.isc(a, active) && usable.row(U.usage.of(U.account.slot(a), us), now, ms)

def trusted_target(+as: List<&2, T.Account>, +to: Nat, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match as:
    case Nil{}:
      False{}
    case Con{a, t}:
      (Nat.is_eq(to, U.account.slot(a)) && trusted_acct(a, active, us, now, ms)) || trusted_target(t, to, active, us, now, ms)

# A last-resort API-key account, allowed only with the flag.
def api_target(+as: List<&2, T.Account>, +to: Nat, +active: Nat, +include: Bool) -> Bool:
  match as:
    case Nil{}:
      False{}
    case Con{a, t}:
      (include && Nat.is_eq(to, U.account.slot(a)) && R.isapi(a, active)) || api_target(t, to, active, include)

# `to` is an account whose eligible headroom is exactly h.
def has_headroom(+as: List<&2, T.Account>, +to: Nat, +h: Nat, +active: Nat, +bar: Maybe<&2, Nat>, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match as:
    case Nil{}:
      False{}
    case Con{a, t}:
      (Nat.is_eq(to, U.account.slot(a)) && K.first.hit(R.elig(a, R.Sel{active, bar, 0n, us, now, ms}), h)) || has_headroom(t, to, h, active, bar, us, now, ms)

def above.at(+m: Maybe<&2, Nat>, +h: Nat) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{x}:
      Nat.is_ge(h, x)

# No eligible account has strictly more headroom than h.
def none_above(+as: List<&2, T.Account>, +h: Nat, +active: Nat, +bar: Maybe<&2, Nat>, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match as:
    case Nil{}:
      True{}
    case Con{a, t}:
      above.at(R.elig(a, R.Sel{active, bar, 0n, us, now, ms}), h) && none_above(t, h, active, bar, us, now, ms)

def grp.at(+c: Maybe<&2, K.RH>, +r: Maybe<&2, Nat>) -> Bool:
  match c:
    case None{}:
      True{}
    case Some{x}:
      match x:
        case K.RH{rx, hx}:
          R.rec.rle(r, rx)

# No candidate of the family comes back sooner than r.
def grp_min(+as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam, +r: Maybe<&2, Nat>) -> Bool:
  match as:
    case Nil{}:
      True{}
    case Con{a, t}:
      grp.at(K.cdn(a, rk, f), r) && grp_min(t, rk, f, r)

def rec.hit(+c: Maybe<&2, K.RH>, +r: Maybe<&2, Nat>) -> Bool:
  match c:
    case None{}:
      False{}
    case Some{x}:
      match x:
        case K.RH{rx, hx}:
          R.rec.req(rx, r)

# `to` is a candidate of the family whose time is r.
def has_rec(+as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam, +to: Nat, +r: Maybe<&2, Nat>) -> Bool:
  match as:
    case Nil{}:
      False{}
    case Con{a, t}:
      (Nat.is_eq(to, U.account.slot(a)) && rec.hit(K.cdn(a, rk, f), r)) || has_rec(t, rk, f, to, r)

# Law 1: a switch lands on an account with a trusted reading (or, with the
# flag, on the last-resort API-key account).
def landed_trusted(+d: T.Decision, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> Bool:
  match d:
    case T.NoSwitch{r, detail}:
      True{}
    case T.Switch{to, t, why, h, mode, rec, bar}:
      match mode:
        case T.MApiLast{}:
          api_target(as, to, active, D.cfg.include(cfg))
        case o:
          trusted_target(as, to, active, us, now, D.cfg.models(cfg))

# Law 3 (headroom ranking): the target holds the most headroom of the
# eligible accounts, the barred one aside.
def landed_best(+d: T.Decision, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> Bool:
  match d:
    case T.NoSwitch{r, detail}:
      True{}
    case T.Switch{to, t, why, h, mode, rec, bar}:
      match mode:
        case T.MHead{}:
          has_headroom(as, to, h, active, bar, us, now, D.cfg.models(cfg)) && none_above(as, h, active, bar, us, now, D.cfg.models(cfg))
        case o:
          True{}

# The ranking context a recovery-mode pick was made in.
def rec_rk(+t: T.Trigger, +bar: Maybe<&2, Nat>, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> K.Rk:
  K.rk.bar(D.rk.base(t, U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)), active, as, us, now, cfg), bar)

# Law R (recovery mode): the target comes back soonest of the candidates
# that come back soon.
def landed_rec(+d: T.Decision, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> Bool:
  match d:
    case T.NoSwitch{r, detail}:
      True{}
    case T.Switch{to, t, why, h, mode, rv, bar}:
      match mode:
        case T.MRec0{}:
          grp_min(as, rec_rk(t, bar, active, as, us, now, cfg), K.FRec0{}, rv) && has_rec(as, rec_rk(t, bar, active, as, us, now, cfg), K.FRec0{}, to, rv)
        case o:
          True{}

# Law 4: a switch never lands on the live slot.
def not_active(+d: T.Decision, +active: Nat) -> Bool:
  match d:
    case T.NoSwitch{r, detail}:
      True{}
    case T.Switch{to, t, why, h, mode, rec, bar}:
      Bool.not(Nat.is_eq(to, active))

def sound(+d: T.Decision, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> Bool:
  landed_trusted(d, as, active, us, now, cfg) && landed_best(d, as, active, us, now, cfg) && landed_rec(d, as, active, us, now, cfg) && not_active(d, active)

# ----------------------------------------------------- proof scaffolding

# Every headroom-ranked candidate has at most b.
def cands_le(+as: List<&2, T.Account>, +b: Nat, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match as:
    case Nil{}:
      True{}
    case Con{a, t}:
      above.at(R.cand(a, R.Sel{active, bar, need, us, now, ms}), b) && cands_le(t, b, active, bar, need, us, now, ms)

# What `first` guarantees about the slot it answers.
def first_inv(+r: Maybe<&2, Nat>, +as: List<&2, T.Account>, +h: Nat, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match r:
    case None{}:
      True{}
    case Some{to}:
      trusted_target(as, to, active, us, now, ms) && has_headroom(as, to, h, active, bar, us, now, ms) && Nat.is_ge(h, need) && Bool.not(Nat.is_eq(to, active))

# What the headroom picker guarantees.
def pmh_inv(+p: K.Pm, +as: List<&2, T.Account>, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match p:
    case K.PmNone{}:
      True{}
    case K.PmAt{slot, r, h}:
      trusted_target(as, slot, active, us, now, ms) && has_headroom(as, slot, h, active, bar, us, now, ms) && none_above(as, h, active, bar, us, now, ms) && Bool.not(Nat.is_eq(slot, active))

# What a reset or recovery picker guarantees about the slot it answers.
def pm_ok(+p: K.Pm, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match p:
    case K.PmNone{}:
      True{}
    case K.PmAt{slot, r, h}:
      trusted_target(as, slot, active, us, now, ms) && Bool.not(Nat.is_eq(slot, active))

# The recovery picker's guarantee: nothing in the family comes back sooner,
# and the slot is a member whose time is r.
def pmg(+p: K.Pm, +as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam) -> Bool:
  match p:
    case K.PmNone{}:
      True{}
    case K.PmAt{slot, r, h}:
      grp_min(as, rk, f, r) && has_rec(as, rk, f, slot, r)

# The best time so far is at or below another.
def mn_le(+a: K.Mn, +b: K.Mn) -> Bool:
  match a b:
    case K.MnNone{} K.MnNone{}:
      True{}
    case K.MnNone{} K.MnAt{y}:
      False{}
    case K.MnAt{x} K.MnNone{}:
      True{}
    case K.MnAt{x} K.MnAt{y}:
      R.rec.rle(x, y)

# The scan's answer bounds every candidate of the family.
def mn_cov(+res: K.Mn, +as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam) -> Bool:
  match res:
    case K.MnNone{}:
      True{}
    case K.MnAt{r}:
      grp_min(as, rk, f, r)

# What `firstrh` guarantees about the slot it answers.
def fr_inv(+m: Maybe<&2, Nat>, +as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam, +r0: Maybe<&2, Nat>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{to}:
      trusted_target(as, to, active, us, now, ms) && Bool.not(Nat.is_eq(to, active)) && has_rec(as, rk, f, to, r0)

def some_rh(+c: Maybe<&2, K.RH>) -> Bool:
  match c:
    case None{}:
      False{}
    case Some{x}:
      True{}

# The tick reaches the failover trigger: the active token is expired, the idle
# hold has run out, and the unhealthy ticks have reached the limit.
def failover_ready(+active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +mem: T.Mem) -> Bool:
  D.row.expired(U.usage.of(active, us)) && Bool.not(D.idle.held(mem, now)) && Bool.not(Nat.is_lt(Nat.add(D.mem.unhealthy(mem), 1n), D.mem.ut(cfg)))
