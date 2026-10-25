import Base
import ./types.bend as T
import ./usage.bend as U
import ./rank.bend as R
import ./safe.bend as SF
import ./algo.bend as A
import ./spec.bend as S

# Specification predicates for the behaviour-profile strategies, as
# src/policy/spec.bend is for `best`: what LAWS.bend states about
# `A.decide` / `A.rotate`, written as Bool functions over the same inputs.

# `to` is the slot of an account that is safe to switch to: OAuth, enabled,
# not the live slot, a trusted headroom above zero, not in backoff.
def ok_target(+as: List<&2, T.Account>, +to: Nat, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match as:
    case Nil{}:
      False{}
    case Con{a, t}:
      (Nat.is_eq(to, U.account.slot(a)) && SF.safe(a, active, us, now, ms)) || ok_target(t, to, active, us, now, ms)

# A switch lands on a safe account.
def landed_ok(+d: T.Decision, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match d:
    case T.NoSwitch{r, detail}:
      True{}
    case T.Switch{to, t, why, h, mode, rec, bar}:
      ok_target(as, to, active, us, now, ms)

# A switch lands on a safe account, and not on the live slot.
def good(+d: T.Decision, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  landed_ok(d, as, active, us, now, ms) && S.not_active(d, active)

# What the picker guarantees about the candidate it answers: a safe account,
# not the live slot.
def pick_ok(+m: Maybe<&2, SF.Cd>, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{c}:
      match c:
        case SF.Cd{slot, k1, k2, h}:
          ok_target(as, slot, active, us, now, ms) && Bool.not(Nat.is_eq(slot, active))

# What a candidate built for `a` guarantees: it names `a`, and `a` is safe and
# not the live slot.
def cand_ok(+m: Maybe<&2, SF.Cd>, +slot_a: Nat, +sf: Bool, +active: Nat) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{c}:
      match c:
        case SF.Cd{slot, k1, k2, h}:
          Nat.is_eq(slot, slot_a) && sf && Bool.not(Nat.is_eq(slot, active))
