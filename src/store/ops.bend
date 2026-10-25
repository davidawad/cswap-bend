import Base
import ../json.bend as Json
import ../act.bend as Act
import ../lock.bend as Lock
import ./base.bend as SBase
import ./seq.bend as SSeq
import ./plan.bend as SPlan
import ./io.bend as SIo

# `do ActM<A>:` needs the monad defined in the file that uses it.
def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

# ---- add-token ------------------------------------------------------------------------------

# The email and slot add-token ends up with. Without an email, the slot is
# fixed first so the synthesized address is unique.
type Eff is Data:
  Eff{email: String, slot: Maybe<&2, U32>}

def eff_slot(+api_key: Bool, +n: U32) -> Eff:
  Eff{SPlan.default_email(api_key, n), Some{n}}

def eff_noemail(+api_key: Bool, +slot: Maybe<&2, U32>, +seq: Json.Json) -> Eff:
  eff_slot(api_key, Maybe.default(&2, U32, slot, SSeq.next_slot(seq)))

def effective(+email0: Maybe<&2, String>, +slot0: Maybe<&2, U32>, +seq: Json.Json, +api_key: Bool) -> Eff:
  match email0:
    case Some{e}:
      Eff{e, slot0}
    case None{}:
      eff_noemail(api_key, slot0, seq)

def email_ok(+m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{e}:
      SBase.valid_email(e)

def is_none(+m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{x}:
      False{}

def clash3(+existing_api: Bool, +n: String, +email: String, +api_key: Bool) -> Maybe<&2, String>:
  match existing_api api_key:
    case True{} True{}:
      None{}
    case False{} False{}:
      None{}
    case _ _:
      Some{"'" ++ email ++ "' already exists as an " ++ SPlan.kind_title(existing_api) ++ " account (slot " ++ n ++ "); cannot add it as an "
        ++ SPlan.kind_title(api_key) ++ " account. Pass a distinct --email."}

def clash2(+slot: Maybe<&2, String>, +seq: Json.Json, +email: String, +api_key: Bool) -> Maybe<&2, String>:
  match slot:
    case None{}:
      None{}
    case Some{n}:
      clash3(SSeq.is_api_key_rec(SSeq.get_or(n, SSeq.accounts_of(seq), Json.JNull{})), n, email, api_key)

# (email, personal) already stored as the other kind.
def clash(+seq: Json.Json, +email: String, +api_key: Bool) -> Maybe<&2, String>:
  clash2(SSeq.find_slot(seq, email, ""), seq, email, api_key)

def clash_msg(+m: Maybe<&2, String>) -> String:
  SSeq.str_or(m, "")

def refresh_slot(+slot: Maybe<&2, U32>, +seq: Json.Json, +email: String) -> Maybe<&2, String>:
  match slot:
    case Some{n}:
      None{}
    case None{}:
      SSeq.find_slot(seq, email, "")

def moved_line(+m: Maybe<&2, String>, +from: String, +to: String) -> String:
  match m:
    case None{}:
      ""
    case Some{old}:
      "Moved from slot " ++ old ++ " → " ++ to ++ "\n"

def unverified_reason(+api_key: Bool) -> String:
  SBase.sel.s(api_key, "an API key has no OAuth profile to look up", "a setup-token has only the user:inference scope, so GET /api/oauth/profile answers 403")

def token_files(+root: String, +token: String, +api_key: Bool, +email: String, +num: String) -> Act.of(Unit):
  do ActM<Unit>:
    SIo.write_cred(root, num, email, SBase.sel.s(api_key, token, SPlan.setup_token_creds(token)))
    SIo.write_config(root, num, email, SPlan.token_config(email))

def token_logs(+root: String, +info: String, +api_key: Bool, +email: String, +num: String) -> Act.of(Unit):
  do ActM<Unit>:
    SIo.log(root, "INFO", info)
    SIo.log(root, "WARNING", "identity unverified for slot " ++ num ++ " (" ++ email ++ "): " ++ unverified_reason(api_key) ++ "; recorded as unverified")

def token_seq(+s2: Json.Json, +num: String, +email: String, +ts: String, +api_key: Bool) -> Json.Json:
  SSeq.stamp(SSeq.put_account(s2, num, SPlan.token_record(email, ts, api_key)), ts)

def token_place2(+root: String, +token: String, +api_key: Bool, +email: String, +ts: String, +seq: Json.Json, +num: String, +displace: Maybe<&2, String>, +migrate: Maybe<&2, String>) -> Act.of(String):
  do ActM<String>:
    s2 : Json.Json <- SIo.drop_pair(root, seq, displace, migrate, ts)
    token_files(root, token, api_key, email, num)
    SIo.write_seq(root, token_seq(s2, num, email, ts, api_key))
    token_logs(root, "Added account " ++ num ++ " from " ++ SPlan.kind_label(api_key) ++ ": " ++ email, api_key, email, num)
    return moved_line(migrate, "", num) ++ "Added Account " ++ num ++ ": " ++ email ++ " [personal] (from " ++ SPlan.kind_label(api_key) ++ ")"

def token_place(+root: String, +token: String, +api_key: Bool, +email: String, +ts: String, +seq: Json.Json, +p: SPlan.SlotPlan, +migrate_slot: String) -> Act.of(String):
  match p:
    case SPlan.SPErr{code, msg}:
      Act.fail(String, code, msg)
    case SPlan.SPOk{num, displace, migrate}:
      token_place2(root, token, api_key, email, ts, seq, num, displace, migrate)

def token_refresh(+root: String, +token: String, +api_key: Bool, +email: String, +ts: String, +seq: Json.Json, +num: String) -> Act.of(String):
  do ActM<String>:
    token_files(root, token, api_key, email, num)
    SIo.write_seq(root, SSeq.stamp(seq, ts))
    token_logs(root, "Updated " ++ SPlan.kind_label(api_key) ++ " for account " ++ num ++ ": " ++ email, api_key, email, num)
    return "Updated " ++ SPlan.kind_label(api_key) ++ " for Account " ++ num ++ " (" ++ email ++ " [personal])."

def token_branch2(+refresh: Maybe<&2, String>, +root: String, +token: String, +api_key: Bool, +email: String, +slot: Maybe<&2, U32>, +assume_yes: Bool, +ts: String, +seq: Json.Json) -> Act.of(String):
  match refresh:
    case Some{num}:
      token_refresh(root, token, api_key, email, ts, seq, num)
    case None{}:
      token_place(root, token, api_key, email, ts, seq, SPlan.plan_slot(slot, seq, email, "", assume_yes), "")

def token_branch(+root: String, +token: String, +api_key: Bool, +e: Eff, +assume_yes: Bool, +ts: String, +seq: Json.Json) -> Act.of(String):
  match e:
    case Eff{+email, +slot}:
      token_branch2(refresh_slot(slot, seq, email), root, token, api_key, email, slot, assume_yes, ts, seq)

def token_checked2(+c: Maybe<&2, String>, +e: Eff, +root: String, +token: String, +api_key: Bool, +assume_yes: Bool, +ts: String, +seq: Json.Json) -> Act.of(String):
  do ActM<String>:
    Act.guard(is_none(c), 2, clash_msg(c))
    token_branch(root, token, api_key, e, assume_yes, ts, seq)

def token_checked(+e: Eff, +root: String, +token: String, +api_key: Bool, +assume_yes: Bool, +ts: String, +seq: Json.Json) -> Act.of(String):
  match e:
    case Eff{+email, slot}:
      token_checked2(clash(seq, email, api_key), Eff{email, slot}, root, token, api_key, assume_yes, ts, seq)

def add_token4(+root: String, +token: String, +email0: Maybe<&2, String>, +slot0: Maybe<&2, U32>, +assume_yes: Bool, +ts: String, +seq: Json.Json) -> Act.of(String):
  token_checked(effective(email0, slot0, seq, SBase.looks_like_api_key(token)), root, token, SBase.looks_like_api_key(token), assume_yes, ts, seq)

def add_token3(+root: String, +token: String, +email0: Maybe<&2, String>, +slot0: Maybe<&2, U32>, +assume_yes: Bool) -> Act.of(String):
  do ActM<String>:
    SIo.setup_dirs(root)
    +ts : String <- SIo.now_iso()
    seq : Json.Json <- SIo.ensure_seq(root, ts)
    add_token4(root, token, email0, slot0, assume_yes, ts, seq)

def add_token2(+root: String, +token: String, +email0: Maybe<&2, String>, +slot0: Maybe<&2, U32>, +assume_yes: Bool) -> Act.of(String):
  do ActM<String>:
    Act.guard(SBase.nonempty(token), 2, "Token cannot be empty")
    Act.guard(email_ok(email0), 2, "Invalid email format: " ++ SSeq.str_or(email0, ""))
    Lock.with_lock(String, SBase.lock_path(root), 10000, add_token3(root, token, email0, slot0, assume_yes))

# Register a raw setup-token or `sk-ant-` API key (no HTTP call). `assume_yes`
# stands for the "Overwrite slot N?" answer; without it an occupied slot is
# Fail{(10, ...)} for the CLI to confirm and retry. The record is written with
# an empty identity and logged as unverified: a setup-token has no profile
# scope, so the oracle cannot resolve it.
def add_token(+ctx: SBase.Ctx, +token: String, +email0: Maybe<&2, String>, +slot0: Maybe<&2, U32>, +assume_yes: Bool) -> Act.of(String):
  add_token2(SBase.root_of(ctx), String.trim(token), email0, slot0, assume_yes)

# ---- remove, read ---------------------------------------------------------------------------

def is_some_str(+m: Maybe<&2, String>) -> Bool:
  Bool.not(is_none(m))

def valid_ident(+seq: Json.Json, +ident: String) -> Bool:
  SBase.all_digits(ident) || SBase.valid_email(ident) || is_some_str(SSeq.find_alias(seq, ident))

def scalar_text(+m: Maybe<&2, Json.Json>) -> String:
  match m:
    case Some{Json.JNum{t}}:
      t
    case Some{Json.JStr{s}}:
      s
    case _:
      ""

# A JSON scalar as text: numbers as written, strings as is, "" otherwise.
def field_json(+rec: Json.Json, +key: String) -> String:
  scalar_text(Json.get(key, rec))

def active_is(+seq: Json.Json, +num: String) -> Bool:
  String.eq(field_json(seq, "activeAccountNumber"), num)

def active_warning(+seq: Json.Json, +num: String, +email: String) -> String:
  SBase.sel.s(active_is(seq, num), "Warning: Account-" ++ num ++ " (" ++ email ++ ") is currently active\n", "")

def removal3(+root: String, +seq: Json.Json, +num: String, +ts: String, +email: String) -> Act.of(String):
  do ActM<String>:
    SIo.archive_slot(root, num, email, ts)
    SIo.write_seq(root, SSeq.stamp(SSeq.drop_account(seq, num), ts))
    SIo.log(root, "INFO", "Removed account " ++ num ++ ": " ++ email ++ "; credential kept under credentials/.removed/")
    return active_warning(seq, num, email) ++ "Removed Account-" ++ num ++ " (" ++ email ++ ")"

def removal2(+root: String, +seq: Json.Json, +num: String, +ts: String, +rec: Maybe<&2, Json.Json>) -> Act.of(String):
  match rec:
    case None{}:
      Act.fail(String, 3, "Account-" ++ num ++ " does not exist")
    case Some{r}:
      removal3(root, seq, num, ts, SSeq.field_str(r, "email"))

def removal(+root: String, +seq: Json.Json, +num: String, +ts: String) -> Act.of(String):
  removal2(root, seq, num, ts, SSeq.slot_record(seq, num))

def remove_resolved(+root: String, +seq: Json.Json, +ident: String, +ts: String, +r: SSeq.Resolved) -> Act.of(String):
  match r:
    case SSeq.RNone{}:
      Act.fail(String, 3, "No account found with identifier: " ++ ident)
    case SSeq.RAmb{msg}:
      Act.fail(String, 1, msg)
    case SSeq.RSlot{n}:
      removal(root, seq, n, ts)

def remove3(+root: String, +ident: String, +ts: String, +seq: Json.Json) -> Act.of(String):
  do ActM<String>:
    Act.guard(valid_ident(seq, ident), 2, "Invalid account identifier: " ++ ident)
    remove_resolved(root, seq, ident, ts, SSeq.resolve(seq, ident))

def remove4(+root: String, +ident: String, +m: Maybe<&2, Json.Json>) -> Act.of(String):
  match m:
    case None{}:
      Act.fail(String, 1, "No accounts are managed yet")
    case Some{seq}:
      do ActM<String>:
        ts : String <- SIo.now_iso()
        remove3(root, ident, SBase.compact_ts(ts), seq)

def remove2(+root: String, +ident: String) -> Act.of(String):
  do ActM<String>:
    SIo.setup_dirs(root)
    m : Maybe<&2, Json.Json> <- SIo.read_seq(root)
    remove4(root, ident, m)

# Take an account out of rotation by slot number, alias or email. Its
# credential is moved to credentials/.removed/<utc-ts>-<slot>-<email>.enc
# (0600), never deleted. The confirmation prompt belongs to the CLI. When the
# account is the active one the answer starts with the reference's warning
# line. Several accounts sharing an email are an error here (the reference
# asks interactively).
def remove(+ctx: SBase.Ctx, +ident: String) -> Act.of(String):
  do ActM<String>:
    Lock.with_lock(String, SBase.lock_path(SBase.root_of(ctx)), 10000, remove2(SBase.root_of(ctx), ident))

def read_resolved(+root: String, +r: SSeq.Resolved, +seq: Json.Json, +ident: String) -> Act.of(String):
  match r:
    case SSeq.RNone{}:
      Act.fail(String, 3, "No account found with identifier: " ++ ident)
    case SSeq.RAmb{msg}:
      Act.fail(String, 1, msg)
    case SSeq.RSlot{+n}:
      SIo.read_cred(root, n, SIo.slot_email(seq, n))

def read_slot2(+root: String, +ident: String, +m: Maybe<&2, Json.Json>) -> Act.of(String):
  match m:
    case None{}:
      Act.fail(String, 1, "No accounts are managed yet")
    case Some{seq}:
      read_resolved(root, SSeq.resolve(seq, ident), seq, ident)

# A slot's stored credential text by slot number, alias or email; "" when the
# slot has none.
def read_slot(+ctx: SBase.Ctx, +ident: String) -> Act.of(String):
  do ActM<String>:
    m : Maybe<&2, Json.Json> <- SIo.read_seq(SBase.root_of(ctx))
    read_slot2(SBase.root_of(ctx), ident, m)

def write_slot2(+root: String, +creds: String, +num: String, +m: Maybe<&2, Json.Json>) -> Act.of(Unit):
  match m:
    case None{}:
      Act.fail(Unit, 1, "No accounts are managed yet")
    case Some{seq}:
      SIo.write_cred(root, num, SIo.slot_email(seq, num), creds)

# Replace the credential of an existing slot (keeping the old one as .prev).
def write_slot(+ctx: SBase.Ctx, +num: String, +creds: String) -> Act.of(Unit):
  do ActM<Unit>:
    m : Maybe<&2, Json.Json> <- SIo.read_seq(SBase.root_of(ctx))
    write_slot2(SBase.root_of(ctx), creds, num, m)
