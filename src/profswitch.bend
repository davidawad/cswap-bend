import Base
import ./json.bend as Json
import ./act.bend as Act
import ./clock.bend as Clock
import ./cmd.bend as Cmd
import ./fs.bend as Fs
import ./setload.bend as Setload
import ./store/base.bend as SBase
import ./swbase.bend as B
import ./swlive.bend as L
import ./switch.bend as Sw
import ./cliswitch.bend as Cliswitch
import ./profile.bend as P
import ./policy/types.bend as T
import ./policy/safe.bend as SF
import ./policy/algo.bend as A
import ./daemon/config.bend as Cfg
import ./daemon/gather.bend as G
import ./daemon/view.bend as V

# `cswap switch` with no target under a profile (`--profile NAME`, or the
# active profile): rotate to the account the profile's strategy picks now.
# The threshold and the cooldown do not apply (the user asked to move); an
# account that is not safe (see src/policy/safe.bend) is never chosen, and
# nothing moves while the active account's usage is unreadable.
#
# With no profile in play, or the `default` profile, `switch` is the legacy
# rotation (src/switch.bend), byte for byte.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def snap_live(+s: G.Snap) -> L.Live:
  match s:
    case G.Snap{seq, live, active, st, rows, ents}:
      live

def snap_ents(+s: G.Snap) -> List<&2, G.Ent>:
  G.snap_ents(s)

def snap_rows(+s: G.Snap) -> Json.Json:
  G.snap_rows(s)

def tag(+p: P.Prof, +r: Json.Json) -> Json.Json:
  Json.set("strategy", Json.JStr{SF.name(P.algo_base(p))}, Json.set("profile", Json.JStr{P.name_of(p)}, r))

def noop(+p: P.Prof, +reason: String, +message: String, +to: Json.Json) -> Json.Json:
  tag(p, B.noop(SF.name(P.algo_base(p)), reason, message, to, []))

def pad_detail2(+empty: Bool, +d: String) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      " (" ++ d ++ ")"

def pad_detail(+d: String) -> String:
  pad_detail2(String.is_empty(d), d)

def nothing_msg(+reason: T.Reason, +detail: String) -> String:
  "Staying put: " ++ T.reason.name(reason) ++ pad_detail(detail)

def decided(+p: P.Prof, +ctx: SBase.Ctx, +opts: L.Opts, +cur: Json.Json, +d: T.Decision) -> Act.of(Json.Json):
  match d:
    case T.Switch{to, trig, why, h, mode, rec, bar}:
      do ActM<Json.Json>:
        r : Json.Json <- Sw.switch_to(ctx, Nat.show(to), False{}, opts)
        return tag(p, r)
    case T.NoSwitch{reason, detail}:
      Act.pure(Json.Json, noop(p, T.reason.name(reason), nothing_msg(reason, detail), cur))

def usages_for(+s: G.Snap, +a: String, +t: U32) -> List<&2, T.Usage>:
  V.usages_of(snap_rows(s), snap_ents(s), Some{a}, t)

def pcfg_for(+p: P.Prof, +raw: Json.Json) -> T.Config:
  V.pol_cfg(P.with_prof(Cfg.from_settings(raw), p))

def decision_for(+p: P.Prof, +raw: Json.Json, +s: G.Snap, +a: String, +t: U32) -> T.Decision:
  A.rotate(P.algo_base(p), V.slot_nat_of(a), V.accounts_of(snap_ents(s)), usages_for(s, a, t), V.nat(t), pcfg_for(p, raw))

def cur_ref(+s: G.Snap, +a: String) -> Json.Json:
  B.ref(Some{a}, L.lv_email(snap_live(s)))

def rotate_at(+p: P.Prof, +ctx: SBase.Ctx, +opts: L.Opts, +raw: Json.Json, +s: G.Snap, +a: String, +t: U32) -> Act.of(Json.Json):
  decided(p, ctx, opts, cur_ref(s, a), decision_for(p, raw, s, a, t))

def rotate_snap(+p: P.Prof, +ctx: SBase.Ctx, +opts: L.Opts, +raw: Json.Json, +s: G.Snap, +act: Maybe<&2, String>, +t: U32) -> Act.of(Json.Json):
  match act:
    case None{}:
      Act.pure(Json.Json, noop(p, "unmanaged-account", "Active account is not managed; run cswap --add-account", B.ref(None{}, L.lv_email(snap_live(s)))))
    case Some{a}:
      rotate_at(p, ctx, opts, raw, s, a, t)

def rotate_opt(+p: P.Prof, +ctx: SBase.Ctx, +opts: L.Opts, +raw: Json.Json, +m: Maybe<&2, G.Snap>, +t: U32) -> Act.of(Json.Json):
  match m:
    case None{}:
      Act.fail(Json.Json, B.e_config(), "No accounts are managed yet")
    case Some{s}:
      rotate_snap(p, ctx, opts, raw, s, G.snap_active(s), t)

def rotate_act(+p: P.Prof, +ctx: SBase.Ctx, +opts: L.Opts, +raw: Json.Json) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    m : Maybe<&2, G.Snap> <- G.snapshot(ctx)
    t : U32 <- Act.lift(U32, Clock.now_s())
    rotate_opt(p, ctx, opts, raw, m, t)

def run_profile(+p: P.Prof, +ctx: SBase.Ctx, +raw: Json.Json, +json: Bool, +opts: L.Opts) -> IO(Cmd.Out):
  IO.bind(Fs.Res(Json.Json), Cmd.Out, rotate_act(p, ctx, opts, raw), r => IO.pure(Cmd.Out, Cliswitch.switch_out(json, r, [], "")))

def with_opts(+p: P.Prof, +ctx: SBase.Ctx, +raw: Json.Json, +json: Bool) -> IO(Cmd.Out):
  IO.bind(L.Opts, Cmd.Out, Cliswitch.switch_opts(), opts => run_profile(p, ctx, raw, json, opts))

# ---- which path a `switch` takes

def legacy(+ctx: SBase.Ctx, +ident: Maybe<&2, String>, +force: Bool, +strategy: Maybe<&2, String>, +model: Maybe<&2, String>, +json: Bool) -> IO(Cmd.Out):
  Cliswitch.switch_cmd(ctx, ident, force, strategy, model, json)

def has(+m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{x}:
      True{}
    case None{}:
      False{}

def usage_err(+msg: String) -> IO(Cmd.Out):
  IO.pure(Cmd.Out, Cmd.Out{2, "", "cswap: error: " ++ msg ++ "\n"})

# A name from `--profile` that matches nothing is an error; a stale
# `active_profile` falls back to the legacy rotation.
def unknown_name(+explicit: Bool, +name: String, +ctx: SBase.Ctx, +ident: Maybe<&2, String>, +force: Bool, +strategy: Maybe<&2, String>, +model: Maybe<&2, String>, +json: Bool) -> IO(Cmd.Out):
  match explicit:
    case True{}:
      IO.pure(Cmd.Out, Cmd.failed(json, "ConfigError", "unknown profile '" ++ name ++ "'; `cswap profile list` shows the profiles"))
    case False{}:
      legacy(ctx, ident, force, strategy, model, json)

def by_name(+is_default: Bool, +p: P.Prof, +ctx: SBase.Ctx, +raw: Json.Json, +ident: Maybe<&2, String>, +force: Bool, +strategy: Maybe<&2, String>, +model: Maybe<&2, String>, +json: Bool) -> IO(Cmd.Out):
  match is_default:
    case True{}:
      legacy(ctx, ident, force, strategy, model, json)
    case False{}:
      with_opts(p, ctx, raw, json)

def resolved(+res: P.Res, +over: Maybe<&2, String>, +ctx: SBase.Ctx, +raw: Json.Json, +ident: Maybe<&2, String>, +force: Bool, +strategy: Maybe<&2, String>, +model: Maybe<&2, String>, +json: Bool) -> IO(Cmd.Out):
  match res:
    case P.RNone{}:
      legacy(ctx, ident, force, strategy, model, json)
    case P.RUnknown{name}:
      unknown_name(has(over), name, ctx, ident, force, strategy, model, json)
    case P.ROk{p}:
      by_name(String.eq(P.name_of(p), "default"), p, ctx, raw, ident, force, strategy, model, json)

# Only a bare `switch` (no target, no --strategy) follows a profile.
def targeted(+ident: Maybe<&2, String>, +strategy: Maybe<&2, String>) -> Bool:
  has(ident) || has(strategy)

def loaded(+over: Maybe<&2, String>, +ctx: SBase.Ctx, +ident: Maybe<&2, String>, +force: Bool, +strategy: Maybe<&2, String>, +model: Maybe<&2, String>, +json: Bool, +raw: Json.Json) -> IO(Cmd.Out):
  resolved(P.resolve(raw, over), over, ctx, raw, ident, force, strategy, model, json)

def targeted_out(+over: Maybe<&2, String>, +ctx: SBase.Ctx, +ident: Maybe<&2, String>, +force: Bool, +strategy: Maybe<&2, String>, +model: Maybe<&2, String>, +json: Bool) -> IO(Cmd.Out):
  match over:
    case Some{o}:
      usage_err("--profile can only be used with a bare 'switch' (no target and no --strategy)")
    case None{}:
      legacy(ctx, ident, force, strategy, model, json)

def route(+tgt: Bool, +over: Maybe<&2, String>, +ctx: SBase.Ctx, +ident: Maybe<&2, String>, +force: Bool, +strategy: Maybe<&2, String>, +model: Maybe<&2, String>, +json: Bool) -> IO(Cmd.Out):
  match tgt:
    case True{}:
      targeted_out(over, ctx, ident, force, strategy, model, json)
    case False{}:
      IO.bind(Json.Json, Cmd.Out, Setload.load(SBase.root_of(ctx)), raw => loaded(over, ctx, ident, force, strategy, model, json, raw))

# `cswap switch [TARGET] [--profile NAME] ...`
def switch_cmd(+ctx: SBase.Ctx, +over: Maybe<&2, String>, +ident: Maybe<&2, String>, +force: Bool, +strategy: Maybe<&2, String>, +model: Maybe<&2, String>, +json: Bool) -> IO(Cmd.Out):
  route(targeted(ident, strategy), over, ctx, ident, force, strategy, model, json)
