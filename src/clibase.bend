import Base
import ./usage.bend as Usage
import ./clock.bend as Clock
import ./fs.bend as Fs
import ./act.bend as Act
import ./cmd.bend as Cmd

# The cswap command line (cli.py): parse, dispatch, exit codes and output.
# Every command answers a Cmd.Out; main prints it and exits with its code.

def version() -> String:
  "cswap-bend 0.1.0"

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def sel.o(c: Bool, a: Cmd.Out, b: Cmd.Out) -> Cmd.Out:
  match c:
    case True{}:
      a
    case False{}:
      b

# The exception class the reference raises for a store failure code.
def kind_of(+code: U32) -> String:
  Clock.sel.s(U32.is_eq(code, 3), "AccountNotFoundError", Clock.sel.s(U32.is_eq(code, 2), "ValidationError", "ConfigError"))

def fail_out(+json: Bool, ce: U32 & String) -> Cmd.Out:
  (c, m) = ce
  Cmd.failed(json, kind_of(c), m)

def act_out(+json: Bool, r: Fs.Res(Cmd.Out)) -> Cmd.Out:
  match r:
    case Fail{e}:
      fail_out(json, e)
    case Done{o}:
      o

def run_act(+json: Bool, a: Act.of(Cmd.Out)) -> IO(Cmd.Out):
  IO.bind(Fs.Res(Cmd.Out), Cmd.Out, a, r => IO.pure(Cmd.Out, act_out(json, r)))

def done(o: Cmd.Out) -> Act.of(Cmd.Out):
  Act.pure(Cmd.Out, o)

def say(+text: String) -> Act.of(Cmd.Out):
  Act.pure(Cmd.Out, Cmd.ok(text))

def first_line(ls: List<&2, String>) -> String:
  match ls:
    case Con{h, t}:
      h
    case Nil{}:
      ""

def stdin_line2(r: Fs.Res(String)) -> Fs.Res(String):
  match r:
    case Done{t}:
      Done{first_line(String.lines(t))}
    case Fail{e}:
      Done{""}

# One line from standard input ("" at end of input).
def read_line() -> Act.of(String):
  IO.bind(Fs.Res(String), Fs.Res(String), Fs.read_stdin(), r => IO.pure(Fs.Res(String), stdin_line2(r)))

def is_yes(+a: String) -> Bool:
  String.eq(String.to_lower(String.trim(a)), "y") || String.eq(String.to_lower(String.trim(a)), "yes")

def text_out(+t: String) -> Cmd.Out:
  Cmd.ok(t)

def affine(ts: List<&2, String>) -> List<String>:
  match ts:
    case Nil{}:
      []
    case Con{h, t}:
      h <> affine(t)

# The clock and the local UTC offset (seconds), and a tie-breaker for claim ids,
# read once at the start of a command.
type Tm is Data:
  Tm{now: U32, off: U32, tick: Nat}

def times() -> Act.of(Tm):
  do ActM<Tm>:
    now : U32 <- Act.lift(U32, Clock.now_s())
    off : U32 <- Act.lift(U32, Usage.local_offset())
    tick : Nat <- Act.lift(Nat, IO.now())
    return Tm{now, off, tick}
