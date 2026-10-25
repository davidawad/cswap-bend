import Base

# What the encoder builds for one value, before it knows where the value sits.
#
# A line is a depth relative to the value and its text. A parent turns the
# reps of its children into its own lines by shifting them, so the encoder
# needs no running depth and recurses on Json alone.

type Ln is Data:
  Ln{d: U32, t: String}

type Rep is Data:
  # A primitive: its text.
  RPrim{t: String}
  # An object (field lines) or a chain of list items: lines at relative depth 0.
  RLines{ls: List<&2, Ln>}
  # A non-empty array: the text after the key (`[2]: a,b`, `[2]{a,b}:`,
  # `[2]:`) and the lines beneath the header, already at depth 1 and deeper.
  RArr{h: String, ks: List<&2, Ln>}
  # An empty array.
  REmpty{}

def shift(+ls: List<&2, Ln>) -> List<&2, Ln>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{Ln{d, t}, rest}:
      Con{Ln{(d + 1 : U32), t}, shift(rest)}

def lines.of(+r: Rep) -> List<&2, Ln>:
  match r:
    case RLines{ls}:
      ls
    case _:
      Nil{}

def cat(+a: List<&2, Ln>, +b: List<&2, Ln>) -> List<&2, Ln>:
  match a:
    case Nil{}:
      b
    case Con{h, t}:
      Con{h, cat(t, b)}

def one(+d: U32, +t: String) -> List<&2, Ln>:
  Con{Ln{d, t}, Nil{}}

# Lines of `key: value` for any value rep.
def field(+k: String, +r: Rep) -> List<&2, Ln>:
  match r:
    case RPrim{t}:
      one(0, k ++ ": " ++ t)
    case RLines{ls}:
      Con{Ln{0, k ++ ":"}, shift(ls)}
    case RArr{h, ks}:
      Con{Ln{0, k ++ h}, ks}
    case REmpty{}:
      one(0, k ++ ": []")

# The first line of an object item rides on the hyphen line; the rest sit one
# level under it.
def item.obj(+ls: List<&2, Ln>) -> List<&2, Ln>:
  match ls:
    case Nil{}:
      one(0, "-")
    case Con{Ln{d, t}, rest}:
      Con{Ln{0, "- " ++ t}, shift(rest)}

# Lines of `- value` for any value rep.
def item(+r: Rep) -> List<&2, Ln>:
  match r:
    case RPrim{t}:
      one(0, "- " ++ t)
    case RLines{ls}:
      item.obj(ls)
    case RArr{h, ks}:
      Con{Ln{0, "- " ++ h}, ks}
    case REmpty{}:
      one(0, "- [0]:")

# Lines of a whole document.
def root(+r: Rep) -> List<&2, Ln>:
  match r:
    case RPrim{t}:
      one(0, t)
    case RLines{ls}:
      ls
    case RArr{h, ks}:
      Con{Ln{0, h}, ks}
    case REmpty{}:
      one(0, "[]")

def indent.of(+size: U32, +d: U32) -> String:
  String.repeat(" ", U32.to_nat((size * d : U32)))

def render.line(+size: U32, +l: Ln) -> String:
  match l:
    case Ln{d, t}:
      indent.of(size, d) ++ t

def render.tail(+size: U32, +ls: List<&2, Ln>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{l, rest}:
      "\n" ++ render.line(size, l) ++ render.tail(size, rest)

# Join lines with LF; no trailing newline.
def render(+size: U32, +ls: List<&2, Ln>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{l, rest}:
      render.line(size, l) ++ render.tail(size, rest)
