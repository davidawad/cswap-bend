import Base
import ./num.bend as N
import ./head.bend as Hd
import ./text.bend as T
import ./split.bend as S
import ./prim.bend as P

# Array headers (spec section 6): `[N]`, `[N|]`, `[N<TAB>]`, optional
# `{f1,f2}`, then the colon. `parse` takes the text starting at `[`.

# length, delimiter as a code point, field names (empty: not tabular), and the
# text after the colon.
type Hdr is Data:
  Hdr{n: U32, d: U32, fields: List<&2, String>, rest: String}

def empty() -> Hdr:
  Hdr{0, 44, Nil{}, SNil{}}

def bad(+m: String) -> Result<&2, &2, String, Hdr>:
  Fail{m}

# A field name: quoted names are unescaped; a bare name that holds another
# delimiter than the active one is a delimiter mismatch.
# A quoted field name keeps its marker (see head.bend).
def mark.name(+r: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  match r:
    case Done{k}:
      Done{Hd.mark() ++ k}
    case Fail{e}:
      Fail{e}

def name.ok(+bare: Bool, +bad_delim: Bool, +tok: String) -> Result<&2, &2, String, String>:
  match bare bad_delim:
    case True{} True{}:
      Fail{"header delimiter mismatch"}
    case True{} False{}:
      Done{tok}
    case False{} _:
      mark.name(P.key(tok))

def other_delim(+c: U32, +d: U32) -> Bool:
  (U32.is_eq(c, 44) || U32.is_eq(c, 9) || U32.is_eq(c, 124)) && Bool.not(U32.is_eq(c, d))

def has_other(+s: String, +d: U32) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{c}, t}:
      other_delim(c, d) || has_other(t, d)

def not_quoted(+s: String) -> Bool:
  Bool.not(Hd.lead(s, 34))

def name(+d: U32, +tok: String) -> Result<&2, &2, String, String>:
  name.ok(not_quoted(tok), has_other(tok, d), tok)

def names.cons(+r: Result<&2, &2, String, String>, +rest: Result<&2, &2, String, List<&2, String>>) -> Result<&2, &2, String, List<&2, String>>:
  match r rest:
    case Done{n} Done{ns}:
      Done{Con{n, ns}}
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

def names(+d: U32, +toks: List<&2, String>) -> Result<&2, &2, String, List<&2, String>>:
  match toks:
    case Nil{}:
      Done{Nil{}}
    case Con{t, rest}:
      names.cons(name(d, String.trim(t)), names(d, rest))

def fields.done(+n: U32, +d: U32, +rest: String, +r: Result<&2, &2, String, List<&2, String>>) -> Result<&2, &2, String, Hdr>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{ks}:
      Done{Hdr{n, d, ks, rest}}

def fields.after.pick(+colon: Bool, +n: U32, +d: U32, +inner: String, +s: String) -> Result<&2, &2, String, Hdr>:
  match colon:
    case True{}:
      fields.done(n, d, Hd.drop(s), names(d, S.split(inner, d)))
    case False{}:
      bad("expected : after the field list")

# After `}`: the colon follows at once.
def fields.after(+n: U32, +d: U32, +inner: String, +s: String) -> Result<&2, &2, String, Hdr>:
  fields.after.pick(Hd.lead(s, 58), n, d, inner, s)

def fields.cut.if(+missing: Bool, +n: U32, +d: U32, +s: String, +i: U32) -> Result<&2, &2, String, Hdr>:
  match missing:
    case True{}:
      bad("unterminated field list")
    case False{}:
      fields.after(n, d, String.take(s, U32.to_nat(i)), String.drop(s, U32.to_nat((i + 1 : U32))))

def fields.cut(+n: U32, +d: U32, +s: String, +i: U32) -> Result<&2, &2, String, Hdr>:
  fields.cut.if(U32.is_eq(i, S.none()), n, d, s, i)

def after.pick(+colon: Bool, +brace: Bool, +n: U32, +d: U32, +s: String) -> Result<&2, &2, String, Hdr>:
  match colon brace:
    case True{} _:
      Done{Hdr{n, d, Nil{}, Hd.drop(s)}}
    case False{} True{}:
      fields.cut(n, d, Hd.drop(s), S.find_unq(Hd.drop(s), 125, 0, 0))
    case False{} False{}:
      bad("expected : or a field list after the length")

# After `]`: the colon, or a field list.
def after(+n: U32, +d: U32, +s: String) -> Result<&2, &2, String, Hdr>:
  after.pick(Hd.lead(s, 58), Hd.lead(s, 123), n, d, s)

def delim.pick(+tab: Bool, +pipe: Bool, +comma: Bool, +n: U32, +s: String) -> Result<&2, &2, String, Hdr>:
  match tab pipe comma:
    case True{} _ _:
      after(n, 9, Hd.drop(Hd.drop(s)))
    case False{} True{} _:
      after(n, 124, Hd.drop(Hd.drop(s)))
    case False{} False{} True{}:
      after(n, 44, Hd.drop(s))
    case False{} False{} False{}:
      bad("invalid array length")

# The delimiter symbol, then `]`.
def delim(+n: U32, +s: String) -> Result<&2, &2, String, Hdr>:
  delim.pick(Hd.lead2(s, 9, 93), Hd.lead2(s, 124, 93), Hd.lead(s, 93), n, s)

def len.pick(+ok: Bool, +n: Maybe<&2, U32>, +rest: String) -> Result<&2, &2, String, Hdr>:
  match ok n:
    case True{} Some{v}:
      delim(v, rest)
    case _ _:
      bad("invalid array length")

def len.ok.pick(+empty: Bool, +zero: Bool, +lead0: Bool, +ds: String) -> Bool:
  match empty zero lead0:
    case True{} _ _:
      False{}
    case False{} True{} _:
      True{}
    case False{} False{} True{}:
      False{}
    case False{} False{} False{}:
      Nat.is_le(String.length(ds), 9n)

# A length is `0` or digits without a leading zero, at most nine of them.
def len.ok(+ds: String) -> Bool:
  len.ok.pick(String.is_empty(ds), String.eq(ds, "0"), Hd.lead(ds, 48), ds)

def len(+r: N.Sp) -> Result<&2, &2, String, Hdr>:
  match r:
    case N.Sp{ds, rest}:
      len.pick(len.ok(ds), U32.read(ds), rest)

def parse.pick(+open: Bool, +s: String) -> Result<&2, &2, String, Hdr>:
  match open:
    case True{}:
      len(N.span_digits(Hd.drop(s)))
    case False{}:
      bad("expected [")

# Parse a header from its `[`.
def parse(+s: String) -> Result<&2, &2, String, Hdr>:
  parse.pick(Hd.lead(s, 91), s)
