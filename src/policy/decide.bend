import Base
import ./types.bend as T
import ./usage.bend as U
import ./rank.bend as R
import ./pick.bend as K
import ./bar.bend as B
import ./exhaust.bend as E

# One autoswitch tick: classify the trigger, honour cooldown, rank the
# candidates, and say why when nothing qualifies. Mirrors AutoSwitchEngine
# ._tick_inner of claude_swap 0.27.2 with patch 0002.
#
# Not decided here (the CLI owns them): freshening the target, quarantining a
# target whose token is dead, the consume-first re-fetch (`stale-usage`),
# `no-viable-target` and `already-active`. To walk the reference's ordered
# list, re-run `decide` with a failed target marked `disabled`.

# What a tick reads.
type Env is Data:
  Env{active: Nat, as: List<&2, T.Account>, us: List<&2, T.Usage>, now: Nat, cfg: T.Config, st: T.State, mem: T.Mem}

def cfg.threshold(+cfg: T.Config) -> Nat:
  match cfg:
    case T.Config{thr, ms, st, iv, cd, hy, ttl, ut, ia}:
      thr

def cfg.models(+cfg: T.Config) -> List<&2, String>:
  match cfg:
    case T.Config{thr, ms, st, iv, cd, hy, ttl, ut, ia}:
      ms

def cfg.include(+cfg: T.Config) -> Bool:
  match cfg:
    case T.Config{thr, ms, st, iv, cd, hy, ttl, ut, ia}:
      ia

def cfg.cf(+cfg: T.Config) -> Bool:
  match cfg:
    case T.Config{thr, ms, st, iv, cd, hy, ttl, ut, ia}:
      K.strat.cf(st)

def in_cooldown(+last: Maybe<&2, Nat>, +now: Nat, +cd: Nat) -> Bool:
  match last:
    case None{}:
      False{}
    case Some{l}:
      Nat.is_lt(Nat.sub(now, l), cd)

def cfg.cooldown(+cfg: T.Config) -> Nat:
  match cfg:
    case T.Config{thr, ms, st, iv, cd, hy, ttl, ut, ia}:
      cd

def st.last_at(+st: T.State) -> Maybe<&2, Nat>:
  match st:
    case T.State{la, lt, lf, sn}:
      la

# ------------------------------------------------ the idle hold, in memory

def is_expired(+s: T.Sentinel) -> Bool:
  match s:
    case T.TokenExpired{}:
      True{}
    case o:
      False{}

def row.expired(+m: Maybe<&2, T.Usage>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{u}:
      is_expired(U.usage.sentinel(u))

def idle.since(+mem: T.Mem, +now: Nat) -> Nat:
  match mem:
    case T.Mem{un, isn}:
      match isn:
        case None{}:
          now
        case Some{t}:
          t

def mem.unhealthy(+mem: T.Mem) -> Nat:
  match mem:
    case T.Mem{un, isn}:
      un

# The idle hold lasts 30 minutes from the first expired tick.
def idle.held(+mem: T.Mem, +now: Nat) -> Bool:
  Nat.is_le(Nat.sub(now, idle.since(mem, now)), 1800n)

def mem.expired(+mem: T.Mem, +now: Nat, +ut: Nat) -> T.Mem:
  T.Mem{Nat.add(mem.unhealthy(mem), 1n), Some{idle.since(mem, now)}}

def mem.hold(+held: Bool, +mem: T.Mem, +now: Nat, +ut: Nat) -> T.Mem:
  match held:
    case True{}:
      T.Mem{0n, Some{idle.since(mem, now)}}
    case False{}:
      mem.expired(mem, now, ut)

# Counters after a tick whose active headroom is unknown.
def mem.unknown(+expired: Bool, +mem: T.Mem, +now: Nat, +ut: Nat) -> T.Mem:
  match expired:
    case False{}:
      T.fresh_mem()
    case True{}:
      mem.hold(idle.held(mem, now), mem, now, ut)

def mem.known(+ah: Maybe<&2, Nat>, +expired: Bool, +mem: T.Mem, +now: Nat, +ut: Nat) -> T.Mem:
  match ah:
    case Some{a}:
      T.fresh_mem()
    case None{}:
      mem.unknown(expired, mem, now, ut)

def mem.ut(+cfg: T.Config) -> Nat:
  match cfg:
    case T.Config{thr, ms, st, iv, cd, hy, ttl, ut, ia}:
      ut

def mem.run(+active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +mem: T.Mem) -> T.Mem:
  mem.known(U.head.row(U.usage.of(active, us), now, cfg.models(cfg)), row.expired(U.usage.of(active, us)), mem, now, mem.ut(cfg))

def mem.api(+include: Bool, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +mem: T.Mem) -> T.Mem:
  match include:
    case False{}:
      mem
    case True{}:
      mem.run(active, us, now, cfg, mem)

def mem.kind(+k: T.AcctKind, +include: Bool, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +mem: T.Mem) -> T.Mem:
  match k:
    case T.ApiKey{}:
      mem.api(include, active, us, now, cfg, mem)
    case o:
      mem.run(active, us, now, cfg, mem)

def mem.acct(+m: Maybe<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +mem: T.Mem) -> T.Mem:
  match m:
    case None{}:
      mem
    case Some{a}:
      match a:
        case T.Account{slot, email, kind, disabled}:
          mem.kind(kind, cfg.include(cfg), active, us, now, cfg, mem)

# The engine's counters after this tick: a known headroom or an unexpired-
# sentinel unknown resets them; an expired token starts the idle hold and,
# once it ran out, counts unhealthy ticks. Unmanaged and API-key actives
# return before touching them.
def mem_after(+active: Nat, +accounts: List<&2, T.Account>, +usage: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +mem: T.Mem) -> T.Mem:
  mem.acct(U.account.of(active, accounts), active, usage, now, cfg, mem)

# ------------------------------------------------------- why nothing qualified

def none.exh.at(+ex: Bool, +e: E.Er) -> T.Decision:
  match ex:
    case True{}:
      T.NoSwitch{T.AllExhausted{E.er.out(e)}, ""}
    case False{}:
      T.NoSwitch{T.NoQualifyingCandidate{}, "no candidate is below the threshold and better than the active account by the hysteresis margin, or usage is unreadable this tick"}

def none.reset(+ars: Maybe<&2, Nat>) -> T.Decision:
  match ars:
    case None{}:
      T.NoSwitch{T.ResetUnknown{}, "active account's weekly reset time is unknown; consume-first is idle until it is reported"}
    case Some{r}:
      T.NoSwitch{T.AlreadyConsumingSoonest{}, "no sooner-resetting account with room to spare"}

def none.trig(+t: T.Trigger, +ex: Bool, +ars: Maybe<&2, Nat>, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> T.Decision:
  match t:
    case T.ConsumeFirstT{}:
      none.reset(ars)
    case o:
      none.exh.at(ex, E.earliest(as, us, now, ms, E.ErNone{}))

def none.known(+k: Bool, +t: T.Trigger, +ex: Bool, +ars: Maybe<&2, Nat>, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> T.Decision:
  match k:
    case False{}:
      T.NoSwitch{T.NoComparison{}, "no candidate has readable usage"}
    case True{}:
      none.trig(t, ex, ars, as, us, now, ms)

def none.cf(+t: T.Trigger, +ars: Maybe<&2, Nat>, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> T.Decision:
  none.known(E.any_known(as, active, us, now, ms), t, E.all_exhausted(as, active, us, now, ms), ars, as, us, now, ms)

def trig.not_cf(+t: T.Trigger) -> Bool:
  match t:
    case T.ConsumeFirstT{}:
      False{}
    case o:
      True{}

def api.pick(+m: Maybe<&2, Nat>, +t: T.Trigger, +next: T.Decision) -> T.Decision:
  match m:
    case Some{slot}:
      T.Switch{slot, t, T.trigger.name(t), 0n, T.MApiLast{}, None{}, None{}}
    case None{}:
      next

def api.gate(+ok: Bool, +t: T.Trigger, +as: List<&2, T.Account>, +active: Nat, +next: T.Decision) -> T.Decision:
  match ok:
    case True{}:
      api.pick(E.api.first(as, active), t, next)
    case False{}:
      next

# ------------------------------------------------------------ ranking

def dec.sw(+p: K.Pk, +t: T.Trigger, +bar: Maybe<&2, Nat>, +next: T.Decision) -> T.Decision:
  match p:
    case K.PkAt{slot, r, h, mode}:
      T.Switch{slot, t, T.trigger.name(t), h, mode, r, bar}
    case K.PkNone{}:
      next

def meas.best(+m: R.Meas) -> Nat:
  match m:
    case R.Meas{any, all, best}:
      best

def rank.ctx(+t: T.Trigger, +ah: Maybe<&2, Nat>, +m: R.Meas, +ar: Maybe<&2, Nat>, +ars: Maybe<&2, Nat>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> K.Rk:
  match cfg:
    case T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}:
      K.rk.mk(t, ah, R.all_above(m, ah, thr), meas.best(m), ar, ars, thr, hy, K.strat.cf(stg), active, None{}, us, now, ms)

# The ranking context of a tick, before the bar.
def rk.base(+t: T.Trigger, +ah: Maybe<&2, Nat>, +active: Nat, +as: List<&2, T.Account>, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> K.Rk:
  rank.ctx(t, ah, R.meas(as, active, us, now, cfg.models(cfg), cfg.threshold(cfg), R.Meas{False{}, True{}, 0n}), R.rec.row(U.usage.of(active, us), now, cfg.models(cfg)), R.seven.row(U.usage.of(active, us), now, cfg.models(cfg)), active, us, now, cfg)

# --------------------------------------------------- candidates and cooldown

def below.detail(+a: Nat, +cfg: T.Config) -> String:
  U.pct.label(Nat.sub(T.full(), a)) ++ "% < " ++ U.pct.label(cfg.threshold(cfg)) ++ "%"

# The pick for one ranking context, as a decision: the target, or `next`.
def sw.pick(+rk: K.Rk, +as: List<&2, T.Account>, +t: T.Trigger, +next: T.Decision) -> T.Decision:
  dec.sw(K.pick(as, rk), t, K.rk.bar_of(rk), next)

# Rank with the bar; if that leaves nothing and the barred account has
# recovered, rank again without it.
def choose.retry(+go: Bool, +t: T.Trigger, +as: List<&2, T.Account>, +rk0: K.Rk, +next: T.Decision) -> T.Decision:
  match go:
    case True{}:
      sw.pick(K.rk.bar(rk0, None{}), as, t, next)
    case False{}:
      next

def env.active(+e: Env) -> Nat:
  match e:
    case Env{active, as, us, now, cfg, st, mem}:
      active

def env.as(+e: Env) -> List<&2, T.Account>:
  match e:
    case Env{active, as, us, now, cfg, st, mem}:
      as

def env.cfg(+e: Env) -> T.Config:
  match e:
    case Env{active, as, us, now, cfg, st, mem}:
      cfg

def trig.is_cf(+t: T.Trigger) -> Bool:
  Bool.not(trig.not_cf(t))

def env.now(+e: Env) -> Nat:
  match e:
    case Env{active, as, us, now, cfg, st, mem}:
      now

def env.st(+e: Env) -> T.State:
  match e:
    case Env{active, as, us, now, cfg, st, mem}:
      st

# ------------------------------------------------------ the active account

def env.us(+e: Env) -> List<&2, T.Usage>:
  match e:
    case Env{active, as, us, now, cfg, st, mem}:
      us

def env.mem(+e: Env) -> T.Mem:
  match e:
    case Env{active, as, us, now, cfg, st, mem}:
      mem

def trig.of(+a: Nat) -> T.Trigger:
  match a:
    case 0n:
      T.AtLimit{}
    case 1n+p:
      T.Proactive{}

# The active account's headroom, as this tick reads it.
def env.ah(+e: Env) -> Maybe<&2, Nat>:
  match e:
    case Env{active, as, us, now, cfg, st, mem}:
      U.head.row(U.usage.of(active, us), now, cfg.models(cfg))

# No OAuth candidate qualified: last-resort API-key account, else say why.
def decide.none(+t: T.Trigger, +ars: Maybe<&2, Nat>, +as: List<&2, T.Account>, +active: Nat, +us: List<&2, T.Usage>, +now: Nat, +cfg: T.Config) -> T.Decision:
  match cfg:
    case T.Config{thr, ms, stg, iv, cd, hy, ttl, ut, ia}:
      api.gate(ia && trig.not_cf(t), t, as, active, none.cf(t, ars, as, active, us, now, ms))

def rank.bar(+bar: Maybe<&2, Nat>, +recov: Bool, +t: T.Trigger, +e: Env) -> T.Decision:
  match e:
    case Env{active, as, us, now, cfg, st, mem}:
      sw.pick(K.rk.bar(rk.base(t, env.ah(e), active, as, us, now, cfg), bar), as, t, choose.retry(Bool.not(B.is_none(bar)) && recov, t, as, rk.base(t, env.ah(e), active, as, us, now, cfg), decide.none(t, R.seven.row(U.usage.of(active, us), now, cfg.models(cfg)), as, active, us, now, cfg)))

def rank.go(+t: T.Trigger, +e: Env) -> T.Decision:
  match e:
    case Env{active, as, us, now, cfg, st, mem}:
      rank.bar(B.no_return(t, st, active, B.recovered(st, active, us, env.ah(e), cfg.threshold(cfg), now, cfg.models(cfg)), us, env.ah(e), cfg.threshold(cfg), now, cfg.models(cfg)), B.recovered(st, active, us, env.ah(e), cfg.threshold(cfg), now, cfg.models(cfg)), t, e)

def cands.none(+blocked: Bool, +t: T.Trigger, +e: Env) -> T.Decision:
  match blocked:
    case True{}:
      T.NoSwitch{T.NoCandidates{}, ""}
    case False{}:
      rank.go(t, e)

# A healthy consume-first account with no OAuth peer to compare against is
# below the threshold, exactly as under `best`.
def cands.cf(+hold: Bool, +t: T.Trigger, +e: Env) -> T.Decision:
  match hold:
    case True{}:
      T.NoSwitch{T.BelowThreshold{}, below.detail(K.ah.or0(env.ah(e)), env.cfg(e))}
    case False{}:
      cands.none(Bool.not(E.any_cand(env.as(e), env.active(e))) && Bool.not(cfg.include(env.cfg(e)) && E.any_api(env.as(e), env.active(e))), t, e)

def decide.cands(+t: T.Trigger, +e: Env) -> T.Decision:
  cands.cf(trig.is_cf(t) && Bool.not(E.any_cand(env.as(e), env.active(e))) && Bool.not(B.is_none(env.ah(e))), t, e)

def cool.go(+cool: Bool, +t: T.Trigger, +e: Env) -> T.Decision:
  match cool:
    case True{}:
      T.NoSwitch{T.Cooldown{}, ""}
    case False{}:
      decide.cands(t, e)

# Cooldown bounds proactive and consume-first switches; at-limit and
# failover ignore it.
def decide.trig(+t: T.Trigger, +e: Env) -> T.Decision:
  match t:
    case T.Proactive{}:
      cool.go(in_cooldown(st.last_at(env.st(e)), env.now(e), cfg.cooldown(env.cfg(e))), t, e)
    case T.ConsumeFirstT{}:
      cool.go(in_cooldown(st.last_at(env.st(e)), env.now(e), cfg.cooldown(env.cfg(e))), t, e)
    case o:
      decide.cands(t, e)

def fail.count(+wait: Bool, +n: Nat, +ut: Nat, +e: Env) -> T.Decision:
  match wait:
    case True{}:
      T.NoSwitch{T.ActiveUsageUnknown{}, Nat.show(n) ++ "/" ++ Nat.show(ut) ++ " before failover"}
    case False{}:
      decide.trig(T.Failover{}, e)

def failover.go(+n: Nat, +e: Env) -> T.Decision:
  match e:
    case Env{active, as, us, now, cfg, st, mem}:
      fail.count(Nat.is_lt(n, mem.ut(cfg)), n, mem.ut(cfg), e)

def idle.go(+held: Bool, +e: Env) -> T.Decision:
  match held:
    case True{}:
      T.NoSwitch{T.ActiveIdle{}, "token expired while Claude Code is idle; resumes on next use"}
    case False{}:
      failover.go(Nat.add(mem.unhealthy(env.mem(e)), 1n), e)

def unknown.go(+expired: Bool, +e: Env) -> T.Decision:
  match expired:
    case False{}:
      T.NoSwitch{T.ActiveUsageUnknown{}, "headroom unknown; not counted toward failover"}
    case True{}:
      idle.go(idle.held(env.mem(e), env.now(e)), e)

def below.go(+cf: Bool, +a: Nat, +e: Env) -> T.Decision:
  match cf:
    case True{}:
      decide.trig(T.ConsumeFirstT{}, e)
    case False{}:
      T.NoSwitch{T.BelowThreshold{}, below.detail(a, env.cfg(e))}

def util.go(+below: Bool, +a: Nat, +e: Env) -> T.Decision:
  match below:
    case True{}:
      below.go(cfg.cf(env.cfg(e)), a, e)
    case False{}:
      decide.trig(trig.of(a), e)

def decide.known(+ah: Maybe<&2, Nat>, +e: Env) -> T.Decision:
  match ah:
    case Some{a}:
      util.go(Nat.is_lt(Nat.sub(T.full(), a), cfg.threshold(env.cfg(e))), a, e)
    case None{}:
      unknown.go(row.expired(U.usage.of(env.active(e), env.us(e))), e)

def decide.run(+e: Env) -> T.Decision:
  decide.known(U.head.row(U.usage.of(env.active(e), env.us(e)), env.now(e), cfg.models(env.cfg(e))), e)

def apikey.go(+include: Bool, +e: Env) -> T.Decision:
  match include:
    case True{}:
      decide.run(e)
    case False{}:
      T.NoSwitch{T.ActiveApiKey{}, "API-key accounts have no quota to watch"}

def decide.kind(+k: T.AcctKind, +e: Env) -> T.Decision:
  match k:
    case T.ApiKey{}:
      apikey.go(cfg.include(env.cfg(e)), e)
    case o:
      decide.run(e)

def decide.acct(+m: Maybe<&2, T.Account>, +e: Env) -> T.Decision:
  match m:
    case None{}:
      T.NoSwitch{T.UnmanagedActive{}, "run 'cswap --add-account' to include it in rotation"}
    case Some{a}:
      match a:
        case T.Account{slot, email, kind, disabled}:
          decide.kind(kind, e)

# One autoswitch tick. `st` is autoswitch_state.json (last switch, where it
# came from, what that account looked like), `mem` the engine's counters
# (see `mem_after` for the next ones). Pure: the caller fetches usage,
# applies the decision and records the switch.
def decide(+active: Nat, +accounts: List<&2, T.Account>, +usage: List<&2, T.Usage>, +now: Nat, +cfg: T.Config, +st: T.State, +mem: T.Mem) -> T.Decision:
  decide.acct(U.account.of(active, accounts), Env{active, accounts, usage, now, cfg, st, mem})
