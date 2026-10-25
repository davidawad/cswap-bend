import Base
import ../json.bend as Json
import ../swlive.bend as L
import ../store/base.bend as SBase
import ../store/seq.bend as SSeq
import ../clock.bend as Clock
import ./events.bend as Ev
import ./cadence.bend as Cad
import ./config.bend as Cfg

# The decision the daemon acts on, what a tick answers, and the result
# builders for the outcomes that need no switch. Kept apart from `apply` so
# the policy side of a tick never imports the switch modules.

type Dec is Data:
  DNone{reason: String, detail: String}
  DExhausted{earliest: Maybe<&2, U32>}
  DGo{to: String, to_email: String, trigger: String, left_headroom: Maybe<&2, U32>, left_recovery: Maybe<&2, U32>}

# The events of one tick, in order, and the sleeper's facts.
type TickRes is Data:
  TickRes{info: Cad.Info, events: List<&2, Json.Json>}

# What `tick` was handed besides the decision.
type Ctx is Data:
  Ctx{ctx: SBase.Ctx, dry_run: Bool, cfg: Cfg.Cfg, now: U32, ts: String, opts: L.Opts, active: Json.Json, next_poll: Maybe<&2, U32>}

def sel_o(+c: Bool, x: Cad.Outcome, y: Cad.Outcome) -> Cad.Outcome:
  match c:
    case True{}:
      x
    case False{}:
      y

def blocked_reason(+r: String) -> Bool:
  String.eq(r, "no-candidates") || String.eq(r, "no-comparison") || String.eq(r, "no-qualifying-candidate") || String.eq(r, "no-viable-target") || String.eq(r, "all-exhausted")

def info(o: Cad.Outcome, +until: Maybe<&2, U32>, +long: Bool, +idle: Bool, +np: Maybe<&2, U32>) -> Cad.Info:
  Cad.Info{o, until, long, idle, np}

def one(i: Cad.Info, +e: Json.Json) -> TickRes:
  TickRes{i, [e]}

def iso_opt(+m: Maybe<&2, U32>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{t}:
      Some{Clock.iso8601_utc(t)}

def ctx_ts(+c: Ctx) -> String:
  match c:
    case Ctx{x, d, cf, n, ts, o, a, np}:
      ts

def ctx_np(+c: Ctx) -> Maybe<&2, U32>:
  match c:
    case Ctx{x, d, cf, n, ts, o, a, np}:
      np

def none_res(+c: Ctx, +reason: String, +detail: String) -> TickRes:
  one(info(sel_o(blocked_reason(reason), Cad.Blocked{}, Cad.NoAction{}), None{}, String.eq(reason, "no-candidates"), String.eq(reason, "active-idle"), ctx_np(c)), Ev.no_switch(ctx_ts(c), reason, detail))

def exhausted_res(+c: Ctx, +earliest: Maybe<&2, U32>) -> TickRes:
  one(info(Cad.Blocked{}, earliest, False{}, False{}, ctx_np(c)), Ev.all_exhausted(ctx_ts(c), iso_opt(earliest)))

# A failed tick: the error as an event, exit 1.
def error_res(+c: Ctx, +msg: String) -> TickRes:
  one(info(Cad.Failed{}, None{}, False{}, False{}, ctx_np(c)), Ev.error(ctx_ts(c), msg, True{}))

# ---- the switch itself ----------------------------------------------------------------------

def ctx_now(+c: Ctx) -> U32:
  match c:
    case Ctx{x, d, cf, n, ts, o, a, np}:
      n

def ctx_cfg(+c: Ctx) -> Cfg.Cfg:
  match c:
    case Ctx{x, d, cf, n, ts, o, a, np}:
      cf

def ctx_store(+c: Ctx) -> SBase.Ctx:
  match c:
    case Ctx{x, d, cf, n, ts, o, a, np}:
      x

def ctx_opts(+c: Ctx) -> L.Opts:
  match c:
    case Ctx{x, d, cf, n, ts, o, a, np}:
      o

def ctx_active(+c: Ctx) -> Json.Json:
  match c:
    case Ctx{x, d, cf, n, ts, o, a, np}:
      a

def ctx_dry(+c: Ctx) -> Bool:
  match c:
    case Ctx{x, d, cf, n, ts, o, a, np}:
      d
