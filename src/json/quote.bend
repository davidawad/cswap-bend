import Base
import ./lex.bend as Lex

def hexd(+n: U32) -> Char:
  Chr{Lex.sel(U32.is_lt(n, 10), (n + 48 : U32), (n + 87 : U32))}

# \uXXXX, lowercase hex as Python writes it.
def uesc(+n: U32) -> String:
  "\\u" ++ SCon{hexd(((n >> 12n) .&. 15 : U32)), SCon{hexd(((n >> 8n) .&. 15 : U32)), SCon{hexd(((n >> 4n) .&. 15 : U32)), SCon{hexd((n .&. 15 : U32)), SNil{}}}}}

def uesc.pair(+c: U32) -> String:
  uesc((55296 + ((c - 65536) >> 10n) : U32)) ++ uesc((56320 + ((c - 65536) .&. 1023) : U32))

def esc.high(ascii: Bool, +c: U32) -> String:
  match ascii:
    case False{}:
      SCon{Chr{c}, SNil{}}
    case True{}:
      Lex.sel.s(U32.is_lt(c, 65536), uesc(c), uesc.pair(c))

def esc.rest(ascii: Bool, +c: U32) -> String:
  Lex.sel.s(U32.is_lt(c, 32), uesc(c),
  Lex.sel.s(U32.is_lt(c, 127), SCon{Chr{c}, SNil{}}, esc.high(ascii, c)))

# One char as Python's encoder writes it inside quotes. ensure_ascii escapes
# everything above `~` (U+007F included); otherwise only controls.
def esc.char(+ascii: Bool, +c: U32) -> String:
  Lex.sel.s(U32.is_eq(c, 34), "\\\"",
  Lex.sel.s(U32.is_eq(c, 92), "\\\\",
  Lex.sel.s(U32.is_eq(c, 10), "\\n",
  Lex.sel.s(U32.is_eq(c, 13), "\\r",
  Lex.sel.s(U32.is_eq(c, 9), "\\t",
  Lex.sel.s(U32.is_eq(c, 8), "\\b",
  Lex.sel.s(U32.is_eq(c, 12), "\\f",
  Lex.sel.s(U32.is_eq(c, 127), Lex.sel.s(ascii, uesc(127), SCon{Chr{127}, SNil{}}), esc.rest(ascii, c)))))))))

def quote.body(s: String, +ascii: Bool) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{c}, t}:
      esc.char(ascii, c) ++ quote.body(t, ascii)

# `"text"` with escapes.
def quote(s: String, ascii: Bool) -> String:
  "\"" ++ quote.body(s, ascii) ++ "\""

# style 0: compact `,` `:`; 1: Python's default `, ` `: `; 2: indent=2.
def indent(d: Nat) -> String:
  String.repeat("  ", d)

def nl(style: U32, d: Nat) -> String:
  Lex.sel.s(U32.is_eq(style, 2), "\n" ++ indent(d), "")

def sep(+style: U32, d: Nat) -> String:
  Lex.sel.s(U32.is_eq(style, 0), ",", Lex.sel.s(U32.is_eq(style, 1), ", ", ",\n" ++ indent(d)))

def colon(+style: U32) -> String:
  Lex.sel.s(U32.is_eq(style, 0), ":", ": ")

# Separator between a chain cell and the next: nothing at the end.
