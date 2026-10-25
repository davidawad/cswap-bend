import Base

# Looking at the front of a string without matching on character codes
# (a numeric pattern expands to a match per bit, which the linter counts).

# Is the first character the code point `c`?
def lead(+s: String, +c: U32) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{x}, t}:
      U32.is_eq(x, c)

# Without the first character.
def drop(+s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{h, t}:
      t

# Are the first two characters `a` then `b`?
def lead2(+s: String, +a: U32, +b: U32) -> Bool:
  lead(s, a) && lead(drop(s), b)

# Has the string at least `n` characters?
def at_least(+s: String, +n: Nat) -> Bool:
  match s n:
    case _ 0n:
      True{}
    case SNil{} _:
      False{}
    case SCon{h, t} 1n+p:
      at_least(t, p)

# ---- quoted-key marker -------------------------------------------------------
#
# The decoder prefixes a key that was written in quotes with one character that
# no text holds (code 4294967295, beyond U+10FFFF), so path expansion can tell
# `"a.b"` (literal) from `a.b` (a path). Markers never leave the decoder.

def mark() -> String:
  SCon{Chr{4294967295}, SNil{}}

def marked(+k: String) -> Bool:
  lead(k, 4294967295)

def unmark.pick(+m: Bool, +k: String) -> String:
  match m:
    case True{}:
      drop(k)
    case False{}:
      k

# The key without its marker.
def unmark(+k: String) -> String:
  unmark.pick(marked(k), k)

# Same key, ignoring markers.
def keq(+a: String, +b: String) -> Bool:
  String.eq(unmark(a), unmark(b))
