import Base
import ../fs.bend as Fs
import ../act.bend as Act
import ../clock.bend as Clock
import ../store.bend as Store
import ../cmd.bend as Cmd
import ../store/base.bend as SBase
import ../store/seq.bend as SSeq
import ../swlive.bend as L
import ./config.bend as Cfg
import ../fmt/out.bend as O
import ./live.bend as Lv
import ../profflag.bend as Profflag
import ./auto.bend as Auto
import ../policy/types.bend as PT
import ./pidlock.bend as Pid
import ./shadowcli.bend as ShC

# The entry the CLI dispatches `auto` to: flags over settings.json over
# defaults, the single-decider lock, then one tick (`--once`) or the loop.
# Exit codes: 0 switched, 1 error, 2 no action (or a usage error), 3 blocked.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def env_or(r: Result<&1, &1, U32 & String, String>, +d: String) -> String:
  match r:
    case Fail{e}:
      d
    case Done{s}:
      s

def oracle_of(r: Result<&1, &1, U32 & String, String>) -> L.Oracle:
  match r:
    case Fail{e}:
      L.OHttp{}
    case Done{p}:
      L.OFile{p}

# How the daemon switches: the delay before the post-switch check
# ($CSWAP_SWITCH_VERIFY_DELAY_MS, default 2000) and where the ownership lookup
# goes ($CSWAP_SWITCH_ORACLE_FILE answers from a file; else the profile API).
def switch_opts(d: Result<&1, &1, U32 & String, String>, o: Result<&1, &1, U32 & String, String>) -> L.Opts:
  L.Opts{Maybe.default(&2, U32, U32.read(env_or(d, "2000")), 2000), oracle_of(o)}

def settings_text(r: Fs.Res(String)) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{t}:
      t

def settings_io(+ctx: SBase.Ctx) -> IO(String):
  IO.bind(Fs.Res(String), String, Fs.read_file(SBase.root_of(ctx) ++ "/settings.json"), r => IO.pure(String, settings_text(r)))

def tick_body(+r: Auto.Run, +once: Bool) -> Act.of(U32):
  Act.cond(U32, once, Auto.once(r), Auto.forever(r, PT.fresh_mem(), False{}))

# The stream's first line, when the format has one (CSV: the header), then the ticks.
def body(+r: Auto.Run, +once: Bool) -> Act.of(U32):
  do ActM<U32>:
    Act.lift(Unit, IO.write(O.stream_head(Auto.run_fmt(r))))
    tick_body(r, once)

def flag_dry(+f: Cfg.Flags) -> Bool:
  match f:
    case Cfg.Flags{o, j, d, th, iv, cd, st, md, ia}:
      d

def flag_fmt(+f: Cfg.Flags) -> O.Fmt:
  match f:
    case Cfg.Flags{o, j, d, th, iv, cd, st, md, ia}:
      O.of_code(j)

def flag_once(+f: Cfg.Flags) -> Bool:
  match f:
    case Cfg.Flags{o, j, d, th, iv, cd, st, md, ia}:
      o

def started(+ctx: SBase.Ctx, +f: Cfg.Flags, +state_dir: String, +opts: L.Opts, +version: String, +cfg: Cfg.Cfg, +pid: U32, +ts: String, +lv: Lv.Live) -> Act.of(U32):
  Pid.with_pidlock(U32, state_dir, body(Auto.Run{ctx, state_dir, cfg, flag_fmt(f), flag_dry(f), opts, ts, version, pid, lv}, flag_once(f)))

def go3(+ctx: SBase.Ctx, +f: Cfg.Flags, +state_dir: String, +opts: L.Opts, +version: String, +text: String, +over: Maybe<&2, String>) -> Act.of(U32):
  do ActM<U32>:
    pid : U32 <- Act.lift(U32, Pid.my_pid())
    t : U32 <- Act.lift(U32, Clock.now_s())
    started(ctx, f, state_dir, opts, version, Lv.cfg_for(text, f, over), pid, Clock.iso8601_utc(t), Lv.live_for(text, f, over))

# A `--profile` that names nothing is a usage error.
def go2(+bad: Maybe<&2, String>, +ctx: SBase.Ctx, +f: Cfg.Flags, +state_dir: String, +opts: L.Opts, +version: String, +text: String, +over: Maybe<&2, String>) -> Act.of(U32):
  match bad:
    case Some{n}:
      Act.fail(U32, 2, "cswap auto: error: unknown profile '" ++ n ++ "'; `cswap profile list` shows the profiles")
    case None{}:
      go3(ctx, f, state_dir, opts, version, text, over)

def go(+ctx: SBase.Ctx, +f: Cfg.Flags, +state_dir: String, +opts: L.Opts, +version: String, +over: Maybe<&2, String>) -> Act.of(U32):
  do ActM<U32>:
    +text : String <- Act.lift(String, settings_io(ctx))
    go2(Lv.unknown(text, over), ctx, f, state_dir, opts, version, text, over)

def with_flags(+ctx: SBase.Ctx, +state_dir: String, +opts: L.Opts, +version: String, +over: Maybe<&2, String>, r: Result<&2, &2, String, Cfg.Flags>) -> Act.of(U32):
  match r:
    case Fail{msg}:
      Act.fail(U32, 2, "cswap auto: error: " ++ msg)
    case Done{f}:
      go(ctx, f, state_dir, opts, version, over)

# `cswap auto ARGS` (ARGS after the verb). `state_dir` is where the pid file,
# status file and log live; pass the backup root when there is no better place.
def plain3(+ok: Bool, +ctx: SBase.Ctx, +state_dir: String, +opts: L.Opts, +version: String, +over: Maybe<&2, String>, +rest: List<&2, String>, +err: String) -> Act.of(U32):
  match ok:
    case True{}:
      with_flags(ctx, state_dir, opts, version, over, Cfg.parse_flags(rest))
    case False{}:
      Act.fail(U32, 2, "cswap auto: error: " ++ err)

def plain2(+ctx: SBase.Ctx, +state_dir: String, +opts: L.Opts, +version: String, +sp: Profflag.Split) -> Act.of(U32):
  match sp:
    case Profflag.Split{rest, over, err, pending}:
      plain3(String.is_empty(err), ctx, state_dir, opts, version, over, rest, err)

def plain(+ctx: SBase.Ctx, +args: List<&2, String>, +state_dir: String, +opts: L.Opts, +version: String) -> Act.of(U32):
  plain2(ctx, state_dir, opts, version, Profflag.split(args))

def routed(+ctx: SBase.Ctx, +sp: ShC.Split, +state_dir: String, +opts: L.Opts, +version: String) -> Act.of(U32):
  Act.cond(U32, ShC.sp_shadow(sp), ShC.run(ctx, opts, sp), plain(ctx, ShC.sp_rest(sp), state_dir, opts, version))

def auto(+ctx: SBase.Ctx, +args: List<&2, String>, +state_dir: String, +opts: L.Opts, +version: String) -> Act.of(U32):
  routed(ctx, ShC.split(Cfg.normalize(args), False{}), state_dir, opts, version)

# ---- as a program entry ----------------------------------------------------------------------------------------

# 2 for a usage error, 1 for everything else.
def code_for(+code: U32) -> U32:
  SSeq.sel.u(U32.is_eq(code, 2), 2, 1)

def finish(r: Fs.Res(U32)) -> IO(Unit):
  match r:
    case Done{code}:
      IO.exit(code)
    case Fail{(code, msg)}:
      IO.bind(Unit, Unit, IO.print_err(msg), u => IO.exit(code_for(code)))

# The verb as a command result: events already went to stdout as they happened,
# so only the exit code (and a failure's message) remain.
def cmd_of(r: Fs.Res(U32)) -> IO(Cmd.Out):
  match r:
    case Done{code}:
      IO.pure(Cmd.Out, Cmd.Out{code, "", ""})
    case Fail{(code, msg)}:
      IO.pure(Cmd.Out, Cmd.Out{code_for(code), "", msg ++ "\n"})

def run2(+ctx: SBase.Ctx, +args: List<&2, String>, +version: String, st: Result<&1, &1, U32 & String, String>, d: Result<&1, &1, U32 & String, String>, o: Result<&1, &1, U32 & String, String>) -> IO(Fs.Res(U32)):
  auto(ctx, args, env_or(st, SBase.root_of(ctx)), switch_opts(d, o), version)

def run1(+ctx: SBase.Ctx, +args: List<&2, String>, +version: String, st: Result<&1, &1, U32 & String, String>, d: Result<&1, &1, U32 & String, String>) -> IO(Fs.Res(U32)):
  IO.bind(Result<&1, &1, U32 & String, String>, Fs.Res(U32), IO.get_env("CSWAP_SWITCH_ORACLE_FILE"), o => run2(ctx, args, version, st, d, o))

def run0(+ctx: SBase.Ctx, +args: List<&2, String>, +version: String, st: Result<&1, &1, U32 & String, String>) -> IO(Fs.Res(U32)):
  IO.bind(Result<&1, &1, U32 & String, String>, Fs.Res(U32), IO.get_env("CSWAP_SWITCH_VERIFY_DELAY_MS"), d => run1(ctx, args, version, st, d))

# `cswap auto ARGS` reading $HOME, $CLAUDE_CONFIG_DIR and $CSWAP_STATE_DIR itself.
def run(+args: List<&2, String>, +version: String) -> IO(Fs.Res(U32)):
  IO.bind(SBase.Ctx, Fs.Res(U32), Store.ctx_env(), ctx => IO.bind(Result<&1, &1, U32 & String, String>, Fs.Res(U32), IO.get_env("CSWAP_STATE_DIR"), st => run0(ctx, args, version, st)))

# The whole verb as an IO program that exits with the tick's code.
def auto_main(+args: List<&2, String>, +version: String) -> IO(Unit):
  IO.bind(Fs.Res(U32), Unit, run(args, version), finish)

# The verb for the CLI dispatch (`cswap auto ARGS`).
def auto_cmd(+args: List<&2, String>, +version: String) -> IO(Cmd.Out):
  IO.bind(Fs.Res(U32), Cmd.Out, run(args, version), cmd_of)
