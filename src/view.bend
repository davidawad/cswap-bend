import Base
import ./pollrow.bend as Pollrow
import ./usage/norm.bend as UNorm
import ./json.bend as Json
import ./clock.bend as Clock
import ./poll.bend as Poll

# The --json projections of a usage reading (json_output.py, pace.py): the
# camelCase windows with their reset strings recomputed at print time and the
# weekly pace fields, and the account rows list and status print.

def week() -> U32:
  604800

def day() -> U32:
  86400

def jv(+k: String, +j: Json.Json) -> Json.Json:
  Maybe.default(&2, Json.Json, Json.get(k, j), Json.JNull{})

def has(+k: String, +j: Json.Json) -> Bool:
  Maybe.is_some(&2, Json.Json, Json.get(k, j))

def put(k: String, v: Json.Json, j: Json.Json) -> Json.Json:
  Json.set(k, v, j)

def put_if(on: Bool, k: String, v: Json.Json, j: Json.Json) -> Json.Json:
  match on:
    case True{}:
      Json.set(k, v, j)
    case False{}:
      j

def put_m(k: String, m: Maybe<&2, Json.Json>, j: Json.Json) -> Json.Json:
  match m:
    case Some{v}:
      Json.set(k, v, j)
    case None{}:
      j

def jstr(s: String) -> Json.Json:
  Json.JStr{s}

def jbool(b: Bool) -> Json.Json:
  Json.JBool{b}

type Cell is Data:
  Cell{countdown: String, clock: String}

# The reset string pair stored with the window when its stamp cannot be read.
def cell.of_clock(m: Maybe<&2, String>, +cd: String) -> Maybe<&2, Cell>:
  match m:
    case Some{c}:
      Some{Cell{cd, c}}
    case None{}:
      None{}

def cell.stored(+w: Json.Json) -> Maybe<&2, Cell>:
  cell.of_clock(Json.as_string(jv("clock", w)), Maybe.default(&2, String, Json.as_string(jv("countdown", w)), "?"))

def cell.at(t: Maybe<&2, U32>, +w: Json.Json, +now: U32, +off: U32) -> Maybe<&2, Cell>:
  match t:
    case Some{+u}:
      Some{Cell{UNorm.countdown(UNorm.remaining(u, now)), UNorm.clock.text(u, now, off)}}
    case None{}:
      cell.stored(w)

def cell.reset(m: Maybe<&2, String>, +w: Json.Json, +now: U32, +off: U32) -> Maybe<&2, Cell>:
  match m:
    case Some{s}:
      cell.at(Clock.parse_iso8601(s), w, now, off)
    case None{}:
      cell.stored(w)

# oauth.fresh_reset_strings: countdown and clock recomputed from resets_at.
def fresh(+w: Json.Json, +now: U32, +off: U32) -> Maybe<&2, Cell>:
  cell.reset(UNorm.resets_of(w), w, now, off)

def with_cell(j: Json.Json, m: Maybe<&2, Cell>) -> Json.Json:
  match m:
    case Some{Cell{cd, ck}}:
      Json.set("clock", jstr(ck), Json.set("countdown", jstr(cd), j))
    case None{}:
      j

# expected: tenths of the week elapsed; eta: when usage would reach 100%.
type Pace is Data:
  Pace{expected: U32, ahead: Bool, eta: Maybe<&2, U32>, last: Maybe<&2, Bool>}

def elapsed.fin(+rem: U32) -> U32:
  Clock.sel(U32.is_eq(rem, 0), 0, (604800 - rem : U32))

def elapsed_of(+reset: U32, +fetched: U32) -> U32:
  elapsed.fin((((reset % 604800) + 604800 - (fetched % 604800)) % 604800 : U32))

def eta.pick(none: Bool, +p: U32, +elapsed: U32, +fetched: U32) -> Maybe<&2, U32>:
  match none:
    case True{}:
      None{}
    case False{}:
      Some{Clock.sel(U32.is_ge(p, 1000), fetched, (fetched + (1000 - Poll.min_u(p, 1000)) * elapsed / p : U32))}

def eta.of(+p: U32, +elapsed: U32, +fetched: U32) -> Maybe<&2, U32>:
  eta.pick(U32.is_eq(elapsed, 0) || U32.is_eq(p, 0), p, elapsed, fetched)

def last.el(none: Bool, +elapsed: U32, +p: U32) -> Maybe<&2, Bool>:
  match none:
    case True{}:
      None{}
    case False{}:
      Some{U32.is_le((p * 604800 : U32), (1000 * elapsed : U32))}

def last.pick(zero: Bool, +p: U32, +elapsed: U32) -> Maybe<&2, Bool>:
  match zero:
    case True{}:
      Some{True{}}
    case False{}:
      last.el(U32.is_eq(elapsed, 0), elapsed, p)

def last.of(+p: U32, +elapsed: U32) -> Maybe<&2, Bool>:
  last.pick(U32.is_eq(p, 0), p, elapsed)

def pace.pick(early: Bool, +p: U32, +elapsed: U32, +fetched: U32) -> Maybe<&2, Pace>:
  match early:
    case True{}:
      None{}
    case False{}:
      Some{Pace{Poll.min_u(1000, ((elapsed * 1000 * 2 + 604800) / 1209600 : U32)),
        U32.is_ge((p * 604800 : U32), ((elapsed * 1000 + 150 * 604800) : U32)), eta.of(p, elapsed, fetched), last.of(p, elapsed)}}

def pace.mk(+p: U32, +elapsed: U32, +fetched: U32) -> Maybe<&2, Pace>:
  pace.pick(U32.is_lt(elapsed, 86400), p, elapsed, fetched)

def pace.reset(p: Maybe<&2, U32>, r: Maybe<&2, U32>, +fetched: U32) -> Maybe<&2, Pace>:
  match p r:
    case Some{x} Some{t}:
      pace.mk(x, elapsed_of(t, fetched), fetched)
    case _ _:
      None{}

# compute_pace for one weekly window; None when it cannot be told or is
# inside the first day after a reset.
def pace_of(+w: Json.Json, fetched: Maybe<&2, U32>) -> Maybe<&2, Pace>:
  match fetched:
    case None{}:
      None{}
    case Some{f}:
      pace.reset(Poll.tenths.json(jv("pct", w)), Poll.win.reset(w), f)

def tenths_text(+n: U32) -> String:
  U32.show((n / 10 : U32)) ++ "." ++ U32.show((n % 10 : U32))

def eta.json(t: U32) -> Json.Json:
  jstr(Clock.iso8601_utc(t))

def last.json(m: Maybe<&2, Bool>) -> Maybe<&2, Json.Json>:
  match m:
    case Some{b}:
      Some{jbool(b)}
    case None{}:
      None{}

def eta.m(m: Maybe<&2, U32>) -> Maybe<&2, Json.Json>:
  match m:
    case Some{t}:
      Some{eta.json(t)}
    case None{}:
      None{}

def with_pace(j: Json.Json, m: Maybe<&2, Pace>) -> Json.Json:
  match m:
    case None{}:
      j
    case Some{Pace{e, a, eta, last}}:
      put_m("willLastToReset", last.json(last),
        put_m("projectedExhaustionAt", eta.m(eta),
          put("aheadOfPace", jbool(a), put("expectedPct", Json.JNum{tenths_text(e)}, j))))

def reset_set(m: Maybe<&2, Json.Json>, j: Json.Json) -> Json.Json:
  match m:
    case Some{v}:
      Json.set("resetsAt", v, j)
    case None{}:
      j

def reset_field(+w: Json.Json, j: Json.Json) -> Json.Json:
  reset_set(Json.get("resets_at", w), j)

# A 5h window: pct, resetsAt and the fresh countdown and clock.
def window_json(+w: Json.Json, +now: U32, +off: U32) -> Json.Json:
  with_cell(reset_field(w, Json.of_pairs([("pct", jv("pct", w))])), fresh(w, now, off))

def weekly_json(+w: Json.Json, +fetched: Maybe<&2, U32>, +now: U32, +off: U32) -> Json.Json:
  with_pace(window_json(w, now, off), pace_of(w, fetched))

def scoped_json(+w: Json.Json, +fetched: Maybe<&2, U32>, +now: U32, +off: U32) -> Json.Json:
  Json.set("name", jv("name", w), weekly_json(w, fetched, now, off))

def scoped_list(ls: List<&2, Json.Json>, +fetched: Maybe<&2, U32>, +now: U32, +off: U32) -> List<&2, Json.Json>:
  match ls:
    case Nil{}:
      []
    case Con{h, t}:
      scoped_json(h, fetched, now, off) <> scoped_list(t, fetched, now, off)

def spend_json(+s: Json.Json, +now: U32, +off: U32) -> Json.Json:
  with_cell(reset_field(s, Json.of_pairs([("used", jv("used", s)), ("limit", jv("limit", s)), ("pct", jv("pct", s)), ("currency", jv("currency", s))])), fresh(s, now, off))

def five_json(+usage: Json.Json, +now: U32, +off: U32) -> Maybe<&2, Json.Json>:
  Maybe.bind(&2, Json.Json, Json.Json, Json.get("five_hour", usage), w => Some{window_json(w, now, off)})

def seven_json(+usage: Json.Json, +fetched: Maybe<&2, U32>, +now: U32, +off: U32) -> Maybe<&2, Json.Json>:
  Maybe.bind(&2, Json.Json, Json.Json, Json.get("seven_day", usage), w => Some{weekly_json(w, fetched, now, off)})

def spend_m(+usage: Json.Json, +now: U32, +off: U32) -> Maybe<&2, Json.Json>:
  Maybe.bind(&2, Json.Json, Json.Json, Json.get("spend", usage), w => Some{spend_json(w, now, off)})

def scoped_m(+usage: Json.Json, +fetched: Maybe<&2, U32>, +now: U32, +off: U32) -> Maybe<&2, Json.Json>:
  Maybe.bind(&2, Json.Json, Json.Json, Json.get("scoped", usage), l => Some{Json.arr(scoped_list(Json.to_list(l), fetched, now, off))})

# usage_to_json: sevenDay and scoped carry pace fields when `fetched` is known.
def usage_to_json(+usage: Json.Json, +fetched: Maybe<&2, U32>, +now: U32, +off: U32) -> Json.Json:
  put_m("scoped", scoped_m(usage, fetched, now, off),
    put_m("spend", spend_m(usage, now, off),
      put_m("sevenDay", seven_json(usage, fetched, now, off),
        put_m("fiveHour", five_json(usage, now, off), Json.of_pairs([])))))

# One managed account as list and status see it. `sentinel` is the usageStatus
# an overlay forces (api_key, no_credentials, token_expired, relogin_required,
# ...), already derived by the caller.
type Acct is Data:
  Acct{num: U32, email: String, org_name: String, org_uuid: String, active: Bool, alias: String, disabled: Bool,
       login_expires: Maybe<&2, String>, sentinel: Maybe<&2, String>, row: Pollrow.Row}

def is_obj(j: Json.Json) -> Bool:
  match j:
    case Json.JObj{f}:
      True{}
    case _:
      False{}

def age_text(+n: U32) -> String:
  U32.show(n) ++ ".0"

def ts(+t: U32) -> String:
  Clock.iso8601_utc(t)

def freshness(fetched: Maybe<&2, U32>, +now: U32, j: Json.Json) -> Json.Json:
  match fetched:
    case None{}:
      j
    case Some{+f}:
      Json.set("usageAgeSeconds", Json.JNum{age_text(Poll.sub0(now, f))}, Json.set("usageFetchedAt", jstr(ts(f)), j))

def lg.fields(ok: Bool, +lg: Json.Json, +f: U32, +now: U32, +off: U32, j: Json.Json) -> Json.Json:
  match ok:
    case False{}:
      j
    case True{}:
      Json.set("lastGoodAgeSeconds", Json.JNum{age_text(Poll.sub0(now, f))},
        Json.set("lastGoodFetchedAt", jstr(ts(f)),
          Json.set("lastGoodUsage", usage_to_json(lg, Some{f}, now, off), j)))

def last_good_fields(+lg: Json.Json, fetched: Maybe<&2, U32>, +now: U32, +off: U32, j: Json.Json) -> Json.Json:
  match fetched:
    case None{}:
      j
    case Some{+f}:
      lg.fields(is_obj(lg), lg, f, now, off, j)

def retry_at(live: Bool, b: Maybe<&2, U32>, j: Json.Json) -> Json.Json:
  match live b:
    case True{} Some{t}:
      Json.set("usageRetryAt", jstr(ts(t)), j)
    case _ _:
      j

def failure_fields(unavailable: Bool, last_error: Maybe<&2, String>, +backoff: Maybe<&2, U32>, +now: U32, j: Json.Json) -> Json.Json:
  match unavailable last_error:
    case True{} Some{e}:
      retry_at(Pollrow.before.m(backoff, now), backoff, Json.set("usageError", jstr(e), j))
    case _ _:
      j

def status_of(sentinel: Maybe<&2, String>, +usage: Json.Json) -> String:
  match sentinel:
    case Some{s}:
      s
    case None{}:
      Clock.sel.s(is_obj(usage), "ok", "unavailable")

def base_row(+a: Acct, status: String, usage: Json.Json) -> Json.Json:
  match a:
    case Acct{num, email, org_name, org_uuid, active, alias, disabled, login, sentinel, row}:
      Json.of_pairs([("number", Json.JNum{U32.show(num)}), ("email", jstr(email)), ("organizationName", jstr(org_name)),
        ("organizationUuid", jstr(org_uuid)), ("isOrganization", jbool(Bool.not(String.is_empty(org_uuid)))), ("active", jbool(active)),
        ("usageStatus", jstr(status)), ("usage", usage)])

def extras(+a: Acct, j: Json.Json) -> Json.Json:
  match a:
    case Acct{num, email, org_name, org_uuid, active, alias, disabled, login, sentinel, row}:
      put_m("loginExpiresAt", Maybe.bind(&2, String, Json.Json, login, s => Some{jstr(s)}),
        put_if(disabled, "disabled", jbool(True{}), put_if(Bool.not(String.is_empty(alias)), "alias", jstr(alias), j)))

def tail.pick(has_usage: Bool, +fetched: Maybe<&2, U32>, +lg: Json.Json, le: Maybe<&2, String>, bu: Maybe<&2, U32>, unavailable: Bool, +now: U32, +off: U32, j: Json.Json) -> Json.Json:
  match has_usage:
    case True{}:
      freshness(fetched, now, j)
    case False{}:
      failure_fields(unavailable, le, bu, now, last_good_fields(lg, fetched, now, off, j))

def tail_fields(row: Pollrow.Row, status: String, usage: Json.Json, +now: U32, +off: U32, j: Json.Json) -> Json.Json:
  match row:
    case Pollrow.Row{fetched, lg, la, fl, le, bu, np, iv, l429, st, sfp, cu, hu}:
      tail.pick(is_obj(usage), fetched, lg, le, bu, String.eq(status, "unavailable"), now, off, j)

def row_json(+a: Acct, +usage: Json.Json, +status: String, +now: U32, +off: U32) -> Json.Json:
  match a:
    case Acct{num, email, org_name, org_uuid, active, alias, disabled, login, sentinel, row}:
      tail_fields(row, status, usage, now, off, extras(a, base_row(a, status, usage)))

def project.pick(ok: Bool, +d: Json.Json, fetched: Maybe<&2, U32>, +now: U32, +off: U32) -> Json.Json:
  match ok:
    case True{}:
      usage_to_json(d, fetched, now, off)
    case False{}:
      Json.JNull{}

def project.of(+d: Json.Json, fetched: Maybe<&2, U32>, +now: U32, +off: U32) -> Json.Json:
  project.pick(is_obj(d), d, fetched, now, off)

def project(+row: Pollrow.Row, models: List<&2, String>, +now: U32, +off: U32) -> Json.Json:
  match row:
    case Pollrow.Row{fetched, lg, la, fl, le, bu, np, iv, l429, st, sfp, cu, hu}:
      project.of(Pollrow.decision_usage(row, models, now), fetched, now, off)

def usage_for(sentinel: Maybe<&2, String>, row: Pollrow.Row, models: List<&2, String>, +now: U32, +off: U32) -> Json.Json:
  match sentinel:
    case Some{s}:
      Json.JNull{}
    case None{}:
      project(row, models, now, off)

def usage_part(+a: Acct, models: List<&2, String>, +now: U32, +off: U32) -> Json.Json:
  match a:
    case Acct{num, email, org_name, org_uuid, active, alias, disabled, login, sentinel, row}:
      usage_for(sentinel, row, models, now, off)

def sentinel_of(+a: Acct) -> Maybe<&2, String>:
  match a:
    case Acct{num, email, org_name, org_uuid, active, alias, disabled, login, sentinel, row}:
      sentinel

def account_row2(+a: Acct, +usage: Json.Json, +now: U32, +off: U32) -> Json.Json:
  row_json(a, usage, status_of(sentinel_of(a), usage), now, off)

# The `list --json` row of one account (account_row).
def account_row(+a: Acct, models: List<&2, String>, +now: U32, +off: U32) -> Json.Json:
  account_row2(a, usage_part(a, models, now, off), now, off)
