import Base
import ../src/json.bend as J
import ../src/cmd.bend as Cmd
import ../src/rpcmsg.bend as R

# Ground equations for turning rpc requests into command lines and command
# output into rpc responses.

def show(r: R.Req) -> String:
  match r:
    case R.ReqOk{id, argv}:
      "ok " ++ J.emit(id) ++ " " ++ String.join(argv, " ")
    case R.ReqBad{id, code, msg}:
      "bad " ++ J.emit(id) ++ " " ++ code ++ ": " ++ msg

def plan(js: String) -> String:
  show(R.plan(J.unwrap(J.parse(js))))

def p_list() -> {plan("{\"id\":1,\"cmd\":\"list\"}") == "ok 1 list --no-input" : String}:
  {==}

def p_alias() -> {plan("{\"id\":\"a\",\"cmd\":\"ls\"}") == "ok \"a\" list --no-input" : String}:
  {==}

def p_rm_alias() -> {plan("{\"cmd\":\"rm\",\"args\":[2],\"opts\":{\"yes\":true}}") == "ok null remove 2 --yes --no-input" : String}:
  {==}

def p_switch_opts() -> {plan("{\"id\":7,\"cmd\":\"switch\",\"args\":[\"2\"],\"opts\":{\"force\":true,\"strategy\":\"best\",\"dry\":false,\"model\":null,\"slot\":3}}") == "ok 7 switch 2 --force --strategy best --slot 3 --no-input" : String}:
  {==}

def p_config_set() -> {plan("{\"id\":1,\"cmd\":\"config\",\"args\":[\"set\",\"autoswitch.threshold\",85]}") == "ok 1 config set autoswitch.threshold 85 --no-input" : String}:
  {==}

def p_dashed_opt() -> {plan("{\"cmd\":\"list\",\"opts\":{\"--token-status\":true}}") == "ok null list --token-status --no-input" : String}:
  {==}

def p_version() -> {plan("{\"cmd\":\"version\"}") == "ok null --version --no-input" : String}:
  {==}

def p_auto() -> {plan("{\"id\":2,\"cmd\":\"auto\"}") == "bad 2 not_allowed: auto is not available over rpc: the poller is the one decider (run `cswap auto`)" : String}:
  {==}

def p_tui() -> {plan("{\"cmd\":\"tui\"}") == "bad null not_allowed: interactive commands are not available over rpc" : String}:
  {==}

def p_watch() -> {plan("{\"cmd\":\"watch\"}") == "bad null not_allowed: interactive commands are not available over rpc" : String}:
  {==}

def p_unknown() -> {plan("{\"cmd\":\"frob\"}") == "bad null unknown_command: unknown command 'frob'" : String}:
  {==}

def p_rpc_nested() -> {plan("{\"cmd\":\"rpc\"}") == "bad null unknown_command: unknown command 'rpc'" : String}:
  {==}

def p_no_cmd() -> {plan("{\"id\":3}") == "bad 3 bad_request: a request needs a \"cmd\" string" : String}:
  {==}

def p_cmd_not_string() -> {plan("{\"id\":3,\"cmd\":5}") == "bad 3 bad_request: a request needs a \"cmd\" string" : String}:
  {==}

def p_not_object() -> {plan("[1]") == "bad null bad_request: a request is an object: {\"id\": ..., \"cmd\": ..., \"args\": [...], \"opts\": {...}}" : String}:
  {==}

def p_bad_args() -> {plan("{\"cmd\":\"list\",\"args\":[true]}") == "bad null bad_request: args must be strings or numbers" : String}:
  {==}

def p_args_not_array() -> {plan("{\"cmd\":\"list\",\"args\":\"x\"}") == "bad null bad_request: args must be an array" : String}:
  {==}

def p_bad_opt() -> {plan("{\"cmd\":\"list\",\"opts\":{\"x\":[1]}}") == "bad null bad_request: option 'x' must be a string, a number or a boolean" : String}:
  {==}

def p_opts_not_object() -> {plan("{\"cmd\":\"list\",\"opts\":[1]}") == "bad null bad_request: opts must be an object" : String}:
  {==}

# ---- responses ---------------------------------------------------------------------------

def resp(id: String, code: U32, out: String, err: String) -> String:
  J.emit(R.response(J.unwrap(J.parse(id)), Cmd.Out{code, out, err}))

def r_ok() -> {resp("1", 0, "{\n  \"schemaVersion\": 1,\n  \"accounts\": []\n}\n", "") == "{\"id\":1,\"ok\":true,\"result\":{\"schemaVersion\":1,\"accounts\":[]}}" : String}:
  {==}

def r_ok_text() -> {resp("\"x\"", 0, "Added Account 1: a@x.test\n", "") == "{\"id\":\"x\",\"ok\":true,\"result\":{\"schemaVersion\":1,\"message\":\"Added Account 1: a@x.test\"}}" : String}:
  {==}

def r_error_envelope() -> {resp("2", 1, "{\n  \"schemaVersion\": 1,\n  \"error\": {\n    \"type\": \"AccountNotFoundError\",\n    \"message\": \"No account found with identifier: 9\"\n  }\n}\n", "") == "{\"id\":2,\"ok\":false,\"error\":{\"code\":\"AccountNotFoundError\",\"message\":\"No account found with identifier: 9\",\"exit\":1}}" : String}:
  {==}

def r_error_text() -> {resp("null", 1, "", "Error: removing Account-2 needs confirmation; pass --yes\n") == "{\"id\":null,\"ok\":false,\"error\":{\"code\":\"Error\",\"message\":\"removing Account-2 needs confirmation; pass --yes\",\"exit\":1}}" : String}:
  {==}

def r_usage() -> {resp("3", 2, "", "usage: cswap <command> [args] [options]\ncswap: error: unrecognized arguments: x\n") == "{\"id\":3,\"ok\":false,\"error\":{\"code\":\"usage\",\"message\":\"unrecognized arguments: x\",\"exit\":2}}" : String}:
  {==}

def r_id_kept() -> {resp("{\"n\":[1,2]}", 0, "{\"a\":1}", "") == "{\"id\":{\"n\":[1,2]},\"ok\":true,\"result\":{\"a\":1}}" : String}:
  {==}
