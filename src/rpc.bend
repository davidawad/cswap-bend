import Base
import ./json.bend as Json
import ./cmd.bend as Cmd
import ./exec.bend as Exec
import ./fmt/out.bend as O
import ./fmt/yaml.bend as Yaml
import ./fmt/toon.bend as Toon
import ./frame.bend as Fr
import ./rpcmsg.bend as M

# One rpc message in, one response out, shared by `cswap rpc` (stdin/stdout)
# and `cswap serve` (a unix socket). The message is in the rpc format: JSON
# (a line), YAML or TOON (a block ended by a blank line). The command runs
# in this process through Exec.exec_line with the output format forced to json.

# A YAML or TOON message is a block, a JSON message a line.
def is_block(f: O.Fmt) -> Bool:
  Bool.not(O.is_json(f))

def render(f: O.Fmt, +j: Json.Json) -> String:
  match f:
    case O.FYaml{}:
      Yaml.emit(j) ++ "\n\n"
    case O.FToon{}:
      Toon.emit(j) ++ "\n\n"
    case _:
      Json.emit.go(j, 0, True{}, 0n) ++ "\n"

def parse_req(f: O.Fmt, +msg: String) -> Result<&2, &2, String, Json.Json>:
  match f:
    case O.FYaml{}:
      Yaml.parse(msg)
    case O.FToon{}:
      Toon.parse(msg)
    case _:
      Json.parse(msg)

def run_req(+f: O.Fmt, r: M.Req) -> IO(String):
  match r:
    case M.ReqOk{id, argv}:
      IO.bind(Cmd.Out, String, Exec.exec_line(argv, Some{O.FJson{}}), o => IO.pure(String, render(f, M.response(id, o))))
    case M.ReqBad{id, code, msg}:
      IO.pure(String, render(f, M.err_resp(id, code, msg, 2)))

def run_doc(+f: O.Fmt, r: Result<&2, &2, String, Json.Json>) -> IO(String):
  match r:
    case Done{j}:
      run_req(f, M.plan(j))
    case Fail{e}:
      IO.pure(String, render(f, M.err_resp(Json.JNull{}, "bad_request", e, 2)))

def handle2(blank: Bool, +f: O.Fmt, +msg: String) -> IO(String):
  match blank:
    case True{}:
      IO.pure(String, "")
    case False{}:
      run_doc(f, parse_req(f, msg))

# The response text for one message ("" for a blank one).
def handle(+f: O.Fmt, +msg: String) -> IO(String):
  handle2(Fr.blank(msg), f, msg)
