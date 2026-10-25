import Base
import ../../src/json.bend as Json
import ../../src/fs.bend as Fs
import ../../src/act.bend as Act
import ../../src/store.bend as Store
import ../../src/swbase.bend as SwBase
import ../../src/swlive.bend as SwLive
import ../../src/switch.bend as Switch
import ../../src/store/base.bend as SBase

# A driver that speaks the CLI's `switch` argv, for tests/switch_it.sh and the
# parity replay of fixtures 11-18:
#   switch-it switch [IDENT] [--json] [--force] [--strategy S] [--model M]
# It prints the result object (or the error envelope, exit 1). The delay before
# the post-switch re-read comes from $CSWAP_SWITCH_VERIFY_DELAY_MS (default 2000).

type Args is Data:
  Args{ident: Maybe<&2, String>, force: Bool, strategy: String, models: List<&2, String>}

def first(+t: List<&2, String>) -> String:
  match t:
    case Con{x, r}:
      x
    case Nil{}:
      ""

def upd2(+is_force: Bool, +is_strat: Bool, +is_model: Bool, +is_flag: Bool, +h: String, +t: List<&2, String>, +ident: Maybe<&2, String>, +force: Bool, +strategy: String, +models: List<&2, String>) -> Args:
  match is_force is_strat is_model is_flag:
    case True{} _ _ _:
      Args{ident, True{}, strategy, models}
    case False{} True{} _ _:
      Args{ident, force, first(t), models}
    case False{} False{} True{} _:
      Args{ident, force, strategy, first(t) <> models}
    case False{} False{} False{} True{}:
      Args{ident, force, strategy, models}
    case False{} False{} False{} False{}:
      Args{Some{h}, force, strategy, models}

def upd(+h: String, +t: List<&2, String>, a: Args) -> Args:
  match a:
    case Args{ident, force, strategy, models}:
      upd2(String.eq(h, "--force"), String.eq(h, "--strategy"), String.eq(h, "--model"), String.starts_with(h, "-"), h, t, ident, force, strategy, models)

def skip2(+two: Bool, +t: List<&2, String>) -> List<&2, String>:
  match two:
    case True{}:
      List.drop(&2, String, t, 1n)
    case False{}:
      t

def skip(+h: String, +t: List<&2, String>) -> List<&2, String>:
  skip2(String.eq(h, "--strategy") || String.eq(h, "--model"), t)

def parse(+fuel: Nat, +xs: List<&2, String>, a: Args) -> Args:
  match fuel xs:
    case _ Nil{}:
      a
    case 0n _:
      a
    case 1n+p Con{h, +t}:
      parse(p, skip(h, t), upd(h, t, a))

def out(r: Fs.Res(Json.Json)) -> IO(Unit):
  match r:
    case Done{j}:
      IO.print(Json.emit_pretty(j))
    case Fail{(code, msg)}:
      IO.bind(Unit, Unit, IO.print(Json.emit_pretty(SwBase.error_envelope(code, msg))), u => IO.exit(1))

def models_out(r: Fs.Res(Json.Json), +strategy: String, +models: List<&2, String>) -> Fs.Res(Json.Json):
  match r:
    case Fail{e}:
      Fail{e}
    case Done{j}:
      Done{SwBase.with_models(j, SwBase.sel_ls(String.eq(strategy, "best") || String.eq(strategy, "next-available"), models, []), "cli")}

def run3(+ident: Maybe<&2, String>, +force: Bool, +strategy: String, +models: List<&2, String>, +ctx: SBase.Ctx, +opts: SwLive.Opts) -> IO(Unit):
  match ident:
    case Some{id}:
      IO.bind(Fs.Res(Json.Json), Unit, Switch.switch_to(ctx, id, force, opts), out)
    case None{}:
      IO.bind(Fs.Res(Json.Json), Unit, Switch.switch_auto(ctx, strategy, models, opts), r => out(models_out(r, strategy, models)))

def run2(+ctx: SBase.Ctx, a: Args, +opts: SwLive.Opts) -> IO(Unit):
  match a:
    case Args{ident, force, strategy, models}:
      run3(ident, force, strategy, models, ctx, opts)

def delay_of(r: Result<&1, &1, U32 & String, String>) -> U32:
  match r:
    case Fail{e}:
      2000
    case Done{s}:
      Maybe.default(&2, U32, U32.read(s), 2000)

def oracle_of(r: Result<&1, &1, U32 & String, String>) -> SwLive.Oracle:
  match r:
    case Fail{e}:
      SwLive.OHttp{}
    case Done{p}:
      SwLive.OFile{p}

def opts_of2(d: Result<&1, &1, U32 & String, String>, o: Result<&1, &1, U32 & String, String>) -> SwLive.Opts:
  SwLive.Opts{delay_of(d), oracle_of(o)}

def run1(+args: List<&2, String>, +ctx: SBase.Ctx, r: Result<&1, &1, U32 & String, String>, o: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  run2(ctx, parse(List.length(&2, String, args), args, Args{None{}, False{}, "", []}), opts_of2(r, o))

def run00(+args: List<&2, String>, +ctx: SBase.Ctx, r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, String>, Unit, IO.get_env("CSWAP_SWITCH_ORACLE_FILE"), o => run1(args, ctx, r, o))

def run0(+args: List<&2, String>, +ctx: SBase.Ctx) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, String>, Unit, IO.get_env("CSWAP_SWITCH_VERIFY_DELAY_MS"), r => run00(args, ctx, r))

def dup(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{+h, t}:
      h <> dup(t)

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{cmd, rest}}:
      IO.bind(SBase.Ctx, Unit, Store.ctx_env(), ctx => run0(dup(rest), ctx))
    case _:
      IO.die(Unit, 2, "usage: switch-it switch [IDENT] [--json] [--force] [--strategy S] [--model M]")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
