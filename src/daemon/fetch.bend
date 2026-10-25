import Base
import ../act.bend as Act
import ../store/base.bend as SBase
import ../collect.bend as Collect
import ../collectrun.bend as CRun
import ../view.bend as View
import ../policy/types.bend as T
import ./config.bend as Cfg
import ./gather.bend as G

# Fetch the accounts a tick decided to poll and merge each outcome into
# cache/usage.json. This is the CLI's collector (collectrun.collect): it leases
# the rows, fetches (gated refresh for inactive accounts), plans the next poll
# with the proved policy and writes under cache/.usage.lock. There is no second
# usage store.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def disabled_of(+a: T.Account) -> Bool:
  match a:
    case T.Account{n, e, k, d}:
      d

def is_active(+slot: String, +active: Maybe<&2, String>) -> Bool:
  match active:
    case Some{a}:
      String.eq(slot, a)
    case None{}:
      False{}

def info_of(+e: G.Ent, +active: Maybe<&2, String>) -> Collect.Info:
  match e:
    case G.Ent{+slot, email, org, creds, acct}:
      Collect.Info{Maybe.default(&2, U32, U32.read(slot), 0), email, "", org, "", disabled_of(acct), is_active(slot, active), creds}

def infos(+es: List<&2, G.Ent>, +active: Maybe<&2, String>) -> List<&2, Collect.Info>:
  match es:
    case Nil{}:
      []
    case Con{e, t}:
      info_of(e, active) <> infos(t, active)

# The threshold in tenths of a percent, as the collector wants it.
def tenths(+cfg: Cfg.Cfg) -> U32:
  (Cfg.cfg_threshold(cfg) / 10 : U32)

def discard(+rs: List<&2, View.Acct>) -> Act.of(Unit):
  Act.pure(Unit, Unit{})

def fetch_all(+ctx: SBase.Ctx, +cfg: Cfg.Cfg, +es: List<&2, G.Ent>, +active: Maybe<&2, String>, +now: U32) -> Act.of(Unit):
  do ActM<Unit>:
    rs : List<&2, View.Acct> <- CRun.collect(ctx, infos(es, active), now, Cfg.cfg_models(cfg), tenths(cfg), U32.to_nat(now))
    discard(rs)
