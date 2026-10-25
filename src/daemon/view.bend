import Base
import ../json.bend as Json
import ../store.bend as Store
import ../store/base.bend as SBase
import ../store/seq.bend as SSeq
import ../usage.bend as Usage
import ../usage/cred.bend as UCred
import ../policy/types.bend as T
import ../policy/usage.bend as PU
import ../policy/rank.bend as PR
import ./rows.bend as Rows
import ./events.bend as Ev
import ./config.bend as Cfg
import ./gather.bend as G
import ./state.bend as St

# Pure bridges between the daemon's data (config, state file, cache rows) and
# the policy's types, and the other way to events.

def nat(+n: U32) -> Nat:
  U32.to_nat(n)

def strategy2(+cf: Bool) -> T.Strategy:
  match cf:
    case True{}:
      T.ConsumeFirst{}
    case False{}:
      T.Best{}

def strategy_of(+s: String) -> T.Strategy:
  strategy2(String.eq(s, "consume-first"))

# serve TTL 180 s; the rest is the settings.
def pol_cfg(+c: Cfg.Cfg) -> T.Config:
  match c:
    case Cfg.Cfg{th, iv, cd, hy, st, ia, ut, ms}:
      T.Config{nat(th), ms, strategy_of(st), nat(iv), nat(cd), nat(hy), 180n, nat(ut), ia}

# ---- autoswitch_state.json -> State ------------------------------------------------------------

def sel_mt(+c: Bool, +x: Maybe<&2, T.Trigger>, +y: Maybe<&2, T.Trigger>) -> Maybe<&2, T.Trigger>:
  match c:
    case True{}:
      x
    case False{}:
      y

def trigger_of(+s: String) -> Maybe<&2, T.Trigger>:
  sel_mt(String.eq(s, "proactive"), Some{T.Proactive{}},
  sel_mt(String.eq(s, "at-limit"), Some{T.AtLimit{}},
  sel_mt(String.eq(s, "failover"), Some{T.Failover{}},
  sel_mt(String.eq(s, "consume-first"), Some{T.ConsumeFirstT{}}, None{}))))

def num_nat(+m: Maybe<&2, Json.Json>) -> Maybe<&2, Nat>:
  Rows.nat_opt(Rows.bind_s(Rows.num_text(m), t => Rows.epoch_text(t)))

def centi_nat(+m: Maybe<&2, Json.Json>) -> Maybe<&2, Nat>:
  Rows.nat_opt(Rows.bind_s(Rows.num_text(m), t => Cfg.centi(t)))

def slot_nat(+m: Maybe<&2, Json.Json>) -> Maybe<&2, Nat>:
  Rows.nat_opt(Rows.bind_s(Rows.str_text(m), t => Cfg.read_u32(t)))

def snap2(+tr: Maybe<&2, Json.Json>, +st: Json.Json) -> T.Snap:
  match tr:
    case Some{Json.JStr{s}}:
      T.Snap{centi_nat(Json.get("leftHeadroom", st)), num_nat(Json.get("leftRecoveryAt", st)), trigger_of(s)}
    case _:
      T.NoSnap{}

def snap_of(+st: Json.Json) -> T.Snap:
  snap2(Json.get("leftTrigger", st), st)

def state_of(+st: Json.Json) -> T.State:
  T.State{Rows.nat_opt(St.last_switch_at(st)), slot_nat(Json.get("lastSwitchTo", st)), num_nat(Json.get("lastSwitchFrom", st)), snap_of(st)}

# ---- accounts and usages ------------------------------------------------------------------------

def accounts_of(+es: List<&2, G.Ent>) -> List<&2, T.Account>:
  match es:
    case Nil{}:
      []
    case Con{G.Ent{s, e, o, c, a}, t}:
      a <> accounts_of(t)

def oauth_of(+creds: String) -> Json.Json:
  SSeq.get_or("claudeAiOauth", Json.unwrap(Json.parse(creds)), Json.JNull{})

def sel_sn(+c: Bool, +x: T.Sentinel, +y: T.Sentinel) -> T.Sentinel:
  match c:
    case True{}:
      x
    case False{}:
      y

def sent2(+is_active: Bool, +has: Bool, +api: Bool, +creds: String, +now: U32) -> T.Sentinel:
  match has api:
    case False{} _:
      T.OtherSentinel{}
    case True{} True{}:
      T.OtherSentinel{}
    case True{} False{}:
      sel_sn(is_active && UCred.expired(oauth_of(creds), now), T.TokenExpired{}, T.NoSentinel{})

# The overlay that hides a row: an expired token on the active account (idle
# Claude Code), or an account with no usable credential or no quota to read.
def sentinel_of(+is_active: Bool, +e: G.Ent, +now: U32) -> T.Sentinel:
  match e:
    case G.Ent{slot, email, org, +creds, acct}:
      sent2(is_active, SBase.nonempty(creds), SBase.looks_like_api_key(creds), creds, now)

def row_guard(+row: Json.Json, +email: String, +org: String) -> Json.Json:
  Store.sel.j(String.eq(SSeq.field_str(row, "email"), email) && String.eq(SSeq.field_str(row, "organizationUuid"), org), row, Json.JNull{})

def row_of(+rows: Json.Json, +e: G.Ent) -> Json.Json:
  match e:
    case G.Ent{slot, email, org, creds, acct}:
      row_guard(SSeq.get_or(slot, rows, Json.JNull{}), email, org)

def is_slot(+active: Maybe<&2, String>, +slot: String) -> Bool:
  match active:
    case Some{a}:
      String.eq(a, slot)
    case None{}:
      False{}

def usage_one(+rows: Json.Json, +e: G.Ent, +active: Maybe<&2, String>, +now: U32) -> T.Usage:
  match e:
    case G.Ent{+slot, +email, +org, +creds, +acct}:
      Rows.usage_of(nat(SSeq.str_u32(slot)), row_of(rows, e), sentinel_of(is_slot(active, slot), e, now))

def usages_of(+rows: Json.Json, +es: List<&2, G.Ent>, +active: Maybe<&2, String>, +now: U32) -> List<&2, T.Usage>:
  match es:
    case Nil{}:
      []
    case Con{e, t}:
      usage_one(rows, e, active, now) <> usages_of(rows, t, active, now)

def sel_mu(+c: Bool, +x: Maybe<&2, T.Usage>, +y: Maybe<&2, T.Usage>) -> Maybe<&2, T.Usage>:
  match c:
    case True{}:
      x
    case False{}:
      y

def usage_pick(+u: T.Usage, +slot: Nat, +rest: Maybe<&2, T.Usage>) -> Maybe<&2, T.Usage>:
  match u:
    case T.Usage{+s, five, fr, seven, sr, ss, fa, bo, er, fl, np, pi, ad, hu, cu, se}:
      sel_mu(Nat.is_eq(s, slot), Some{u}, rest)

def usage_for(+us: List<&2, T.Usage>, +slot: Nat) -> Maybe<&2, T.Usage>:
  match us:
    case Nil{}:
      None{}
    case Con{u, t}:
      usage_pick(u, slot, usage_for(t, slot))

def sel_me(+c: Bool, +x: Maybe<&2, G.Ent>, +y: Maybe<&2, G.Ent>) -> Maybe<&2, G.Ent>:
  match c:
    case True{}:
      x
    case False{}:
      y

def ent_pick(+e: G.Ent, +slot: String, +rest: Maybe<&2, G.Ent>) -> Maybe<&2, G.Ent>:
  match e:
    case G.Ent{+s, em, o, c, a}:
      sel_me(String.eq(s, slot), Some{e}, rest)

def ent_for(+es: List<&2, G.Ent>, +slot: String) -> Maybe<&2, G.Ent>:
  match es:
    case Nil{}:
      None{}
    case Con{e, t}:
      ent_pick(e, slot, ent_for(t, slot))

def email2(+m: Maybe<&2, G.Ent>) -> String:
  match m:
    case Some{G.Ent{s, em, o, c, a}}:
      em
    case None{}:
      ""

# ---- the poll event ----------------------------------------------------------------------------

def email_of(+es: List<&2, G.Ent>, +slot: String) -> String:
  email2(ent_for(es, slot))

def scoped_keep(+hit: Bool, +w: Ev.Win, +rest: List<&2, Ev.Win>) -> List<&2, Ev.Win>:
  match hit:
    case True{}:
      w <> rest
    case False{}:
      rest

def scoped_wins(+ss: List<&2, T.Scoped>, +ms: List<&2, String>, +now: Nat) -> List<&2, Ev.Win>:
  match ss:
    case Nil{}:
      []
    case Con{T.Scoped{n, p, r}, t}:
      scoped_keep(PU.model.wanted(String.to_lower(n), ms), Ev.Win{n, U32.from_nat(p)}, scoped_wins(t, ms, now))

def opt_win(+name: String, +m: Maybe<&2, Nat>, +rest: List<&2, Ev.Win>) -> List<&2, Ev.Win>:
  match m:
    case Some{p}:
      Ev.Win{name, U32.from_nat(p)} <> rest
    case None{}:
      rest

def win_rows(+u: T.Usage, +ms: List<&2, String>, +now: Nat) -> List<&2, Ev.Win>:
  match u:
    case T.Usage{s, five, fr, seven, sr, ss, fa, bo, er, fl, np, pi, ad, hu, cu, se}:
      opt_win("5h", five, opt_win("7d", seven, scoped_wins(ss, ms, now)))

def head_u32(+m: Maybe<&2, Nat>) -> Maybe<&2, U32>:
  match m:
    case Some{n}:
      Some{U32.from_nat(n)}
    case None{}:
      None{}

def err_text(+row: Json.Json) -> Maybe<&2, String>:
  Rows.str_text(Json.get("lastError", row))

def sel_wl(+c: Bool, +x: List<&2, Ev.Win>, +y: List<&2, Ev.Win>) -> List<&2, Ev.Win>:
  match c:
    case True{}:
      x
    case False{}:
      y

def poll_row2(+slot: String, +trusted: Bool, +u: T.Usage, +err: Maybe<&2, String>, +ms: List<&2, String>, +now: Nat) -> Ev.Row:
  Ev.Row{slot, head_u32(PU.headroom(u, now, ms)), sel_wl(trusted, win_rows(u, ms, now), []), err}

# One poll row: windows only for a trusted reading; the error only when the
# usage is unknown.
def poll_row(+e: G.Ent, +u: T.Usage, +rows: Json.Json, +ms: List<&2, String>, +now: Nat) -> Ev.Row:
  match e:
    case G.Ent{+slot, email, org, creds, acct}:
      poll_row2(slot, PU.trusted(u, now, ms), u, err_text(row_of(rows, e)), ms, now)

def row_opt(+e: G.Ent, +u: Maybe<&2, T.Usage>, +rows: Json.Json, +ms: List<&2, String>, +now: Nat) -> Maybe<&2, Ev.Row>:
  match u:
    case Some{x}:
      Some{poll_row(e, x, rows, ms, now)}
    case None{}:
      None{}

def push_row(+m: Maybe<&2, Ev.Row>, +rest: List<&2, Ev.Row>) -> List<&2, Ev.Row>:
  match m:
    case Some{r}:
      r <> rest
    case None{}:
      rest

def ent_slot(+e: G.Ent) -> String:
  match e:
    case G.Ent{s, em, o, c, a}:
      s

def poll_rows(+es: List<&2, G.Ent>, +us: List<&2, T.Usage>, +rows: Json.Json, +ms: List<&2, String>, +now: Nat) -> List<&2, Ev.Row>:
  match es:
    case Nil{}:
      []
    case Con{e, t}:
      push_row(row_opt(e, usage_for(us, nat(SSeq.str_u32(ent_slot(e)))), rows, ms, now), poll_rows(t, us, rows, ms, now))

def slot_nat_of(+s: String) -> Nat:
  nat(SSeq.str_u32(s))

# {"number": N, "email": ...} for a slot of the roster.
def ref_json(+slot: String, +es: List<&2, G.Ent>) -> Json.Json:
  Ev.ref(slot, email_of(es, slot))

def opt_json(+m: Maybe<&2, String>) -> Json.Json:
  match m:
    case Some{x}:
      Json.JStr{x}
    case None{}:
      Json.JNull{}

def snap_accounts(+s: G.Snap) -> List<&2, T.Account>:
  accounts_of(G.snap_ents(s))

def snap_state(+s: G.Snap) -> T.State:
  state_of(G.snap_state(s))
