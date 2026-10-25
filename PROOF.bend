import Base
import ./LAWS.bend as Laws
import ./src/policy/types.bend as T
import ./src/policy/usage.bend as U
import ./src/policy/rank.bend as R
import ./src/policy/pick.bend as K
import ./src/policy/bar.bend as B
import ./src/policy/exhaust.bend as E
import ./src/policy/decide.bend as D
import ./src/policy/spec.bend as S
import ./src/policy/safe.bend as SF
import ./src/policy/algo.bend as A
import ./src/policy/specalg.bend as SA

def Laws.header_none_on_empty(name):
  {==}

def Laws.header_found_sticks(name, ls, v):
  match ls:
    case Nil{}:
      {==}
    case Con{h, t}:
      {==}

# ==== proofs for the decision core

# ---- Bool plumbing
def ft_disc(+b: Bool) -> Type:
  match b:
    case True{}:
      Empty
    case False{}:
      Unit

def ft_empty(+e: {False{} == True{} : Bool}) -> Empty:
  %e : ft_disc(_)
  Unit{}

def ft_absurd(-A: Type, +e: {False{} == True{} : Bool}) -> A:
  Empty.absurd(A, ft_empty(e))

def and_intro(+x: Bool, +y: Bool, +px: {x == True{} : Bool}, +py: {y == True{} : Bool}) -> {Bool.and(x, y) == True{} : Bool}:
  %Equal.sym(Bool, x, True{}, px) : {Bool.and(_, y) == True{} : Bool}
  py

def and_l(+x: Bool, +y: Bool, +p: {Bool.and(x, y) == True{} : Bool}) -> {x == True{} : Bool}:
  match x:
    case True{}:
      {==}
    case False{}:
      ft_absurd({False{} == True{} : Bool}, p)

def and_r(+x: Bool, +y: Bool, +p: {Bool.and(x, y) == True{} : Bool}) -> {y == True{} : Bool}:
  match x:
    case True{}:
      p
    case False{}:
      ft_absurd({y == True{} : Bool}, p)

def or_intro_l(+x: Bool, +y: Bool, +px: {x == True{} : Bool}) -> {Bool.or(x, y) == True{} : Bool}:
  %Equal.sym(Bool, x, True{}, px) : {Bool.or(_, y) == True{} : Bool}
  {==}

def or_intro_r(+x: Bool, +y: Bool, +py: {y == True{} : Bool}) -> {Bool.or(x, y) == True{} : Bool}:
  match x:
    case True{}:
      {==}
    case False{}:
      py

def tf_disc(+b: Bool) -> Type:
  match b:
    case True{}:
      Unit
    case False{}:
      Empty

def tf_empty(+e: {True{} == False{} : Bool}) -> Empty:
  %e : tf_disc(_)
  Unit{}

def tf_absurd(-A: Type, +e: {True{} == False{} : Bool}) -> A:
  Empty.absurd(A, tf_empty(e))

# ---- Nat order
def ge_trans(+a: Nat, +b: Nat, +c: Nat, +p: {Nat.is_ge(a, b) == True{} : Bool}, +q: {Nat.is_ge(b, c) == True{} : Bool}) -> {Nat.is_ge(a, c) == True{} : Bool}:
  match a b c:
    case 0n _ 0n:
      {==}
    case 1n+ap _ 0n:
      {==}
    case 0n 0n 1n+cp:
      ft_absurd({Nat.is_ge(0n, 1n+cp) == True{} : Bool}, q)
    case 0n 1n+bp 1n+cp:
      ft_absurd({Nat.is_ge(0n, 1n+cp) == True{} : Bool}, p)
    case 1n+ap 0n 1n+cp:
      ft_absurd({Nat.is_ge(1n+ap, 1n+cp) == True{} : Bool}, q)
    case 1n+ap 1n+bp 1n+cp:
      ge_trans(ap, bp, cp, p, q)

def eq_refl(+n: Nat) -> {Nat.is_eq(n, n) == True{} : Bool}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      eq_refl(p)

def neg_ge(+x: Nat, +n: Nat, +b: Nat, +e: {Nat.is_ge(x, n) == False{} : Bool}, +h: {Nat.is_ge(b, n) == True{} : Bool}) -> {Nat.is_ge(b, x) == True{} : Bool}:
  match x n b:
    case 0n _ 0n:
      {==}
    case 0n _ 1n+bp:
      {==}
    case 1n+xp 0n _:
      tf_absurd({Nat.is_ge(b, 1n+xp) == True{} : Bool}, e)
    case 1n+xp 1n+np 0n:
      ft_absurd({Nat.is_ge(0n, 1n+xp) == True{} : Bool}, h)
    case 1n+xp 1n+np 1n+bp:
      neg_ge(xp, np, bp, e, h)


# is_eq answers a two-way order.
def eq_ge(+x: Nat, +h: Nat, +p: {Nat.is_eq(x, h) == True{} : Bool}) -> {Nat.is_ge(h, x) == True{} : Bool}:
  match x h:
    case 0n 0n:
      {==}
    case 0n 1n+hp:
      ft_absurd({Nat.is_ge(1n+hp, 0n) == True{} : Bool}, p)
    case 1n+xp 0n:
      ft_absurd({Nat.is_ge(0n, 1n+xp) == True{} : Bool}, p)
    case 1n+xp 1n+hp:
      eq_ge(xp, hp, p)


# ---- the headroom picker: top bounds every candidate

def step_ge(+c: Maybe<&2, Nat>, +acc: Nat) -> {Nat.is_ge(K.top.step(c, acc), acc) == True{} : Bool}:
  match c:
    case None{}:
      Nat.ge_refl(acc)
    case Some{h}:
      Nat.max_ge_l(acc, h)

def top_ge_acc(+as: List<&2, T.Account>, +s: R.Sel, +acc: Nat) -> {Nat.is_ge(K.top(as, s, acc), acc) == True{} : Bool}:
  match as:
    case Nil{}:
      Nat.ge_refl(acc)
    case Con{a, t}:
      ge_trans(K.top(t, s, K.top.step(R.cand(a, s), acc)), K.top.step(R.cand(a, s), acc), acc, top_ge_acc(t, s, K.top.step(R.cand(a, s), acc)), step_ge(R.cand(a, s), acc))

def above_step(+c: Maybe<&2, Nat>, +acc: Nat, +b: Nat, +hb: {Nat.is_ge(b, K.top.step(c, acc)) == True{} : Bool}) -> {S.above.at(c, b) == True{} : Bool}:
  match c:
    case None{}:
      {==}
    case Some{h}:
      ge_trans(b, Nat.max(acc, h), h, hb, Nat.max_ge_r(acc, h))

def cands_top(+as: List<&2, T.Account>, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +acc: Nat) -> {S.cands_le(as, K.top(as, R.Sel{active, bar, need, us, now, ms}, acc), active, bar, need, us, now, ms) == True{} : Bool}:
  match as:
    case Nil{}:
      {==}
    case Con{a, t}:
      and_intro(
        S.above.at(R.cand(a, R.Sel{active, bar, need, us, now, ms}), K.top(t, R.Sel{active, bar, need, us, now, ms}, K.top.step(R.cand(a, R.Sel{active, bar, need, us, now, ms}), acc))),
        S.cands_le(t, K.top(t, R.Sel{active, bar, need, us, now, ms}, K.top.step(R.cand(a, R.Sel{active, bar, need, us, now, ms}), acc)), active, bar, need, us, now, ms),
        above_step(R.cand(a, R.Sel{active, bar, need, us, now, ms}), acc, K.top(t, R.Sel{active, bar, need, us, now, ms}, K.top.step(R.cand(a, R.Sel{active, bar, need, us, now, ms}), acc)), top_ge_acc(t, R.Sel{active, bar, need, us, now, ms}, K.top.step(R.cand(a, R.Sel{active, bar, need, us, now, ms}), acc))),
        cands_top(t, active, bar, need, us, now, ms, K.top.step(R.cand(a, R.Sel{active, bar, need, us, now, ms}), acc)))

# ---- none_above from the candidate bound

def gate_at(+ok: Bool, +x: Nat, +need: Nat, +b: Nat, +e: {Nat.is_ge(x, need) == ok : Bool}, +h1: {S.above.at(R.cand.gate.at(ok, x), b) == True{} : Bool}, +h2: {Nat.is_ge(b, need) == True{} : Bool}) -> {Nat.is_ge(b, x) == True{} : Bool}:
  match ok:
    case True{}:
      h1
    case False{}:
      neg_ge(x, need, b, e, h2)

def above_gate(+m: Maybe<&2, Nat>, +need: Nat, +b: Nat, +h1: {S.above.at(R.cand.gate(m, need), b) == True{} : Bool}, +h2: {Nat.is_ge(b, need) == True{} : Bool}) -> {S.above.at(m, b) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{x}:
      gate_at(Nat.is_ge(x, need), x, need, b, {==}, h1, h2)

def none_above_from(+as: List<&2, T.Account>, +b: Nat, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +hc: {S.cands_le(as, b, active, bar, need, us, now, ms) == True{} : Bool}, +hn: {Nat.is_ge(b, need) == True{} : Bool}) -> {S.none_above(as, b, active, bar, us, now, ms) == True{} : Bool}:
  match as:
    case Nil{}:
      {==}
    case Con{a, t}:
      and_intro(
        S.above.at(R.elig(a, R.Sel{active, bar, 0n, us, now, ms}), b),
        S.none_above(t, b, active, bar, us, now, ms),
        above_gate(R.elig(a, R.Sel{active, bar, 0n, us, now, ms}), need, b, and_l(S.above.at(R.cand(a, R.Sel{active, bar, need, us, now, ms}), b), S.cands_le(t, b, active, bar, need, us, now, ms), hc), hn),
        none_above_from(t, b, active, bar, need, us, now, ms, and_r(S.above.at(R.cand(a, R.Sel{active, bar, need, us, now, ms}), b), S.cands_le(t, b, active, bar, need, us, now, ms), hc), hn))

# ---- facts about a hit candidate

def hit_gate_a_at(+ok: Bool, +x: Nat, +need: Nat, +h: Nat, +hit: {K.first.hit(R.cand.gate.at(ok, x), h) == True{} : Bool}) -> {K.first.hit(Some{x}, h) == True{} : Bool}:
  match ok:
    case True{}:
      hit
    case False{}:
      ft_absurd({K.first.hit(Some{x}, h) == True{} : Bool}, hit)

def hit_gate_a(+m: Maybe<&2, Nat>, +need: Nat, +h: Nat, +hit: {K.first.hit(R.cand.gate(m, need), h) == True{} : Bool}) -> {K.first.hit(m, h) == True{} : Bool}:
  match m:
    case None{}:
      hit
    case Some{x}:
      hit_gate_a_at(Nat.is_ge(x, need), x, need, h, hit)

def hit_gate_b_at(+ok: Bool, +x: Nat, +need: Nat, +h: Nat, +e: {Nat.is_ge(x, need) == ok : Bool}, +hit: {K.first.hit(R.cand.gate.at(ok, x), h) == True{} : Bool}) -> {Nat.is_ge(h, need) == True{} : Bool}:
  match ok:
    case True{}:
      ge_trans(h, x, need, eq_ge(x, h, hit), e)
    case False{}:
      ft_absurd({Nat.is_ge(h, need) == True{} : Bool}, hit)

def hit_gate_b(+m: Maybe<&2, Nat>, +need: Nat, +h: Nat, +hit: {K.first.hit(R.cand.gate(m, need), h) == True{} : Bool}) -> {Nat.is_ge(h, need) == True{} : Bool}:
  match m:
    case None{}:
      ft_absurd({Nat.is_ge(h, need) == True{} : Bool}, hit)
    case Some{x}:
      hit_gate_b_at(Nat.is_ge(x, need), x, need, h, {==}, hit)

# ---- an eligible reading is a trusted one

def some_pos(+hd: Maybe<&2, Nat>, +p: {E.is_some(R.elig.pos(hd)) == True{} : Bool}) -> {E.is_some(hd) == True{} : Bool}:
  match hd:
    case None{}:
      p
    case Some{x}:
      {==}

def some_row(+m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +p: {E.is_some(R.elig.row(m, now, ms)) == True{} : Bool}) -> {S.usable.row(m, now, ms) == True{} : Bool}:
  match m:
    case None{}:
      p
    case Some{u}:
      some_pos(U.headroom(u, now, ms), p)

def some_ok(+b: Bool, +m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +p: {E.is_some(R.sel.ok(b, m, now, ms)) == True{} : Bool}) -> {Bool.and(b, S.usable.row(m, now, ms)) == True{} : Bool}:
  match b:
    case True{}:
      some_row(m, now, ms, p)
    case False{}:
      p

def hit_some(+c: Maybe<&2, Nat>, +h: Nat, +p: {K.first.hit(c, h) == True{} : Bool}) -> {E.is_some(c) == True{} : Bool}:
  match c:
    case None{}:
      p
    case Some{x}:
      {==}

def isc_not_active(+a: T.Account, +active: Nat, +p: {R.isc(a, active) == True{} : Bool}) -> {Bool.not(Nat.is_eq(U.account.slot(a), active)) == True{} : Bool}:
  match a:
    case T.Account{slot, email, kind, disabled}:
      and_r(R.is_oauth(kind) && Bool.not(disabled), Bool.not(Nat.is_eq(slot, active)), p)

def trusted_of_ok(+x: Bool, +nb: Bool, +ur: Bool, +p: {Bool.and(Bool.and(x, nb), ur) == True{} : Bool}) -> {Bool.and(x, ur) == True{} : Bool}:
  and_intro(x, ur, and_l(x, nb, and_l(Bool.and(x, nb), ur, p)), and_r(Bool.and(x, nb), ur, p))

# an eligible account has a trusted reading and is a switchable candidate
def elig_trusted(+a: T.Account, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +p: {E.is_some(R.elig(a, R.Sel{active, bar, need, us, now, ms})) == True{} : Bool}) -> {S.trusted_acct(a, active, us, now, ms) == True{} : Bool}:
  match a:
    case T.Account{slot, email, kind, disabled}:
      trusted_of_ok(R.is_oauth(kind) && Bool.not(disabled) && Bool.not(Nat.is_eq(slot, active)), Bool.not(R.barred(bar, slot)), S.usable.row(U.usage.of(slot, us), now, ms), some_ok(R.target.base(T.Account{slot, email, kind, disabled}, active, bar), U.usage.of(slot, us), now, ms, p))

def hit_elig(+a: T.Account, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +h: Nat, +hit: {K.first.hit(R.cand(a, R.Sel{active, bar, need, us, now, ms}), h) == True{} : Bool}) -> {K.first.hit(R.elig(a, R.Sel{active, bar, 0n, us, now, ms}), h) == True{} : Bool}:
  hit_gate_a(R.elig(a, R.Sel{active, bar, need, us, now, ms}), need, h, hit)

def hit_trusted(+a: T.Account, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +h: Nat, +hit: {K.first.hit(R.cand(a, R.Sel{active, bar, need, us, now, ms}), h) == True{} : Bool}) -> {S.trusted_acct(a, active, us, now, ms) == True{} : Bool}:
  elig_trusted(a, active, bar, need, us, now, ms, hit_some(R.elig(a, R.Sel{active, bar, need, us, now, ms}), h, hit_gate_a(R.elig(a, R.Sel{active, bar, need, us, now, ms}), need, h, hit)))

def hit_ge(+a: T.Account, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +h: Nat, +hit: {K.first.hit(R.cand(a, R.Sel{active, bar, need, us, now, ms}), h) == True{} : Bool}) -> {Nat.is_ge(h, need) == True{} : Bool}:
  hit_gate_b(R.elig(a, R.Sel{active, bar, need, us, now, ms}), need, h, hit)

# a trusted account is a candidate, so it is not the live one
def trusted_not_active(+a: T.Account, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +p: {S.trusted_acct(a, active, us, now, ms) == True{} : Bool}) -> {Bool.not(Nat.is_eq(U.account.slot(a), active)) == True{} : Bool}:
  isc_not_active(a, active, and_l(R.isc(a, active), S.usable.row(U.usage.of(U.account.slot(a), us), now, ms), p))

# ---- four-way conjunctions
def c4_u(+u: Bool, +h: Bool, +g: Bool, +n: Bool, +p: {Bool.and(Bool.and(Bool.and(u, h), g), n) == True{} : Bool}) -> {u == True{} : Bool}:
  and_l(u, h, and_l(Bool.and(u, h), g, and_l(Bool.and(Bool.and(u, h), g), n, p)))

def c4_h(+u: Bool, +h: Bool, +g: Bool, +n: Bool, +p: {Bool.and(Bool.and(Bool.and(u, h), g), n) == True{} : Bool}) -> {h == True{} : Bool}:
  and_r(u, h, and_l(Bool.and(u, h), g, and_l(Bool.and(Bool.and(u, h), g), n, p)))

def c4_g(+u: Bool, +h: Bool, +g: Bool, +n: Bool, +p: {Bool.and(Bool.and(Bool.and(u, h), g), n) == True{} : Bool}) -> {g == True{} : Bool}:
  and_r(Bool.and(u, h), g, and_l(Bool.and(Bool.and(u, h), g), n, p))

def c4_n(+u: Bool, +h: Bool, +g: Bool, +n: Bool, +p: {Bool.and(Bool.and(Bool.and(u, h), g), n) == True{} : Bool}) -> {n == True{} : Bool}:
  and_r(Bool.and(Bool.and(u, h), g), n, p)

def c4_intro(+u: Bool, +h: Bool, +g: Bool, +n: Bool, +pu: {u == True{} : Bool}, +ph: {h == True{} : Bool}, +pg: {g == True{} : Bool}, +pn: {n == True{} : Bool}) -> {Bool.and(Bool.and(Bool.and(u, h), g), n) == True{} : Bool}:
  and_intro(Bool.and(Bool.and(u, h), g), n, and_intro(Bool.and(u, h), g, and_intro(u, h, pu, ph), pg), pn)

# ---- first_inv: lift over a longer list, and one step of `first`

def fi_lift(+r: Maybe<&2, Nat>, +a: T.Account, +t: List<&2, T.Account>, +h: Nat, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +ih: {S.first_inv(r, t, h, active, bar, need, us, now, ms) == True{} : Bool}) -> {S.first_inv(r, Con{a, t}, h, active, bar, need, us, now, ms) == True{} : Bool}:
  match r:
    case None{}:
      {==}
    case Some{to}:
      c4_intro(
        S.trusted_target(Con{a, t}, to, active, us, now, ms),
        S.has_headroom(Con{a, t}, to, h, active, bar, us, now, ms),
        Nat.is_ge(h, need),
        Bool.not(Nat.is_eq(to, active)),
        or_intro_r(Nat.is_eq(to, U.account.slot(a)) && S.trusted_acct(a, active, us, now, ms), S.trusted_target(t, to, active, us, now, ms),
          c4_u(S.trusted_target(t, to, active, us, now, ms), S.has_headroom(t, to, h, active, bar, us, now, ms), Nat.is_ge(h, need), Bool.not(Nat.is_eq(to, active)), ih)),
        or_intro_r(Nat.is_eq(to, U.account.slot(a)) && K.first.hit(R.elig(a, R.Sel{active, bar, 0n, us, now, ms}), h), S.has_headroom(t, to, h, active, bar, us, now, ms),
          c4_h(S.trusted_target(t, to, active, us, now, ms), S.has_headroom(t, to, h, active, bar, us, now, ms), Nat.is_ge(h, need), Bool.not(Nat.is_eq(to, active)), ih)),
        c4_g(S.trusted_target(t, to, active, us, now, ms), S.has_headroom(t, to, h, active, bar, us, now, ms), Nat.is_ge(h, need), Bool.not(Nat.is_eq(to, active)), ih),
        c4_n(S.trusted_target(t, to, active, us, now, ms), S.has_headroom(t, to, h, active, bar, us, now, ms), Nat.is_ge(h, need), Bool.not(Nat.is_eq(to, active)), ih))

def fi_step(+hit: Bool, +a: T.Account, +t: List<&2, T.Account>, +rest: Maybe<&2, Nat>, +h: Nat, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +e: {K.first.hit(R.cand(a, R.Sel{active, bar, need, us, now, ms}), h) == hit : Bool}, +ih: {S.first_inv(rest, t, h, active, bar, need, us, now, ms) == True{} : Bool}) -> {S.first_inv(K.first.pick(hit, U.account.slot(a), rest), Con{a, t}, h, active, bar, need, us, now, ms) == True{} : Bool}:
  match hit:
    case False{}:
      fi_lift(rest, a, t, h, active, bar, need, us, now, ms, ih)
    case True{}:
      c4_intro(
        S.trusted_target(Con{a, t}, U.account.slot(a), active, us, now, ms),
        S.has_headroom(Con{a, t}, U.account.slot(a), h, active, bar, us, now, ms),
        Nat.is_ge(h, need),
        Bool.not(Nat.is_eq(U.account.slot(a), active)),
        or_intro_l(Nat.is_eq(U.account.slot(a), U.account.slot(a)) && S.trusted_acct(a, active, us, now, ms), S.trusted_target(t, U.account.slot(a), active, us, now, ms),
          and_intro(Nat.is_eq(U.account.slot(a), U.account.slot(a)), S.trusted_acct(a, active, us, now, ms), eq_refl(U.account.slot(a)), hit_trusted(a, active, bar, need, us, now, ms, h, e))),
        or_intro_l(Nat.is_eq(U.account.slot(a), U.account.slot(a)) && K.first.hit(R.elig(a, R.Sel{active, bar, 0n, us, now, ms}), h), S.has_headroom(t, U.account.slot(a), h, active, bar, us, now, ms),
          and_intro(Nat.is_eq(U.account.slot(a), U.account.slot(a)), K.first.hit(R.elig(a, R.Sel{active, bar, 0n, us, now, ms}), h), eq_refl(U.account.slot(a)), hit_elig(a, active, bar, need, us, now, ms, h, e))),
        hit_ge(a, active, bar, need, us, now, ms, h, e),
        trusted_not_active(a, active, us, now, ms, hit_trusted(a, active, bar, need, us, now, ms, h, e)))

def first_inv_all(+as: List<&2, T.Account>, +h: Nat, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> {S.first_inv(K.first(as, R.Sel{active, bar, need, us, now, ms}, h), as, h, active, bar, need, us, now, ms) == True{} : Bool}:
  match as:
    case Nil{}:
      {==}
    case Con{a, t}:
      fi_step(K.first.hit(R.cand(a, R.Sel{active, bar, need, us, now, ms}), h), a, t, K.first(t, R.Sel{active, bar, need, us, now, ms}, h), h, active, bar, need, us, now, ms, {==}, first_inv_all(t, h, active, bar, need, us, now, ms))

# ---- the headroom picker is sound

def pk_slot_head(+m: Maybe<&2, Nat>, +h: Nat, +as: List<&2, T.Account>, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +hf: {S.first_inv(m, as, h, active, bar, need, us, now, ms) == True{} : Bool}, +hc: {S.cands_le(as, h, active, bar, need, us, now, ms) == True{} : Bool}) -> {S.pmh_inv(K.pk.slot(m, None{}, h), as, active, bar, need, us, now, ms) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{slot}:
      c4_intro(
        S.trusted_target(as, slot, active, us, now, ms),
        S.has_headroom(as, slot, h, active, bar, us, now, ms),
        S.none_above(as, h, active, bar, us, now, ms),
        Bool.not(Nat.is_eq(slot, active)),
        c4_u(S.trusted_target(as, slot, active, us, now, ms), S.has_headroom(as, slot, h, active, bar, us, now, ms), Nat.is_ge(h, need), Bool.not(Nat.is_eq(slot, active)), hf),
        c4_h(S.trusted_target(as, slot, active, us, now, ms), S.has_headroom(as, slot, h, active, bar, us, now, ms), Nat.is_ge(h, need), Bool.not(Nat.is_eq(slot, active)), hf),
        none_above_from(as, h, active, bar, need, us, now, ms, hc, c4_g(S.trusted_target(as, slot, active, us, now, ms), S.has_headroom(as, slot, h, active, bar, us, now, ms), Nat.is_ge(h, need), Bool.not(Nat.is_eq(slot, active)), hf)),
        c4_n(S.trusted_target(as, slot, active, us, now, ms), S.has_headroom(as, slot, h, active, bar, us, now, ms), Nat.is_ge(h, need), Bool.not(Nat.is_eq(slot, active)), hf))

def pick_head_at_inv(+h0: Nat, +as: List<&2, T.Account>, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +hc: {S.cands_le(as, h0, active, bar, need, us, now, ms) == True{} : Bool}) -> {S.pmh_inv(K.pick.head.at(h0, as, R.Sel{active, bar, need, us, now, ms}), as, active, bar, need, us, now, ms) == True{} : Bool}:
  match h0:
    case 0n:
      {==}
    case 1n+p:
      pk_slot_head(K.first(as, R.Sel{active, bar, need, us, now, ms}, 1n+p), 1n+p, as, active, bar, need, us, now, ms, first_inv_all(as, 1n+p, active, bar, need, us, now, ms), hc)

def pick_head_inv(+as: List<&2, T.Account>, +active: Nat, +bar: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> {S.pmh_inv(K.pick.head(as, R.Sel{active, bar, need, us, now, ms}), as, active, bar, need, us, now, ms) == True{} : Bool}:
  pick_head_at_inv(K.top(as, R.Sel{active, bar, need, us, now, ms}, 0n), as, active, bar, need, us, now, ms, cands_top(as, active, bar, need, us, now, ms, 0n))

# ---- Nat and recovery-time order

def le_refl(+a: Nat) -> {Nat.is_le(a, a) == True{} : Bool}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      le_refl(p)

def le_trans(+a: Nat, +b: Nat, +c: Nat, +p: {Nat.is_le(a, b) == True{} : Bool}, +q: {Nat.is_le(b, c) == True{} : Bool}) -> {Nat.is_le(a, c) == True{} : Bool}:
  match a b c:
    case 0n _ 0n:
      {==}
    case 0n _ 1n+cp:
      {==}
    case 1n+ap 0n _:
      ft_absurd({Nat.is_le(a, c) == True{} : Bool}, p)
    case 1n+ap 1n+bp 0n:
      ft_absurd({Nat.is_le(a, c) == True{} : Bool}, q)
    case 1n+ap 1n+bp 1n+cp:
      le_trans(ap, bp, cp, p, q)

def min_le_l(+a: Nat, +b: Nat) -> {Nat.is_le(Nat.min(a, b), a) == True{} : Bool}:
  match a b:
    case 0n _:
      {==}
    case 1n+ap 0n:
      {==}
    case 1n+ap 1n+bp:
      min_le_l(ap, bp)

def min_le_r(+a: Nat, +b: Nat) -> {Nat.is_le(Nat.min(a, b), b) == True{} : Bool}:
  match a b:
    case 0n 0n:
      {==}
    case 0n 1n+bp:
      {==}
    case 1n+ap 0n:
      {==}
    case 1n+ap 1n+bp:
      min_le_r(ap, bp)

def rle_refl(+x: Maybe<&2, Nat>) -> {R.rec.rle(x, x) == True{} : Bool}:
  match x:
    case None{}:
      {==}
    case Some{a}:
      le_refl(a)

def rle_trans(+x: Maybe<&2, Nat>, +y: Maybe<&2, Nat>, +z: Maybe<&2, Nat>, +p: {R.rec.rle(x, y) == True{} : Bool}, +q: {R.rec.rle(y, z) == True{} : Bool}) -> {R.rec.rle(x, z) == True{} : Bool}:
  match x y z:
    case None{} None{} None{}:
      {==}
    case None{} Some{b} None{}:
      {==}
    case Some{a} None{} None{}:
      {==}
    case Some{a} Some{b} None{}:
      {==}
    case None{} None{} Some{c}:
      ft_absurd({R.rec.rle(x, z) == True{} : Bool}, q)
    case None{} Some{b} Some{c}:
      ft_absurd({R.rec.rle(x, z) == True{} : Bool}, p)
    case Some{a} None{} Some{c}:
      ft_absurd({R.rec.rle(x, z) == True{} : Bool}, q)
    case Some{a} Some{b} Some{c}:
      le_trans(a, b, c, p, q)

def rmin_l(+x: Maybe<&2, Nat>, +y: Maybe<&2, Nat>) -> {R.rec.rle(R.rec.min(x, y), x) == True{} : Bool}:
  match x y:
    case None{} None{}:
      {==}
    case None{} Some{b}:
      {==}
    case Some{a} None{}:
      le_refl(a)
    case Some{a} Some{b}:
      min_le_l(a, b)

def rmin_r(+x: Maybe<&2, Nat>, +y: Maybe<&2, Nat>) -> {R.rec.rle(R.rec.min(x, y), y) == True{} : Bool}:
  match x y:
    case None{} None{}:
      {==}
    case None{} Some{b}:
      le_refl(b)
    case Some{a} None{}:
      {==}
    case Some{a} Some{b}:
      min_le_r(a, b)

# ---- the earliest ranking time

def mn_le_refl(+m: K.Mn) -> {S.mn_le(m, m) == True{} : Bool}:
  match m:
    case K.MnNone{}:
      {==}
    case K.MnAt{x}:
      rle_refl(x)

def mn_le_trans(+a: K.Mn, +b: K.Mn, +c: K.Mn, +p: {S.mn_le(a, b) == True{} : Bool}, +q: {S.mn_le(b, c) == True{} : Bool}) -> {S.mn_le(a, c) == True{} : Bool}:
  match a b c:
    case K.MnNone{} K.MnNone{} K.MnNone{}:
      {==}
    case K.MnNone{} K.MnAt{y} K.MnNone{}:
      {==}
    case K.MnAt{x} K.MnNone{} K.MnNone{}:
      {==}
    case K.MnAt{x} K.MnAt{y} K.MnNone{}:
      {==}
    case K.MnNone{} K.MnNone{} K.MnAt{z}:
      ft_absurd({S.mn_le(a, c) == True{} : Bool}, q)
    case K.MnNone{} K.MnAt{y} K.MnAt{z}:
      ft_absurd({S.mn_le(a, c) == True{} : Bool}, p)
    case K.MnAt{x} K.MnNone{} K.MnAt{z}:
      ft_absurd({S.mn_le(a, c) == True{} : Bool}, q)
    case K.MnAt{x} K.MnAt{y} K.MnAt{z}:
      rle_trans(x, y, z, p, q)

def step_le(+c: Maybe<&2, K.RH>, +m: K.Mn) -> {S.mn_le(K.minr.step(c, m), m) == True{} : Bool}:
  match c:
    case None{}:
      mn_le_refl(m)
    case Some{x}:
      match x:
        case K.RH{r, h}:
          match m:
            case K.MnNone{}:
              {==}
            case K.MnAt{x0}:
              rmin_l(x0, r)

def minr_le(+as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam, +m: K.Mn) -> {S.mn_le(K.minr(as, rk, f, m), m) == True{} : Bool}:
  match as:
    case Nil{}:
      mn_le_refl(m)
    case Con{a, t}:
      mn_le_trans(K.minr(t, rk, f, K.minr.step(K.cdn(a, rk, f), m)), K.minr.step(K.cdn(a, rk, f), m), m, minr_le(t, rk, f, K.minr.step(K.cdn(a, rk, f), m)), step_le(K.cdn(a, rk, f), m))

def grp_at_min(+m: K.Mn, +rx: Maybe<&2, Nat>, +r: Maybe<&2, Nat>, +hle: {S.mn_le(K.MnAt{r}, K.mn.min(m, rx)) == True{} : Bool}) -> {R.rec.rle(r, rx) == True{} : Bool}:
  match m:
    case K.MnNone{}:
      hle
    case K.MnAt{x0}:
      rle_trans(r, R.rec.min(x0, rx), rx, hle, rmin_r(x0, rx))

def grp_at_of(+c: Maybe<&2, K.RH>, +m: K.Mn, +r: Maybe<&2, Nat>, +hle: {S.mn_le(K.MnAt{r}, K.minr.step(c, m)) == True{} : Bool}) -> {S.grp.at(c, r) == True{} : Bool}:
  match c:
    case None{}:
      {==}
    case Some{x}:
      match x:
        case K.RH{rx, hx}:
          grp_at_min(m, rx, r, hle)

def cov_cons(+res: K.Mn, +a: T.Account, +t: List<&2, T.Account>, +m: K.Mn, +rk: K.Rk, +f: K.Fam, +hle: {S.mn_le(res, K.minr.step(K.cdn(a, rk, f), m)) == True{} : Bool}, +ih: {S.mn_cov(res, t, rk, f) == True{} : Bool}) -> {S.mn_cov(res, Con{a, t}, rk, f) == True{} : Bool}:
  match res:
    case K.MnNone{}:
      {==}
    case K.MnAt{r}:
      and_intro(S.grp.at(K.cdn(a, rk, f), r), S.grp_min(t, rk, f, r), grp_at_of(K.cdn(a, rk, f), m, r, hle), ih)

def minr_cov(+as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam, +m: K.Mn) -> {S.mn_cov(K.minr(as, rk, f, m), as, rk, f) == True{} : Bool}:
  match as:
    case Nil{}:
      match m:
        case K.MnNone{}:
          {==}
        case K.MnAt{x}:
          {==}
    case Con{a, t}:
      cov_cons(K.minr(t, rk, f, K.minr.step(K.cdn(a, rk, f), m)), a, t, m, rk, f, minr_le(t, rk, f, K.minr.step(K.cdn(a, rk, f), m)), minr_cov(t, rk, f, K.minr.step(K.cdn(a, rk, f), m)))

# ---- a family candidate is an eligible one

def cdn_some_elig(+m: Maybe<&2, Nat>, +f: K.Fam, +a: T.Account, +rk: K.Rk, +p: {S.some_rh(K.cdn.at(m, f, a, rk)) == True{} : Bool}) -> {E.is_some(m) == True{} : Bool}:
  match m:
    case None{}:
      p
    case Some{x}:
      {==}

def cdn_trusted(+a: T.Account, +rk: K.Rk, +f: K.Fam, +p: {S.some_rh(K.cdn(a, rk, f)) == True{} : Bool}) -> {S.trusted_acct(a, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}:
  match rk:
    case K.Rk{t, cf, rm, ah0, best, ar, ars, thr, s}:
      match s:
        case R.Sel{active, bar, need, us, now, ms}:
          elig_trusted(a, active, bar, need, us, now, ms, cdn_some_elig(R.elig(a, R.Sel{active, bar, need, us, now, ms}), f, a, rk, p))

def hit_some_rh(+c: Maybe<&2, K.RH>, +r0: Maybe<&2, Nat>, +h0: Nat, +p: {K.firstrh.hit(c, r0, h0) == True{} : Bool}) -> {S.some_rh(c) == True{} : Bool}:
  match c:
    case None{}:
      p
    case Some{x}:
      {==}

def hit_rec(+c: Maybe<&2, K.RH>, +r0: Maybe<&2, Nat>, +h0: Nat, +p: {K.firstrh.hit(c, r0, h0) == True{} : Bool}) -> {S.rec.hit(c, r0) == True{} : Bool}:
  match c:
    case None{}:
      p
    case Some{x}:
      match x:
        case K.RH{r, h}:
          and_l(R.rec.req(r, r0), Nat.is_eq(h, h0), p)

# ---- three-way conjunctions
def c3_u(+u: Bool, +n: Bool, +h: Bool, +p: {Bool.and(Bool.and(u, n), h) == True{} : Bool}) -> {u == True{} : Bool}:
  and_l(u, n, and_l(Bool.and(u, n), h, p))

def c3_n(+u: Bool, +n: Bool, +h: Bool, +p: {Bool.and(Bool.and(u, n), h) == True{} : Bool}) -> {n == True{} : Bool}:
  and_r(u, n, and_l(Bool.and(u, n), h, p))

def c3_h(+u: Bool, +n: Bool, +h: Bool, +p: {Bool.and(Bool.and(u, n), h) == True{} : Bool}) -> {h == True{} : Bool}:
  and_r(Bool.and(u, n), h, p)

def c3_intro(+u: Bool, +n: Bool, +h: Bool, +pu: {u == True{} : Bool}, +pn: {n == True{} : Bool}, +ph: {h == True{} : Bool}) -> {Bool.and(Bool.and(u, n), h) == True{} : Bool}:
  and_intro(Bool.and(u, n), h, and_intro(u, n, pu, pn), ph)

# ---- firstrh: lift over a longer list, and one step

def fr_lift(+m: Maybe<&2, Nat>, +a: T.Account, +t: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam, +r0: Maybe<&2, Nat>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +ih: {S.fr_inv(m, t, rk, f, r0, active, us, now, ms) == True{} : Bool}) -> {S.fr_inv(m, Con{a, t}, rk, f, r0, active, us, now, ms) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{to}:
      c3_intro(
        S.trusted_target(Con{a, t}, to, active, us, now, ms),
        Bool.not(Nat.is_eq(to, active)),
        S.has_rec(Con{a, t}, rk, f, to, r0),
        or_intro_r(Nat.is_eq(to, U.account.slot(a)) && S.trusted_acct(a, active, us, now, ms), S.trusted_target(t, to, active, us, now, ms),
          c3_u(S.trusted_target(t, to, active, us, now, ms), Bool.not(Nat.is_eq(to, active)), S.has_rec(t, rk, f, to, r0), ih)),
        c3_n(S.trusted_target(t, to, active, us, now, ms), Bool.not(Nat.is_eq(to, active)), S.has_rec(t, rk, f, to, r0), ih),
        or_intro_r(Nat.is_eq(to, U.account.slot(a)) && S.rec.hit(K.cdn(a, rk, f), r0), S.has_rec(t, rk, f, to, r0),
          c3_h(S.trusted_target(t, to, active, us, now, ms), Bool.not(Nat.is_eq(to, active)), S.has_rec(t, rk, f, to, r0), ih)))

def fr_step(+hit: Bool, +a: T.Account, +t: List<&2, T.Account>, +rest: Maybe<&2, Nat>, +rk: K.Rk, +f: K.Fam, +r0: Maybe<&2, Nat>, +h0: Nat, +e: {K.firstrh.hit(K.cdn(a, rk, f), r0, h0) == hit : Bool}, +ih: {S.fr_inv(rest, t, rk, f, r0, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}) -> {S.fr_inv(K.first.pick(hit, U.account.slot(a), rest), Con{a, t}, rk, f, r0, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}:
  match hit:
    case False{}:
      fr_lift(rest, a, t, rk, f, r0, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk), ih)
    case True{}:
      c3_intro(
        S.trusted_target(Con{a, t}, U.account.slot(a), K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)),
        Bool.not(Nat.is_eq(U.account.slot(a), K.rk.active(rk))),
        S.has_rec(Con{a, t}, rk, f, U.account.slot(a), r0),
        or_intro_l(Nat.is_eq(U.account.slot(a), U.account.slot(a)) && S.trusted_acct(a, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)), S.trusted_target(t, U.account.slot(a), K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)),
          and_intro(Nat.is_eq(U.account.slot(a), U.account.slot(a)), S.trusted_acct(a, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)), eq_refl(U.account.slot(a)), cdn_trusted(a, rk, f, hit_some_rh(K.cdn(a, rk, f), r0, h0, e)))),
        trusted_not_active(a, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk), cdn_trusted(a, rk, f, hit_some_rh(K.cdn(a, rk, f), r0, h0, e))),
        or_intro_l(Nat.is_eq(U.account.slot(a), U.account.slot(a)) && S.rec.hit(K.cdn(a, rk, f), r0), S.has_rec(t, rk, f, U.account.slot(a), r0),
          and_intro(Nat.is_eq(U.account.slot(a), U.account.slot(a)), S.rec.hit(K.cdn(a, rk, f), r0), eq_refl(U.account.slot(a)), hit_rec(K.cdn(a, rk, f), r0, h0, e))))

def firstrh_inv(+as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam, +r0: Maybe<&2, Nat>, +h0: Nat) -> {S.fr_inv(K.firstrh(as, rk, f, r0, h0), as, rk, f, r0, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}:
  match as:
    case Nil{}:
      {==}
    case Con{a, t}:
      fr_step(K.firstrh.hit(K.cdn(a, rk, f), r0, h0), a, t, K.firstrh(t, rk, f, r0, h0), rk, f, r0, h0, {==}, firstrh_inv(t, rk, f, r0, h0))

# ---- the reset and recovery pickers

def pk_slot_g(+m: Maybe<&2, Nat>, +r0: Maybe<&2, Nat>, +h0: Nat, +as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam, +hf: {S.fr_inv(m, as, rk, f, r0, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}, +hg: {S.grp_min(as, rk, f, r0) == True{} : Bool}) -> {S.pmg(K.pk.slot(m, r0, h0), as, rk, f) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{slot}:
      and_intro(S.grp_min(as, rk, f, r0), S.has_rec(as, rk, f, slot, r0), hg, c3_h(S.trusted_target(as, slot, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)), Bool.not(Nat.is_eq(slot, K.rk.active(rk))), S.has_rec(as, rk, f, slot, r0), hf))

def pk_slot_ok(+m: Maybe<&2, Nat>, +r0: Maybe<&2, Nat>, +h0: Nat, +as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam, +hf: {S.fr_inv(m, as, rk, f, r0, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}) -> {S.pm_ok(K.pk.slot(m, r0, h0), as, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{slot}:
      and_intro(S.trusted_target(as, slot, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)), Bool.not(Nat.is_eq(slot, K.rk.active(rk))), c3_u(S.trusted_target(as, slot, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)), Bool.not(Nat.is_eq(slot, K.rk.active(rk))), S.has_rec(as, rk, f, slot, r0), hf), c3_n(S.trusted_target(as, slot, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)), Bool.not(Nat.is_eq(slot, K.rk.active(rk))), S.has_rec(as, rk, f, slot, r0), hf))

def pick_rh_at_g(+m: K.Mn, +as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam, +hc: {S.mn_cov(m, as, rk, f) == True{} : Bool}) -> {S.pmg(K.pick.rh.at(m, as, rk, f), as, rk, f) == True{} : Bool}:
  match m:
    case K.MnNone{}:
      {==}
    case K.MnAt{r0}:
      pk_slot_g(K.firstrh(as, rk, f, r0, K.maxh(as, rk, f, r0, 0n)), r0, K.maxh(as, rk, f, r0, 0n), as, rk, f, firstrh_inv(as, rk, f, r0, K.maxh(as, rk, f, r0, 0n)), hc)

def pick_rh_at_ok(+m: K.Mn, +as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam) -> {S.pm_ok(K.pick.rh.at(m, as, rk, f), as, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}:
  match m:
    case K.MnNone{}:
      {==}
    case K.MnAt{r0}:
      pk_slot_ok(K.firstrh(as, rk, f, r0, K.maxh(as, rk, f, r0, 0n)), r0, K.maxh(as, rk, f, r0, 0n), as, rk, f, firstrh_inv(as, rk, f, r0, K.maxh(as, rk, f, r0, 0n)))

def pick_rh_g(+as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam) -> {S.pmg(K.pick.rh(as, rk, f), as, rk, f) == True{} : Bool}:
  pick_rh_at_g(K.minr(as, rk, f, K.MnNone{}), as, rk, f, minr_cov(as, rk, f, K.MnNone{}))

def pick_rh_ok(+as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam) -> {S.pm_ok(K.pick.rh(as, rk, f), as, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}:
  pick_rh_at_ok(K.minr(as, rk, f, K.MnNone{}), as, rk, f)

def pick_hr_go_ok(+m: K.Mn, +h0: Nat, +as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam) -> {S.pm_ok(K.pick.hr.go(m, h0, as, rk, f), as, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}:
  match m:
    case K.MnNone{}:
      {==}
    case K.MnAt{r0}:
      pk_slot_ok(K.firstrh(as, rk, f, r0, h0), r0, h0, as, rk, f, firstrh_inv(as, rk, f, r0, h0))

def pick_hr_at_ok(+h0: Nat, +as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam) -> {S.pm_ok(K.pick.hr.at(h0, as, rk, f), as, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}:
  match h0:
    case 0n:
      {==}
    case 1n+p:
      pick_hr_go_ok(K.minat(as, rk, f, 1n+p, K.MnNone{}), 1n+p, as, rk, f)

def pick_hr_ok(+as: List<&2, T.Account>, +rk: K.Rk, +f: K.Fam) -> {S.pm_ok(K.pick.hr(as, rk, f), as, K.rk.active(rk), K.rk.us(rk), K.rk.now(rk), K.rk.ms(rk)) == True{} : Bool}:
  pick_hr_at_ok(K.maxall(as, rk, f, 0n), as, rk, f)

# ---- the ranking context, rebuilt from its parts

def mkrk(+t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> K.Rk:
  K.Rk{t0, cf, rm, ah0, best, ar, ars, thr, R.Sel{active, bar0, need, us, now, D.cfg.models(cfg)}}

def pmg_rk(+p: K.Pm, +as: List<&2, T.Account>, +rkA: K.Rk, +rkB: K.Rk, +f: K.Fam, +e: {rkA == rkB : K.Rk}, +g: {S.pmg(p, as, rkA, f) == True{} : Bool}) -> {S.pmg(p, as, rkB, f) == True{} : Bool}:
  %e : {S.pmg(p, as, _, f) == True{} : Bool}
  g

# ---- a picked target makes a sound decision

def sw_head(+pm: K.Pm, +as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hinv: {S.pmh_inv(pm, as, active, bar0, need, us, now, D.cfg.models(cfg)) == True{} : Bool}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.dec.sw(K.pk.of(T.MHead{}, pm), t, bar0, next), as, active, us, now, cfg) == True{} : Bool}:
  match pm:
    case K.PmNone{}:
      hn
    case K.PmAt{slot, r, h}:
      and_intro(
        S.landed_trusted(T.Switch{slot, t, T.trigger.name(t), h, T.MHead{}, r, bar0}, as, active, us, now, cfg) && S.landed_best(T.Switch{slot, t, T.trigger.name(t), h, T.MHead{}, r, bar0}, as, active, us, now, cfg) && True{},
        Bool.not(Nat.is_eq(slot, active)),
        and_intro(
          S.landed_trusted(T.Switch{slot, t, T.trigger.name(t), h, T.MHead{}, r, bar0}, as, active, us, now, cfg) && S.landed_best(T.Switch{slot, t, T.trigger.name(t), h, T.MHead{}, r, bar0}, as, active, us, now, cfg),
          True{},
          and_intro(
            S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)),
            S.has_headroom(as, slot, h, active, bar0, us, now, D.cfg.models(cfg)) && S.none_above(as, h, active, bar0, us, now, D.cfg.models(cfg)),
            c4_u(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), S.has_headroom(as, slot, h, active, bar0, us, now, D.cfg.models(cfg)), S.none_above(as, h, active, bar0, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hinv),
            and_intro(S.has_headroom(as, slot, h, active, bar0, us, now, D.cfg.models(cfg)), S.none_above(as, h, active, bar0, us, now, D.cfg.models(cfg)), c4_h(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), S.has_headroom(as, slot, h, active, bar0, us, now, D.cfg.models(cfg)), S.none_above(as, h, active, bar0, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hinv), c4_g(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), S.has_headroom(as, slot, h, active, bar0, us, now, D.cfg.models(cfg)), S.none_above(as, h, active, bar0, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hinv))),
          {==}),
        c4_n(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), S.has_headroom(as, slot, h, active, bar0, us, now, D.cfg.models(cfg)), S.none_above(as, h, active, bar0, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hinv))

def sw_reset(+pm: K.Pm, +as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hok: {S.pm_ok(pm, as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.dec.sw(K.pk.of(T.MReset{}, pm), t, bar0, next), as, active, us, now, cfg) == True{} : Bool}:
  match pm:
    case K.PmNone{}:
      hn
    case K.PmAt{slot, r, h}:
      and_intro(
        S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)) && True{} && True{},
        Bool.not(Nat.is_eq(slot, active)),
        and_intro(
          S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)) && True{},
          True{},
          and_intro(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), True{}, and_l(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hok), {==}),
          {==}),
        and_r(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hok))

def sw_fall(+pm: K.Pm, +as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hok: {S.pm_ok(pm, as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.dec.sw(K.pk.of(T.MFallback{}, pm), t, bar0, next), as, active, us, now, cfg) == True{} : Bool}:
  match pm:
    case K.PmNone{}:
      hn
    case K.PmAt{slot, r, h}:
      and_intro(
        S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)) && True{} && True{},
        Bool.not(Nat.is_eq(slot, active)),
        and_intro(
          S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)) && True{},
          True{},
          and_intro(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), True{}, and_l(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hok), {==}),
          {==}),
        and_r(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hok))

def sw_rec1(+pm: K.Pm, +as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hok: {S.pm_ok(pm, as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.dec.sw(K.pk.of(T.MRec1{}, pm), t, bar0, next), as, active, us, now, cfg) == True{} : Bool}:
  match pm:
    case K.PmNone{}:
      hn
    case K.PmAt{slot, r, h}:
      and_intro(
        S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)) && True{} && True{},
        Bool.not(Nat.is_eq(slot, active)),
        and_intro(
          S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)) && True{},
          True{},
          and_intro(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), True{}, and_l(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hok), {==}),
          {==}),
        and_r(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hok))

def sw_rec0(+pm: K.Pm, +as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hg: {S.pmg(pm, as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), K.FRec0{}) == True{} : Bool}, +hok: {S.pm_ok(pm, as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}, +hrk: {mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg) == S.rec_rk(t, bar0, active, as, us, now, cfg) : K.Rk}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.dec.sw(K.pk.of(T.MRec0{}, pm), t, bar0, next), as, active, us, now, cfg) == True{} : Bool}:
  match pm:
    case K.PmNone{}:
      hn
    case K.PmAt{slot, r, h}:
      and_intro(
        S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)) && True{} && S.pmg(K.PmAt{slot, r, h}, as, S.rec_rk(t, bar0, active, as, us, now, cfg), K.FRec0{}),
        Bool.not(Nat.is_eq(slot, active)),
        and_intro(
          S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)) && True{},
          S.pmg(K.PmAt{slot, r, h}, as, S.rec_rk(t, bar0, active, as, us, now, cfg), K.FRec0{}),
          and_intro(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), True{}, and_l(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hok), {==}),
          pmg_rk(K.PmAt{slot, r, h}, as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), S.rec_rk(t, bar0, active, as, us, now, cfg), K.FRec0{}, hrk, hg)),
        and_r(S.trusted_target(as, slot, active, us, now, D.cfg.models(cfg)), Bool.not(Nat.is_eq(slot, active)), hok))

def sw_rec_late(+p1: K.Pm, +as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hok1: {S.pm_ok(p1, as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.dec.sw(K.pick.rec.late(p1, as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg)), t, bar0, next), as, active, us, now, cfg) == True{} : Bool}:
  match p1:
    case K.PmNone{}:
      sw_fall(K.pick.rh(as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), K.FFall{}), as, t, next, t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg, pick_rh_ok(as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), K.FFall{}), hn)
    case K.PmAt{slot, r, h}:
      sw_rec1(p1, as, t, next, t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg, hok1, hn)

def sw_rec_mid(+p0: K.Pm, +as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hg: {S.pmg(p0, as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), K.FRec0{}) == True{} : Bool}, +hok0: {S.pm_ok(p0, as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}, +hrk: {mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg) == S.rec_rk(t, bar0, active, as, us, now, cfg) : K.Rk}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.dec.sw(K.pick.rec.mid(p0, as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg)), t, bar0, next), as, active, us, now, cfg) == True{} : Bool}:
  match p0:
    case K.PmNone{}:
      sw_rec_late(K.pick.hr(as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), K.FRec1{}), as, t, next, t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg, pick_hr_ok(as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), K.FRec1{}), hn)
    case K.PmAt{slot, r, h}:
      sw_rec0(p0, as, t, next, t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg, hg, hok0, hrk, hn)

def sw_rec(+as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hrk: {mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg) == S.rec_rk(t, bar0, active, as, us, now, cfg) : K.Rk}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.dec.sw(K.pick.rec(as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg)), t, bar0, next), as, active, us, now, cfg) == True{} : Bool}:
  sw_rec_mid(K.pick.rh(as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), K.FRec0{}), as, t, next, t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg, pick_rh_g(as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), K.FRec0{}), pick_rh_ok(as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), K.FRec0{}), hrk, hn)

def sw_cf(+cfx: Bool, +as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.dec.sw(K.pick.cf(cfx, as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg)), t, bar0, next), as, active, us, now, cfg) == True{} : Bool}:
  match cfx:
    case True{}:
      sw_reset(K.pick.rh(as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), K.FReset{}), as, t, next, t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg, pick_rh_ok(as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), K.FReset{}), hn)
    case False{}:
      sw_head(K.pick.head(as, R.Sel{active, bar0, need, us, now, D.cfg.models(cfg)}), as, t, next, t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg, pick_head_inv(as, active, bar0, need, us, now, D.cfg.models(cfg)), hn)

def sw_fam(+rmx: Bool, +as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hrk: {mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg) == S.rec_rk(t, bar0, active, as, us, now, cfg) : K.Rk}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.dec.sw(K.pick.fam(rmx, as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg)), t, bar0, next), as, active, us, now, cfg) == True{} : Bool}:
  match rmx:
    case True{}:
      sw_rec(as, t, next, t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg, hrk, hn)
    case False{}:
      sw_cf(cf, as, t, next, t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg, hn)

def sw_pick(+as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hrk: {mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg) == S.rec_rk(t, bar0, active, as, us, now, cfg) : K.Rk}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.sw.pick(mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), as, t, next), as, active, us, now, cfg) == True{} : Bool}:
  sw_fam(rm, as, t, next, t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg, hrk, hn)

# ---- decisions that cannot switch are sound

def l_none_exh_at(+ex: Bool, +er: E.Er, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> {S.sound(D.none.exh.at(ex, er), as, active, us, now, cfg) == True{} : Bool}:
  match ex:
    case True{}:
      {==}
    case False{}:
      {==}

def l_none_reset(+ars: Maybe<&2, Nat>, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> {S.sound(D.none.reset(ars), as, active, us, now, cfg) == True{} : Bool}:
  match ars:
    case None{}:
      {==}
    case Some{r}:
      {==}

def l_none_trig(+t: T.Trigger, +ex: Bool, +ars: Maybe<&2, Nat>, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +cfg: T.Config) -> {S.sound(D.none.trig(t, ex, ars, as, us, now, ms), as, active, us, now, cfg) == True{} : Bool}:
  match t:
    case T.Proactive{}:
      l_none_exh_at(ex, E.earliest(as, us, now, ms, E.ErNone{}), as, active, us, now, cfg)
    case T.AtLimit{}:
      l_none_exh_at(ex, E.earliest(as, us, now, ms, E.ErNone{}), as, active, us, now, cfg)
    case T.Failover{}:
      l_none_exh_at(ex, E.earliest(as, us, now, ms, E.ErNone{}), as, active, us, now, cfg)
    case T.ConsumeFirstT{}:
      l_none_reset(ars, as, active, us, now, cfg)

def l_none_known(+k: Bool, +t: T.Trigger, +ex: Bool, +ars: Maybe<&2, Nat>, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +cfg: T.Config) -> {S.sound(D.none.known(k, t, ex, ars, as, us, now, ms), as, active, us, now, cfg) == True{} : Bool}:
  match k:
    case True{}:
      l_none_trig(t, ex, ars, as, active, us, now, ms, cfg)
    case False{}:
      {==}

def l_none_cf(+t: T.Trigger, +ars: Maybe<&2, Nat>, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +cfg: T.Config) -> {S.sound(D.none.cf(t, ars, as, active, us, now, ms), as, active, us, now, cfg) == True{} : Bool}:
  l_none_known(E.any_known(as, active, us, now, ms), t, E.all_exhausted(as, active, us, now, ms), ars, as, active, us, now, ms, cfg)

# ---- the first last-resort API-key account is a valid target

def api_inv(+m: Maybe<&2, Nat>, +as: List<&2, T.Account>, +active: Nat, +include: Bool) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{slot}:
      S.api_target(as, slot, active, include) && Bool.not(Nat.is_eq(slot, active))

def isapi_not_active(+a: T.Account, +active: Nat, +p: {R.isapi(a, active) == True{} : Bool}) -> {Bool.not(Nat.is_eq(U.account.slot(a), active)) == True{} : Bool}:
  match a:
    case T.Account{slot, email, kind, disabled}:
      and_r(R.is_api(kind) && Bool.not(disabled), Bool.not(Nat.is_eq(slot, active)), p)

def api_lift(+m: Maybe<&2, Nat>, +a: T.Account, +t: List<&2, T.Account>, +active: Nat, +include: Bool, +ih: {api_inv(m, t, active, include) == True{} : Bool}) -> {api_inv(m, Con{a, t}, active, include) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{slot}:
      and_intro(S.api_target(Con{a, t}, slot, active, include), Bool.not(Nat.is_eq(slot, active)), or_intro_r(include && Nat.is_eq(slot, U.account.slot(a)) && R.isapi(a, active), S.api_target(t, slot, active, include), and_l(S.api_target(t, slot, active, include), Bool.not(Nat.is_eq(slot, active)), ih)), and_r(S.api_target(t, slot, active, include), Bool.not(Nat.is_eq(slot, active)), ih))

def api_step(+hit: Bool, +a: T.Account, +t: List<&2, T.Account>, +rest: Maybe<&2, Nat>, +active: Nat, +include: Bool, +hi: {include == True{} : Bool}, +e: {R.isapi(a, active) == hit : Bool}, +ih: {api_inv(rest, t, active, include) == True{} : Bool}) -> {api_inv(K.first.pick(hit, U.account.slot(a), rest), Con{a, t}, active, include) == True{} : Bool}:
  match hit:
    case False{}:
      api_lift(rest, a, t, active, include, ih)
    case True{}:
      and_intro(
        S.api_target(Con{a, t}, U.account.slot(a), active, include),
        Bool.not(Nat.is_eq(U.account.slot(a), active)),
        or_intro_l(include && Nat.is_eq(U.account.slot(a), U.account.slot(a)) && R.isapi(a, active), S.api_target(t, U.account.slot(a), active, include),
          and_intro(include && Nat.is_eq(U.account.slot(a), U.account.slot(a)), R.isapi(a, active), and_intro(include, Nat.is_eq(U.account.slot(a), U.account.slot(a)), hi, eq_refl(U.account.slot(a))), e)),
        isapi_not_active(a, active, e))

def api_first_inv(+as: List<&2, T.Account>, +active: Nat, +include: Bool, +hi: {include == True{} : Bool}) -> {api_inv(E.api.first(as, active), as, active, include) == True{} : Bool}:
  match as:
    case Nil{}:
      {==}
    case Con{a, t}:
      api_step(R.isapi(a, active), a, t, E.api.first(t, active), active, include, hi, {==}, api_first_inv(t, active, include, hi))

def l_api_pick(+m: Maybe<&2, Nat>, +t: T.Trigger, +next: T.Decision, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hi: {api_inv(m, as, active, D.cfg.include(cfg)) == True{} : Bool}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.api.pick(m, t, next), as, active, us, now, cfg) == True{} : Bool}:
  match m:
    case None{}:
      hn
    case Some{slot}:
      and_intro(
        S.api_target(as, slot, active, D.cfg.include(cfg)) && True{} && True{},
        Bool.not(Nat.is_eq(slot, active)),
        and_intro(
          S.api_target(as, slot, active, D.cfg.include(cfg)) && True{},
          True{},
          and_intro(S.api_target(as, slot, active, D.cfg.include(cfg)), True{}, and_l(S.api_target(as, slot, active, D.cfg.include(cfg)), Bool.not(Nat.is_eq(slot, active)), hi), {==}),
          {==}),
        and_r(S.api_target(as, slot, active, D.cfg.include(cfg)), Bool.not(Nat.is_eq(slot, active)), hi))

def l_api_gate_x(+ok: Bool, +t: T.Trigger, +next: T.Decision, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hinc: {D.cfg.include(cfg) == True{} : Bool}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.api.gate(ok, t, as, active, next), as, active, us, now, cfg) == True{} : Bool}:
  match ok:
    case True{}:
      l_api_pick(E.api.first(as, active), t, next, as, active, us, now, cfg, api_first_inv(as, active, D.cfg.include(cfg), hinc), hn)
    case False{}:
      hn

def l_api_gate(+ia: Bool, +x: Bool, +t: T.Trigger, +next: T.Decision, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +hia: {ia == D.cfg.include(cfg) : Bool}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.api.gate(ia && x, t, as, active, next), as, active, us, now, cfg) == True{} : Bool}:
  match ia:
    case True{}:
      l_api_gate_x(x, t, next, as, active, us, now, cfg, Equal.sym(Bool, True{}, D.cfg.include(cfg), hia), hn)
    case False{}:
      hn

def l_decide_none(+t: T.Trigger, +ars: Maybe<&2, Nat>, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> {S.sound(D.decide.none(t, ars, as, active, us, now, cfg), as, active, us, now, cfg) == True{} : Bool}:
  match cfg:
    case T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}:
      l_api_gate(ia, D.trig.not_cf(t), t, D.none.cf(t, ars, as, active, us, now, ms), as, active, us, now, T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}, {==}, l_none_cf(t, ars, as, active, us, now, ms, T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}))

# ---- ranking with the bar

def l_choose_retry(+go: Bool, +t: T.Trigger, +next: T.Decision, +t0: T.Trigger, +cf: Bool, +rm: Bool, +ah0: Nat, +best: Nat, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +thr: Nat, +active: Nat, +bar0: Maybe<&2, Nat>, +need: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +as: List<&2, T.Account>, +hrk: {mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, None{}, need, us, now, cfg) == S.rec_rk(t, None{}, active, as, us, now, cfg) : K.Rk}, +hn: {S.sound(next, as, active, us, now, cfg) == True{} : Bool}) -> {S.sound(D.choose.retry(go, t, as, mkrk(t0, cf, rm, ah0, best, ar, ars, thr, active, bar0, need, us, now, cfg), next), as, active, us, now, cfg) == True{} : Bool}:
  match go:
    case True{}:
      sw_pick(as, t, next, t0, cf, rm, ah0, best, ar, ars, thr, active, None{}, need, us, now, cfg, hrk, hn)
    case False{}:
      hn

def l_rank_bar(+bar: Maybe<&2, Nat>, +recov: Bool, +t: T.Trigger, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.rank.bar(bar, recov, t, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match cfg:
    case T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}:
      sw_pick(as, t, D.choose.retry(Bool.not(B.is_none(bar)) && recov, t, as, D.rk.base(t, D.env.ah(D.Env{active, as, us, now, T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}, st, mem}), active, as, us, now, T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}), D.decide.none(t, R.seven.row(U.usage.of(active, us), now, ms), as, active, us, now, T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia})), t, K.strat.cf(stg), Bool.and(R.all_above(R.meas(as, active, us, now, ms, thr, R.Meas{False{}, True{}, 0n}), U.head.row(U.usage.of(active, us), now, ms), thr), K.trig.pc(t)), K.ah.or0(U.head.row(U.usage.of(active, us), now, ms)), D.meas.best(R.meas(as, active, us, now, ms, thr, R.Meas{False{}, True{}, 0n})), R.rec.row(U.usage.of(active, us), now, ms), R.seven.row(U.usage.of(active, us), now, ms), thr, active, bar, K.need.of(t, K.ah.or0(U.head.row(U.usage.of(active, us), now, ms)), hy, thr), us, now, T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}, {==},
        l_choose_retry(Bool.not(B.is_none(bar)) && recov, t, D.decide.none(t, R.seven.row(U.usage.of(active, us), now, ms), as, active, us, now, T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}), t, K.strat.cf(stg), Bool.and(R.all_above(R.meas(as, active, us, now, ms, thr, R.Meas{False{}, True{}, 0n}), U.head.row(U.usage.of(active, us), now, ms), thr), K.trig.pc(t)), K.ah.or0(U.head.row(U.usage.of(active, us), now, ms)), D.meas.best(R.meas(as, active, us, now, ms, thr, R.Meas{False{}, True{}, 0n})), R.rec.row(U.usage.of(active, us), now, ms), R.seven.row(U.usage.of(active, us), now, ms), thr, active, None{}, K.need.of(t, K.ah.or0(U.head.row(U.usage.of(active, us), now, ms)), hy, thr), us, now, T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}, as, {==}, l_decide_none(t, R.seven.row(U.usage.of(active, us), now, ms), as, active, us, now, T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia})))

# ---- the stages of one tick

def l_rank_go(+t: T.Trigger, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.rank.go(t, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  l_rank_bar(B.no_return(t, st, active, B.recovered(st, active, us, D.env.ah(D.Env{active, as, us, now, cfg, st, mem}), D.cfg.threshold(cfg), now, D.cfg.models(cfg)), us, D.env.ah(D.Env{active, as, us, now, cfg, st, mem}), D.cfg.threshold(cfg), now, D.cfg.models(cfg)), B.recovered(st, active, us, D.env.ah(D.Env{active, as, us, now, cfg, st, mem}), D.cfg.threshold(cfg), now, D.cfg.models(cfg)), t, active, as, us, now, cfg, st, mem)

def l_cands_none(+blocked: Bool, +t: T.Trigger, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.cands.none(blocked, t, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match blocked:
    case True{}:
      {==}
    case False{}:
      l_rank_go(t, active, as, us, now, cfg, st, mem)

def l_cands_cf(+hold: Bool, +t: T.Trigger, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.cands.cf(hold, t, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match hold:
    case True{}:
      {==}
    case False{}:
      l_cands_none(Bool.not(E.any_cand(as, active)) && Bool.not(D.cfg.include(cfg) && E.any_api(as, active)), t, active, as, us, now, cfg, st, mem)

def l_decide_cands(+t: T.Trigger, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.decide.cands(t, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  l_cands_cf(D.trig.is_cf(t) && Bool.not(E.any_cand(as, active)) && Bool.not(B.is_none(D.env.ah(D.Env{active, as, us, now, cfg, st, mem}))), t, active, as, us, now, cfg, st, mem)

def l_cool_go(+cool: Bool, +t: T.Trigger, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.cool.go(cool, t, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match cool:
    case True{}:
      {==}
    case False{}:
      l_decide_cands(t, active, as, us, now, cfg, st, mem)

def l_decide_trig(+t: T.Trigger, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.decide.trig(t, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match t:
    case T.Proactive{}:
      l_cool_go(D.in_cooldown(D.st.last_at(st), now, D.cfg.cooldown(cfg)), T.Proactive{}, active, as, us, now, cfg, st, mem)
    case T.AtLimit{}:
      l_decide_cands(T.AtLimit{}, active, as, us, now, cfg, st, mem)
    case T.Failover{}:
      l_decide_cands(T.Failover{}, active, as, us, now, cfg, st, mem)
    case T.ConsumeFirstT{}:
      l_cool_go(D.in_cooldown(D.st.last_at(st), now, D.cfg.cooldown(cfg)), T.ConsumeFirstT{}, active, as, us, now, cfg, st, mem)

def l_below_go(+cfx: Bool, +a: Nat, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.below.go(cfx, a, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match cfx:
    case True{}:
      l_decide_trig(T.ConsumeFirstT{}, active, as, us, now, cfg, st, mem)
    case False{}:
      {==}

def l_util_go(+below: Bool, +a: Nat, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.util.go(below, a, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match below:
    case True{}:
      l_below_go(D.cfg.cf(cfg), a, active, as, us, now, cfg, st, mem)
    case False{}:
      l_decide_trig(D.trig.of(a), active, as, us, now, cfg, st, mem)

def l_fail_count(+wait: Bool, +n: Nat, +ut: Nat, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.fail.count(wait, n, ut, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match wait:
    case True{}:
      {==}
    case False{}:
      l_decide_trig(T.Failover{}, active, as, us, now, cfg, st, mem)

def l_failover_go(+n: Nat, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.failover.go(n, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  l_fail_count(Nat.is_lt(n, D.mem.ut(cfg)), n, D.mem.ut(cfg), active, as, us, now, cfg, st, mem)

def l_idle_go(+held: Bool, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.idle.go(held, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match held:
    case True{}:
      {==}
    case False{}:
      l_failover_go(Nat.add(D.mem.unhealthy(mem), 1n), active, as, us, now, cfg, st, mem)

def l_unknown_go(+expired: Bool, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.unknown.go(expired, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match expired:
    case False{}:
      {==}
    case True{}:
      l_idle_go(D.idle.held(mem, now), active, as, us, now, cfg, st, mem)

def l_decide_known(+ah: Maybe<&2, Nat>, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.decide.known(ah, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match ah:
    case Some{a}:
      l_util_go(Nat.is_lt(Nat.sub(T.full(), a), D.cfg.threshold(cfg)), a, active, as, us, now, cfg, st, mem)
    case None{}:
      l_unknown_go(D.row.expired(U.usage.of(active, us)), active, as, us, now, cfg, st, mem)

def l_decide_run(+active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.decide.run(D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  l_decide_known(U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)), active, as, us, now, cfg, st, mem)

def l_apikey_go(+include: Bool, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.apikey.go(include, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match include:
    case True{}:
      l_decide_run(active, as, us, now, cfg, st, mem)
    case False{}:
      {==}

def l_decide_kind(+k: T.AcctKind, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.decide.kind(k, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match k:
    case T.ApiKey{}:
      l_apikey_go(D.cfg.include(cfg), active, as, us, now, cfg, st, mem)
    case T.SetupToken{}:
      l_decide_run(active, as, us, now, cfg, st, mem)
    case T.FullLogin{}:
      l_decide_run(active, as, us, now, cfg, st, mem)

def l_decide_acct(+m: Maybe<&2, T.Account>, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.decide.acct(m, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, cfg) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{a}:
      match a:
        case T.Account{slot, email, kind, disabled}:
          l_decide_kind(kind, active, as, us, now, cfg, st, mem)

def l_decide(+active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.sound(D.decide(active, as, us, now, cfg, st, mem), as, active, us, now, cfg) == True{} : Bool}:
  l_decide_acct(U.account.of(active, as), active, as, us, now, cfg, st, mem)

# ---- unknown active headroom: no switch unless the failover trigger is reached

def sn_disc(+m: Maybe<&2, Nat>) -> Type:
  match m:
    case None{}:
      Empty
    case Some{x}:
      Unit

def sn_empty(+a: Nat, +e: {Some{a} == None{} : Maybe<&2, Nat>}) -> Empty:
  %e : sn_disc(_)
  Unit{}

def sn_absurd(-A: Type, +a: Nat, +e: {Some{a} == None{} : Maybe<&2, Nat>}) -> A:
  Empty.absurd(A, sn_empty(a, e))

def l2_fail_count(+wait: Bool, +n: Nat, +ut: Nat, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hf: {Bool.not(wait) == False{} : Bool}) -> {S.is_switch(D.fail.count(wait, n, ut, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  match wait:
    case True{}:
      {==}
    case False{}:
      tf_absurd({S.is_switch(D.fail.count(False{}, n, ut, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}, hf)

def l2_idle_go(+held: Bool, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hf: {Bool.and(Bool.not(held), Bool.not(Nat.is_lt(Nat.add(D.mem.unhealthy(mem), 1n), D.mem.ut(cfg)))) == False{} : Bool}) -> {S.is_switch(D.idle.go(held, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  match held:
    case True{}:
      {==}
    case False{}:
      l2_fail_count(Nat.is_lt(Nat.add(D.mem.unhealthy(mem), 1n), D.mem.ut(cfg)), Nat.add(D.mem.unhealthy(mem), 1n), D.mem.ut(cfg), active, as, us, now, cfg, st, mem, hf)

def l2_unknown_go(+expired: Bool, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hf: {Bool.and(Bool.and(expired, Bool.not(D.idle.held(mem, now))), Bool.not(Nat.is_lt(Nat.add(D.mem.unhealthy(mem), 1n), D.mem.ut(cfg)))) == False{} : Bool}) -> {S.is_switch(D.unknown.go(expired, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  match expired:
    case False{}:
      {==}
    case True{}:
      l2_idle_go(D.idle.held(mem, now), active, as, us, now, cfg, st, mem, hf)

def l2_known(+ah: Maybe<&2, Nat>, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hah: {ah == None{} : Maybe<&2, Nat>}, +hf: {S.failover_ready(active, us, now, cfg, mem) == False{} : Bool}) -> {S.is_switch(D.decide.known(ah, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  match ah:
    case Some{a}:
      sn_absurd({S.is_switch(D.decide.known(Some{a}, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}, a, hah)
    case None{}:
      l2_unknown_go(D.row.expired(U.usage.of(active, us)), active, as, us, now, cfg, st, mem, hf)

def l2_run(+active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hah: {U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)) == None{} : Maybe<&2, Nat>}, +hf: {S.failover_ready(active, us, now, cfg, mem) == False{} : Bool}) -> {S.is_switch(D.decide.run(D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  l2_known(U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)), active, as, us, now, cfg, st, mem, hah, hf)

def l2_apikey(+include: Bool, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hah: {U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)) == None{} : Maybe<&2, Nat>}, +hf: {S.failover_ready(active, us, now, cfg, mem) == False{} : Bool}) -> {S.is_switch(D.apikey.go(include, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  match include:
    case True{}:
      l2_run(active, as, us, now, cfg, st, mem, hah, hf)
    case False{}:
      {==}

def l2_kind(+k: T.AcctKind, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hah: {U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)) == None{} : Maybe<&2, Nat>}, +hf: {S.failover_ready(active, us, now, cfg, mem) == False{} : Bool}) -> {S.is_switch(D.decide.kind(k, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  match k:
    case T.ApiKey{}:
      l2_apikey(D.cfg.include(cfg), active, as, us, now, cfg, st, mem, hah, hf)
    case T.SetupToken{}:
      l2_run(active, as, us, now, cfg, st, mem, hah, hf)
    case T.FullLogin{}:
      l2_run(active, as, us, now, cfg, st, mem, hah, hf)

def l2_acct(+m: Maybe<&2, T.Account>, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hah: {U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)) == None{} : Maybe<&2, Nat>}, +hf: {S.failover_ready(active, us, now, cfg, mem) == False{} : Bool}) -> {S.is_switch(D.decide.acct(m, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{a}:
      match a:
        case T.Account{slot, email, kind, disabled}:
          l2_kind(kind, active, as, us, now, cfg, st, mem, hah, hf)

# ---- the laws

def Laws.decide_switch_trusted(active, accounts, usage, now, cfg, st, mem):
  c4_u(S.landed_trusted(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.landed_best(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.landed_rec(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.not_active(D.decide(active, accounts, usage, now, cfg, st, mem), active), l_decide(active, accounts, usage, now, cfg, st, mem))

def Laws.decide_switch_best_headroom(active, accounts, usage, now, cfg, st, mem):
  c4_h(S.landed_trusted(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.landed_best(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.landed_rec(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.not_active(D.decide(active, accounts, usage, now, cfg, st, mem), active), l_decide(active, accounts, usage, now, cfg, st, mem))

def Laws.decide_recovery_earliest(active, accounts, usage, now, cfg, st, mem):
  c4_g(S.landed_trusted(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.landed_best(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.landed_rec(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.not_active(D.decide(active, accounts, usage, now, cfg, st, mem), active), l_decide(active, accounts, usage, now, cfg, st, mem))

def Laws.decide_switch_not_active(active, accounts, usage, now, cfg, st, mem):
  c4_n(S.landed_trusted(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.landed_best(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.landed_rec(D.decide(active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, cfg), S.not_active(D.decide(active, accounts, usage, now, cfg, st, mem), active), l_decide(active, accounts, usage, now, cfg, st, mem))

def Laws.decide_unknown_no_switch_unless_failover(active, accounts, usage, now, cfg, st, mem, unknown, no_failover):
  l2_acct(U.account.of(active, accounts), active, accounts, usage, now, cfg, st, mem, unknown, no_failover)

def Laws.poll_due_backoff(u, now, cfg, inside):
  match u:
    case T.Usage{slot, five, fr, seven, sr, ss, fa, bo, er, nfl, np, pi, ad, hu, cu, se}:
      match cfg:
        case T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}:
          %Equal.sym(Bool, Cmp.is_lt(Nat.cmp(now, bo)), True{}, inside) : {U.poll.gate(Bool.or(Bool.or(Bool.or(_, Cmp.is_ge(Nat.cmp(ad, 1n))), Cmp.is_lt(Nat.cmp(now, hu))), Cmp.is_lt(Nat.cmp(now, cu))), U.poll.ready(np, now, pi, fa, ttl)) == False{} : Bool}
          {==}

# ==== proofs for the behaviour-profile strategies

def not_true(+b: Bool, +p: {Bool.not(b) == True{} : Bool}) -> {b == False{} : Bool}:
  match b:
    case True{}:
      ft_absurd({True{} == False{} : Bool}, p)
    case False{}:
      {==}

# A safe account is not the live slot.
def l_safe_na(+a: T.Account, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +hs: {SF.safe(a, active, us, now, ms) == True{} : Bool}) -> {Bool.not(Nat.is_eq(U.account.slot(a), active)) == True{} : Bool}:
  match a:
    case T.Account{slot, email, kind, disabled}:
      and_r(Bool.and(R.is_oauth(kind), Bool.not(disabled)), Bool.not(Nat.is_eq(slot, active)), and_l(R.isc(T.Account{slot, email, kind, disabled}, active), SF.row.safe(U.usage.of(slot, us), now, ms), hs))

# A candidate that passes the headroom gate names its account.
def l_need(+ok: Bool, +s: Nat, +k1: Maybe<&2, Nat>, +k2: Nat, +h: Nat, +active: Nat, +hna: {Bool.not(Nat.is_eq(s, active)) == True{} : Bool}) -> {SA.cand_ok(SF.cand.need(ok, SF.Cd{s, k1, k2, h}), s, True{}, active) == True{} : Bool}:
  match ok:
    case True{}:
      and_intro(Bool.and(Nat.is_eq(s, s), True{}), Bool.not(Nat.is_eq(s, active)), and_intro(Nat.is_eq(s, s), True{}, eq_refl(s), {==}), hna)
    case False{}:
      {==}

def l_go(+sf: Bool, +algo: SF.Algo, +a: T.Account, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +need: Nat, +hs: {SF.safe(a, active, us, now, ms) == sf : Bool}) -> {SA.cand_ok(SF.cand.go(sf, algo, a, active, us, now, ms, need), U.account.slot(a), sf, active) == True{} : Bool}:
  match sf:
    case True{}:
      l_need(Nat.is_ge(SF.h.of(U.head.row(U.usage.of(U.account.slot(a), us), now, ms)), need), U.account.slot(a), SF.key1(algo, active, U.account.slot(a), R.seven.row(U.usage.of(U.account.slot(a), us), now, ms)), SF.key2(algo, U.account.slot(a), SF.h.of(U.head.row(U.usage.of(U.account.slot(a), us), now, ms))), SF.h.of(U.head.row(U.usage.of(U.account.slot(a), us), now, ms)), active, l_safe_na(a, active, us, now, ms, hs))
    case False{}:
      {==}

def l_cand(+algo: SF.Algo, +a: T.Account, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +need: Nat) -> {SA.cand_ok(SF.cand(algo, a, active, us, now, ms, need), U.account.slot(a), SF.safe(a, active, us, now, ms), active) == True{} : Bool}:
  l_go(SF.safe(a, active, us, now, ms), algo, a, active, us, now, ms, need, {==})

# What the tail guarantees still holds with one more account in front.
def l_weak(+c: SF.Cd, +a: T.Account, +t: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +h: {SA.pick_ok(Some{c}, t, active, us, now, ms) == True{} : Bool}) -> {SA.pick_ok(Some{c}, Con{a, t}, active, us, now, ms) == True{} : Bool}:
  match c:
    case SF.Cd{slot, k1, k2, hh}:
      and_intro(SA.ok_target(Con{a, t}, slot, active, us, now, ms), Bool.not(Nat.is_eq(slot, active)),
        or_intro_r(Bool.and(Nat.is_eq(slot, U.account.slot(a)), SF.safe(a, active, us, now, ms)), SA.ok_target(t, slot, active, us, now, ms), and_l(SA.ok_target(t, slot, active, us, now, ms), Bool.not(Nat.is_eq(slot, active)), h)),
        and_r(SA.ok_target(t, slot, active, us, now, ms), Bool.not(Nat.is_eq(slot, active)), h))

# The head's own candidate is a safe target.
def l_head(+c: SF.Cd, +a: T.Account, +t: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +hm: {SA.cand_ok(Some{c}, U.account.slot(a), SF.safe(a, active, us, now, ms), active) == True{} : Bool}) -> {SA.pick_ok(Some{c}, Con{a, t}, active, us, now, ms) == True{} : Bool}:
  match c:
    case SF.Cd{slot, k1, k2, hh}:
      and_intro(SA.ok_target(Con{a, t}, slot, active, us, now, ms), Bool.not(Nat.is_eq(slot, active)),
        or_intro_l(Bool.and(Nat.is_eq(slot, U.account.slot(a)), SF.safe(a, active, us, now, ms)), SA.ok_target(t, slot, active, us, now, ms),
          and_l(Bool.and(Nat.is_eq(slot, U.account.slot(a)), SF.safe(a, active, us, now, ms)), Bool.not(Nat.is_eq(slot, active)), hm)),
        and_r(Bool.and(Nat.is_eq(slot, U.account.slot(a)), SF.safe(a, active, us, now, ms)), Bool.not(Nat.is_eq(slot, active)), hm))

def l_merge_at(+first: Bool, +c: SF.Cd, +d: SF.Cd, +a: T.Account, +t: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +hc: {SA.pick_ok(Some{c}, Con{a, t}, active, us, now, ms) == True{} : Bool}, +hd: {SA.pick_ok(Some{d}, t, active, us, now, ms) == True{} : Bool}) -> {SA.pick_ok(SF.merge.at(first, c, d), Con{a, t}, active, us, now, ms) == True{} : Bool}:
  match first:
    case True{}:
      l_weak(d, a, t, active, us, now, ms, hd)
    case False{}:
      hc

def l_merge_some(+c: SF.Cd, +tail: Maybe<&2, SF.Cd>, +a: T.Account, +t: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +hm: {SA.cand_ok(Some{c}, U.account.slot(a), SF.safe(a, active, us, now, ms), active) == True{} : Bool}, +ht: {SA.pick_ok(tail, t, active, us, now, ms) == True{} : Bool}) -> {SA.pick_ok(SF.merge.some(c, tail), Con{a, t}, active, us, now, ms) == True{} : Bool}:
  match tail:
    case None{}:
      l_head(c, a, t, active, us, now, ms, hm)
    case Some{d}:
      l_merge_at(SF.cd.lt(d, c), c, d, a, t, active, us, now, ms, l_head(c, a, t, active, us, now, ms, hm), ht)

def l_merge(+m: Maybe<&2, SF.Cd>, +tail: Maybe<&2, SF.Cd>, +a: T.Account, +t: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +hm: {SA.cand_ok(m, U.account.slot(a), SF.safe(a, active, us, now, ms), active) == True{} : Bool}, +ht: {SA.pick_ok(tail, t, active, us, now, ms) == True{} : Bool}) -> {SA.pick_ok(SF.merge(m, tail), Con{a, t}, active, us, now, ms) == True{} : Bool}:
  match m:
    case None{}:
      match tail:
        case None{}:
          {==}
        case Some{d}:
          l_weak(d, a, t, active, us, now, ms, ht)
    case Some{c}:
      l_merge_some(c, tail, a, t, active, us, now, ms, hm, ht)

# The picker only ever answers a safe account that is not the live slot.
def l_pick(+algo: SF.Algo, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +need: Nat) -> {SA.pick_ok(SF.pick(algo, as, active, us, now, ms, need), as, active, us, now, ms) == True{} : Bool}:
  match as:
    case Nil{}:
      {==}
    case Con{a, t}:
      l_merge(SF.cand(algo, a, active, us, now, ms, need), SF.pick(algo, t, active, us, now, ms, need), a, t, active, us, now, ms, l_cand(algo, a, active, us, now, ms, need), l_pick(algo, t, active, us, now, ms, need))

# ---- the decision chain: every strategy's decision is good

def l_sw(+m: Maybe<&2, SF.Cd>, +algo: SF.Algo, +t: T.Trigger, +next: T.Decision, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>, +hp: {SA.pick_ok(m, as, active, us, now, ms) == True{} : Bool}, +hn: {SA.good(next, as, active, us, now, ms) == True{} : Bool}) -> {SA.good(A.sw(m, algo, t, next), as, active, us, now, ms) == True{} : Bool}:
  match m:
    case None{}:
      hn
    case Some{c}:
      match c:
        case SF.Cd{slot, k1, k2, h}:
          and_intro(SA.landed_ok(T.Switch{slot, t, T.trigger.name(t), h, A.mode.of(algo), None{}, None{}}, as, active, us, now, ms), S.not_active(T.Switch{slot, t, T.trigger.name(t), h, A.mode.of(algo), None{}, None{}}, active),
            and_l(SA.ok_target(as, slot, active, us, now, ms), Bool.not(Nat.is_eq(slot, active)), hp),
            and_r(SA.ok_target(as, slot, active, us, now, ms), Bool.not(Nat.is_eq(slot, active)), hp))

def l_nosw(+d: T.Decision, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> {SA.good(A.nosw(d), as, active, us, now, ms) == True{} : Bool}:
  match d:
    case T.NoSwitch{r, detail}:
      {==}
    case T.Switch{to, t, why, h, mode, rec, bar}:
      {==}

def l_go_pick(+algo: SF.Algo, +via: A.Via, +a: Nat, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {SA.good(A.go.pick(algo, via, a, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}:
  l_sw(SF.pick(algo, as, active, us, now, D.cfg.models(cfg), A.need.of(algo, via, a, D.cfg.threshold(cfg))), algo, A.trig.via(via, a), A.nosw(D.none.cf(T.Proactive{}, None{}, as, active, us, now, D.cfg.models(cfg))), as, active, us, now, D.cfg.models(cfg),
    l_pick(algo, as, active, us, now, D.cfg.models(cfg), A.need.of(algo, via, a, D.cfg.threshold(cfg))),
    l_nosw(D.none.cf(T.Proactive{}, None{}, as, active, us, now, D.cfg.models(cfg)), as, active, us, now, D.cfg.models(cfg)))

def l_go_cool(+cool: Bool, +algo: SF.Algo, +via: A.Via, +a: Nat, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {SA.good(A.go.cool(cool, algo, via, a, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}:
  match cool:
    case True{}:
      {==}
    case False{}:
      l_go_pick(algo, via, a, active, as, us, now, cfg, st, mem)

def l_go_auto(+a: Nat, +algo: SF.Algo, +via: A.Via, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {SA.good(A.go.auto(a, algo, via, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}:
  match a:
    case 0n:
      l_go_pick(algo, via, a, active, as, us, now, cfg, st, mem)
    case 1n+p:
      l_go_cool(D.in_cooldown(D.st.last_at(st), now, D.cfg.cooldown(cfg)), algo, via, a, active, as, us, now, cfg, st, mem)

def l_go_via(+algo: SF.Algo, +via: A.Via, +a: Nat, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {SA.good(A.go.via(algo, via, a, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}:
  match via:
    case A.VAuto{}:
      l_go_auto(a, algo, via, active, as, us, now, cfg, st, mem)
    case A.VRotate{}:
      l_go_pick(algo, via, a, active, as, us, now, cfg, st, mem)

def l_go_below(+below: Bool, +algo: SF.Algo, +via: A.Via, +a: Nat, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {SA.good(A.go.below(below, algo, via, a, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}:
  match below:
    case True{}:
      {==}
    case False{}:
      l_go_via(algo, via, a, active, as, us, now, cfg, st, mem)

def l_go_known(+ah: Maybe<&2, Nat>, +algo: SF.Algo, +via: A.Via, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {SA.good(A.go.known(ah, algo, via, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}:
  match ah:
    case None{}:
      {==}
    case Some{a}:
      l_go_below(Bool.and(A.via.auto(via), Nat.is_lt(Nat.sub(T.full(), a), D.cfg.threshold(cfg))), algo, via, a, active, as, us, now, cfg, st, mem)

def l_go_kind(+k: T.AcctKind, +algo: SF.Algo, +via: A.Via, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {SA.good(A.go.kind(k, algo, via, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}:
  match k:
    case T.ApiKey{}:
      {==}
    case T.SetupToken{}:
      l_go_known(U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)), algo, via, active, as, us, now, cfg, st, mem)
    case T.FullLogin{}:
      l_go_known(U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)), algo, via, active, as, us, now, cfg, st, mem)

def l_go_acct(+m: Maybe<&2, T.Account>, +algo: SF.Algo, +via: A.Via, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {SA.good(A.go.acct(m, algo, via, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{a}:
      match a:
        case T.Account{slot, email, kind, disabled}:
          l_go_kind(kind, algo, via, active, as, us, now, cfg, st, mem)

def l_core(+algo: SF.Algo, +via: A.Via, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {SA.good(A.core(algo, via, D.Env{active, as, us, now, cfg, st, mem}), as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}:
  l_go_acct(U.account.of(active, as), algo, via, active, as, us, now, cfg, st, mem)

# ---- unknown active headroom never switches, whatever the strategy

def l3_known(+ah: Maybe<&2, Nat>, +algo: SF.Algo, +via: A.Via, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hah: {ah == None{} : Maybe<&2, Nat>}) -> {S.is_switch(A.go.known(ah, algo, via, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  match ah:
    case None{}:
      {==}
    case Some{a}:
      sn_absurd({S.is_switch(A.go.known(ah, algo, via, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}, a, hah)

def l3_kind(+k: T.AcctKind, +algo: SF.Algo, +via: A.Via, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hah: {U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)) == None{} : Maybe<&2, Nat>}) -> {S.is_switch(A.go.kind(k, algo, via, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  match k:
    case T.ApiKey{}:
      {==}
    case T.SetupToken{}:
      l3_known(U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)), algo, via, active, as, us, now, cfg, st, mem, hah)
    case T.FullLogin{}:
      l3_known(U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)), algo, via, active, as, us, now, cfg, st, mem, hah)

def l3_acct(+m: Maybe<&2, T.Account>, +algo: SF.Algo, +via: A.Via, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hah: {U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)) == None{} : Maybe<&2, Nat>}) -> {S.is_switch(A.go.acct(m, algo, via, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  match m:
    case None{}:
      {==}
    case Some{a}:
      match a:
        case T.Account{slot, email, kind, disabled}:
          l3_kind(kind, algo, via, active, as, us, now, cfg, st, mem, hah)

def l3_core(+algo: SF.Algo, +via: A.Via, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hah: {U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)) == None{} : Maybe<&2, Nat>}) -> {S.is_switch(A.core(algo, via, D.Env{active, as, us, now, cfg, st, mem})) == False{} : Bool}:
  l3_acct(U.account.of(active, as), algo, via, active, as, us, now, cfg, st, mem, hah)

# ---- the profile laws

def l_dec_good(+algo: SF.Algo, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hs: {SF.strict(algo) == True{} : Bool}) -> {SA.good(A.decide(algo, active, as, us, now, cfg, st, mem), as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}:
  match algo:
    case SF.ABest{}:
      ft_absurd({SA.good(A.decide(SF.ABest{}, active, as, us, now, cfg, st, mem), as, active, us, now, D.cfg.models(cfg)) == True{} : Bool}, hs)
    case SF.ARoundRobin{}:
      l_core(SF.ARoundRobin{}, A.VAuto{}, active, as, us, now, cfg, st, mem)
    case SF.ASoonestReset{}:
      l_core(SF.ASoonestReset{}, A.VAuto{}, active, as, us, now, cfg, st, mem)
    case SF.ASticky{}:
      l_core(SF.ASticky{}, A.VAuto{}, active, as, us, now, cfg, st, mem)
    case SF.ADrainFirst{}:
      l_core(SF.ADrainFirst{}, A.VAuto{}, active, as, us, now, cfg, st, mem)

def Laws.profile_safe_not_active(a, active, us, now, ms, safe):
  not_true(Nat.is_eq(U.account.slot(a), active), l_safe_na(a, active, us, now, ms, safe))

def Laws.profile_safe_known(a, active, us, now, ms, safe):
  and_l(SF.known(U.head.row(U.usage.of(U.account.slot(a), us), now, ms)), Bool.not(SF.exhausted(U.head.row(U.usage.of(U.account.slot(a), us), now, ms))),
    and_l(Bool.and(SF.known(U.head.row(U.usage.of(U.account.slot(a), us), now, ms)), Bool.not(SF.exhausted(U.head.row(U.usage.of(U.account.slot(a), us), now, ms)))), Bool.not(SF.backed_off(U.usage.of(U.account.slot(a), us), now)),
      and_r(R.isc(a, active), SF.row.safe(U.usage.of(U.account.slot(a), us), now, ms), safe)))

def Laws.profile_safe_not_exhausted(a, active, us, now, ms, safe):
  not_true(SF.exhausted(U.head.row(U.usage.of(U.account.slot(a), us), now, ms)),
    and_r(SF.known(U.head.row(U.usage.of(U.account.slot(a), us), now, ms)), Bool.not(SF.exhausted(U.head.row(U.usage.of(U.account.slot(a), us), now, ms))),
      and_l(Bool.and(SF.known(U.head.row(U.usage.of(U.account.slot(a), us), now, ms)), Bool.not(SF.exhausted(U.head.row(U.usage.of(U.account.slot(a), us), now, ms)))), Bool.not(SF.backed_off(U.usage.of(U.account.slot(a), us), now)),
        and_r(R.isc(a, active), SF.row.safe(U.usage.of(U.account.slot(a), us), now, ms), safe))))

def Laws.profile_safe_not_backoff(a, active, us, now, ms, safe):
  not_true(SF.backed_off(U.usage.of(U.account.slot(a), us), now),
    and_r(Bool.and(SF.known(U.head.row(U.usage.of(U.account.slot(a), us), now, ms)), Bool.not(SF.exhausted(U.head.row(U.usage.of(U.account.slot(a), us), now, ms)))), Bool.not(SF.backed_off(U.usage.of(U.account.slot(a), us), now)),
      and_r(R.isc(a, active), SF.row.safe(U.usage.of(U.account.slot(a), us), now, ms), safe)))

def Laws.profile_switch_target_safe(algo, active, accounts, usage, now, cfg, st, mem, strict):
  and_l(SA.landed_ok(A.decide(algo, active, accounts, usage, now, cfg, st, mem), accounts, active, usage, now, D.cfg.models(cfg)), S.not_active(A.decide(algo, active, accounts, usage, now, cfg, st, mem), active),
    l_dec_good(algo, active, accounts, usage, now, cfg, st, mem, strict))

def l_dec_na(+algo: SF.Algo, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> {S.not_active(A.decide(algo, active, as, us, now, cfg, st, mem), active) == True{} : Bool}:
  match algo:
    case SF.ABest{}:
      c4_n(S.landed_trusted(D.decide(active, as, us, now, cfg, st, mem), as, active, us, now, cfg), S.landed_best(D.decide(active, as, us, now, cfg, st, mem), as, active, us, now, cfg), S.landed_rec(D.decide(active, as, us, now, cfg, st, mem), as, active, us, now, cfg), S.not_active(D.decide(active, as, us, now, cfg, st, mem), active), l_decide(active, as, us, now, cfg, st, mem))
    case SF.ARoundRobin{}:
      and_r(SA.landed_ok(A.decide(SF.ARoundRobin{}, active, as, us, now, cfg, st, mem), as, active, us, now, D.cfg.models(cfg)), S.not_active(A.decide(SF.ARoundRobin{}, active, as, us, now, cfg, st, mem), active), l_dec_good(SF.ARoundRobin{}, active, as, us, now, cfg, st, mem, {==}))
    case SF.ASoonestReset{}:
      and_r(SA.landed_ok(A.decide(SF.ASoonestReset{}, active, as, us, now, cfg, st, mem), as, active, us, now, D.cfg.models(cfg)), S.not_active(A.decide(SF.ASoonestReset{}, active, as, us, now, cfg, st, mem), active), l_dec_good(SF.ASoonestReset{}, active, as, us, now, cfg, st, mem, {==}))
    case SF.ASticky{}:
      and_r(SA.landed_ok(A.decide(SF.ASticky{}, active, as, us, now, cfg, st, mem), as, active, us, now, D.cfg.models(cfg)), S.not_active(A.decide(SF.ASticky{}, active, as, us, now, cfg, st, mem), active), l_dec_good(SF.ASticky{}, active, as, us, now, cfg, st, mem, {==}))
    case SF.ADrainFirst{}:
      and_r(SA.landed_ok(A.decide(SF.ADrainFirst{}, active, as, us, now, cfg, st, mem), as, active, us, now, D.cfg.models(cfg)), S.not_active(A.decide(SF.ADrainFirst{}, active, as, us, now, cfg, st, mem), active), l_dec_good(SF.ADrainFirst{}, active, as, us, now, cfg, st, mem, {==}))

def Laws.profile_switch_not_active(algo, active, accounts, usage, now, cfg, st, mem):
  l_dec_na(algo, active, accounts, usage, now, cfg, st, mem)

def l_dec_unknown(+algo: SF.Algo, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem, +hah: {U.head.row(U.usage.of(active, us), now, D.cfg.models(cfg)) == None{} : Maybe<&2, Nat>}, +hf: {S.failover_ready(active, us, now, cfg, mem) == False{} : Bool}) -> {S.is_switch(A.decide(algo, active, as, us, now, cfg, st, mem)) == False{} : Bool}:
  match algo:
    case SF.ABest{}:
      l2_acct(U.account.of(active, as), active, as, us, now, cfg, st, mem, hah, hf)
    case SF.ARoundRobin{}:
      l3_core(SF.ARoundRobin{}, A.VAuto{}, active, as, us, now, cfg, st, mem, hah)
    case SF.ASoonestReset{}:
      l3_core(SF.ASoonestReset{}, A.VAuto{}, active, as, us, now, cfg, st, mem, hah)
    case SF.ASticky{}:
      l3_core(SF.ASticky{}, A.VAuto{}, active, as, us, now, cfg, st, mem, hah)
    case SF.ADrainFirst{}:
      l3_core(SF.ADrainFirst{}, A.VAuto{}, active, as, us, now, cfg, st, mem, hah)

def Laws.profile_unknown_no_switch(algo, active, accounts, usage, now, cfg, st, mem, unknown, no_failover):
  l_dec_unknown(algo, active, accounts, usage, now, cfg, st, mem, unknown, no_failover)

def Laws.profile_rotate_target_safe(algo, active, accounts, usage, now, cfg):
  and_l(SA.landed_ok(A.rotate(algo, active, accounts, usage, now, cfg), accounts, active, usage, now, D.cfg.models(cfg)), S.not_active(A.rotate(algo, active, accounts, usage, now, cfg), active),
    l_core(algo, A.VRotate{}, active, accounts, usage, now, cfg, T.fresh_state(), T.fresh_mem()))

def Laws.profile_rotate_not_active(algo, active, accounts, usage, now, cfg):
  and_r(SA.landed_ok(A.rotate(algo, active, accounts, usage, now, cfg), accounts, active, usage, now, D.cfg.models(cfg)), S.not_active(A.rotate(algo, active, accounts, usage, now, cfg), active),
    l_core(algo, A.VRotate{}, active, accounts, usage, now, cfg, T.fresh_state(), T.fresh_mem()))

def Laws.profile_rotate_unknown_no_switch(algo, active, accounts, usage, now, cfg, unknown):
  l3_core(algo, A.VRotate{}, active, accounts, usage, now, cfg, T.fresh_state(), T.fresh_mem(), unknown)
