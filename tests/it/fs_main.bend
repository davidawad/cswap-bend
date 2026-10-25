import Base
import ../../src/fs.bend as Fs
import ../../src/fs/write.bend as FsW

# A tiny CLI over fs for tests/fs_it.sh:
#   fs-it write PATH DATA MODE | read PATH | exists PATH | ls PATH | mkdir PATH | rm PATH

def say.unit(r: Fs.Res(Unit)) -> IO(Unit):
  IO.bind(Unit, Unit, IO.pass(Unit, r), u => IO.print("ok"))

def say.names(ns: List<&2, String>) -> IO(Unit):
  match ns:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      IO.bind(Unit, Unit, IO.print(h), u => say.names(t))

def say.dir(r: Fs.Res(List<&2, String>)) -> IO(Unit):
  IO.bind(List<&2, String>, Unit, IO.pass(List<&2, String>, r), say.names)

def say.text(r: Fs.Res(String)) -> IO(Unit):
  IO.bind(String, Unit, IO.pass(String, r), IO.write)

def say.bool(b: Bool) -> IO(Unit):
  match b:
    case True{}:
      IO.print("yes")
    case False{}:
      IO.print("no")

def pick(r: Bool, e: Bool, l: Bool, m: Bool, a: String) -> IO(Unit):
  match r e l m:
    case True{} _ _ _:
      IO.bind(Fs.Res(String), Unit, Fs.read_file(a), say.text)
    case False{} True{} _ _:
      IO.bind(Bool, Unit, Fs.exists(a), say.bool)
    case False{} False{} True{} _:
      IO.bind(Fs.Res(List<&2, String>), Unit, Fs.list_dir(a), say.dir)
    case False{} False{} False{} True{}:
      IO.bind(Fs.Res(Unit), Unit, FsW.mkdir_p(a), say.unit)
    case False{} False{} False{} False{}:
      IO.bind(Fs.Res(Unit), Unit, FsW.remove(a), say.unit)

def dispatch1(+cmd: String, a: String) -> IO(Unit):
  pick(String.eq(cmd, "read"), String.eq(cmd, "exists"), String.eq(cmd, "ls"), String.eq(cmd, "mkdir"), a)

def dispatch(cmd: String, rest: List<String>) -> IO(Unit):
  match rest:
    case Con{a, Con{b, Con{c, Nil{}}}}:
      IO.bind(Fs.Res(Unit), Unit, FsW.write_atomic(a, b, c), say.unit)
    case Con{a, Nil{}}:
      dispatch1(cmd, a)
    case _:
      IO.die(Unit, 2, "usage")

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{cmd, rest}}:
      dispatch(cmd, rest)
    case _:
      IO.die(Unit, 2, "usage")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)

