import Base
import ./fs/write.bend as FWrite
import ./json.bend as Json
import ./fs.bend as Fs
import ./act.bend as Act
import ./cmd.bend as Cmd

# settings.json and `cswap config`, as the reference's settings.py and
# cli.py `_config_command` (claude-swap 0.27.2).
#
# Numbers stay decimal TEXT. `Dec` is a canonical decimal (no leading zeros in
# the integer part, no trailing zeros in the fraction); comparison is on the
# digit strings, so clamping needs no floats. Python's float repr is rebuilt
# from the text: `85` -> `85.0`, `85.50` -> `85.5`, `0.00001` -> `1e-05`.
# Known gaps, all rare: `1_0` style underscores, more than 15 significant
# digits (Python rounds to 17), and a file number such as `1.50` that the
# reference would rewrite as `1.5` on an unrelated `set`.

# ---- decimals --------------------------------------------------------------

# ---- the settings registry -------------------------------------------------

# ---- lenient load (settings.py `_clamped`, `load_settings`) -----------------

# ---- accessors on a loaded (normalized) settings object ----------------------

# ---- CLI override clamps (merged_with_cli) -----------------------------------

# ---- strict write (settings.py `parse_setting_value`) -------------------------

# ---- editing the raw object --------------------------------------------------

# ---- effective settings and their text ----------------------------------------

# ---- the config command ---------------------------------------------------------

# ---- argv -----------------------------------------------------------------------

type Dec is Data:
  Dec{neg: Bool, i: String, f: String}

type Exp is Data:
  Exp{neg: Bool, n: Nat}

def sel.s(c: Bool, x: String, y: String) -> String:
  match c:
    case True{}:
      x
    case False{}:
      y

def all_digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Char.is_digit(c) && all_digits(t)

def drop0.pick(z: Bool, c: Char, t: String, rest: String) -> String:
  match z:
    case True{}:
      rest
    case False{}:
      SCon{c, t}

# Leading '0' characters dropped.
def drop0(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, +t}:
      drop0.pick(Char.is_eq(c, '0'), c, t, drop0(t))

def canon(neg: Bool, +i: String, f: String) -> Dec:
  Dec{neg, sel.s(String.is_empty(drop0(i)), "0", drop0(i)), String.reverse(drop0(String.reverse(f)))}

# Move the point n digits right (digits come from the fraction, zeros pad).
def shr(n: Nat, neg: Bool, i: String, f: String) -> Dec:
  match n f:
    case 0n _:
      canon(neg, i, f)
    case 1n+p SNil{}:
      shr(p, neg, i ++ "0", "")
    case 1n+p SCon{c, t}:
      shr(p, neg, i ++ SCon{c, SNil{}}, t)

# Move the point n digits left; `ri` is the integer part reversed.
def shl(n: Nat, neg: Bool, ri: String, f: String) -> Dec:
  match n ri:
    case 0n _:
      canon(neg, String.reverse(ri), f)
    case 1n+p SNil{}:
      shl(p, neg, "", "0" ++ f)
    case 1n+p SCon{c, t}:
      shl(p, neg, t, SCon{c, f})

def shift.pick(eneg: Bool, n: Nat, neg: Bool, i: String, f: String) -> Dec:
  match eneg:
    case True{}:
      shl(n, neg, String.reverse(i), f)
    case False{}:
      shr(n, neg, i, f)

def shift(d: Dec, e: Exp) -> Dec:
  match d e:
    case Dec{neg, i, f} Exp{eneg, n}:
      shift.pick(eneg, n, neg, i, f)

def exp.cap2(+d: String) -> Nat:
  U32.to_nat(U32.min(Maybe.default(&2, U32, U32.read(d), 400), 400))

# The exponent digits as a Nat, capped at 400 (beyond that the value clamps
# or vanishes the same way).
def exp.cap(+d: String) -> Nat:
  exp.cap2(sel.s(Nat.is_gt(String.length(d), 3n), "400", d))

def exp.pick(ok: Bool, neg: Bool, d: String) -> Maybe<&2, Exp>:
  match ok:
    case True{}:
      Some{Exp{neg, exp.cap(d)}}
    case False{}:
      None{}

def exp.of3(neg: Bool, +d: String) -> Maybe<&2, Exp>:
  exp.pick(all_digits(d) && Bool.not(String.is_empty(d)), neg, d)

def exp.of2(+neg: Bool, plus: Bool, +x: String) -> Maybe<&2, Exp>:
  exp.of3(neg, sel.s(neg || plus, String.drop(x, 1n), x))

# The exponent text after `e`: an optional sign and at least one digit.
def exp.of(+x: String) -> Maybe<&2, Exp>:
  exp.of2(String.starts_with(x, "-"), String.starts_with(x, "+"), x)

def mant.pick(ok: Bool, neg: Bool, i: String, f: String) -> Maybe<&2, Dec>:
  match ok:
    case True{}:
      Some{canon(neg, i, f)}
    case False{}:
      None{}

def mant.mk(neg: Bool, +i: String, +f: String) -> Maybe<&2, Dec>:
  mant.pick(all_digits(i) && all_digits(f) && Bool.not(String.is_empty(i) && String.is_empty(f)), neg, i, f)

def mant.parts(neg: Bool, ps: List<&2, String>) -> Maybe<&2, Dec>:
  match ps:
    case Con{i, Nil{}}:
      mant.mk(neg, i, "")
    case Con{i, Con{f, Nil{}}}:
      mant.mk(neg, i, f)
    case _:
      None{}

def num.join(m: Maybe<&2, Dec>, e: Maybe<&2, Exp>) -> Maybe<&2, Dec>:
  match m e:
    case Some{d} Some{x}:
      Some{shift(d, x)}
    case _ _:
      None{}

def num.parts(neg: Bool, ps: List<&2, String>) -> Maybe<&2, Dec>:
  match ps:
    case Con{m, Nil{}}:
      num.join(mant.parts(neg, String.split(m, '.')), Some{Exp{False{}, 0n}})
    case Con{m, Con{x, Nil{}}}:
      num.join(mant.parts(neg, String.split(m, '.')), exp.of(x))
    case _:
      None{}

def num.sign(+neg: Bool, plus: Bool, +s: String) -> Maybe<&2, Dec>:
  num.parts(neg, String.split(String.to_lower(sel.s(neg || plus, String.drop(s, 1n), s)), 'e'))

def num.trimmed(+s: String) -> Maybe<&2, Dec>:
  num.sign(String.starts_with(s, "-"), String.starts_with(s, "+"), s)

# Python's float() / JSON number text as a decimal: optional sign, digits with
# an optional point, optional exponent; surrounding spaces ignored. Not `inf`
# or `nan` (see `special`).
def num(+s: String) -> Maybe<&2, Dec>:
  num.trimmed(String.trim(s))

def lit(+s: String) -> Dec:
  Maybe.default(&2, Dec, num(s), Dec{False{}, "0", ""})

def is_zero(d: Dec) -> Bool:
  match d:
    case Dec{neg, i, f}:
      String.eq(i, "0") && String.is_empty(f)

# a < b on magnitudes.
def mag_lt(a: Dec, b: Dec) -> Bool:
  match a b:
    case Dec{na, +ia, +fa} Dec{nb, +ib, +fb}:
      Nat.is_lt(String.length(ia), String.length(ib))
        || (Nat.is_eq(String.length(ia), String.length(ib))
          && (String.is_lt(ia, ib) || (String.eq(ia, ib) && String.is_lt(fa, fb))))

def neg_nonzero(+d: Dec) -> Bool:
  match d:
    case Dec{neg, i, f}:
      neg && Bool.not(is_zero(Dec{neg, i, f}))

def below(+v: Dec, +lo: Dec) -> Bool:
  neg_nonzero(v) || mag_lt(v, lo)

def above(+v: Dec, +hi: Dec) -> Bool:
  Bool.not(neg_nonzero(v)) && mag_lt(hi, v)

def clamp.pick(b: Bool, a: Bool, v: Dec, lo: Dec, hi: Dec) -> Dec:
  match b a:
    case True{} _:
      lo
    case False{} True{}:
      hi
    case False{} False{}:
      v

# min(max(v, lo), hi)
def clamp(+v: Dec, +lo: Dec, +hi: Dec) -> Dec:
  clamp.pick(below(v, lo), above(v, hi), v, lo, hi)

def lead0.pick(z: Bool, rest: Nat) -> Nat:
  match z:
    case True{}:
      1n+rest
    case False{}:
      0n

def lead0(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{+c, +t}:
      lead0.pick(Char.is_eq(c, '0'), lead0(t))

def pad2(+n: Nat) -> String:
  sel.s(Nat.is_lt(n, 10n), "0", "") ++ U32.show(U32.from_nat(n))

def sci.tail(t: String) -> String:
  match t:
    case SNil{}:
      ""
    case SCon{h, r}:
      "." ++ SCon{h, r}

def sci.mant(sig: String) -> String:
  match sig:
    case SNil{}:
      "0"
    case SCon{h, r}:
      SCon{h, sci.tail(r)}

# 1e-05 style, for 0 < value < 1e-4 (the fraction has four leading zeros).
def sci(neg: Bool, +f: String) -> String:
  sel.s(neg, "-", "") ++ sci.mant(drop0(f)) ++ "e-" ++ pad2(1n+lead0(f))

def repr.pick(tiny: Bool, neg: Bool, i: String, +f: String) -> String:
  match tiny:
    case True{}:
      sci(neg, f)
    case False{}:
      sel.s(neg, "-", "") ++ i ++ "." ++ sel.s(String.is_empty(f), "0", f)

# Python's repr(float) of the decimal.
def repr(d: Dec) -> String:
  match d:
    case Dec{neg, +i, +f}:
      repr.pick(String.eq(i, "0") && String.starts_with(f, "0000"), neg, i, f)

def fmt.pick(whole: Bool, d: Dec) -> String:
  match d:
    case Dec{neg, +i, +f}:
      sel.s(whole, i, repr(Dec{neg, i, f}))

# format_setting_value for a float: `85.0` prints as `85`.
def fmt(d: Dec) -> String:
  match d:
    case Dec{neg, i, +f}:
      fmt.pick(String.is_empty(f), Dec{neg, i, f})

# The integer part times ten plus the first fraction digit (tenths, floored).
def tenths.fin(i: String, f: String) -> U32:
  (Maybe.default(&2, U32, U32.read(i), 0) * 10 + Maybe.default(&2, U32, U32.read(String.take(f, 1n)), 0) : U32)

def tenths.dec(d: Dec) -> U32:
  match d:
    case Dec{neg, i, f}:
      tenths.fin(i, f)

# Tenths of a decimal text (floored); 0 for text that is not a number.
def tenths(s: String) -> U32:
  tenths.dec(lit(s))

type Sort is Data:
  KFloat{}
  KInt{}
  KBool{}
  KChoice{}
  KString{}

# `lo`/`hi` are decimal text exactly as the reference prints them; `choices`
# is comma separated; `dflt` is the default as a JSON value.
type Spec is Data:
  Spec{section: String, key: String, kind: Sort, lo: String, hi: String, choices: String, dflt: Json.Json}

def spec.num(key: String, kind: Sort, lo: String, hi: String, dflt: String) -> Spec:
  Spec{"autoswitch", key, kind, lo, hi, "", Json.JNum{dflt}}

# Registry order, as SETTING_SPECS.
def specs() -> List<&2, Spec>:
  [spec.num("threshold", KFloat{}, "50", "99.9", "90.0"),
   spec.num("intervalSeconds", KFloat{}, "15", "3600", "60.0"),
   spec.num("cooldownSeconds", KFloat{}, "0", "86400", "300.0"),
   spec.num("hysteresisPct", KFloat{}, "0", "50", "10.0"),
   Spec{"autoswitch", "strategy", KChoice{}, "", "", "best,consume-first", Json.JStr{"best"}},
   Spec{"autoswitch", "includeApiKeyAccounts", KBool{}, "", "", "", Json.JBool{False{}}},
   spec.num("unhealthyTicks", KInt{}, "1", "100", "3"),
   Spec{"autoswitch", "model", KString{}, "", "", "", Json.JNull{}},
   Spec{"ui", "theme", KChoice{}, "", "", "dark,light,auto", Json.JStr{"auto"}}]

def dotted(+sp: Spec) -> String:
  match sp:
    case Spec{section, key, kind, lo, hi, choices, dflt}:
      section ++ "." ++ key

def find.pick(hit: Bool, sp: Spec, rest: Maybe<&2, Spec>) -> Maybe<&2, Spec>:
  match hit:
    case True{}:
      Some{sp}
    case False{}:
      rest

def find(+key: String, xs: List<&2, Spec>) -> Maybe<&2, Spec>:
  match xs:
    case Nil{}:
      None{}
    case Con{+h, t}:
      find.pick(String.eq(dotted(h), key), h, find(key, t))

def dotted_all(xs: List<&2, Spec>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{+h, t}:
      dotted(h) <> dotted_all(t)

# setting_spec: the spec of a dotted key, or the reference's error text.
def spec_of.pick(m: Maybe<&2, Spec>, key: String) -> Result<&2, &2, String, Spec>:
  match m:
    case Some{sp}:
      Done{sp}
    case None{}:
      Fail{"unknown setting '" ++ key ++ "'\nValid keys: " ++ String.join(dotted_all(specs()), ", ")}

def spec_of(+key: String) -> Result<&2, &2, String, Spec>:
  spec_of.pick(find(key, specs()), key)
