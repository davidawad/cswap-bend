import Base

type Tok is Data:
  TLBrace{}
  TRBrace{}
  TLBrack{}
  TRBrack{}
  TColon{}
  TComma{}
  TNull{}
  TTrue{}
  TFalse{}
  TNum{text: String}
  TStr{s: String}
  TSkip{}
  TErr{msg: String}

def sel(c: Bool, x: U32, y: U32) -> U32:
  match c:
    case True{}:
      x
    case False{}:
      y

def sel.s(c: Bool, x: String, y: String) -> String:
  match c:
    case True{}:
      x
    case False{}:
      y

def sel.n(c: Bool, x: Nat, y: Nat) -> Nat:
  match c:
    case True{}:
      x
    case False{}:
      y

def not(b: Bool) -> Bool:
  Bool.not(b)

def eqc(+c: Char, +d: Char) -> Bool:
  Char.is_eq(c, d)

# ---- characters and numbers --------------------------------------------------

def is_word(+c: Char) -> Bool:
  Char.is_digit(c) || Char.is_alpha(c) || eqc(c, '-') || eqc(c, '+') || eqc(c, '.')

def head_word(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+c, t}:
      is_word(c)

# Leading run of word characters.
def span_word(s: String, ok: Bool) -> Nat:
  match s ok:
    case SCon{c, +t} True{}:
      1n+span_word(t, head_word(t))
    case _ _:
      0n

# Chars through the closing quote (or to the end when it is missing).
def span_str(s: String, live: Bool, +esc: Bool) -> Nat:
  match s live:
    case SCon{+c, t} True{}:
      1n+span_str(t, not(not(esc) && eqc(c, '"')), not(esc) && eqc(c, '\\'))
    case _ _:
      0n

def num.next2(+st: U32, +d: Bool, +z: Bool, +dot: Bool, +ex: Bool, +sign: Bool, +minus: Bool) -> U32:
  sel(U32.is_eq(st, 0), sel(minus, 1, sel(z, 2, sel(d, 3, 99))),
  sel(U32.is_eq(st, 1), sel(d, sel(z, 2, 3), 99),
  sel(U32.is_eq(st, 2), sel(dot, 4, sel(ex, 6, 99)),
  sel(U32.is_eq(st, 3), sel(d, 3, sel(dot, 4, sel(ex, 6, 99))),
  sel(U32.is_eq(st, 4), sel(d, 5, 99),
  sel(U32.is_eq(st, 5), sel(d, 5, sel(ex, 6, 99)),
  sel(U32.is_eq(st, 6), sel(sign, 7, sel(d, 8, 99)),
  sel(U32.is_eq(st, 7), sel(d, 8, 99),
  sel(U32.is_eq(st, 8), sel(d, 8, 99), 99)))))))))

# JSON number grammar as a state machine: 0 start, 1 after -, 2 after 0,
# 3 int digits, 4 after ., 5 frac digits, 6 after e, 7 after exp sign,
# 8 exp digits, 99 dead. 2, 3, 5 and 8 accept.
def num.next(+st: U32, +c: Char) -> U32:
  num.next2(st, Char.is_digit(c), eqc(c, '0'), eqc(c, '.'), eqc(c, 'e') || eqc(c, 'E'), eqc(c, '-') || eqc(c, '+'), eqc(c, '-'))

def num.run(s: String, +st: U32) -> U32:
  match s:
    case SNil{}:
      st
    case SCon{c, t}:
      num.run(t, num.next(st, c))

def num.acc(+st: U32) -> Bool:
  U32.is_eq(st, 2) || U32.is_eq(st, 3) || U32.is_eq(st, 5) || U32.is_eq(st, 8)

def num.ok(+s: String) -> Bool:
  num.acc(num.run(s, 0))

# What a bare word is: null, true, false, a number, or an error.
def word.num(ok: Bool, w: String) -> Tok:
  match ok:
    case True{}:
      TNum{w}
    case False{}:
      TErr{"bad literal: " ++ w}

def word.pick(n: Bool, t: Bool, f: Bool, special: Bool, +w: String) -> Tok:
  match n t f special:
    case True{} _ _ _:
      TNull{}
    case False{} True{} _ _:
      TTrue{}
    case False{} False{} True{} _:
      TFalse{}
    case False{} False{} False{} True{}:
      TNum{w}
    case False{} False{} False{} False{}:
      word.num(num.ok(w), w)

def word.tok(+w: String) -> Tok:
  word.pick(String.eq(w, "null"), String.eq(w, "true"), String.eq(w, "false"),
    String.eq(w, "NaN") || String.eq(w, "Infinity") || String.eq(w, "-Infinity"), w)

# ---- string escapes ----------------------------------------------------------

def hv(+c: U32) -> U32:
  sel(U32.is_ge(c, 48) && U32.is_le(c, 57), (c - 48 : U32),
  sel(U32.is_ge(c, 97) && U32.is_le(c, 102), (c - 87 : U32),
  sel(U32.is_ge(c, 65) && U32.is_le(c, 70), (c - 55 : U32), 99)))

# Code of the char at index i; 0 past the end.
def cc.pick(m: Maybe<&2, Char>) -> U32:
  match m:
    case None{}:
      0
    case Some{Chr{c}}:
      c

def cc(+s: String, i: Nat) -> U32:
  cc.pick(String.get(s, i))

def hex4.fin(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  sel(U32.is_lt(a, 16) && U32.is_lt(b, 16) && U32.is_lt(c, 16) && U32.is_lt(d, 16),
    (a * 4096 + b * 256 + c * 16 + d : U32), 65533)

# The four hex digits at the head of s as a number; U+FFFD when malformed.
def hex4(+s: String) -> U32:
  hex4.fin(hv(cc(s, 0n)), hv(cc(s, 1n)), hv(cc(s, 2n)), hv(cc(s, 3n)))

def is_hi(+u: U32) -> Bool:
  U32.is_ge(u, 55296) && U32.is_le(u, 56319)

def is_lo(+u: U32) -> Bool:
  U32.is_ge(u, 56320) && U32.is_le(u, 57343)

# After \uD83D: is the next escape a \uDC00..\uDFFF low half?
def pair.ok(+u1: U32, +t5: String) -> Bool:
  is_hi(u1) && U32.is_eq(cc(t5, 0n), 92) && U32.is_eq(cc(t5, 1n), 117) && is_lo(hex4(String.drop(t5, 2n)))

def pair.cp(+u1: U32, +t5: String) -> U32:
  (65536 + ((u1 - 55296) << 10n) + (hex4(String.drop(t5, 2n)) - 56320) : U32)

def esc.u2(+u1: U32, +t5: String) -> U32:
  sel(pair.ok(u1, t5), pair.cp(u1, t5), u1)

def esc.u(+t: String) -> U32:
  esc.u2(hex4(String.drop(t, 1n)), String.drop(t, 5n))

def esc.cp2(+e: U32, +t: String) -> U32:
  sel(U32.is_eq(e, 34) || U32.is_eq(e, 92) || U32.is_eq(e, 47), e,
  sel(U32.is_eq(e, 98), 8,
  sel(U32.is_eq(e, 102), 12,
  sel(U32.is_eq(e, 110), 10,
  sel(U32.is_eq(e, 114), 13,
  sel(U32.is_eq(e, 116), 9,
  sel(U32.is_eq(e, 117), esc.u(t), 65533)))))))

# The code point a char (or the escape it starts) stands for.
def esc.cp(+c: U32, +t: String) -> U32:
  sel(U32.is_eq(c, 92), esc.cp2(cc(t, 0n), t), c)

def esc.sk2(+e: U32, +t: String) -> U32:
  sel(U32.is_eq(e, 117), sel(pair.ok(hex4(String.drop(t, 1n)), String.drop(t, 5n)), 11, 5), 1)

# Chars after the first that the escape consumes.
def esc.skip(+c: U32, +t: String) -> Nat:
  U32.to_nat(sel(U32.is_eq(c, 92), esc.sk2(cc(t, 0n), t), 0))

# Decode the escapes of a string body. `fuel` is its length.
def unescape(fuel: Nat, s: String) -> String:
  match fuel s:
    case _ SNil{}:
      SNil{}
    case 0n _:
      SNil{}
    case 1n+p SCon{Chr{+c}, +t}:
      SCon{Chr{esc.cp(c, t)}, unescape(p, String.drop(t, esc.skip(c, t)))}

# ---- lexer -------------------------------------------------------------------

def str.closed(s: String, live: Bool, +esc: Bool) -> Bool:
  match s live:
    case SCon{+c, t} True{}:
      str.closed(t, not(not(esc) && eqc(c, '"')), not(esc) && eqc(c, '\\'))
    case _ l:
      not(l)

def str.pick(closed: Bool, +body: String) -> Tok:
  match closed:
    case True{}:
      TStr{unescape(String.length(body), body)}
    case False{}:
      TErr{"unterminated string"}

# t follows the opening quote.
def str.tok(+t: String) -> Tok:
  str.pick(str.closed(t, True{}, False{}), String.take(t, Nat.sub(span_str(t, True{}, False{}), 1n)))

def tk.sel(c: Bool, t: Tok, rest: Tok) -> Tok:
  match c:
    case True{}:
      t
    case False{}:
      rest

def punct.pick(lb: Bool, rb: Bool, ls: Bool, rs: Bool, co: Bool, cm: Bool, ws: Bool) -> Tok:
  tk.sel(lb, TLBrace{}, tk.sel(rb, TRBrace{}, tk.sel(ls, TLBrack{}, tk.sel(rs, TRBrack{}, tk.sel(co, TColon{}, tk.sel(cm, TComma{}, tk.sel(ws, TSkip{}, TErr{"unexpected character"})))))))

def punct.tok(+c: Char) -> Tok:
  punct.pick(eqc(c, '{'), eqc(c, '}'), eqc(c, '['), eqc(c, ']'), eqc(c, ':'), eqc(c, ','), Char.is_space(c))

def tok.of2(q: Bool, w: Bool, +c: Char, +t: String) -> Tok:
  match q w:
    case True{} _:
      str.tok(t)
    case False{} True{}:
      word.tok(SCon{c, String.take(t, span_word(t, head_word(t)))})
    case False{} False{}:
      punct.tok(c)

def tok.of(+c: Char, +t: String) -> Tok:
  tok.of2(eqc(c, '"'), is_word(c), c, t)

def tok.adv(+c: Char, +t: String) -> Nat:
  sel.n(eqc(c, '"'), span_str(t, True{}, False{}), sel.n(is_word(c), span_word(t, head_word(t)), 0n))

def tok.cons(t: Tok, rest: List<&2, Tok>) -> List<&2, Tok>:
  match t:
    case TSkip{}:
      rest
    case _:
      t <> rest

# Tokens of s. `fuel` is its length.
def lex(fuel: Nat, s: String) -> List<&2, Tok>:
  match fuel s:
    case _ SNil{}:
      []
    case 0n _:
      [TErr{"internal: lexer out of fuel"}]
    case 1n+p SCon{+c, +t}:
      tok.cons(tok.of(c, t), lex(p, String.drop(t, tok.adv(c, t))))

# 11 { 12 [ 21 } 22 ] 3 , 0 anything else.
