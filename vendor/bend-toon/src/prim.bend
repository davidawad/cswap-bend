import Base
import ./json.bend as J
import ./num.bend as N
import ./head.bend as Hd
import ./text.bend as T

# Primitive tokens (spec section 4 and appendix B.4): quoted string, true,
# false, null, number, or bare string.

def quoted.rest(+ok: Bool, +v: String) -> Result<&2, &2, String, J.Json>:
  match ok:
    case True{}:
      Done{J.JStr{v}}
    case False{}:
      Fail{"unexpected characters after the closing quote"}

# The closing quote must end the token.
def quoted.end(+r: Result<&2, &2, String, T.Cut>) -> Result<&2, &2, String, J.Json>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{T.Cut{v, rest}}:
      quoted.rest(String.is_empty(rest), v)

# A forbidden leading zero: an integer part of two or more digits starting
# with 0 (`05`, `-007`), which stays a string. `0`, `0.5`, `0e1` are numbers.
def lead0.ip(+ip: String) -> Bool:
  Hd.lead(ip, 48) && Hd.at_least(ip, 2n)

def lead0(+m: Maybe<&2, N.Num>) -> Bool:
  match m:
    case Some{N.Num{neg, ip, fp, eneg, ex}}:
      lead0.ip(ip)
    case None{}:
      False{}

def num.pick(+ok: Bool, +c: Maybe<&2, String>, +tok: String) -> J.Json:
  match ok c:
    case True{} Some{t}:
      J.JNum{t}
    case _ _:
      J.JStr{tok}

# A bare token that is not true, false or null: number or string.
def bare.num(+tok: String) -> J.Json:
  num.pick(Bool.not(lead0(N.split(tok))), N.canon(tok), tok)

def bare.pick(+t: Bool, +f: Bool, +n: Bool, +tok: String) -> J.Json:
  match t f n:
    case True{} _ _:
      J.JBool{True{}}
    case False{} True{} _:
      J.JBool{False{}}
    case False{} False{} True{}:
      J.JNull{}
    case False{} False{} False{}:
      bare.num(tok)

def bare(+tok: String) -> J.Json:
  bare.pick(String.eq(tok, "true"), String.eq(tok, "false"), String.eq(tok, "null"), tok)

def parse.pick(+quoted: Bool, +tok: String) -> Result<&2, &2, String, J.Json>:
  match quoted:
    case True{}:
      quoted.end(T.unq(Hd.drop(tok)))
    case False{}:
      Done{bare(tok)}

# A trimmed token as a value.
def parse(+tok: String) -> Result<&2, &2, String, J.Json>:
  parse.pick(Hd.lead(tok, 34), tok)

def key.rest(+ok: Bool, +v: String) -> Result<&2, &2, String, String>:
  match ok:
    case True{}:
      Done{v}
    case False{}:
      Fail{"unexpected characters after the closing quote"}

def key.end(+r: Result<&2, &2, String, T.Cut>) -> Result<&2, &2, String, String>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{T.Cut{v, rest}}:
      key.rest(String.is_empty(rest), v)

def key.pick(+quoted: Bool, +tok: String) -> Result<&2, &2, String, String>:
  match quoted:
    case True{}:
      key.end(T.unq(Hd.drop(tok)))
    case False{}:
      Done{tok}

def key(+tok: String) -> Result<&2, &2, String, String>:
  key.pick(Hd.lead(tok, 34), tok)

# Values of a delimited list, as an array chain.
def values.cons(+r: Result<&2, &2, String, J.Json>, +rest: Result<&2, &2, String, J.Json>) -> Result<&2, &2, String, J.Json>:
  match r rest:
    case Done{v} Done{vs}:
      Done{J.JCons{v, vs}}
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

def values(+toks: List<&2, String>) -> Result<&2, &2, String, J.Json>:
  match toks:
    case Nil{}:
      Done{J.JNil{}}
    case Con{t, rest}:
      values.cons(parse(String.trim(t)), values(rest))
