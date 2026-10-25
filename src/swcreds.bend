import Base
import ./json.bend as Json
import ./swbase.bend as B
import ./store/base.bend as SBase
import ./store/plan.bend as SPlan
import ./store/seq.bend as SSeq

# Switch, part 2: what a credential is and whose it is (pure).

# What the live credential is, compared with the slot it is filed under.

type CKind is Data:
  KOwnBytes{}
  KOwnFamily{}
  KWiped{}
  KForeignSynced{slot: String}
  KForeign{slot: String}
  KAlien{}
  KUnresolved{}

# Another slot's stored credential.
type Other is Data:
  Other{slot: String, creds: String}

def is_shared_key(+k: String) -> Bool:
  String.eq(k, "mcpOAuth") || String.eq(k, "mcpOAuthClientConfig") || String.eq(k, "mcpXaaIdp") || String.eq(k, "mcpXaaIdpConfig") || String.eq(k, "pluginSecrets")

def keep_field(+drop: Bool, +k: String, +v: Json.Json, +rest: Json.Json) -> Json.Json:
  match drop:
    case True{}:
      rest
    case False{}:
      Json.JField{k, v, rest}

# The fields of an object chain that are (or are not) shared across accounts.
def pick_fields(+fields: Json.Json, +shared: Bool) -> Json.Json:
  match fields:
    case Json.JField{k, v, t}:
      keep_field(Bool.not(SBase.sel.b(shared, is_shared_key(k), Bool.not(is_shared_key(k)))), k, v, pick_fields(t, shared))
    case _:
      Json.JNil{}

def append_fields(+a: Json.Json, +b: Json.Json) -> Json.Json:
  match a:
    case Json.JField{k, v, t}:
      Json.JField{k, v, append_fields(t, b)}
    case _:
      b

def has_oauth(+fields: Json.Json) -> Bool:
  match fields:
    case Json.JField{k, v, t}:
      String.eq(k, "claudeAiOauth") || has_oauth(t)
    case _:
      False{}

def merge3(+oauth: Bool, +lf: Json.Json, +tf: Json.Json, +target_text: String) -> String:
  match oauth:
    case True{}:
      Json.emit_py(Json.JObj{append_fields(pick_fields(tf, False{}), pick_fields(lf, True{}))})
    case False{}:
      target_text

def merge2(+live: Json.Json, +target: Json.Json, +target_text: String) -> String:
  match live target:
    case Json.JObj{lf} Json.JObj{tf}:
      merge3(has_oauth(tf), lf, tf, target_text)
    case _ _:
      target_text

def merge1(live: Result<&2, &2, String, Json.Json>, target: Result<&2, &2, String, Json.Json>, +target_text: String) -> String:
  match live target:
    case Done{l} Done{t}:
      merge2(l, t, target_text)
    case _ _:
      target_text

# The credential to write for `target` while `live` is replaced: Claude Code's
# account-independent fields (MCP logins, plugin secrets) ride along from the
# live one. A live API key or non-JSON leaves the target as is.
def prepare_activation(+target: String, +live: String) -> String:
  merge1(Json.parse(live), Json.parse(target), target)

def oauth_of(+creds: Json.Json) -> Json.Json:
  SSeq.get_or("claudeAiOauth", creds, Json.JNull{})

def refresh_of2(r: Result<&2, &2, String, Json.Json>) -> String:
  match r:
    case Done{j}:
      SSeq.field_str(oauth_of(j), "refreshToken")
    case Fail{e}:
      ""

def refresh_of(+text: String) -> String:
  refresh_of2(Json.parse(text))

def access_of2(r: Result<&2, &2, String, Json.Json>) -> String:
  match r:
    case Done{j}:
      SSeq.field_str(oauth_of(j), "accessToken")
    case Fail{e}:
      ""

def access_of(+text: String) -> String:
  access_of2(Json.parse(text))

def is_object(+j: Json.Json) -> Bool:
  match j:
    case Json.JObj{f}:
      True{}
    case _:
      False{}

def is_oauth_obj2(r: Result<&2, &2, String, Json.Json>) -> Bool:
  match r:
    case Done{j}:
      is_object(oauth_of(j))
    case Fail{e}:
      False{}

def is_oauth_obj(+text: String) -> Bool:
  is_oauth_obj2(Json.parse(text))

def same_lineage2(+ra: String, +rb: String, +a: String, +b: String) -> Bool:
  SBase.sel.b(SBase.nonempty(ra) || SBase.nonempty(rb), String.eq(ra, rb), String.eq(a, b))

# The credential fingerprint rule: the refresh token when there is one, else
# the whole text. Equal fingerprints are equal tokens, so compare the tokens.
def same_lineage(+a: String, +b: String) -> Bool:
  same_lineage2(refresh_of(a), refresh_of(b), a, b)

# Claude Code empties both tokens in place when a refresh is rejected.
def wiped(+text: String) -> Bool:
  is_oauth_obj(text) && String.is_empty(access_of(text)) && String.is_empty(refresh_of(text))

def foreign_slot(+live: String, +others: List<&2, Other>) -> Maybe<&2, String>:
  match others:
    case Nil{}:
      None{}
    case Con{Other{s, c}, t}:
      SSeq.pick_slot(SBase.nonempty(c) && same_lineage(live, c), s, foreign_slot(live, t))

def classify3(+foreign: Maybe<&2, String>) -> CKind:
  match foreign:
    case Some{s}:
      KForeignSynced{s}
    case None{}:
      KUnresolved{}

def classify2b(+is_wiped: Bool, +foreign: Maybe<&2, String>) -> CKind:
  match is_wiped:
    case True{}:
      KWiped{}
    case False{}:
      classify3(foreign)

def classify2(+backup_nonempty: Bool, +eq: Bool, +family: Bool, +is_wiped: Bool, +foreign: Maybe<&2, String>) -> CKind:
  match backup_nonempty eq family:
    case True{} True{} _:
      KOwnBytes{}
    case True{} False{} True{}:
      KOwnFamily{}
    case _ _ _:
      classify2b(is_wiped, foreign)

# `_classify_outgoing_credential` without the profile oracle: byte equality,
# refresh-token lineage, wiped tokens, another slot already holding this
# lineage, else unresolved.
def classify(+live: String, +backup: String, +others: List<&2, Other>) -> CKind:
  classify2(SBase.nonempty(backup), String.eq(backup, live), same_lineage(backup, live), wiped(live), foreign_slot(live, others))

def kind_warning(+k: CKind, +cur: String) -> List<&2, String>:
  match k:
    case KWiped{}:
      ["The live credential's tokens were wiped (Claude Code clears them when a refresh is rejected). Account-" ++ cur ++ "'s stored backup was kept. If the account cannot authenticate after switching back, log in with Claude Code and run: cswap add"]
    case KForeignSynced{s}:
      ["Credential ownership mismatch detected. The live credential already matches Account-" ++ s ++ "'s stored backup, so nothing was written into Account-" ++ cur ++ "."]
    case KForeign{s}:
      ["Credential ownership mismatch detected. The live credential was preserved and was not written into Account-" ++ cur ++ ". If Account-" ++ s ++ " later cannot authenticate, log in as it and run: cswap add --slot " ++ s]
    case KAlien{}:
      ["The live login does not match a managed account. It was preserved and not written into Account-" ++ cur ++ ". If you need that account, log in as it and run: cswap add"]
    case _:
      []

def org_compatible(+r_org: String, +own_org: String) -> Bool:
  String.is_empty(r_org) || String.is_empty(own_org) || String.eq(r_org, own_org)

def sel_ck(+c: Bool, +x: CKind, +y: CKind) -> CKind:
  match c:
    case True{}:
      x
    case False{}:
      y

def foreign_or_synced(+n: String, +live: String, +others: List<&2, Other>) -> CKind:
  sel_ck(String.eq(SSeq.str_or(foreign_slot(live, others), ""), n), KForeignSynced{n}, KForeign{n})

def stored_uuid(+seq: Json.Json, +slot: String) -> String:
  SSeq.field_str(SSeq.get_or(slot, SSeq.accounts_of(seq), Json.JNull{}), "uuid")

def resolved_kind4(+is_cur: Bool, +n: String, +seq: Json.Json, +live: String, +others: List<&2, Other>, +uuid: String) -> CKind:
  match is_cur:
    case True{}:
      KOwnFamily{}
    case False{}:
      sel_ck(SBase.nonempty(uuid) && String.eq(String.trim(stored_uuid(seq, n)), uuid), foreign_or_synced(n, live, others), KAlien{})

def resolved_kind3(+own: Bool, +slot: Maybe<&2, String>, +seq: Json.Json, +cur: String, +live: String, +others: List<&2, Other>, +uuid: String, +email: String, +has_org: Bool) -> CKind:
  match own slot:
    case True{} _:
      KOwnFamily{}
    case False{} None{}:
      sel_ck(SBase.nonempty(email) && has_org, KAlien{}, KUnresolved{})
    case False{} Some{n}:
      resolved_kind4(String.eq(n, cur), n, seq, live, others, uuid)

# An email match whose stored uuid disagrees is not a match.
def drop_mismatch(+m: Maybe<&2, String>, +seq: Json.Json, +uuid: String) -> Maybe<&2, String>:
  match m:
    case Some{n}:
      B.sel_ms(SBase.nonempty(uuid) && SBase.nonempty(stored_uuid(seq, n)) && Bool.not(String.eq(stored_uuid(seq, n), uuid)), None{}, Some{n})
    case None{}:
      None{}

# The slot holding (uuid, org), if any.
def uuid_in(+fields: Json.Json, +uuid: String, +org: String) -> Maybe<&2, String>:
  match fields:
    case Json.JField{k, v, t}:
      SSeq.pick_slot(SBase.nonempty(SSeq.field_str(v, "uuid")) && String.eq(SSeq.field_str(v, "uuid"), uuid) && String.eq(SSeq.field_str(v, "organizationUuid"), org), k, uuid_in(t, uuid, org))
    case _:
      None{}

def resolved_slot3(+m: Maybe<&2, String>, +seq: Json.Json, +uuid: String, +org: String) -> Maybe<&2, String>:
  match m:
    case Some{n}:
      Some{n}
    case None{}:
      B.sel_ms(SBase.nonempty(uuid), uuid_in(SSeq.fields_of(seq), uuid, org), None{})

def resolved_slot2(+by_email: Maybe<&2, String>, +seq: Json.Json, +uuid: String, +org: String) -> Maybe<&2, String>:
  resolved_slot3(drop_mismatch(by_email, seq, uuid), seq, uuid, org)

def resolved_slot(+seq: Json.Json, +email: String, +org: String, +uuid: String) -> Maybe<&2, String>:
  resolved_slot2(B.sel_ms(SBase.nonempty(email), SSeq.find_slot(seq, email, org), None{}), seq, uuid, org)

def stored_org(+seq: Json.Json, +slot: String) -> String:
  SSeq.field_str(SSeq.get_or(slot, SSeq.accounts_of(seq), Json.JNull{}), "organizationUuid")

def resolved_kind2(+seq: Json.Json, +cur: String, +live: String, +others: List<&2, Other>, +uuid: String, +email: String, +org: String, +has_org: Bool) -> CKind:
  resolved_kind3(SBase.nonempty(uuid) && String.eq(uuid, String.trim(stored_uuid(seq, cur))) && org_compatible(org, stored_org(seq, cur)),
    resolved_slot(seq, email, org, uuid), seq, cur, live, others, uuid, email, has_org)

def resolved_kind(+seq: Json.Json, +cur: String, +live: String, +others: List<&2, Other>, +p: SPlan.Prof) -> CKind:
  match p:
    case SPlan.ProfNone{}:
      KUnresolved{}
    case SPlan.Prof{uuid, email, org}:
      resolved_kind2(seq, cur, live, others, String.trim(uuid), SSeq.str_or(email, ""), SSeq.str_or(org, ""), B.is_some_str(org))

def final_kind(+base: CKind, +seq: Json.Json, +cur: String, +live: String, +others: List<&2, Other>, +p: SPlan.Prof) -> CKind:
  match base:
    case KUnresolved{}:
      resolved_kind(seq, cur, live, others, p)
    case _:
      base

# Alien and foreign live credentials are kept aside, never written into a slot.
def preserve(+k: CKind) -> Bool:
  match k:
    case KAlien{}:
      True{}
    case KForeign{s}:
      True{}
    case _:
      False{}
