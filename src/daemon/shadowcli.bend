import Base
import ../fs.bend as Fs
import ../act.bend as Act
import ../store/base.bend as SBase
import ../swlive.bend as L
import ./config.bend as Cfg
import ./shadow.bend as Sh

# The `--shadow` / `--shadow-log PATH` flags of `cswap auto`, taken out before
# the ordinary flags are parsed, and the shadow run they select.

# shadow?, the log path, the remaining arguments.

type Split is Data:
  Split{shadow: Bool, log: Maybe<&2, String>, rest: List<&2, String>}

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def sp_shadow(+s: Split) -> Bool:
  match s:
    case Split{sh, l, r}:
      sh

def sp_log(+s: Split) -> Maybe<&2, String>:
  match s:
    case Split{sh, l, r}:
      l

def sp_rest(+s: Split) -> List<&2, String>:
  match s:
    case Split{sh, l, r}:
      r

def keep(+a: String, +s: Split) -> Split:
  match s:
    case Split{sh, l, r}:
      Split{sh, l, a <> r}

def mark(+s: Split) -> Split:
  match s:
    case Split{sh, l, r}:
      Split{True{}, l, r}

def set_log(+v: String, +s: Split) -> Split:
  match s:
    case Split{sh, l, r}:
      Split{sh, Some{v}, r}

def pick(+pend: Bool, +is_sh: Bool, +is_log: Bool, +a: String, +r: Split) -> Split:
  match pend is_sh is_log:
    case True{} _ _:
      set_log(a, r)
    case False{} True{} _:
      mark(r)
    case False{} False{} True{}:
      r
    case False{} False{} False{}:
      keep(a, r)

def next_pend(+pend: Bool, +is_log: Bool) -> Bool:
  match pend:
    case True{}:
      False{}
    case False{}:
      is_log

# `pend`: the previous argument was --shadow-log, so this one is its value.
def split(+xs: List<&2, String>, +pend: Bool) -> Split:
  match xs:
    case Nil{}:
      Split{False{}, None{}, []}
    case Con{a, t}:
      pick(pend, String.eq(a, "--shadow"), String.eq(a, "--shadow-log"), a, split(t, next_pend(pend, String.eq(a, "--shadow-log"))))

def settings_text(r: Fs.Res(String)) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{t}:
      t

def read_settings(+ctx: SBase.Ctx) -> Act.of(String):
  Act.lift(String, IO.bind(Fs.Res(String), String, Fs.read_file(SBase.root_of(ctx) ++ "/settings.json"), r => IO.pure(String, settings_text(r))))

def flag_once(+f: Cfg.Flags) -> Bool:
  match f:
    case Cfg.Flags{o, j, d, th, iv, cd, st, md, ia}:
      o

def started(+ctx: SBase.Ctx, +opts: L.Opts, +log: String, +f: Cfg.Flags, +text: String) -> Act.of(U32):
  Sh.run(Sh.Sh{ctx, Cfg.merge(Cfg.from_text(text), f), opts, log}, flag_once(f))

def with_flags(+ctx: SBase.Ctx, +opts: L.Opts, +log: String, r: Result<&2, &2, String, Cfg.Flags>) -> Act.of(U32):
  match r:
    case Fail{msg}:
      Act.fail(U32, 2, "cswap auto: error: " ++ msg)
    case Done{f}:
      Act.bind(String, U32, read_settings(ctx), t => started(ctx, opts, log, f, t))

def with_log(+ctx: SBase.Ctx, +opts: L.Opts, +m: Maybe<&2, String>, +rest: List<&2, String>) -> Act.of(U32):
  match m:
    case None{}:
      Act.fail(U32, 2, "cswap auto: error: --shadow needs --shadow-log PATH")
    case Some{log}:
      with_flags(ctx, opts, log, Cfg.parse_flags(rest))

# Run `auto --shadow ...` (ARGS is what follows the verb).
def run(+ctx: SBase.Ctx, +opts: L.Opts, +sp: Split) -> Act.of(U32):
  with_log(ctx, opts, sp_log(sp), sp_rest(sp))
