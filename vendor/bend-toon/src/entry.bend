import Base
import ./json.bend as J
import ./text.bend as T
import ./split.bend as S
import ./prim.bend as P
import ./head.bend as Hd
import ./hdr.bend as H

# One logical line seen as an entry (spec sections 5, 6, 8): `key: value`,
# `key:` (opens an object), `key[N]...:` (an array header), or none of these.

type Ent is Data:
  ENot{}
  EVal{k: String, v: J.Json}
  EOpen{k: String}
  EArr{k: Maybe<&2, String>, h: H.Hdr}

def val.done(+k: String, +r: Result<&2, &2, String, J.Json>) -> Result<&2, &2, String, Ent>:
  match r:
    case Done{v}:
      Done{EVal{k, v}}
    case Fail{e}:
      Fail{e}

def val.pick(+blank: Bool, +arr: Bool, +k: String, +t: String) -> Result<&2, &2, String, Ent>:
  match blank arr:
    case True{} _:
      Done{EOpen{k}}
    case False{} True{}:
      Done{EArr{Some{k}, H.empty()}}
    case False{} False{}:
      val.done(k, P.parse(t))

# The text after the colon of `key:`.
def val(+k: String, +v: String) -> Result<&2, &2, String, Ent>:
  val.pick(String.is_empty(String.trim(v)), String.eq(String.trim(v), "[]"), k, String.trim(v))

def hdr.done(+k: Maybe<&2, String>, +r: Result<&2, &2, String, H.Hdr>) -> Result<&2, &2, String, Ent>:
  match r:
    case Done{h}:
      Done{EArr{k, h}}
    case Fail{e}:
      Fail{e}

def quoted.pick(+colon: Bool, +brack: Bool, +k: String, +rest: String) -> Result<&2, &2, String, Ent>:
  match colon brack:
    case True{} _:
      val(Hd.mark() ++ k, Hd.drop(rest))
    case False{} True{}:
      hdr.done(Some{Hd.mark() ++ k}, H.parse(rest))
    case False{} False{}:
      Done{ENot{}}

# quoted key, then what follows its closing quote
def quoted.rest(+k: String, +rest: String) -> Result<&2, &2, String, Ent>:
  quoted.pick(Hd.lead(rest, 58), Hd.lead(rest, 91), k, rest)

def quoted(+r: Result<&2, &2, String, T.Cut>) -> Result<&2, &2, String, Ent>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{T.Cut{k, rest}}:
      quoted.rest(k, rest)

# The key text before the colon at `ci`, and the value after it.
def kv(+text: String, +ci: U32) -> Result<&2, &2, String, Ent>:
  val(String.trim(String.take(text, U32.to_nat(ci))), String.drop(text, U32.to_nat((ci + 1 : U32))))

def key.opt.pick(+blank: Bool, +k: String) -> Maybe<&2, String>:
  match blank:
    case True{}:
      None{}
    case False{}:
      Some{k}

def key.opt(+raw: String) -> Maybe<&2, String>:
  key.opt.pick(String.is_empty(String.trim(raw)), String.trim(raw))

# A header that did not parse: with no colon at all the line is no entry; with
# one, strict mode reports the header and lenient mode reads a literal key.
def hdr.bad(+nocolon: Bool, +strict: Bool, +e: String, +text: String, +ci: U32) -> Result<&2, &2, String, Ent>:
  match nocolon strict:
    case True{} _:
      Done{ENot{}}
    case False{} True{}:
      Fail{e}
    case False{} False{}:
      kv(text, ci)

def hdr.at(+strict: Bool, +text: String, +ci: U32, +bi: U32, +r: Result<&2, &2, String, H.Hdr>) -> Result<&2, &2, String, Ent>:
  match r:
    case Done{h}:
      Done{EArr{key.opt(String.take(text, U32.to_nat(bi))), h}}
    case Fail{e}:
      hdr.bad(U32.is_eq(ci, S.none()), strict, e, text, ci)

def bare.pick(+strict: Bool, +bfirst: Bool, +nocolon: Bool, +text: String, +ci: U32, +bi: U32) -> Result<&2, &2, String, Ent>:
  match bfirst nocolon:
    case True{} _:
      hdr.at(strict, text, ci, bi, H.parse(String.drop(text, U32.to_nat(bi))))
    case False{} True{}:
      Done{ENot{}}
    case False{} False{}:
      kv(text, ci)

def bare(+strict: Bool, +text: String) -> Result<&2, &2, String, Ent>:
  bare.pick(strict, U32.is_lt(S.find(text, 91, 0), S.find(text, 58, 0)), U32.is_eq(S.find(text, 58, 0), S.none()), text, S.find(text, 58, 0), S.find(text, 91, 0))

def parse.pick(+isq: Bool, +strict: Bool, +text: String) -> Result<&2, &2, String, Ent>:
  match isq:
    case True{}:
      quoted(T.unq(Hd.drop(text)))
    case False{}:
      bare(strict, text)

# Parse a line's content (after indentation or after a list hyphen).
def parse(+strict: Bool, +text: String) -> Result<&2, &2, String, Ent>:
  parse.pick(Hd.lead(text, 34), strict, text)
