import Base
import ./json.bend as Json
import ./fs.bend as Fs
import ./act.bend as Act
import ./store.bend as Store
import ./lock.bend as Lock
import ./dirlock.bend as Dirlock
import ./b64.bend as B64
import ./swbase.bend as B
import ./swcreds.bend as C
import ./fs/write.bend as FsW
import ./store/base.bend as SBase
import ./store/io.bend as SIo
import ./store/plan.bend as SPlan
import ./store/seq.bend as SSeq
import ./tokensrc.bend as Tokensrc

# Switch, part 4: the live login on disk, the locks, the ownership lookup.

# `do ActM<A>:` (see store.bend).

type Oracle is Data:
  OHttp{}
  OFile{path: String}
  ONone{}

type Opts is Data:
  Opts{delay_ms: U32, oracle: Oracle}

# ~/.claude.json and .credentials.json as they are right now.
type Live is Data:
  Live{cfg_text: Maybe<&2, String>, cfg: Maybe<&2, Json.Json>, creds_text: Maybe<&2, String>}

# The live credential as read before the locks, and what the oracle said of it.
type Pre is Data:
  Pre{live: String, prof: SPlan.Prof}

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def opts_delay(+o: Opts) -> U32:
  match o:
    case Opts{d, r}:
      d

def opts_oracle(+o: Opts) -> Oracle:
  match o:
    case Opts{d, r}:
      r

def file_prof(r: Fs.Res(String)) -> SPlan.Prof:
  match r:
    case Fail{e}:
      SPlan.ProfNone{}
    case Done{t}:
      SPlan.profile_of_text(t)

# Ask the oracle whose token this is. OHttp is GET /api/oauth/profile; OFile
# answers from a JSON file (tests); ONone never resolves.
def run_oracle(+o: Oracle, +token: String) -> IO(SPlan.Prof):
  match o:
    case OHttp{}:
      Store.profile_http(token)
    case OFile{path}:
      IO.bind(Fs.Res(String), SPlan.Prof, Fs.read_file(path), r => IO.pure(SPlan.Prof, file_prof(r)))
    case ONone{}:
      IO.pure(SPlan.Prof, SPlan.ProfNone{})

def read_text_opt2(+ex: Bool, +path: String) -> Act.of(Maybe<&2, String>):
  match ex:
    case False{}:
      Act.pure(Maybe<&2, String>, None{})
    case True{}:
      do ActM<Maybe<&2, String>>:
        t : String <- Fs.read_file(path)
        return Some{t}

# The file's text, None when it does not exist.
def read_text_opt(+path: String) -> Act.of(Maybe<&2, String>):
  do ActM<Maybe<&2, String>>:
    ex : Bool <- Act.lift(Bool, Fs.exists(path))
    read_text_opt2(ex, path)

def parse_text2(r: Result<&2, &2, String, Json.Json>) -> Maybe<&2, Json.Json>:
  match r:
    case Done{j}:
      Some{j}
    case Fail{e}:
      None{}

def parse_text(+m: Maybe<&2, String>) -> Maybe<&2, Json.Json>:
  match m:
    case None{}:
      None{}
    case Some{t}:
      parse_text2(Json.parse(t))

# The user-config active pick (tokensrc) replaces the identity ~/.claude.json
# names, which a running session rewrites. Without a pick nothing changes.
def overlay_cfg(+m: Maybe<&2, Json.Json>, +pick: Json.Json) -> Maybe<&2, Json.Json>:
  match m:
    case None{}:
      None{}
    case Some{c}:
      Some{Tokensrc.overlay(c, pick)}

def read_live(+ctx: SBase.Ctx) -> Act.of(Live):
  do ActM<Live>:
    +cfg_text : Maybe<&2, String> <- read_text_opt(SBase.global_config_path(ctx))
    creds_text : Maybe<&2, String> <- read_text_opt(SBase.live_creds_path(ctx))
    pick : Json.Json <- Act.lift(Json.Json, Tokensrc.read_pick())
    return Live{cfg_text, overlay_cfg(parse_text(cfg_text), pick), creds_text}

def lv_cfg(+l: Live) -> Json.Json:
  match l:
    case Live{t, +c, k}:
      Store.sel.j(B.is_some_json(c), B.unwrap_json(c), Json.JNull{})

def lv_cfg_text(+l: Live) -> Maybe<&2, String>:
  match l:
    case Live{t, c, k}:
      t

def lv_cfg_ok(+l: Live) -> Bool:
  match l:
    case Live{t, c, k}:
      B.is_some_json(c)

def lv_creds_text(+l: Live) -> Maybe<&2, String>:
  match l:
    case Live{t, c, k}:
      k

# The live credential: the file, else a managed key in the config.
def lv_creds(+l: Live) -> String:
  SBase.sel.s(B.is_some_str(lv_creds_text(l)), B.text_or(lv_creds_text(l)), SSeq.field_str(lv_cfg(l), "primaryApiKey"))

# (email, organizationUuid) the config names; "" email means logged out.
def lv_email(+l: Live) -> String:
  Store.id_email(Store.ident_of(lv_cfg(l)))

def lv_org(+l: Live) -> String:
  Store.id_org(Store.ident_of(lv_cfg(l)))

def lv_slot2(+has: Bool, +l: Live, +seq: Json.Json) -> Maybe<&2, String>:
  match has:
    case True{}:
      SSeq.find_slot(seq, lv_email(l), lv_org(l))
    case False{}:
      None{}

# The slot the live login belongs to, if it is managed.
def lv_slot(+l: Live, +seq: Json.Json) -> Maybe<&2, String>:
  lv_slot2(SBase.nonempty(lv_email(l)), l, seq)

def sel_o(+c: Bool, +x: List<&2, C.Other>, +y: List<&2, C.Other>) -> List<&2, C.Other>:
  match c:
    case True{}:
      x
    case False{}:
      y

def other_creds(+root: String, +seq: Json.Json, +slots: List<&2, String>, +current: String) -> Act.of(List<&2, C.Other>):
  match slots:
    case Nil{}:
      Act.pure(List<&2, C.Other>, [])
    case Con{s, t}:
      do ActM<List<&2, C.Other>>:
        c : String <- SIo.read_cred(root, s, SIo.slot_email(seq, s))
        +rest : List<&2, C.Other> <- other_creds(root, seq, t, current)
        return sel_o(String.eq(s, current), rest, C.Other{s, c} <> rest)

def archive_live(+root: String, +email: String, +creds: String, +ts: String) -> Act.of(Unit):
  do ActM<Unit>:
    SIo.secure_dir(SBase.removed_dir(root))
    SIo.write_secret(SBase.removed_dir(root) ++ "/" ++ ts ++ "-live-" ++ SBase.sel.s(String.is_empty(email), "unknown", email) ++ ".enc", B64.encode(creds))
    SIo.log(root, "WARNING", "Archived the live login (" ++ SBase.sel.s(String.is_empty(email), "unknown", email) ++ ") to credentials/.removed/" ++ ts ++ "-live-...enc before replacing it; credentials are moved aside, never deleted")

def archive_if(+needed: Bool, +root: String, +email: String, +creds: String, +ts: String) -> Act.of(Unit):
  Act.cond(Unit, needed, archive_live(root, email, creds, ts), Act.pure(Unit, Unit{}))

def write_live_creds2(+api_key: Bool, +ctx: SBase.Ctx, +creds: String) -> Act.of(Unit):
  match api_key:
    case True{}:
      FsW.remove(SBase.live_creds_path(ctx))
    case False{}:
      do ActM<Unit>:
        FsW.mkdir_p(Fs.dirname(SBase.live_creds_path(ctx)))
        SIo.write_secret(SBase.live_creds_path(ctx), creds)

# A setup-token (no refreshToken) must never land in a login store Claude Code
# reads: every running session would pick it up and lose its real login. It
# reaches a session only through CLAUDE_CODE_OAUTH_TOKEN at launch.
def is_setup_token(+creds: String) -> Bool:
  SBase.nonempty(creds) && Bool.not(SBase.looks_like_api_key(creds)) && String.is_empty(SSeq.field_str(SSeq.get_or("claudeAiOauth", Json.unwrap(Json.parse(creds)), Json.JNull{}), "refreshToken"))

# Put the target's credential live. An API key leaves no .credentials.json.
def write_live_creds(+ctx: SBase.Ctx, +creds: String) -> Act.of(Unit):
  Act.cond(Unit, is_setup_token(creds), Act.pure(Unit, Unit{}), write_live_creds2(SBase.looks_like_api_key(creds), ctx, creds))

def write_cfg(+ctx: SBase.Ctx, +j: Json.Json) -> Act.of(Unit):
  SIo.write_secret(SBase.global_config_path(ctx), Json.emit_pretty(j))

def restore_text(+path: String, +m: Maybe<&2, String>) -> Act.of(Unit):
  match m:
    case Some{t}:
      SIo.write_secret(path, t)
    case None{}:
      FsW.remove(path)

# Undo a half-done switch: the three files go back to their old text.
def restore(+ctx: SBase.Ctx, +root: String, +creds: Maybe<&2, String>, +cfg: Maybe<&2, String>, +seq_text: String) -> Act.of(Unit):
  do ActM<Unit>:
    restore_text(SBase.live_creds_path(ctx), creds)
    restore_text(SBase.global_config_path(ctx), cfg)
    SIo.write_secret(SBase.seq_path(root), seq_text)

def wrap_failure(r: Fs.Res(Unit)) -> Fs.Res(Unit):
  match r:
    case Done{u}:
      Done{u}
    case Fail{(code, msg)}:
      Fail{(code, "Switch failed and was rolled back: " ++ msg)}

def config_home_of(+ctx: SBase.Ctx) -> String:
  match ctx:
    case SBase.Ctx{h, c, g}:
      c

# Claude Code's lock directories and cswap's own flock, in the reference's
# order: .lock, then the credentials pair, then the config lock.
def with_locks(-A: Type, +ctx: SBase.Ctx, act: Act.of(A)) -> Act.of(A):
  Lock.with_lock(A, SBase.lock_path(SBase.root_of(ctx)), 10000,
    Dirlock.with_dirlock(A, config_home_of(ctx) ++ "/.oauth_refresh.lock", 9000, 60,
      Dirlock.with_dirlock(A, config_home_of(ctx) ++ ".lock", 9000, 60,
        Dirlock.with_dirlock(A, SBase.global_config_path(ctx) ++ ".lock", 9000, 10, act))))

def sel_prof(+c: Bool, +x: SPlan.Prof, +y: SPlan.Prof) -> SPlan.Prof:
  match c:
    case True{}:
      x
    case False{}:
      y

def pre_prof(+pre: Pre, +live: String) -> SPlan.Prof:
  match pre:
    case Pre{l, p}:
      sel_prof(String.eq(l, live), p, SPlan.ProfNone{})

def no_pre() -> Pre:
  Pre{"", SPlan.ProfNone{}}

def need_lookup(+slot: Maybe<&2, String>, +live: String, +backup: String) -> Bool:
  B.is_some_str(slot) && SBase.nonempty(live) && Bool.not(String.eq(backup, live)) && Bool.not(C.same_lineage(backup, live))

# `_prefetch_live_identity`: before any lock is taken, look the diverged live
# credential up (the only network call of a switch).
def prefetch2(+want: Bool, +o: Oracle, +live: String) -> Act.of(SPlan.Prof):
  Act.cond(SPlan.Prof, want && SBase.nonempty(C.access_of(live)), Act.lift(SPlan.Prof, run_oracle(o, C.access_of(live))), Act.pure(SPlan.Prof, SPlan.ProfNone{}))

def lookup_need(+l: Live, +seq: Json.Json, +backup: String) -> Bool:
  need_lookup(lv_slot(l, seq), lv_creds(l), backup)

def backup_of(+ctx: SBase.Ctx, +l: Live, +seq: Json.Json) -> Act.of(String):
  SIo.read_cred(SBase.root_of(ctx), SSeq.str_or(lv_slot(l, seq), ""), lv_email(l))

def lookup_for(+ctx: SBase.Ctx, +o: Oracle, +l: Live, +seq: Json.Json) -> Act.of(SPlan.Prof):
  do ActM<SPlan.Prof>:
    backup : String <- backup_of(ctx, l, seq)
    prefetch2(lookup_need(l, seq, backup), o, lv_creds(l))

def prefetch3(+ctx: SBase.Ctx, +o: Oracle, +l: Live, +m: Maybe<&2, Json.Json>) -> Act.of(Pre):
  match m:
    case None{}:
      Act.pure(Pre, no_pre())
    case Some{seq}:
      do ActM<Pre>:
        p : SPlan.Prof <- lookup_for(ctx, o, l, seq)
        return Pre{lv_creds(l), p}

def prefetch(+ctx: SBase.Ctx, +o: Oracle) -> Act.of(Pre):
  do ActM<Pre>:
    l : Live <- read_live(ctx)
    m : Maybe<&2, Json.Json> <- SIo.read_seq(SBase.root_of(ctx))
    prefetch3(ctx, o, l, m)
