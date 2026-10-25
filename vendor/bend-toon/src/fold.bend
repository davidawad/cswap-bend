import Base
import ./json.bend as J
import ./head.bend as Hd

# Key folding (spec section 13.4, encoder, mode "safe"): a chain of objects
# with one key each collapses into a dotted key, `{a: {b: {c: 1}}}` into
# `a.b.c: 1`.
#
# It is a rewrite of the value before encoding. Along objects only (arrays are
# leaves of a chain, and objects inside arrays are not folded), a key K1 whose
# value is an object with the single key K2, and so on, folds to `K1.K2...Kd`
# when every segment matches `^[A-Za-z_][A-Za-z0-9_]*$`, d = min(L, flatten
# depth) is at least 2, and the folded key collides with neither a sibling key
# nor (at root) a literal dotted root key.

# A chain: how many segments, the folded key, the value after the last
# segment, and whether every segment is an identifier.
type Ci is Data:
  Ci{n: U32, key: String, tail: J.Json, ok: Bool}

# What to do with one field: the key to write, the value after any folding,
# that value's fields, their sibling keys, the budget and the path to carry
# into them.
type Plan is Data:
  Plan{key: String, vt: J.Json, fs2: J.Json, sibs2: List<&2, String>, nb: U32, np: String}

def alnum(+c: Char) -> Bool:
  Char.is_alpha(c) || Char.is_digit(c) || Char.is_eq(c, '_')

def ident_tail(+s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      alnum(c) && ident_tail(t)

# An IdentifierSegment.
def ident(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      (Char.is_alpha(c) || Char.is_eq(c, '_')) && ident_tail(t)

def member(+k: String, +ks: List<&2, String>) -> Bool:
  match ks:
    case Nil{}:
      False{}
    case Con{h, t}:
      String.eq(k, h) || member(k, t)

def keys(+fs: J.Json) -> List<&2, String>:
  match fs:
    case J.JField{k, v, t}:
      Con{k, keys(t)}
    case _:
      Nil{}

def has_dot(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      Char.is_eq(c, '.') || has_dot(t)

def dotted.pick(+hit: Bool, +k: String, +rest: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      Con{k, rest}
    case False{}:
      rest

# Keys that hold a dot.
def dotted(+ks: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}:
      Nil{}
    case Con{k, t}:
      dotted.pick(has_dot(k), k, dotted(t))

# Nodes in a value: the fuel for the fold.
def size(+j: J.Json) -> Nat:
  match j:
    case J.JArr{x}:
      1n+size(x)
    case J.JObj{x}:
      1n+size(x)
    case J.JCons{h, t}:
      1n+Nat.add(size(h), size(t))
    case J.JField{k, v, t}:
      1n+Nat.add(size(v), size(t))
    case _:
      1n

def chain.step(+go: Bool, +v: J.Json, +n: U32, +key: String, +ok: Bool, +r: Ci) -> Ci:
  match go:
    case True{}:
      r
    case False{}:
      Ci{n, key, v, ok}

# Walk single-key objects from `v`, at most `budget` segments in all.
def chain(+v: J.Json, +n: U32, +budget: U32, +key: String, +ok: Bool) -> Ci:
  match v:
    case J.JObj{J.JField{k2, v2, J.JNil{}}}:
      chain.step(U32.is_lt(n, budget), v, n, key, ok, chain(v2, (n + 1 : U32), budget, key ++ "." ++ k2, ok && ident(k2)))
    case _:
      Ci{n, key, v, ok}

def path(+prefix: String, +key: String) -> String:
  match prefix:
    case SNil{}:
      key
    case _:
      prefix ++ "." ++ key

def ci.n(+c: Ci) -> U32:
  match c:
    case Ci{n, key, tail, ok}:
      n

def ci.key(+c: Ci) -> String:
  match c:
    case Ci{n, key, tail, ok}:
      key

def ci.tail(+c: Ci) -> J.Json:
  match c:
    case Ci{n, key, tail, ok}:
      tail

def ci.ok(+c: Ci) -> Bool:
  match c:
    case Ci{n, key, tail, ok}:
      ok

# Does this field fold?
def foldable(+c: Ci, +sibs: List<&2, String>, +prefix: String, +rl: List<&2, String>) -> Bool:
  U32.is_ge(ci.n(c), 2) && ci.ok(c) && Bool.not(member(ci.key(c), sibs)) && Bool.not(member(path(prefix, ci.key(c)), rl))

def pick.s(+b: Bool, +x: String, +y: String) -> String:
  match b:
    case True{}:
      x
    case False{}:
      y

def pick.j(+b: Bool, +x: J.Json, +y: J.Json) -> J.Json:
  match b:
    case True{}:
      x
    case False{}:
      y

def pick.u(+b: Bool, +x: U32, +y: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      y

# The fields of an object value, or none.
def fields.of(+v: J.Json) -> J.Json:
  match v:
    case J.JObj{fs}:
      fs
    case _:
      J.JNil{}

# An object value with its folded fields, other values unchanged.
def rebuild(+v: J.Json, +inner: J.Json) -> J.Json:
  match v:
    case J.JObj{fs}:
      J.JObj{inner}
    case _:
      v

def plan.go(+c: Ci, +f: Bool, +k: String, +v: J.Json, +budget: U32, +prefix: String) -> Plan:
  +nk : String = pick.s(f, ci.key(c), k)
  +vt : J.Json = pick.j(f, ci.tail(c), v)
  Plan{nk, vt, fields.of(vt), keys(fields.of(vt)), pick.u(f, (budget - ci.n(c) : U32), budget), path(prefix, nk)}

def plan(+k: String, +v: J.Json, +sibs: List<&2, String>, +budget: U32, +prefix: String, +rl: List<&2, String>) -> Plan:
  +c : Ci = chain(v, 1, budget, k, ident(k))
  plan.go(c, foldable(c, sibs, prefix, rl), k, v, budget, prefix)

def plan.fs(+pl: Plan) -> J.Json:
  match pl:
    case Plan{key, vt, fs2, sibs2, nb, np}:
      fs2

def plan.sibs(+pl: Plan) -> List<&2, String>:
  match pl:
    case Plan{key, vt, fs2, sibs2, nb, np}:
      sibs2

def plan.nb(+pl: Plan) -> U32:
  match pl:
    case Plan{key, vt, fs2, sibs2, nb, np}:
      nb

def plan.np(+pl: Plan) -> String:
  match pl:
    case Plan{key, vt, fs2, sibs2, nb, np}:
      np

# The field with its folded inside, followed by the folded rest.
def field.mk(+pl: Plan, +inner: J.Json, +rest: J.Json) -> J.Json:
  match pl:
    case Plan{key, vt, fs2, sibs2, nb, np}:
      J.JField{key, rebuild(vt, inner), rest}

# `fs` is a field chain. `budget` is the segments still allowed, `prefix` the
# dotted path of the object so far, `rl` the literal dotted keys at root.
def foldf(+fuel: Nat, +fs: J.Json, +sibs: List<&2, String>, +budget: U32, +prefix: String, +rl: List<&2, String>) -> J.Json:
  match fuel fs:
    case 0n _:
      fs
    case 1n+p J.JField{k, v, t}:
      +pl : Plan = plan(k, v, sibs, budget, prefix, rl)
      field.mk(pl, foldf(p, plan.fs(pl), plan.sibs(pl), plan.nb(pl), plan.np(pl), rl), foldf(p, t, sibs, budget, prefix, rl))
    case 1n+p _:
      fs

def fold.obj(+j: J.Json, +fs: J.Json, +budget: U32) -> J.Json:
  J.JObj{foldf(size(j), fs, keys(fs), budget, SNil{}, dotted(keys(fs)))}

def fold.if(+off: Bool, +j: J.Json, +depth: U32) -> J.Json:
  match off:
    case True{}:
      j
    case False{}:
      match j:
        case J.JObj{fs}:
          fold.obj(j, fs, depth)
        case _:
          j

# Fold keys of a value with at most `depth` segments per dotted key; a depth
# below 2 folds nothing.
def fold(+j: J.Json, +depth: U32) -> J.Json:
  fold.if(U32.is_lt(depth, 2), j, depth)
