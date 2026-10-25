import Base
import ../json.bend as Json

# YAML pieces shared by the writer (yamlw.bend) and the reader (yamlr.bend):
# which strings may be written plain, quoted tokens, and how a plain word
# resolves to null, a boolean, a number or a string. Pure.

def JR() -> Type:
  Result<&2, &2, String, Json.Json>

def ge(+c: U32, lo: U32) -> Bool:
  U32.is_ge(c, lo)

def between(+c: U32, lo: U32, hi: U32) -> Bool:
  U32.is_ge(c, lo) && U32.is_le(c, hi)

def is_digit(+c: U32) -> Bool:
  between(c, 48, 57)

def is_space(+c: U32) -> Bool:
  U32.is_eq(c, 32)

# ---- numbers (the JSON grammar: -?(0|[1-9]d*)(.d+)?([eE][+-]?d+)?) ---------

type NS is Data:
  NStart{}
  NMinus{}
  NZero{}
  NInt{}
  NDot{}
  NFrac{}
  NExp{}
  NESign{}
  NEDig{}
  NBad{}

def ns.lead(+c: U32) -> NS:
  Bool.pick(NS, U32.is_eq(c, 48), NZero{}, Bool.pick(NS, between(c, 49, 57), NInt{}, NBad{}))

def ns.start(+c: U32) -> NS:
  Bool.pick(NS, U32.is_eq(c, 45), NMinus{}, ns.lead(c))

def ns.tail(+c: U32) -> NS:
  Bool.pick(NS, U32.is_eq(c, 46), NDot{}, Bool.pick(NS, U32.is_eq(c, 101) || U32.is_eq(c, 69), NExp{}, NBad{}))

def ns.int(+c: U32) -> NS:
  Bool.pick(NS, is_digit(c), NInt{}, ns.tail(c))

def ns.frac(+c: U32) -> NS:
  Bool.pick(NS, is_digit(c), NFrac{}, Bool.pick(NS, U32.is_eq(c, 101) || U32.is_eq(c, 69), NExp{}, NBad{}))

def ns.exp(+c: U32) -> NS:
  Bool.pick(NS, U32.is_eq(c, 43) || U32.is_eq(c, 45), NESign{}, Bool.pick(NS, is_digit(c), NEDig{}, NBad{}))

def ns.digits(+c: U32, next: NS) -> NS:
  Bool.pick(NS, is_digit(c), next, NBad{})

def ns.step(s: NS, +c: U32) -> NS:
  match s:
    case NStart{}:
      ns.start(c)
    case NMinus{}:
      ns.lead(c)
    case NZero{}:
      ns.tail(c)
    case NInt{}:
      ns.int(c)
    case NDot{}:
      ns.digits(c, NFrac{})
    case NFrac{}:
      ns.frac(c)
    case NExp{}:
      ns.exp(c)
    case NESign{}:
      ns.digits(c, NEDig{})
    case NEDig{}:
      ns.digits(c, NEDig{})
    case NBad{}:
      NBad{}

def ns.run(s: String, st: NS) -> NS:
  match s:
    case SNil{}:
      st
    case SCon{Chr{c}, t}:
      ns.run(t, ns.step(st, c))

def ns.accept(s: NS) -> Bool:
  match s:
    case NZero{}:
      True{}
    case NInt{}:
      True{}
    case NFrac{}:
      True{}
    case NEDig{}:
      True{}
    case _:
      False{}

# Is the whole text a JSON number?
def is_number(s: String) -> Bool:
  ns.accept(ns.run(s, NStart{}))

# ---- plain words -------------------------------------------------------------

def word_is(+low: String, w: String) -> Bool:
  String.eq(low, w)

def is_null_word(+low: String) -> Bool:
  String.is_empty(low) || word_is(low, "~") || word_is(low, "null")

def is_bool_word(+low: String) -> Bool:
  word_is(low, "true") || word_is(low, "false")

# Words YAML 1.1 and 1.2 readers turn into another type.
def reserved(+low: String) -> Bool:
  is_null_word(low) || is_bool_word(low) || word_is(low, "yes") || word_is(low, "no") || word_is(low, "on") || word_is(low, "off") || word_is(low, "y") || word_is(low, "n")

# A plain word as the value it stands for.
def resolve.low(+low: String, +s: String) -> Json.Json:
  Bool.pick(Json.Json, is_null_word(low), Json.JNull{},
  Bool.pick(Json.Json, word_is(low, "true"), Json.JBool{True{}},
  Bool.pick(Json.Json, word_is(low, "false"), Json.JBool{False{}},
  Bool.pick(Json.Json, is_number(s), Json.JNum{s}, Json.JStr{s}))))

def resolve(+s: String) -> Json.Json:
  resolve.low(String.to_lower(s), s)

# ---- may a string be written plain? -------------------------------------------

# Characters a plain scalar must not start with: indicators, quotes, and
# anything a reader could take for a number, a date, a tag or a merge key.
def bad_first(+c: U32) -> Bool:
  U32.is_eq(c, 45) || U32.is_eq(c, 63) || U32.is_eq(c, 58) || U32.is_eq(c, 44) || U32.is_eq(c, 91) || U32.is_eq(c, 93) || U32.is_eq(c, 123) || U32.is_eq(c, 125)
    || U32.is_eq(c, 35) || U32.is_eq(c, 38) || U32.is_eq(c, 42) || U32.is_eq(c, 33) || U32.is_eq(c, 124) || U32.is_eq(c, 62) || U32.is_eq(c, 39) || U32.is_eq(c, 34)
    || U32.is_eq(c, 37) || U32.is_eq(c, 64) || U32.is_eq(c, 96) || U32.is_eq(c, 43) || U32.is_eq(c, 46) || U32.is_eq(c, 126) || U32.is_eq(c, 61) || U32.is_eq(c, 60)
    || is_digit(c) || is_space(c)

def bad_char(+c: U32) -> Bool:
  U32.is_lt(c, 32) || between(c, 127, 159) || between(c, 8232, 8233) || U32.is_eq(c, 65279)

# Scan the rest: no control characters, no ": " or trailing ":", no " #".
def rest_ok(s: String, +prev: U32) -> Bool:
  match s:
    case SNil{}:
      Bool.not(U32.is_eq(prev, 58)) && Bool.not(is_space(prev))
    case SCon{Chr{+c}, t}:
      Bool.not(bad_char(c)) && Bool.not(U32.is_eq(prev, 58) && is_space(c)) && Bool.not(is_space(prev) && U32.is_eq(c, 35)) && rest_ok(t, c)

def first_ok(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{+c}, t}:
      Bool.not(bad_first(c)) && Bool.not(bad_char(c)) && rest_ok(t, c)

def plain_ok(+s: String) -> Bool:
  first_ok(s) && Bool.not(reserved(String.to_lower(s)))

# ---- quoted tokens ------------------------------------------------------------

def dq.pick(done: Bool, n: Nat, rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match done:
    case True{}:
      Some{n}
    case False{}:
      rest

# `n` characters of a double-quoted body (after the opening quote) up to and
# including its closing quote, or None when it never closes.
def dq.end(s: String, +n: Nat, +esc: Bool) -> Maybe<&2, Nat>:
  match s:
    case SNil{}:
      None{}
    case SCon{Chr{+c}, t}:
      dq.pick(Bool.not(esc) && U32.is_eq(c, 34), Nat.add(n, 1n), dq.end(t, Nat.add(n, 1n), Bool.not(esc) && U32.is_eq(c, 92)))

def sq.eos(prevq: Bool, n: Nat) -> Maybe<&2, Nat>:
  match prevq:
    case True{}:
      Some{n}
    case False{}:
      None{}

def sq.pick(done: Bool, n: Nat, rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match done:
    case True{}:
      Some{n}
    case False{}:
      rest

# The same for a single-quoted body: `''` is a quote. `prevq`: the last
# character was a quote that may close the string.
def sq.end(s: String, +n: Nat, +prevq: Bool) -> Maybe<&2, Nat>:
  match s:
    case SNil{}:
      sq.eos(prevq, n)
    case SCon{Chr{+c}, t}:
      sq.pick(prevq && Bool.not(U32.is_eq(c, 39)), n, sq.end(t, Nat.add(n, 1n), Bool.not(prevq) && U32.is_eq(c, 39)))

def first_code(s: String) -> U32:
  match s:
    case SNil{}:
      0
    case SCon{Chr{c}, t}:
      c

def tl.plus(m: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{n}:
      Some{Nat.add(n, 1n)}

def tl.pick(isd: Bool, iss: Bool, d: Maybe<&2, Nat>, s: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match isd iss:
    case True{} _:
      d
    case False{} True{}:
      s
    case False{} False{}:
      None{}

def token_len.q(+s: String, +c: U32) -> Maybe<&2, Nat>:
  tl.pick(U32.is_eq(c, 34), U32.is_eq(c, 39), tl.plus(dq.end(String.drop(s, 1n), 0n, False{})), tl.plus(sq.end(String.drop(s, 1n), 0n, False{})))

# Length of the quoted token at the start of `s` (quotes included), when `s`
# starts with a quote and the token closes.
def token_len(+s: String) -> Maybe<&2, Nat>:
  token_len.q(s, first_code(s))
