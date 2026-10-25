import Base
import ../../src/store.bend as Store
import ../../src/fs.bend as Fs
import ../../src/act.bend as Act
import ../../src/store/base.bend as SBase
import ../../src/store/plan.bend as SPlan
import ../../src/store/ops.bend as SOps

# A tiny CLI over store for tests/store_it.sh (HOME and CLAUDE_CONFIG_DIR as
# the environment sets them):
#   store-it add-token TOKEN [EMAIL [SLOT]]
#   store-it add-token-slot TOKEN EMAIL SLOT   (overwrites an occupied slot)
#   store-it add [ALIAS]    (adopt the live login; the profile oracle answers
#                            from the JSON file named by $STORE_IT_PROFILE, or
#                            not at all when that is unset)
#   store-it remove IDENT
#   store-it read IDENT

def say(r: Fs.Res(String)) -> IO(Unit):
  IO.bind(String, Unit, IO.pass(String, r), IO.print)

def stub_prof(r: Fs.Res(String)) -> SPlan.Prof:
  match r:
    case Fail{e}:
      SPlan.ProfNone{}
    case Done{t}:
      SPlan.profile_of_text(t)

def stub_fetch2(+path: String, r: Result<&1, &1, U32 & String, String>) -> IO(SPlan.Prof):
  match r:
    case Fail{e}:
      IO.pure(SPlan.Prof, SPlan.ProfNone{})
    case Done{p}:
      IO.bind(Fs.Res(String), SPlan.Prof, Fs.read_file(p), body => IO.pure(SPlan.Prof, stub_prof(body)))

def stub_fetch(+token: String) -> IO(SPlan.Prof):
  IO.bind(Result<&1, &1, U32 & String, String>, SPlan.Prof, IO.get_env("STORE_IT_PROFILE"), r => stub_fetch2(token, r))

def opt(xs: List<String>) -> Maybe<&2, String>:
  match xs:
    case Con{h, t}:
      Some{h}
    case Nil{}:
      None{}

def slot_of(+m: Maybe<&2, String>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      U32.read(s)

def tok(ctx: SBase.Ctx, +t: String, +e: Maybe<&2, String>, +s: Maybe<&2, String>, +yes: Bool) -> IO(Unit):
  IO.bind(Fs.Res(String), Unit, SOps.add_token(ctx, t, e, slot_of(s), yes), say)

def run4(ctx: SBase.Ctx, +tk: Bool, +tks: Bool, +add: Bool, +rm: Bool, args: List<String>) -> IO(Unit):
  match tk tks add rm args:
    case True{} _ _ _ Con{t, Con{e, Con{s, Nil{}}}}:
      tok(ctx, t, Some{e}, Some{s}, False{})
    case True{} _ _ _ Con{t, Con{e, Nil{}}}:
      tok(ctx, t, Some{e}, None{}, False{})
    case True{} _ _ _ Con{t, Nil{}}:
      tok(ctx, t, None{}, None{}, False{})
    case False{} True{} _ _ Con{t, Con{e, Con{s, Nil{}}}}:
      tok(ctx, t, Some{e}, Some{s}, True{})
    case False{} False{} True{} _ args:
      IO.bind(Fs.Res(String), Unit, Store.add_current(ctx, opt(args), None{}, False{}, t => stub_fetch(t)), say)
    case False{} False{} False{} True{} Con{id, Nil{}}:
      IO.bind(Fs.Res(String), Unit, SOps.remove(ctx, id), say)
    case False{} False{} False{} False{} Con{id, Nil{}}:
      IO.bind(Fs.Res(String), Unit, SOps.read_slot(ctx, id), say)
    case _ _ _ _ _:
      IO.die(Unit, 2, "usage")

def run3(ctx: SBase.Ctx, +cmd: String, args: List<String>) -> IO(Unit):
  run4(ctx, String.eq(cmd, "add-token"), String.eq(cmd, "add-token-slot"), String.eq(cmd, "add"), String.eq(cmd, "remove"), args)

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{cmd, rest}}:
      IO.bind(SBase.Ctx, Unit, Store.ctx_env(), ctx => run3(ctx, cmd, rest))
    case _:
      IO.die(Unit, 2, "usage")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
