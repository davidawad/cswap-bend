import Base
import ./fs.bend as Fs

# `do Act<A>:` blocks: an IO step that can fail with Fs's `(code, message)`.
# `x : T <- step` stops the block at the first Fail. A binder cannot be used
# twice: rebind it with `+y : T = x` first.

def of(-A: Type) -> Type:
  IO(Fs.Res(A))

def pure(-A: Type, x: A) -> of(A):
  IO.pure(Fs.Res(A), Done{x})

def fail(-A: Type, code: U32, msg: String) -> of(A):
  IO.pure(Fs.Res(A), Fail{(code, msg)})

def step(-A: Type, -B: Type, r: Fs.Res(A), f: A -> of(B)) -> of(B):
  match r:
    case Fail{e}:
      IO.pure(Fs.Res(B), Fail{e})
    case Done{a}:
      f(a)

def bind(-A: Type, -B: Type, m: of(A), f: A -> of(B)) -> of(B):
  IO.bind(Fs.Res(A), Fs.Res(B), m, r => step(A, B, r, f))

# Lift a plain IO value.
def lift(-A: Type, m: IO(A)) -> of(A):
  IO.bind(A, Fs.Res(A), m, x => IO.pure(Fs.Res(A), Done{x}))

# Run `act` whatever `m` answered with, after it: for cleanup.
def finally(-A: Type, act: of(A), cleanup: of(Unit)) -> of(A):
  IO.bind(Fs.Res(A), Fs.Res(A), act, r => IO.bind(Fs.Res(Unit), Fs.Res(A), cleanup, c => IO.pure(Fs.Res(A), r)))

# a when `c`, else b.
def cond(-A: Type, c: Bool, a: of(A), b: of(A)) -> of(A):
  match c:
    case True{}:
      a
    case False{}:
      b

# Fail with (code, msg) unless `ok`.
def guard(ok: Bool, code: U32, msg: String) -> of(Unit):
  match ok:
    case True{}:
      pure(Unit, Unit{})
    case False{}:
      fail(Unit, code, msg)

def on_fail2(-A: Type, r: Fs.Res(A), cleanup: of(Unit)) -> of(A):
  match r:
    case Done{x}:
      IO.pure(Fs.Res(A), Done{x})
    case Fail{e}:
      IO.bind(Fs.Res(Unit), Fs.Res(A), cleanup, c => IO.pure(Fs.Res(A), Fail{e}))

# Run `cleanup` only when `act` failed, and still answer the failure.
def on_fail(-A: Type, act: of(A), cleanup: of(Unit)) -> of(A):
  IO.bind(Fs.Res(A), Fs.Res(A), act, r => on_fail2(A, r, cleanup))
