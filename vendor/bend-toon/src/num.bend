import Base
import ./head.bend as Hd

# Decimal text to TOON canonical decimal text, on strings only (no floats, so
# any number of digits is exact).
#
# canon("1.5000") == Some{"1.5"}, canon("-1E+03") == Some{"-1000"},
# canon("-0.0") == Some{"0"}, canon("1e-7") == Some{"1e-7"}.
#
# The value is 0.DDD * 10^P with D free of leading and trailing zeros. P is a
# U32 biased by 2^31 (`bias`), so comparisons are unsigned. Decimal form for
# 1e-6 <= |n| < 1e21 (spec section 2), exponent form (`1e+21`, `1.5e-7`)
# outside it. An exponent of more than nine digits is refused (None).

type Sp is Data:
  Sp{a: String, b: String}

# A parsed number: sign, integer digits, fraction digits, exponent as a
# biased-free signed pair.
type Num is Data:
  Num{neg: Bool, ip: String, fp: String, eneg: Bool, ex: String}

type Sp2 is Data:
  Sp2{d: String, p: U32}

def bias() -> U32:
  2147483648

def sp.cons(+c: U32, +r: Sp) -> Sp:
  match r:
    case Sp{a, b}:
      Sp{SCon{Chr{c}, a}, b}

def sp.pick(+d: Bool, +c: U32, +whole: String, +r: Sp) -> Sp:
  match d:
    case True{}:
      sp.cons(c, r)
    case False{}:
      Sp{SNil{}, whole}

# Leading run of ASCII digits, and the rest.
def span_digits(+s: String) -> Sp:
  match s:
    case SNil{}:
      Sp{SNil{}, SNil{}}
    case SCon{Chr{c}, t}:
      sp.pick(Char.is_digit(Chr{c}), c, s, span_digits(t))

def is_zero_char(+c: Char) -> Bool:
  Char.is_eq(c, '0')

# True when the string is empty or all zeros.
def all_zeros(+s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      is_zero_char(c) && all_zeros(t)

def num.opt(+ok: Bool, +n: Num) -> Maybe<&2, Num>:
  match ok:
    case True{}:
      Some{n}
    case False{}:
      None{}

# After the exponent digits: nothing may follow.
def exp.done(+neg: Bool, +ip: String, +fp: String, +eneg: Bool, +r: Sp) -> Maybe<&2, Num>:
  match r:
    case Sp{+ds, +rest}:
      num.opt(String.is_empty(rest) && Bool.not(String.is_empty(ds)), Num{neg, ip, fp, eneg, ds})

def exp.sign(+neg: Bool, +ip: String, +fp: String, +eneg: Bool, +s: String) -> Maybe<&2, Num>:
  exp.done(neg, ip, fp, eneg, span_digits(s))

def exp.part.pick(+plus: Bool, +minus: Bool, +neg: Bool, +ip: String, +fp: String, +s: String) -> Maybe<&2, Num>:
  match plus minus:
    case True{} _:
      exp.sign(neg, ip, fp, False{}, Hd.drop(s))
    case False{} True{}:
      exp.sign(neg, ip, fp, True{}, Hd.drop(s))
    case False{} False{}:
      exp.sign(neg, ip, fp, False{}, s)

# After `e`: an optional sign, then digits.
def exp.part(+neg: Bool, +ip: String, +fp: String, +s: String) -> Maybe<&2, Num>:
  exp.part.pick(Hd.lead(s, 43), Hd.lead(s, 45), neg, ip, fp, s)

def frac.rest.pick(+empty: Bool, +e: Bool, +neg: Bool, +ip: String, +fp: String, +s: String) -> Maybe<&2, Num>:
  match empty e:
    case True{} _:
      Some{Num{neg, ip, fp, False{}, "0"}}
    case False{} True{}:
      exp.part(neg, ip, fp, Hd.drop(s))
    case False{} False{}:
      None{}

# After the fraction: end of text or an exponent.
def frac.rest(+neg: Bool, +ip: String, +fp: String, +s: String) -> Maybe<&2, Num>:
  frac.rest.pick(String.is_empty(s), Hd.lead(s, 101) || Hd.lead(s, 69), neg, ip, fp, s)

def frac.digits(+neg: Bool, +ip: String, +r: Sp) -> Maybe<&2, Num>:
  match r:
    case Sp{ds, rest}:
      match ds:
        case SNil{}:
          None{}
        case _:
          frac.rest(neg, ip, ds, rest)

def int.rest.pick(+dot: Bool, +neg: Bool, +ip: String, +s: String) -> Maybe<&2, Num>:
  match dot:
    case True{}:
      frac.digits(neg, ip, span_digits(Hd.drop(s)))
    case False{}:
      frac.rest(neg, ip, SNil{}, s)

# After the integer digits: a fraction, an exponent, or the end.
def int.rest(+neg: Bool, +ip: String, +s: String) -> Maybe<&2, Num>:
  int.rest.pick(Hd.lead(s, 46), neg, ip, s)

def int.digits(+neg: Bool, +r: Sp) -> Maybe<&2, Num>:
  match r:
    case Sp{ds, rest}:
      match ds:
        case SNil{}:
          None{}
        case _:
          int.rest(neg, ds, rest)

def split.pick(+minus: Bool, +s: String) -> Maybe<&2, Num>:
  match minus:
    case True{}:
      int.digits(True{}, span_digits(Hd.drop(s)))
    case False{}:
      int.digits(False{}, span_digits(s))

# `-?digits(.digits)?([eE][+-]?digits)?`, as parts.
def split(+s: String) -> Maybe<&2, Num>:
  split.pick(Hd.lead(s, 45), s)

# ---- value to canonical text -----------------------------------------------------

def zeros(+k: U32) -> String:
  String.repeat("0", U32.to_nat(k))

def len32(+s: String) -> U32:
  U32.from_nat(String.length(s))

def lead.pick(+z: Bool, +d: String, +p: U32, +r: Sp2) -> Sp2:
  match z:
    case True{}:
      r
    case False{}:
      Sp2{d, p}

# Drop leading zeros of the digit string; each one lowers the point position.
def strip.lead(+d: String, +p: U32) -> Sp2:
  match d:
    case SNil{}:
      Sp2{d, p}
    case SCon{c, t}:
      lead.pick(is_zero_char(c), d, p, strip.lead(t, (p - 1 : U32)))

def drop.pick(+z: Bool, +s: String, +rest: String) -> String:
  match z:
    case True{}:
      rest
    case False{}:
      s

def drop_zeros(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{c, t}:
      drop.pick(is_zero_char(c), s, drop_zeros(t))

def strip.trail(+d: String) -> String:
  String.reverse(drop_zeros(String.reverse(d)))

def mantissa(+d: String) -> String:
  match d:
    case SNil{}:
      "0"
    case SCon{c, t}:
      match t:
        case SNil{}:
          SCon{c, SNil{}}
        case _:
          SCon{c, SCon{'.', t}}

def exp.sign.text(+pos: Bool, +bp: U32) -> String:
  match pos:
    case True{}:
      "e+" ++ U32.show((bp - bias() - 1 : U32))
    case False{}:
      "e-" ++ U32.show((bias() + 1 - bp : U32))

# Exponent form: 1e+21, 1.5e-7. `p` is the point position, biased.
def fmt.exp(+bp: U32, +d: String) -> String:
  mantissa(d) ++ exp.sign.text(U32.is_gt(bp, bias()), bp)

# 0.000ddd for a point position of 0 down to -5.
def fmt.small(+bp: U32, +d: String) -> String:
  "0." ++ zeros((bias() - bp : U32)) ++ d

def fmt.int.pick(+fits: Bool, +k: U32, +d: String) -> String:
  match fits:
    case True{}:
      d ++ zeros((k - len32(d) : U32))
    case False{}:
      String.take(d, U32.to_nat(k)) ++ "." ++ String.drop(d, U32.to_nat(k))

def fmt.int(+bp: U32, +d: String) -> String:
  fmt.int.pick(U32.is_le(len32(d), (bp - bias() : U32)), (bp - bias() : U32), d)

def fmt.mid(+le0: Bool, +bp: U32, +d: String) -> String:
  match le0:
    case True{}:
      fmt.small(bp, d)
    case False{}:
      fmt.int(bp, d)

def fmt.low(+exp: Bool, +bp: U32, +d: String) -> String:
  match exp:
    case True{}:
      fmt.exp(bp, d)
    case False{}:
      fmt.mid(U32.is_le(bp, bias()), bp, d)

# Digits (no leading or trailing zeros) and biased point position to text.
def fmt(+bp: U32, +d: String) -> String:
  fmt.low(U32.is_gt(bp, (bias() + 21 : U32)) || U32.is_lt(bp, (bias() - 5 : U32)), bp, d)

def sign.text(+neg: Bool) -> String:
  match neg:
    case True{}:
      "-"
    case False{}:
      ""

def exp.val.pick(+m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{n}:
      n
    case None{}:
      0

def exp.val(+s: String) -> U32:
  exp.val.pick(U32.read(s))

def read.exp(+eneg: Bool, +ex: String) -> U32:
  match eneg:
    case True{}:
      (bias() - exp.val(ex) : U32)
    case False{}:
      (bias() + exp.val(ex) : U32)

def canon.zero(+z: Bool, +neg: Bool, +d: String, +p: U32) -> String:
  match z:
    case True{}:
      "0"
    case False{}:
      sign.text(neg) ++ fmt(p, strip.trail(d))

def canon.digits(+neg: Bool, +s: Sp2) -> String:
  match s:
    case Sp2{d, p}:
      canon.zero(String.is_empty(d), neg, d, p)

def canon.parts(+ok: Bool, +neg: Bool, +ip: String, +fp: String, +eneg: Bool, +ex: String) -> Maybe<&2, String>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{canon.digits(neg, strip.lead(ip ++ fp, (read.exp(eneg, ex) + len32(ip) : U32)))}

def canon.opt(+m: Maybe<&2, Num>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{Num{neg, ip, fp, eneg, ex}}:
      canon.parts(Nat.is_le(String.length(ex), 9n), neg, ip, fp, eneg, ex)

# Canonical text of a decimal number, None when `s` is not one.
def canon(+s: String) -> Maybe<&2, String>:
  canon.opt(split(s))
