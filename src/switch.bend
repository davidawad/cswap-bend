import Base
import ./json.bend as Json
import ./act.bend as Act
import ./store.bend as Store
import ./swbase.bend as B
import ./swpick.bend as P
import ./swlive.bend as L
import ./swrun.bend as R
import ./store/base.bend as SBase
import ./store/io.bend as SIo
import ./store/ops.bend as SOps
import ./store/seq.bend as SSeq

# Switch, part 6: the entry points (switch_to, switch_auto).

# `do ActM<A>:` (see store.bend).

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def direct4(+already: Bool, +ctx: SBase.Ctx, +n: String, +force: Bool, +opts: L.Opts, +email: String) -> Act.of(Json.Json):
  match already:
    case True{}:
      Act.pure(Json.Json, B.noop("direct", "already-active", "Already on Account-" ++ n ++ " (" ++ email ++ ")", B.ref(Some{n}, email), []))
    case False{}:
      do ActM<Json.Json>:
        op : Json.Json <- R.do_switch(ctx, n, force, opts)
        return B.forced_result(force, B.result_of_op(op, "direct", []))

def direct3(+ctx: SBase.Ctx, +seq: Json.Json, +n: String, +force: Bool, +opts: L.Opts, +rec: Maybe<&2, Json.Json>) -> Act.of(Json.Json):
  match rec:
    case None{}:
      Act.fail(Json.Json, B.e_not_found(), "Account-" ++ n ++ " does not exist")
    case Some{r}:
      do ActM<Json.Json>:
        l : L.Live <- L.read_live(ctx)
        direct4(Bool.not(force) && String.eq(SSeq.str_or(L.lv_slot(l, seq), ""), n), ctx, n, force, opts, SSeq.field_str(r, "email"))

def direct2(+ctx: SBase.Ctx, +seq: Json.Json, +ident: String, +force: Bool, +opts: L.Opts, +r: SSeq.Resolved) -> Act.of(Json.Json):
  match r:
    case SSeq.RNone{}:
      Act.fail(Json.Json, B.e_not_found(), "No account found with identifier: " ++ ident)
    case SSeq.RAmb{msg}:
      Act.fail(Json.Json, B.e_config(), msg)
    case SSeq.RSlot{n}:
      direct3(ctx, seq, n, force, opts, SSeq.slot_record(seq, n))

def direct1(+ctx: SBase.Ctx, +ident: String, +force: Bool, +opts: L.Opts, +m: Maybe<&2, Json.Json>) -> Act.of(Json.Json):
  match m:
    case None{}:
      Act.fail(Json.Json, B.e_config(), "No accounts are managed yet")
    case Some{seq}:
      do ActM<Json.Json>:
        Act.guard(SOps.valid_ident(seq, ident), B.e_validation(), "Invalid account identifier: " ++ ident)
        direct2(ctx, seq, ident, force, opts, SSeq.resolve(seq, ident))

# `cswap switch <num|email|alias> [--force]`: the result object of contract 2.3.
# Already on the target is a no-op (`already-active`) unless `force`, which
# rewrites the live login from the stored backup (`activated`). After a real
# switch the live login is re-read once, `opts` later (see verify_live).
def switch_to(+ctx: SBase.Ctx, +ident: String, +force: Bool, +opts: L.Opts) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    m : Maybe<&2, Json.Json> <- SIo.read_seq(SBase.root_of(ctx))
    direct1(ctx, ident, force, opts, m)

def is_disabled(+rec: Maybe<&2, Json.Json>) -> Bool:
  match rec:
    case None{}:
      False{}
    case Some{r}:
      B.is_true(Json.get("disabled", r))

def cand_of2(+slot: String, +rec: Maybe<&2, Json.Json>, +c: String, +cfg: Maybe<&2, String>, +usage: Json.Json, +models: List<&2, String>) -> P.Cand:
  P.Cand{slot, is_disabled(rec), SBase.nonempty(c) && SBase.nonempty(B.text_or(cfg)), P.headroom(P.usage_row(usage, slot), models)}

def cand_of(+root: String, +seq: Json.Json, +usage: Json.Json, +models: List<&2, String>, +slot: String) -> Act.of(P.Cand):
  do ActM<P.Cand>:
    c : String <- SIo.read_cred(root, slot, SIo.slot_email(seq, slot))
    cfg : Maybe<&2, String> <- L.read_text_opt(SBase.config_path(root, slot, SIo.slot_email(seq, slot)))
    return cand_of2(slot, SSeq.slot_record(seq, slot), c, cfg, usage, models)

def cands_of(+root: String, +seq: Json.Json, +usage: Json.Json, +models: List<&2, String>, +slots: List<&2, String>) -> Act.of(List<&2, P.Cand>):
  match slots:
    case Nil{}:
      Act.pure(List<&2, P.Cand>, [])
    case Con{s, t}:
      do ActM<List<&2, P.Cand>>:
        c : P.Cand <- cand_of(root, seq, usage, models, s)
        rest : List<&2, P.Cand> <- cands_of(root, seq, usage, models, t)
        return c <> rest

def drop_slot_str(+x: String, +xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      B.sel_ls(String.eq(h, x), drop_slot_str(x, t), h <> drop_slot_str(x, t))

def usable(+cs: List<&2, P.Cand>) -> List<&2, P.Cand>:
  match cs:
    case Nil{}:
      []
    case Con{P.Cand{s, d, sw, h}, t}:
      P.sel_lc(Bool.not(d) && sw, P.Cand{s, d, sw, h} <> usable(t), usable(t))

def limits_label(+models: List<&2, String>) -> String:
  SBase.sel.s(List.is_empty(&2, String, models), "5h/7d limit", "usage limits")

def stay_msg(+cur: String) -> String:
  "staying on Account-" ++ cur ++ "."

def note_pick(+note: String, +cur: String, +curref: Json.Json, +models: List<&2, String>) -> Json.Json:
  Store.sel.j(String.eq(note, "current-unavailable"), B.noop("best", "usage-unavailable", "Current account usage is unavailable — " ++ stay_msg(cur), curref, []),
  Store.sel.j(String.eq(note, "no-comparison"), B.noop("best", "usage-unavailable", "No other account has usage data to compare — " ++ stay_msg(cur), curref, []),
  Store.sel.j(String.eq(note, "incomplete-comparison"), B.noop("best", "usage-unavailable", "No account with known usage has more remaining quota; some usage is unavailable — " ++ stay_msg(cur), curref, []),
  Store.sel.j(String.eq(note, "stay"), B.noop("best", "already-best", "Already on the account with the most remaining quota (Account-" ++ cur ++ ").", curref, []),
    B.noop("best", "candidates-exhausted", "All accounts are at their " ++ limits_label(models) ++ " — " ++ stay_msg(cur), curref, [])))))

def note_result(+note: String, +cur: String, +curref: Json.Json, +models: List<&2, String>) -> Json.Json:
  note_pick(note, cur, curref, models)

def best_out(o: P.BestOut, +ctx: SBase.Ctx, +cur: String, +curref: Json.Json, +models: List<&2, String>, +opts: L.Opts, fallthrough: Act.of(Json.Json)) -> Act.of(Json.Json):
  match o:
    case P.BPick{slot}:
      do ActM<Json.Json>:
        op : Json.Json <- R.do_switch(ctx, slot, False{}, opts)
        return B.result_of_op(op, "best", [])
    case P.BNote{+note}:
      Act.cond(Json.Json, String.eq(note, "none"), fallthrough, Act.pure(Json.Json, note_result(note, cur, curref, models)))

def best_pick(+usage: Json.Json, +cur: String, +models: List<&2, String>, +others: List<&2, P.Cand>) -> P.BestOut:
  P.select_best(P.headroom(P.usage_row(usage, cur), models), usable(others))

def best_run(+ctx: SBase.Ctx, +root: String, +seq: Json.Json, +cur: String, +curref: Json.Json, +usage: Json.Json, +models: List<&2, String>, +opts: L.Opts, fallthrough: Act.of(Json.Json)) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    others : List<&2, P.Cand> <- cands_of(root, seq, usage, models, drop_slot_str(cur, B.slots_of(seq)))
    best_out(best_pick(usage, cur, models, others), ctx, cur, curref, models, opts, fallthrough)

def rotate_do(+ctx: SBase.Ctx, +slot: String, +label: String, +warns: List<&2, String>, +opts: L.Opts) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    op : Json.Json <- R.do_switch(ctx, slot, False{}, opts)
    return B.result_of_op(op, label, warns)

def rotate_out(+s: P.Sel, +ctx: SBase.Ctx, +cur: String, +curref: Json.Json, +label: String, +models: List<&2, String>, +opts: L.Opts) -> Act.of(Json.Json):
  match s:
    case P.SelOk{slot, warns}:
      Act.cond(Json.Json, String.eq(slot, cur),
        Act.pure(Json.Json, B.noop(label, "already-active", "Already on " ++ B.ref_text(curref), curref, warns)),
        rotate_do(ctx, slot, label, warns, opts))
    case P.SelNone{warns, exhausted}:
      Act.pure(Json.Json, Store.sel.j(exhausted,
        B.noop(label, "candidates-exhausted", "All other accounts are at their " ++ limits_label(models) ++ " — " ++ stay_msg(cur), curref, warns),
        B.noop(label, "no-valid-target", "No other accounts have valid stored credentials/config.", curref, warns)))

def rotate_run2(+anchor: Maybe<&2, String>, +ctx: SBase.Ctx, +root: String, +seq: Json.Json, +cur: String, +curref: Json.Json, +usage: Json.Json, +label: String, +models: List<&2, String>, +opts: L.Opts) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    cs : List<&2, P.Cand> <- cands_of(root, seq, usage, models, P.rotated(B.slots_of(seq), anchor))
    rotate_out(P.select_next(cs, String.eq(label, "next-available")), ctx, cur, curref, label, models, opts)

def rotate_run(+ctx: SBase.Ctx, +root: String, +seq: Json.Json, +cur: String, +curref: Json.Json, +usage: Json.Json, +label: String, +models: List<&2, String>, +opts: L.Opts) -> Act.of(Json.Json):
  rotate_run2(B.sel_ms(String.eq(label, "next-available"), Some{cur}, B.num_str(Json.get("activeAccountNumber", seq))), ctx, root, seq, cur, curref, usage, label, models, opts)

def auto4(+strategy: String, +ctx: SBase.Ctx, +root: String, +seq: Json.Json, +cur: String, +curref: Json.Json, +usage: Json.Json, +label: String, +models: List<&2, String>, +opts: L.Opts) -> Act.of(Json.Json):
  Act.cond(Json.Json, String.eq(strategy, "best"),
    best_run(ctx, root, seq, cur, curref, usage, models, opts, rotate_run(ctx, root, seq, cur, curref, usage, label, models, opts)),
    rotate_run(ctx, root, seq, cur, curref, usage, label, models, opts))

def usage_json(+u: Maybe<&2, String>) -> Json.Json:
  Store.sel.j(B.is_some_json(L.parse_text(u)), B.unwrap_json(L.parse_text(u)), Json.JNull{})

def auto3(+strategy: String, +ctx: SBase.Ctx, +seq: Json.Json, +cur: String, +email: String, +label: String, +models: List<&2, String>, +opts: L.Opts) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    +u : Maybe<&2, String> <- L.read_text_opt(SBase.root_of(ctx) ++ "/cache/usage.json")
    auto4(strategy, ctx, SBase.root_of(ctx), seq, cur, B.ref(Some{cur}, email), usage_json(u), label, models, opts)

def auto2(+strategy: String, +ctx: SBase.Ctx, +seq: Json.Json, +l: L.Live, +cur: Maybe<&2, String>, +label: String, +models: List<&2, String>, +opts: L.Opts) -> Act.of(Json.Json):
  match cur:
    case None{}:
      Act.pure(Json.Json, B.noop(label, "unmanaged-account", "Active account is not managed; run cswap --add-account", B.ref(None{}, L.lv_email(l)), []))
    case Some{c}:
      Act.cond(Json.Json, Nat.is_lt(List.length(&2, String, B.slots_of(seq)), 2n),
        Act.pure(Json.Json, B.noop(label, "only-one-account", "Only one account is managed. Add more accounts to switch between.", B.ref(Some{c}, L.lv_email(l)), [])),
        auto3(strategy, ctx, seq, c, L.lv_email(l), label, models, opts))

def preferred2(+active: Maybe<&2, String>, +slots: List<&2, String>) -> Maybe<&2, String>:
  match active:
    case Some{a}:
      Some{a}
    case None{}:
      List.head(&2, String, slots)

# Switch with nobody logged in: the active slot, else the first.
def preferred(+seq: Json.Json) -> Maybe<&2, String>:
  preferred2(B.num_str(Json.get("activeAccountNumber", seq)), B.slots_of(seq))

def reason_of(+c: P.Cand) -> String:
  match c:
    case P.Cand{s, d, sw, h}:
      SBase.sel.s(d, "(disabled)", "(no stored credentials/config)")

def any_switchable(+cs: List<&2, P.Cand>) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case Con{P.Cand{s, d, sw, h}, t}:
      sw || any_switchable(t)

def fallback_out(+s: P.Sel, +all_cs: List<&2, P.Cand>, +ctx: SBase.Ctx, +warn: String, +label: String, +opts: L.Opts) -> Act.of(Json.Json):
  match s:
    case P.SelOk{slot, w}:
      rotate_do(ctx, slot, label, [warn], opts)
    case P.SelNone{w, e}:
      Act.fail(Json.Json, B.e_config(), SBase.sel.s(any_switchable(all_cs), "No accounts remain in rotation. Re-enable one with: cswap enable <num|email>", "No managed accounts have valid stored credentials/config. Re-add a slot with: cswap --add-account --slot <number>"))

def logged_out3(+c: P.Cand, +rest: List<&2, P.Cand>, +ctx: SBase.Ctx, +label: String, +opts: L.Opts) -> Act.of(Json.Json):
  match c:
    case P.Cand{slot, d, sw, h}:
      Act.cond(Json.Json, Bool.not(d) && sw,
        rotate_do(ctx, slot, label, [], opts),
        fallback_out(P.select_next(rest, False{}), Con{c, rest}, ctx, "Skipped Account-" ++ slot ++ " " ++ reason_of(c), label, opts))

def logged_out2(+cs: List<&2, P.Cand>, +ctx: SBase.Ctx, +label: String, +opts: L.Opts) -> Act.of(Json.Json):
  match cs:
    case Nil{}:
      Act.fail(Json.Json, B.e_config(), "No accounts are managed yet")
    case Con{c, rest}:
      logged_out3(c, rest, ctx, label, opts)

def logged_out4(+m: Maybe<&2, String>, +ctx: SBase.Ctx, +seq: Json.Json, +label: String, +opts: L.Opts) -> Act.of(Json.Json):
  match m:
    case None{}:
      Act.fail(Json.Json, B.e_config(), "No accounts are managed yet")
    case Some{t}:
      do ActM<Json.Json>:
        cs : List<&2, P.Cand> <- cands_of(SBase.root_of(ctx), seq, Json.JNull{}, [], Con{t, drop_slot_str(t, B.slots_of(seq))})
        logged_out2(cs, ctx, label, opts)

def logged_out(+ctx: SBase.Ctx, +seq: Json.Json, +label: String, +opts: L.Opts) -> Act.of(Json.Json):
  logged_out4(preferred(seq), ctx, seq, label, opts)

def auto_branch(+strategy: String, +ctx: SBase.Ctx, +seq: Json.Json, +l: L.Live, +label: String, +models: List<&2, String>, +opts: L.Opts) -> Act.of(Json.Json):
  Act.cond(Json.Json, String.is_empty(L.lv_email(l)), logged_out(ctx, seq, label, opts), auto2(strategy, ctx, seq, l, L.lv_slot(l, seq), label, models, opts))

def auto1(+strategy: String, +ctx: SBase.Ctx, +label: String, +models: List<&2, String>, +opts: L.Opts, +m: Maybe<&2, Json.Json>) -> Act.of(Json.Json):
  match m:
    case None{}:
      Act.fail(Json.Json, B.e_config(), "No accounts are managed yet")
    case Some{seq}:
      do ActM<Json.Json>:
        +l : L.Live <- L.read_live(ctx)
        auto_branch(strategy, ctx, seq, l, label, models, opts)

# `cswap switch [--strategy best|next-available] [--model NAMES]`: strategy
# "" rotates through `sequence`; "next-available" also skips accounts with no
# headroom; "best" moves to the account with strictly more headroom. Usage is
# read from cache/usage.json as it stands (no fetch). A logged-out machine
# activates the active (else first) slot. The result is the object of
# contract 2.3; no-op outcomes are results, not errors. A live unmanaged login
# is reported as `unmanaged-account` (the CLI adds it with Store.add_current).
def switch_auto(+ctx: SBase.Ctx, +strategy: String, +models: List<&2, String>, +opts: L.Opts) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    m : Maybe<&2, Json.Json> <- SIo.read_seq(SBase.root_of(ctx))
    auto1(strategy, ctx, B.sel_s(String.eq(strategy, "best") || String.eq(strategy, "next-available"), strategy, "rotation"), B.sel_ls(String.eq(strategy, "best") || String.eq(strategy, "next-available"), models, []), opts, m)

# ---- who owns a diverged live credential ------------------------------------------------------
