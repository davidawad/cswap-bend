import Base
import ./fs.bend as Fs
import ./fs/write.bend as FsW

# An exclusive advisory lock that interoperates with the Python cswap's
# locking.py: flock(LOCK_EX) on a file opened for writing at the same path,
# so both implementations can run side by side. The lock belongs to the open
# file; closing the File (release) drops it, and so does the process dying.
#
# Like the reference, a held lock is polled every 100 ms (LOCK_NB) until the
# timeout passes, because a blocking flock could not be given up on.

# One LOCK_EX|LOCK_NB attempt on the File's descriptor: Done{1} held, Done{0}
# someone else holds it. The File comes back beside the answer.
def Flock.try(file: File) -> IO(File & Result<&1, &1, U32 & String, U32>):
  import "./effs/flock.c"
  import "./effs/flock.js"

def poll_ms() -> U32:
  100

def tried.bool(r: Fs.Res(U32)) -> Fs.Res(Bool):
  match r:
    case Fail{e}:
      Fail{e}
    case Done{n}:
      Done{U32.is_eq(n, 1)}

def tried(fr: File & Fs.Res(U32)) -> IO(File & Fs.Res(Bool)):
  (f, r) = fr
  IO.pure(File & Fs.Res(Bool), (f, tried.bool(r)))

# One attempt, as a Bool.
def attempt(f: File) -> IO(File & Fs.Res(Bool)):
  IO.bind(File & Fs.Res(U32), File & Fs.Res(Bool), Flock.try(f), tried)

# Retry `fuel` more times, 100 ms apart, until the lock is held.
def wait(fuel: Nat, fr: File & Fs.Res(Bool)) -> IO(File & Fs.Res(Bool)):
  match fuel fr:
    case 1n++p Tuple{f, Done{False{}}}:
      IO.bind(Unit, File & Fs.Res(Bool), IO.sleep(poll_ms()),
        u => IO.bind(File & Fs.Res(Bool), File & Fs.Res(Bool), attempt(f), r => wait(p, r)))
    case _ _:
      IO.pure(File & Fs.Res(Bool), fr)

def held.pick(f: File, r: Fs.Res(Bool)) -> IO(Fs.Res(Maybe<&1, File>)):
  match r:
    case Fail{e}:
      IO.bind(Unit, Fs.Res(Maybe<&1, File>), File.close(f), u => IO.pure(Fs.Res(Maybe<&1, File>), Fail{e}))
    case Done{True{}}:
      IO.pure(Fs.Res(Maybe<&1, File>), Done{Some{f}})
    case Done{False{}}:
      IO.bind(Unit, Fs.Res(Maybe<&1, File>), File.close(f), u => IO.pure(Fs.Res(Maybe<&1, File>), Done{None{}}))

def held.fin(fr: File & Fs.Res(Bool)) -> IO(Fs.Res(Maybe<&1, File>)):
  (f, r) = fr
  held.pick(f, r)

# Attempts that fit in the timeout: the first one, then one per 100 ms.
def tries(timeout_ms: U32) -> Nat:
  U32.to_nat((timeout_ms / poll_ms() : U32))

def opened(timeout_ms: U32, r: Fs.Res(File)) -> IO(Fs.Res(Maybe<&1, File>)):
  match r:
    case Fail{e}:
      IO.pure(Fs.Res(Maybe<&1, File>), Fail{e})
    case Done{f}:
      IO.bind(File & Fs.Res(Bool), Fs.Res(Maybe<&1, File>),
        IO.bind(File & Fs.Res(Bool), File & Fs.Res(Bool), attempt(f), r1 => wait(tries(timeout_ms), r1)),
        held.fin)

def parent.ok(r: Fs.Res(Unit), timeout_ms: U32, path: String) -> IO(Fs.Res(Maybe<&1, File>)):
  match r:
    case Fail{e}:
      IO.pure(Fs.Res(Maybe<&1, File>), Fail{e})
    case Done{u}:
      IO.bind(Fs.Res(File), Fs.Res(Maybe<&1, File>), File.open(path, "w"), g => opened(timeout_ms, g))

# Take the lock at `path`, waiting up to `timeout_ms`. Done{Some{file}} holds
# it (pass the file to `release`); Done{None} means the wait timed out.
# Creates missing parent directories and truncates the lock file, as the
# reference does.
def acquire(+path: String, timeout_ms: U32) -> IO(Fs.Res(Maybe<&1, File>)):
  IO.bind(Fs.Res(Unit), Fs.Res(Maybe<&1, File>), FsW.mkdir_p(Fs.dirname(path)),
    r => parent.ok(r, timeout_ms, path))

# Drop the lock.
def release(f: File) -> IO(Unit):
  File.close(f)

def busy() -> Fs.Res(Unit):
  Fail{(11, "Failed to acquire lock - another instance may be running")}

def done.close(-A: Type, r: Fs.Res(A), f: File) -> IO(Fs.Res(A)):
  IO.bind(Unit, Fs.Res(A), File.close(f), u => IO.pure(Fs.Res(A), r))

def held.run(-A: Type, act: IO(Fs.Res(A)), m: Fs.Res(Maybe<&1, File>)) -> IO(Fs.Res(A)):
  match m:
    case Fail{e}:
      IO.pure(Fs.Res(A), Fail{e})
    case Done{None{}}:
      IO.pure(Fs.Res(A), Fail{(11, "Failed to acquire lock - another instance may be running")})
    case Done{Some{f}}:
      IO.bind(Fs.Res(A), Fs.Res(A), act, r => done.close(A, r, f))

# Run `act` while holding the lock; the lock is released afterwards whatever
# `act` answers. A timeout is Fail{(11, "Failed to acquire lock ...")}.
def with_lock(-A: Type, path: String, timeout_ms: U32, act: IO(Fs.Res(A))) -> IO(Fs.Res(A)):
  IO.bind(Fs.Res(Maybe<&1, File>), Fs.Res(A), acquire(path, timeout_ms), m => held.run(A, act, m))

