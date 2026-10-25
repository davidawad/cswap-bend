import Base
import ./exec.bend as Exec
import ./cmd.bend as Cmd
import ./server.bend as Server
import ./srvargs.bend as Sa

# The cswap-bend program: run the command line, print its output, exit with its code.
# `rpc` and `serve` are the two verbs that do not return a single answer: they
# read requests and write responses until their input or a signal ends them.

def write_err.m(c: Bool, +text: String) -> IO(Unit):
  match c:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      IO.print_err(String.trim_end(text))

def write_err(+text: String) -> IO(Unit):
  write_err.m(String.is_empty(text), text)
def finish(o: Cmd.Out) -> IO(Unit):
  match o:
    case Cmd.Out{code, out, err}:
      IO.bind(Unit, Unit, IO.write(out), u => IO.bind(Unit, Unit, write_err(err), v => IO.exit(code)))

def run_plan(p: Sa.Plan) -> IO(Cmd.Out):
  match p:
    case Sa.PRpc{fmt}:
      Server.rpc(fmt)
    case Sa.PServe{path, fmt}:
      Server.serve(path, fmt)
    case Sa.PBad{msg}:
      IO.pure(Cmd.Out, Cmd.Out{2, "", "usage: cswap <command> [args] [options]\ncswap: error: " ++ msg ++ "\n"})

def route3(is_srv: Bool, +h: String, +t: List<&2, String>, +args: List<&2, String>) -> IO(Cmd.Out):
  match is_srv:
    case True{}:
      run_plan(Sa.plan(h, t))
    case False{}:
      Exec.exec_line(args, None{})

def route2(+args: List<&2, String>) -> IO(Cmd.Out):
  match args:
    case Nil{}:
      Exec.exec_line(args, None{})
    case Con{h, t}:
      route3(String.eq(h, "rpc") || String.eq(h, "serve"), h, t, Con{h, t})

# The command for `IO.args` (its head is the program name).
def run(ts: List<String>) -> IO(Cmd.Out):
  route2(Exec.tail_of(ts))

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), ts => IO.bind(Cmd.Out, Unit, run(ts), finish))
