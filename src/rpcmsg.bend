import Base
import ./json.bend as Json
import ./cmd.bend as Cmd
import ./fmt/out.bend as O

# The pure half of `cswap rpc`: a request document becomes a command line, a
# command's output becomes a response document. docs/API.md has the schema.
#
#   request   {"id": any, "cmd": "list", "args": ["..."], "opts": {"name": value}}
#   success   {"id": ..., "ok": true,  "result": <the command's --format json document>}
#   failure   {"id": ..., "ok": false, "error": {"code": "...", "message": "...", "exit": N}}
#
# `opts` names are options without the dashes: true is the bare flag, a string
# or number is its value, false and null are left out. No effects.

type Req is Data:
  ReqOk{id: Json.Json, argv: List<&2, String>}
  ReqBad{id: Json.Json, code: String, msg: String}

# ---- the request ------------------------------------------------------------------

type Bad is Data:
  Bad{code: String, msg: String}

def or_null(m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case Some{v}:
      v
    case None{}:
      Json.JNull{}

def item_str(+h: Json.Json) -> Result<&2, &2, String, String>:
  match h:
    case Json.JStr{s}:
      Done{s}
    case Json.JNum{t}:
      Done{t}
    case _:
      Fail{"args must be strings or numbers"}

def cons_str(x: Result<&2, &2, String, String>, rest: Result<&2, &2, String, List<&2, String>>) -> Result<&2, &2, String, List<&2, String>>:
  match x rest:
    case Done{a} Done{b}:
      Done{a <> b}
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

def strs_of(items: Json.Json) -> Result<&2, &2, String, List<&2, String>>:
  match items:
    case Json.JCons{h, t}:
      cons_str(item_str(h), strs_of(t))
    case _:
      Done{[]}

def args_of(+v: Json.Json) -> Result<&2, &2, String, List<&2, String>>:
  match v:
    case Json.JNull{}:
      Done{[]}
    case Json.JArr{items}:
      strs_of(items)
    case _:
      Fail{"args must be an array"}

def dashes(+k: String) -> String:
  Bool.pick(String, String.starts_with(k, "-"), k, "--" ++ k)

def opt_flag(+k: String, +v: Json.Json) -> Result<&2, &2, String, List<&2, String>>:
  match v:
    case Json.JBool{True{}}:
      Done{[dashes(k)]}
    case Json.JBool{False{}}:
      Done{[]}
    case Json.JNull{}:
      Done{[]}
    case Json.JStr{s}:
      Done{[dashes(k), s]}
    case Json.JNum{t}:
      Done{[dashes(k), t]}
    case _:
      Fail{"option '" ++ k ++ "' must be a string, a number or a boolean"}

def cat(x: Result<&2, &2, String, List<&2, String>>, rest: Result<&2, &2, String, List<&2, String>>) -> Result<&2, &2, String, List<&2, String>>:
  match x rest:
    case Done{a} Done{b}:
      Done{List.append(&2, String, a, b)}
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

def flags_of(fields: Json.Json) -> Result<&2, &2, String, List<&2, String>>:
  match fields:
    case Json.JField{k, v, t}:
      cat(opt_flag(k, v), flags_of(t))
    case _:
      Done{[]}

def opts_of(+v: Json.Json) -> Result<&2, &2, String, List<&2, String>>:
  match v:
    case Json.JNull{}:
      Done{[]}
    case Json.JObj{f}:
      flags_of(f)
    case _:
      Fail{"opts must be an object"}

# ---- which commands -------------------------------------------------------------------

def allowed(+v: String) -> Bool:
  String.eq(v, "list") || String.eq(v, "status") || String.eq(v, "switch") || String.eq(v, "add") || String.eq(v, "add-token") || String.eq(v, "remove")
    || String.eq(v, "import-usage") || String.eq(v, "config") || String.eq(v, "profile") || String.eq(v, "upgrade") || String.eq(v, "help")

def refused(+v: String) -> String:
  Bool.pick(String, String.eq(v, "auto"), "auto is not available over rpc: the poller is the one decider (run `cswap auto`)",
  Bool.pick(String, String.eq(v, "tui") || String.eq(v, "watch"), "interactive commands are not available over rpc",
  Bool.pick(String, String.eq(v, "menubar"), "menubar is not supported in cswap-bend", "unknown command")))

def cmd_ok(+v: String, +name: String) -> Result<&2, &2, Bad, String>:
  Bool.pick(Result<&2, &2, Bad, String>, allowed(v), Done{v},
  Bool.pick(Result<&2, &2, Bad, String>, String.eq(v, "auto") || String.eq(v, "tui") || String.eq(v, "watch") || String.eq(v, "menubar"),
    Fail{Bad{"not_allowed", refused(v)}}, Fail{Bad{"unknown_command", "unknown command '" ++ name ++ "'"}}))

# The command a name stands for (the CLI's aliases).
def canon(+n: String) -> String:
  Bool.pick(String, String.eq(n, "ls"), "list", Bool.pick(String, String.eq(n, "rm"), "remove", Bool.pick(String, String.eq(n, "update"), "upgrade", n)))

# The program word for a command name; Fail names why it is not served.
def cmd_word(+name: String) -> Result<&2, &2, Bad, String>:
  Bool.pick(Result<&2, &2, Bad, String>, String.eq(name, "version"), Done{"--version"}, cmd_ok(canon(name), name))

def cmd_of(+m: Maybe<&2, Json.Json>) -> Result<&2, &2, Bad, String>:
  match m:
    case Some{Json.JStr{s}}:
      cmd_word(s)
    case _:
      Fail{Bad{"bad_request", "a request needs a \"cmd\" string"}}

# ---- building ---------------------------------------------------------------------------

def bad(+id: Json.Json, +code: String, +msg: String) -> Req:
  ReqBad{id, code, msg}

def build3(+id: Json.Json, +w: String, a: Result<&2, &2, String, List<&2, String>>, o: Result<&2, &2, String, List<&2, String>>) -> Req:
  match a o:
    case Done{xs} Done{fs}:
      ReqOk{id, w <> List.append(&2, String, xs, List.append(&2, String, fs, ["--no-input"]))}
    case Fail{e} _:
      bad(id, "bad_request", e)
    case _ Fail{e}:
      bad(id, "bad_request", e)

def build2(+id: Json.Json, c: Result<&2, &2, Bad, String>, +j: Json.Json) -> Req:
  match c:
    case Fail{Bad{code, msg}}:
      bad(id, code, msg)
    case Done{w}:
      build3(id, w, args_of(or_null(Json.get("args", j))), opts_of(or_null(Json.get("opts", j))))

def build(+j: Json.Json) -> Req:
  build2(or_null(Json.get("id", j)), cmd_of(Json.get("cmd", j)), j)

# The command line a request asks for, or why it cannot be served.
def plan(+j: Json.Json) -> Req:
  match j:
    case Json.JObj{f}:
      build(j)
    case _:
      bad(Json.JNull{}, "bad_request", "a request is an object: {\"id\": ..., \"cmd\": ..., \"args\": [...], \"opts\": {...}}")

# ---- the response -----------------------------------------------------------------------------

def ok_resp(+id: Json.Json, +result: Json.Json) -> Json.Json:
  Json.of_pairs([("id", id), ("ok", Json.JBool{True{}}), ("result", result)])

def err_resp(+id: Json.Json, +code: String, +msg: String, +exit: U32) -> Json.Json:
  Json.of_pairs([("id", id), ("ok", Json.JBool{False{}}), ("error", Json.of_pairs([("code", Json.JStr{code}), ("message", Json.JStr{msg}), ("exit", Json.JNum{U32.show(exit)})]))])

def last_part(ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{h, Nil{}}:
      h
    case Con{h, Con{h2, t}}:
      last_part(Con{h2, t})

def cut_pick(hit: Bool, rest: String, more: String) -> String:
  match hit:
    case True{}:
      rest
    case False{}:
      more

# The text after the first `error: ` in `s`, else `whole`.
def cut_error(s: String, +whole: String) -> String:
  match s:
    case SNil{}:
      whole
    case SCon{+c, +t}:
      cut_pick(String.starts_with(s, "error: "), String.drop(s, 7n), cut_error(t, whole))

# The message of a usage error: the last line, after its `error: `.
def after_error(+err: String) -> String:
  cut_error(String.trim(last_part(String.lines(String.trim(err)))), String.trim(last_part(String.lines(String.trim(err)))))

def str_at(+j: Json.Json, +k: String) -> String:
  Maybe.default(&2, String, Json.as_string(or_null(Json.get(k, j))), "")

def fail_doc(+id: Json.Json, +exit: U32, +d: Json.Json, +err: String) -> Json.Json:
  Bool.pick(Json.Json, Maybe.is_some(&2, Json.Json, Json.get("error", d)),
    err_resp(id, str_at(or_null(Json.get("error", d)), "type"), str_at(or_null(Json.get("error", d)), "message"), exit),
    err_resp(id, Bool.pick(String, U32.is_eq(exit, 2), "usage", "error"), after_error(err), exit))

def err_of(m: Maybe<&2, Json.Json>, +id: Json.Json, +exit: U32, +err: String) -> Json.Json:
  match m:
    case Some{d}:
      fail_doc(id, exit, d, err)
    case None{}:
      err_resp(id, Bool.pick(String, U32.is_eq(exit, 2), "usage", "error"), after_error(err), exit)

def ok_of(m: Maybe<&2, Json.Json>, +id: Json.Json) -> Json.Json:
  match m:
    case Some{d}:
      ok_resp(id, d)
    case None{}:
      ok_resp(id, Json.JObj{Json.JNil{}})

def response2(good: Bool, +id: Json.Json, +exit: U32, +err: String, m: Maybe<&2, Json.Json>) -> Json.Json:
  match good:
    case True{}:
      ok_of(m, id)
    case False{}:
      err_of(m, id, exit, err)

# The response document for a command's output.
def response(+id: Json.Json, o: Cmd.Out) -> Json.Json:
  match o:
    case Cmd.Out{+code, out, +err}:
      response2(U32.is_eq(code, 0), id, code, err, O.doc_of(Cmd.Out{code, out, err}))
