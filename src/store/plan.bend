import Base
import ../json.bend as Json
import ../act.bend as Act
import ./base.bend as SBase
import ./seq.bend as SSeq

# ---- the identity oracle (GET /api/oauth/profile) ------------------------------------

# What the oracle answered: nothing usable, or an account uuid with an
# optional address and organization.
type Prof is Data:
  ProfNone{}
  Prof{uuid: String, email: Maybe<&2, String>, org: Maybe<&2, String>}

def opt_str(+rec: Json.Json, +key: String) -> Maybe<&2, String>:
  Maybe.bind(&2, Json.Json, String, Json.get(key, rec), s => Json.as_string(s))

def org_uuid_of(+o: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match o:
    case None{}:
      None{}
    case Some{rec}:
      opt_str(rec, "uuid")

def prof3b(+empty: Bool, +uuid: String, +email: Maybe<&2, String>, +org: Maybe<&2, String>) -> Prof:
  match empty:
    case True{}:
      ProfNone{}
    case False{}:
      Prof{uuid, email, org}

def prof3(+uuid: String, +email: Maybe<&2, String>, +org: Maybe<&2, String>) -> Prof:
  prof3b(String.is_empty(uuid), uuid, email, org)

def prof2(+acct: Maybe<&2, Json.Json>, +org: Maybe<&2, String>) -> Prof:
  match acct:
    case None{}:
      ProfNone{}
    case Some{a}:
      prof3(String.trim(SSeq.field_str(a, "uuid")), opt_str(a, "email"), org)

# oauth.fetch_oauth_profile's reading of the response body.
def profile_of(+j: Json.Json) -> Prof:
  prof2(Json.get("account", j), org_uuid_of(Json.get("organization", j)))

def profile_of_res(r: Result<&2, &2, String, Json.Json>) -> Prof:
  match r:
    case Fail{e}:
      ProfNone{}
    case Done{j}:
      profile_of(j)

def profile_of_text(+body: String) -> Prof:
  profile_of_res(Json.parse(body))

# Should the stored credential's owner be looked up, and with which token?
type Plan is Data:
  PSkip{why: String}
  PFetch{token: String}

# The access token's expiry in whole seconds (`expiresAt` is epoch ms).
def expires_s(+ms: String) -> Maybe<&2, U32>:
  U32.read(String.take(ms, Nat.sub(String.length(ms), 3n)))

def token_of(+creds: Json.Json) -> String:
  SSeq.field_str(SSeq.get_or("claudeAiOauth", creds, Json.JNull{}), "accessToken")

def expiry_text(+m: Maybe<&2, Json.Json>) -> Maybe<&2, U32>:
  match m:
    case Some{Json.JNum{t}}:
      expires_s(t)
    case _:
      None{}

def expiry_of(+creds: Json.Json) -> Maybe<&2, U32>:
  expiry_text(Json.get("expiresAt", SSeq.get_or("claudeAiOauth", creds, Json.JNull{})))

def plan5(+expired: Bool, +token: String) -> Plan:
  match expired:
    case True{}:
      PSkip{"the access token is expired"}
    case False{}:
      PFetch{token}

def plan4(+token: String, +expiry: Maybe<&2, U32>, +now: U32) -> Plan:
  match expiry:
    case Some{e}:
      plan5(U32.is_le(e, now), token)
    case None{}:
      PFetch{token}

def plan3b(+empty: Bool, +token: String, +expiry: Maybe<&2, U32>, +now: U32) -> Plan:
  match empty:
    case True{}:
      PSkip{"no access token to resolve"}
    case False{}:
      plan4(token, expiry, now)

def plan3(+token: String, +expiry: Maybe<&2, U32>, +now: U32) -> Plan:
  plan3b(String.is_empty(token), token, expiry, now)

def plan_res(r: Result<&2, &2, String, Json.Json>, +now: U32) -> Plan:
  match r:
    case Fail{e}:
      PSkip{"no access token to resolve"}
    case Done{+j}:
      plan3(token_of(j), expiry_of(j), now)

def plan_for(+creds: String, +now: U32) -> Plan:
  plan_res(Json.parse(creds), now)

type Verdict is Data:
  VOk{}
  VUnverified{why: String}
  VBad{msg: String}

def bad_uuid(+email: String, +seen: String, +want: String) -> String:
  "The stored credential does not belong to " ++ email ++ ": the token resolves to account " ++ seen ++ ", not " ++ want
    ++ ". Nothing was changed. This happens when the config names one account while the credential store still holds another's token (e.g. a renamed .claude.json over a live keychain item). Log in as "
    ++ email ++ " in THIS environment, then re-run."

def bad_email(+email: String, +seen: String) -> String:
  "The stored credential does not belong to " ++ email ++ ": the token resolves to " ++ seen
    ++ ". Nothing was changed. This happens when the config names one account while the credential store still holds another's token (e.g. a renamed .claude.json over a live keychain item). Log in as "
    ++ email ++ " in THIS environment, then re-run."

def bad_org(+email: String, +seen: String, +want: String) -> String:
  "The stored credential for " ++ email ++ " belongs to organization " ++ SBase.sel.s(String.is_empty(seen), "personal", seen)
    ++ ", not " ++ SBase.sel.s(String.is_empty(want), "personal", want) ++ ". Nothing was changed. Two accounts can share an email across organizations. Log in as "
    ++ email ++ " in the " ++ SBase.sel.s(String.is_empty(want), "personal", want) ++ " organization in THIS environment, then re-run."

def org_verdict2(+same: Bool, +email: String, +seen: String, +want: String) -> Verdict:
  match same:
    case True{}:
      VOk{}
    case False{}:
      VBad{bad_org(email, seen, want)}

def org_verdict(+email: String, +want: String, +org: Maybe<&2, String>) -> Verdict:
  match org:
    case None{}:
      VOk{}
    case Some{o}:
      org_verdict2(String.eq(String.trim(o), want), email, String.trim(o), want)

# Only a clean identity match goes on to the organization check.
def then_org(+v: Verdict, +email: String, +want: String, +org: Maybe<&2, String>) -> Verdict:
  match v:
    case VOk{}:
      org_verdict(email, want, org)
    case _:
      v

def sel.v(+c: Bool, +x: Verdict, +y: Verdict) -> Verdict:
  match c:
    case True{}:
      x
    case False{}:
      y

def ident_by_email2(+empty: Bool, +email: String, +seen: String) -> Verdict:
  match empty:
    case True{}:
      VUnverified{"the resolved identity carries no address"}
    case False{}:
      sel.v(String.eq(String.to_lower(seen), String.to_lower(email)), VOk{}, VBad{bad_email(email, seen)})

def ident_by_email(+email: String, +seen: String) -> Verdict:
  ident_by_email2(String.is_empty(seen), email, seen)

def ident_verdict2(+no_uuid: Bool, +email: String, +acct_uuid: String, +uuid: String, +pemail: Maybe<&2, String>) -> Verdict:
  match no_uuid:
    case True{}:
      ident_by_email(email, String.trim(SSeq.str_or(pemail, "")))
    case False{}:
      sel.v(String.eq(uuid, acct_uuid), VOk{}, VBad{bad_uuid(email, uuid, acct_uuid)})

def ident_verdict(+email: String, +acct_uuid: String, +uuid: String, +pemail: Maybe<&2, String>) -> Verdict:
  ident_verdict2(String.is_empty(acct_uuid), email, acct_uuid, uuid, pemail)

# Does the credential's owner match (email, org, accountUuid)? Uuid first,
# then the address only when no uuid is on file; the org is checked either way.
# None from the oracle is "unresolvable", never "wrong".
def judge(+email: String, +org: String, +acct_uuid: String, +p: Prof) -> Verdict:
  match p:
    case ProfNone{}:
      VUnverified{"the identity lookup did not resolve"}
    case Prof{uuid, pemail, porg}:
      then_org(ident_verdict(email, acct_uuid, uuid, pemail), email, org, porg)

# ---- choosing a slot (pure) ---------------------------------------------------------------

# Where a new identity goes: its slot, the slot of another account to displace
# (archived, never deleted) and the old slot of the same account when it moves.
type SlotPlan is Data:
  SPOk{num: String, displace: Maybe<&2, String>, migrate: Maybe<&2, String>}
  SPErr{code: U32, msg: String}

def sel.m(+c: Bool, +x: Maybe<&2, String>, +y: Maybe<&2, String>) -> Maybe<&2, String>:
  match c:
    case True{}:
      x
    case False{}:
      y

def differs(+m: Maybe<&2, String>, +num: String) -> Maybe<&2, String>:
  match m:
    case Some{old}:
      sel.m(String.eq(old, num), None{}, Some{old})
    case None{}:
      None{}

def occupied2(+same: Bool, +assume_yes: Bool, +num: String, +other: String) -> SlotPlan:
  match same assume_yes:
    case True{} _:
      SPOk{num, None{}, None{}}
    case False{} True{}:
      SPOk{num, Some{num}, None{}}
    case False{} False{}:
      SPErr{10, "Slot " ++ num ++ " already occupied by " ++ other}

def occupied(+rec: Maybe<&2, Json.Json>, +email: String, +org: String, +assume_yes: Bool, +num: String) -> SlotPlan:
  match rec:
    case None{}:
      SPOk{num, None{}, None{}}
    case Some{r}:
      occupied2(SSeq.rec_is(r, email, org), assume_yes, num, SSeq.field_str(r, "email"))

def with_migrate(+p: SlotPlan, +m: Maybe<&2, String>) -> SlotPlan:
  match p:
    case SPOk{num, d, old}:
      SPOk{num, d, m}
    case _:
      p

def plan_slot2(+n: U32, +seq: Json.Json, +email: String, +org: String, +assume_yes: Bool) -> SlotPlan:
  with_migrate(occupied(SSeq.slot_record(seq, U32.show(n)), email, org, assume_yes, U32.show(n)),
    differs(SSeq.find_slot(seq, email, org), U32.show(n)))

def plan_slot1(+low: Bool, +n: U32, +seq: Json.Json, +email: String, +org: String, +assume_yes: Bool) -> SlotPlan:
  match low:
    case True{}:
      SPErr{1, "Slot number must be >= 1"}
    case False{}:
      plan_slot2(n, seq, email, org, assume_yes)

def plan_slot(+slot: Maybe<&2, U32>, +seq: Json.Json, +email: String, +org: String, +assume_yes: Bool) -> SlotPlan:
  match slot:
    case None{}:
      SPOk{U32.show(SSeq.next_slot(seq)), None{}, None{}}
    case Some{n}:
      plan_slot1(U32.is_lt(n, 1), n, seq, email, org, assume_yes)

# ---- records and credential payloads ------------------------------------------------------

def with_kind(+api_key: Bool, +rec: Json.Json) -> Json.Json:
  match api_key:
    case True{}:
      Json.set("kind", SSeq.jstr("api_key"), rec)
    case False{}:
      rec

def token_record(+email: String, +ts: String, +api_key: Bool) -> Json.Json:
  with_kind(api_key, Json.JObj{Json.JField{"email", SSeq.jstr(email), Json.JField{"uuid", SSeq.jstr(""),
    Json.JField{"organizationUuid", SSeq.jstr(""), Json.JField{"organizationName", SSeq.jstr(""), Json.JField{"added", SSeq.jstr(ts), Json.JNil{}}}}}}})

def with_alias2(+empty: Bool, +alias: String, +rec: Json.Json) -> Json.Json:
  match empty:
    case True{}:
      rec
    case False{}:
      Json.set("alias", SSeq.jstr(alias), rec)

def with_alias(+alias: String, +rec: Json.Json) -> Json.Json:
  with_alias2(String.is_empty(alias), alias, rec)

# {"claudeAiOauth": {"accessToken": T, "scopes": ["user:inference"]}}, as json.dumps writes it.
def setup_token_creds(+token: String) -> String:
  Json.emit_py(SSeq.obj1("claudeAiOauth", Json.JObj{Json.JField{"accessToken", SSeq.jstr(token),
    Json.JField{"scopes", Json.arr([SSeq.jstr("user:inference")]), Json.JNil{}}}}))

# The config backup add-token synthesizes.
def token_config(+email: String) -> String:
  Json.emit_py(SSeq.obj1("oauthAccount", Json.JObj{Json.JField{"emailAddress", SSeq.jstr(email), Json.JField{"accountUuid", SSeq.jstr(""),
    Json.JField{"organizationUuid", Json.JNull{}, Json.JField{"organizationName", Json.JNull{}, Json.JNil{}}}}}}))

def default_email(+api_key: Bool, +slot: U32) -> String:
  SBase.sel.s(api_key, "api-key", "setup-token") ++ "-" ++ U32.show(slot) ++ "@token.local"

def kind_label(+api_key: Bool) -> String:
  SBase.sel.s(api_key, "API key", "token")

def kind_name(+api_key: Bool) -> String:
  SBase.sel.s(api_key, "api_key", "oauth")

def kind_title(+api_key: Bool) -> String:
  SBase.sel.s(api_key, "API-key", "OAuth")

# `do ActM<A>:` blocks (the do-notation needs the monad's name defined here).
def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)
