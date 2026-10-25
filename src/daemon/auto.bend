import Base
import ../json.bend as Json
import ../fs.bend as Fs
import ../fs/write.bend as FsW
import ../act.bend as Act
import ../clock.bend as Clock
import ../store.bend as Store
import ../store/base.bend as SBase
import ../swlive.bend as L
import ../policy/types.bend as T
import ./events.bend as Ev
import ../fmt/out.bend as O
import ./cadence.bend as Cad
import ./config.bend as Cfg
import ./live.bend as Lv
import ../store/io.bend as SIo
import ./walk.bend as Wk
import ./quarantine.bend as Q
import ./dec.bend as Dc
import ./tick.bend as Tk
import ./gather.bend as G
import ./collect.bend as Col
import ./status.bend as Stat
import ./pidlock.bend as Pid

# `cswap auto`: --once is one tick (exit 0 switched, 1 error, 2 no action, 3
# blocked); otherwise tick, sleep, tick, forever. One decider per backup root
# (a pid-file flock), the status file rewritten after every tick, and a JSONL
# log line per tick with where each account's reading came from. A SIGTERM
# ends the process (the kernel drops the lock); the pid file is then stale
# but harmless, as the lock is what counts.

# What a run is: the roster context, the state dir, the settings in force,
# --json, --dry-run, the switch options, and when the process started, the
# pid, and what is needed to read the settings again each tick (the flags and
# the profile in force: src/daemon/live.bend).

type Run is Data:
  Run{ctx: SBase.Ctx, state_dir: String, cfg: Cfg.Cfg, fmt: O.Fmt, dry: Bool, opts: L.Opts, started: String, version: String, pid: U32, live: Lv.Live}

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def run_ctx(r: Run) -> SBase.Ctx:
  match r:
    case Run{c, sd, cf, j, d, o, st, v, p, lv}:
      c

def run_dir(r: Run) -> String:
  match r:
    case Run{c, sd, cf, j, d, o, st, v, p, lv}:
      sd

def run_cfg(r: Run) -> Cfg.Cfg:
  match r:
    case Run{c, sd, cf, j, d, o, st, v, p, lv}:
      cf

def run_fmt(r: Run) -> O.Fmt:
  match r:
    case Run{c, sd, cf, j, d, o, st, v, p, lv}:
      j

def run_dry(r: Run) -> Bool:
  match r:
    case Run{c, sd, cf, j, d, o, st, v, p, lv}:
      d

def run_opts(r: Run) -> L.Opts:
  match r:
    case Run{c, sd, cf, j, d, o, st, v, p, lv}:
      o

def run_started(r: Run) -> String:
  match r:
    case Run{c, sd, cf, j, d, o, st, v, p, lv}:
      st

def run_version(r: Run) -> String:
  match r:
    case Run{c, sd, cf, j, d, o, st, v, p, lv}:
      v

def run_pid(r: Run) -> U32:
  match r:
    case Run{c, sd, cf, j, d, o, st, v, p, lv}:
      p

def run_live(r: Run) -> Lv.Live:
  match r:
    case Run{c, sd, cf, j, d, o, st, v, p, lv}:
      lv

def with_live(+r: Run, +cfg: Cfg.Cfg, +lv: Lv.Live) -> Run:
  match r:
    case Run{c, sd, cf, j, d, o, st, v, p, l0}:
      Run{c, sd, cfg, j, d, o, st, v, p, lv}

# The run with the settings of this tick: settings.json read again, the
# profile laid over it, the flags over both.
def refreshed(+r: Run, +text: String) -> Run:
  with_live(r, Lv.cfg_for(text, Lv.live_flags(run_live(r)), Lv.live_over(run_live(r))), Lv.live_for(text, Lv.live_flags(run_live(r)), Lv.live_over(run_live(r))))

def refresh(+r: Run) -> Act.of(Run):
  do ActM<Run>:
    text : String <- Act.lift(String, Lv.read_text(SBase.root_of(run_ctx(r))))
    return refreshed(r, text)

def tagged(+r: Run, +o: Tk.Out) -> Tk.Out:
  match o:
    case Tk.Out{Dc.TickRes{i, evs}, m, a, es, ac, ck}:
      Tk.Out{Dc.TickRes{i, Lv.tag_events(Lv.live_tag(run_live(r)), evs)}, m, a, es, ac, ck}

def interval(r: Run) -> U32:
  Cfg.cfg_interval(run_cfg(r))

# ---- printing --------------------------------------------------------------------------------------------

def show2(human: Bool, +f: O.Fmt, +e: Json.Json) -> String:
  match human:
    case True{}:
      Ev.human(e)
    case False{}:
      O.event_text(f, e)

def show(+f: O.Fmt, +e: Json.Json) -> String:
  show2(O.is_text(f), f, e)

def print_all(+f: O.Fmt, +evs: List<&2, Json.Json>) -> Act.of(Unit):
  match evs:
    case Nil{}:
      Act.pure(Unit, Unit{})
    case Con{e, t}:
      do ActM<Unit>:
        Act.lift(Unit, IO.print(show(f, e)))
        print_all(f, t)

# ---- one tick, never raising ------------------------------------------------------------------------------

def failed_out(+env: Tk.Env, +ts: String, +msg: String) -> Tk.Out:
  Tk.Out{Dc.TickRes{Cad.Info{Cad.Failed{}, None{}, False{}, False{}, None{}}, [Ev.error(ts, msg, True{})]}, Tk.env_mem(env), None{}, [], Json.arr([]), Tk.env_checked(env)}

def prepend(+extra: List<&2, Json.Json>, +o: Tk.Out) -> Tk.Out:
  match o:
    case Tk.Out{Dc.TickRes{i, evs}, m, a, es, ac, ck}:
      Tk.Out{Dc.TickRes{i, List.append(&2, Json.Json, extra, evs)}, m, a, es, ac, ck}

def tick_out(+env: Tk.Env, +ts: String, r: Fs.Res(Tk.Out)) -> Tk.Out:
  match r:
    case Done{o}:
      o
    case Fail{(code, msg)}:
      failed_out(env, ts, msg)

def release_with(+env: Tk.Env, +t: U32, +sq: Maybe<&2, Json.Json>) -> Act.of(List<&2, Json.Json>):
  match sq:
    case None{}:
      Act.pure(List<&2, Json.Json>, [])
    case Some{seq}:
      Q.release_recovered(SBase.root_of(Tk.env_ctx(env)), seq, Clock.iso8601_utc(t))

def release_now(+env: Tk.Env, +t: U32) -> Act.of(List<&2, Json.Json>):
  do ActM<List<&2, Json.Json>>:
    sq : Maybe<&2, Json.Json> <- SIo.read_seq(SBase.root_of(Tk.env_ctx(env)))
    release_with(env, t, sq)

# Quarantines that no longer hold (the account was replaced, or its login was
# renewed) are released before deciding; a dry run changes nothing.
def released(+env: Tk.Env, +t: U32) -> Act.of(List<&2, Json.Json>):
  Act.cond(List<&2, Json.Json>, Tk.env_dry(env), Act.pure(List<&2, Json.Json>, []), release_now(env, t))

def fetched(+env: Tk.Env, +t: U32) -> Act.of(Maybe<&2, G.Snap>):
  do ActM<Maybe<&2, G.Snap>>:
    m0 : Maybe<&2, G.Snap> <- G.snapshot(Tk.env_ctx(env))
    Col.refresh_opt(Tk.env_ctx(env), Tk.env_cfg(env), t, m0)

# Release what no longer holds, snapshot, fetch what is due, decide, and walk the ranking.
def look(+env: Tk.Env) -> Act.of(Tk.Out):
  do ActM<Tk.Out>:
    +t : U32 <- Act.lift(U32, Clock.now_s())
    rel : List<&2, Json.Json> <- released(env, t)
    m : Maybe<&2, G.Snap> <- fetched(env, t)
    o : Tk.Out <- Wk.run(env, t, Clock.iso8601_utc(t), m)
    return prepend(rel, o)

def tick_safe(+env: Tk.Env) -> Act.of(Tk.Out):
  do ActM<Tk.Out>:
    t : U32 <- Act.lift(U32, Clock.now_s())
    r : Fs.Res(Tk.Out) <- Act.lift(Fs.Res(Tk.Out), look(env))
    return tick_out(env, Clock.iso8601_utc(t), r)

# ---- after a tick: status file and log --------------------------------------------------------------------

def out_info(+o: Tk.Out) -> Cad.Info:
  match o:
    case Tk.Out{Dc.TickRes{info, evs}, m, a, es, ac, ck}:
      info

def out_events(+o: Tk.Out) -> List<&2, Json.Json>:
  match o:
    case Tk.Out{Dc.TickRes{info, evs}, m, a, es, ac, ck}:
      evs

def out_mem(+o: Tk.Out) -> T.Mem:
  match o:
    case Tk.Out{r, m, a, es, ac, ck}:
      m

def out_active(+o: Tk.Out) -> Maybe<&2, String>:
  match o:
    case Tk.Out{r, m, a, es, ac, ck}:
      a

def out_entries(+o: Tk.Out) -> List<&2, Stat.Entry>:
  match o:
    case Tk.Out{r, m, a, es, ac, ck}:
      es

def out_checked(+o: Tk.Out) -> Bool:
  match o:
    case Tk.Out{r, m, a, es, ac, ck}:
      ck

def out_accts(+o: Tk.Out) -> Json.Json:
  match o:
    case Tk.Out{r, m, a, es, ac, ck}:
      ac

def info_outcome(i: Cad.Info) -> Cad.Outcome:
  match i:
    case Cad.Info{o, u, l, idle, np}:
      o

def outcome_name(o: Cad.Outcome) -> String:
  match o:
    case Cad.Switched{}:
      "switched"
    case Cad.NoAction{}:
      "no-action"
    case Cad.Blocked{}:
      "blocked"
    case Cad.Failed{}:
      "failed"

def status_of(+r: Run, +o: Tk.Out, +ts: String, +next_at: String) -> Stat.Status:
  Stat.Status{run_pid(r), run_version(r), run_started(r), Some{ts}, Some{next_at}, out_active(o), out_entries(o), run_cfg(r)}

# A blocked tick is a warning, a failed one an error.
def level_of(o: Cad.Outcome) -> String:
  match o:
    case Cad.Blocked{}:
      "warn"
    case Cad.Failed{}:
      "error"
    case _:
      "info"

# One JSONL log line: the tick, what came of it, and per account where its
# reading came from (usage-endpoint, header-probe or cache).
def log_json(+ts: String, +o: Tk.Out) -> Json.Json:
  Json.JObj{Json.JField{"ts", Json.JStr{ts}, Json.JField{"level", Json.JStr{level_of(info_outcome(out_info(o)))}, Json.JField{"msg", Json.JStr{"tick"},
    Json.JField{"outcome", Json.JStr{outcome_name(info_outcome(out_info(o)))}, Json.JField{"active", Ev.opt_str(out_active(o)), Json.JField{"accounts", out_accts(o), Json.JNil{}}}}}}}}

def swallow(r: Fs.Res(Unit)) -> Act.of(Unit):
  Act.pure(Unit, Unit{})

def best_effort(m: Act.of(Unit)) -> Act.of(Unit):
  IO.bind(Fs.Res(Unit), Fs.Res(Unit), m, r => swallow(r))

def write_status(+r: Run, +o: Tk.Out, +ts: String, +delay: U32, +now: U32) -> Act.of(Unit):
  best_effort(Stat.write(run_dir(r), status_of(r, o, ts, Clock.iso8601_utc((now + delay : U32)))))

def write_log(+r: Run, +o: Tk.Out, +ts: String) -> Act.of(Unit):
  best_effort(FsW.append(run_dir(r) ++ "/daemon.log", Json.emit_py(Lv.tag_log(Lv.live_tag(run_live(r)), log_json(ts, o))) ++ "\n"))

def record_tick(+r: Run, +o: Tk.Out, +ts: String, +delay: U32, +now: U32) -> Act.of(Unit):
  do ActM<Unit>:
    write_status(r, o, ts, delay, now)
    write_log(r, o, ts)

def sleep_if(+c: Bool, +e: Json.Json) -> List<&2, Json.Json>:
  match c:
    case True{}:
      [e]
    case False{}:
      []

def sleep_event(r: Run, +delay: U32, +now: U32) -> List<&2, Json.Json>:
  sleep_if(Cad.announce(delay, interval(r)), Ev.sleep(Clock.iso8601_utc(now), (delay * 10 : U32), Clock.iso8601_utc((now + delay : U32))))

def env_of(+r: Run, +mem: T.Mem, +checked: Bool) -> Tk.Env:
  Tk.Env{run_ctx(r), run_cfg(r), run_dry(r), run_opts(r), mem, checked, []}

# ---- --once --------------------------------------------------------------------------------------------------

def finish_tick(+r: Run, +o: Tk.Out, +delay: U32, +now: U32, +extra: List<&2, Json.Json>) -> Act.of(Unit):
  do ActM<Unit>:
    print_all(run_fmt(r), List.append(&2, Json.Json, out_events(o), extra))
    record_tick(r, o, Clock.iso8601_utc(now), delay, now)

def first_tick(+r: Run) -> Act.of(Tk.Out):
  do ActM<Tk.Out>:
    +o : Tk.Out <- tick_safe(env_of(r, T.fresh_mem(), False{}))
    return tagged(r, o)

def out_code(+o: Tk.Out) -> U32:
  Cad.exit_code(info_outcome(out_info(o)))

def once(+r: Run) -> Act.of(U32):
  do ActM<U32>:
    +r2 : Run <- refresh(r)
    +o : Tk.Out <- first_tick(r2)
    now : U32 <- Act.lift(U32, Clock.now_s())
    finish_tick(r2, o, interval(r2), now, [])
    return out_code(o)

# ---- the loop ------------------------------------------------------------------------------------------------

# Tick, record, sleep, repeat. Not terminating by construction: kept in this
# module, which no proof imports.
def nap(+delay: U32) -> Act.of(Unit):
  Act.lift(Unit, IO.sleep((delay * 1000 : U32)))

def pace(+r: Run, +o: Tk.Out, +now: U32) -> Act.of(Unit):
  do ActM<Unit>:
    +delay : U32 = Cad.next_delay(out_info(o), now, interval(r))
    finish_tick(r, o, delay, now, sleep_event(r, delay, now))
    nap(delay)

def settle(r: Run, +o: Tk.Out) -> Act.of(Unit):
  do ActM<Unit>:
    now : U32 <- Act.lift(U32, Clock.now_s())
    pace(r, o, now)

def tick_tagged(+r: Run, +mem: T.Mem, +checked: Bool) -> Act.of(Tk.Out):
  do ActM<Tk.Out>:
    +o : Tk.Out <- tick_safe(env_of(r, mem, checked))
    return tagged(r, o)

def round(+r: Run, +mem: T.Mem, +checked: Bool) -> Act.of(Tk.Out):
  do ActM<Tk.Out>:
    +r2 : Run <- refresh(r)
    +o : Tk.Out <- tick_tagged(r2, mem, checked)
    settle(r2, o)
    return o

@unsafe def forever(+r: Run, mem: T.Mem, checked: Bool) -> Act.of(U32):
  do ActM<U32>:
    +o : Tk.Out <- round(r, mem, checked)
    forever(r, out_mem(o), out_checked(o))
