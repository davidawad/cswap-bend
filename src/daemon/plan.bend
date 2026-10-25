import Base
import ../store.bend as Store
import ../policy/types.bend as T
import ../policy/usage.bend as PU
import ./gather.bend as G
import ./view.bend as V

# Which accounts a scheduled auto tick fetches (autoswitch.py
# _collect_scheduled_usage, contract 4.2 step 3). No network for a fresh row.

def sel_e(+c: Bool, +x: List<&2, G.Ent>, +y: List<&2, G.Ent>) -> List<&2, G.Ent>:
  match c:
    case True{}:
      x
    case False{}:
      y

def is_active(+e: G.Ent, +active: Maybe<&2, String>) -> Bool:
  V.is_slot(active, V.ent_slot(e))

def acct_disabled(+a: T.Account) -> Bool:
  match a:
    case T.Account{s, em, k, d}:
      d

# A candidate can be fetched: not disabled/quarantined/unswitchable.
def eligible(+e: G.Ent) -> Bool:
  match e:
    case G.Ent{s, em, o, c, a}:
      Bool.not(acct_disabled(a))

def due2(+m: Maybe<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> Bool:
  match m:
    case Some{u}:
      PU.poll_due(u, now, cfg)
    case None{}:
      False{}

def due(+e: G.Ent, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> Bool:
  due2(V.usage_for(us, V.slot_nat_of(V.ent_slot(e))), now, cfg)

def stale2(+m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match m:
    case Some{u}:
      Bool.not(PU.fresh(u, now, ms))
    case None{}:
      False{}

def stale(+e: G.Ent, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  stale2(V.usage_for(us, V.slot_nat_of(V.ent_slot(e))), now, ms)

def fa2(+m: Maybe<&2, T.Usage>) -> Nat:
  match m:
    case Some{T.Usage{s, five, fr, seven, sr, ss, fa, bo, er, fl, np, pi, ad, hu, cu, se}}:
      Maybe.default(&2, Nat, fa, 0n)
    case _:
      0n

def fetched_at(+e: G.Ent, +us: List<&2, T.Usage>) -> Nat:
  fa2(V.usage_for(us, V.slot_nat_of(V.ent_slot(e))))

# The active account, when it is due.
def active_due(+es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +active: Maybe<&2, String>, +now: Nat, +cfg: T.Config) -> List<&2, G.Ent>:
  match es:
    case Nil{}:
      []
    case Con{e, t}:
      sel_e(is_active(e, active) && eligible(e) && due(e, us, now, cfg), [e], active_due(t, us, active, now, cfg))

# Due candidates, in roster order.
def due_cands(+es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +active: Maybe<&2, String>, +now: Nat, +cfg: T.Config) -> List<&2, G.Ent>:
  match es:
    case Nil{}:
      []
    case Con{e, t}:
      sel_e(Bool.not(is_active(e, active)) && eligible(e) && due(e, us, now, cfg), e <> due_cands(t, us, active, now, cfg), due_cands(t, us, active, now, cfg))

def sel_m(+c: Bool, +x: Maybe<&2, G.Ent>, +y: Maybe<&2, G.Ent>) -> Maybe<&2, G.Ent>:
  match c:
    case True{}:
      x
    case False{}:
      y

def older(+e: G.Ent, +best: Maybe<&2, G.Ent>, +us: List<&2, T.Usage>) -> Maybe<&2, G.Ent>:
  match best:
    case None{}:
      Some{e}
    case Some{b}:
      sel_m(Nat.is_lt(fetched_at(e, us), fetched_at(b, us)), Some{e}, best)

# The due candidate with the oldest measurement (the first wins ties).
def oldest(+es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +best: Maybe<&2, G.Ent>) -> Maybe<&2, G.Ent>:
  match es:
    case Nil{}:
      best
    case Con{e, t}:
      oldest(t, us, older(e, best, us))

def one_of(+m: Maybe<&2, G.Ent>) -> List<&2, G.Ent>:
  match m:
    case Some{e}:
      [e]
    case None{}:
      []

# Phase 1: the active account if due, plus at most one due candidate.
def first_pass(+es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +active: Maybe<&2, String>, +now: Nat, +cfg: T.Config) -> List<&2, G.Ent>:
  List.append(&2, G.Ent, active_due(es, us, active, now, cfg), one_of(oldest(due_cands(es, us, active, now, cfg), us, None{})))

def same_slot(+a: G.Ent, +b: G.Ent) -> Bool:
  String.eq(V.ent_slot(a), V.ent_slot(b))

def in_list(+e: G.Ent, +xs: List<&2, G.Ent>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      same_slot(e, h) || in_list(e, t)

def exempt3(+u: T.Usage, +h: Maybe<&2, Nat>) -> Bool:
  match u h:
    case T.Usage{s, five, fr, seven, sr, ss, fa, bo, er, fl, Some{np}, pi, ad, hu, cu, se} Some{x}:
      Nat.is_eq(x, 0n) && Nat.is_gt(pi, 600n)
    case _ _:
      False{}

def exempt2(+m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match m:
    case Some{u}:
      exempt3(u, PU.headroom(u, now, ms))
    case None{}:
      False{}

# Rows planned past a long wait and exhausted are left alone.
def exempt(+e: G.Ent, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  exempt2(V.usage_for(us, V.slot_nat_of(V.ent_slot(e))), now, ms)

# Phase 2 (escalation): every other candidate that is due or stale.
def escalated(+es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +active: Maybe<&2, String>, +skip: List<&2, G.Ent>, +now: Nat, +cfg: T.Config, +ms: List<&2, String>) -> List<&2, G.Ent>:
  match es:
    case Nil{}:
      []
    case Con{e, t}:
      sel_e(Bool.not(is_active(e, active)) && eligible(e) && Bool.not(in_list(e, skip)) && (due(e, us, now, cfg) || stale(e, us, now, ms)) && Bool.not(exempt(e, us, now, ms)),
        e <> escalated(t, us, active, skip, now, cfg, ms), escalated(t, us, active, skip, now, cfg, ms))
