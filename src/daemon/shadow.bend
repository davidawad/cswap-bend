import Base
import ../json.bend as Json
import ../fs.bend as Fs
import ../fs/write.bend as FsW
import ../act.bend as Act
import ../clock.bend as Clock
import ../store/base.bend as SBase
import ../swlive.bend as L
import ../policy/types.bend as T
import ./events.bend as Ev
import ./config.bend as Cfg
import ./dec.bend as Dc
import ./tick.bend as Tk
import ./gather.bend as G
import ./pidlock.bend as Pid

# `cswap auto --shadow --shadow-log PATH`: the decider run for comparison only.
# It reads the usage cache the other poller keeps (no HTTP, no fetch), decides
# with the same policy, and appends what it WOULD have done as one JSONL line
# per tick to PATH. It never switches, quarantines, releases or touches state,
# status, cache or log under the backup root; its only writes are PATH and a
# pid/lock pair beside it.

# The headroom (slot -> percent) the tick used: the poll event's headroomPct.

type Step is Data:
  Step{line: Json.Json, mem: T.Mem, checked: Bool}

type Sh is Data:
  Sh{ctx: SBase.Ctx, cfg: Cfg.Cfg, opts: L.Opts, log: String}

def field2(+m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case None{}:
      Json.JNull{}
    case Some{j}:
      j

def field(+k: String, +e: Json.Json) -> Json.Json:
  field2(Json.get(k, e))

def headroom_of(+evs: List<&2, Json.Json>) -> Json.Json:
  match evs:
    case Nil{}:
      Json.JObj{Json.JNil{}}
    case Con{e, t}:
      field("headroomPct", e)

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def last_event(+es: List<&2, Json.Json>, +d: Json.Json) -> Json.Json:
  match es:
    case Nil{}:
      d
    case Con{e, t}:
      last_event(t, e)

def ctx_active(+c: Dc.Ctx) -> Json.Json:
  match c:
    case Dc.Ctx{x, d, cf, n, ts, o, a, np}:
      a

def out_events(+o: Tk.Out) -> List<&2, Json.Json>:
  match o:
    case Tk.Out{Dc.TickRes{i, evs}, m, a, es, ac, ck}:
      evs

def out_active(+o: Tk.Out) -> Maybe<&2, String>:
  match o:
    case Tk.Out{r, m, a, es, ac, ck}:
      a

def out_accts(+o: Tk.Out) -> Json.Json:
  match o:
    case Tk.Out{r, m, a, es, ac, ck}:
      ac

def out_mem(+o: Tk.Out) -> T.Mem:
  match o:
    case Tk.Out{r, m, a, es, ac, ck}:
      m

def out_checked(+o: Tk.Out) -> Bool:
  match o:
    case Tk.Out{r, m, a, es, ac, ck}:
      ck

# The decision as the event the live daemon would have logged.
def decision_event(+ts: String, +c: Dc.Ctx, +d: Dc.Dec) -> Json.Json:
  match d:
    case Dc.DNone{reason, detail}:
      Ev.no_switch(ts, reason, detail)
    case Dc.DExhausted{e}:
      Ev.no_switch(ts, "all-exhausted", "")
    case Dc.DGo{to, email, trig, lh, lr}:
      Ev.switch(ts, trig, ctx_active(c), Ev.ref(to, email), [], True{})

def line(+ts: String, +o: Tk.Out, +dec: Json.Json, +evs: List<&2, Json.Json>) -> Json.Json:
  Json.JObj{Json.JField{"ts", Json.JStr{ts}, Json.JField{"active", Ev.opt_str(out_active(o)),
    Json.JField{"event", field("event", dec), Json.JField{"reason", field("reason", dec), Json.JField{"trigger", field("trigger", dec),
    Json.JField{"from", field("from", dec), Json.JField{"to", field("to", dec), Json.JField{"accounts", headroom_of(evs),
    Json.JField{"sources", out_accts(o), Json.JField{"events", Json.arr(evs), Json.JNil{}}}}}}}}}}}}

def step_of(+ts: String, +o: Tk.Out, +dec: Json.Json, +evs: List<&2, Json.Json>) -> Step:
  Step{line(ts, o, dec, evs), out_mem(o), out_checked(o)}

def shadow2(+ts: String, +nx: Tk.Next) -> Step:
  match nx:
    case Tk.NDone{o}:
      step_of(ts, o, last_event(out_events(o), Json.JNull{}), out_events(o))
    case Tk.NAct{o, c, d}:
      step_of(ts, o, decision_event(ts, c, d), List.append(&2, Json.Json, out_events(o), [decision_event(ts, c, d)]))

# What this tick would do: the finished outcome's own last event, or the
# decision it stopped at. Pure: nothing is fetched, applied or written.
def shadow_step(+env: Tk.Env, +t: U32, +m: Maybe<&2, G.Snap>) -> Step:
  shadow2(Clock.iso8601_utc(t), Tk.tick(env, t, m))

def step_line(+s: Step) -> String:
  match s:
    case Step{l, m, c}:
      Json.emit_py(l) ++ "\n"

def step_mem(+s: Step) -> T.Mem:
  match s:
    case Step{l, m, c}:
      m

def step_checked(+s: Step) -> Bool:
  match s:
    case Step{l, m, c}:
      c

def swallow(r: Fs.Res(Unit)) -> Act.of(Unit):
  Act.pure(Unit, Unit{})

# ---- the loop ------------------------------------------------------------------------------------------------

def sh_env(+r: Sh, +mem: T.Mem, +checked: Bool) -> Tk.Env:
  match r:
    case Sh{c, cf, o, l}:
      Tk.Env{c, cf, True{}, o, mem, checked, []}

def sh_ctx(+r: Sh) -> SBase.Ctx:
  match r:
    case Sh{c, cf, o, l}:
      c

def sh_log(+r: Sh) -> String:
  match r:
    case Sh{c, cf, o, l}:
      l

def sh_interval(+r: Sh) -> U32:
  match r:
    case Sh{c, cf, o, l}:
      Cfg.cfg_interval(cf)

def emit(+r: Sh, +s: Step) -> Act.of(Step):
  IO.bind(Fs.Res(Unit), Fs.Res(Step), FsW.append(sh_log(r), step_line(s)), u => IO.pure(Fs.Res(Step), Done{s}))

def one_tick(+r: Sh, +mem: T.Mem, +checked: Bool) -> Act.of(Step):
  do ActM<Step>:
    +t : U32 <- Act.lift(U32, Clock.now_s())
    m : Maybe<&2, G.Snap> <- G.snapshot(sh_ctx(r))
    emit(r, shadow_step(sh_env(r, mem, checked), t, m))

def once(+r: Sh) -> Act.of(U32):
  do ActM<U32>:
    s : Step <- one_tick(r, T.fresh_mem(), False{})
    return 0

def nap(+delay: U32) -> Act.of(Unit):
  Act.lift(Unit, IO.sleep((delay * 1000 : U32)))

@unsafe def forever(+r: Sh, mem: T.Mem, checked: Bool) -> Act.of(U32):
  do ActM<U32>:
    +s : Step <- one_tick(r, mem, checked)
    nap(sh_interval(r))
    forever(r, step_mem(s), step_checked(s))

def body(+r: Sh, +once_only: Bool) -> Act.of(U32):
  Act.cond(U32, once_only, once(r), forever(r, T.fresh_mem(), False{}))

# Run as the one shadow decider of the log's directory.
def run(+r: Sh, +once_only: Bool) -> Act.of(U32):
  Pid.with_pidlock(U32, Fs.dirname(sh_log(r)), body(r, once_only))
