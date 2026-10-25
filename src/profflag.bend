import Base

# `--profile NAME` (or `--profile=NAME`) taken off a command line, for
# `cswap switch` (src/main.bend) and `cswap auto` (src/daemon/entry.bend).

# What is left of the words after `switch` once `--profile NAME` (or
# `--profile=NAME`) is taken off, the name, and a usage error if the flag had
# no value. `pending`: the last word was `--profile`.
type Split is Data:
  Split{rest: List<&2, String>, over: Maybe<&2, String>, err: String, pending: Bool}

def split.with_over(+h: String, +s: Split) -> Split:
  match s:
    case Split{rest, over, err, p}:
      Split{rest, Some{h}, err, False{}}

def split.set_pending(+s: Split) -> Split:
  match s:
    case Split{rest, over, err, p}:
      Split{rest, over, err, True{}}

def split.keep(+h: String, +s: Split) -> Split:
  match s:
    case Split{rest, over, err, p}:
      Split{h <> rest, over, err, False{}}

def split.eq_form(+is_eq: Bool, +h: String, +s: Split) -> Split:
  match is_eq:
    case True{}:
      split.with_over(String.drop(h, 10n), s)
    case False{}:
      split.keep(h, s)

def split.flag(+is_flag: Bool, +is_eq: Bool, +h: String, +s: Split) -> Split:
  match is_flag:
    case True{}:
      split.set_pending(s)
    case False{}:
      split.eq_form(is_eq, h, s)

def split.step2(+pending: Bool, +is_flag: Bool, +is_eq: Bool, +h: String, +s: Split) -> Split:
  match pending:
    case True{}:
      split.with_over(h, s)
    case False{}:
      split.flag(is_flag, is_eq, h, s)

def split.pending(+s: Split) -> Bool:
  match s:
    case Split{rest, over, err, pending}:
      pending

def split.step(+h: String, +s: Split) -> Split:
  split.step2(split.pending(s), String.eq(h, "--profile"), String.starts_with(h, "--profile="), h, s)

def split.go(+args: List<&2, String>, +s: Split) -> Split:
  match args:
    case Nil{}:
      s
    case Con{h, t}:
      split.go(t, split.step(h, s))

def split.end2(+pending: Bool, +rest: List<&2, String>, +over: Maybe<&2, String>, +err: String) -> Split:
  match pending:
    case True{}:
      Split{List.reverse(&2, String, rest), over, "argument --profile: expected one argument", False{}}
    case False{}:
      Split{List.reverse(&2, String, rest), over, err, False{}}

def split.end(+s: Split) -> Split:
  match s:
    case Split{rest, over, err, pending}:
      split.end2(pending, rest, over, err)

def split(+args: List<&2, String>) -> Split:
  split.end(split.go(args, Split{[], None{}, "", False{}}))
