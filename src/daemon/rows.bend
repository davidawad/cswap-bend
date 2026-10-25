import Base
import ../json.bend as Json
import ../clock.bend as Clock
import ../policy/types.bend as T
import ./config.bend as Cfg

# cache/usage.json rows (contract 1.5) into the policy's `Usage`. Percentages
# become centi-percent Nat; epochs and ISO reset stamps become unix seconds.

def nat_opt(+m: Maybe<&2, U32>) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{n}:
      Some{U32.to_nat(n)}

# "1792740000.1" -> 1792740000, "7" -> 7; None for anything else.
def epoch_text(+t: String) -> Maybe<&2, U32>:
  Cfg.read_u32(Maybe.default(&2, String, List.head(&2, String, String.split(t, '.')), ""))

def num_text(+m: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match m:
    case Some{Json.JNum{t}}:
      Some{t}
    case _:
      None{}

def str_text(+m: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match m:
    case Some{Json.JStr{s}}:
      Some{s}
    case _:
      None{}

def bind_s(+m: Maybe<&2, String>, f: String -> Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      f(s)

def epoch_of(+j: Json.Json, +key: String) -> Maybe<&2, Nat>:
  nat_opt(bind_s(num_text(Json.get(key, j)), t => epoch_text(t)))

def pct_of(+j: Json.Json) -> Maybe<&2, Nat>:
  nat_opt(bind_s(num_text(Json.get("pct", j)), t => Cfg.centi(t)))

def iso_of(+j: Json.Json) -> Maybe<&2, Nat>:
  nat_opt(bind_s(str_text(Json.get("resets_at", j)), t => Clock.parse_iso8601(t)))

def or_null(+m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case Some{w}:
      w
    case None{}:
      Json.JNull{}

def win(+j: Json.Json, +key: String) -> Json.Json:
  or_null(Json.get(key, j))

# ---- scoped windows -----------------------------------------------------------------------

def scoped2(+name: Maybe<&2, String>, +pct: Maybe<&2, Nat>, +reset: Maybe<&2, Nat>) -> Maybe<&2, T.Scoped>:
  match name pct:
    case Some{n} Some{p}:
      Some{T.Scoped{n, p, reset}}
    case _ _:
      None{}

def scoped_one(+s: Json.Json) -> Maybe<&2, T.Scoped>:
  scoped2(str_text(Json.get("name", s)), pct_of(s), iso_of(s))

def scoped_push(+m: Maybe<&2, T.Scoped>, +rest: List<&2, T.Scoped>) -> List<&2, T.Scoped>:
  match m:
    case Some{s}:
      s <> rest
    case None{}:
      rest

def scoped_chain(+items: Json.Json) -> List<&2, T.Scoped>:
  match items:
    case Json.JCons{h, t}:
      scoped_push(scoped_one(h), scoped_chain(t))
    case _:
      []

def unwrap_arr(+j: Json.Json) -> Json.Json:
  match j:
    case Json.JArr{items}:
      items
    case _:
      Json.JNil{}

def scoped_of(+good: Json.Json) -> List<&2, T.Scoped>:
  scoped_chain(unwrap_arr(win(good, "scoped")))

# ---- error and plan fields ---------------------------------------------------------------------

def err2(+is429: Bool) -> T.ErrKind:
  match is429:
    case True{}:
      T.ErrHttp429{}
    case False{}:
      T.ErrOther{}

def err_kind(+m: Maybe<&2, String>) -> T.ErrKind:
  match m:
    case None{}:
      T.ErrNone{}
    case Some{e}:
      err2(String.eq(e, "http-429"))

def zero_or(+m: Maybe<&2, Nat>) -> Nat:
  match m:
    case None{}:
      0n
    case Some{n}:
      n

def u32_field(+j: Json.Json, +key: String) -> Nat:
  zero_or(nat_opt(bind_s(num_text(Json.get(key, j)), t => Cfg.read_u32(Maybe.default(&2, String, List.head(&2, String, String.split(t, '.')), "")))))

def usage2(+slot: Nat, +row: Json.Json, +good: Json.Json, +sentinel: T.Sentinel) -> T.Usage:
  T.Usage{slot, pct_of(win(good, "five_hour")), iso_of(win(good, "five_hour")), pct_of(win(good, "seven_day")), iso_of(win(good, "seven_day")),
    scoped_of(good), epoch_of(row, "fetchedAt"), u32_field(row, "backoffUntil"), err_kind(str_text(Json.get("lastError", row))), u32_field(row, "consecutiveFailures"),
    epoch_of(row, "nextPollAt"), u32_field(row, "pollIntervalS"), u32_field(row, "authDeadStrikes"), u32_field(row, "heldUntil"), u32_field(row, "claimUntil"), sentinel}

# A row, as the policy reads it. `row` is JNull when the slot has none (or it
# belongs to another identity): never fetched. `sentinel` is the overlay the
# caller computed from the credential.
def usage_of(+slot: Nat, +row: Json.Json, +sentinel: T.Sentinel) -> T.Usage:
  usage2(slot, row, win(row, "lastGood"), sentinel)

def empty_usage(+slot: Nat, +sentinel: T.Sentinel) -> T.Usage:
  usage_of(slot, Json.JNull{}, sentinel)
