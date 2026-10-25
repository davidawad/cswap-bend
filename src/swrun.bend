import Base
import ./json.bend as Json
import ./fs.bend as Fs
import ./act.bend as Act
import ./store.bend as Store
import ./swbase.bend as B
import ./swcreds.bend as C
import ./swlive.bend as L
import ./fs/write.bend as FsW
import ./store/base.bend as SBase
import ./store/io.bend as SIo
import ./store/seq.bend as SSeq

# Switch, part 5: the locked switch, rollback and the post-switch check.

# `do ActM<A>:` (see store.bend).

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def need(+ok: Bool, +msg: String) -> Act.of(Unit):
  Act.guard(ok, 4, msg)

def reinstruct(+slot: String) -> String:
  "Re-add with: cswap --add-account --slot " ++ slot

def oauth_present(+j: Json.Json) -> Bool:
  match j:
    case Json.JObj{Json.JField{k, v, t}}:
      True{}
    case _:
      False{}

# The outgoing account's backup, by what the live credential is.
def backup_outgoing(+k: C.CKind, +root: String, +cur: String, +email: String, +creds: String, +cfg_text: String) -> Act.of(Unit):
  match k:
    case C.KOwnBytes{}:
      SIo.write_config(root, cur, email, cfg_text)
    case C.KWiped{}:
      SIo.write_config(root, cur, email, cfg_text)
    case C.KForeignSynced{s}:
      Act.pure(Unit, Unit{})
    case C.KForeign{s}:
      Act.pure(Unit, Unit{})
    case C.KAlien{}:
      Act.pure(Unit, Unit{})
    case _:
      do ActM<Unit>:
        SIo.write_cred(root, cur, email, creds)
        SIo.write_config(root, cur, email, cfg_text)

def salvage(+bad: Bool, +ctx: SBase.Ctx, +ts: String) -> Act.of(Unit):
  Act.cond(Unit, bad, FsW.rename(SBase.global_config_path(ctx), SBase.global_config_path(ctx) ++ ".corrupt-" ++ ts), Act.pure(Unit, Unit{}))

# What ~/.claude.json becomes: the live one with the target's oauthAccount, or
# the target's whole config backup when there is no readable live one.
def new_config(+l: L.Live, +oauth: Json.Json, +tcreds: String, +tcfg: Json.Json) -> Json.Json:
  Store.sel.j(L.lv_cfg_ok(l), B.activate_config(L.lv_cfg(l), oauth, tcreds), tcfg)

def live_salvage(+ctx: SBase.Ctx, +ts: String, +l: L.Live) -> Act.of(Unit):
  salvage(Bool.not(L.lv_cfg_ok(l)) && B.is_some_str(L.lv_cfg_text(l)), ctx, ts)

def activate_files(+ctx: SBase.Ctx, +ts: String, +l: L.Live, +oauth: Json.Json, +tcreds: String, +tcfg: Json.Json) -> Act.of(Unit):
  do ActM<Unit>:
    L.write_live_creds(ctx, C.prepare_activation(tcreds, L.lv_creds(l)))
    live_salvage(ctx, ts, l)
    L.write_cfg(ctx, new_config(l, oauth, tcreds, tcfg))

def final_steps(+ctx: SBase.Ctx, +root: String, +target: String, +ts: String, +seq: Json.Json, +l: L.Live, +oauth: Json.Json, +tcreds: String, +tcfg: Json.Json) -> Act.of(Unit):
  do ActM<Unit>:
    activate_files(ctx, ts, l, oauth, tcreds, tcfg)
    SIo.write_seq(root, SSeq.stamp(SSeq.set_active(seq, SSeq.str_u32(target)), ts))

def transact(+ctx: SBase.Ctx, +root: String, +ts: String, +seq_text: String, +l: L.Live, steps: Act.of(Unit)) -> Act.of(Unit):
  IO.bind(Fs.Res(Unit), Fs.Res(Unit), Act.on_fail(Unit, steps, L.restore(ctx, root, L.lv_creds_text(l), L.lv_cfg_text(l), seq_text)), r => IO.pure(Fs.Res(Unit), L.wrap_failure(r)))

def archive_for_a(+root: String, +cts: String, +l: L.Live, +tcreds: String) -> Act.of(Unit):
  L.archive_if(SBase.nonempty(L.lv_creds(l)) && Bool.not(String.eq(L.lv_creds(l), tcreds)), root, L.lv_email(l), L.lv_creds(l), cts)

def finish_a(+root: String, +target: String, +temail: String, +l: L.Live, +oauth: Json.Json, +cur: Maybe<&2, String>) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    SIo.log(root, "INFO", "Activated account " ++ target ++ " (live login " ++ SBase.sel.s(String.is_empty(L.lv_email(l)), "absent", "was " ++ L.lv_email(l)) ++ ")")
    return B.op_json(B.from_ref(L.lv_email(l), cur), B.ref(Some{target}, temail), [], SSeq.field_str(oauth, "organizationUuid"))

def switch_a(+ctx: SBase.Ctx, +root: String, +target: String, +temail: String, +ts: String, +cts: String, +seq_text: String, +seq: Json.Json, +l: L.Live, +oauth: Json.Json, +tcreds: String, +tcfg: Json.Json, +cur: Maybe<&2, String>) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    archive_for_a(root, cts, l, tcreds)
    transact(ctx, root, ts, seq_text, l, final_steps(ctx, root, target, ts, seq, l, oauth, tcreds, tcfg))
    finish_a(root, target, temail, l, oauth, cur)

def live_present(+l: L.Live) -> Act.of(Unit):
  Act.guard(SBase.nonempty(L.lv_creds(l)), 5, "Current account credential is empty (Keychain unreadable?); refusing to overwrite its backup")

def classify_in(+pre: L.Pre, +seq: Json.Json, +cur: String, +l: L.Live, +backup: String, +others: List<&2, C.Other>) -> C.CKind:
  C.final_kind(C.classify(L.lv_creds(l), backup, others), seq, cur, L.lv_creds(l), others, L.pre_prof(pre, L.lv_creds(l)))

def classify_b(+pre: L.Pre, +root: String, +seq: Json.Json, +cur: String, +l: L.Live) -> Act.of(C.CKind):
  do ActM<C.CKind>:
    live_present(l)
    backup : String <- SIo.read_cred(root, cur, L.lv_email(l))
    +others : List<&2, C.Other> <- L.other_creds(root, seq, B.slots_of(seq), cur)
    return classify_in(pre, seq, cur, l, backup, others)

def backup_out(+k: C.CKind, +root: String, +cur: String, +l: L.Live) -> Act.of(Unit):
  backup_outgoing(k, root, cur, L.lv_email(l), L.lv_creds(l), B.text_or(L.lv_cfg_text(l)))

def save_b(+k: C.CKind, +root: String, +cur: String, +ts: String, +l: L.Live) -> Act.of(Unit):
  do ActM<Unit>:
    L.archive_if(C.preserve(k), root, L.lv_email(l), L.lv_creds(l), SBase.compact_ts(ts))
    backup_out(k, root, cur, l)

def finish_b(+k: C.CKind, +root: String, +target: String, +temail: String, +l: L.Live, +oauth: Json.Json, +cur: String) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    SIo.log(root, "INFO", "Switched from account " ++ cur ++ " to " ++ target)
    return B.op_json(B.from_ref(L.lv_email(l), Some{cur}), B.ref(Some{target}, temail), C.kind_warning(k, cur), SSeq.field_str(oauth, "organizationUuid"))

def switch_b(+pre: L.Pre, +ctx: SBase.Ctx, +root: String, +target: String, +temail: String, +ts: String, +seq_text: String, +seq: Json.Json, +l: L.Live, +oauth: Json.Json, +tcreds: String, +tcfg: Json.Json, +cur: String) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    +k : C.CKind <- classify_b(pre, root, seq, cur, l)
    save_b(k, root, cur, ts, l)
    transact(ctx, root, ts, seq_text, l, final_steps(ctx, root, target, ts, seq, l, oauth, tcreds, tcfg))
    finish_b(k, root, target, temail, l, oauth, cur)

def perform5(+case_a: Bool, +pre: L.Pre, +ctx: SBase.Ctx, +root: String, +target: String, +ts: String, +seq_text: String, +seq: Json.Json, +temail: String, +l: L.Live, +tcreds: String, +tcfg: Json.Json, +oauth: Json.Json) -> Act.of(Json.Json):
  Act.cond(Json.Json, case_a,
    switch_a(ctx, root, target, temail, ts, SBase.compact_ts(ts), seq_text, seq, l, oauth, tcreds, tcfg, L.lv_slot(l, seq)),
    switch_b(pre, ctx, root, target, temail, ts, seq_text, seq, l, oauth, tcreds, tcfg, SSeq.str_or(L.lv_slot(l, seq), "")))

def perform4(+ctx: SBase.Ctx, +root: String, +target: String, +force: Bool, +pre: L.Pre, +ts: String, +seq_text: String, +seq: Json.Json, +temail: String, +l: L.Live, +tcreds: String, +tcfg: Json.Json, +oauth: Json.Json) -> Act.of(Json.Json):
  perform5(force || String.is_empty(L.lv_email(l)) || Bool.not(B.is_some_str(L.lv_slot(l, seq))), pre, ctx, root, target, ts, seq_text, seq, temail, l, tcreds, tcfg, oauth)

def perform7(+ok: Bool, +ctx: SBase.Ctx, +root: String, +target: String, +force: Bool, +pre: L.Pre, +ts: String, +seq_text: String, +seq: Json.Json, +temail: String, +l: L.Live, +tcreds: String, +tcfg: Json.Json) -> Act.of(Json.Json):
  Act.cond(Json.Json, ok,
    perform4(ctx, root, target, force, pre, ts, seq_text, seq, temail, l, tcreds, tcfg, SSeq.get_or("oauthAccount", tcfg, Json.JNull{})),
    Act.fail(Json.Json, 4, "Invalid oauthAccount in backup"))

def perform6(+ctx: SBase.Ctx, +root: String, +target: String, +force: Bool, +pre: L.Pre, +ts: String, +seq_text: String, +seq: Json.Json, +temail: String, +l: L.Live, +tcreds: String, parsed: Result<&2, &2, String, Json.Json>) -> Act.of(Json.Json):
  match parsed:
    case Fail{e}:
      Act.fail(Json.Json, 4, "Invalid backup config: " ++ e)
    case Done{+tcfg}:
      perform7(oauth_present(SSeq.get_or("oauthAccount", tcfg, Json.JNull{})), ctx, root, target, force, pre, ts, seq_text, seq, temail, l, tcreds, tcfg)

def tcfg_need(+target: String, +tcfg_text: Maybe<&2, String>) -> Act.of(Unit):
  need(SBase.nonempty(B.text_or(tcfg_text)), "Account-" ++ target ++ " has no stored config backup. " ++ reinstruct(target))

def perform3b(+ctx: SBase.Ctx, +root: String, +target: String, +force: Bool, +pre: L.Pre, +ts: String, +seq_text: String, +seq: Json.Json, +temail: String, +l: L.Live, +tcreds: String) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    +tcfg_text : Maybe<&2, String> <- L.read_text_opt(SBase.config_path(root, target, temail))
    tcfg_need(target, tcfg_text)
    perform6(ctx, root, target, force, pre, ts, seq_text, seq, temail, l, tcreds, Json.parse(B.text_or(tcfg_text)))

def perform3(+ctx: SBase.Ctx, +root: String, +target: String, +force: Bool, +pre: L.Pre, +ts: String, +seq_text: String, +seq: Json.Json, +temail: String) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    l : L.Live <- L.read_live(ctx)
    +tcreds : String <- SIo.read_cred(root, target, temail)
    need(SBase.nonempty(tcreds), "Account-" ++ target ++ " has no stored credentials. " ++ reinstruct(target))
    perform3b(ctx, root, target, force, pre, ts, seq_text, seq, temail, l, tcreds)

def perform2b(+ctx: SBase.Ctx, +root: String, +target: String, +force: Bool, +pre: L.Pre, +ts: String, +seq_text: String, +seq: Json.Json, +rec: Maybe<&2, Json.Json>) -> Act.of(Json.Json):
  match rec:
    case None{}:
      Act.fail(Json.Json, 3, "Account-" ++ target ++ " does not exist")
    case Some{r}:
      perform3(ctx, root, target, force, pre, ts, seq_text, seq, SSeq.field_str(r, "email"))

def perform2(+ctx: SBase.Ctx, +root: String, +target: String, +force: Bool, +pre: L.Pre, +ts: String, +seq_text: String, parsed: Result<&2, &2, String, Json.Json>) -> Act.of(Json.Json):
  match parsed:
    case Fail{e}:
      Act.fail(Json.Json, 1, SBase.seq_path(root) ++ " exists but could not be parsed (" ++ e ++ "). Repair or move it, then retry — refusing to overwrite it unread.")
    case Done{+seq}:
      perform2b(ctx, root, target, force, pre, ts, seq_text, seq, SSeq.slot_record(seq, target))

# The switch itself, under every lock the reference takes.
def perform_locked(+ctx: SBase.Ctx, +target: String, +force: Bool, +pre: L.Pre, +ts: String) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    +seq_text : String <- Fs.read_file(SBase.seq_path(SBase.root_of(ctx)))
    perform2(ctx, SBase.root_of(ctx), target, force, pre, ts, seq_text, Json.parse(seq_text))

def verify2(+l: L.Live, +target: String, +temail: String, +torg: String) -> Act.of(Unit):
  Act.guard(String.eq(L.lv_email(l), temail) && String.eq(L.lv_org(l), torg), B.e_overridden(), B.override_msg(target, temail, L.lv_email(l)))

# Claude Code on macOS prefers a keychain login over ~/.claude/.credentials.json,
# so a file-only switch can be silently undone: it rewrites oauthAccount from
# the keychain login. Wait `opts`, read ~/.claude.json again, and if it no
# longer names the target report `live-login-overridden`. The keychain is never
# touched; the remedy is the user's.
def verify_live(+ctx: SBase.Ctx, +delay_ms: U32, +target: String, +temail: String, +torg: String) -> Act.of(Unit):
  do ActM<Unit>:
    Act.lift(Unit, IO.sleep(delay_ms))
    l : L.Live <- L.read_live(ctx)
    verify2(l, target, temail, torg)

def do_switch2(+ctx: SBase.Ctx, +target: String, +force: Bool, +opts: L.Opts, +pre: L.Pre) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    ts : String <- SIo.now_iso()
    +op : Json.Json <- L.with_locks(Json.Json, ctx, perform_locked(ctx, target, force, pre, ts))
    verify_live(ctx, L.opts_delay(opts), target, SSeq.field_str(SSeq.get_or("to", op, Json.JNull{}), "email"), SSeq.field_str(op, "targetOrg"))
    return op

def do_switch(+ctx: SBase.Ctx, +target: String, +force: Bool, +opts: L.Opts) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    pre : L.Pre <- Act.cond(L.Pre, force, Act.pure(L.Pre, L.no_pre()), L.prefetch(ctx, L.opts_oracle(opts)))
    do_switch2(ctx, target, force, opts, pre)
