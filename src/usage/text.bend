import Base
import ../http.bend as Http
import ../json.bend as Json
import ../clock.bend as Clock

def user_agent() -> String:
  "claude-swap/1.0"

def usage_url() -> String:
  "https://api.anthropic.com/api/oauth/usage"

def messages_url() -> String:
  "https://api.anthropic.com/v1/messages"

def token_url() -> String:
  "https://platform.claude.com/v1/oauth/token"

def client_id() -> String:
  "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

def probe_model() -> String:
  "claude-haiku-5-5"

# ---- request text ----------------------------------------------------------

def usage.config(token: String) -> String:
  Http.config("GET", usage_url(),
    [("Authorization", "Bearer " ++ token), ("anthropic-beta", "oauth-2025-04-20"), ("User-Agent", user_agent())],
    "", 5)

def probe.body() -> String:
  Json.emit_py(Json.of_pairs([
    ("model", Json.JStr{probe_model()}),
    ("max_tokens", Json.JNum{"1"}),
    ("system", Json.arr([Json.of_pairs([("type", Json.JStr{"text"}), ("text", Json.JStr{"You are Claude Code, Anthropic's official CLI for Claude."})])])),
    ("messages", Json.arr([Json.of_pairs([("role", Json.JStr{"user"}), ("content", Json.JStr{"."})])]))]))

def probe.config(token: String) -> String:
  Http.config("POST", messages_url(),
    [("Authorization", "Bearer " ++ token), ("anthropic-version", "2023-06-01"),
     ("anthropic-beta", "claude-code-20250219,oauth-2025-04-20"), ("content-type", "application/json"),
     ("User-Agent", user_agent())],
    probe.body(), 20)

def refresh.body(refresh_token: String) -> String:
  Json.emit_py(Json.of_pairs([
    ("grant_type", Json.JStr{"refresh_token"}), ("refresh_token", Json.JStr{refresh_token}), ("client_id", Json.JStr{client_id()})]))

def refresh.config(refresh_token: String) -> String:
  Http.config("POST", token_url(),
    [("Content-Type", "application/json"), ("User-Agent", user_agent())],
    refresh.body(refresh_token), 10)

# ---- numbers as text -------------------------------------------------------

def maybe.none_if(bad: Bool, s: String) -> Maybe<&2, String>:
  match bad:
    case True{}:
      None{}
    case False{}:
      Some{s}

def strip0.pick(zero: Bool, more: Bool, c: Char, t: String, rest: String) -> String:
  match zero more:
    case True{} True{}:
      rest
    case _ _:
      SCon{c, t}

# Leading zeros dropped, keeping at least one digit.
def strip0(s: String) -> String:
  match s:
    case SNil{}:
      "0"
    case SCon{+c, +t}:
      strip0.pick(Char.is_eq(c, '0'), Bool.not(String.is_empty(t)), c, t, strip0(t))

def float.mk(neg: Bool, +i: String, +f: String) -> Maybe<&2, String>:
  maybe.none_if(Bool.not(Clock.all_digits(i) && Clock.all_digits(f) && Bool.not(String.is_empty(i))),
    Clock.sel.s(neg, "-", "") ++ strip0(i) ++ "." ++ String.reverse(strip0(String.reverse(f))))

def float.parts(neg: Bool, ps: List<&2, String>) -> Maybe<&2, String>:
  match ps:
    case Con{i, Nil{}}:
      float.mk(neg, i, "0")
    case Con{i, Con{f, Nil{}}}:
      float.mk(neg, i, f)
    case _:
      None{}

def float.sign(+neg: Bool, +s: String) -> Maybe<&2, String>:
  float.parts(neg, String.split(Clock.sel.s(neg, String.drop(s, 1n), s), '.'))

# A JSON number's text as Python prints float(text): `50` -> `50.0`, `5.50` ->
# `5.5`. None for anything but plain decimals (exponents, signs after the
# first, text).
def float(+s: String) -> Maybe<&2, String>:
  float.sign(String.starts_with(s, "-"), s)

def split.int(ps: List<&2, String>) -> Maybe<&2, String>:
  match ps:
    case Con{i, t}:
      Some{i}
    case Nil{}:
      None{}

# float(text) / 100 as Python prints it (decimal shift, exact for decimals).
def div100.fin(+i2: String, +f: String) -> Maybe<&2, String>:
  float(String.take(i2, Nat.sub(String.length(i2), 2n)) ++ "." ++ String.drop(i2, Nat.sub(String.length(i2), 2n)) ++ f)

def div100.parts(ps: List<&2, String>) -> Maybe<&2, String>:
  match ps:
    case Con{i, Con{f, Nil{}}}:
      div100.fin("00" ++ i, f)
    case _:
      None{}

def div100.go(m: Maybe<&2, String>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{n}:
      div100.parts(String.split(n, '.'))

def div100(+s: String) -> Maybe<&2, String>:
  div100.go(float(s))

# round(float(s) * 100, 1) for a decimal fraction: tenths of a percent, as
# text. `0.25` -> `25.0`, `0.4256` -> `42.6`.
def pct1.show(+n: U32) -> String:
  U32.show((n / 10 : U32)) ++ "." ++ U32.show((n % 10 : U32))

def pct1.fin(+i: String, +f: String) -> Maybe<&2, String>:
  do Maybe<&2, String>:
    ip : U32 <- U32.read(i)
    fp : U32 <- Clock.num(f ++ "0000", 0n, 3n)
    rd : U32 <- Clock.num(f ++ "0000", 3n, 1n)
    return pct1.show((ip * 1000 + fp + Clock.sel(U32.is_ge(rd, 5), 1, 0) : U32))

def pct1.pick(ok: Bool, +i: String, +f: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      pct1.fin(i, f)
    case False{}:
      None{}

def pct1.parts(ps: List<&2, String>) -> Maybe<&2, String>:
  match ps:
    case Con{+i, Nil{}}:
      pct1.pick(Clock.all_digits(i) && Bool.not(String.is_empty(i)) && Nat.is_le(String.length(i), 6n), i, "")
    case Con{+i, Con{+f, Nil{}}}:
      pct1.pick(Clock.all_digits(i) && Clock.all_digits(f) && Bool.not(String.is_empty(i)) && Nat.is_le(String.length(i), 6n), i, f)
    case _:
      None{}

def pct1(s: String) -> Maybe<&2, String>:
  pct1.parts(String.split(s, '.'))

# ---- rate-limit headers (patch 0003) ---------------------------------------

def rl() -> String:
  "anthropic-ratelimit-unified-"

def reset.epoch(m: Maybe<&2, U32>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{t}:
      Some{Clock.iso8601_offset(t)}

def reset.iso(m: Maybe<&2, String>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      reset.epoch(U32.read(s))

def hwin.mk(pct: String, reset: Maybe<&2, String>) -> Maybe<&2, Json.Json>:
  match reset:
    case None{}:
      Some{Json.of_pairs([("utilization", Json.JNum{pct})])}
    case Some{r}:
      Some{Json.of_pairs([("utilization", Json.JNum{pct}), ("resets_at", Json.JStr{r})])}

def hwin.pick(pct: Maybe<&2, String>, reset: Maybe<&2, String>) -> Maybe<&2, Json.Json>:
  match pct:
    case None{}:
      None{}
    case Some{p}:
      hwin.mk(p, reset)

def hwin.util(u: Maybe<&2, String>, reset: Maybe<&2, String>) -> Maybe<&2, Json.Json>:
  match u:
    case None{}:
      None{}
    case Some{x}:
      hwin.pick(pct1(x), reset.iso(reset))

# One window ("5h" or "7d") of the rate-limit headers: utilization is a
# fraction, reset an epoch. No utilization header, no window.
def hwin(+p: String, +head: String) -> Maybe<&2, Json.Json>:
  hwin.util(Http.header(rl() ++ p ++ "-utilization:", head), Http.header(rl() ++ p ++ "-reset:", head))

def hdata.set(k: String, w: Maybe<&2, Json.Json>, j: Json.Json) -> Json.Json:
  match w:
    case None{}:
      j
    case Some{v}:
      Json.set(k, v, j)

def hdata.keys(ks: List<&2, String>, j: Json.Json) -> Maybe<&2, Json.Json>:
  match ks:
    case Nil{}:
      None{}
    case Con{h, t}:
      Some{j}

def hdata.fin(+j: Json.Json) -> Maybe<&2, Json.Json>:
  hdata.keys(Json.keys(j), j)

# `anthropic-ratelimit-unified-*` response headers (the raw header block) in
# the /api/oauth/usage shape; None when neither window is present.
def usage_from_ratelimit_headers(+head: String) -> Maybe<&2, Json.Json>:
  hdata.fin(hdata.set("seven_day", hwin("7d", head), hdata.set("five_hour", hwin("5h", head), Json.of_pairs([]))))
