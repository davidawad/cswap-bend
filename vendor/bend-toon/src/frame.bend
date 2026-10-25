import Base
import ./json.bend as J
import ./split.bend as S
import ./head.bend as Hd

# The decoder's explicit stack of open containers (an object, a list array or
# a tabular array), with the operations that grow, close and unwind it.
#
# `depth` is the depth of a frame's child lines. `att` says how the finished
# value attaches to the frame beneath it. Children are kept in reverse order
# and reversed when the frame closes.

type Att is Data:
  AKey{k: String}
  AItem{}
  ARoot{}

type Fr is Data:
  FObj{depth: U32, att: Att, fs: J.Json}
  FLst{depth: U32, att: Att, n: U32, c: U32, xs: J.Json}
  FTab{depth: U32, att: Att, n: U32, c: U32, d: U32, ks: List<&2, String>, xs: J.Json}

# The stack (top first), the finished root once there is one, and the shallowest
# array that had a blank line inside it since the last content line.
type St is Data:
  St{stk: List<&2, Fr>, root: Maybe<&2, J.Json>, bmin: U32}

def stk.of(+st: St) -> List<&2, Fr>:
  match st:
    case St{stk, root, bmin}:
      stk

def bmin.of(+st: St) -> U32:
  match st:
    case St{stk, root, bmin}:
      bmin

def fr.depth(+f: Fr) -> U32:
  match f:
    case FObj{d, a, fs}:
      d
    case FLst{d, a, n, c, xs}:
      d
    case FTab{d, a, n, c, dl, ks, xs}:
      d

def fr.att(+f: Fr) -> Att:
  match f:
    case FObj{d, a, fs}:
      a
    case FLst{d, a, n, c, xs}:
      a
    case FTab{d, a, n, c, dl, ks, xs}:
      a

# ---- chains --------------------------------------------------------------------------

def rev.items(+xs: J.Json, +acc: J.Json) -> J.Json:
  match xs:
    case J.JCons{h, t}:
      rev.items(t, J.JCons{h, acc})
    case _:
      acc

def rev.fields(+fs: J.Json, +acc: J.Json) -> J.Json:
  match fs:
    case J.JField{k, v, t}:
      rev.fields(t, J.JField{k, v, acc})
    case _:
      acc

def has_key(+k: String, +fs: J.Json) -> Bool:
  match fs:
    case J.JField{k2, v, t}:
      Hd.keq(k, k2) || has_key(k, t)
    case _:
      False{}

def set.pick(+hit: Bool, +k: String, +v: J.Json, +old: J.Json, +rest: J.Json, +t: J.Json) -> J.Json:
  match hit:
    case True{}:
      J.JField{k, v, t}
    case False{}:
      J.JField{k, old, rest}

# Replace the value under `k`, keeping its place.
def set(+k: String, +v: J.Json, +fs: J.Json) -> J.Json:
  match fs:
    case J.JField{k2, old, t}:
      set.pick(Hd.keq(k, k2), k2, v, old, set(k, v, t), t)
    case _:
      fs

def add.if(+dup: Bool, +strict: Bool, +k: String, +v: J.Json, +fs: J.Json) -> Result<&2, &2, String, J.Json>:
  match dup strict:
    case False{} _:
      Done{J.JField{k, v, fs}}
    case True{} True{}:
      Fail{"duplicate key"}
    case True{} False{}:
      Done{set(k, v, fs)}

# Add a field to a reversed field chain. A repeated key is an error in strict
# mode; otherwise the later value replaces the earlier (section 14.4).
def add_field(+strict: Bool, +fs: J.Json, +k: String, +v: J.Json) -> Result<&2, &2, String, J.Json>:
  add.if(has_key(k, fs), strict, k, v, fs)

# ---- closing -------------------------------------------------------------------------

def count.ok(+strict: Bool, +n: U32, +c: U32) -> Bool:
  Bool.not(strict) || U32.is_eq(n, c)

def fin.arr(+ok: Bool, +xs: J.Json) -> Result<&2, &2, String, J.Json>:
  match ok:
    case True{}:
      Done{J.JArr{rev.items(xs, J.JNil{})}}
    case False{}:
      Fail{"array length does not match its header"}

def finish(+f: Fr, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match f:
    case FObj{d, a, fs}:
      Done{J.JObj{rev.fields(fs, J.JNil{})}}
    case FLst{d, a, n, c, xs}:
      fin.arr(count.ok(strict, n, c), xs)
    case FTab{d, a, n, c, dl, ks, xs}:
      fin.arr(count.ok(strict, n, c), xs)

def put.field.done(+r: Result<&2, &2, String, J.Json>, +d: U32, +a: Att, +rest: List<&2, Fr>, +root: Maybe<&2, J.Json>, +bmin: U32) -> Result<&2, &2, String, St>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{fs2}:
      Done{St{Con{FObj{d, a, fs2}, rest}, root, bmin}}

def put.field(+strict: Bool, +d: U32, +a: Att, +fs: J.Json, +k: String, +v: J.Json, +rest: List<&2, Fr>, +root: Maybe<&2, J.Json>, +bmin: U32) -> Result<&2, &2, String, St>:
  put.field.done(add_field(strict, fs, k, v), d, a, rest, root, bmin)

# Attach a finished value to the frame beneath, or make it the root.
def attach.top(+top: Fr, +att: Att, +v: J.Json, +rest: List<&2, Fr>, +root: Maybe<&2, J.Json>, +strict: Bool, +bmin: U32) -> Result<&2, &2, String, St>:
  match top att:
    case FObj{d, a, fs} AKey{k}:
      put.field(strict, d, a, fs, k, v, rest, root, bmin)
    case FLst{d, a, n, c, xs} AItem{}:
      Done{St{Con{FLst{d, a, n, c, J.JCons{v, xs}}, rest}, root, bmin}}
    case _ _:
      Fail{"misplaced value"}

def attach(+att: Att, +v: J.Json, +stk: List<&2, Fr>, +root: Maybe<&2, J.Json>, +strict: Bool, +bmin: U32) -> Result<&2, &2, String, St>:
  match stk:
    case Nil{}:
      Done{St{Nil{}, Some{v}, bmin}}
    case Con{top, rest}:
      attach.top(top, att, v, rest, root, strict, bmin)

def close.go(+r: Result<&2, &2, String, J.Json>, +att: Att, +rest: List<&2, Fr>, +root: Maybe<&2, J.Json>, +strict: Bool, +bmin: U32) -> Result<&2, &2, String, St>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{v}:
      attach(att, v, rest, root, strict, bmin)

# Close the top frame into the one beneath it.
def close(+st: St, +strict: Bool) -> Result<&2, &2, String, St>:
  match st:
    case St{Con{top, rest}, root, bmin}:
      close.go(finish(top, strict), fr.att(top), rest, root, strict, bmin)
    case _:
      Done{st}

def close.if(+b: Bool, +st: St, +strict: Bool) -> Result<&2, &2, String, St>:
  match b:
    case True{}:
      close(st, strict)
    case False{}:
      Done{st}

# Is the top frame at or below depth `t`?
def should_pop(+stk: List<&2, Fr>, +t: U32) -> Bool:
  match stk:
    case Con{top, rest}:
      U32.is_ge(fr.depth(top), t)
    case Nil{}:
      False{}

# Close every frame whose child depth is at least `t`. `fuel` is the stack
# height, enough for every frame to close.
def pop(+fuel: Nat, +sr: Result<&2, &2, String, St>, +t: U32, +strict: Bool) -> Result<&2, &2, String, St>:
  match fuel sr:
    case 0n _:
      sr
    case 1n+p Fail{e}:
      Fail{e}
    case 1n+p Done{st}:
      pop(p, close.if(should_pop(stk.of(st), t), st, strict), t, strict)

# ---- blank lines ---------------------------------------------------------------------

def arr.depth.if(+empty: Bool, +d: U32) -> U32:
  match empty:
    case True{}:
      S.none()
    case False{}:
      d

def arr.depth(+f: Fr) -> U32:
  match f:
    case FLst{d, a, n, c, xs}:
      arr.depth.if(U32.is_zero(c), d)
    case FTab{d, a, n, c, dl, ks, xs}:
      arr.depth.if(U32.is_zero(c), d)
    case _:
      S.none()

# Shallowest array frame that already has an item or row.
def arr.min(+stk: List<&2, Fr>) -> U32:
  match stk:
    case Nil{}:
      S.none()
    case Con{top, rest}:
      U32.min(arr.depth(top), arr.min(rest))

# A blank line: remember the shallowest array it falls inside.
def blank.note(+st: St) -> St:
  match st:
    case St{stk, root, bmin}:
      St{stk, root, U32.min(bmin, arr.min(stk))}

def blank.if(+bad: Bool, +st: St) -> Result<&2, &2, String, St>:
  match bad:
    case True{}:
      Fail{"blank line inside an array"}
    case False{}:
      match st:
        case St{stk, root, bmin}:
          Done{St{stk, root, S.none()}}

# A content line at depth `d` after a blank: it is inside the array when the
# array's child depth is at most `d`.
def blank.check(+st: St, +d: U32, +strict: Bool) -> Result<&2, &2, String, St>:
  blank.if(strict && U32.is_le(bmin.of(st), d), st)
