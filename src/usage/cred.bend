import Base
import ../http.bend as Http
import ../json.bend as Json
import ../clock.bend as Clock
import ./text.bend as UText
import ./norm.bend as UNorm
import ./req.bend as UReq

# ---- credential JSON -------------------------------------------------------

# A rotated credential and who the token endpoint said it belongs to
# (oauth._parse_token_account: {uuid, email, organizationUuid}, or JNull).

type Granted is Data:
  Granted{cred: String, account: Json.Json}

def parse.get(+k: String, r: Result<&2, &2, String, Json.Json>) -> Maybe<&2, Json.Json>:
  match r:
    case Fail{e}:
      None{}
    case Done{j}:
      Json.get(k, j)

def oauth.obj(+m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case Some{Json.JObj{f}}:
      Json.JObj{f}
    case _:
      Json.JNull{}

# The claudeAiOauth object of a credential text; JNull when absent or not an
# object (extract_oauth_data).
def oauth.of(+cred: String) -> Json.Json:
  oauth.obj(parse.get("claudeAiOauth", Json.parse(cred)))

def str.at(+k: String, +o: Json.Json) -> Maybe<&2, String>:
  UNorm.nonempty(Json.as_string(Maybe.default(&2, Json.Json, Json.get(k, o), Json.JNull{})))

def access_token(+o: Json.Json) -> Maybe<&2, String>:
  str.at("accessToken", o)

def refresh_token(+o: Json.Json) -> Maybe<&2, String>:
  str.at("refreshToken", o)

def has_refresh(+o: Json.Json) -> Bool:
  Maybe.is_some(&2, String, refresh_token(o))

def has_profile(+xs: List<&2, Json.Json>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{Json.JStr{s}, t}:
      String.eq(s, "user:profile") || has_profile(t)
    case Con{h, t}:
      has_profile(t)

def scopes.check(+xs: List<&2, Json.Json>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      Bool.not(has_profile(h <> t))

# `scopes` present and non-empty without user:profile: a setup-token.
def inference_only(+o: Json.Json) -> Bool:
  scopes.check(Json.to_list(Maybe.default(&2, Json.Json, Json.get("scopes", o), Json.JNull{})))

def exp.secs(+d: String) -> Maybe<&2, U32>:
  U32.read(String.take(d, Nat.sub(String.length(d), 3n)))

def exp.check(+ok: Bool, +d: String, +now: U32) -> Bool:
  match ok:
    case False{}:
      False{}
    case True{}:
      U32.is_ge((now + 300 : U32), Maybe.default(&2, U32, exp.secs(d), 0))

def exp.int(+ps: List<&2, String>, +now: U32) -> Bool:
  match ps:
    case Con{+i, t}:
      exp.check(Clock.all_digits(i) && Bool.not(String.is_empty(i)) && Nat.is_le(String.length(i), 13n), i, now)
    case Nil{}:
      False{}

def exp.num(+j: Json.Json, +now: U32) -> Bool:
  match j:
    case Json.JNum{t}:
      exp.int(String.split(t, '.'), now)
    case _:
      False{}

# is_oauth_token_expired: now + 5 min >= expiresAt (ms). Missing or
# non-numeric is not expired.
def expired(+o: Json.Json, +now: U32) -> Bool:
  exp.num(Maybe.default(&2, Json.Json, Json.get("expiresAt", o), Json.JNull{}), now)

# ---- token refresh ---------------------------------------------------------

def set.rt(+m: Maybe<&2, String>, +o: Json.Json) -> Json.Json:
  match m:
    case None{}:
      o
    case Some{r}:
      Json.set("refreshToken", Json.JStr{r}, o)

def scopes.cons(+skip: Bool, +h: String, +rest: List<&2, Json.Json>) -> List<&2, Json.Json>:
  match skip:
    case True{}:
      rest
    case False{}:
      Json.JStr{h} <> rest

def scopes.list(+ps: List<&2, String>) -> List<&2, Json.Json>:
  match ps:
    case Nil{}:
      []
    case Con{+h, t}:
      scopes.cons(String.is_empty(h), h, scopes.list(t))

def set.sc(+m: Maybe<&2, String>, +o: Json.Json) -> Json.Json:
  match m:
    case None{}:
      o
    case Some{s}:
      Json.set("scopes", Json.arr(scopes.list(String.split(s, ' '))), o)

# The credential's oauth object after a grant: accessToken, expiresAt (ms),
# then refreshToken and scopes when the response carries them.
def refresh.fields(+o: Json.Json, +at: String, +ex: U32, +rt: Maybe<&2, String>, +sc: Maybe<&2, String>, +now: U32) -> Json.Json:
  set.sc(sc, set.rt(rt, Json.set("expiresAt", Json.JNum{U32.show((now + ex : U32)) ++ "000"}, Json.set("accessToken", Json.JStr{at}, o))))

def token.org(+o: Maybe<&2, Json.Json>) -> Json.Json:
  match o:
    case Some{org}:
      Maybe.default(&2, Json.Json, Json.get("uuid", org), Json.JNull{})
    case None{}:
      Json.JNull{}

def token.acct3(+blank: Bool, +u: String, +a: Json.Json, +resp: Json.Json) -> Json.Json:
  match blank:
    case True{}:
      Json.JNull{}
    case False{}:
      Json.JObj{Json.JField{"uuid", Json.JStr{String.trim(u)}, Json.JField{"email", Maybe.default(&2, Json.Json, Json.get("email_address", a), Json.JNull{}), Json.JField{"organizationUuid", token.org(Json.get("organization", resp)), Json.JNil{}}}}}

def token.acct2(+uuid: Maybe<&2, String>, +a: Json.Json, +resp: Json.Json) -> Json.Json:
  match uuid:
    case None{}:
      Json.JNull{}
    case Some{u}:
      token.acct3(String.is_empty(String.trim(u)), u, a, resp)

def token.acct1(+a: Maybe<&2, Json.Json>, +resp: Json.Json) -> Json.Json:
  match a:
    case None{}:
      Json.JNull{}
    case Some{acct}:
      token.acct2(str.at("uuid", acct), acct, resp)

def token.account(+resp: Json.Json) -> Json.Json:
  token.acct1(Json.get("account", resp), resp)

def refresh.build(+j: Json.Json, +o: Json.Json, +resp: Json.Json, +now: U32) -> Maybe<&2, String>:
  do Maybe<&2, String>:
    a : Json.Json <- Json.get("access_token", resp)
    at : String <- Json.as_string(a)
    e : Json.Json <- Json.get("expires_in", resp)
    ex : U32 <- Json.as_u32(e)
    return Json.emit_py(Json.set("claudeAiOauth", refresh.fields(o, at, ex, str.at("refresh_token", resp), str.at("scope", resp), now), j))

def grant.ok(+m: Maybe<&2, String>, +acct: Json.Json) -> Result<&2, &2, String, Granted>:
  match m:
    case Some{c}:
      Done{Granted{c, acct}}
    case None{}:
      Fail{"transient"}

def grant.parse(r: Result<&2, &2, String, Json.Json>, +j: Json.Json, +o: Json.Json, +now: U32) -> Result<&2, &2, String, Granted>:
  match r:
    case Fail{e}:
      Fail{"transient"}
    case Done{+resp}:
      grant.ok(refresh.build(j, o, resp, now), token.account(resp))

# The verdict is the body's top-level `error`, only on 400/401/403: a dead
# lineage (invalid_grant) or a rejected client (invalid_client); everything
# else is transient.
def grant.err.kind(+hit: Bool, +s: String) -> Result<&2, &2, String, Granted>:
  match hit:
    case True{}:
      Fail{s}
    case False{}:
      Fail{"transient"}

def grant.err.pick(+e: Maybe<&2, String>) -> Result<&2, &2, String, Granted>:
  match e:
    case Some{+s}:
      grant.err.kind(String.eq(s, "invalid_grant") || String.eq(s, "invalid_client"), s)
    case None{}:
      Fail{"transient"}

def grant.err.body(r: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Granted>:
  match r:
    case Fail{m}:
      Fail{"transient"}
    case Done{b}:
      grant.err.pick(Json.as_string(Maybe.default(&2, Json.Json, Json.get("error", b), Json.JNull{})))

def rejects(+st: U32) -> Bool:
  U32.is_eq(st, 400) || U32.is_eq(st, 401) || U32.is_eq(st, 403)

def grant.err(+rejects: Bool, +body: String) -> Result<&2, &2, String, Granted>:
  match rejects:
    case True{}:
      grant.err.body(Json.parse(body))
    case False{}:
      Fail{"transient"}

def grant.reply.pick(+ok: Bool, +rj: Bool, +body: String, +j: Json.Json, +o: Json.Json, +now: U32) -> Result<&2, &2, String, Granted>:
  match ok:
    case True{}:
      grant.parse(Json.parse(body), j, o, now)
    case False{}:
      grant.err(rj, body)

def grant.reply(+rep: Http.Reply, +j: Json.Json, +o: Json.Json, +now: U32) -> Result<&2, &2, String, Granted>:
  match rep:
    case Http.Reply{st, head, body}:
      grant.reply.pick(UReq.ok2xx(st), rejects(st), body, j, o, now)

def grant.result(r: Result<&2, &2, String, Http.Reply>, +j: Json.Json, +o: Json.Json, +now: U32) -> Result<&2, &2, String, Granted>:
  match r:
    case Fail{k}:
      Fail{"transient"}
    case Done{rep}:
      grant.reply(rep, j, o, now)

# refresh: the token endpoint POST of try_refresh_oauth_credentials. Done
# carries the rotated credential text; Fail is `invalid_grant`,
# `invalid_client`, `no_refresh_token` or `transient`.
def refresh.post(+j: Json.Json, +o: Json.Json, +rt: String) -> IO(Result<&2, &2, String, Granted>):
  do IO<Result<&2, &2, String, Granted>>:
    now : U32 <- Clock.now_s()
    r : Result<&2, &2, String, Http.Reply> <- Http.request("POST", UText.token_url(),
      [("Content-Type", "application/json"), ("User-Agent", UText.user_agent())], UText.refresh.body(rt), 10)
    return grant.result(r, j, o, now)

def refresh.rt(+j: Json.Json, +o: Json.Json, +m: Maybe<&2, String>) -> IO(Result<&2, &2, String, Granted>):
  match m:
    case None{}:
      IO.pure(Result<&2, &2, String, Granted>, Fail{"no_refresh_token"})
    case Some{rt}:
      refresh.post(j, o, rt)

def refresh.top(+j: Json.Json, +o: Json.Json) -> IO(Result<&2, &2, String, Granted>):
  match j:
    case Json.JObj{f}:
      refresh.rt(j, o, refresh_token(o))
    case _:
      IO.pure(Result<&2, &2, String, Granted>, Fail{"transient"})

def refresh.parsed(r: Result<&2, &2, String, Json.Json>, +o: Json.Json) -> IO(Result<&2, &2, String, Granted>):
  match r:
    case Fail{e}:
      IO.pure(Result<&2, &2, String, Granted>, Fail{"transient"})
    case Done{j}:
      refresh.top(j, o)

# `refresh` with the account identity the token endpoint optionally names.
def refresh_acct(+cred: String) -> IO(Result<&2, &2, String, Granted>):
  refresh.parsed(Json.parse(cred), oauth.of(cred))

def granted.cred(r: Result<&2, &2, String, Granted>) -> Result<&2, &2, String, String>:
  match r:
    case Fail{k}:
      Fail{k}
    case Done{Granted{c, a}}:
      Done{c}

def refresh(+cred: String) -> IO(Result<&2, &2, String, String>):
  IO.bind(Result<&2, &2, String, Granted>, Result<&2, &2, String, String>, refresh_acct(cred), r => IO.pure(Result<&2, &2, String, String>, granted.cred(r)))
