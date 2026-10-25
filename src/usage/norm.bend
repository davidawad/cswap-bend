import Base
import ../json.bend as Json
import ../clock.bend as Clock
import ./text.bend as UText

# ---- reset text and the normalised result ----------------------------------

def months() -> String:
  "JanFebMarAprMayJunJulAugSepOctNovDec"

def hhmm(+local: U32) -> String:
  Clock.pad2(((local % 86400) / 3600 : U32)) ++ ":" ++ Clock.pad2(((local % 3600) / 60 : U32))

def clock.date2(md: U32 & U32, +local: U32) -> String:
  (m, d) = md
  String.take(String.drop(months(), U32.to_nat((m * 3 - 3 : U32))), 3n) ++ " " ++ U32.show(d) ++ " " ++ hhmm(local)

def clock.date(ymd: U32 & (U32 & U32), +local: U32) -> String:
  (y, md) = ymd
  clock.date2(md, local)

# "20:39" on the same local day as now, else "Jul 5 08:59". `off` is the local
# UTC offset biased by 86400 (Clock.tz).
def clock.text(+reset: U32, +now: U32, +off: U32) -> String:
  Clock.sel.s(U32.is_eq(((reset + off - 86400) / 86400 : U32), ((now + off - 86400) / 86400 : U32)),
    hhmm((reset + off - 86400 : U32)),
    clock.date(Clock.civil(((reset + off - 86400) / 86400 : U32)), (reset + off - 86400 : U32)))

def countdown(+rem: U32) -> String:
  Clock.sel.s(U32.is_gt((rem / 86400 : U32), 0), U32.show((rem / 86400 : U32)) ++ "d " ++ U32.show(((rem % 86400) / 3600 : U32)) ++ "h",
    Clock.sel.s(U32.is_gt((rem / 3600 : U32), 0), U32.show((rem / 3600 : U32)) ++ "h " ++ U32.show(((rem % 3600) / 60 : U32)) ++ "m",
      U32.show((rem / 60 : U32)) ++ "m"))

def remaining(+reset: U32, +now: U32) -> U32:
  Clock.sel(U32.is_gt(reset, now), (reset - now : U32), 0)

def nonempty(m: Maybe<&2, String>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{+s}:
      UText.maybe.none_if(String.is_empty(s), s)

def resets_of(w: Json.Json) -> Maybe<&2, String>:
  nonempty(Json.as_string(Maybe.default(&2, Json.Json, Json.get("resets_at", w), Json.JNull{})))

# resets_at, then countdown and clock when the stamp parses.
def with_reset.at(j: Json.Json, s: String, t: Maybe<&2, U32>, +now: U32, +off: U32) -> Json.Json:
  match t:
    case None{}:
      Json.set("resets_at", Json.JStr{s}, j)
    case Some{+u}:
      Json.set("clock", Json.JStr{clock.text(u, now, off)},
        Json.set("countdown", Json.JStr{countdown(remaining(u, now))},
          Json.set("resets_at", Json.JStr{s}, j)))

def with_reset(j: Json.Json, r: Maybe<&2, String>, +now: U32, +off: U32) -> Json.Json:
  match r:
    case None{}:
      j
    case Some{+s}:
      with_reset.at(j, s, Clock.parse_iso8601(s), now, off)

def put(k: String, m: Maybe<&2, Json.Json>, j: Json.Json) -> Json.Json:
  match m:
    case None{}:
      j
    case Some{v}:
      Json.set(k, v, j)

# five_hour / seven_day: {pct, resets_at, countdown, clock}. A window with no
# utilization is left out.
def window.pct(u: Maybe<&2, Json.Json>, r: Maybe<&2, String>, +now: U32, +off: U32) -> Maybe<&2, Json.Json>:
  match u:
    case None{}:
      None{}
    case Some{p}:
      Some{with_reset(Json.of_pairs([("pct", p)]), r, now, off)}

def window.of(+w: Json.Json, +now: U32, +off: U32) -> Maybe<&2, Json.Json>:
  window.pct(Json.get("utilization", w), resets_of(w), now, off)

def window.in(m: Maybe<&2, Json.Json>, +now: U32, +off: U32) -> Maybe<&2, Json.Json>:
  match m:
    case None{}:
      None{}
    case Some{w}:
      window.of(w, now, off)

def window(+key: String, +data: Json.Json, +now: U32, +off: U32) -> Maybe<&2, Json.Json>:
  window.in(Json.get(key, data), now, off)

def num.text(j: Json.Json) -> Maybe<&2, String>:
  match j:
    case Json.JNum{t}:
      Some{t}
    case _:
      None{}

def nonnull(m: Maybe<&2, Json.Json>) -> Maybe<&2, Json.Json>:
  match m:
    case None{}:
      None{}
    case Some{Json.JNull{}}:
      None{}
    case Some{j}:
      Some{j}

def num.field(+k: String, +j: Json.Json) -> Maybe<&2, String>:
  do Maybe<&2, String>:
    v : Json.Json <- nonnull(Json.get(k, j))
    num.text(v)

# float(field) as Python prints it.
def float.field(+k: String, +j: Json.Json) -> Maybe<&2, String>:
  do Maybe<&2, String>:
    t : String <- num.field(k, j)
    UText.float(t)

def spend.mk(used: String, limit: String, pct: String, cur: Json.Json, eu: Json.Json, +now: U32, +off: U32) -> Json.Json:
  with_reset(Json.of_pairs([("used", Json.JNum{used}), ("limit", Json.JNum{limit}), ("pct", Json.JNum{pct}), ("currency", cur)]),
    resets_of(eu), now, off)

def spend.fields(+eu: Json.Json, +now: U32, +off: U32) -> Maybe<&2, Json.Json>:
  do Maybe<&2, Json.Json>:
    u : String <- num.field("used_credits", eu)
    used : String <- UText.div100(u)
    l : String <- num.field("monthly_limit", eu)
    limit : String <- UText.div100(l)
    p : String <- num.field("utilization", eu)
    pct : String <- UText.float(p)
    return spend.mk(used, limit, pct, Maybe.default(&2, Json.Json, Json.get("currency", eu), Json.JStr{"USD"}), eu, now, off)

def spend.on(enabled: Maybe<&2, Bool>, res: Json.Json, +eu: Json.Json, +now: U32, +off: U32) -> Json.Json:
  match enabled:
    case Some{True{}}:
      put("spend", spend.fields(eu, now, off), res)
    case _:
      res

def spend.add(res: Json.Json, m: Maybe<&2, Json.Json>, +now: U32, +off: U32) -> Json.Json:
  match m:
    case None{}:
      res
    case Some{+eu}:
      spend.on(Json.as_bool(Maybe.default(&2, Json.Json, Json.get("is_enabled", eu), Json.JNull{})), res, eu, now, off)

# One `limits[]` entry with scope.model.display_name and a numeric percent.
def scoped.entry(name: String, pct: String, +lim: Json.Json, +now: U32, +off: U32) -> Json.Json:
  with_reset(Json.of_pairs([("name", Json.JStr{name}), ("pct", Json.JNum{pct})]), resets_of(lim), now, off)

def scoped.name(+lim: Json.Json) -> Maybe<&2, String>:
  do Maybe<&2, String>:
    scope : Json.Json <- Json.get("scope", lim)
    model : Json.Json <- Json.get("model", scope)
    n : Json.Json <- Json.get("display_name", model)
    s : String <- Json.as_string(n)
    nonempty(Some{s})

def scoped.of(name: Maybe<&2, String>, pct: Maybe<&2, String>, +lim: Json.Json, +now: U32, +off: U32) -> Maybe<&2, Json.Json>:
  match name pct:
    case Some{n} Some{p}:
      Some{scoped.entry(n, p, lim, now, off)}
    case _ _:
      None{}

def scoped.one(+lim: Json.Json, +now: U32, +off: U32) -> Maybe<&2, Json.Json>:
  scoped.of(scoped.name(lim), float.field("percent", lim), lim, now, off)

def scoped.cons(m: Maybe<&2, Json.Json>, rest: List<&2, Json.Json>) -> List<&2, Json.Json>:
  match m:
    case None{}:
      rest
    case Some{x}:
      x <> rest

def scoped.go(ls: List<&2, Json.Json>, +now: U32, +off: U32) -> List<&2, Json.Json>:
  match ls:
    case Nil{}:
      []
    case Con{h, t}:
      scoped.cons(scoped.one(h, now, off), scoped.go(t, now, off))

def scoped.put(xs: List<&2, Json.Json>, res: Json.Json) -> Json.Json:
  match xs:
    case Nil{}:
      res
    case Con{h, t}:
      Json.set("scoped", Json.arr(h <> t), res)

def result.fin(ks: List<&2, String>, res: Json.Json) -> Json.Json:
  match ks:
    case Nil{}:
      Json.JNull{}
    case Con{h, t}:
      res

def result.keep(+r: Json.Json) -> Json.Json:
  result.fin(Json.keys(r), r)

# The normalised usage (five_hour, seven_day, spend, scoped), or JNull when
# the data carries nothing: build_usage_result. `now` is unix seconds, `off`
# the local UTC offset biased by 86400.
def build_usage_result(+data: Json.Json, +now: U32, +off: U32) -> Json.Json:
  result.keep(scoped.put(
    scoped.go(Json.to_list(Maybe.default(&2, Json.Json, Json.get("limits", data), Json.JNull{})), now, off),
    spend.add(
      put("seven_day", window("seven_day", data, now, off), put("five_hour", window("five_hour", data, now, off), Json.of_pairs([]))),
      Json.get("extra_usage", data), now, off)))
