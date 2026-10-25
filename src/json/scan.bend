import Base
import ./lex.bend as Lex

def tk.kind(t: Lex.Tok) -> U32:
  match t:
    case Lex.TLBrace{}:
      11
    case Lex.TLBrack{}:
      12
    case Lex.TRBrace{}:
      21
    case Lex.TRBrack{}:
      22
    case Lex.TComma{}:
      3
    case _:
      0

def depth.next(+k: U32, +d: U32) -> U32:
  Lex.sel(U32.is_eq(k, 11) || U32.is_eq(k, 12), (d + 1 : U32),
    Lex.sel(U32.is_eq(k, 21) || U32.is_eq(k, 22), Lex.sel(U32.is_eq(d, 0), 0, (d - 1 : U32)), d))

def stopper(+k: U32, +d: U32) -> Bool:
  U32.is_eq(d, 0) && (U32.is_eq(k, 3) || U32.is_eq(k, 21) || U32.is_eq(k, 22))

def scan.pick(stop: Bool, rest: Nat) -> Nat:
  match stop:
    case True{}:
      0n
    case False{}:
      rest

# Tokens before the first comma or closer at depth 0.
def scan(toks: List<&2, Lex.Tok>, +d: U32) -> Nat:
  match toks:
    case Nil{}:
      0n
    case Con{+h, t}:
      scan.pick(stopper(tk.kind(h), d), 1n+scan(t, depth.next(tk.kind(h), d)))

def last.kind(m: Maybe<&2, Lex.Tok>) -> U32:
  match m:
    case None{}:
      0
    case Some{t}:
      tk.kind(t)

# Is the last token of t the closer `k`?
def closed_by(+t: List<&2, Lex.Tok>, k: U32) -> Bool:
  U32.is_eq(last.kind(List.last(&2, Lex.Tok, t)), k)

def err.of(toks: List<&2, Lex.Tok>) -> String:
  match toks:
    case Nil{}:
      ""
    case Con{Lex.TErr{m}, t}:
      m
    case Con{h, t}:
      err.of(t)
