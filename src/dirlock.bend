import Base
import ./fs.bend as Fs
import ./act.bend as Act
import ./clock.bend as Clock
import ./fs/write.bend as FsW

# Directory locks, the npm proper-lockfile protocol Claude Code uses for its
# credential and config files (contract 1.8): `mkdir` takes the lock, `rmdir`
# releases it, and a lock whose mtime is older than `staleness` seconds is
# taken over. cswap holds these for well under a second (and never across the
# post-switch verification delay), so the reference's 3 s touch thread has
# nothing to keep alive and is not run.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

# Modification time of a path in whole seconds.
def Dirlock.mtime(+path: String) -> IO(Result<&1, &1, U32 & String, U32>):
  import "./effs/mtime.c"
  import "./effs/mtime.js"

def poll_ms() -> U32:
  250

def mkdir_ok(r: Fs.Res(String)) -> Fs.Res(Bool):
  match r:
    case Fail{e}:
      Done{False{}}
    case Done{out}:
      Done{True{}}

# One attempt: mkdir without -p, so it fails while the lock is held.
def take_once(+dir: String) -> Act.of(Bool):
  IO.bind(Fs.Res(String), Fs.Res(Bool), Fs.tool("/bin/mkdir", [dir]), r => IO.pure(Fs.Res(Bool), mkdir_ok(r)))

def stale_of(m: Result<&1, &1, U32 & String, U32>, +now: U32, +staleness: U32) -> Bool:
  match m:
    case Fail{e}:
      False{}
    case Done{t}:
      U32.is_gt(now, (t + staleness : U32))

def is_stale(+dir: String, +staleness: U32) -> Act.of(Bool):
  do ActM<Bool>:
    now : U32 <- Act.lift(U32, Clock.now_s())
    m : Result<&1, &1, U32 & String, U32> <- Act.lift(Result<&1, &1, U32 & String, U32>, Dirlock.mtime(dir))
    return stale_of(m, now, staleness)

def reclaim(+stale: Bool, +dir: String) -> Act.of(Unit):
  Act.cond(Unit, stale, Fs.tool_unit("/bin/rmdir", [dir]), Act.pure(Unit, Unit{}))

def basename(+p: String) -> String:
  Maybe.default(&2, String, List.last(&2, String, String.split(p, '/')), p)

def busy_msg(+dir: String) -> String:
  "Could not acquire " ++ basename(dir) ++ " — Claude Code appears to be refreshing credentials. Retry in a few seconds."

# Take over a stale lock, wait a beat, try again.
def retake(+dir: String, +staleness: U32) -> Act.of(Bool):
  do ActM<Bool>:
    st : Bool <- is_stale(dir, staleness)
    reclaim(st, dir)
    Act.lift(Unit, IO.sleep(poll_ms()))
    take_once(dir)

# Wait for the lock `fuel` more times, taking over a stale one.
def wait(+fuel: Nat, +dir: String, +staleness: U32, +got: Bool) -> Act.of(Unit):
  match fuel got:
    case _ True{}:
      Act.pure(Unit, Unit{})
    case 0n False{}:
      Act.fail(Unit, 4, busy_msg(dir))
    case 1n++p False{}:
      do ActM<Unit>:
        again : Bool <- retake(dir, staleness)
        wait(p, dir, staleness, again)

def tries(+timeout_ms: U32) -> Nat:
  U32.to_nat((timeout_ms / poll_ms() : U32))

# Take the lock at `dir` (its parent is created), waiting up to `timeout_ms`.
def take(+dir: String, +timeout_ms: U32, +staleness: U32) -> Act.of(Unit):
  do ActM<Unit>:
    FsW.mkdir_p(Fs.dirname(dir))
    first : Bool <- take_once(dir)
    wait(tries(timeout_ms), dir, staleness, first)

def release(+dir: String) -> Act.of(Unit):
  IO.bind(Fs.Res(Unit), Fs.Res(Unit), Fs.tool_unit("/bin/rmdir", [dir]), r => IO.pure(Fs.Res(Unit), Done{Unit{}}))

# Hold the directory lock around `act`, released whatever `act` answers.
def with_dirlock(-A: Type, +dir: String, +timeout_ms: U32, +staleness: U32, act: Act.of(A)) -> Act.of(A):
  do ActM<A>:
    take(dir, timeout_ms, staleness)
    Act.finally(A, act, release(dir))
