import Base
import ./json.bend as Json
import ./fs.bend as Fs
import ./act.bend as Act
import ./store.bend as Store
import ./store/base.bend as SBase
import ./store/seq.bend as SSeq
import ./store/io.bend as SIo
import ./fs/write.bend as FsW

# User-supplied token sources and active pick (dot-plk73m). The core knows no
# store. $CSWAP_TOKEN_CONFIG names a JSON file:
#   {"accounts": {"a@x": {"command": ["/path/script", "a@x"]}},
#    "active":   {"file": "/abs/path/active.json"}}
# An account's token is the stdout of its command. The active pick is
# {"account": email, "organizationUuid": org} in the named file; when present
# it is the identity cswap uses instead of ~/.claude.json, which a running
# Claude Code session rewrites. No config means everything behaves as before.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def json_of(r: Fs.Res(String)) -> Json.Json:
  match r:
    case Fail{e}:
      Json.JNull{}
    case Done{s}:
      Json.unwrap(Json.parse(s))

def config_at(r: Result<&1, &1, U32 & String, String>) -> IO(Json.Json):
  match r:
    case Fail{e}:
      IO.pure(Json.Json, Json.JNull{})
    case Done{p}:
      IO.bind(Fs.Res(String), Json.Json, Fs.read_file(p), t => IO.pure(Json.Json, json_of(t)))

def config() -> IO(Json.Json):
  IO.bind(Result<&1, &1, U32 & String, String>, Json.Json, IO.get_env("CSWAP_TOKEN_CONFIG"), r => config_at(r))

def pick_file(+cfg: Json.Json) -> String:
  SSeq.field_str(SSeq.get_or("active", cfg, Json.JNull{}), "file")

def pick_go(has: Bool, +p: String) -> IO(Json.Json):
  match has:
    case True{}:
      IO.bind(Fs.Res(String), Json.Json, Fs.read_file(p), t => IO.pure(Json.Json, json_of(t)))
    case False{}:
      IO.pure(Json.Json, Json.JNull{})

def pick_cfg(+c: Json.Json) -> IO(Json.Json):
  pick_go(SBase.nonempty(pick_file(c)), pick_file(c))

# {"account", "organizationUuid"} the config names, JNull when there is none.
def read_pick() -> IO(Json.Json):
  IO.bind(Json.Json, Json.Json, config(), c => pick_cfg(c))

def with_pick(+cfg: Json.Json, +pick: Json.Json) -> Json.Json:
  Json.set("oauthAccount", Json.set("organizationUuid", Json.JStr{SSeq.field_str(pick, "organizationUuid")}, Json.set("emailAddress", Json.JStr{SSeq.field_str(pick, "account")}, SSeq.get_or("oauthAccount", cfg, Json.JObj{Json.JNil{}}))), cfg)

# The ~/.claude.json view with the active pick's identity laid over it.
def overlay(+cfg: Json.Json, +pick: Json.Json) -> Json.Json:
  Store.sel.j(SBase.nonempty(SSeq.field_str(pick, "account")), with_pick(cfg, pick), cfg)

def write_pick2(has: Bool, +p: String, +email: String, +org: String) -> Act.of(Unit):
  match has:
    case True{}:
      do ActM<Unit>:
        FsW.mkdir_p(Fs.dirname(p))
        SIo.write_secret(p, Json.emit_pretty(Json.of_pairs([("account", Json.JStr{email}), ("organizationUuid", Json.JStr{org})])))
    case False{}:
      Act.pure(Unit, Unit{})

def write_pick3(+c: Json.Json, +email: String, +org: String) -> Act.of(Unit):
  write_pick2(SBase.nonempty(pick_file(c)), pick_file(c), email, org)

# Record the active pick where the config names it (no-op without a config).
def write_pick(+email: String, +org: String) -> Act.of(Unit):
  Act.bind(Json.Json, Unit, Act.lift(Json.Json, config()), c => write_pick3(c, email, org))

def strs(+xs: List<&2, Json.Json>) -> List<String>:
  match xs:
    case Nil{}:
      []
    case Con{Json.JStr{s}, t}:
      s <> strs(t)
    case Con{h, t}:
      strs(t)

def run_cmd(argv: List<String>) -> Act.of(String):
  match argv:
    case Nil{}:
      Act.pure(String, "")
    case Con{prog, args}:
      Fs.tool(prog, args)

def creds_text(+t: String) -> String:
  Json.emit_pretty(Json.of_pairs([("claudeAiOauth", Json.of_pairs([("accessToken", Json.JStr{SBase.strip_chars(t, "\n\r ")}), ("scopes", Json.arr([Json.JStr{"user:inference"}]))]))]))

def creds_of(+t: String) -> Act.of(String):
  Act.pure(String, SBase.sel.s(SBase.nonempty(SBase.strip_chars(t, "\n\r ")), creds_text(t), ""))

def creds_go(+cfg: Json.Json, +email: String) -> Act.of(String):
  Act.bind(String, String, run_cmd(strs(Json.to_list(SSeq.get_or("command", SSeq.get_or(email, SSeq.get_or("accounts", cfg, Json.JNull{}), Json.JNull{}), Json.JNull{})))), t => creds_of(t))

# The setup-token credential text the config's command yields for `email`;
# "" when no command is configured for it.
def creds_for(+email: String) -> Act.of(String):
  Act.bind(Json.Json, String, Act.lift(Json.Json, config()), c => creds_go(c, email))
