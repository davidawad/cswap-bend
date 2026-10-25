import Base
import ./json.bend as J
import ./split.bend as S
import ./prim.bend as P
import ./hdr.bend as H
import ./entry.bend as E
import ./dline.bend as D
import ./frame.bend as F
import ./head.bend as Hd

# One content line applied to the decoder state (spec sections 8 to 10).

type Start is Data:
  SVal{v: J.Json}
  SOpen{fr: F.Fr}

# What follows a list hyphen.
type Item is Data:
  IBad{}
  IEmpty{}
  IText{t: String}

def count(+xs: J.Json) -> U32:
  match xs:
    case J.JCons{h, t}:
      (1 + count(t) : U32)
    case _:
      0

def list.len(+ks: List<&2, String>) -> U32:
  match ks:
    case Nil{}:
      0
    case Con{k, t}:
      (1 + list.len(t) : U32)

# ---- arrays after a header --------------------------------------------------------

def inline.ok(+ok: Bool, +vs: J.Json) -> Result<&2, &2, String, Start>:
  match ok:
    case True{}:
      Done{SVal{J.JArr{vs}}}
    case False{}:
      Fail{"array length does not match its header"}

def inline.done(+r: Result<&2, &2, String, J.Json>, +n: U32, +strict: Bool) -> Result<&2, &2, String, Start>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{vs}:
      inline.ok(Bool.not(strict) || U32.is_eq(count(vs), n), vs)

def inline.go(+fields: List<&2, String>, +n: U32, +d: U32, +rest: String, +strict: Bool) -> Result<&2, &2, String, Start>:
  match fields:
    case Nil{}:
      inline.done(P.values(S.split(rest, d)), n, strict)
    case Con{f, t}:
      Fail{"values after a field list"}

def block(+zero: Bool, +fields: List<&2, String>, +n: U32, +d: U32, +att: F.Att, +depth: U32) -> Result<&2, &2, String, Start>:
  match zero fields:
    case True{} _:
      Done{SVal{J.JArr{J.JNil{}}}}
    case False{} Nil{}:
      Done{SOpen{F.FLst{depth, att, n, 0, J.JNil{}}}}
    case False{} Con{f, t}:
      Done{SOpen{F.FTab{depth, att, n, 0, d, Con{f, t}, J.JNil{}}}}

def start.pick(+noinline: Bool, +n: U32, +d: U32, +fields: List<&2, String>, +rest: String, +att: F.Att, +depth: U32, +strict: Bool) -> Result<&2, &2, String, Start>:
  match noinline:
    case True{}:
      block(U32.is_zero(n), fields, n, d, att, depth)
    case False{}:
      inline.go(fields, n, d, rest, strict)

# What a header opens: a finished array (inline values or zero length) or an
# open frame whose child lines sit at `depth`.
def arr_start(+att: F.Att, +depth: U32, +h: H.Hdr, +strict: Bool) -> Result<&2, &2, String, Start>:
  match h:
    case H.Hdr{n, d, fields, rest}:
      start.pick(String.is_empty(String.trim(rest)), n, d, fields, rest, att, depth, strict)

# ---- object lines ------------------------------------------------------------------

def obj.arr(+r: Result<&2, &2, String, Start>, +k: String, +dp: U32, +a: F.Att, +fs: J.Json, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32, +strict: Bool) -> Result<&2, &2, String, F.St>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{SVal{v}}:
      F.put.field(strict, dp, a, fs, k, v, rest, root, bmin)
    case Done{SOpen{fr}}:
      Done{F.St{Con{fr, Con{F.FObj{dp, a, fs}, rest}}, root, bmin}}

# An entry applied to the object frame `FObj{dp, a, fs}` on top of `rest`.
def obj.ent(+ent: E.Ent, +dp: U32, +a: F.Att, +fs: J.Json, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32, +strict: Bool) -> Result<&2, &2, String, F.St>:
  match ent:
    case E.ENot{}:
      Fail{"missing colon after key"}
    case E.EVal{k, v}:
      F.put.field(strict, dp, a, fs, k, v, rest, root, bmin)
    case E.EOpen{k}:
      Done{F.St{Con{F.FObj{(dp + 1 : U32), F.AKey{k}, J.JNil{}}, Con{F.FObj{dp, a, fs}, rest}}, root, bmin}}
    case E.EArr{Some{k}, h}:
      obj.arr(arr_start(F.AKey{k}, (dp + 1 : U32), h, strict), k, dp, a, fs, rest, root, bmin, strict)
    case E.EArr{None{}, h}:
      Fail{"array header without a key"}

def obj.line(+r: Result<&2, &2, String, E.Ent>, +dp: U32, +a: F.Att, +fs: J.Json, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32, +strict: Bool) -> Result<&2, &2, String, F.St>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{ent}:
      obj.ent(ent, dp, a, fs, rest, root, bmin, strict)

# ---- list lines --------------------------------------------------------------------

def hyphen.pick(+bare: Bool, +spaced: Bool, +text: String) -> Item:
  match bare spaced:
    case True{} _:
      IEmpty{}
    case False{} True{}:
      IText{String.trim(Hd.drop(Hd.drop(text)))}
    case False{} False{}:
      IBad{}

def hyphen(+text: String) -> Item:
  hyphen.pick(String.eq(text, "-"), Hd.lead2(text, 45, 32), text)

def lst.push(+v: J.Json, +dp: U32, +a: F.Att, +n: U32, +c: U32, +xs: J.Json, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32) -> Result<&2, &2, String, F.St>:
  Done{F.St{Con{F.FLst{dp, a, n, (c + 1 : U32), J.JCons{v, xs}}, rest}, root, bmin}}

def item.prim(+r: Result<&2, &2, String, J.Json>, +dp: U32, +a: F.Att, +n: U32, +c: U32, +xs: J.Json, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32) -> Result<&2, &2, String, F.St>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{v}:
      lst.push(v, dp, a, n, c, xs, rest, root, bmin)

def item.arr(+r: Result<&2, &2, String, Start>, +dp: U32, +a: F.Att, +n: U32, +c: U32, +xs: J.Json, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32) -> Result<&2, &2, String, F.St>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{SVal{v}}:
      lst.push(v, dp, a, n, c, xs, rest, root, bmin)
    case Done{SOpen{fr}}:
      Done{F.St{Con{fr, Con{F.FLst{dp, a, n, (c + 1 : U32), xs}, rest}}, root, bmin}}

# A list item whose text parsed as an entry or as nothing special.
def item.ent(+r: Result<&2, &2, String, E.Ent>, +t: String, +strict: Bool, +dp: U32, +a: F.Att, +n: U32, +c: U32, +xs: J.Json, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32) -> Result<&2, &2, String, F.St>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{E.ENot{}}:
      item.prim(P.parse(t), dp, a, n, c, xs, rest, root, bmin)
    case Done{E.EArr{None{}, h}}:
      item.arr(arr_start(F.AItem{}, (dp + 1 : U32), h, strict), dp, a, n, c, xs, rest, root, bmin)
    case Done{ent}:
      obj.ent(ent, (dp + 1 : U32), F.AItem{}, J.JNil{}, Con{F.FLst{dp, a, n, (c + 1 : U32), xs}, rest}, root, bmin, strict)

def lst.item(+it: Item, +strict: Bool, +dp: U32, +a: F.Att, +n: U32, +c: U32, +xs: J.Json, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32) -> Result<&2, &2, String, F.St>:
  match it:
    case IBad{}:
      Fail{"expected a list item"}
    case IEmpty{}:
      lst.push(J.JObj{J.JNil{}}, dp, a, n, c, xs, rest, root, bmin)
    case IText{t}:
      item.ent(E.parse(strict, t), t, strict, dp, a, n, c, xs, rest, root, bmin)

# ---- tabular rows ------------------------------------------------------------------

def row.like.go(+di: U32, +ci: U32) -> Bool:
  U32.is_eq(ci, S.none()) || (Bool.not(U32.is_eq(di, S.none())) && U32.is_lt(di, ci))

# Section 9.3: a line with no unquoted colon, or whose first unquoted
# delimiter comes before its first unquoted colon, is a row.
def row.like(+text: String, +d: U32) -> Bool:
  row.like.go(S.find_unq(text, d, 0, 0), S.find_unq(text, 58, 0, 0))

def zip(+ks: List<&2, String>, +vs: J.Json) -> J.Json:
  match ks vs:
    case Con{k, kt} J.JCons{v, vt}:
      J.JField{k, v, zip(kt, vt)}
    case _ _:
      J.JNil{}

def row.push(+ok: Bool, +vs: J.Json, +dp: U32, +a: F.Att, +n: U32, +c: U32, +d: U32, +ks: List<&2, String>, +xs: J.Json, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32) -> Result<&2, &2, String, F.St>:
  match ok:
    case False{}:
      Fail{"row width does not match the field count"}
    case True{}:
      Done{F.St{Con{F.FTab{dp, a, n, (c + 1 : U32), d, ks, J.JCons{J.JObj{zip(ks, vs)}, xs}}, rest}, root, bmin}}

def row.add(+r: Result<&2, &2, String, J.Json>, +strict: Bool, +dp: U32, +a: F.Att, +n: U32, +c: U32, +d: U32, +ks: List<&2, String>, +xs: J.Json, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32) -> Result<&2, &2, String, F.St>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{vs}:
      row.push(Bool.not(strict) || U32.is_eq(count(vs), list.len(ks)), vs, dp, a, n, c, d, ks, xs, rest, root, bmin)

def tab.line(+isrow: Bool, +text: String, +strict: Bool, +dp: U32, +a: F.Att, +n: U32, +c: U32, +d: U32, +ks: List<&2, String>, +xs: J.Json, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32) -> Result<&2, &2, String, F.St>:
  match isrow:
    case False{}:
      Fail{"key-value line among tabular rows"}
    case True{}:
      row.add(P.values(S.split(text, d)), strict, dp, a, n, c, d, ks, xs, rest, root, bmin)

# ---- dispatch ----------------------------------------------------------------------

def top.go(+text: String, +top: F.Fr, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32, +strict: Bool) -> Result<&2, &2, String, F.St>:
  match top:
    case F.FObj{dp, a, fs}:
      obj.line(E.parse(strict, text), dp, a, fs, rest, root, bmin, strict)
    case F.FLst{dp, a, n, c, xs}:
      lst.item(hyphen(text), strict, dp, a, n, c, xs, rest, root, bmin)
    case F.FTab{dp, a, n, c, d, ks, xs}:
      tab.line(row.like(text, d), text, strict, dp, a, n, c, d, ks, xs, rest, root, bmin)

def top.line(+deep: Bool, +text: String, +top: F.Fr, +rest: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32, +strict: Bool) -> Result<&2, &2, String, F.St>:
  match deep:
    case True{}:
      Fail{"unexpected indentation"}
    case False{}:
      top.go(text, top, rest, root, bmin, strict)

def dispatch.stk(+depth: U32, +text: String, +stk: List<&2, F.Fr>, +root: Maybe<&2, J.Json>, +bmin: U32, +strict: Bool) -> Result<&2, &2, String, F.St>:
  match stk:
    case Nil{}:
      Fail{"unexpected content after the end of the document"}
    case Con{top, rest}:
      top.line(strict && U32.is_gt(depth, F.fr.depth(top)), text, top, rest, root, bmin, strict)

def dispatch(+depth: U32, +text: String, +r: Result<&2, &2, String, F.St>, +strict: Bool) -> Result<&2, &2, String, F.St>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{F.St{stk, root, bmin}}:
      dispatch.stk(depth, text, stk, root, bmin, strict)

def wrap(+no: U32, +r: Result<&2, &2, String, F.St>) -> Result<&2, &2, String, F.St>:
  match r:
    case Fail{e}:
      Fail{D.at(no, e)}
    case Done{st}:
      Done{st}

def note.blank(+strict: Bool, +st: F.St) -> F.St:
  match strict:
    case True{}:
      F.blank.note(st)
    case False{}:
      st

def content(+no: U32, +depth: U32, +text: String, +st: F.St, +strict: Bool) -> Result<&2, &2, String, F.St>:
  wrap(no, dispatch(depth, text, F.pop(List.length(&2, F.Fr, F.stk.of(st)), F.blank.check(st, depth, strict), (depth + 1 : U32), strict), strict))

def step.go(+blank: Bool, +no: U32, +depth: U32, +text: String, +st: F.St, +strict: Bool) -> Result<&2, &2, String, F.St>:
  match blank:
    case True{}:
      Done{note.blank(strict, st)}
    case False{}:
      content(no, depth, text, st, strict)

# Apply one line. A blank line only updates the blank-line bookkeeping.
def step(+l: D.DL, +st: F.St, +strict: Bool) -> Result<&2, &2, String, F.St>:
  match l:
    case D.DL{no, depth, text, blank}:
      step.go(blank, no, depth, text, st, strict)
