import Base

# Message framing for `cswap rpc` and `cswap serve`: a JSON message is one
# line; a YAML or TOON message is a block of lines ended by a blank line.
# `take` cuts the first complete message off a buffer. Pure.

type Cut is Data:
  Cut{msg: String, rest: String}

def nl.pick(hit: Bool, n: Nat, rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{n}
    case False{}:
      rest

# Index of the first LF.
def nl.find(s: String, +n: Nat) -> Maybe<&2, Nat>:
  match s:
    case SNil{}:
      None{}
    case SCon{Chr{+c}, t}:
      nl.pick(U32.is_eq(c, 10), n, nl.find(t, Nat.add(n, 1n)))

# Index of the LF that ends a blank line: an LF whose previous line break was
# an LF too (CR before either is ignored). `prev`: the last significant
# character was an LF (true at the start, so leading blank lines are cut).
def blank.find(s: String, +n: Nat, +prev: Bool) -> Maybe<&2, Nat>:
  match s:
    case SNil{}:
      None{}
    case SCon{Chr{+c}, t}:
      nl.pick(prev && U32.is_eq(c, 10), n, blank.find(t, Nat.add(n, 1n), Bool.pick(Bool, U32.is_eq(c, 13), prev, U32.is_eq(c, 10))))

def cut.at(m: Maybe<&2, Nat>, +s: String) -> Maybe<&2, Cut>:
  match m:
    case None{}:
      None{}
    case Some{+n}:
      Some{Cut{String.take(s, n), String.drop(s, Nat.add(n, 1n))}}

# The first message of `buf` (json: a line; block: up to a blank line) and the
# rest, none while the message is incomplete.
def take(block: Bool, +buf: String) -> Maybe<&2, Cut>:
  match block:
    case True{}:
      cut.at(blank.find(buf, 0n, True{}), buf)
    case False{}:
      cut.at(nl.find(buf, 0n), buf)

# Is there anything but white space?
def blank(+s: String) -> Bool:
  String.is_empty(String.trim(s))
