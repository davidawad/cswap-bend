import Base
import ../json.bend as Json

# The JSONL events of `cswap auto --json` (contract 4.5, autoswitch.py
# *Event classes). Percentages are centi-percent U32 (85.5 % = 8550); they
# print the way Python prints the float: `60.0`, `42.5`, `87.66`.

type Win is Data:
  Win{name: String, pct: U32}

# One account in a poll: headroom (None = unknown), the relevant windows, and
# the fetch error to show when its usage is unknown.
type Row is Data:
  Row{slot: String, headroom: Maybe<&2, U32>, windows: List<&2, Win>, error: Maybe<&2, String>}

def sel(+c: Bool, +x: String, +y: String) -> String:
  match c:
    case True{}:
      x
    case False{}:
      y

def two(+n: U32) -> String:
  sel(U32.is_lt(n, 10), "0" ++ U32.show(n), U32.show(n))

# Digits after the point with a trailing zero dropped, at least one digit.
def frac(+cents: U32) -> String:
  sel(U32.is_eq((cents % 10 : U32), 0), U32.show((cents / 10 : U32)), two(cents))

# 6000 -> "60.0", 4250 -> "42.5", 8766 -> "87.66".
def float_text(+c: U32) -> String:
  U32.show((c / 100 : U32)) ++ "." ++ frac((c % 100 : U32))

def fl(+c: U32) -> Json.Json:
  Json.JNum{float_text(c)}

# `%.10g`: 4000 -> "40", 8766 -> "87.66".
def pct_label(+c: U32) -> String:
  sel(U32.is_eq((c % 100 : U32), 0), U32.show((c / 100 : U32)), float_text(c))

def pair(+k: String, +v: Json.Json, +rest: Json.Json) -> Json.Json:
  Json.JField{k, v, rest}

def str(+s: String) -> Json.Json:
  Json.JStr{s}

# {"schemaVersion": 1, "event": KIND, "ts": TS, ...fields}
def event(+kind: String, +ts: String, +fields: Json.Json) -> Json.Json:
  Json.JObj{pair("schemaVersion", Json.JNum{"1"}, pair("event", str(kind), pair("ts", str(ts), fields)))}

# {"number": int, "email": str}
def ref(+slot: String, +email: String) -> Json.Json:
  Json.JObj{pair("number", Json.JNum{slot}, pair("email", str(email), Json.JNil{}))}

def ref_opt(+m: Maybe<&2, String>, +email: String) -> Json.Json:
  match m:
    case None{}:
      Json.JNull{}
    case Some{s}:
      ref(s, email)

# ---- poll ---------------------------------------------------------------------------------

def hr_json(+m: Maybe<&2, U32>) -> Json.Json:
  match m:
    case None{}:
      Json.JNull{}
    case Some{c}:
      fl(c)

def headroom_chain(+rows: List<&2, Row>) -> Json.Json:
  match rows:
    case Nil{}:
      Json.JNil{}
    case Con{Row{s, h, w, e}, t}:
      pair(s, hr_json(h), headroom_chain(t))

def windows_chain(+ws: List<&2, Win>) -> Json.Json:
  match ws:
    case Nil{}:
      Json.JNil{}
    case Con{Win{n, p}, t}:
      pair(n, fl(p), windows_chain(t))

def windows_pick(+empty: Bool, +s: String, +w: List<&2, Win>, +rest: Json.Json) -> Json.Json:
  match empty:
    case True{}:
      rest
    case False{}:
      pair(s, Json.JObj{windows_chain(w)}, rest)

# {slot: {"5h": 20.0, ...}} for the accounts that have windows.
def windows_all(+rows: List<&2, Row>) -> Json.Json:
  match rows:
    case Nil{}:
      Json.JNil{}
    case Con{Row{s, h, w, e}, t}:
      windows_pick(List.is_empty(&2, Win, w), s, w, windows_all(t))

# Only an unknown-usage account with an error is listed.
def errors_pick(+h: Maybe<&2, U32>, +e: Maybe<&2, String>, +s: String, +rest: Json.Json) -> Json.Json:
  match h e:
    case None{} Some{m}:
      pair(s, str(m), rest)
    case _ _:
      rest

def errors_all(+rows: List<&2, Row>) -> Json.Json:
  match rows:
    case Nil{}:
      Json.JNil{}
    case Con{Row{s, h, w, e}, t}:
      errors_pick(h, e, s, errors_all(t))

def opt_obj(+c: Json.Json, +key: String, +rest: Json.Json) -> Json.Json:
  match c:
    case Json.JNil{}:
      rest
    case _:
      pair(key, Json.JObj{c}, rest)

# fetchErrors and windowsPct appear only when non-empty.
def poll(+ts: String, +active: Json.Json, +rows: List<&2, Row>, +threshold: U32) -> Json.Json:
  event("poll", ts, pair("active", active, pair("headroomPct", Json.JObj{headroom_chain(rows)}, pair("threshold", fl(threshold),
    opt_obj(errors_all(rows), "fetchErrors", opt_obj(windows_all(rows), "windowsPct", Json.JNil{}))))))

# ---- the rest ----------------------------------------------------------------------------

def strs(+xs: List<&2, String>) -> List<&2, Json.Json>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      str(h) <> strs(t)

def switch(+ts: String, +trigger: String, +from: Json.Json, +to: Json.Json, +warnings: List<&2, String>, +dry_run: Bool) -> Json.Json:
  event("switch", ts, pair("trigger", str(trigger), pair("from", from, pair("to", to,
    pair("warnings", Json.arr(strs(warnings)), pair("dryRun", Json.JBool{dry_run}, Json.JNil{}))))))

def no_switch(+ts: String, +reason: String, +detail: String) -> Json.Json:
  event("no-switch", ts, pair("reason", str(reason), pair("detail", str(detail), Json.JNil{})))

def quarantined(+ts: String, +slot: String, +email: String, +reason: String) -> Json.Json:
  event("account-quarantined", ts, pair("number", str(slot), pair("email", str(email), pair("reason", str(reason), Json.JNil{}))))

def unquarantined(+ts: String, +slot: String, +email: String, +reason: String) -> Json.Json:
  event("account-unquarantined", ts, pair("number", str(slot), pair("email", str(email), pair("reason", str(reason), Json.JNil{}))))

def opt_str(+m: Maybe<&2, String>) -> Json.Json:
  match m:
    case None{}:
      Json.JNull{}
    case Some{x}:
      str(x)

def is_none(+m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{x}:
      False{}

# `earliest` is an ISO Z stamp, or none when no reset is known.
def all_exhausted(+ts: String, +earliest: Maybe<&2, String>) -> Json.Json:
  event("all-exhausted", ts, pair("earliestResetAt", opt_str(earliest), Json.JNil{}))

# `seconds` is deciseconds (round(seconds, 1)).
def sleep(+ts: String, +deci: U32, +until: String) -> Json.Json:
  event("sleep", ts, pair("seconds", Json.JNum{U32.show((deci / 10 : U32)) ++ "." ++ U32.show((deci % 10 : U32))}, pair("until", str(until), Json.JNil{})))

def error(+ts: String, +message: String, +transient: Bool) -> Json.Json:
  event("error", ts, pair("message", str(message), pair("transient", Json.JBool{transient}, Json.JNil{})))

def config_warning(+ts: String, +message: String) -> Json.Json:
  event("config-warning", ts, pair("message", str(message), Json.JNil{}))

# One line of stdout: json.dumps(event).
def line(+e: Json.Json) -> String:
  Json.emit_py(e)

# ---- the same events for a person (no --json) -------------------------------------------------

def s_of(+m: Maybe<&2, Json.Json>) -> String:
  match m:
    case Some{Json.JStr{s}}:
      s
    case Some{Json.JNum{t}}:
      t
    case _:
      ""

def f_of(+j: Json.Json, +k: String) -> String:
  s_of(Json.get(k, j))

def ref_text(+j: Json.Json) -> String:
  match j:
    case Json.JNull{}:
      "(none)"
    case _:
      "Account-" ++ f_of(j, "number") ++ " (" ++ f_of(j, "email") ++ ")"

def null_or(+m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case Some{v}:
      v
    case None{}:
      Json.JNull{}

def get_or_null(+j: Json.Json, +k: String) -> Json.Json:
  null_or(Json.get(k, j))

def poll_text2(+active: Json.Json, +e: Json.Json) -> String:
  match active:
    case Json.JNull{}:
      "poll: no active account"
    case _:
      "poll: " ++ ref_text(active) ++ " (switch at " ++ f_of(e, "threshold") ++ "%)"

def poll_text(+e: Json.Json) -> String:
  poll_text2(get_or_null(e, "active"), e)

def detail_text(+d: String) -> String:
  sel(String.is_empty(d), "", " (" ++ d ++ ")")

def is_dry(+m: Maybe<&2, Json.Json>) -> Bool:
  match m:
    case Some{Json.JBool{b}}:
      b
    case _:
      False{}

def switch_text(+e: Json.Json) -> String:
  sel(is_dry(Json.get("dryRun", e)), "[dry-run] would switch ", "Switched ") ++ ref_text(get_or_null(e, "from")) ++ " -> " ++ ref_text(get_or_null(e, "to")) ++ " (" ++ f_of(e, "trigger") ++ ")"

def human2(+kind: String, +e: Json.Json) -> String:
  sel(String.eq(kind, "poll"), poll_text(e),
  sel(String.eq(kind, "switch"), switch_text(e),
  sel(String.eq(kind, "no-switch"), "no switch: " ++ f_of(e, "reason") ++ detail_text(f_of(e, "detail")),
  sel(String.eq(kind, "all-exhausted"), "all accounts exhausted; earliest reset " ++ f_of(e, "earliestResetAt"),
  sel(String.eq(kind, "account-quarantined"), "Account-" ++ f_of(e, "number") ++ " (" ++ f_of(e, "email") ++ ") quarantined: " ++ f_of(e, "reason"),
  sel(String.eq(kind, "account-unquarantined"), "Account-" ++ f_of(e, "number") ++ " (" ++ f_of(e, "email") ++ ") back in rotation (" ++ f_of(e, "reason") ++ ")",
  sel(String.eq(kind, "sleep"), "sleeping " ++ f_of(e, "seconds") ++ "s (until " ++ f_of(e, "until") ++ ")",
  sel(String.eq(kind, "error"), "error: " ++ f_of(e, "message") ++ " (will retry)",
  "warning: " ++ f_of(e, "message")))))))))

# One line for the event, in the reference's words where they are simple.
def human(+e: Json.Json) -> String:
  human2(f_of(e, "event"), e)
