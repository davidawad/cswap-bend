import Base
import ./head.bend as Hd

# Source text to numbered lines with their depth (spec section 12).

type DL is Data:
  DL{no: U32, depth: U32, text: String, blank: Bool}

# Leading spaces and tabs counted, and what follows them.
type Ld is Data:
  Ld{sp: U32, tabs: U32, rest: String}

def lead.pick(+go: Bool, +s: String, +sp: U32, +tabs: U32, +r: Ld) -> Ld:
  match go:
    case True{}:
      r
    case False{}:
      Ld{sp, tabs, s}

def inc(+b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

# Count the leading spaces and tabs. `live` is true until the first other
# character; the recursion runs to the end of the line but only counts
# while live.
def lead(+s: String, +sp: U32, +tabs: U32, +live: Bool) -> Ld:
  match s:
    case SNil{}:
      Ld{sp, tabs, s}
    case SCon{Chr{c}, t}:
      lead.pick(live && (U32.is_eq(c, 32) || U32.is_eq(c, 9)), s, sp, tabs,
        lead(t, (sp + inc(live && U32.is_eq(c, 32)) : U32), (tabs + inc(live && U32.is_eq(c, 9)) : U32), live && (U32.is_eq(c, 32) || U32.is_eq(c, 9))))

def at(+no: U32, +m: String) -> String:
  "line " ++ U32.show(no) ++ ": " ++ m

def blank(+no: U32) -> Result<&2, &2, String, DL>:
  Done{DL{no, 0, SNil{}, True{}}}

# Depth is spaces divided by the indent size. Strict mode refuses tabs in the
# indentation and a count that is not a multiple. Lenient mode floors the
# count and reads each leading tab as one indent level.
def depth.pick(+bad_tab: Bool, +bad_mult: Bool, +no: U32, +depth: U32, +text: String) -> Result<&2, &2, String, DL>:
  match bad_tab bad_mult:
    case True{} _:
      Fail{at(no, "tabs are not allowed in indentation")}
    case False{} True{}:
      Fail{at(no, "indentation is not a multiple of the indent size")}
    case False{} False{}:
      Done{DL{no, depth, text, False{}}}

def make.nonblank(+no: U32, +l: Ld, +size: U32, +strict: Bool) -> Result<&2, &2, String, DL>:
  match l:
    case Ld{sp, tabs, rest}:
      depth.pick(strict && Bool.not(U32.is_zero(tabs)), strict && Bool.not(U32.is_zero(U32.mod(sp, size)) ), no,
        (U32.div(sp, size) + tabs : U32), String.trim_end(rest))

def make.pick(+isblank: Bool, +no: U32, +l: Ld, +size: U32, +strict: Bool) -> Result<&2, &2, String, DL>:
  match isblank:
    case True{}:
      blank(no)
    case False{}:
      make.nonblank(no, l, size, strict)

def make.of(+no: U32, +l: Ld, +size: U32, +strict: Bool) -> Result<&2, &2, String, DL>:
  match l:
    case Ld{sp, tabs, rest}:
      make.pick(String.is_empty(String.trim(rest)), no, Ld{sp, tabs, rest}, size, strict)

def make(+no: U32, +line: String, +size: U32, +strict: Bool) -> Result<&2, &2, String, DL>:
  make.of(no, lead(line, 0, 0, True{}), size, strict)

def prep.cons(+r: Result<&2, &2, String, DL>, +rest: Result<&2, &2, String, List<&2, DL>>) -> Result<&2, &2, String, List<&2, DL>>:
  match r rest:
    case Done{l} Done{ls}:
      Done{Con{l, ls}}
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

def prep.go(+lines: List<&2, String>, +no: U32, +size: U32, +strict: Bool) -> Result<&2, &2, String, List<&2, DL>>:
  match lines:
    case Nil{}:
      Done{Nil{}}
    case Con{l, rest}:
      prep.cons(make(no, l, size, strict), prep.go(rest, (no + 1 : U32), size, strict))

def size.of(+n: U32) -> U32:
  U32.max(n, 1)

# Split on LF and number the lines from 1.
def prep(+src: String, +size: U32, +strict: Bool) -> Result<&2, &2, String, List<&2, DL>>:
  prep.go(String.lines(src), 1, size.of(size), strict)
