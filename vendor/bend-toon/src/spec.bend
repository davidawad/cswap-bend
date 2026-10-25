import Base
import ./json.bend as J
import ./encode.bend as E
import ./decode.bend as D

# The statements LAWS.bend makes about the codec, as plain defs.

# Primitives chosen to hit every quoting and number rule. All numbers are in
# canonical form, so decode returns exactly what was encoded.
type Atom is Data:
  ANull{}
  ATrue{}
  AFalse{}
  AInt{}
  ADec{}
  AStr{}
  AComma{}
  ANumStr{}
  AEmpty{}
  AColon{}
  AEsc{}

# Object keys, plain and needing quotes.
type KeyAtom is Data:
  KPlain{}
  KSpace{}
  KDigit{}
  KEmpty{}
  KColon{}

type Dl is Data:
  DComma{}
  DTab{}
  DPipe{}

# Four primitives for laws with two slots: null, a number, a string that needs
# quotes under a comma, and one with escapes.
type Duo is Data:
  PNull{}
  PNum{}
  PComma{}
  PEsc{}

# Encode with comma and indent 2, then decode strictly.
def rt(+v: J.Json) -> Result<&2, &2, String, J.Json>:
  D.decode(E.encode(v, E.defaults()), D.ddefaults())

# The same with delimiter `d` and indent `i`.
def rt.with(+v: J.Json, +d: E.Delim, +i: U32) -> Result<&2, &2, String, J.Json>:
  D.decode(E.encode(v, E.EOpts{i, d, 0}), D.DOpts{i, True{}, False{}})

# ---- a finite universe of values, for laws quantified over every member ----------

def atom.str(+a: Atom) -> J.Json:
  match a:
    case AStr{}:
      J.JStr{"x y"}
    case AComma{}:
      J.JStr{"a,b"}
    case ANumStr{}:
      J.JStr{"42"}
    case AEmpty{}:
      J.JStr{""}
    case AColon{}:
      J.JStr{"a:b"}
    case AEsc{}:
      J.JStr{"q\"\n\t\\"}
    case _:
      J.JNull{}

def atom(+a: Atom) -> J.Json:
  match a:
    case ANull{}:
      J.JNull{}
    case ATrue{}:
      J.JBool{True{}}
    case AFalse{}:
      J.JBool{False{}}
    case AInt{}:
      J.JNum{"42"}
    case ADec{}:
      J.JNum{"-0.5"}
    case _:
      atom.str(a)

def key(+k: KeyAtom) -> String:
  match k:
    case KPlain{}:
      "name"
    case KSpace{}:
      "full name"
    case KDigit{}:
      "1x"
    case KEmpty{}:
      ""
    case KColon{}:
      "a:b"

def delim(+d: Dl) -> E.Delim:
  match d:
    case DComma{}:
      E.Comma{}
    case DTab{}:
      E.Tab{}
    case DPipe{}:
      E.Pipe{}

def one(+k: String, +v: J.Json) -> J.Json:
  J.JObj{J.JField{k, v, J.JNil{}}}

def two(+k1: String, +v1: J.Json, +k2: String, +v2: J.Json) -> J.Json:
  J.JObj{J.JField{k1, v1, J.JField{k2, v2, J.JNil{}}}}

def duo(+d: Duo) -> Atom:
  match d:
    case PNull{}:
      ANull{}
    case PNum{}:
      ADec{}
    case PComma{}:
      AComma{}
    case PEsc{}:
      AEsc{}

# Shapes: where two values sit. A law that fills both slots from one atom
# passes it twice.
def s.fields(+a: J.Json, +b: J.Json) -> J.Json:
  two("x", a, "y", b)

def s.inline(+a: J.Json, +b: J.Json) -> J.Json:
  one("xs", J.arr([a, b]))

def s.root_arr(+a: J.Json, +b: J.Json) -> J.Json:
  J.arr([a, b])

def s.tabular(+a: J.Json, +b: J.Json) -> J.Json:
  one("rows", J.arr([two("p", a, "q", b), two("p", b, "q", a)]))

def s.mixed(+a: J.Json, +b: J.Json) -> J.Json:
  one("items", J.arr([a, one("k", b), J.arr([a, b])]))

def s.nested(+a: J.Json, +b: J.Json) -> J.Json:
  two("o", one("i", one("leaf", a)), "t", b)

def s.list_first_tab(+a: J.Json, +b: J.Json) -> J.Json:
  one("items", J.arr([two("u", J.arr([one("id", a), one("id", b)]), "note", a)]))

def s.field(+k: KeyAtom, +a: Atom) -> J.Json:
  one(key(k), atom(a))

# ---- ground values -------------------------------------------------------------------

def n(+t: String) -> J.Json:
  J.JNum{t}

def s(+t: String) -> J.Json:
  J.JStr{t}

# The example from the spec's introduction, with an extra field.
def g.users() -> J.Json:
  J.obj([("users", J.arr([J.obj([("id", n("1")), ("name", s("Alice")), ("role", s("admin"))]), J.obj([("id", n("2")), ("name", s("Bob")), ("role", s("user"))])])), ("count", n("2"))])

# Every container kind at once: nested objects, inline, tabular and list arrays,
# arrays of arrays, a list item that opens with a tabular array.
def g.everything() -> J.Json:
  J.obj([("meta", J.obj([("v", n("3")), ("tags", J.arr([s("a"), s("b c"), s("d,e")]))])), ("rows", J.arr([J.obj([("k", n("1")), ("v", J.JNull{})]), J.obj([("k", n("2")), ("v", s("x"))])])), ("mixed", J.arr([n("1"), J.obj([("a", J.JBool{True{}}), ("b", J.arr([n("1"), n("2")]))]), J.arr([s("p"), s("q")]), s("end")])), ("grid", J.arr([J.arr([n("1"), n("2")]), J.arr([n("3")]), J.arr([])])), ("lead", J.arr([J.obj([("u", J.arr([J.obj([("id", n("1"))]), J.obj([("id", n("2"))])])), ("note", s("n"))])]))])

# Strings that need quotes, strings that do not, and unicode.
def g.strings() -> J.Json:
  J.obj([("a", s("café 🚀")), ("b", s(" padded ")), ("c", s("- item")), ("d", s("[5]: x")), ("e", s("true")), ("f", s("05")), ("g", s("1e-6")), ("h", s("x\ty\nz")), ("i", s("say \"hi\"")), ("j", s("back\\slash")), ("k", s("hello world")), ("l", s("a-b")), ("m", s(""))])

# Canonical number forms.
def g.numbers() -> J.Json:
  J.obj([("n", J.arr([n("0"), n("-1"), n("3.14"), n("1000000"), n("1e-7"), n("1e+21"), n("9007199254740991"), n("0.000001"), n("-0.5")]))])

# Empty containers everywhere.
def g.empties() -> J.Json:
  J.obj([("o", J.obj([])), ("a", J.arr([])), ("n", J.obj([("p", J.obj([])), ("q", J.arr([]))])), ("l", J.arr([J.obj([]), J.arr([]), J.obj([("z", J.obj([]))])]))])

# Keys that need quotes.
def g.keys() -> J.Json:
  J.obj([("full name", n("1")), ("a:b", n("2")), ("", n("3")), ("1x", n("4")), ("-lead", n("5")), ("[i]", n("6")), ("dot.ted", n("7")), ("t", J.arr([J.obj([("order:id", n("1")), ("x y", n("2"))]), J.obj([("order:id", n("3")), ("x y", n("4"))])]))])

# A root array of uniform objects.
def g.root_tab() -> J.Json:
  J.arr([J.obj([("id", n("1")), ("ok", J.JBool{True{}})]), J.obj([("id", n("2")), ("ok", J.JBool{False{}})])])

# A root array that mixes everything.
def g.root_mixed() -> J.Json:
  J.arr([s("summary"), J.obj([("id", n("1")), ("name", s("Ada"))]), J.arr([J.obj([("id", n("2"))]), J.obj([("status", s("draft"))])])])
