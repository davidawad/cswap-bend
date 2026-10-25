import Base
import ./json.bend as J
import ./num.bend as N
import ./text.bend as T
import ./rep.bend as R
import ./fold.bend as F

# Encoder (spec sections 2, 3, 6 to 12), without key folding.

type Delim is Data:
  Comma{}
  Tab{}
  Pipe{}

# Encoder options: spaces per indent level, the document delimiter, and key
# folding (section 13.4): 0 is off, n of 2 or more folds chains of single-key
# objects into dotted keys of at most n segments, 4294967295 folds whole chains.
type EOpts is Data:
  EOpts{indent: U32, delim: Delim, fold: U32}

def defaults() -> EOpts:
  EOpts{2, Comma{}, 0}

# The delimiter as a code point.
def code(+d: Delim) -> U32:
  match d:
    case Comma{}:
      44
    case Tab{}:
      9
    case Pipe{}:
      124

# What a header writes inside the brackets for this delimiter.
def sym(+d: Delim) -> String:
  match d:
    case Comma{}:
      ""
    case Tab{}:
      "\t"
    case Pipe{}:
      "|"

def delim.text(+d: Delim) -> String:
  SCon{Chr{code(d)}, SNil{}}

# ---- primitives ------------------------------------------------------------------

def bool.text(+b: Bool) -> String:
  T.sel.s(b, "true", "false")

def num.text(+m: Maybe<&2, String>) -> String:
  match m:
    case Some{t}:
      t
    case None{}:
      "null"

def is_prim(+j: J.Json) -> Bool:
  match j:
    case J.JNull{}:
      True{}
    case J.JBool{b}:
      True{}
    case J.JNum{t}:
      True{}
    case J.JStr{s}:
      True{}
    case _:
      False{}

# The text of a primitive, quoted as `d` (a code point) requires.
def prim.text(+j: J.Json, +d: U32) -> String:
  match j:
    case J.JNull{}:
      "null"
    case J.JBool{b}:
      bool.text(b)
    case J.JNum{t}:
      num.text(N.canon(t))
    case J.JStr{s}:
      T.enc.str(s, d)
    case _:
      ""

# ---- array shape -----------------------------------------------------------------

def count(+items: J.Json) -> U32:
  match items:
    case J.JCons{h, t}:
      (1 + count(t) : U32)
    case _:
      0

def all_prim(+items: J.Json) -> Bool:
  match items:
    case J.JCons{h, t}:
      is_prim(h) && all_prim(t)
    case _:
      True{}

# Primitives joined by the delimiter.
def join.prims(+items: J.Json, +d: Delim) -> String:
  match items:
    case J.JCons{h, J.JNil{}}:
      prim.text(h, code(d))
    case J.JCons{h, t}:
      prim.text(h, code(d)) ++ delim.text(d) ++ join.prims(t, d)
    case _:
      ""

def fields.len(+fs: J.Json) -> U32:
  match fs:
    case J.JField{k, v, t}:
      (1 + fields.len(t) : U32)
    case _:
      0

def fields.prim(+fs: J.Json) -> Bool:
  match fs:
    case J.JField{k, v, t}:
      is_prim(v) && fields.prim(t)
    case _:
      True{}

def field.pick(+hit: Bool, +v: J.Json, +rest: J.Json) -> J.Json:
  match hit:
    case True{}:
      v
    case False{}:
      rest

def field.get(+k: String, +fs: J.Json) -> J.Json:
  match fs:
    case J.JField{k2, v, t}:
      field.pick(String.eq(k, k2), v, field.get(k, t))
    case _:
      J.JNull{}

def has_key(+k: String, +fs: J.Json) -> Bool:
  match fs:
    case J.JField{k2, v, t}:
      String.eq(k, k2) || has_key(k, t)
    case _:
      False{}

# The keys of an object.
def keys.of(+fs: J.Json) -> List<&2, String>:
  match fs:
    case J.JField{k, v, t}:
      Con{k, keys.of(t)}
    case _:
      Nil{}

def has_all(+ks: List<&2, String>, +fs: J.Json) -> Bool:
  match ks:
    case Nil{}:
      True{}
    case Con{k, t}:
      has_key(k, fs) && has_all(t, fs)

def list.len(+ks: List<&2, String>) -> U32:
  match ks:
    case Nil{}:
      0
    case Con{k, t}:
      (1 + list.len(t) : U32)

# One element fits the header's keys: an object of primitives with exactly
# those keys.
def row.fits(+ks: List<&2, String>, +e: J.Json) -> Bool:
  match e:
    case J.JObj{fs}:
      fields.prim(fs) && U32.is_eq(fields.len(fs), list.len(ks)) && has_all(ks, fs)
    case _:
      False{}

def tab.ok(+ks: List<&2, String>, +items: J.Json) -> Bool:
  match items:
    case J.JCons{h, t}:
      row.fits(ks, h) && tab.ok(ks, t)
    case _:
      True{}

# Keys of the first element when it is a non-empty object, else none.
def first.keys(+items: J.Json) -> List<&2, String>:
  match items:
    case J.JCons{J.JObj{fs}, t}:
      keys.of(fs)
    case _:
      Nil{}

def tabular.keys(+ks: List<&2, String>, +items: J.Json) -> Bool:
  match ks:
    case Nil{}:
      False{}
    case Con{k, t}:
      tab.ok(Con{k, t}, items)

def tabular(+items: J.Json) -> Bool:
  tabular.keys(first.keys(items), items)

def fields.text(+ks: List<&2, String>, +d: Delim) -> String:
  match ks:
    case Nil{}:
      ""
    case Con{k, Nil{}}:
      T.enc.key(k)
    case Con{k, t}:
      T.enc.key(k) ++ delim.text(d) ++ fields.text(t, d)

def row.cells(+ks: List<&2, String>, +fs: J.Json, +d: Delim) -> String:
  match ks:
    case Nil{}:
      ""
    case Con{k, Nil{}}:
      prim.text(field.get(k, fs), code(d))
    case Con{k, t}:
      prim.text(field.get(k, fs), code(d)) ++ delim.text(d) ++ row.cells(t, fs, d)

def row.of(+ks: List<&2, String>, +e: J.Json, +d: Delim) -> String:
  match e:
    case J.JObj{fs}:
      row.cells(ks, fs, d)
    case _:
      ""

def rows(+ks: List<&2, String>, +items: J.Json, +d: Delim) -> List<&2, R.Ln>:
  match items:
    case J.JCons{h, t}:
      Con{R.Ln{1, row.of(ks, h, d)}, rows(ks, t, d)}
    case _:
      Nil{}

def head(+items: J.Json, +d: Delim) -> String:
  "[" ++ U32.show(count(items)) ++ sym(d) ++ "]"

def tab.rep(+items: J.Json, +d: Delim) -> R.Rep:
  R.RArr{head(items, d) ++ "{" ++ fields.text(first.keys(items), d) ++ "}:", rows(first.keys(items), items, d)}

def arr.pick(+empty: Bool, +prims: Bool, +tab: Bool, +items: J.Json, +d: Delim, +ls: R.Rep) -> R.Rep:
  match empty prims tab:
    case True{} _ _:
      R.REmpty{}
    case False{} True{} _:
      R.RArr{head(items, d) ++ ": " ++ join.prims(items, d), Nil{}}
    case False{} False{} True{}:
      tab.rep(items, d)
    case False{} False{} False{}:
      R.RArr{head(items, d) ++ ":", R.shift(R.lines.of(ls))}

# An array's rep. `elem` is true for an element of another array, where the
# tabular form is not available (section 9.4); `ls` is the encoding of the
# elements as list items.
def arr.rep(+elem: Bool, +items: J.Json, +d: Delim, +ls: R.Rep) -> R.Rep:
  arr.pick(U32.is_zero(count(items)), all_prim(items), Bool.not(elem) && tabular(items), items, d, ls)

# ---- the encoder -----------------------------------------------------------------

# One def for values, object fields and list items. `elem` says the value is an
# array element (no tabular form). `j` shrinks on every call.
def enc(j: J.Json, +elem: Bool, +d: Delim) -> R.Rep:
  match j:
    case J.JArr{+items}:
      arr.rep(elem, items, d, enc(items, True{}, d))
    case J.JObj{fields}:
      enc(fields, False{}, d)
    case J.JNil{}:
      R.RLines{Nil{}}
    case J.JCons{h, t}:
      R.RLines{R.cat(R.item(enc(h, True{}, d)), R.lines.of(enc(t, True{}, d)))}
    case J.JField{k, v, t}:
      R.RLines{R.cat(R.field(T.enc.key(k), enc(v, False{}, d)), R.lines.of(enc(t, False{}, d)))}
    case _:
      R.RPrim{prim.text(j, code(d))}

# Encode a value as TOON text.
def encode(j: J.Json, o: EOpts) -> String:
  match o:
    case EOpts{indent, d, fold}:
      R.render(indent, R.root(enc(F.fold(j, fold), False{}, d)))
