import Base
import ./num.bend as N

# The JSON data model TOON speaks.
#
# The shape is the one cswap-bend uses (`src/json.bend` there): arrays and
# objects are chains inside Json itself (JNil, JCons, JField) rather than
# Lists, so every traversal is one structurally recursive def. Json is Data
# (reusable). Converting to or from cswap-bend's Json is a constructor-for-
# constructor map, one def of seven arms.
#
# Numbers keep their source text (JNum{"1.50"}); encode and decode write the
# canonical decimal form. A JNum whose text is not a number (NaN, Infinity)
# encodes as null (spec section 3).

type Json is Data:
  JNull{}
  JBool{b: Bool}
  JNum{text: String}
  JStr{s: String}
  JArr{items: Json}
  JObj{fields: Json}
  JNil{}
  JCons{head: Json, tail: Json}
  JField{key: String, val: Json, tail: Json}

# Array of the values, in order.
def arr.chain(+xs: List<&2, Json>) -> Json:
  match xs:
    case Nil{}:
      JNil{}
    case Con{h, t}:
      JCons{h, arr.chain(t)}

def arr(+xs: List<&2, Json>) -> Json:
  JArr{arr.chain(xs)}

def field.of(kv: String & Json, +rest: Json) -> Json:
  (k, v) = kv
  JField{k, v, rest}

def obj.chain(kvs: List<(String & Json)>) -> Json:
  match kvs:
    case Nil{}:
      JNil{}
    case Con{kv, t}:
      field.of(kv, obj.chain(t))

# Object from ordered (key, value) pairs.
def obj(kvs: List<(String & Json)>) -> Json:
  JObj{obj.chain(kvs)}

# Number from its decimal text.
def num(+t: String) -> Json:
  JNum{t}

def str(+s: String) -> Json:
  JStr{s}

# ---- equality ------------------------------------------------------------------------

def num.eq(+a: Maybe<&2, String>, +b: Maybe<&2, String>) -> Bool:
  match a b:
    case Some{x} Some{y}:
      String.eq(x, y)
    case None{} None{}:
      True{}
    case _ _:
      False{}

def bool.eq(+a: Bool, +b: Bool) -> Bool:
  match a b:
    case True{} True{}:
      True{}
    case False{} False{}:
      True{}
    case _ _:
      False{}

def lit.eq(+a: Json, +b: Json) -> Bool:
  match a b:
    case JNull{} JNull{}:
      True{}
    case JBool{x} JBool{y}:
      bool.eq(x, y)
    case JNil{} JNil{}:
      True{}
    case _ _:
      False{}

def prim.eq(+a: Json, +b: Json) -> Bool:
  match a b:
    case JNum{x} JNum{y}:
      num.eq(N.canon(x), N.canon(y))
    case JStr{x} JStr{y}:
      String.eq(x, y)
    case _ _:
      lit.eq(a, b)

# JSON-model equality (spec section 2): same shape, same ordered keys, numbers
# equal by value (`1.0` equals `1`), strings equal by code points.
def eq(+a: Json, +b: Json) -> Bool:
  match a b:
    case JArr{x} JArr{y}:
      eq(x, y)
    case JObj{x} JObj{y}:
      eq(x, y)
    case JCons{h, t} JCons{h2, t2}:
      eq(h, h2) && eq(t, t2)
    case JField{k, v, t} JField{k2, v2, t2}:
      String.eq(k, k2) && eq(v, v2) && eq(t, t2)
    case _ _:
      prim.eq(a, b)
