import Base
import ./json.bend as Json
import ./fs.bend as Fs
import ./act.bend as Act
import ./lock.bend as Lock
import ./clock.bend as Clock
import ./http.bend as Http
import ./store/base.bend as SBase
import ./store/seq.bend as SSeq
import ./store/plan.bend as SPlan
import ./store/io.bend as SIo
import ./store/ops.bend as SOps

# `do ActM<A>:` needs the monad defined in the file that uses it.
def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

# The account store: ~/.claude-swap-backup (sequence.json, credentials/,
# configs/), laid out exactly as the Python cswap writes it so both can share
# one backup root. See parity/contract.md section 1.

# ---- add (adopt the live login) -------------------------------------------------------

def profile_url() -> String:
  "https://api.anthropic.com/api/oauth/profile"

def prof_if_ok(+ok: Bool, +body: String) -> SPlan.Prof:
  match ok:
    case True{}:
      SPlan.profile_of_text(body)
    case False{}:
      SPlan.ProfNone{}

def prof_of_reply(r: Result<&2, &2, String, Http.Reply>) -> SPlan.Prof:
  match r:
    case Fail{e}:
      SPlan.ProfNone{}
    case Done{Http.Reply{status, head, body}}:
      prof_if_ok(U32.is_eq(status, 200), body)

# GET /api/oauth/profile through Http.request (curl, the token on stdin, and the
# CSWAP_TEST_HTTP_BASE seam). Any failure is ProfNone: "unresolvable", never
# "wrong".
def profile_http(+token: String) -> IO(SPlan.Prof):
  IO.bind(Result<&2, &2, String, Http.Reply>, SPlan.Prof,
    Http.request("GET", profile_url(), [("Authorization", "Bearer " ++ token), ("Content-Type", "application/json"), ("User-Agent", "claude-swap/1.0")], "", 5),
    r => IO.pure(SPlan.Prof, prof_of_reply(r)))

def alias_char(+c: Char) -> Bool:
  Char.is_lower(c) || Char.is_digit(c) || Char.is_eq(c, '-') || Char.is_eq(c, '_') || Char.is_eq(c, '.')

def alias_chars(+s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      alias_char(c) && alias_chars(t)

def alias_err2(+a: String, +name: String) -> String:
  SBase.sel.s(String.is_empty(a), "alias cannot be empty",
  SBase.sel.s(SBase.all_digits(a), "alias '" ++ name ++ "' cannot be purely numeric (reserved for slot numbers)",
  SBase.sel.s(String.starts_with(a, "-"), "alias '" ++ name ++ "' cannot start with '-' (would be read as a command flag)",
  SBase.sel.s(alias_chars(a), "", "alias '" ++ name ++ "' may only contain letters, digits, '-', '_', and '.'"))))

# models.normalize_alias: the message for a bad alias, "" for a good one.
def alias_err(+name: String) -> String:
  alias_err2(String.to_lower(String.trim(name)), name)

def alias_norm(+name: String) -> String:
  String.to_lower(String.trim(name))

# The alias, normalized; "" when none was asked for.
def alias_of(+m: Maybe<&2, String>) -> String:
  alias_norm(SSeq.str_or(m, ""))

def alias_check(+m: Maybe<&2, String>) -> Act.of(Unit):
  match m:
    case None{}:
      Act.pure(Unit, Unit{})
    case Some{name}:
      Act.guard(String.is_empty(alias_err(name)), 2, alias_err(name))

# Who the live ~/.claude.json says is logged in.
type Ident is Data:
  Ident{email: String, org: String, uuid: String, org_name: String}

def ident_of2(+oa: Json.Json) -> Ident:
  Ident{SSeq.field_str(oa, "emailAddress"), SSeq.field_str(oa, "organizationUuid"), SSeq.field_str(oa, "accountUuid"), SSeq.field_str(oa, "organizationName")}

def ident_of(+cfg: Json.Json) -> Ident:
  ident_of2(SSeq.get_or("oauthAccount", cfg, Json.JNull{}))

def notice_text(+email: String, +why: String) -> String:
  "Notice: could not verify that the stored credential belongs to " ++ email ++ " (" ++ why
    ++ "). Registering anyway; re-run where the check can complete to confirm.\n"

# Fail on an owner mismatch; a notice when it could not be checked.
def verdict_act(+v: SPlan.Verdict, +email: String) -> Act.of(String):
  match v:
    case SPlan.VOk{}:
      Act.pure(String, "")
    case SPlan.VUnverified{why}:
      Act.pure(String, notice_text(email, why))
    case SPlan.VBad{msg}:
      Act.fail(String, 1, msg)

def id_email(+id: Ident) -> String:
  match id:
    case Ident{e, o, u, n}:
      e

def id_org(+id: Ident) -> String:
  match id:
    case Ident{e, o, u, n}:
      o

def id_uuid(+id: Ident) -> String:
  match id:
    case Ident{e, o, u, n}:
      u

def verify_prof(+id: Ident, +prof: SPlan.Prof) -> Act.of(String):
  verdict_act(SPlan.judge(id_email(id), id_org(id), id_uuid(id), prof), id_email(id))

def verify_plan(+p: SPlan.Plan, +id: Ident, fetch: String -> IO(SPlan.Prof)) -> Act.of(String):
  match p:
    case SPlan.PSkip{why}:
      Act.pure(String, notice_text(id_email(id), why))
    case SPlan.PFetch{token}:
      do ActM<String>:
        prof : SPlan.Prof <- Act.lift(SPlan.Prof, fetch(token))
        verify_prof(id, prof)

def id_org_name(+id: Ident) -> String:
  match id:
    case Ident{e, o, u, n}:
      n

# The credential of the live login: .credentials.json, else primaryApiKey.
def capture2(+ex: Bool, +path: String, +cfg: Json.Json) -> Act.of(String):
  match ex:
    case True{}:
      Fs.read_file(path)
    case False{}:
      Act.pure(String, SSeq.field_str(cfg, "primaryApiKey"))

def capture(+ctx: SBase.Ctx, +cfg: Json.Json) -> Act.of(String):
  do ActM<String>:
    ex : Bool <- Act.lift(Bool, Fs.exists(SBase.live_creds_path(ctx)))
    capture2(ex, SBase.live_creds_path(ctx), cfg)

def api_key_msg() -> String:
  "Active login is an API-key account. Add it with 'cswap add-token sk-ant-...' instead of 'cswap add'."

def alias_taken2(+m: Maybe<&2, String>, +exclude: String) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{n}:
      SPlan.differs(Some{n}, exclude)

def alias_taken(+seq: Json.Json, +alias: String, +exclude: String) -> Maybe<&2, String>:
  alias_taken2(SSeq.find_alias(seq, alias), exclude)

def alias_conflict2(+none_asked: Bool, +taken: Maybe<&2, String>, +alias: String) -> Act.of(Unit):
  match none_asked taken:
    case True{} _:
      Act.pure(Unit, Unit{})
    case False{} None{}:
      Act.pure(Unit, Unit{})
    case False{} Some{n}:
      Act.fail(Unit, 2, "Alias '" ++ alias ++ "' is already used by account " ++ n)

def alias_conflict(+seq: Json.Json, +alias: String, +exclude: String) -> Act.of(Unit):
  alias_conflict2(String.is_empty(alias), alias_taken(seq, alias, exclude), alias)

def same_alias(+m: Maybe<&2, Json.Json>, +id: Ident) -> String:
  match m:
    case None{}:
      ""
    case Some{r}:
      SBase.sel.s(SSeq.rec_is(r, id_email(id), id_org(id)), SSeq.field_str(r, "alias"), "")

def existing_alias2(+migrate: Maybe<&2, String>, +seq: Json.Json, +num: String, +id: Ident) -> String:
  match migrate:
    case Some{old}:
      SSeq.field_str(SSeq.get_or(old, SSeq.accounts_of(seq), Json.JNull{}), "alias")
    case None{}:
      same_alias(SSeq.slot_record(seq, num), id)

def existing_alias(+seq: Json.Json, +num: String, +migrate: Maybe<&2, String>, +id: Ident) -> String:
  existing_alias2(migrate, seq, num, id)

def carried_alias(+alias: String, +seq: Json.Json, +num: String, +migrate: Maybe<&2, String>, +id: Ident) -> String:
  SBase.sel.s(String.is_empty(alias), existing_alias(seq, num, migrate, id), alias)

def sel.j(+c: Bool, +x: Json.Json, +y: Json.Json) -> Json.Json:
  match c:
    case True{}:
      x
    case False{}:
      y

def refresh_files(+root: String, +id: Ident, +creds: String, +cfg_text: String, +num: String) -> Act.of(Unit):
  do ActM<Unit>:
    SIo.write_cred(root, num, id_email(id), creds)
    SIo.write_config(root, num, id_email(id), cfg_text)

def refresh_alias_seq(+seq: Json.Json, +alias: String, +num: String) -> Json.Json:
  sel.j(String.is_empty(alias), seq, Json.set("accounts", Json.set(num, Json.set("alias", SSeq.jstr(alias), SSeq.get_or(num, SSeq.accounts_of(seq), Json.JObj{Json.JNil{}})), SSeq.accounts_of(seq)), seq))

def commit_active(+root: String, +seq: Json.Json, +num: String, +ts: String) -> Act.of(Unit):
  SIo.write_seq(root, SSeq.stamp(SSeq.set_active(seq, SSeq.str_u32(num)), ts))

def refresh_msg(+id: Ident, +seq: Json.Json, +num: String) -> String:
  "Updated credentials for Account " ++ num ++ " (" ++ id_email(id) ++ " [" ++ SSeq.org_tag(SSeq.get_or(num, SSeq.accounts_of(seq), Json.JNull{})) ++ "])."

def current_refresh(+root: String, +id: Ident, +creds: String, +cfg_text: String, +alias: String, +ts: String, +seq: Json.Json, +num: String) -> Act.of(String):
  do ActM<String>:
    alias_conflict(seq, alias, num)
    refresh_files(root, id, creds, cfg_text, num)
    commit_active(root, refresh_alias_seq(seq, alias, num), num, ts)
    SIo.log(root, "INFO", "Updated credentials for account " ++ num ++ ": " ++ id_email(id))
    return refresh_msg(id, seq, num)

def account_record(+email: String, +uuid: String, +org: String, +org_name: String, +ts: String, +alias: String) -> Json.Json:
  SPlan.with_alias(alias, Json.JObj{Json.JField{"email", SSeq.jstr(email), Json.JField{"uuid", SSeq.jstr(uuid),
    Json.JField{"organizationUuid", SSeq.jstr(org), Json.JField{"organizationName", SSeq.jstr(org_name), Json.JField{"added", SSeq.jstr(ts), Json.JNil{}}}}}}})

def place_seq(+s2: Json.Json, +id: Ident, +num: String, +ts: String, +alias: String, +seq: Json.Json, +migrate: Maybe<&2, String>) -> Json.Json:
  SSeq.put_account(s2, num, account_record(id_email(id), id_uuid(id), id_org(id), id_org_name(id), ts, carried_alias(alias, seq, num, migrate, id)))

def place_log(+root: String, +id: Ident, +num: String) -> Act.of(Unit):
  SIo.log(root, "INFO", "Added account " ++ num ++ ": " ++ id_email(id) ++ " (org: " ++ SBase.sel.s(String.is_empty(id_org(id)), "personal", id_org(id)) ++ ")")

def place_msg(+id: Ident, +migrate: Maybe<&2, String>, +num: String) -> String:
  SOps.moved_line(migrate, "", num) ++ "Added Account " ++ num ++ ": " ++ id_email(id) ++ " [" ++ SBase.sel.s(String.is_empty(id_org_name(id)), "personal", id_org_name(id)) ++ "]"

def current_place2(+root: String, +id: Ident, +creds: String, +cfg_text: String, +alias: String, +ts: String, +seq: Json.Json, +num: String, +displace: Maybe<&2, String>, +migrate: Maybe<&2, String>) -> Act.of(String):
  do ActM<String>:
    alias_conflict(seq, alias, num)
    s2 : Json.Json <- SIo.drop_pair(root, seq, displace, migrate, ts)
    refresh_files(root, id, creds, cfg_text, num)
    commit_active(root, place_seq(s2, id, num, ts, alias, seq, migrate), num, ts)
    place_log(root, id, num)
    return place_msg(id, migrate, num)

def current_place(+root: String, +id: Ident, +creds: String, +cfg_text: String, +alias: String, +ts: String, +seq: Json.Json, +p: SPlan.SlotPlan) -> Act.of(String):
  match p:
    case SPlan.SPErr{code, msg}:
      Act.fail(String, code, msg)
    case SPlan.SPOk{num, displace, migrate}:
      current_place2(root, id, creds, cfg_text, alias, ts, seq, num, displace, migrate)

def current_branch2(+refresh: Maybe<&2, String>, +root: String, +id: Ident, +creds: String, +cfg_text: String, +alias: String, +slot0: Maybe<&2, U32>, +assume_yes: Bool, +ts: String, +seq: Json.Json) -> Act.of(String):
  match refresh:
    case Some{num}:
      current_refresh(root, id, creds, cfg_text, alias, ts, seq, num)
    case None{}:
      current_place(root, id, creds, cfg_text, alias, ts, seq, SPlan.plan_slot(slot0, seq, id_email(id), id_org(id), assume_yes))

def refresh_for(+slot0: Maybe<&2, U32>, +seq: Json.Json, +id: Ident) -> Maybe<&2, String>:
  match slot0:
    case Some{n}:
      None{}
    case None{}:
      SSeq.find_slot(seq, id_email(id), id_org(id))

def current_branch(+root: String, +id: Ident, +creds: String, +cfg_text: String, +alias: String, +slot0: Maybe<&2, U32>, +assume_yes: Bool, +ts: String, +seq: Json.Json) -> Act.of(String):
  current_branch2(refresh_for(slot0, seq, id), root, id, creds, cfg_text, alias, slot0, assume_yes, ts, seq)

def creds_checked(+ctx: SBase.Ctx, +cfg: Json.Json) -> Act.of(String):
  do ActM<String>:
    +creds : String <- capture(ctx, cfg)
    Act.guard(SBase.nonempty(creds), 3, "No credentials found for current account")
    Act.guard(SBase.not_(SBase.looks_like_api_key(creds)), 2, api_key_msg())
    return creds

def notice_for(+creds: String, +cfg: Json.Json, fetch: String -> IO(SPlan.Prof)) -> Act.of(String):
  do ActM<String>:
    now : U32 <- Act.lift(U32, Clock.now_s())
    verify_plan(SPlan.plan_for(creds, now), ident_of(cfg), fetch)

def current4(+root: String, +ctx: SBase.Ctx, +alias: String, +slot0: Maybe<&2, U32>, +assume_yes: Bool, +ts: String, +seq: Json.Json, +cfg_text: String, +cfg: Json.Json, fetch: String -> IO(SPlan.Prof)) -> Act.of(String):
  do ActM<String>:
    +creds : String <- creds_checked(ctx, cfg)
    notice : String <- notice_for(creds, cfg, fetch)
    msg : String <- current_branch(root, ident_of(cfg), creds, cfg_text, alias, slot0, assume_yes, ts, seq)
    return notice ++ msg

def no_login() -> String:
  "No active Claude account found. Please log in first."

def current3c(+none: Bool, +root: String, +ctx: SBase.Ctx, +alias: String, +slot0: Maybe<&2, U32>, +assume_yes: Bool, +ts: String, +seq: Json.Json, +cfg_text: String, +cfg: Json.Json, fetch: String -> IO(SPlan.Prof)) -> Act.of(String):
  match none:
    case True{}:
      Act.fail(String, 1, no_login())
    case False{}:
      current4(root, ctx, alias, slot0, assume_yes, ts, seq, cfg_text, cfg, fetch)

def current3b(+root: String, +ctx: SBase.Ctx, +alias: String, +slot0: Maybe<&2, U32>, +assume_yes: Bool, +ts: String, +seq: Json.Json, +cfg_text: String, parsed: Result<&2, &2, String, Json.Json>, fetch: String -> IO(SPlan.Prof)) -> Act.of(String):
  match parsed:
    case Fail{e}:
      Act.fail(String, 1, no_login())
    case Done{+cfg}:
      current3c(String.is_empty(id_email(ident_of(cfg))), root, ctx, alias, slot0, assume_yes, ts, seq, cfg_text, cfg, fetch)

def read_config_text2(r: Fs.Res(String)) -> Act.of(String):
  match r:
    case Fail{e}:
      Act.fail(String, 1, no_login())
    case Done{t}:
      Act.pure(String, t)

def read_config_text(+ctx: SBase.Ctx) -> Act.of(String):
  IO.bind(Fs.Res(String), Fs.Res(String), Fs.read_file(SBase.global_config_path(ctx)), r => read_config_text2(r))

def current3(+root: String, +ctx: SBase.Ctx, +alias: String, +slot0: Maybe<&2, U32>, +assume_yes: Bool, fetch: String -> IO(SPlan.Prof)) -> Act.of(String):
  do ActM<String>:
    SIo.setup_dirs(root)
    +ts : String <- SIo.now_iso()
    seq : Json.Json <- SIo.ensure_seq(root, ts)
    +cfg_text : String <- read_config_text(ctx)
    current3b(root, ctx, alias, slot0, assume_yes, ts, seq, cfg_text, Json.parse(cfg_text), fetch)

# Adopt the live login (~/.claude.json oauthAccount + .credentials.json) into a
# slot. The credential's owner is looked up with `fetch` (profile_http in
# production, a stub in tests); an owner that disagrees with the config's
# (email, organization) is refused with the reference's wording and nothing is
# written. An unresolvable owner registers with a Notice line, as the
# reference does. An occupied slot needs `assume_yes` (see add_token).
def add_current(+ctx: SBase.Ctx, +alias: Maybe<&2, String>, +slot0: Maybe<&2, U32>, +assume_yes: Bool, fetch: String -> IO(SPlan.Prof)) -> Act.of(String):
  do ActM<String>:
    alias_check(alias)
    Lock.with_lock(String, SBase.lock_path(SBase.root_of(ctx)), 10000, current3(SBase.root_of(ctx), ctx, alias_of(alias), slot0, assume_yes, fetch))

# ---- from the environment ------------------------------------------------------------------

def env_or(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{s}:
      s

def ctx_with(+home: String, r: Result<&1, &1, U32 & String, String>) -> IO(SBase.Ctx):
  IO.pure(SBase.Ctx, SBase.ctx_of(home, env_or(r)))

# Ctx from $HOME and $CLAUDE_CONFIG_DIR.
def ctx_env() -> IO(SBase.Ctx):
  IO.bind(String, SBase.Ctx, IO.try(String, IO.get_env("HOME")),
    h => IO.bind(Result<&1, &1, U32 & String, String>, SBase.Ctx, IO.get_env("CLAUDE_CONFIG_DIR"), r => ctx_with(h, r)))
