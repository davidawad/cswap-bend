import Base
import ./types.bend as T
import ./usage.bend as U
import ./rank.bend as R
import ./pick.bend as K

# Why nothing qualified: which accounts are readable, which are exhausted,
# and the earliest moment a blocked account is usable again.

# How an account is blocked: not at all, at 100 % with no known reset, or
# until the latest reset among its windows at 100 %.
type Br is Data:
  NotBlocked{}
  BlockedNoTs{}
  BlockedAt{t: Nat}

type Er is Data:
  ErNone{}
  ErAt{t: Nat}
  ErPoison{}

def readable.at(+ok: Bool, +m: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      m
    case False{}:
      None{}

# The trusted headroom of a candidate, backoff or not.
def readable.acct(+a: T.Account, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Maybe<&2, Nat>:
  readable.at(R.isc(a, active), U.head.row(U.usage.of(U.account.slot(a), us), now, ms))

def is_some(+m: Maybe<&2, Nat>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      True{}

# Some candidate has a trusted reading.
def any_known(+as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match as:
    case Nil{}:
      False{}
    case Con{a, t}:
      is_some(readable.acct(a, active, us, now, ms)) || any_known(t, active, us, now, ms)

def exhausted.known(+m: Maybe<&2, Nat>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{h}:
      Nat.is_eq(h, 0n)

def exhausted.at(+base: Bool, +m: Maybe<&2, Nat>) -> Bool:
  match base:
    case False{}:
      True{}
    case True{}:
      exhausted.known(m)

# Every OAuth candidate is readable and at its limit.
def all_exhausted(+as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match as:
    case Nil{}:
      True{}
    case Con{a, t}:
      exhausted.at(R.isc(a, active), readable.acct(a, active, us, now, ms)) && all_exhausted(t, active, us, now, ms)

def any_cand(+as: List<&2, T.Account>, +active: Nat) -> Bool:
  match as:
    case Nil{}:
      False{}
    case Con{a, t}:
      R.isc(a, active) || any_cand(t, active)

def any_api(+as: List<&2, T.Account>, +active: Nat) -> Bool:
  match as:
    case Nil{}:
      False{}
    case Con{a, t}:
      R.isapi(a, active) || any_api(t, active)

# The first last-resort API-key candidate, in sequence order.
def api.first(+as: List<&2, T.Account>, +active: Nat) -> Maybe<&2, Nat>:
  match as:
    case Nil{}:
      None{}
    case Con{a, t}:
      K.first.pick(R.isapi(a, active), U.account.slot(a), api.first(t, active))

# -------------------------------------------------- earliest recovery

def br.upd(+acc: Br, +r: Maybe<&2, Nat>) -> Br:
  match acc r:
    case NotBlocked{} None{}:
      BlockedNoTs{}
    case BlockedNoTs{} None{}:
      BlockedNoTs{}
    case BlockedAt{x} None{}:
      BlockedAt{x}
    case NotBlocked{} Some{t}:
      BlockedAt{t}
    case BlockedNoTs{} Some{t}:
      BlockedAt{t}
    case BlockedAt{x} Some{t}:
      BlockedAt{Nat.max(x, t)}

def br.if(+blocked: Bool, +acc: Br, +r: Maybe<&2, Nat>) -> Br:
  match blocked:
    case True{}:
      br.upd(acc, r)
    case False{}:
      acc

def br.win(+ws: List<&2, T.Win>, +acc: Br) -> Br:
  match ws:
    case Nil{}:
      acc
    case Con{w, t}:
      match w:
        case T.Win{p, r}:
          br.win(t, br.if(Nat.is_ge(p, T.full()), acc, r))

def br.fresh(+ok: Bool, +u: T.Usage, +ms: List<&2, String>) -> Br:
  match ok:
    case True{}:
      br.win(U.windows(u, ms), NotBlocked{})
    case False{}:
      NotBlocked{}

def br.row(+m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Br:
  match m:
    case None{}:
      NotBlocked{}
    case Some{u}:
      br.fresh(U.trusted(u, now, ms), u, ms)

def er.min(+e: Er, +t: Nat) -> Er:
  match e:
    case ErNone{}:
      ErAt{t}
    case ErAt{x}:
      ErAt{Nat.min(x, t)}
    case ErPoison{}:
      ErPoison{}

def er.at(+past: Bool, +e: Er, +t: Nat) -> Er:
  match past:
    case True{}:
      ErPoison{}
    case False{}:
      er.min(e, t)

def er.step(+e: Er, +b: Br, +now: Nat) -> Er:
  match b:
    case NotBlocked{}:
      e
    case BlockedNoTs{}:
      ErPoison{}
    case BlockedAt{t}:
      er.at(Nat.is_le(t, now), e, t)

def er.out(+e: Er) -> Maybe<&2, Nat>:
  match e:
    case ErAt{t}:
      Some{t}
    case o:
      None{}

# Earliest moment any blocked account (the live one included) is usable
# again; None when it cannot be proven.
def earliest(+as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +e: Er) -> Er:
  match as:
    case Nil{}:
      e
    case Con{a, t}:
      earliest(t, us, now, ms, er.step(e, br.row(U.usage.of(U.account.slot(a), us), now, ms), now))
