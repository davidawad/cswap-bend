import Base
import ./num.bend as N
import ./head.bend as Hd

# Strings and keys (spec section 7): escaping, quoting decisions, unescaping.

# ---- characters --------------------------------------------------------------

# A decoded value with the text that follows it.
type Cut is Data:
  Cut{val: String, rest: String}

# Unescape state: normal, after a backslash, or reading the hex digits of a
# \uXXXX escape (`k` digits to go, `acc` so far).
type Us is Data:
  UN{}
  UB{}
  UH{k: U32, acc: U32}

# What one character does to the output.
type Ek is Data:
  EkChar{u: U32}
  EkNone{}
  EkEnd{}
  EkErr{m: String}

# The whitespace JavaScript's String.trim removes: what section 7.2 means by
# leading or trailing whitespace.
def is_ws(+c: U32) -> Bool:
  U32.is_eq(c, 32) || (U32.is_ge(c, 9) && U32.is_le(c, 13)) || U32.is_eq(c, 160)
    || U32.is_eq(c, 5760) || (U32.is_ge(c, 8192) && U32.is_le(c, 8202))
    || U32.is_eq(c, 8232) || U32.is_eq(c, 8233) || U32.is_eq(c, 8239)
    || U32.is_eq(c, 8287) || U32.is_eq(c, 12288) || U32.is_eq(c, 65279)

def head_ws(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{c}, t}:
      is_ws(c)

def last_ws(+s: String) -> Bool:
  head_ws(String.reverse(s))

def sel.s(+b: Bool, +x: String, +y: String) -> String:
  match b:
    case True{}:
      x
    case False{}:
      y

# ---- encoding ------------------------------------------------------------------

def sel.u(+b: Bool, +x: U32, +y: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      y

def hexd(+n: U32) -> Char:
  Chr{sel.u(U32.is_lt(n, 10), (n + 48 : U32), (n + 87 : U32))}

# \u00xx for a control character, lowercase hex.
def esc.ctl(+c: U32) -> String:
  "\\u00" ++ SCon{hexd(((c >> 4n) : U32)), SCon{hexd((c .&. 15 : U32)), SNil{}}}

def esc.other(+c: U32) -> String:
  sel.s(U32.is_lt(c, 32), esc.ctl(c), SCon{Chr{c}, SNil{}})

# One character inside quotes (section 7.1 encoder column).
def esc.char(+c: U32) -> String:
  sel.s(U32.is_eq(c, 34), "\\\"",
  sel.s(U32.is_eq(c, 92), "\\\\",
  sel.s(U32.is_eq(c, 10), "\\n",
  sel.s(U32.is_eq(c, 13), "\\r",
  sel.s(U32.is_eq(c, 9), "\\t", esc.other(c))))))

def esc.body(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{c}, t}:
      esc.char(c) ++ esc.body(t)

# `"text"` with escapes.
def quote(+s: String) -> String:
  "\"" ++ esc.body(s) ++ "\""

# A character that forces quotes anywhere in a string value: colon, double
# quote, backslash, brackets, braces, control characters, or the delimiter.
def special(+c: U32, +d: U32) -> Bool:
  U32.is_eq(c, 58) || U32.is_eq(c, 34) || U32.is_eq(c, 92) || U32.is_eq(c, 91)
    || U32.is_eq(c, 93) || U32.is_eq(c, 123) || U32.is_eq(c, 125)
    || U32.is_lt(c, 32) || U32.is_eq(c, d)

def has_special(+s: String, +d: U32) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{c}, t}:
      special(c, d) || has_special(t, d)

def is_some(+m: Maybe<&2, N.Num>) -> Bool:
  match m:
    case Some{n}:
      True{}
    case None{}:
      False{}

def numeric_like(+s: String) -> Bool:
  is_some(N.split(s))

def starts_hyphen(+s: String) -> Bool:
  Hd.lead(s, 45)

def reserved(+s: String) -> Bool:
  String.eq(s, "true") || String.eq(s, "false") || String.eq(s, "null")

# Section 7.2: must this string value be quoted? `d` is the delimiter that
# applies (the document delimiter for field values, the active delimiter for
# array cells), as a code point.
def needs_quote(+s: String, +d: U32) -> Bool:
  String.is_empty(s) || head_ws(s) || last_ws(s) || reserved(s)
    || numeric_like(s) || starts_hyphen(s) || has_special(s, d)

# A string value, quoted when it must be.
def enc.str(+s: String, +d: U32) -> String:
  sel.s(needs_quote(s, d), quote(s), s)

def key_start(+c: Char) -> Bool:
  Char.is_alpha(c) || Char.is_eq(c, '_')

def key_rest(+c: Char) -> Bool:
  Char.is_alpha(c) || Char.is_digit(c) || Char.is_eq(c, '_') || Char.is_eq(c, '.')

def key_tail(+s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      key_rest(c) && key_tail(t)

# `^[A-Za-z_][A-Za-z0-9_.]*$`.
def key_plain(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, t}:
      key_start(c) && key_tail(t)

def enc.key(+k: String) -> String:
  sel.s(key_plain(k), k, quote(k))

# ---- decoding ------------------------------------------------------------------

def hex.pick(+dg: Bool, +lo: Bool, +up: Bool, +c: U32) -> Maybe<&2, U32>:
  match dg lo up:
    case True{} _ _:
      Some{(c - 48 : U32)}
    case False{} True{} _:
      Some{(c - 87 : U32)}
    case False{} False{} True{}:
      Some{(c - 55 : U32)}
    case _ _ _:
      None{}

def hex.val(+c: U32) -> Maybe<&2, U32>:
  hex.pick(U32.is_ge(c, 48) && U32.is_le(c, 57), U32.is_ge(c, 97) && U32.is_le(c, 102),
    U32.is_ge(c, 65) && U32.is_le(c, 70), c)

def push(+c: U32, +r: Result<&2, &2, String, Cut>) -> Result<&2, &2, String, Cut>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{Cut{v, rest}}:
      Done{Cut{SCon{Chr{c}, v}, rest}}

# The code point a simple escape letter stands for, or the sentinel 4294967295.
def esc.code(+e: U32) -> U32:
  sel.u(U32.is_eq(e, 110), 10, sel.u(U32.is_eq(e, 114), 13, sel.u(U32.is_eq(e, 116), 9,
    sel.u(U32.is_eq(e, 34), 34, sel.u(U32.is_eq(e, 92), 92, 4294967295)))))

def us.pick(+b: Bool, +x: Us, +y: Us) -> Us:
  match b:
    case True{}:
      x
    case False{}:
      y

def hex.next(+m: Maybe<&2, U32>, +k: U32, +acc: U32) -> Us:
  match m:
    case None{}:
      UN{}
    case Some{h}:
      us.pick(U32.is_eq(k, 1), UN{}, UH{(k - 1 : U32), (((acc << 4n) : U32) + h : U32)})

# The state after reading character `c`.
def next(+st: Us, +c: U32) -> Us:
  match st:
    case UN{}:
      us.pick(U32.is_eq(c, 92), UB{}, UN{})
    case UB{}:
      us.pick(U32.is_eq(c, 117), UH{4, 0}, UN{})
    case UH{k, acc}:
      hex.next(hex.val(c), k, acc)

def ek.pick(+b: Bool, +x: Ek, +y: Ek) -> Ek:
  match b:
    case True{}:
      x
    case False{}:
      y

def simple.emit(+code: U32) -> Ek:
  ek.pick(U32.is_eq(code, 4294967295), EkErr{"invalid escape sequence"}, EkChar{code})

# A finished \uXXXX value: a surrogate is refused (section 7.1).
def unit.emit(+n: U32) -> Ek:
  ek.pick(U32.is_ge(n, 55296) && U32.is_le(n, 57343), EkErr{"surrogate code point in \\u escape"}, EkChar{n})

def hex.emit(+m: Maybe<&2, U32>, +k: U32, +acc: U32) -> Ek:
  match m:
    case None{}:
      EkErr{"invalid \\u escape"}
    case Some{h}:
      ek.pick(U32.is_eq(k, 1), unit.emit((((acc << 4n) : U32) + h : U32)), EkNone{})

# What character `c` emits in state `st`.
def emit(+st: Us, +c: U32) -> Ek:
  match st:
    case UN{}:
      ek.pick(U32.is_eq(c, 34), EkEnd{}, ek.pick(U32.is_eq(c, 92), EkNone{}, EkChar{c}))
    case UB{}:
      ek.pick(U32.is_eq(c, 117), EkNone{}, simple.emit(esc.code(c)))
    case UH{k, acc}:
      hex.emit(hex.val(c), k, acc)

def unq.k(+ek: Ek, +t: String, +r: Result<&2, &2, String, Cut>) -> Result<&2, &2, String, Cut>:
  match ek:
    case EkChar{u}:
      push(u, r)
    case EkNone{}:
      r
    case EkEnd{}:
      Done{Cut{SNil{}, t}}
    case EkErr{m}:
      Fail{m}

def unq.go(+s: String, +st: Us) -> Result<&2, &2, String, Cut>:
  match s:
    case SNil{}:
      Fail{"unterminated string"}
    case SCon{Chr{c}, t}:
      unq.k(emit(st, c), t, unq.go(t, next(st, c)))

# Unescape a quoted string whose opening quote is already consumed; the
# result carries the text after the closing quote.
def unq(+s: String) -> Result<&2, &2, String, Cut>:
  unq.go(s, UN{})
