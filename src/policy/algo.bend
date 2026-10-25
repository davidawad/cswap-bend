import Base
import ./types.bend as T
import ./usage.bend as U
import ./rank.bend as R
import ./exhaust.bend as E
import ./decide.bend as D
import ./safe.bend as SF

# Behaviour profiles, part 2: one tick (or one manual rotation) under a
# strategy. `best` is `D.decide`, unchanged. The others share the gates below
# and differ only in the ranking key (`SF.key`):
#
#   gates, in order: unmanaged active account, active API key, unknown active
#   headroom (never switches, there is no failover), and for an automatic tick
#   the threshold and the cooldown; then `SF.pick` over the safe candidates.
#
# A rotation (`VRotate`, the manual `switch` with no target) skips the
# threshold and the cooldown: the user asked to move now.

type Via is Data:
  VAuto{}
  VRotate{}

def via.auto(+v: Via) -> Bool:
  match v:
    case VAuto{}:
      True{}
    case VRotate{}:
      False{}

def drain(+algo: SF.Algo) -> Bool:
  match algo:
    case SF.ADrainFirst{}:
      True{}
    case o:
      False{}

def need.under(+under: Bool, +thr: Nat) -> Nat:
  match under:
    case True{}:
      Nat.add(Nat.sub(T.full(), thr), 1n)
    case False{}:
      1n

# The least headroom a target needs: drain-first and a proactive automatic
# switch must land below the threshold; an at-limit switch or a rotation takes
# any headroom.
def need.of(+algo: SF.Algo, +via: Via, +a: Nat, +thr: Nat) -> Nat:
  need.under(drain(algo) || (via.auto(via) && Nat.is_gt(a, 0n)), thr)

def mode.of(+algo: SF.Algo) -> T.Mode:
  match algo:
    case SF.ASoonestReset{}:
      T.MReset{}
    case o:
      T.MHead{}

def trig.via(+via: Via, +a: Nat) -> T.Trigger:
  match via:
    case VAuto{}:
      D.trig.of(a)
    case VRotate{}:
      T.Proactive{}

def sw(+m: Maybe<&2, SF.Cd>, +algo: SF.Algo, +t: T.Trigger, +next: T.Decision) -> T.Decision:
  match m:
    case None{}:
      next
    case Some{c}:
      match c:
        case SF.Cd{slot, k1, k2, h}:
          T.Switch{slot, t, T.trigger.name(t), h, mode.of(algo), None{}, None{}}

# Nothing qualified: the reason `best` would give. The decision is rebuilt as
# a NoSwitch whatever `d` is, so no proof has to look inside `D.none.cf`.
def nosw(+d: T.Decision) -> T.Decision:
  match d:
    case T.NoSwitch{r, detail}:
      T.NoSwitch{r, detail}
    case o:
      T.NoSwitch{T.NoCandidates{}, ""}

def go.pick(+algo: SF.Algo, +via: Via, +a: Nat, +e: D.Env) -> T.Decision:
  match e:
    case D.Env{active, as, us, now, cfg, st, mem}:
      sw(SF.pick(algo, as, active, us, now, D.cfg.models(cfg), need.of(algo, via, a, D.cfg.threshold(cfg))), algo, trig.via(via, a),
        nosw(D.none.cf(T.Proactive{}, None{}, as, active, us, now, D.cfg.models(cfg))))

def go.cool(+cool: Bool, +algo: SF.Algo, +via: Via, +a: Nat, +e: D.Env) -> T.Decision:
  match cool:
    case True{}:
      T.NoSwitch{T.Cooldown{}, ""}
    case False{}:
      go.pick(algo, via, a, e)

# At limit ignores the cooldown; a proactive switch honours it.
def go.auto(+a: Nat, +algo: SF.Algo, +via: Via, +e: D.Env) -> T.Decision:
  match a:
    case 0n:
      go.pick(algo, via, a, e)
    case 1n+p:
      go.cool(D.in_cooldown(D.st.last_at(D.env.st(e)), D.env.now(e), D.cfg.cooldown(D.env.cfg(e))), algo, via, a, e)

def go.via(+algo: SF.Algo, +via: Via, +a: Nat, +e: D.Env) -> T.Decision:
  match via:
    case VAuto{}:
      go.auto(a, algo, via, e)
    case VRotate{}:
      go.pick(algo, via, a, e)

def go.below(+below: Bool, +algo: SF.Algo, +via: Via, +a: Nat, +e: D.Env) -> T.Decision:
  match below:
    case True{}:
      T.NoSwitch{T.BelowThreshold{}, D.below.detail(a, D.env.cfg(e))}
    case False{}:
      go.via(algo, via, a, e)

def go.known(+ah: Maybe<&2, Nat>, +algo: SF.Algo, +via: Via, +e: D.Env) -> T.Decision:
  match ah:
    case None{}:
      T.NoSwitch{T.ActiveUsageUnknown{}, "headroom unknown; a profile strategy never switches away from an account it cannot read (use 'cswap switch NUM')"}
    case Some{a}:
      go.below(via.auto(via) && Nat.is_lt(Nat.sub(T.full(), a), D.cfg.threshold(D.env.cfg(e))), algo, via, a, e)

def go.run(+algo: SF.Algo, +via: Via, +e: D.Env) -> T.Decision:
  go.known(D.env.ah(e), algo, via, e)

def go.kind(+k: T.AcctKind, +algo: SF.Algo, +via: Via, +e: D.Env) -> T.Decision:
  match k:
    case T.ApiKey{}:
      T.NoSwitch{T.ActiveApiKey{}, "API-key accounts have no quota to watch"}
    case o:
      go.run(algo, via, e)

def go.acct(+m: Maybe<&2, T.Account>, +algo: SF.Algo, +via: Via, +e: D.Env) -> T.Decision:
  match m:
    case None{}:
      T.NoSwitch{T.UnmanagedActive{}, "run 'cswap --add-account' to include it in rotation"}
    case Some{a}:
      match a:
        case T.Account{slot, email, kind, disabled}:
          go.kind(kind, algo, via, e)

def core(+algo: SF.Algo, +via: Via, +e: D.Env) -> T.Decision:
  go.acct(U.account.of(D.env.active(e), D.env.as(e)), algo, via, e)

# One autoswitch tick under `algo`.
def decide(+algo: SF.Algo, +active: Nat, +accounts: List<&2, T.Account>, +usage: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> T.Decision:
  match algo:
    case SF.ABest{}:
      D.decide(active, accounts, usage, now, cfg, st, mem)
    case o:
      core(o, VAuto{}, D.Env{active, accounts, usage, now, cfg, st, mem})

# A manual rotation under `algo`: the target now, whatever the active's
# utilization. `best` ranks by headroom, as `sticky` does.
def rotate(+algo: SF.Algo, +active: Nat, +accounts: List<&2, T.Account>, +usage: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> T.Decision:
  core(algo, VRotate{}, D.Env{active, accounts, usage, now, cfg, T.fresh_state(), T.fresh_mem()})

# One tick under the strategy a name stands for; anything else (best,
# consume-first) is the reference engine.
def decide_cfg(+name: String, +active: Nat, +accounts: List<&2, T.Account>, +usage: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> T.Decision:
  decide(Maybe.default(&2, SF.Algo, SF.parse(name), SF.ABest{}), active, accounts, usage, now, cfg, st, mem)
