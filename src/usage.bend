import Base
import ./json.bend as Json
import ./clock.bend as Clock
import ./usage/norm.bend as UNorm
import ./usage/req.bend as UReq
import ./usage/cred.bend as UCred
import ./usage/gate.bend as UGate

# Usage reads, as the reference's oauth.py (claude-swap 0.27.2 plus patch
# 0003): the usage endpoint for full-login tokens, the one-token inference
# probe (rate-limit headers) for setup-tokens and on a usage-endpoint 429.
# Pure parts first (header mapping, normalisation, classification, request
# text), then the effects. Nothing here logs: tokens live only in a curl
# config on stdin and in the credential text the caller owns.

# ---- fetch_usage -----------------------------------------------------------

# usage: the normalised result (JNull when there is none); error: the kind
# (http-429, http-403, timeout, network, bad-response, no-access-token,
# invalid_grant, no_refresh_token, invalid_client, refresh-failed, ...);
# retry: Retry-After seconds; struck: the credential text whose refresh token
# the server rejected for good (the store quarantines on it).
type Outcome is Data:
  Outcome{usage: Json.Json, error: Maybe<&2, String>, retry: Maybe<&2, U32>, struck: Maybe<&2, String>}

# credential: the rotated credential when a refresh succeeded, for the store
# to persist.
type Fetched is Data:
  Fetched{outcome: Outcome, credential: Maybe<&2, String>}

def done(o: Outcome, upd: Maybe<&2, String>) -> IO(Fetched):
  IO.pure(Fetched, Fetched{o, upd})

def out.ok(+data: Json.Json, +now: U32, +off: U32) -> Outcome:
  Outcome{UNorm.build_usage_result(data, now, off), None{}, None{}, None{}}

def out.err(e: UReq.Err) -> Outcome:
  match e:
    case UReq.Err{kind, retry, body}:
      Outcome{Json.JNull{}, Some{kind}, retry, None{}}

def out.kind(k: String, struck: Maybe<&2, String>) -> Outcome:
  Outcome{Json.JNull{}, Some{k}, None{}, struck}

def dead(+k: String) -> Bool:
  String.eq(k, "invalid_grant") || String.eq(k, "no_refresh_token")

def final.pick(r: Result<&2, &2, UReq.Err, Json.Json>, +now: U32, +off: U32, upd: Maybe<&2, String>) -> IO(Fetched):
  match r:
    case Done{d}:
      done(out.ok(d, now, off), upd)
    case Fail{e}:
      done(out.err(e), upd)

# Refusals that will not resolve by retrying this pass: the caller must not
# fall through to the usage endpoint with the known-expired token.
def deterministic(+k: String) -> Bool:
  String.eq(k, "invalid_client") || String.eq(k, "consume-busy") || String.eq(k, "store-unmirrored")

def retry.k(+k: String) -> String:
  Clock.sel.s(dead(k) || deterministic(k), k, "refresh-failed")

def struck.pick(d: Bool, cred: String) -> Maybe<&2, String>:
  match d:
    case True{}:
      Some{cred}
    case False{}:
      None{}

def retry.struck(+k: String, +cred: String) -> Maybe<&2, String>:
  struck.pick(dead(k), cred)

def retry.tok(m: Maybe<&2, String>, new: String, +now: U32, +off: U32) -> IO(Fetched):
  match m:
    case None{}:
      done(out.kind("refresh-failed", None{}), Some{new})
    case Some{t}:
      IO.bind(Result<&2, &2, UReq.Err, Json.Json>, Fetched, UReq.request_usage_data(t, False{}),
        r => final.pick(r, now, off, Some{new}))

def retry.fail(e: Maybe<&2, String>, consumed: Maybe<&2, String>, +cred: String, upd: Maybe<&2, String>) -> IO(Fetched):
  match e:
    case Some{+k}:
      done(out.kind(retry.k(k), retry.struck(k, Maybe.default(&2, String, consumed, cred))), upd)
    case None{}:
      done(out.kind("refresh-failed", None{}), upd)

def retry.got(c: Maybe<&2, String>, e: Maybe<&2, String>, consumed: Maybe<&2, String>, +cred: String, +now: U32, +off: U32, upd: Maybe<&2, String>) -> IO(Fetched):
  match c:
    case Some{+new}:
      retry.tok(UCred.access_token(UCred.oauth.of(new)), new, now, off)
    case None{}:
      retry.fail(e, consumed, cred, upd)

# After a 401 and a refresh: failures keep their identity only when the
# reference does (dead lineage, rejected client, consume-busy), else
# `refresh-failed`.
def retry.pick(g: UGate.Gated, +cred: String, +now: U32, +off: U32, upd: Maybe<&2, String>) -> IO(Fetched):
  match g:
    case UGate.Gated{c, e, consumed, acct}:
      retry.got(c, e, consumed, cred, now, off, upd)

def fail.refresh(retry: Bool, e: UReq.Err, gate: UGate.Gate, +cred: String, +now: U32, +off: U32, upd: Maybe<&2, String>) -> IO(Fetched):
  match retry:
    case True{}:
      IO.bind(UGate.Gated, Fetched, UGate.refresh_via(gate, cred), g => retry.pick(g, cred, now, off, upd))
    case False{}:
      done(out.err(e), upd)

def is_401(e: UReq.Err) -> Bool:
  match e:
    case UReq.Err{kind, retry, body}:
      String.eq(kind, "http-401")

# 401 on an inactive account with a refresh token: refresh once, retry once.
def fetch.after(r: Result<&2, &2, UReq.Err, Json.Json>, gate: UGate.Gate, +cred: String, +o: Json.Json, +active: Bool, +now: U32, +off: U32, upd: Maybe<&2, String>) -> IO(Fetched):
  match r:
    case Done{d}:
      done(out.ok(d, now, off), upd)
    case Fail{+e}:
      fail.refresh(is_401(e) && Bool.not(active) && UCred.has_refresh(o), e, gate, cred, now, off, upd)

def fetch.req(+gate: UGate.Gate, +cred: String, +o: Json.Json, +token: String, +active: Bool, +now: U32, +off: U32, upd: Maybe<&2, String>, inf: Bool) -> IO(Fetched):
  IO.bind(Result<&2, &2, UReq.Err, Json.Json>, Fetched, UReq.request_usage_data(token, inf),
    r => fetch.after(r, gate, cred, o, active, now, off, upd))

def pre.stop(stop: Bool, +k: String, gate: UGate.Gate, +cred: String, +o: Json.Json, +token: String, +active: Bool, +now: U32, +off: U32, consumed: Maybe<&2, String>) -> IO(Fetched):
  match stop:
    case True{}:
      done(out.kind(k, retry.struck(k, Maybe.default(&2, String, consumed, cred))), None{})
    case False{}:
      fetch.req(gate, cred, o, token, active, now, off, None{}, UCred.inference_only(o))

def pre.fail(e: Maybe<&2, String>, consumed: Maybe<&2, String>, gate: UGate.Gate, +cred: String, +o: Json.Json, +token: String, +active: Bool, +now: U32, +off: U32) -> IO(Fetched):
  match e:
    case Some{+k}:
      pre.stop(dead(k) || deterministic(k), k, gate, cred, o, token, active, now, off, consumed)
    case None{}:
      pre.stop(False{}, "transient", gate, cred, o, token, active, now, off, consumed)

# Before the request: an expired token of an inactive account is refreshed. A
# dead lineage or a deterministic refusal stops here; a transient failure goes
# on with the old token. A refreshed token is a new token: the usage endpoint
# first, even for a setup-token scope.
def pre.new(gate: UGate.Gate, +new: String, +token: String, +active: Bool, +now: U32, +off: U32) -> IO(Fetched):
  fetch.req(gate, new, UCred.oauth.of(new), Maybe.default(&2, String, UCred.access_token(UCred.oauth.of(new)), token), active, now, off, Some{new}, False{})

def pre.got(c: Maybe<&2, String>, e: Maybe<&2, String>, consumed: Maybe<&2, String>, gate: UGate.Gate, +cred: String, +o: Json.Json, +token: String, +active: Bool, +now: U32, +off: U32) -> IO(Fetched):
  match c:
    case Some{new}:
      pre.new(gate, new, token, active, now, off)
    case None{}:
      pre.fail(e, consumed, gate, cred, o, token, active, now, off)

def fetch.pre(g: UGate.Gated, gate: UGate.Gate, +cred: String, +o: Json.Json, +token: String, +active: Bool, +now: U32, +off: U32) -> IO(Fetched):
  match g:
    case UGate.Gated{c, e, consumed, acct}:
      pre.got(c, e, consumed, gate, cred, o, token, active, now, off)

def gate.pick(needs: Bool, +gate: UGate.Gate, +cred: String, +o: Json.Json, +token: String, +active: Bool, +now: U32, +off: U32) -> IO(Fetched):
  match needs:
    case True{}:
      IO.bind(UGate.Gated, Fetched, UGate.refresh_via(gate, cred), g => fetch.pre(g, gate, cred, o, token, active, now, off))
    case False{}:
      fetch.req(gate, cred, o, token, active, now, off, None{}, UCred.inference_only(o))

def fetch.gate(+gate: UGate.Gate, +cred: String, +o: Json.Json, token: String, +active: Bool, +now: U32, +off: U32) -> IO(Fetched):
  gate.pick(Bool.not(active) && UCred.has_refresh(o) && UCred.expired(o, now), gate, cred, o, token, active, now, off)

def fetch.start(m: Maybe<&2, String>, gate: UGate.Gate, +cred: String, +o: Json.Json, +active: Bool, +now: U32, +off: U32) -> IO(Fetched):
  match m:
    case None{}:
      done(out.kind("no-access-token", None{}), None{})
    case Some{t}:
      fetch.gate(gate, cred, o, t, active, now, off)

# The local UTC offset, biased by 86400 (86400 = UTC when `date` is unusable).
def offset.of(oe: String & String) -> U32:
  (o, e) = oe
  Maybe.default(&2, U32, Clock.tz(String.trim(o)), 86400)

def offset.run(r: U32 & (String & String)) -> U32:
  (st, oe) = r
  offset.of(oe)

def offset.pick(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> U32:
  match r:
    case Fail{e}:
      86400
    case Done{v}:
      offset.run(v)

def local_offset() -> IO(U32):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, U32, Process.run("date", ["+%z"], "", 64, 2000),
    r => IO.pure(U32, offset.pick(r)))

# fetch_usage plus the 401 refresh of try_fetch_usage_for_account, over the
# credential JSON text. Refreshes only inactive accounts. The rotated
# credential comes back in `Fetched.credential` for the store to persist.
# `gate` picks the refresh path: NoGate{} posts directly (tests); Gate{slot,
# email, root} runs it under the slot's consume lock.
def fetch_with(gate: UGate.Gate, +credential: String, is_active: Bool) -> IO(Fetched):
  do IO<Fetched>:
    now : U32 <- Clock.now_s()
    off : U32 <- local_offset()
    fetch.start(UCred.access_token(UCred.oauth.of(credential)), gate, credential, UCred.oauth.of(credential), is_active, now, off)

def fetch_usage(credential: String, is_active: Bool) -> IO(Fetched):
  fetch_with(UGate.NoGate{}, credential, is_active)

# The same, refreshing through the consume gate on <root>/credentials.
def fetch_usage_gated(credential: String, is_active: Bool, slot: String, email: String, root: String) -> IO(Fetched):
  fetch_with(UGate.Gate{slot, email, root}, credential, is_active)
