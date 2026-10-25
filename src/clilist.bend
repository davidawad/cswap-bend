import Base
import ./setload.bend as Setload
import ./collectrun.bend as Collectrun
import ./pollrow.bend as Pollrow
import ./store/io.bend as SIo
import ./store/base.bend as SBase
import ./store/seq.bend as SSeq
import ./json.bend as Json
import ./clock.bend as Clock
import ./act.bend as Act
import ./cmd.bend as Cmd
import ./view.bend as View
import ./collect.bend as Collect
import ./store.bend as Store
import ./render.bend as Render
import ./warn.bend as Warn
import ./clibase.bend as Clibase

def rows_json(as: List<&2, View.Acct>, +models: List<&2, String>, +now: U32, +off: U32) -> List<&2, Json.Json>:
  match as:
    case Nil{}:
      []
    case Con{h, t}:
      View.account_row(h, models, now, off) <> rows_json(t, models, now, off)

def active.pick(active: Bool, +num: U32, rest: Json.Json) -> Json.Json:
  match active:
    case True{}:
      Json.JNum{U32.show(num)}
    case False{}:
      rest

def active_num(as: List<&2, View.Acct>) -> Json.Json:
  match as:
    case Nil{}:
      Json.JNull{}
    case Con{View.Acct{num, e, on, ou, active, al, dis, lg, sen, row}, t}:
      active.pick(active, num, active_num(t))

def strs_json(xs: List<&2, String>) -> List<&2, Json.Json>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      Json.JStr{h} <> strs_json(t)

def with_warn(+k: String, xs: List<&2, String>, j: Json.Json) -> Json.Json:
  match xs:
    case Nil{}:
      j
    case Con{h, t}:
      Json.set(k, Json.arr(strs_json(h <> t)), j)

def list_payload(+as: List<&2, View.Acct>, models: List<&2, String>, +now: U32, +off: U32, dups: List<&2, String>, locks: List<&2, String>) -> Json.Json:
  with_warn("lockstepUsageWarnings", locks, with_warn("duplicateAccountWarnings", dups,
    Json.of_pairs([("schemaVersion", Json.JNum{"1"}), ("activeAccountNumber", active_num(as)), ("accounts", Json.arr(rows_json(as, models, now, off)))])))

def lines.measured(has: Bool, +lg: Json.Json, +fetched: Maybe<&2, U32>, +now: U32, +off: U32, le: Maybe<&2, String>) -> List<&2, String>:
  match has:
    case True{}:
      Render.measured(lg, fetched, Pollrow.age_of(fetched, now), now, off)
    case False{}:
      Render.unavailable(le)

def acct_lines2(sentinel: Maybe<&2, String>, +row: Pollrow.Row, +now: U32, +off: U32) -> List<&2, String>:
  match sentinel row:
    case Some{s} Pollrow.Row{fetched, lg, la, fl, le, bu, np, iv, l429, st, sfp, cu, hu}:
      Render.sentinel_lines(s, lg, fetched, Pollrow.age_of(fetched, now), off)
    case None{} Pollrow.Row{+fetched, lg, la, fl, le, bu, np, iv, l429, st, sfp, cu, hu}:
      lines.measured(View.is_obj(lg), lg, fetched, now, off, le)

def acct_lines(+a: View.Acct, +now: U32, +off: U32) -> List<&2, String>:
  match a:
    case View.Acct{num, email, org_name, org_uuid, active, alias, disabled, login, sentinel, row}:
      acct_lines2(sentinel, row, now, off)

def tag_of(+org_name: String) -> String:
  Clock.sel.s(String.is_empty(org_name), "personal", org_name)

def head_line(+a: View.Acct) -> String:
  match a:
    case View.Acct{num, email, org_name, org_uuid, active, alias, disabled, login, sentinel, row}:
      "  " ++ U32.show(num) ++ ": " ++ Clock.sel.s(String.is_empty(alias), email, alias ++ " (" ++ email ++ ")") ++ " [" ++ tag_of(org_name) ++ "]"
        ++ Clock.sel.s(active, " (active)", "") ++ Clock.sel.s(disabled, " (disabled)", "")

def indent5(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{h, t}:
      "     " ++ h ++ "\n" ++ indent5(t)

def acct_block(+a: View.Acct, +now: U32, +off: U32) -> String:
  head_line(a) ++ "\n" ++ indent5(acct_lines(a, now, off))

def blocks(as: List<&2, View.Acct>, +now: U32, +off: U32) -> String:
  match as:
    case Nil{}:
      ""
    case Con{h, Nil{}}:
      acct_block(h, now, off)
    case Con{h, Con{h2, t2}}:
      acct_block(h, now, off) ++ "\n" ++ blocks(h2 <> t2, now, off)

def warn_lines(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      "Warning: " ++ h ++ "\n" ++ warn_lines(t)

def warn_gap(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, t}:
      "\n" ++ warn_lines(h <> t)

def warn_block(dups: List<&2, String>, locks: List<&2, String>) -> String:
  warn_gap(List.append(&2, String, dups, locks))

def list_text(as: List<&2, View.Acct>, +now: U32, +off: U32, dups: List<&2, String>, locks: List<&2, String>) -> String:
  "Accounts:\n" ++ blocks(as, now, off) ++ warn_block(dups, locks)

def list_out(+json: Bool, as: List<&2, View.Acct>, models: List<&2, String>, +now: U32, +off: U32, dups: List<&2, String>, locks: List<&2, String>) -> Cmd.Out:
  match json:
    case True{}:
      Cmd.doc(list_payload(as, models, now, off, dups, locks))
    case False{}:
      Cmd.Out{0, list_text(as, now, off, dups, locks), ""}

def empty_list(+json: Bool) -> Cmd.Out:
  match json:
    case True{}:
      Cmd.doc(Json.of_pairs([("schemaVersion", Json.JNum{"1"}), ("activeAccountNumber", Json.JNull{}), ("accounts", Json.arr([]))]))
    case False{}:
      Cmd.ok("No accounts are managed yet.")

def settings_of(+ctx: SBase.Ctx) -> Act.of(Json.Json):
  Act.lift(Json.Json, Setload.load(SBase.root_of(ctx)))

# One usage pass over `infos` with the models and threshold of the settings.
def usage_pass(+ctx: SBase.Ctx, infos: List<&2, Collect.Info>, tm: Clibase.Tm, +cfg: Json.Json) -> Act.of(List<&2, View.Acct>):
  match tm:
    case Clibase.Tm{now, off, tick}:
      Collectrun.collect(ctx, infos, now, Setload.model(cfg), Setload.threshold_tenths(cfg), tick)

def list_finish(+json: Bool, +infos: List<&2, Collect.Info>, +accts: List<&2, View.Acct>, +seq: Json.Json, +cfg: Json.Json, tm: Clibase.Tm) -> Cmd.Out:
  match tm:
    case Clibase.Tm{+now, off, tick}:
      list_out(json, accts, Setload.model(cfg), now, off, Warn.duplicates(infos, seq), Warn.lockstep(accts, Setload.model(cfg), now))

def list_run(+ctx: SBase.Ctx, +seq: Json.Json, +json: Bool) -> Act.of(Cmd.Out):
  do Clibase.ActM<Cmd.Out>:
    +tm : Clibase.Tm <- Clibase.times()
    +cfg : Json.Json <- settings_of(ctx)
    +infos : List<&2, Collect.Info> <- Collect.gather(ctx, seq)
    +accts : List<&2, View.Acct> <- usage_pass(ctx, infos, tm, cfg)
    return list_finish(json, infos, accts, seq, cfg, tm)

def list_seq(m: Maybe<&2, Json.Json>, +ctx: SBase.Ctx, +json: Bool) -> Act.of(Cmd.Out):
  match m:
    case None{}:
      Clibase.done(empty_list(json))
    case Some{seq}:
      list_run(ctx, seq, json)

def list_cmd(+ctx: SBase.Ctx, +json: Bool) -> Act.of(Cmd.Out):
  Act.bind(Maybe<&2, Json.Json>, Cmd.Out, SIo.read_seq(SBase.root_of(ctx)), m => list_seq(m, ctx, json))

def unmanaged(+json: Bool, +email: String) -> Cmd.Out:
  match json:
    case True{}:
      Cmd.doc(Json.of_pairs([("schemaVersion", Json.JNum{"1"}), ("active", Json.of_pairs([("email", Json.JStr{email}), ("managed", Json.JBool{False{}})]))]))
    case False{}:
      Cmd.ok("Status: " ++ email ++ " (not managed)")

def logged_out(+json: Bool) -> Cmd.Out:
  match json:
    case True{}:
      Cmd.doc(Json.of_pairs([("schemaVersion", Json.JNum{"1"}), ("active", Json.JNull{})]))
    case False{}:
      Cmd.ok("Status: No active Claude account")

def only.pick(a: Bool, i: Collect.Info, rest: List<&2, Collect.Info>) -> List<&2, Collect.Info>:
  match a:
    case True{}:
      i <> rest
    case False{}:
      rest

def info_active(+i: Collect.Info) -> Bool:
  match i:
    case Collect.Info{num, email, org_name, org_uuid, alias, disabled, active, creds}:
      active

def active_only(xs: List<&2, Collect.Info>) -> List<&2, Collect.Info>:
  match xs:
    case Nil{}:
      []
    case Con{+i, t}:
      only.pick(info_active(i), i, active_only(t))

def status_row(+a: View.Acct, models: List<&2, String>, +now: U32, +off: U32) -> Json.Json:
  Json.set("managed", Json.JBool{True{}}, Json.del("loginExpiresAt", Json.del("disabled", Json.del("active", View.account_row(a, models, now, off)))))

def total_of(+seq: Json.Json) -> Json.Json:
  Json.JNum{Nat.show(List.length(&2, String, Json.keys(Maybe.default(&2, Json.Json, Json.get("accounts", seq), Json.JNull{}))))}

def total_text(j: Json.Json) -> String:
  match j:
    case Json.JNum{t}:
      t
    case _:
      "0"

def indent2(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{h, t}:
      "  " ++ h ++ "\n" ++ indent2(t)

def status_text(+a: View.Acct, +total: Json.Json, +now: U32, +off: U32) -> String:
  match a:
    case View.Acct{num, email, org_name, org_uuid, active, alias, disabled, login, sentinel, row}:
      "Status: Account-" ++ U32.show(num) ++ " (" ++ email ++ " [" ++ tag_of(org_name) ++ "])\n  Total managed accounts: " ++ total_text(total) ++ "\n"
        ++ indent2(acct_lines(a, now, off))

def status_out2(+json: Bool, +a: View.Acct, models: List<&2, String>, +seq: Json.Json, +now: U32, +off: U32) -> Cmd.Out:
  match json:
    case True{}:
      Cmd.doc(Json.of_pairs([("schemaVersion", Json.JNum{"1"}), ("active", status_row(a, models, now, off)), ("totalManagedAccounts", total_of(seq))]))
    case False{}:
      Cmd.Out{0, status_text(a, total_of(seq), now, off), ""}

def status_out(+json: Bool, as: List<&2, View.Acct>, models: List<&2, String>, +seq: Json.Json, +now: U32, +off: U32) -> Cmd.Out:
  match as:
    case Nil{}:
      Cmd.fail("the active account has no record")
    case Con{+a, t}:
      status_out2(json, a, models, seq, now, off)

def status_finish(+json: Bool, accts: List<&2, View.Acct>, +seq: Json.Json, +cfg: Json.Json, tm: Clibase.Tm) -> Cmd.Out:
  match tm:
    case Clibase.Tm{now, off, tick}:
      status_out(json, accts, Setload.model(cfg), seq, now, off)

def status_run(+ctx: SBase.Ctx, +seq: Json.Json, +json: Bool) -> Act.of(Cmd.Out):
  do Clibase.ActM<Cmd.Out>:
    +tm : Clibase.Tm <- Clibase.times()
    +cfg : Json.Json <- settings_of(ctx)
    infos : List<&2, Collect.Info> <- Collect.gather(ctx, seq)
    accts : List<&2, View.Acct> <- usage_pass(ctx, active_only(infos), tm, cfg)
    return status_finish(json, accts, seq, cfg, tm)

def status_slot(m: Maybe<&2, String>, +ctx: SBase.Ctx, +seq: Json.Json, +json: Bool, +email: String) -> Act.of(Cmd.Out):
  match m:
    case None{}:
      Clibase.done(unmanaged(json, email))
    case Some{slot}:
      status_run(ctx, seq, json)

def status_seq(m: Maybe<&2, Json.Json>, +ctx: SBase.Ctx, +json: Bool, +id: Store.Ident) -> Act.of(Cmd.Out):
  match m:
    case None{}:
      Clibase.done(unmanaged(json, Store.id_email(id)))
    case Some{+seq}:
      status_slot(SSeq.find_slot(seq, Store.id_email(id), Store.id_org(id)), ctx, seq, json, Store.id_email(id))

def status_ident.m(c: Bool, +id: Store.Ident, +ctx: SBase.Ctx, +json: Bool) -> Act.of(Cmd.Out):
  match c:
    case True{}:
      Clibase.done(logged_out(json))
    case False{}:
      Act.bind(Maybe<&2, Json.Json>, Cmd.Out, SIo.read_seq(SBase.root_of(ctx)), m => status_seq(m, ctx, json, id))

def status_ident(+id: Store.Ident, +ctx: SBase.Ctx, +json: Bool) -> Act.of(Cmd.Out):
  status_ident.m(String.is_empty(Store.id_email(id)), id, ctx, json)
def status_cmd(+ctx: SBase.Ctx, +json: Bool) -> Act.of(Cmd.Out):
  Act.bind(Store.Ident, Cmd.Out, Act.lift(Store.Ident, Collect.live_ident(ctx)), id => status_ident(id, ctx, json))
