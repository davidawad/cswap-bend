import Base

# Quote-aware scanning of a line (spec appendix B.3): where the first unquoted
# colon or delimiter is, and how to cut a row on its delimiter.

# Scanner state: 0 outside quotes, 1 inside, 2 inside after a backslash.
def sel.u(+b: Bool, +x: U32, +y: U32) -> U32:
  match b:
    case True{}:
      x
    case False{}:
      y

def qnext.pick(+st: U32, +quote: Bool, +bslash: Bool) -> U32:
  sel.u(U32.is_eq(st, 0), sel.u(quote, 1, 0),
  sel.u(U32.is_eq(st, 1), sel.u(bslash, 2, sel.u(quote, 0, 1)), 1))

def qnext(+st: U32, +c: U32) -> U32:
  qnext.pick(st, U32.is_eq(c, 34), U32.is_eq(c, 92))

# Sentinel index for "not found".
def none() -> U32:
  4294967295

def found(+hit: Bool, +i: U32, +later: U32) -> U32:
  sel.u(hit, i, later)

# Index of the first `target` outside quotes, or `none()`.
def find_unq(+s: String, +target: U32, +st: U32, +i: U32) -> U32:
  match s:
    case SNil{}:
      none()
    case SCon{Chr{c}, t}:
      found(U32.is_eq(st, 0) && U32.is_eq(c, target), i, find_unq(t, target, qnext(st, c), (i + 1 : U32)))

# Put a character in front of the token being built, or start a new token.
def split.put(+c: U32, +sep: Bool, +r: List<&2, String>) -> List<&2, String>:
  match sep:
    case True{}:
      Con{SNil{}, r}
    case False{}:
      match r:
        case Con{h, rest}:
          Con{SCon{Chr{c}, h}, rest}
        case Nil{}:
          Nil{}

def split.go(+s: String, +d: U32, +st: U32) -> List<&2, String>:
  match s:
    case SNil{}:
      Con{SNil{}, Nil{}}
    case SCon{Chr{c}, t}:
      split.put(c, U32.is_eq(st, 0) && U32.is_eq(c, d), split.go(t, d, qnext(st, c)))

# Cut on the delimiter `d` outside quotes. Always at least one token.
def split(+s: String, +d: U32) -> List<&2, String>:
  split.go(s, d, 0)

# Index of the first `target`, ignoring quotes, or `none()`.
def find(+s: String, +target: U32, +i: U32) -> U32:
  match s:
    case SNil{}:
      none()
    case SCon{Chr{c}, t}:
      found(U32.is_eq(c, target), i, find(t, target, (i + 1 : U32)))
