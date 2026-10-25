import Base
import ./setload.bend as Setload
import ./store/base.bend as SBase
import ./store/seq.bend as SSeq
import ./json.bend as Json
import ./fs.bend as Fs
import ./act.bend as Act
import ./cmd.bend as Cmd
import ./settings.bend as Settings
import ./swbase.bend as SwBase
import ./swlive.bend as SwLive
import ./switch.bend as Switch

def delay_of(r: Result<&1, &1, U32 & String, String>) -> U32:
  match r:
    case Fail{e}:
      2000
    case Done{v}:
      Maybe.default(&2, U32, U32.read(v), 2000)

def oracle_of(r: Result<&1, &1, U32 & String, String>) -> SwLive.Oracle:
  match r:
    case Fail{e}:
      SwLive.OHttp{}
    case Done{p}:
      SwLive.OFile{p}

def opts_of(d: Result<&1, &1, U32 & String, String>, o: Result<&1, &1, U32 & String, String>) -> SwLive.Opts:
  SwLive.Opts{delay_of(d), oracle_of(o)}

# How long to wait before the post-switch re-read ($CSWAP_SWITCH_VERIFY_DELAY_MS,
# default 2000 ms) and where the ownership lookup comes from ($CSWAP_SWITCH_ORACLE_FILE
# names a JSON file in tests; unset means the profile endpoint).
def switch_opts() -> IO(SwLive.Opts):
  IO.bind(Result<&1, &1, U32 & String, String>, SwLive.Opts, IO.get_env("CSWAP_SWITCH_VERIFY_DELAY_MS"),
    d => IO.bind(Result<&1, &1, U32 & String, String>, SwLive.Opts, IO.get_env("CSWAP_SWITCH_ORACLE_FILE"), o => IO.pure(SwLive.Opts, opts_of(d, o))))

def warns_text(ws: List<&2, Json.Json>) -> String:
  match ws:
    case Nil{}:
      ""
    case Con{Json.JStr{w}, t}:
      "Warning: " ++ w ++ "\n" ++ warns_text(t)
    case Con{h, t}:
      warns_text(t)

def switch_text(+j: Json.Json) -> String:
  warns_text(Json.to_list(Maybe.default(&2, Json.Json, Json.get("warnings", j), Json.JNull{}))) ++ SSeq.field_str(j, "message") ++ "\n"

def switch_ok(+json: Bool, +j: Json.Json) -> Cmd.Out:
  match json:
    case True{}:
      Cmd.doc(j)
    case False{}:
      Cmd.Out{0, switch_text(j), ""}

def switch_fail2(+json: Bool, +c: U32, +m: String) -> Cmd.Out:
  match json:
    case True{}:
      Cmd.Out{1, Json.emit_pretty(SwBase.error_envelope(c, m)) ++ "\n", ""}
    case False{}:
      Cmd.fail(m)

def switch_fail(+json: Bool, ce: U32 & String) -> Cmd.Out:
  (c, m) = ce
  switch_fail2(json, c, m)

def switch_out(+json: Bool, r: Fs.Res(Json.Json), +models: List<&2, String>, +source: String) -> Cmd.Out:
  match r:
    case Fail{e}:
      switch_fail(json, e)
    case Done{j}:
      switch_ok(json, SwBase.with_models(j, models, source))

# The models that gate a strategy switch: --model wins, else the
# autoswitch.model setting; none for a plain rotation or a direct switch.
type Gate is Data:
  Gate{models: List<&2, String>, source: String}

def gate_model(model: Maybe<&2, String>, +cfg: Json.Json) -> Gate:
  match model:
    case Some{m}:
      Gate{Setload.model_names(m), "cli"}
    case None{}:
      Gate{Setload.model(cfg), "autoswitch.model"}

def gate_of(strategy: Maybe<&2, String>, model: Maybe<&2, String>, +cfg: Json.Json) -> Gate:
  match strategy:
    case None{}:
      Gate{[], ""}
    case Some{s}:
      gate_model(model, cfg)

def gate_models(g: Gate) -> List<&2, String>:
  match g:
    case Gate{m, s}:
      m

def switch_run(+ctx: SBase.Ctx, ident: Maybe<&2, String>, +force: Bool, +strategy: Maybe<&2, String>, +gate: Gate, +opts: SwLive.Opts) -> Act.of(Json.Json):
  match ident:
    case Some{id}:
      Switch.switch_to(ctx, id, force, opts)
    case None{}:
      Switch.switch_auto(ctx, Maybe.default(&2, String, strategy, ""), gate_models(gate), opts)

def gate_source(g: Gate) -> String:
  match g:
    case Gate{m, s}:
      s

def switch_cmd2(+ctx: SBase.Ctx, ident: Maybe<&2, String>, +force: Bool, +strategy: Maybe<&2, String>, +gate: Gate, +json: Bool, +opts: SwLive.Opts) -> IO(Cmd.Out):
  IO.bind(Fs.Res(Json.Json), Cmd.Out, switch_run(ctx, ident, force, strategy, gate, opts),
    r => IO.pure(Cmd.Out, switch_out(json, r, gate_models(gate), gate_source(gate))))

def switch_cmd(+ctx: SBase.Ctx, ident: Maybe<&2, String>, +force: Bool, +strategy: Maybe<&2, String>, model: Maybe<&2, String>, +json: Bool) -> IO(Cmd.Out):
  IO.bind(SwLive.Opts, Cmd.Out, switch_opts(),
    opts => IO.bind(Json.Json, Cmd.Out, Setload.load(SBase.root_of(ctx)),
      cfg => switch_cmd2(ctx, ident, force, strategy, gate_of(strategy, model, cfg), json, opts)))
