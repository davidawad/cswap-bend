import Base
import ./urec.bend as Urec
import ./pollrow.bend as Pollrow
import ./usage/cred.bend as UCred
import ./store/io.bend as SIo
import ./store/seq.bend as SSeq
import ./store/base.bend as SBase
import ./json.bend as Json
import ./clock.bend as Clock
import ./fs.bend as Fs
import ./act.bend as Act
import ./poll.bend as Poll
import ./ustore.bend as Ustore
import ./usage.bend as Usage
import ./view.bend as View
import ./store.bend as Store

# API (also the daemon's collector; do not copy it):
#   gather(ctx, seq) -> Act(List<Info>)      every account in `sequence`, the active one with the live credential
#   collect(ctx, infos, now, models, threshold_tenths, tick) -> Act(List<View.Acct>)
#       one usage pass: lease what is eligible, fetch it (gated refresh for inactive accounts), merge, read back
#   fingerprint(creds) -> IO(String)         the usage.json fingerprint (sha256 via shasum, token on stdin)
# `models` are the scoped-window names that gate an account; `threshold_tenths` is the autoswitch threshold in tenths of a percent.
#
# Store-backed usage collection for list and status (_collect_usage_entries):
# read the rows, lease what is eligible, fetch it, merge the outcomes, and
# hand back one View.Acct per account. Fetches run one after another (the
# reference runs them in parallel with a 0.25 s stagger).

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

# One managed account with the credential its usage is read with: the live
# one for the active slot, the stored backup otherwise.
type Info is Data:
  Info{num: U32, email: String, org_name: String, org_uuid: String, alias: String, disabled: Bool,
       active: Bool, creds: String}

def id_of(+i: Info) -> Ustore.Id:
  match i:
    case Info{num, email, org_name, org_uuid, alias, disabled, active, creds}:
      Ustore.Id{U32.show(num), email, org_uuid}

def slot_of(+i: Info) -> String:
  match i:
    case Info{num, email, org_name, org_uuid, alias, disabled, active, creds}:
      U32.show(num)

def read_text2(r: Fs.Res(String)) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{t}:
      t

# A file's text, "" when it cannot be read.
def read_text(+path: String) -> IO(String):
  IO.bind(Fs.Res(String), String, Fs.read_file(path), r => IO.pure(String, read_text2(r)))

def live_ident(+ctx: SBase.Ctx) -> IO(Store.Ident):
  IO.bind(String, Store.Ident, read_text(SBase.global_config_path(ctx)), t => IO.pure(Store.Ident, Store.ident_of(Json.unwrap(Json.parse(t)))))

def active.pick(ok: Bool, +seq: Json.Json, +id: Store.Ident) -> Maybe<&2, String>:
  match ok:
    case True{}:
      SSeq.find_slot(seq, Store.id_email(id), Store.id_org(id))
    case False{}:
      None{}

def active_slot(+seq: Json.Json, +id: Store.Ident) -> Maybe<&2, String>:
  active.pick(SBase.not_(String.is_empty(Store.id_email(id))), seq, id)

def is_active(m: Maybe<&2, String>, +slot: String) -> Bool:
  match m:
    case Some{s}:
      String.eq(s, slot)
    case None{}:
      False{}

def jstr_of(+rec: Json.Json, +k: String) -> String:
  SSeq.field_str(rec, k)

def flag.of(m: Maybe<&2, Json.Json>) -> Bool:
  match m:
    case Some{Json.JBool{True{}}}:
      True{}
    case _:
      False{}

def rec_flag(+rec: Json.Json, +k: String) -> Bool:
  flag.of(Json.get(k, rec))

def info.mk(+n: U32, +rec: Json.Json, active: Bool, +creds: String) -> Info:
  Info{n, jstr_of(rec, "email"), jstr_of(rec, "organizationName"), jstr_of(rec, "organizationUuid"), jstr_of(rec, "alias"), rec_flag(rec, "disabled"), active, creds}

def info.creds(active: Bool, +live: String, +root: String, +slot: String, +email: String) -> Act.of(String):
  match active:
    case True{}:
      Act.pure(String, live)
    case False{}:
      SIo.read_cred(root, slot, email)

def info.rec(m: Maybe<&2, Json.Json>, +n: U32, +active: Bool, +live: String, +root: String) -> Act.of(Info):
  match m:
    case None{}:
      Act.fail(Info, 1, "Account-" ++ U32.show(n) ++ " has no record")
    case Some{+rec}:
      Act.bind(String, Info, info.creds(active, live, root, U32.show(n), jstr_of(rec, "email")), c => Act.pure(Info, info.mk(n, rec, active, c)))

def info.one(+seq: Json.Json, +n: U32, am: Maybe<&2, String>, +live: String, +root: String) -> Act.of(Info):
  info.rec(SSeq.slot_record(seq, U32.show(n)), n, is_active(am, U32.show(n)), live, root)

def infos.go(ns: List<&2, U32>, +seq: Json.Json, +am: Maybe<&2, String>, +live: String, +root: String) -> Act.of(List<&2, Info>):
  match ns:
    case Nil{}:
      Act.pure(List<&2, Info>, [])
    case Con{n, t}:
      Act.bind(Info, List<&2, Info>, info.one(seq, n, am, live, root),
        i => Act.bind(List<&2, Info>, List<&2, Info>, infos.go(t, seq, am, live, root), rest => Act.pure(List<&2, Info>, i <> rest)))

def gather.go(+ctx: SBase.Ctx, +seq: Json.Json, +id: Store.Ident, +live: String) -> Act.of(List<&2, Info>):
  infos.go(SSeq.seq_nums(seq), seq, active_slot(seq, id), live, SBase.root_of(ctx))

# Every account in `sequence`, with the active one (by the live
# ~/.claude.json identity) carrying the live credential.
def gather(+ctx: SBase.Ctx, +seq: Json.Json) -> Act.of(List<&2, Info>):
  Act.bind(Store.Ident, List<&2, Info>, Act.lift(Store.Ident, live_ident(ctx)),
    id => Act.bind(String, List<&2, Info>, Act.lift(String, read_text(SBase.live_creds_path(ctx))), live => gather.go(ctx, seq, id, live)))

def sha.of2(oe: String & String) -> String:
  (o, e) = oe
  String.take(o, 64n)

def sha.of1(r: U32 & (String & String)) -> String:
  (st, oe) = r
  sha.of2(oe)

def sha.of(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{v}:
      sha.of1(v)

# Hex sha256 of a text through shasum(1), the text on stdin (never on argv).
def sha256(+text: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, String, Process.run("shasum", ["-a", "256"], text, 4096, 5000), r => IO.pure(String, sha.of(r)))

def fp.rt(+tag: String, +text: String) -> IO(String):
  IO.bind(String, String, sha256(text), h => IO.pure(String, tag ++ h))

def fp.pick(m: Maybe<&2, String>, +creds: String) -> IO(String):
  match m:
    case Some{rt}:
      fp.rt("sha256:", rt)
    case None{}:
      fp.rt("sha256-full:", creds)

# oauth.credential_fingerprint: the refresh token's hash, else the whole
# credential's.
def fingerprint(+creds: String) -> IO(String):
  fp.pick(UCred.refresh_token(UCred.oauth.of(creds)), creds)

# 0 none, 1 dead refresh-token lineage, 2 a strike the credential has outgrown.
def dead.cmp(+stored: String, struck: Maybe<&2, String>) -> U32:
  match struck:
    case None{}:
      1
    case Some{s}:
      Clock.sel(String.eq(s, stored), 1, 2)

def dead.go(has: Bool, struck: Maybe<&2, String>, +creds: String) -> IO(U32):
  match has:
    case False{}:
      IO.pure(U32, 0)
    case True{}:
      IO.bind(String, U32, fingerprint(creds), f => IO.pure(U32, dead.cmp(f, struck)))

def dead.fp(strikes: U32, struck: Maybe<&2, String>, +creds: String) -> IO(U32):
  dead.go(U32.is_ge(strikes, 1), struck, creds)

def dead.row(+r: Pollrow.Row, +creds: String) -> IO(U32):
  match r:
    case Pollrow.Row{fetched, lg, la, fl, le, bu, np, iv, l429, st, sfp, cu, hu}:
      dead.fp(st, sfp, creds)

def dead_state(+row: Json.Json, +creds: String) -> IO(U32):
  dead.row(Pollrow.row.of(row), creds)

def static.cred(none: Bool) -> Maybe<&2, String>:
  match none:
    case True{}:
      Some{"no_credentials"}
    case False{}:
      None{}

def static.pick(api: Bool, +creds: String) -> Maybe<&2, String>:
  match api:
    case True{}:
      Some{"api_key"}
    case False{}:
      static.cred(Maybe.is_none(&2, String, UCred.access_token(UCred.oauth.of(creds))))

def static_of(+creds: String) -> Maybe<&2, String>:
  static.pick(SBase.looks_like_api_key(creds), creds)

def held_row(+row: Json.Json, +now: U32) -> Bool:
  Pollrow.before.m(Pollrow.num.field("heldUntil", row), now)

def expired_creds(+creds: String, +now: U32) -> Bool:
  UCred.expired(UCred.oauth.of(creds), now)

def expired.pick(on: Bool, +creds: String, +now: U32) -> Maybe<&2, String>:
  match on:
    case True{}:
      Some{"token_expired"}
    case False{}:
      None{}

# An expired active token is never refreshed here (that is Claude Code's, under
# its own lock): it reads `token_expired` unless a held reading covers it.
def expired_sentinel(active: Bool, +row: Json.Json, +creds: String, +now: U32) -> Maybe<&2, String>:
  expired.pick(active && Bool.not(held_row(row, now)) && expired_creds(creds, now), creds, now)

def first(a: Maybe<&2, String>, b: Maybe<&2, String>) -> Maybe<&2, String>:
  match a:
    case Some{x}:
      Some{x}
    case None{}:
      b

def dead.pick(dead: Bool) -> Maybe<&2, String>:
  match dead:
    case True{}:
      Some{"relogin_required"}
    case False{}:
      None{}

def dead_sentinel(+d: U32) -> Maybe<&2, String>:
  dead.pick(U32.is_eq(d, 1))

# One account with its stored row and the usage state read off them.
type St is Data:
  St{info: Info, row: Json.Json, sentinel: Maybe<&2, String>, healed: Bool}

def st.mk(+i: Info, +row: Json.Json, +d: U32, +now: U32) -> St:
  match i:
    case Info{num, email, org_name, org_uuid, alias, disabled, active, creds}:
      St{i, row, first(static_of(creds), first(dead_sentinel(d), expired_sentinel(active, row, creds, now))), U32.is_eq(d, 2)}

def row_or_null(m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case Some{r}:
      r
    case None{}:
      Json.of_pairs([])

def creds_of(+i: Info) -> String:
  match i:
    case Info{num, email, org_name, org_uuid, alias, disabled, active, creds}:
      creds

def st.row(+i: Info, +row: Json.Json, +now: U32) -> IO(St):
  IO.bind(U32, St, dead_state(row, creds_of(i)), d => IO.pure(St, st.mk(i, row, d, now)))

def st.of(+i: Info, +rows: Json.Json, +now: U32) -> IO(St):
  st.row(i, row_or_null(Ustore.row_of(rows, id_of(i))), now)

def states(xs: List<&2, Info>, +rows: Json.Json, +now: U32) -> IO(List<&2, St>):
  match xs:
    case Nil{}:
      IO.pure(List<&2, St>, [])
    case Con{h, t}:
      IO.bind(St, List<&2, St>, st.of(h, rows, now), s => IO.bind(List<&2, St>, List<&2, St>, states(t, rows, now), rest => IO.pure(List<&2, St>, s <> rest)))

def st_slot(+s: St) -> String:
  match s:
    case St{info, row, sentinel, healed}:
      slot_of(info)

def st_healed(+s: St) -> Bool:
  match s:
    case St{info, row, sentinel, healed}:
      healed

def st_id(+s: St) -> Ustore.Id:
  match s:
    case St{info, row, sentinel, healed}:
      id_of(info)


def st_sentinel(+s: St) -> Maybe<&2, String>:
  match s:
    case St{info, row, sentinel, healed}:
      sentinel
