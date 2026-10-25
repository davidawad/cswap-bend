import Base
import ../http.bend as Http
import ../json.bend as Json
import ./text.bend as UText

# ---- error classification --------------------------------------------------

# kind: http-<code>, timeout, network, bad-response (the reference's
# _classify_usage_error names); retry: Retry-After seconds when sent; body: the
# response text, kept only to tell a scope 403 from other 403s (never shown).
type Err is Data:
  Err{kind: String, retry: Maybe<&2, U32>, body: String}

def retry.int(ps: List<&2, String>) -> Maybe<&2, U32>:
  match ps:
    case Con{i, t}:
      U32.read(i)
    case Nil{}:
      None{}

def retry.norm(m: Maybe<&2, String>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{n}:
      retry.int(String.split(n, '.'))

def retry.zero(m: Maybe<&2, String>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{n}:
      Some{0}

def retry.neg(neg: Bool, +raw: String) -> Maybe<&2, U32>:
  match neg:
    case True{}:
      retry.zero(UText.float(String.drop(raw, 1n)))
    case False{}:
      retry.norm(UText.float(raw))

def retry.of(m: Maybe<&2, String>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{+raw}:
      retry.neg(String.starts_with(raw, "-"), raw)

# Retry-After in whole seconds (the seconds form only; fractions drop, a
# negative value is 0, anything else is none).
def retry_after(+head: String) -> Maybe<&2, U32>:
  retry.of(Http.header("retry-after:", head))

def http.err(+r: Http.Reply) -> Err:
  match r:
    case Http.Reply{st, head, body}:
      Err{"http-" ++ U32.show(st), retry_after(head), body}

def ok2xx(+st: U32) -> Bool:
  U32.is_ge(st, 200) && U32.is_lt(st, 300)

# The reference raises on a 403 whose body says the token lacks scope.
def scope_error(e: Err) -> Bool:
  match e:
    case Err{kind, retry, +body}:
      String.eq(kind, "http-403") && (String.contains(body, "oauth_scope_insufficient") || String.contains(body, "scope requirement"))

def is_429(e: Err) -> Bool:
  match e:
    case Err{kind, retry, body}:
      String.eq(kind, "http-429")

def bad(kind: String) -> Err:
  Err{kind, None{}, ""}

# ---- the two usage requests ------------------------------------------------

def probe.pick(data: Maybe<&2, Json.Json>, ok: Bool, e: Err) -> Result<&2, &2, Err, Json.Json>:
  match data ok:
    case Some{d} _:
      Done{d}
    case None{} True{}:
      Fail{bad("bad-response")}
    case None{} False{}:
      Fail{e}

def probe.reply(+r: Http.Reply) -> Result<&2, &2, Err, Json.Json>:
  match r:
    case Http.Reply{st, head, body}:
      probe.pick(UText.usage_from_ratelimit_headers(head), ok2xx(st), http.err(r))

def probe.result(r: Result<&2, &2, String, Http.Reply>) -> Result<&2, &2, Err, Json.Json>:
  match r:
    case Fail{k}:
      Fail{bad(k)}
    case Done{rep}:
      probe.reply(rep)

# The one-token Messages call whose rate-limit headers carry the usage; a
# non-2xx that still has the headers (429 when exhausted) is a valid reading.
def probe(token: String) -> IO(Result<&2, &2, Err, Json.Json>):
  IO.bind(Result<&2, &2, String, Http.Reply>, Result<&2, &2, Err, Json.Json>,
    Http.request("POST", UText.messages_url(),
      [("Authorization", "Bearer " ++ token), ("anthropic-version", "2023-06-01"),
       ("anthropic-beta", "claude-code-20250219,oauth-2025-04-20"), ("content-type", "application/json"),
       ("User-Agent", UText.user_agent())],
      UText.probe.body(), 20),
    r => IO.pure(Result<&2, &2, Err, Json.Json>, probe.result(r)))

# data.get on a non-object raises AttributeError in the reference.
def body.obj(j: Json.Json) -> Result<&2, &2, Err, Json.Json>:
  match j:
    case Json.JObj{f}:
      Done{j}
    case _:
      Fail{bad("AttributeError")}

def body.json(ok: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, Err, Json.Json>:
  match ok:
    case Fail{m}:
      Fail{bad("bad-response")}
    case Done{j}:
      body.obj(j)

def usage.pick(ok: Bool, +body: String, e: Err) -> Result<&2, &2, Err, Json.Json>:
  match ok:
    case True{}:
      body.json(Json.parse(body))
    case False{}:
      Fail{e}

def usage.reply(+r: Http.Reply) -> Result<&2, &2, Err, Json.Json>:
  match r:
    case Http.Reply{st, head, body}:
      usage.pick(ok2xx(st), body, http.err(r))

def usage.result(r: Result<&2, &2, String, Http.Reply>) -> Result<&2, &2, Err, Json.Json>:
  match r:
    case Fail{k}:
      Fail{bad(k)}
    case Done{rep}:
      usage.reply(rep)

def usage.get(token: String) -> IO(Result<&2, &2, Err, Json.Json>):
  IO.bind(Result<&2, &2, String, Http.Reply>, Result<&2, &2, Err, Json.Json>,
    Http.request("GET", UText.usage_url(),
      [("Authorization", "Bearer " ++ token), ("anthropic-beta", "oauth-2025-04-20"), ("User-Agent", UText.user_agent())],
      "", 5),
    r => IO.pure(Result<&2, &2, Err, Json.Json>, usage.result(r)))

# A probe that failed after a usage-endpoint 429 hands back the 429.
def fallback.pick(p: Result<&2, &2, Err, Json.Json>, orig: Err) -> Result<&2, &2, Err, Json.Json>:
  match p:
    case Done{d}:
      Done{d}
    case Fail{e}:
      Fail{orig}

def fallback(+token: String, +orig: Err) -> IO(Result<&2, &2, Err, Json.Json>):
  IO.bind(Result<&2, &2, Err, Json.Json>, Result<&2, &2, Err, Json.Json>, probe(token),
    p => IO.pure(Result<&2, &2, Err, Json.Json>, fallback.pick(p, orig)))

def route(scope: Bool, rl: Bool, e: Err, token: String) -> IO(Result<&2, &2, Err, Json.Json>):
  match scope rl:
    case True{} _:
      probe(token)
    case False{} True{}:
      fallback(token, e)
    case False{} False{}:
      IO.pure(Result<&2, &2, Err, Json.Json>, Fail{e})

def usage.next(r: Result<&2, &2, Err, Json.Json>, token: String) -> IO(Result<&2, &2, Err, Json.Json>):
  match r:
    case Done{d}:
      IO.pure(Result<&2, &2, Err, Json.Json>, Done{d})
    case Fail{+e}:
      route(scope_error(e), is_429(e), e, token)

def request_data.go(+token: String, inference_only: Bool) -> IO(Result<&2, &2, Err, Json.Json>):
  match inference_only:
    case True{}:
      probe(token)
    case False{}:
      IO.bind(Result<&2, &2, Err, Json.Json>, Result<&2, &2, Err, Json.Json>, usage.get(token), r => usage.next(r, token))

# request_usage_data: the usage endpoint, with the probe for an
# inference-only token, after a scope 403, and after a 429 (whose own error
# stands if the probe fails too).
def request_usage_data(token: String, inference_only: Bool) -> IO(Result<&2, &2, Err, Json.Json>):
  request_data.go(token, inference_only)
