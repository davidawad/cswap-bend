import Base
import ./src/json.bend as I
import ./src/encode.bend as Enc
import ./src/decode.bend as Dec

# bend-toon: TOON (Token-Oriented Object Notation, spec v3.3) for Bend 2.
#
#   import bend-toon@0.1.0/main.bend as Toon
#
#   Toon.encode(value, Toon.EncodeOpts{2, Toon.Comma{}})   -> String
#   Toon.decode(text, Toon.DecodeOpts{2, True{}})           -> Result<String, Json>
#
# The types below are this file's own, so a caller can name them (Bend does
# not expose the types of a module's imports). They have the shape of the
# Json in cswap-bend's src/json.bend, constructor for constructor, and the
# codec works on an internal copy of the same shape (src/json.bend).
# README.md has the API, the value model and the conformance report.

# JSON values. Arrays and objects are chains inside Json itself: an array is
# JArr{JCons{a, JCons{b, JNil{}}}}, an object is
# JObj{JField{"k", v, JField{"k2", v2, JNil{}}}}. Numbers keep their decimal
# text (JNum{"1.50"}); encode writes the canonical form.
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

# Delimiter of arrays and tabular rows.
type Delim is Data:
  Comma{}
  Tab{}
  Pipe{}

# Spaces per indent level, the document delimiter, and key folding: 0 is off
# (the default), n of 2 or more folds chains of single-key objects into dotted
# keys of at most n segments (`a.b.c: 1`), 4294967295 folds whole chains.
type EncodeOpts is Data:
  EncodeOpts{indent: U32, delim: Delim, fold: U32}

# Spaces per indent level (used to compute line depth), strict mode (counts,
# indentation, blank lines, duplicate keys), and path expansion (an unquoted
# key `a.b.c` becomes nested objects; quoted keys stay literal).
type DecodeOpts is Data:
  DecodeOpts{indent: U32, strict: Bool, expand: Bool}

# Indent 2, comma.
def encode_default() -> EncodeOpts:
  EncodeOpts{2, Comma{}, 0}

# Indent 2, strict.
def decode_default() -> DecodeOpts:
  DecodeOpts{2, True{}, False{}}

# ---- conversion to and from the codec's own value type -----------------------

def to_inner(j: Json) -> I.Json:
  match j:
    case JNull{}:
      I.JNull{}
    case JBool{b}:
      I.JBool{b}
    case JNum{t}:
      I.JNum{t}
    case JStr{s}:
      I.JStr{s}
    case JArr{x}:
      I.JArr{to_inner(x)}
    case JObj{x}:
      I.JObj{to_inner(x)}
    case JNil{}:
      I.JNil{}
    case JCons{h, t}:
      I.JCons{to_inner(h), to_inner(t)}
    case JField{k, v, t}:
      I.JField{k, to_inner(v), to_inner(t)}

def of_inner(j: I.Json) -> Json:
  match j:
    case I.JNull{}:
      JNull{}
    case I.JBool{b}:
      JBool{b}
    case I.JNum{t}:
      JNum{t}
    case I.JStr{s}:
      JStr{s}
    case I.JArr{x}:
      JArr{of_inner(x)}
    case I.JObj{x}:
      JObj{of_inner(x)}
    case I.JNil{}:
      JNil{}
    case I.JCons{h, t}:
      JCons{of_inner(h), of_inner(t)}
    case I.JField{k, v, t}:
      JField{k, of_inner(v), of_inner(t)}

def of_inner_result(r: Result<&2, &2, String, I.Json>) -> Result<&2, &2, String, Json>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{v}:
      Done{of_inner(v)}

def inner_delim(d: Delim) -> Enc.Delim:
  match d:
    case Comma{}:
      Enc.Comma{}
    case Tab{}:
      Enc.Tab{}
    case Pipe{}:
      Enc.Pipe{}

# ---- API ---------------------------------------------------------------------

# TOON text of a value, LF line endings, no trailing newline. NaN and Infinity
# (a JNum whose text is not a number) encode as null.
def encode(j: Json, o: EncodeOpts) -> String:
  match o:
    case EncodeOpts{indent, d, fold}:
      Enc.encode(to_inner(j), Enc.EOpts{indent, inner_delim(d), fold})

# The value of TOON text, or the first error with its line number.
def decode(s: String, o: DecodeOpts) -> Result<&2, &2, String, Json>:
  match o:
    case DecodeOpts{indent, strict, expand}:
      of_inner_result(Dec.decode(s, Dec.DOpts{indent, strict, expand}))

# JSON-model equality: numbers by value (`1.0` equals `1`), objects by ordered
# keys.
def eq(a: Json, b: Json) -> Bool:
  I.eq(to_inner(a), to_inner(b))
