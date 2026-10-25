import Base
import ../json.bend as Json
import ../act.bend as Act
import ../store/base.bend as SBase
import ../policy/types.bend as T
import ../policy/usage.bend as PU
import ./config.bend as Cfg
import ./gather.bend as G
import ./view.bend as V
import ./plan.bend as Plan
import ./fetch.bend as Fetch

# The fetch half of a tick: poll what is due (the active account and one
# candidate, then everyone when the active account is shaky) and hand back the
# snapshot with the refreshed cache rows. Kept apart from `tick` so the policy
# never shares a module with the usage and switch code.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def is_token_expired(+u: T.Usage) -> Bool:
  match u:
    case T.Usage{s, five, fr, seven, sr, ss, fa, bo, er, fl, np, pi, ad, hu, cu, T.TokenExpired{}}:
      True{}
    case _:
      False{}

def escalate2(+h: Maybe<&2, Nat>, +expired: Bool, +thr: U32) -> Bool:
  match h:
    case None{}:
      Bool.not(expired)
    case Some{x}:
      Nat.is_ge(Nat.sub(T.full(), x), Nat.sub(U32.to_nat(thr), 1500n))

# Fetch every candidate too when the active account's headroom is unknown (and
# the token is not just expired on an idle Claude Code), or it is within 15
# points of the threshold.
def should_escalate(+m: Maybe<&2, T.Usage>, +now: Nat, +thr: U32, +ms: List<&2, String>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{u}:
      escalate2(PU.headroom(u, now, ms), is_token_expired(u), thr)

def fetch_pass(+ctx: SBase.Ctx, +cfg: Cfg.Cfg, +targets: List<&2, G.Ent>, +active: Maybe<&2, String>, +now: U32, +rows: Json.Json) -> Act.of(Json.Json):
  Act.cond(Json.Json, List.is_empty(&2, G.Ent, targets), Act.pure(Json.Json, rows),
    do ActM<Json.Json>:
      Fetch.fetch_all(ctx, cfg, targets, active, now)
      Act.lift(Json.Json, G.read_rows(SBase.root_of(ctx))))

def escalation(+ctx: SBase.Ctx, +es: List<&2, G.Ent>, +active: String, +rows1: Json.Json, +rows0: Json.Json, +now: U32, +cfg: Cfg.Cfg) -> Act.of(Json.Json):
  fetch_pass(ctx, cfg, Plan.escalated(es, V.usages_of(rows1, es, Some{active}, now), Some{active}, Plan.first_pass(es, V.usages_of(rows0, es, Some{active}, now), Some{active}, V.nat(now), V.pol_cfg(cfg)), V.nat(now), V.pol_cfg(cfg), Cfg.cfg_models(cfg)), Some{active}, now, rows1)

def shaky(+es: List<&2, G.Ent>, +active: String, +rows1: Json.Json, +now: U32, +cfg: Cfg.Cfg) -> Bool:
  should_escalate(V.usage_for(V.usages_of(rows1, es, Some{active}, now), V.slot_nat_of(active)), V.nat(now), Cfg.cfg_threshold(cfg), Cfg.cfg_models(cfg))

def second_pass(+ctx: SBase.Ctx, +es: List<&2, G.Ent>, +active: String, +rows1: Json.Json, +rows0: Json.Json, +now: U32, +cfg: Cfg.Cfg) -> Act.of(Json.Json):
  Act.cond(Json.Json, shaky(es, active, rows1, now, cfg),
    escalation(ctx, es, active, rows1, rows0, now, cfg),
    Act.pure(Json.Json, rows1))

# Fetch what is due, in two passes (the active account and one candidate; then
# everyone when the active account is shaky), and answer the rows as they
# stand.
def collect(+ctx: SBase.Ctx, +es: List<&2, G.Ent>, +active: String, +rows0: Json.Json, +now: U32, +cfg: Cfg.Cfg) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    rows1 : Json.Json <- fetch_pass(ctx, cfg, Plan.first_pass(es, V.usages_of(rows0, es, Some{active}, now), Some{active}, V.nat(now), V.pol_cfg(cfg)), Some{active}, now, rows0)
    second_pass(ctx, es, active, rows1, rows0, now, cfg)

def snap_with(+s: G.Snap, +rows: Json.Json) -> G.Snap:
  match s:
    case G.Snap{seq, live, active, st, rows0, ents}:
      G.Snap{seq, live, active, st, rows, ents}

def refresh2(+ctx: SBase.Ctx, +cfg: Cfg.Cfg, +now: U32, +s: G.Snap, +a: String) -> Act.of(G.Snap):
  do ActM<G.Snap>:
    rows : Json.Json <- collect(ctx, G.snap_ents(s), a, G.snap_rows(s), now, cfg)
    return snap_with(s, rows)

# The snapshot with the due accounts fetched; unchanged without an active account.
def refresh3(+a: Maybe<&2, String>, +ctx: SBase.Ctx, +cfg: Cfg.Cfg, +now: U32, +s: G.Snap) -> Act.of(G.Snap):
  match a:
    case None{}:
      Act.pure(G.Snap, s)
    case Some{x}:
      refresh2(ctx, cfg, now, s, x)

# The snapshot with the due accounts fetched; unchanged without an active account.
def refresh(+ctx: SBase.Ctx, +cfg: Cfg.Cfg, +now: U32, +s: G.Snap) -> Act.of(G.Snap):
  refresh3(G.snap_active(s), ctx, cfg, now, s)

def some(+s: G.Snap) -> Act.of(Maybe<&2, G.Snap>):
  Act.pure(Maybe<&2, G.Snap>, Some{s})

def refresh_opt(+ctx: SBase.Ctx, +cfg: Cfg.Cfg, +now: U32, +m: Maybe<&2, G.Snap>) -> Act.of(Maybe<&2, G.Snap>):
  match m:
    case None{}:
      Act.pure(Maybe<&2, G.Snap>, None{})
    case Some{s}:
      Act.bind(G.Snap, Maybe<&2, G.Snap>, refresh(ctx, cfg, now, s), r => some(r))
