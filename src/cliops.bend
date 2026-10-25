import Base
import ./urec.bend as Urec
import ./store/ops.bend as SOps
import ./store/io.bend as SIo
import ./store/base.bend as SBase
import ./store/seq.bend as SSeq
import ./json.bend as Json
import ./clock.bend as Clock
import ./fs.bend as Fs
import ./act.bend as Act
import ./cmd.bend as Cmd
import ./ustore.bend as Ustore
import ./store.bend as Store
import ./importu.bend as Importu
import ./clibase.bend as Clibase

# How a command may talk to the user: `noin` forbids reading standard input
# (a prompt becomes an error), `yes` answers the remove confirmation.
type Ni is Data:
  Ni{noin: Bool, yes: Bool}

def ni_noin(+ni: Ni) -> Bool:
  match ni:
    case Ni{noin, yes}:
      noin

def ni_yes(+ni: Ni) -> Bool:
  match ni:
    case Ni{noin, yes}:
      yes

def slot_in(+m: String) -> String:
  Clibase.first_line(String.split(String.drop(m, 5n), ' '))

def answer(yes: Bool, +prefix: String, retry: Act.of(String)) -> Act.of(String):
  match yes:
    case True{}:
      Act.bind(String, String, retry, t => Act.pure(String, prefix ++ "\n" ++ t))
    case False{}:
      Act.pure(String, prefix ++ "\nCancelled")

def ask(+m: String, retry: Act.of(String)) -> Act.of(String):
  Act.bind(String, String, Clibase.read_line(), a => answer(Clibase.is_yes(a), m ++ "\nOverwrite slot " ++ slot_in(m) ++ "? [y/N] ", retry))

def ow.pick(occupied: Bool, +c: U32, +m: String, retry: Act.of(String)) -> Act.of(String):
  match occupied:
    case True{}:
      ask(m, retry)
    case False{}:
      Act.fail(String, c, m)

def ow.err(ce: U32 & String, retry: Act.of(String), +noin: Bool) -> Act.of(String):
  (+c, m) = ce
  ow.pick(U32.is_eq(c, 10) && Bool.not(noin), c, m, retry)

def ow.handle(r: Fs.Res(String), retry: Act.of(String), +noin: Bool) -> Act.of(String):
  match r:
    case Done{t}:
      Act.pure(String, t)
    case Fail{e}:
      ow.err(e, retry, noin)

# Run `first`; when it stops at an occupied slot (code 10) ask on stdin and,
# on a yes, run `retry` (the same call, told to overwrite). With `noin` the
# occupied slot is the error.
def with_overwrite(first: Act.of(String), retry: Act.of(String), +noin: Bool) -> Act.of(String):
  IO.bind(Fs.Res(String), Fs.Res(String), first, r => ow.handle(r, retry, noin))

def digits.pick(d: Bool, +c: Char, rest: String) -> String:
  match d:
    case True{}:
      SCon{c, rest}
    case False{}:
      ""

def digits_of(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+c, t}:
      digits.pick(Char.is_digit(c), c, digits_of(t))

def nonempty.pick(empty: Bool, +s: String) -> Maybe<&2, String>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Some{s}

def nonempty_str(+s: String) -> Maybe<&2, String>:
  nonempty.pick(String.is_empty(s), s)

def touched.pick(added: Bool, updated: Bool, +l: String) -> Maybe<&2, String>:
  match added updated:
    case True{} _:
      nonempty_str(digits_of(String.drop(l, 14n)))
    case False{} True{}:
      nonempty_str(digits_of(String.drop(l, 32n)))
    case False{} False{}:
      None{}

def touched.line(+l: String) -> Maybe<&2, String>:
  touched.pick(String.starts_with(l, "Added Account "), String.starts_with(l, "Updated credentials for Account "), l)

def first_some(a: Maybe<&2, String>, b: Maybe<&2, String>) -> Maybe<&2, String>:
  match a:
    case Some{x}:
      Some{x}
    case None{}:
      b

# The slot a successful add reported ("Added Account N: ..." and the like).
def touched(ls: List<&2, String>) -> Maybe<&2, String>:
  match ls:
    case Nil{}:
      None{}
    case Con{h, t}:
      first_some(touched.line(h), touched(t))

def clear_rec(m: Maybe<&2, Json.Json>, +root: String, +slot: String) -> Act.of(Unit):
  match m:
    case None{}:
      Act.pure(Unit, Unit{})
    case Some{+rec}:
      Urec.clear_dead(root, [Ustore.Id{slot, SSeq.field_str(rec, "email"), SSeq.field_str(rec, "organizationUuid")}])

def clear_seq(m: Maybe<&2, Json.Json>, +root: String, +slot: String) -> Act.of(Unit):
  match m:
    case None{}:
      Act.pure(Unit, Unit{})
    case Some{seq}:
      clear_rec(SSeq.slot_record(seq, slot), root, slot)

def clear_slot(m: Maybe<&2, String>, +root: String) -> Act.of(Unit):
  match m:
    case None{}:
      Act.pure(Unit, Unit{})
    case Some{slot}:
      Act.bind(Maybe<&2, Json.Json>, Unit, SIo.read_seq(root), sq => clear_seq(sq, root, slot))

# A credential was written for the slot: its dead-token strike (and failure
# state) no longer describes it, so the usage row starts clean.
def after_write(+root: String, +text: String) -> Act.of(Cmd.Out):
  Act.bind(Unit, Cmd.Out, clear_slot(touched(String.lines(text)), root), u => Act.pure(Cmd.Out, Clibase.text_out(text)))

def add_cmd(+ctx: SBase.Ctx, +alias: Maybe<&2, String>, +slot: Maybe<&2, U32>, +ni: Ni) -> Act.of(Cmd.Out):
  Act.bind(String, Cmd.Out, with_overwrite(Store.add_current(ctx, alias, slot, False{}, t0 => Store.profile_http(t0)), Store.add_current(ctx, alias, slot, True{}, t1 => Store.profile_http(t1)), ni_noin(ni)),
    t => after_write(SBase.root_of(ctx), t))

# The token: the argument, one line of stdin for `-`, or a prompt line.
def line_or_stop(noin: Bool) -> Act.of(String):
  match noin:
    case True{}:
      Act.fail(String, 2, "the token must be on the command line (standard input is not available)")
    case False{}:
      Clibase.read_line()

def token_src2(dash: Bool, +t: String, +noin: Bool) -> Act.of(String):
  match dash:
    case True{}:
      line_or_stop(noin)
    case False{}:
      Act.pure(String, t)

def token_src(m: Maybe<&2, String>, +noin: Bool) -> Act.of(String):
  match m:
    case Some{+t}:
      token_src2(String.eq(t, "-"), t, noin)
    case None{}:
      line_or_stop(noin)

def token_run2(empty: Bool, +ctx: SBase.Ctx, +t: String, +email: Maybe<&2, String>, +slot: Maybe<&2, U32>, +noin: Bool) -> Act.of(Cmd.Out):
  match empty:
    case True{}:
      Act.fail(Cmd.Out, 2, "Token cannot be empty")
    case False{}:
      Act.bind(String, Cmd.Out, with_overwrite(SOps.add_token(ctx, t, email, slot, False{}), SOps.add_token(ctx, t, email, slot, True{}), noin),
        out => after_write(SBase.root_of(ctx), out))

def token_run(+ctx: SBase.Ctx, +token: String, email: Maybe<&2, String>, slot: Maybe<&2, U32>, +noin: Bool) -> Act.of(Cmd.Out):
  token_run2(String.is_empty(String.trim(token)), ctx, String.trim(token), email, slot, noin)

def add_token_cmd(+ctx: SBase.Ctx, src: Maybe<&2, String>, email: Maybe<&2, String>, slot: Maybe<&2, U32>, +ni: Ni) -> Act.of(Cmd.Out):
  Act.bind(String, Cmd.Out, token_src(src, ni_noin(ni)), t => token_run(ctx, t, email, slot, ni_noin(ni)))

def remove_answer(yes: Bool, +prompt: String, +ctx: SBase.Ctx, +num: String) -> Act.of(Cmd.Out):
  match yes:
    case True{}:
      Act.bind(String, Cmd.Out, SOps.remove(ctx, num), t => Act.pure(Cmd.Out, Cmd.Out{0, prompt ++ t ++ "\n", ""}))
    case False{}:
      Act.pure(Cmd.Out, Cmd.Out{0, prompt ++ "Cancelled\n", ""})

def remove_ask(+ctx: SBase.Ctx, +num: String, +email: String) -> Act.of(Cmd.Out):
  Act.bind(String, Cmd.Out, Clibase.read_line(), a => remove_answer(Clibase.is_yes(a), "Are you sure you want to permanently remove Account-" ++ num ++ " (" ++ email ++ ")? [y/N] ", ctx, num))

def remove_now(+ctx: SBase.Ctx, +num: String) -> Act.of(Cmd.Out):
  Act.bind(String, Cmd.Out, SOps.remove(ctx, num), t => Act.pure(Cmd.Out, Cmd.ok(t)))

def remove_gate(noin: Bool, +ctx: SBase.Ctx, +num: String, +email: String) -> Act.of(Cmd.Out):
  match noin:
    case True{}:
      Act.fail(Cmd.Out, 2, "removing Account-" ++ num ++ " needs confirmation; pass --yes")
    case False{}:
      remove_ask(ctx, num, email)

def remove_confirm(yes: Bool, noin: Bool, +ctx: SBase.Ctx, +num: String, +email: String) -> Act.of(Cmd.Out):
  match yes:
    case True{}:
      remove_now(ctx, num)
    case False{}:
      remove_gate(noin, ctx, num, email)

def remove_rec(m: Maybe<&2, Json.Json>, +ctx: SBase.Ctx, +num: String, +ni: Ni) -> Act.of(Cmd.Out):
  match m:
    case None{}:
      Act.fail(Cmd.Out, 3, "Account-" ++ num ++ " does not exist")
    case Some{rec}:
      remove_confirm(ni_yes(ni), ni_noin(ni), ctx, num, SSeq.field_str(rec, "email"))

def remove_res(r: SSeq.Resolved, +ctx: SBase.Ctx, +seq: Json.Json, +ident: String, +ni: Ni) -> Act.of(Cmd.Out):
  match r:
    case SSeq.RNone{}:
      Act.fail(Cmd.Out, 3, "No account found with identifier: " ++ ident)
    case SSeq.RAmb{msg}:
      Act.fail(Cmd.Out, 1, msg)
    case SSeq.RSlot{+n}:
      remove_rec(SSeq.slot_record(seq, n), ctx, n, ni)

def remove_seq(m: Maybe<&2, Json.Json>, +ctx: SBase.Ctx, +ident: String, +ni: Ni) -> Act.of(Cmd.Out):
  match m:
    case None{}:
      Act.fail(Cmd.Out, 1, "No accounts are managed yet")
    case Some{+seq}:
      remove_res(SSeq.resolve(seq, ident), ctx, seq, ident, ni)

def remove_cmd(+ctx: SBase.Ctx, +ident: String, +ni: Ni) -> Act.of(Cmd.Out):
  Act.bind(Maybe<&2, Json.Json>, Cmd.Out, SIo.read_seq(SBase.root_of(ctx)), m => remove_seq(m, ctx, ident, ni))

def source_pick(ex: Bool, +path: String) -> Act.of(String):
  match ex:
    case True{}:
      Fs.read_file(path)
    case False{}:
      Act.fail(String, 4, "usage file not found: " ++ path)

def source_text(+path: String) -> Act.of(String):
  Act.bind(Bool, String, Act.lift(Bool, Fs.exists(path)), ex => source_pick(ex, path))

def source_dash(dash: Bool, +path: String) -> Act.of(String):
  match dash:
    case True{}:
      IO.bind(Fs.Res(String), Fs.Res(String), Fs.read_stdin(), r => IO.pure(Fs.Res(String), r))
    case False{}:
      source_text(path)

def source_of(+path: String) -> Act.of(String):
  source_dash(String.eq(path, "-"), path)

def slot_of_reading(+r: Urec.Reading) -> String:
  match r:
    case Urec.Reading{id, usage, age}:
      Ustore.slot_of(id)

def email_of_reading(+r: Urec.Reading) -> String:
  match r:
    case Urec.Reading{Ustore.Id{slot, email, org}, usage, age}:
      email

def adopt_line(yes: Bool, +r: Urec.Reading) -> String:
  match yes:
    case True{}:
      "Adopted usage for " ++ email_of_reading(r) ++ " \u{2192} slot " ++ slot_of_reading(r) ++ "\n"
    case False{}:
      "Kept slot " ++ slot_of_reading(r) ++ "'s own reading for " ++ email_of_reading(r) ++ ": it is newer\n"

def adopt_lines(rs: List<&2, Urec.Reading>, +adopted: List<&2, String>) -> String:
  match rs:
    case Nil{}:
      ""
    case Con{+r, t}:
      adopt_line(Importu.has_slot(slot_of_reading(r), adopted), r) ++ adopt_lines(t, adopted)

def hold_text(any: Bool, +h: U32) -> String:
  match any:
    case True{}:
      Clock.sel.s(U32.is_gt(h, 0), "; fetching held for up to " ++ U32.show(h) ++ "s", "; holds lifted")
    case False{}:
      ""

def hold_note(hold: Maybe<&2, U32>, +any: Bool) -> String:
  match hold:
    case Some{h}:
      hold_text(any, h)
    case None{}:
      ""

def summary(+adopted: Nat, +kept: Nat, +skipped: U32, hold: Maybe<&2, U32>, +any: Bool) -> String:
  "Done: " ++ Nat.show(adopted) ++ " adopted, " ++ Nat.show(kept) ++ " kept, " ++ U32.show(skipped) ++ " skipped" ++ hold_note(hold, any)

def import_report(+rs: List<&2, Urec.Reading>, +skipped: U32, hold: Maybe<&2, U32>, ar: Urec.AR) -> Cmd.Out:
  match ar:
    case Urec.AR{rows, +adopted, kept}:
      Cmd.Out{0, "", adopt_lines(rs, adopted) ++ summary(List.length(&2, String, adopted), List.length(&2, String, kept), skipped, hold, Bool.not(List.is_empty(&2, Urec.Reading, rs))) ++ "\n"}

def adopt_run(+root: String, +rs: List<&2, Urec.Reading>, +skipped: U32, +hold: Maybe<&2, U32>, +now: U32) -> Act.of(Cmd.Out):
  Act.bind(Urec.AR, Cmd.Out, Urec.adopt(root, rs, hold, now), ar => Act.pure(Cmd.Out, import_report(rs, skipped, hold, ar)))

def import_plan_run(r: Result<&2, &2, String, Importu.Plan>, +root: String, hold: Maybe<&2, U32>, +now: U32) -> Act.of(Cmd.Out):
  match r:
    case Fail{e}:
      Act.fail(Cmd.Out, 4, e)
    case Done{Importu.Plan{rs, sk}}:
      adopt_run(root, rs, sk, hold, now)

def import_seq(m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case Some{j}:
      j
    case None{}:
      Json.of_pairs([])

def import_with(+ctx: SBase.Ctx, +text: String, hold: Maybe<&2, U32>, tm: Clibase.Tm, m: Maybe<&2, Json.Json>) -> Act.of(Cmd.Out):
  match tm:
    case Clibase.Tm{+now, off, tick}:
      import_plan_run(Importu.import_plan(text, import_seq(m), now, off), SBase.root_of(ctx), hold, now)

def import_run(+ctx: SBase.Ctx, +text: String, hold: Maybe<&2, U32>) -> Act.of(Cmd.Out):
  do Clibase.ActM<Cmd.Out>:
    tm : Clibase.Tm <- Clibase.times()
    m : Maybe<&2, Json.Json> <- SIo.read_seq(SBase.root_of(ctx))
    import_with(ctx, text, hold, tm, m)

def import_cmd(+ctx: SBase.Ctx, +path: String, hold: Maybe<&2, U32>) -> Act.of(Cmd.Out):
  Act.bind(String, Cmd.Out, source_of(path), text => import_run(ctx, text, hold))
