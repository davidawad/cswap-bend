import Base

# The global options taken off a command line before the verb sees it:
# `--format NAME` (or `--format=NAME`), `--no-input` (never read standard
# input: a prompt becomes an error) and `--yes` (answer a confirmation).
# `config import` and `profile import` keep `--format`: there it names the
# format of the input file.

type G is Data:
  G{rest: List<&2, String>, fmt: Maybe<&2, String>, noin: Bool, yes: Bool, err: String, pending: Bool}

def start() -> G:
  G{[], None{}, False{}, False{}, "", False{}}

def with_fmt(+g: G, +v: String) -> G:
  match g:
    case G{rest, fmt, noin, yes, err, p}:
      G{rest, Some{v}, noin, yes, err, False{}}

def pend(+g: G) -> G:
  match g:
    case G{rest, fmt, noin, yes, err, p}:
      G{rest, fmt, noin, yes, err, True{}}

def with_noin(+g: G) -> G:
  match g:
    case G{rest, fmt, noin, yes, err, p}:
      G{rest, fmt, True{}, yes, err, p}

def with_yes(+g: G) -> G:
  match g:
    case G{rest, fmt, noin, yes, err, p}:
      G{rest, fmt, noin, True{}, err, p}

def keep(+h: String, +g: G) -> G:
  match g:
    case G{rest, fmt, noin, yes, err, p}:
      G{h <> rest, fmt, noin, yes, err, p}

def is_pending(+g: G) -> Bool:
  match g:
    case G{rest, fmt, noin, yes, err, p}:
      p

def sel.g(c: Bool, +a: G, +b: G) -> G:
  match c:
    case True{}:
      a
    case False{}:
      b

def free(+keep_fmt: Bool, +h: String, +g: G) -> G:
  sel.g(Bool.not(keep_fmt) && String.eq(h, "--format"), pend(g),
  sel.g(Bool.not(keep_fmt) && String.starts_with(h, "--format="), with_fmt(g, String.drop(h, 9n)),
  sel.g(String.eq(h, "--no-input"), with_noin(g),
  sel.g(String.eq(h, "--yes"), with_yes(g),
  keep(h, g)))))

def step(+keep_fmt: Bool, +h: String, +g: G) -> G:
  sel.g(is_pending(g), with_fmt(g, h), free(keep_fmt, h, g))

def go(+keep_fmt: Bool, args: List<&2, String>, +g: G) -> G:
  match args:
    case Nil{}:
      g
    case Con{h, t}:
      go(keep_fmt, t, step(keep_fmt, h, g))

def end2(+g: G) -> G:
  match g:
    case G{rest, fmt, noin, yes, err, p}:
      G{List.reverse(&2, String, rest), fmt, noin, yes, Bool.pick(String, p, "argument --format: expected one argument", err), False{}}

# The words left, the format name given, and the two switches. `keep_fmt`:
# leave `--format` where it is.
def split(+keep_fmt: Bool, args: List<&2, String>) -> G:
  end2(go(keep_fmt, args, start()))
