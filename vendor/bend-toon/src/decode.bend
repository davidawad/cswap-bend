import Base
import ./json.bend as J
import ./split.bend as S
import ./prim.bend as P
import ./hdr.bend as H
import ./entry.bend as E
import ./dline.bend as D
import ./frame.bend as F
import ./step.bend as T
import ./expand.bend as X
import ./head.bend as Hd

# Decoder (spec sections 4, 5, 12 to 14): lines to a Json value.

# Decoder options: spaces per indent level, strict mode, and path expansion
# (section 13.4: unquoted dotted keys become nested objects).
type DOpts is Data:
  DOpts{indent: U32, strict: Bool, expand: Bool}

def ddefaults() -> DOpts:
  DOpts{2, True{}, False{}}

# Apply every line in order, stopping at the first error.
def fold(+ls: List<&2, D.DL>, +sr: Result<&2, &2, String, F.St>, +strict: Bool) -> Result<&2, &2, String, F.St>:
  match ls sr:
    case Nil{} _:
      sr
    case Con{l, t} Done{st}:
      fold(t, T.step(l, st, strict), strict)
    case Con{l, t} Fail{e}:
      Fail{e}

def root.value(+r: Result<&2, &2, String, F.St>) -> Result<&2, &2, String, J.Json>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{F.St{stk, Some{v}, bmin}}:
      Done{v}
    case Done{st}:
      Fail{"no value"}

# The stack height: enough steps to close every frame.
def fuel(+r: Result<&2, &2, String, F.St>) -> Nat:
  match r:
    case Done{F.St{stk, root, bmin}}:
      List.length(&2, F.Fr, stk)
    case Fail{e}:
      0n

# Close what is still open and take the root.
def finish(+r: Result<&2, &2, String, F.St>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  root.value(F.pop(fuel(r), r, 0, strict))

def all_blank(+ls: List<&2, D.DL>) -> Bool:
  match ls:
    case Nil{}:
      True{}
    case Con{D.DL{no, depth, text, blank}, t}:
      blank && all_blank(t)

def skip_blank(+ls: List<&2, D.DL>) -> List<&2, D.DL>:
  match ls:
    case Con{D.DL{no, depth, text, True{}}, t}:
      skip_blank(t)
    case _:
      ls

def init(+stk: List<&2, F.Fr>, +root: Maybe<&2, J.Json>) -> Result<&2, &2, String, F.St>:
  Done{F.St{stk, root, S.none()}}

def object.root() -> Result<&2, &2, String, F.St>:
  init(Con{F.FObj{0, F.ARoot{}, J.JNil{}}, Nil{}}, None{})

# The root is an array: its header started a value or an open frame.
def array.root(+r: Result<&2, &2, String, T.Start>) -> Result<&2, &2, String, F.St>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{T.SVal{v}}:
      init(Nil{}, Some{v})
    case Done{T.SOpen{fr}}:
      init(Con{fr, Nil{}}, None{})

def run.object(+ls: List<&2, D.DL>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  finish(fold(ls, object.root(), strict), strict)

def run.array(+ls: List<&2, D.DL>, +r: Result<&2, &2, String, T.Start>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  finish(fold(ls, array.root(r), strict), strict)

# A one-line document that is no entry is a primitive.
def single.pick(+r: Result<&2, &2, String, E.Ent>, +text: String, +ls: List<&2, D.DL>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match r:
    case Done{E.ENot{}}:
      P.parse(text)
    case _:
      run.object(ls, strict)

def single.if(+empty: Bool, +text: String, +ls: List<&2, D.DL>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match empty:
    case True{}:
      Done{J.JArr{J.JNil{}}}
    case False{}:
      single.pick(E.parse(strict, text), text, ls, strict)

def single(+text: String, +ls: List<&2, D.DL>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  single.if(String.eq(text, "[]"), text, ls, strict)

# Section 5 root form discovery, after the header of a root array failed.
def root.other(+one: Bool, +text: String, +ls: List<&2, D.DL>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match one:
    case True{}:
      single(text, ls, strict)
    case False{}:
      run.object(ls, strict)

def root.hdr(+r: Result<&2, &2, String, H.Hdr>, +one: Bool, +text: String, +all: List<&2, D.DL>, +rest: List<&2, D.DL>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match r:
    case Done{h}:
      run.array(rest, T.arr_start(F.ARoot{}, 1, h, strict), strict)
    case Fail{e}:
      root.other(one, text, all, strict)

def header.try.pick(+root: Bool, +text: String) -> Result<&2, &2, String, H.Hdr>:
  match root:
    case True{}:
      H.parse(text)
    case False{}:
      Fail{"not a root header"}

def header.try(+depth: U32, +text: String) -> Result<&2, &2, String, H.Hdr>:
  header.try.pick(U32.is_zero(depth) && Hd.lead(text, 91), text)

def start.first(+l: D.DL, +rest: List<&2, D.DL>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match l:
    case D.DL{no, depth, text, blank}:
      root.hdr(header.try(depth, text), all_blank(rest), text, Con{l, rest}, rest, strict)

def start.skipped(+ls: List<&2, D.DL>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match ls:
    case Nil{}:
      Done{J.JObj{J.JNil{}}}
    case Con{l, rest}:
      start.first(l, rest, strict)

def start(+ls: List<&2, D.DL>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  start.skipped(skip_blank(ls), strict)

def run(+r: Result<&2, &2, String, List<&2, D.DL>>, +strict: Bool) -> Result<&2, &2, String, J.Json>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{ls}:
      start(ls, strict)

def post.pick(+expand: Bool, +strict: Bool, +v: J.Json) -> Result<&2, &2, String, J.Json>:
  match expand:
    case True{}:
      X.expand(v, strict)
    case False{}:
      Done{X.strip(v)}

# Quoted-key markers come off; with path expansion the dotted keys unfold.
def post(+expand: Bool, +strict: Bool, +r: Result<&2, &2, String, J.Json>) -> Result<&2, &2, String, J.Json>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{v}:
      post.pick(expand, strict, v)

# Decode TOON text.
def decode(+src: String, +o: DOpts) -> Result<&2, &2, String, J.Json>:
  match o:
    case DOpts{indent, strict, expand}:
      post(expand, strict, run(D.prep(src, indent, strict), strict))
