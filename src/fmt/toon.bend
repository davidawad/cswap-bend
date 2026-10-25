import Base
import ../json.bend as Json
import ../../vendor/bend-toon/main.bend as Toon

# TOON (spec v3.3) for the JSON data model, through the vendored bend-toon
# package (vendor/bend-toon, see VENDOR.md). Once bend-toon is on BendHub, the
# import above becomes `import bend-toon@0.1.0.0/main.bend as Toon`.
# bend-toon declares its own Json type with this module's constructors, so the
# two are converted constructor for constructor.

def to_toon(j: Json.Json) -> Toon.Json:
  match j:
    case Json.JNull{}:
      Toon.JNull{}
    case Json.JBool{b}:
      Toon.JBool{b}
    case Json.JNum{t}:
      Toon.JNum{t}
    case Json.JStr{s}:
      Toon.JStr{s}
    case Json.JArr{x}:
      Toon.JArr{to_toon(x)}
    case Json.JObj{x}:
      Toon.JObj{to_toon(x)}
    case Json.JNil{}:
      Toon.JNil{}
    case Json.JCons{h, t}:
      Toon.JCons{to_toon(h), to_toon(t)}
    case Json.JField{k, v, t}:
      Toon.JField{k, to_toon(v), to_toon(t)}

def of_toon(j: Toon.Json) -> Json.Json:
  match j:
    case Toon.JNull{}:
      Json.JNull{}
    case Toon.JBool{b}:
      Json.JBool{b}
    case Toon.JNum{t}:
      Json.JNum{t}
    case Toon.JStr{s}:
      Json.JStr{s}
    case Toon.JArr{x}:
      Json.JArr{of_toon(x)}
    case Toon.JObj{x}:
      Json.JObj{of_toon(x)}
    case Toon.JNil{}:
      Json.JNil{}
    case Toon.JCons{h, t}:
      Json.JCons{of_toon(h), of_toon(t)}
    case Toon.JField{k, v, t}:
      Json.JField{k, of_toon(v), of_toon(t)}

# TOON text (indent 2, comma delimiter, LF, no trailing newline).
def emit(j: Json.Json) -> String:
  Toon.encode(to_toon(j), Toon.encode_default())

def lift(r: Result<&2, &2, String, Toon.Json>) -> Result<&2, &2, String, Json.Json>:
  match r:
    case Done{v}:
      Done{of_toon(v)}
    case Fail{e}:
      Fail{e}

# The value of TOON text (strict mode); `Fail` starts with the line number.
def parse(s: String) -> Result<&2, &2, String, Json.Json>:
  lift(Toon.decode(s, Toon.decode_default()))
