import Base
import ../json.bend as Json
import ../json/quote.bend as Quote
import ./ylex.bend as L

# The YAML emitter: block style, two spaces per level, `- ` items under their
# key. A string is written plain only when no reader could take it for
# another type (L.plain_ok); otherwise it is double-quoted with JSON escapes
# (valid YAML). No trailing newline. Pure.

# Where a value sits: the document, after `key:`, after `- `, or inside a
# chain of fields or items.
type Ctx is Data:
  CTop{}
  CKey{}
  CItem{}
  CChain{}

def pad(+d: Nat) -> String:
  String.repeat(" ", d)

def str(+s: String) -> String:
  Bool.pick(String, L.plain_ok(s), s, Quote.quote(s, False{}))

# Before a scalar: a space after `key:`.
def lead(+k: Ctx) -> String:
  match k:
    case CKey{}:
      " "
    case _:
      ""

# The indent of a container's lines.
def ind(+k: Ctx, +d: Nat) -> Nat:
  match k:
    case CTop{}:
      d
    case _:
      Nat.add(d, 2n)

# Before a container's first line: under a key it starts a new line.
def pre(+k: Ctx, +d: Nat) -> String:
  match k:
    case CKey{}:
      "\n" ++ pad(Nat.add(d, 2n))
    case _:
      ""

def is_nil(j: Json.Json) -> Bool:
  match j:
    case Json.JNil{}:
      True{}
    case _:
      False{}

def cont(empty: Bool, +k: Ctx, +d: Nat, lit: String, body: String) -> String:
  match empty:
    case True{}:
      lead(k) ++ lit
    case False{}:
      pre(k, d) ++ body

# A new line for the next field or item, none at the end of the chain.
def sep(t: Json.Json, +d: Nat, rest: String) -> String:
  match t:
    case Json.JNil{}:
      ""
    case _:
      "\n" ++ pad(d) ++ rest

# `j` at the base indent `d` in context `k`. Chains (fields, items) carry their
# lines at `d`; the first line of a chain starts wherever the caller left off.
def y(j: Json.Json, +k: Ctx, +d: Nat) -> String:
  match j:
    case Json.JNull{}:
      lead(k) ++ "null"
    case Json.JBool{b}:
      lead(k) ++ Json.bool.show(b)
    case Json.JNum{t}:
      lead(k) ++ t
    case Json.JStr{s}:
      lead(k) ++ str(s)
    case Json.JArr{+items}:
      cont(is_nil(items), k, d, "[]", y(items, CChain{}, ind(k, d)))
    case Json.JObj{+fields}:
      cont(is_nil(fields), k, d, "{}", y(fields, CChain{}, ind(k, d)))
    case Json.JNil{}:
      ""
    case Json.JCons{h, +t}:
      "- " ++ y(h, CItem{}, d) ++ sep(t, d, y(t, CChain{}, d))
    case Json.JField{key, v, +t}:
      str(key) ++ ":" ++ y(v, CKey{}, d) ++ sep(t, d, y(t, CChain{}, d))

# One YAML document for the value (no `---`, no trailing newline).
def emit(j: Json.Json) -> String:
  y(j, CTop{}, 0n)
