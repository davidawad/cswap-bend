import Base
import ../policy/algo.bend as A
import ../json.bend as Json
import ../act.bend as Act
import ../clock.bend as Clock
import ../store.bend as Store
import ../store/base.bend as SBase
import ../swlive.bend as L
import ../policy/types.bend as T
import ../policy/usage.bend as PU
import ../policy/rank.bend as PR
import ../policy/decide.bend as D
import ./events.bend as Ev
import ./cadence.bend as Cad
import ./config.bend as Cfg
import ./gather.bend as G
import ./view.bend as V
import ./plan.bend as Plan
import ./dec.bend as Dc
import ./status.bend as Stat

# One tick of `cswap auto` (autoswitch.py _tick_inner): look at the roster
# and the live login, fetch what is due, print the poll, ask the policy what
# to do, and act. Everything it prints is an event (a Json), returned in order.

type Env is Data:
  Env{ctx: SBase.Ctx, cfg: Cfg.Cfg, dry_run: Bool, opts: L.Opts, mem: T.Mem, checked: Bool, skip: List<&2, String>}

# The tick's events and sleeper facts, the engine's counters for the next tick,
# and what the status file shows.
type Out is Data:
  Out{res: Dc.TickRes, mem: T.Mem, active: Maybe<&2, String>, entries: List<&2, Stat.Entry>, accts: Json.Json, checked: Bool}

# Either the tick is over (nothing to decide) or the decision is ready to act
# on; `out` carries the poll events so far.
type Next is Data:
  NDone{out: Out}
  NAct{out: Out, ctx: Dc.Ctx, dec: Dc.Dec}

# ---- nobody to watch -----------------------------------------------------------------------------

def env_ctx(e: Env) -> SBase.Ctx:
  match e:
    case Env{c, cf, d, o, m, k, sk}:
      c

def env_cfg(e: Env) -> Cfg.Cfg:
  match e:
    case Env{c, cf, d, o, m, k, sk}:
      cf

def env_dry(e: Env) -> Bool:
  match e:
    case Env{c, cf, d, o, m, k, sk}:
      d

def env_opts(e: Env) -> L.Opts:
  match e:
    case Env{c, cf, d, o, m, k, sk}:
      o

def env_checked(e: Env) -> Bool:
  match e:
    case Env{c, cf, d, o, m, k, sk}:
      k

def env_skip(e: Env) -> List<&2, String>:
  match e:
    case Env{c, cf, d, o, m, k, sk}:
      sk

def with_skip(e: Env, +skip: List<&2, String>) -> Env:
  match e:
    case Env{c, cf, d, o, m, k, sk}:
      Env{c, cf, d, o, m, k, skip}

def env_mem(e: Env) -> T.Mem:
  match e:
    case Env{c, cf, d, o, m, k, sk}:
      m

def idle_detail(+live: Bool) -> String:
  match live:
    case True{}:
      "run 'cswap --add-account' to include it in rotation"
    case False{}:
      "log in and run 'cswap --add-account' first"

def idle_reason(+live: Bool) -> String:
  match live:
    case True{}:
      "unmanaged-active-account"
    case False{}:
      "no-active-account"

def idle_events(+ts: String, +thr: U32, +live: Bool) -> List<&2, Json.Json>:
  [Ev.poll(ts, Json.JNull{}, [], thr), Ev.no_switch(ts, idle_reason(live), idle_detail(live))]

def idle_out(+env: Env, +ts: String, +live: Bool) -> Out:
  Out{Dc.TickRes{Cad.Info{Cad.NoAction{}, None{}, False{}, False{}, None{}}, idle_events(ts, Cfg.cfg_threshold(env_cfg(env)), live)}, env_mem(env), None{}, [], Json.arr([]), env_checked(env)}

def has_live(+s: G.Snap) -> Bool:
  match s:
    case G.Snap{seq, +live, active, st, rows, ents}:
      SBase.nonempty(L.lv_email(live)) || SBase.nonempty(L.lv_creds(live))

# ---- what the policy said --------------------------------------------------------------------------

def secs(+n: Nat) -> U32:
  U32.from_nat(n)

def opt_secs(+m: Maybe<&2, Nat>) -> Maybe<&2, U32>:
  match m:
    case Some{n}:
      Some{secs(n)}
    case None{}:
      None{}

def exhausted_dec(+e: Maybe<&2, Nat>) -> Dc.Dec:
  Dc.DExhausted{opt_secs(e)}

def left_headroom(+a: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Maybe<&2, U32>:
  match a:
    case Some{u}:
      V.head_u32(PU.headroom(u, now, ms))
    case None{}:
      None{}

# ---- the active account ----------------------------------------------------------------------------

def dec_of(+d: T.Decision, +es: List<&2, G.Ent>, +active: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Dc.Dec:
  match d:
    case T.NoSwitch{T.AllExhausted{e}, detail}:
      exhausted_dec(e)
    case T.NoSwitch{r, detail}:
      Dc.DNone{T.reason.name(r), detail}
    case T.Switch{+to, trig, why, h, mode, rec, bar}:
      Dc.DGo{Nat.show(to), V.email_of(es, Nat.show(to)), T.trigger.name(trig), left_headroom(active, now, ms), opt_secs(PR.rec.row(active, now, ms))}

def active_nat(+a: String) -> Nat:
  V.slot_nat_of(a)

# ---- one tick -----------------------------------------------------------------------------------------

def next_poll_of(+m: Maybe<&2, T.Usage>) -> Maybe<&2, U32>:
  match m:
    case Some{T.Usage{s, five, fr, seven, sr, ss, fa, bo, er, fl, np, pi, ad, hu, cu, se}}:
      opt_secs(np)
    case _:
      None{}

def iso_opt(+m: Maybe<&2, Nat>) -> Maybe<&2, String>:
  match m:
    case Some{n}:
      Some{Clock.iso8601_utc(secs(n))}
    case None{}:
      None{}

def sel_bo(+c: Bool, +x: Maybe<&2, String>, +y: Maybe<&2, String>) -> Maybe<&2, String>:
  match c:
    case True{}:
      x
    case False{}:
      y

def backoff_iso(+u: T.Usage, +now: Nat) -> Maybe<&2, String>:
  match u:
    case T.Usage{s, five, fr, seven, sr, ss, fa, +bo, er, fl, np, pi, ad, hu, cu, se}:
      sel_bo(Nat.is_gt(bo, now), Some{Clock.iso8601_utc(secs(bo))}, None{})

def opt_u(+m: Maybe<&2, Nat>) -> Maybe<&2, U32>:
  V.head_u32(m)

def entry_of(+u: T.Usage, +now: Nat, +ms: List<&2, String>, +rows: Json.Json, +e: G.Ent) -> Stat.Entry:
  match u:
    case T.Usage{+s, +five, fr, +seven, sr, ss, +fa, bo, er, fl, np, pi, ad, hu, cu, se}:
      Stat.Entry{Nat.show(s), opt_u(five), opt_u(seven), iso_opt(fa), backoff_iso(u, now), V.err_text(V.row_of(rows, e))}

def entry_push(+m: Maybe<&2, T.Usage>, +e: G.Ent, +rows: Json.Json, +now: Nat, +ms: List<&2, String>, +rest: List<&2, Stat.Entry>) -> List<&2, Stat.Entry>:
  match m:
    case Some{u}:
      entry_of(u, now, ms, rows, e) <> rest
    case None{}:
      rest

def entries_of(+es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +rows: Json.Json, +now: Nat, +ms: List<&2, String>) -> List<&2, Stat.Entry>:
  match es:
    case Nil{}:
      []
    case Con{e, t}:
      entry_push(V.usage_for(us, V.slot_nat_of(V.ent_slot(e))), e, rows, now, ms, entries_of(t, us, rows, now, ms))

def poll_event(+ts: String, +active: String, +s: G.Snap, +us: List<&2, T.Usage>, +rows: Json.Json, +now: U32, +cfg: Cfg.Cfg) -> Json.Json:
  Ev.poll(ts, V.ref_json(active, G.snap_ents(s)), V.poll_rows(G.snap_ents(s), us, rows, Cfg.cfg_models(cfg), V.nat(now)), Cfg.cfg_threshold(cfg))

def prefix_poll(+r: Dc.TickRes, +ts: String, +active: String, +s: G.Snap, +us: List<&2, T.Usage>, +rows: Json.Json, +now: U32, +cfg: Cfg.Cfg, +warn: List<&2, Json.Json>) -> Dc.TickRes:
  match r:
    case Dc.TickRes{info, evs}:
      Dc.TickRes{info, poll_event(ts, active, s, us, rows, now, cfg) <> List.append(&2, Json.Json, warn, evs)}

def attempted2(+m: Maybe<&2, Json.Json>, +now: U32) -> Bool:
  match m:
    case Some{Json.JNum{t}}:
      String.eq(Maybe.default(&2, String, List.head(&2, String, String.split(t, '.')), ""), U32.show(now))
    case _:
      False{}

def attempted_now(+row: Json.Json, +now: U32) -> Bool:
  attempted2(Json.get("lastAttemptAt", row), now)

def ent_kind(+e: G.Ent) -> T.AcctKind:
  match e:
    case G.Ent{s, em, o, c, T.Account{n, ae, k, d}}:
      k

def opt_pct(+m: Maybe<&2, Nat>) -> Json.Json:
  match m:
    case Some{p}:
      Ev.fl(secs(p))
    case None{}:
      Json.JNull{}

# "usage-endpoint" or "header-probe" when this tick fetched the account (a
# setup-token is read by the probe), "cache" otherwise.
def source_of(+attempted_now: Bool, +k: T.AcctKind) -> String:
  match attempted_now k:
    case False{} _:
      "cache"
    case True{} T.SetupToken{}:
      "header-probe"
    case True{} _:
      "usage-endpoint"

def log_one(+e: G.Ent, +u: T.Usage, +rows: Json.Json, +now: U32, +ms: List<&2, String>) -> Json.Json:
  match u:
    case T.Usage{s, five, fr, seven, sr, ss, fa, bo, er, fl, np, pi, ad, hu, cu, se}:
      Json.JObj{Json.JField{"slot", Json.JNum{Nat.show(s)}, Json.JField{"source", Json.JStr{source_of(attempted_now(V.row_of(rows, e), now), ent_kind(e))},
        Json.JField{"pct_5h", opt_pct(five), Json.JField{"pct_7d", opt_pct(seven), Json.JField{"error", V.opt_json(V.err_text(V.row_of(rows, e))), Json.JNil{}}}}}}}

def log_push(+m: Maybe<&2, T.Usage>, +e: G.Ent, +rows: Json.Json, +now: U32, +ms: List<&2, String>, +rest: List<&2, Json.Json>) -> List<&2, Json.Json>:
  match m:
    case Some{u}:
      log_one(e, u, rows, now, ms) <> rest
    case None{}:
      rest

def log_accts(+es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +rows: Json.Json, +now: U32, +ms: List<&2, String>) -> List<&2, Json.Json>:
  match es:
    case Nil{}:
      []
    case Con{e, t}:
      log_push(V.usage_for(us, V.slot_nat_of(V.ent_slot(e))), e, rows, now, ms, log_accts(t, us, rows, now, ms))

def readable2(+m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match m:
    case Some{u}:
      PU.trusted(u, now, ms)
    case None{}:
      False{}

def readable(+e: G.Ent, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  readable2(V.usage_for(us, V.slot_nat_of(V.ent_slot(e))), now, ms)

def is_api(+k: T.AcctKind) -> Bool:
  match k:
    case T.ApiKey{}:
      True{}
    case _:
      False{}

def watched(+e: G.Ent) -> Bool:
  Plan.eligible(e) && Bool.not(is_api(ent_kind(e)))

# Every account the guard looks at (switchable, not quarantined, not an API
# key) has a trusted reading.
def all_readable(+es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Bool:
  match es:
    case Nil{}:
      True{}
    case Con{e, t}:
      Bool.not(watched(e)) || (readable(e, us, now, ms) && all_readable(t, us, now, ms))

def keep_name(+is_all: Bool, +h: String, +rest: List<&2, String>) -> List<&2, String>:
  match is_all:
    case True{}:
      rest
    case False{}:
      h <> rest

def lower_names(+ms: List<&2, String>) -> List<&2, String>:
  match ms:
    case Nil{}:
      []
    case Con{h, t}:
      keep_name(String.eq(String.to_lower(h), "all"), h, lower_names(t))

def checked_after(+env: Env, +es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +now: Nat) -> Bool:
  env_checked(env) || List.is_empty(&2, String, lower_names(Cfg.cfg_models(env_cfg(env)))) || all_readable(es, us, now, Cfg.cfg_models(env_cfg(env)))

def check_ready(+env: Env, +es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +now: Nat) -> Bool:
  Bool.not(env_checked(env)) && Bool.not(List.is_empty(&2, String, lower_names(Cfg.cfg_models(env_cfg(env))))) && all_readable(es, us, now, Cfg.cfg_models(env_cfg(env)))

def miss_pick(+found: Bool, +h: String, +rest: List<&2, String>) -> List<&2, String>:
  match found:
    case True{}:
      rest
    case False{}:
      h <> rest

def missing(+wanted: List<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match wanted:
    case Nil{}:
      []
    case Con{h, t}:
      miss_pick(PU.model.wanted(String.to_lower(h), seen), h, missing(t, seen))

def scoped_names(+ss: List<&2, T.Scoped>) -> List<&2, String>:
  match ss:
    case Nil{}:
      []
    case Con{T.Scoped{n, p, r}, t}:
      String.to_lower(n) <> scoped_names(t)

def names_of(+m: Maybe<&2, T.Usage>) -> List<&2, String>:
  match m:
    case Some{T.Usage{s, five, fr, seven, sr, ss, fa, bo, er, fl, np, pi, ad, hu, cu, se}}:
      scoped_names(ss)
    case None{}:
      []

def seen_names(+es: List<&2, G.Ent>, +us: List<&2, T.Usage>) -> List<&2, String>:
  match es:
    case Nil{}:
      []
    case Con{e, t}:
      List.append(&2, String, names_of(V.usage_for(us, V.slot_nat_of(V.ent_slot(e)))), seen_names(t, us))

def warn_text(+names: List<&2, String>) -> String:
  "autoswitch.model: " ++ String.join(names, ", ") ++ " matches no account's usage windows — only the 5h/7d limits are being watched for it (typo?)"

def warn_events(+ts: String, +miss: List<&2, String>) -> List<&2, Json.Json>:
  match miss:
    case Nil{}:
      []
    case Con{h, t}:
      [Ev.config_warning(ts, warn_text(Con{h, t}))]

def warn2(+ready: Bool, env: Env, +es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +ts: String) -> List<&2, Json.Json>:
  match ready:
    case True{}:
      warn_events(ts, missing(lower_names(Cfg.cfg_models(env_cfg(env))), seen_names(es, us)))
    case False{}:
      []

def model_warning(+env: Env, +es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +now: Nat, +ts: String) -> List<&2, Json.Json>:
  warn2(check_ready(env, es, us, now), env, es, us, ts)

def apply_ctx(+env: Env, +s: G.Snap, +active: String, +us: List<&2, T.Usage>, +now: U32, +ts: String) -> Dc.Ctx:
  Dc.Ctx{env_ctx(env), env_dry(env), env_cfg(env), now, ts, env_opts(env), V.ref_json(active, G.snap_ents(s)), next_poll_of(V.usage_for(us, active_nat(active)))}

def to_dec(env: Env, +s: G.Snap, +active: String, +us: List<&2, T.Usage>, +now: U32, +d: T.Decision) -> Dc.Dec:
  dec_of(d, G.snap_ents(s), V.usage_for(us, active_nat(active)), V.nat(now), Cfg.cfg_models(env_cfg(env)))

def mem_next(env: Env, +s: G.Snap, +active: String, +us: List<&2, T.Usage>, +now: U32, +pcfg: T.Config) -> T.Mem:
  D.mem_after(active_nat(active), V.accounts_of(G.snap_ents(s)), us, V.nat(now), pcfg, env_mem(env))

def entries_for(env: Env, +s: G.Snap, +us: List<&2, T.Usage>, +rows: Json.Json, +now: U32) -> List<&2, Stat.Entry>:
  entries_of(G.snap_ents(s), us, rows, V.nat(now), Cfg.cfg_models(env_cfg(env)))

def log_for(env: Env, +s: G.Snap, +us: List<&2, T.Usage>, +rows: Json.Json, +now: U32) -> Json.Json:
  Json.arr(log_accts(G.snap_ents(s), us, rows, now, Cfg.cfg_models(env_cfg(env))))

def lead_res(+env: Env, +s: G.Snap, +active: String, +rows: Json.Json, +now: U32, +ts: String, +us: List<&2, T.Usage>, r: Dc.TickRes) -> Dc.TickRes:
  prefix_poll(r, ts, active, s, us, rows, now, env_cfg(env), model_warning(env, G.snap_ents(s), us, V.nat(now), ts))

def made_out(+env: Env, +s: G.Snap, +active: String, +rows: Json.Json, +now: U32, +ts: String, +us: List<&2, T.Usage>, +pcfg: T.Config, r: Dc.TickRes) -> Out:
  Out{lead_res(env, s, active, rows, now, ts, us, r), mem_next(env, s, active, us, now, pcfg), Some{active}, entries_for(env, s, us, rows, now), log_for(env, s, us, rows, now), checked_after(env, G.snap_ents(s), us, V.nat(now))}

def lead_out(env: Env, +s: G.Snap, +active: String, +rows: Json.Json, +now: U32, +ts: String, +us: List<&2, T.Usage>, +pcfg: T.Config) -> Out:
  made_out(env, s, active, rows, now, ts, us, pcfg, Dc.TickRes{Cad.Info{Cad.NoAction{}, None{}, False{}, False{}, None{}}, []})

# The tick up to the decision: the poll (and warning) events, the counters, and
# what to do about it. Acting on it is `apply`'s business (it needs the switch).
def decide_out3(+env: Env, +s: G.Snap, +active: String, +rows: Json.Json, +now: U32, +ts: String, +us: List<&2, T.Usage>, +pcfg: T.Config, +d: T.Decision) -> Next:
  NAct{lead_out(env, s, active, rows, now, ts, us, pcfg), apply_ctx(env, s, active, us, now, ts), to_dec(env, s, active, us, now, d)}

def decide_out2(+env: Env, +s: G.Snap, +active: String, +rows: Json.Json, +now: U32, +ts: String, +us: List<&2, T.Usage>, +pcfg: T.Config) -> Next:
  decide_out3(env, s, active, rows, now, ts, us, pcfg, A.decide_cfg(Cfg.cfg_strategy(env_cfg(env)), active_nat(active), V.snap_accounts(s), us, V.nat(now), pcfg, V.snap_state(s), env_mem(env)))

def decide_out(+env: Env, +s: G.Snap, +active: String, +rows: Json.Json, +now: U32, +ts: String) -> Next:
  decide_out2(env, s, active, rows, now, ts, V.usages_of(rows, G.snap_ents(s), Some{active}, now), V.pol_cfg(env_cfg(env)))

def active_out(env: Env, +s: G.Snap, +active: String, +now: U32, +ts: String) -> Next:
  decide_out(env, s, active, G.snap_rows(s), now, ts)

def snap_out2(env: Env, +now: U32, +ts: String, +s: G.Snap, +active: Maybe<&2, String>) -> Next:
  match active:
    case None{}:
      NDone{idle_out(env, ts, has_live(s))}
    case Some{a}:
      active_out(env, s, a, now, ts)

def snap_out(env: Env, +now: U32, +ts: String, +m: Maybe<&2, G.Snap>) -> Next:
  match m:
    case None{}:
      NDone{idle_out(env, ts, False{})}
    case Some{s}:
      snap_out2(env, now, ts, s, G.snap_active(s))

# One tick over a snapshot whose rows are already refreshed (see `collect`).
def tick(+env: Env, +now: U32, +m: Maybe<&2, G.Snap>) -> Next:
  snap_out(env, now, Clock.iso8601_utc(now), G.skip_snap(m, env_skip(env)))

# ---- the structured log: where each account's reading came from -----------------------------------

# ---- the one-shot model-name typo guard ----------------------------------------------------------------
