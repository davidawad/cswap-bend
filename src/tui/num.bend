import Base
import ../json.bend as Json
import ../clock.bend as Clock

# Reading numbers and stamps out of the JSON files the dashboard follows.

def sel(+c: Bool, +x: U32, +y: U32) -> U32:
  match c:
    case True{}:
      x
    case False{}:
      y

def read_or(+m: Maybe<&2, U32>, +d: U32) -> U32:
  match m:
    case None{}:
      d
    case Some{x}:
      x

# Two fraction digits, padded: "5" -> 50, "07" -> 7, "555" -> 55.
def frac_centi(+f: String) -> Maybe<&2, U32>:
  U32.read(String.take(f ++ "00", 2n))

def centi_join(+i: Maybe<&2, U32>, +f: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match i f:
    case Some{a} Some{b}:
      Some{(a * 100 + b : U32)}
    case _ _:
      None{}

def centi_parts(+ps: List<&2, String>) -> Maybe<&2, U32>:
  match ps:
    case Con{i, Nil{}}:
      centi_join(U32.read(i), Some{0})
    case Con{i, Con{f, Nil{}}}:
      centi_join(U32.read(i), frac_centi(f))
    case _:
      None{}

# "47" -> 4700, "47.5" -> 4750, "47.555" -> 4755; anything else is None.
def centi_text(+t: String) -> Maybe<&2, U32>:
  centi_parts(String.split(t, '.'))

def centi_of(+j: Json.Json) -> Maybe<&2, U32>:
  match j:
    case Json.JNum{t}:
      centi_text(t)
    case _:
      None{}

def centi_at2(+m: Maybe<&2, Json.Json>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{x}:
      centi_of(x)

def centi_at(+key: String, +j: Json.Json) -> Maybe<&2, U32>:
  centi_at2(Json.get(key, j))

def secs_parts(+ps: List<&2, String>) -> Maybe<&2, U32>:
  match ps:
    case Con{i, t}:
      U32.read(i)
    case Nil{}:
      None{}

# Whole seconds of a JSON number: "1792740000.1" -> 1792740000.
def secs_of(+j: Json.Json) -> Maybe<&2, U32>:
  match j:
    case Json.JNum{t}:
      secs_parts(String.split(t, '.'))
    case _:
      None{}

def secs_at2(+m: Maybe<&2, Json.Json>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{x}:
      secs_of(x)

def secs_at(+key: String, +j: Json.Json) -> Maybe<&2, U32>:
  secs_at2(Json.get(key, j))

def iso_of(+j: Json.Json) -> Maybe<&2, U32>:
  match j:
    case Json.JStr{s}:
      Clock.parse_iso8601(s)
    case _:
      None{}

def iso_at2(+m: Maybe<&2, Json.Json>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{x}:
      iso_of(x)

def iso_at(+key: String, +j: Json.Json) -> Maybe<&2, U32>:
  iso_at2(Json.get(key, j))

def uint_of(+j: Json.Json) -> Maybe<&2, U32>:
  Json.as_u32(j)

def uint_at2(+m: Maybe<&2, Json.Json>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{x}:
      uint_of(x)

def uint_at(+key: String, +j: Json.Json) -> Maybe<&2, U32>:
  uint_at2(Json.get(key, j))

def str_or(+m: Maybe<&2, String>, +d: String) -> String:
  match m:
    case None{}:
      d
    case Some{s}:
      s

def opt_json_s(+m: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{j}:
      Json.as_string(j)

def str_at(+key: String, +j: Json.Json) -> String:
  str_or(opt_json_s(Json.get(key, j)), "")

def null_json() -> Json.Json:
  Json.JNull{}

# A parsed value, JSON null when the text does not parse.
def parsed(+r: Result<&2, &2, String, Json.Json>) -> Json.Json:
  match r:
    case Done{j}:
      j
    case Fail{e}:
      Json.JNull{}

def parse_text(+t: String) -> Json.Json:
  parsed(Json.parse(t))

def from_opt(+m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case None{}:
      Json.JNull{}
    case Some{j}:
      j

def get_or_null(+key: String, +j: Json.Json) -> Json.Json:
  from_opt(Json.get(key, j))
