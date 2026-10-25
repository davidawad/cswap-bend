import Base
import ../fs.bend as Fs
import ../fs/write.bend as FsW
import ../act.bend as Act
import ../lock.bend as Lock

# One decider per backup root: `cswap auto` holds an exclusive flock on
# <state>/daemon.lock for as long as it runs (the kernel drops it if the
# process dies) and writes its pid to <state>/daemon.pid. A second `auto` on
# the same root refuses with a message naming the holder.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def lock_path(+state_dir: String) -> String:
  state_dir ++ "/daemon.lock"

def pid_path(+state_dir: String) -> String:
  state_dir ++ "/daemon.pid"

def pid_of(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> U32:
  match r:
    case Fail{e}:
      0
    case Done{(st, (out, err))}:
      Maybe.default(&2, U32, U32.read(String.trim(out)), 0)

# This process's pid: the parent of a child shell (Bend has no getpid).
def my_pid() -> IO(U32):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, U32, Process.run("/bin/sh", ["-c", "echo $PPID"], "", 64, 5000), r => IO.pure(U32, pid_of(r)))

def holder_text(r: Fs.Res(String)) -> String:
  match r:
    case Done{t}:
      String.trim(t)
    case Fail{e}:
      "unknown"

def busy_msg(+state_dir: String, +holder: String) -> String:
  "Another `cswap auto` is already running on this backup root (pid " ++ holder ++ "; " ++ lock_path(state_dir) ++ " is locked). Only one decider may run: stop it first."

def busy_fail(-A: Type, +state_dir: String) -> Act.of(A):
  IO.bind(Fs.Res(String), Fs.Res(A), Fs.read_file(pid_path(state_dir)), r => IO.pure(Fs.Res(A), Fail{(11, busy_msg(state_dir, holder_text(r)))}))

def claim(+state_dir: String) -> Act.of(Unit):
  do ActM<Unit>:
    pid : U32 <- Act.lift(U32, my_pid())
    FsW.write_atomic(pid_path(state_dir), U32.show(pid) ++ "\n", "600")

def give_back(+state_dir: String, f: File) -> Act.of(Unit):
  do ActM<Unit>:
    Act.lift(Unit, Lock.release(f))
    FsW.remove(pid_path(state_dir))

def run_held(-A: Type, +state_dir: String, f: File, c: Fs.Res(Unit), act: Act.of(A)) -> Act.of(A):
  match c:
    case Fail{e}:
      IO.bind(Unit, Fs.Res(A), Lock.release(f), u => IO.pure(Fs.Res(A), Fail{e}))
    case Done{u}:
      Act.finally(A, act, give_back(state_dir, f))

def held(-A: Type, +state_dir: String, m: Maybe<&1, File>, act: Act.of(A)) -> Act.of(A):
  match m:
    case None{}:
      busy_fail(A, state_dir)
    case Some{f}:
      IO.bind(Fs.Res(Unit), Fs.Res(A), claim(state_dir), c => run_held(A, state_dir, f, c, act))

# Run `act` as the one decider of this state dir. A second caller gets
# Fail{(11, "Another `cswap auto` is already running ...")} and `act` never starts.
def with_pidlock(-A: Type, +state_dir: String, act: Act.of(A)) -> Act.of(A):
  do ActM<A>:
    FsW.mkdir_p(state_dir)
    m : Maybe<&1, File> <- Lock.acquire(lock_path(state_dir), 0)
    held(A, state_dir, m, act)
