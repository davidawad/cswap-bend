import Base
import ./json.bend as J
import ./split.bend as S
import ./head.bend as Hd
import ./fold.bend as K

# Path expansion (spec section 13.4, decoder, mode "safe"): an unquoted key
# `a.b.c` whose segments are all identifiers becomes the nested object
# `{a: {b: {c: ..}}}`, and overlapping paths merge. A quoted key is literal.
#
# It is a pass over the decoded value, as in the reference decoder. Objects
# arrive with their quoted keys marked (head.bend), arrays and values are
# expanded first, then each field is flattened to leaf assignments
# (path, leaf) which are inserted in document order into the object being
# built. A conflict (a leaf where an object must be, an object where a leaf
# is, two leaves at one path) is an error in strict mode and last-write-wins
# otherwise.

# ---- the path of a key -----------------------------------------------------------------

def all_ident(+ks: List<&2, String>) -> Bool:
  match ks:
    case Nil{}:
      True{}
    case Con{k, t}:
      K.ident(k) && all_ident(t)

# A bare key with a dot and only identifier segments expands.
def eligible(+k: String) -> Bool:
  K.has_dot(k) && all_ident(S.split(k, 46))

def segs.bare(+e: Bool, +k: String) -> List<&2, String>:
  match e:
    case True{}:
      S.split(k, 46)
    case False{}:
      Con{k, Nil{}}

def segs.pick(+quoted: Bool, +k: String) -> List<&2, String>:
  match quoted:
    case True{}:
      Con{Hd.unmark(k), Nil{}}
    case False{}:
      segs.bare(eligible(k), k)

def segs_of(+k: String) -> List<&2, String>:
  segs.pick(Hd.marked(k), k)

def snoc(+ks: List<&2, String>, +k: String) -> List<&2, String>:
  match ks:
    case Nil{}:
      Con{k, Nil{}}
    case Con{h, t}:
      Con{h, snoc(t, k)}

# ---- inserting a leaf at a path ----------------------------------------------------------

# The nested objects for a path ending in `leaf`.
def build(+segs: List<&2, String>, +leaf: J.Json) -> J.Json:
  match segs:
    case Nil{}:
      leaf
    case Con{s, rest}:
      J.JObj{J.JField{s, build(rest, leaf), J.JNil{}}}

def conflict(+strict: Bool, +segs: List<&2, String>, +leaf: J.Json) -> Result<&2, &2, String, J.Json>:
  match strict:
    case True{}:
      Fail{"expansion conflict"}
    case False{}:
      Done{build(segs, leaf)}

def empty_obj(+j: J.Json) -> Bool:
  match j:
    case J.JObj{J.JNil{}}:
      True{}
    case _:
      False{}

# An existing object met by the end of a path: only an empty object leaf agrees.
def same.pick(+ok: Bool, +strict: Bool, +e: J.Json, +leaf: J.Json) -> Result<&2, &2, String, J.Json>:
  match ok:
    case True{}:
      Done{e}
    case False{}:
      conflict(strict, Nil{}, leaf)

def wrap.obj(+r: Result<&2, &2, String, J.Json>) -> Result<&2, &2, String, J.Json>:
  match r:
    case Done{fs}:
      Done{J.JObj{fs}}
    case Fail{e}:
      Fail{e}

# A cell of a field chain: replace the value when the key is the path's head,
# else look further along the chain.
def cell(+hit: Bool, +k: String, +ev: J.Json, +t: J.Json, +rv: Result<&2, &2, String, J.Json>, +rt: Result<&2, &2, String, J.Json>) -> Result<&2, &2, String, J.Json>:
  match hit rv rt:
    case True{} Done{v} _:
      Done{J.JField{k, v, t}}
    case True{} Fail{e} _:
      Fail{e}
    case False{} _ Done{t2}:
      Done{J.JField{k, ev, t2}}
    case False{} _ Fail{e}:
      Fail{e}

# Insert `leaf` at `segs` inside `e`: an object value, a field chain, or
# whatever sits at the path (then it conflicts unless the path has ended).
def ins(+e: J.Json, +segs: List<&2, String>, +leaf: J.Json, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match e segs:
    case J.JObj{efs} Nil{}:
      same.pick(empty_obj(leaf), strict, e, leaf)
    case J.JObj{efs} Con{s, rest}:
      wrap.obj(ins(efs, segs, leaf, strict))
    case J.JField{k, ev, t} Con{s, rest}:
      cell(Hd.keq(k, s), k, ev, t, ins(ev, rest, leaf, strict), ins(t, segs, leaf, strict))
    case J.JNil{} Con{s, rest}:
      Done{J.JField{s, build(rest, leaf), J.JNil{}}}
    case J.JField{k, ev, t} Nil{}:
      Done{e}
    case J.JNil{} Nil{}:
      Done{e}
    case _ _:
      conflict(strict, segs, leaf)

def ins.r(+acc: Result<&2, &2, String, J.Json>, +segs: List<&2, String>, +leaf: J.Json, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match acc:
    case Done{a}:
      ins(a, segs, leaf, strict)
    case Fail{e}:
      Fail{e}

# Flatten an expanded value at `segs` into leaf assignments, inserted in order.
def fl.pick(+empty: Bool, +j: J.Json, +segs: List<&2, String>, +acc: Result<&2, &2, String, J.Json>, +strict: Bool, +r: Result<&2, &2, String, J.Json>) -> Result<&2, &2, String, J.Json>:
  match empty:
    case True{}:
      ins.r(acc, segs, j, strict)
    case False{}:
      r

def fl(+j: J.Json, +segs: List<&2, String>, +acc: Result<&2, &2, String, J.Json>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match j:
    case J.JObj{fs}:
      fl.pick(empty_obj(j), j, segs, acc, strict, fl(fs, segs, acc, strict))
    case J.JField{k, v, t}:
      fl(t, segs, fl(v, snoc(segs, k), acc, strict), strict)
    case J.JNil{}:
      acc
    case _:
      ins.r(acc, segs, j, strict)

# ---- the pass ----------------------------------------------------------------------------

def init() -> Result<&2, &2, String, J.Json>:
  Done{J.JObj{J.JNil{}}}

def fl.r(+vr: Result<&2, &2, String, J.Json>, +segs: List<&2, String>, +acc: Result<&2, &2, String, J.Json>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match vr:
    case Done{v}:
      fl(v, segs, acc, strict)
    case Fail{e}:
      Fail{e}

def arr.r(+r: Result<&2, &2, String, J.Json>) -> Result<&2, &2, String, J.Json>:
  match r:
    case Done{items}:
      Done{J.JArr{items}}
    case Fail{e}:
      Fail{e}

def cons.r(+h: Result<&2, &2, String, J.Json>, +t: Result<&2, &2, String, J.Json>) -> Result<&2, &2, String, J.Json>:
  match h t:
    case Done{x} Done{y}:
      Done{J.JCons{x, y}}
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

def nil() -> Result<&2, &2, String, J.Json>:
  Done{J.JNil{}}

# `acc` is the object under construction while walking a field chain, and
# Done{JNil} while walking an array's elements.
def ex(+j: J.Json, +acc: Result<&2, &2, String, J.Json>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match j:
    case J.JObj{fs}:
      ex(fs, init(), strict)
    case J.JField{k, v, t}:
      ex(t, fl.r(ex(v, init(), strict), segs_of(k), acc, strict), strict)
    case J.JNil{}:
      acc
    case J.JArr{items}:
      arr.r(ex(items, nil(), strict))
    case J.JCons{h, t}:
      cons.r(ex(h, init(), strict), ex(t, nil(), strict))
    case _:
      Done{j}

# Remove the quoted-key markers (path expansion off).
def strip(+j: J.Json) -> J.Json:
  match j:
    case J.JObj{x}:
      J.JObj{strip(x)}
    case J.JArr{x}:
      J.JArr{strip(x)}
    case J.JCons{h, t}:
      J.JCons{strip(h), strip(t)}
    case J.JField{k, v, t}:
      J.JField{Hd.unmark(k), strip(v), strip(t)}
    case _:
      j

def expand(+j: J.Json, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  ex(j, init(), strict)
