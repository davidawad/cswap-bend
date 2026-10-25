import Base
import ../../src/lock.bend as Lock
import ../../src/fs.bend as Fs

# A tiny CLI over lock for tests/lock_it.sh:
#   lock-it hold PATH HOLD_MS   take the lock at once, print "held", keep it HOLD_MS, print "released"
#   lock-it try PATH TIMEOUT_MS wait up to TIMEOUT_MS: print "acquired" or "timeout"

def after.hold(ms: U32, r: Fs.Res(Maybe<&1, File>)) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.pass(Unit, Fail{e})
    case Done{None{}}:
      IO.print("timeout")
    case Done{Some{f}}:
      do IO<Unit>:
        IO.print("held")
        IO.sleep(ms)
        Lock.release(f)
        IO.print("released")

def after.try(r: Fs.Res(Maybe<&1, File>)) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.pass(Unit, Fail{e})
    case Done{None{}}:
      IO.print("timeout")
    case Done{Some{f}}:
      do IO<Unit>:
        Lock.release(f)
        IO.print("acquired")

def hold(path: String, ms: U32) -> IO(Unit):
  IO.bind(Fs.Res(Maybe<&1, File>), Unit, Lock.acquire(path, 0), r => after.hold(ms, r))

def try(path: String, ms: U32) -> IO(Unit):
  IO.bind(Fs.Res(Maybe<&1, File>), Unit, Lock.acquire(path, ms), after.try)

def go.pick(is_hold: Bool, path: String, ms: U32) -> IO(Unit):
  match is_hold:
    case True{}:
      hold(path, ms)
    case False{}:
      try(path, ms)

def go(is_hold: Bool, path: String, n: Maybe<&2, U32>) -> IO(Unit):
  match n:
    case None{}:
      IO.die(Unit, 2, "usage: lock-it hold|try PATH MS")
    case Some{ms}:
      go.pick(is_hold, path, ms)

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{cmd, Con{path, Con{ms, Nil{}}}}}:
      go(String.eq(cmd, "hold"), path, U32.read(ms))
    case _:
      IO.die(Unit, 2, "usage: lock-it hold|try PATH MS")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)

