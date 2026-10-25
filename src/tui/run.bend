import Base
import ../fs.bend as Fs
import ../clock.bend as Clock
import ./fmt.bend as F
import ./model.bend as M
import ./view.bend as V
import ./read.bend as R
import ./num.bend as N

# `cswap tui`: a read-only dashboard. It never fetches usage and never decides
# anything; it redraws from the files the daemon and the CLI keep:
#   <backup root>/sequence.json, cache/usage.json, settings.json
#   <state dir>/daemon-status.json, daemon.log   (state dir: $CSWAP_STATE_DIR,
#                                                  else the backup root)
#
# Flags: --once (draw one frame and exit), --interval N (seconds between
# frames, default 2), --no-color. NO_COLOR and $COLUMNS (default 100) are
# honoured; $CSWAP_TUI_NOW (unix seconds) pins the clock for tests.
#
# Bend 2 has no raw key input, so there are no key bindings: the dashboard runs
# until it is killed (q and Ctrl-C do what Ctrl-C does to any program), and the
# reference's `s <slot>` switch action is not offered; use `cswap switch`.

type Opts is Data:
  Opts{once: Bool, interval: U32, color: Bool, bad: String}

def usage_text() -> String:
  "usage: cswap tui [--once] [--interval SECONDS] [--no-color]"

# ---- arguments ----------------------------------------------------------------------------

def set_interval(+o: Opts, +n: U32) -> Opts:
  match o:
    case Opts{once, i, c, b}:
      Opts{once, n, c, b}

def with_bad(+o: Opts, +msg: String) -> Opts:
  match o:
    case Opts{once, i, c, b}:
      Opts{once, i, c, msg}

def with_interval(+o: Opts, +v: Maybe<&2, U32>) -> Opts:
  match v:
    case None{}:
      with_bad(o, "--interval needs a whole number of seconds")
    case Some{n}:
      set_interval(o, n)

def with_once(+o: Opts) -> Opts:
  match o:
    case Opts{once, i, c, b}:
      Opts{True{}, i, c, b}

def with_plain(+o: Opts) -> Opts:
  match o:
    case Opts{once, i, c, b}:
      Opts{once, i, False{}, b}

def keep(+ok: Bool, +m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      m
    case False{}:
      None{}

def positive(+m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m:
    case Some{n}:
      keep(U32.is_gt(n, 0), m)
    case None{}:
      None{}

def default_opts() -> Opts:
  Opts{False{}, 2, True{}, ""}

# ---- reading ------------------------------------------------------------------------------------

def env_pick(r: Result<&1, &1, U32 & String, String>, +d: String) -> String:
  match r:
    case Fail{e}:
      d
    case Done{s}:
      s

def env_or(+name: String, +d: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, String>, String, IO.get_env(name), r => IO.pure(String, env_pick(r, d)))

def text_pick(r: Fs.Res(String)) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{t}:
      t

def read_text(+path: String) -> IO(String):
  IO.bind(Fs.Res(String), String, Fs.read_file(path), r => IO.pure(String, text_pick(r)))

def out_of(v: U32 & (String & String)) -> String:
  (st, oe) = v
  (o, e) = oe
  o

def out_pick(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{v}:
      out_of(v)

def code_of(v: U32 & (String & String)) -> U32:
  (st, oe) = v
  st

def code_pick(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> U32:
  match r:
    case Fail{e}:
      1
    case Done{v}:
      code_of(v)

# The last lines of a file, "" when it is missing.
def tail_text(+path: String, +n: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, String, Process.run("tail", ["-n", n, path], "", 262144, 2000), r => IO.pure(String, out_pick(r)))

def local_off() -> IO(U32):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, U32, Process.run("date", ["+%z"], "", 64, 2000),
    r => IO.pure(U32, N.read_or(Clock.tz(String.trim(out_pick(r))), 86400)))

# Is the daemon's pid alive? `kill -0` answers without signalling.
def alive(+pid: Maybe<&2, U32>) -> IO(Bool):
  match pid:
    case None{}:
      IO.pure(Bool, False{})
    case Some{p}:
      IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, Bool, Process.run("kill", ["-0", U32.show(p)], "", 64, 2000), r => IO.pure(Bool, U32.is_eq(code_pick(r), 0)))

def now_pick(+pinned: String, +real: U32) -> U32:
  N.read_or(U32.read(pinned), real)

def clock_now() -> IO(U32):
  IO.bind(String, U32, env_or("CSWAP_TUI_NOW", ""), p => IO.bind(U32, U32, Clock.now_s(), t => IO.pure(U32, now_pick(p, t))))

# ---- one frame --------------------------------------------------------------------------------------

def frame_of(+v: M.View, +version: String, +now: U32, +off: U32, +live: Bool, +seq_t: String, +cache_t: String, +status_t: String, +settings_t: String, +log_t: String) -> String:
  V.frame(R.snap(version, live, now, off, seq_t, cache_t, status_t, settings_t, log_t), v)

def pid_of(+status_t: String) -> Maybe<&2, U32>:
  N.uint_at(R.f_pid(), N.parse_text(status_t))

def frame_io(+v: M.View, +version: String, +root: String, +state: String) -> IO(String):
  do IO<String>:
    now : U32 <- clock_now()
    off : U32 <- local_off()
    seq_t : String <- read_text(root ++ "/sequence.json")
    cache_t : String <- read_text(root ++ "/cache/usage.json")
    settings_t : String <- read_text(root ++ "/settings.json")
    +status_t : String <- read_text(state ++ "/daemon-status.json")
    log_t : String <- tail_text(state ++ "/daemon.log", "8")
    live : Bool <- alive(pid_of(status_t))
    IO.pure(String, frame_of(v, version, now, off, live, seq_t, cache_t, status_t, settings_t, log_t))

# ---- the loop -------------------------------------------------------------------------------------------

def clear() -> String:
  "\u{1B}[H\u{1B}[2J"

@unsafe def forever(+v: M.View, +version: String, +root: String, +state: String, +secs: U32) -> IO(Unit):
  do IO<Unit>:
    f : String <- frame_io(v, version, root, state)
    IO.write(clear() ++ f ++ "\n")
    IO.sleep((secs * 1000 : U32))
    forever(v, version, root, state, secs)

def width_of(+cols: String) -> U32:
  N.read_or(positive(U32.read(cols)), 100)

def color_of(+want: Bool, +no_color: String) -> Bool:
  want && String.is_empty(no_color)

def opts_color(+o: Opts) -> Bool:
  match o:
    case Opts{once, i, c, b}:
      c

def opts_once(+o: Opts) -> Bool:
  match o:
    case Opts{once, i, c, b}:
      once

def opts_secs(+o: Opts) -> U32:
  match o:
    case Opts{once, i, c, b}:
      i

def once_frame(+v: M.View, +version: String, +root: String, +state: String) -> IO(Unit):
  IO.bind(String, Unit, frame_io(v, version, root, state), f => IO.print(f))

def pick_mode(+once: Bool, +v: M.View, +version: String, +root: String, +state: String, +secs: U32) -> IO(Unit):
  match once:
    case True{}:
      once_frame(v, version, root, state)
    case False{}:
      forever(v, version, root, state, secs)

def run_with(+o: Opts, +version: String, +v: M.View, +root: String, +state: String) -> IO(Unit):
  pick_mode(opts_once(o), v, version, root, state, opts_secs(o))

def run(+o: Opts, +version: String, +cols: String, +no_color: String, +home: String, +state: String) -> IO(Unit):
  run_with(o, version, M.View{width_of(cols), color_of(opts_color(o), no_color)}, home ++ "/.claude-swap-backup", state)

def opts_bad(+o: Opts) -> String:
  match o:
    case Opts{once, i, c, b}:
      b

def start2(+o: Opts, +version: String, +cols: String, +no_color: String, +home: String, +st: String) -> IO(Unit):
  run(o, version, cols, no_color, home, st)

def start1(+o: Opts, +version: String, +cols: String, +no_color: String, +home: String) -> IO(Unit):
  IO.bind(String, Unit, env_or("CSWAP_STATE_DIR", home ++ "/.claude-swap-backup"), st => start2(o, version, cols, no_color, home, st))

def start(+o: Opts, +version: String) -> IO(Unit):
  do IO<Unit>:
    home : String <- IO.try(String, IO.get_env("HOME"))
    cols : String <- env_or("COLUMNS", "")
    no_color : String <- env_or("NO_COLOR", "")
    start1(o, version, cols, no_color, home)

def reject(+msg: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print_err("cswap tui: error: " ++ msg ++ "\n" ++ usage_text()), u => IO.exit(2))

def read_opt(+v: Maybe<&2, String>) -> Maybe<&2, U32>:
  match v:
    case None{}:
      None{}
    case Some{s}:
      U32.read(s)

def step_pick(+once: Bool, +plain: Bool, +iv: Bool, +o: Opts, +a: String, +v: Maybe<&2, String>) -> Opts:
  match once plain iv:
    case True{} _ _:
      with_once(o)
    case False{} True{} _:
      with_plain(o)
    case False{} False{} True{}:
      with_interval(o, positive(read_opt(v)))
    case False{} False{} False{}:
      with_bad(o, "unknown argument " ++ a)

# One argument: its effect on the options. `v` is the word after it.
def step(+o: Opts, +a: String, +v: Maybe<&2, String>) -> Opts:
  step_pick(String.eq(a, "--once"), String.eq(a, "--no-color"), String.eq(a, "--interval"), o, a, v)

def head_opt(+l: List<&2, String>) -> Maybe<&2, String>:
  match l:
    case Nil{}:
      None{}
    case Con{h, t}:
      Some{h}

def tail_of(+l: List<&2, String>) -> List<&2, String>:
  match l:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      t

def rest_after2(+iv: Bool, +t: List<&2, String>) -> List<&2, String>:
  match iv:
    case True{}:
      tail_of(t)
    case False{}:
      t

# `fuel` is the argument count, at least the number of steps.
def parse(+fuel: Nat, +args: List<&2, String>, +o: Opts) -> Opts:
  match fuel args:
    case _ Nil{}:
      o
    case 0n _:
      o
    case 1n+p Con{a, t}:
      parse(p, rest_after2(String.eq(a, "--interval"), t), step(o, a, head_opt(t)))

def dispatch_pick(+ok: Bool, +o: Opts, +version: String) -> IO(Unit):
  match ok:
    case True{}:
      start(o, version)
    case False{}:
      reject(opts_bad(o))

def dispatch(+o: Opts, +version: String) -> IO(Unit):
  dispatch_pick(String.is_empty(opts_bad(o)), o, version)

# A reusable copy of an argument list (the elements are Data).
def share(args: List<String>) -> List<&2, String>:
  match args:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{h, share(t)}

def main2(+args: List<&2, String>, +version: String) -> IO(Unit):
  dispatch(parse(List.length(&2, String, args), args, default_opts()), version)

# The entry the CLI dispatches `tui` to: `args` are the words after the verb.
def main(args: List<String>, version: String) -> IO(Unit):
  main2(share(args), version)
