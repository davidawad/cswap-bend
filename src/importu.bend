import Base
import ./urec.bend as Urec
import ./store/seq.bend as SSeq
import ./usage/text.bend as UText
import ./json.bend as Json
import ./clock.bend as Clock
import ./view.bend as View
import ./ustore.bend as Ustore

# `import-usage`: read another machine's `list --json` document and validate
# every row before anything is written (transfer.py import_usage). The result
# is the readings to adopt, how many rows were skipped, or the TransferError.

def jv(+k: String, +j: Json.Json) -> Json.Json:
  Maybe.default(&2, Json.Json, Json.get(k, j), Json.JNull{})

def neg.pick(neg: Bool, +s: String) -> Maybe<&2, String>:
  match neg:
    case True{}:
      None{}
    case False{}:
      Some{s}

def nonneg(m: Maybe<&2, String>) -> Maybe<&2, String>:
  match m:
    case Some{+s}:
      neg.pick(String.starts_with(s, "-"), s)
    case None{}:
      None{}

def ok_float(t: String) -> Maybe<&2, String>:
  nonneg(UText.float(t))

# A JSON number that is finite and not negative, as Python-float text.
def num_text(j: Json.Json) -> Maybe<&2, String>:
  match j:
    case Json.JNum{t}:
      ok_float(t)
    case _:
      None{}

def with_reset(+s: String, +out: Json.Json, +now: U32, +off: U32) -> Json.Json:
  View.with_cell(Json.set("resets_at", Json.JStr{s}, out), View.fresh(Json.of_pairs([("resets_at", Json.JStr{s})]), now, off))

def win.parse(+label: String, +s: String, t: Maybe<&2, U32>, out: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Json.Json>:
  match t:
    case None{}:
      Fail{label ++ ".resetsAt is not an ISO-8601 time: '" ++ s ++ "'"}
    case Some{u}:
      Done{with_reset(s, out, now, off)}

def win.reset(+label: String, +resets: Json.Json, out: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Json.Json>:
  match resets:
    case Json.JNull{}:
      Done{out}
    case Json.JStr{s}:
      win.parse(label, s, Clock.parse_iso8601(s), out, now, off)
    case _:
      Fail{label ++ ".resetsAt must be an ISO-8601 string"}

def win.pct(m: Maybe<&2, String>, +label: String, +w: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Json.Json>:
  match m:
    case None{}:
      Fail{label ++ ".pct must be a non-negative number"}
    case Some{p}:
      win.reset(label, jv("resetsAt", w), Json.of_pairs([("pct", Json.JNum{p})]), now, off)

def win.obj(w: Json.Json, +label: String, +now: U32, +off: U32) -> Result<&2, &2, String, Json.Json>:
  match w:
    case Json.JObj{+f}:
      win.pct(num_text(jv("pct", w)), label, w, now, off)
    case _:
      Fail{label ++ " must be an object"}

# One window back to the stored shape, fetch-time strings rebuilt.
def window(+w: Json.Json, +label: String, +now: U32, +off: U32) -> Result<&2, &2, String, Json.Json>:
  win.obj(w, label, now, off)

def put.res(+k: String, r: Result<&2, &2, String, Json.Json>, acc: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  match r acc:
    case Fail{e} _:
      Fail{e}
    case Done{v} Fail{e}:
      Fail{e}
    case Done{v} Done{a}:
      Done{Json.set(k, v, a)}

def put_win(+k: String, +label: String, +w: Maybe<&2, Json.Json>, +now: U32, +off: U32, acc: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  match w:
    case None{}:
      acc
    case Some{x}:
      put.res(k, window(x, label, now, off), acc)

def spend.num2(m: Maybe<&2, String>, +k: String, out: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match m:
    case Some{t}:
      Done{Json.set(k, Json.JNum{t}, out)}
    case None{}:
      Fail{"spend." ++ k ++ " must be a number"}

# Any finite number (the spend amounts may be signed).
def num_any(j: Json.Json) -> Maybe<&2, String>:
  match j:
    case Json.JNum{t}:
      UText.float(t)
    case _:
      None{}

def spend.num(+k: String, +s: Json.Json, out: Json.Json) -> Result<&2, &2, String, Json.Json>:
  spend.num2(num_any(jv(k, s)), k, out)

def spend.cur(cur: Json.Json, r: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  match cur r:
    case _ Fail{e}:
      Fail{e}
    case Json.JStr{c} Done{o}:
      Done{Json.set("currency", Json.JStr{c}, o)}
    case _ Done{o}:
      Fail{"spend.currency must be a string"}

def spend.limit(+s: Json.Json, r: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{o}:
      spend.cur(jv("currency", s), spend.num("limit", s, o))

def spend.chain(+s: Json.Json, w: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  match w:
    case Fail{e}:
      Fail{e}
    case Done{o}:
      spend.limit(s, spend.num("used", s, o))

def spend.of(+s: Json.Json, w: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  spend.chain(s, w)

def put_spend2(m: Maybe<&2, Json.Json>, +now: U32, +off: U32, acc: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  match m:
    case None{}:
      acc
    case Some{+s}:
      put.res("spend", spend.of(s, window(s, "spend", now, off)), acc)

def put_spend(+u: Json.Json, +now: U32, +off: U32, acc: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  put_spend2(Json.get("spend", u), now, off, acc)

def name.keep(empty: Bool, +n: String, +label: String, out: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match empty:
    case True{}:
      Fail{label ++ ".name must be a non-empty string"}
    case False{}:
      Done{Json.set("name", Json.JStr{n}, out)}

def name.of(m: Maybe<&2, String>, +label: String, out: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match m:
    case Some{+n}:
      name.keep(String.is_empty(n), n, label, out)
    case None{}:
      Fail{label ++ ".name must be a non-empty string"}

def scoped.entry(r: Result<&2, &2, String, Json.Json>, +w: Json.Json, +label: String) -> Result<&2, &2, String, Json.Json>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{o}:
      name.of(Json.as_string(jv("name", w)), label, o)

def scoped.add(e: Result<&2, &2, String, Json.Json>, acc: Result<&2, &2, String, List<&2, Json.Json>>) -> Result<&2, &2, String, List<&2, Json.Json>>:
  match e acc:
    case Fail{m} _:
      Fail{m}
    case Done{v} Fail{m}:
      Fail{m}
    case Done{v} Done{xs}:
      Done{List.append(&2, Json.Json, xs, [v])}

def scoped.list(ls: List<&2, Json.Json>, +i: Nat, +now: U32, +off: U32, acc: Result<&2, &2, String, List<&2, Json.Json>>) -> Result<&2, &2, String, List<&2, Json.Json>>:
  match ls:
    case Nil{}:
      acc
    case Con{+w, t}:
      scoped.list(t, 1n+i, now, off, scoped.add(scoped.entry(window(w, "scoped[" ++ Nat.show(i) ++ "]", now, off), w, "scoped[" ++ Nat.show(i) ++ "]"), acc))

def scoped.put(r: Result<&2, &2, String, List<&2, Json.Json>>, acc: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  match r acc:
    case Fail{e} _:
      Fail{e}
    case Done{xs} Fail{e}:
      Fail{e}
    case Done{xs} Done{a}:
      Done{Json.set("scoped", Json.arr(xs), a)}

def put_scoped2(m: Maybe<&2, Json.Json>, +now: U32, +off: U32, acc: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  match m:
    case None{}:
      acc
    case Some{Json.JArr{items}}:
      scoped.put(scoped.list(Json.to_list(Json.JArr{items}), 0n, now, off, Done{[]}), acc)
    case Some{x}:
      Fail{"scoped must be a list"}

def put_scoped(+u: Json.Json, +now: U32, +off: U32, acc: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  put_scoped2(Json.get("scoped", u), now, off, acc)

def nonempty_keys(ks: List<&2, String>, o: Json.Json) -> Result<&2, &2, String, Json.Json>:
  match ks:
    case Nil{}:
      Fail{"usage carries no windows"}
    case Con{h, t}:
      Done{o}

def nonempty_res(r: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+o}:
      nonempty_keys(Json.keys(o), o)

def usage.fields(+u: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Json.Json>:
  nonempty_res(put_scoped(u, now, off, put_spend(u, now, off,
    put_win("seven_day", "sevenDay", Json.get("sevenDay", u), now, off,
      put_win("five_hour", "fiveHour", Json.get("fiveHour", u), now, off, Done{Json.of_pairs([])})))))

def usage.obj(+u: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Json.Json>:
  match u:
    case Json.JObj{f}:
      usage.fields(u, now, off)
    case _:
      Fail{"usage must be an object"}

# usage_from_json: the stored usage shape from a `list --json` usage object.
def usage_from_json(+u: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Json.Json>:
  usage.obj(u, now, off)

# Rows accepted so far, rows skipped, and the first error (TransferError text).
type IA is Data:
  IA{readings: List<&2, Urec.Reading>, skipped: U32, slots: List<&2, String>, err: String}

def ia.err(msg: String, ia: IA) -> IA:
  match ia:
    case IA{rs, sk, slots, err}:
      IA{rs, sk, slots, msg}

def ia.skip(ia: IA) -> IA:
  match ia:
    case IA{rs, sk, slots, err}:
      IA{rs, (sk + 1 : U32), slots, err}

def has_slot(+s: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      String.eq(h, s) || has_slot(s, t)

def org_label(+org: String) -> String:
  Clock.sel.s(String.is_empty(org), "personal", org)

def ia.add(+id: Ustore.Id, +usage: Json.Json, +age: U32, ia: IA) -> IA:
  match ia:
    case IA{rs, sk, slots, err}:
      IA{Urec.Reading{id, usage, age} <> rs, sk, Ustore.slot_of(id) <> slots, err}

def ia.dup(dup: Bool, +id: Ustore.Id, +email: String, +org: String, +usage: Json.Json, +age: U32, ia: IA) -> IA:
  match dup:
    case True{}:
      ia.err("duplicate account in usage document: " ++ email ++ " (org=" ++ org_label(org) ++ ")", ia)
    case False{}:
      ia.add(id, usage, age, ia)

def ia.dup2(+slot: String, +email: String, +org: String, +usage: Json.Json, +age: U32, ia: IA) -> IA:
  match ia:
    case IA{rs, sk, +slots, err}:
      ia.dup(has_slot(slot, slots), Ustore.Id{slot, email, org}, email, org, usage, age, IA{rs, sk, slots, err})

def ia.slot(m: Maybe<&2, String>, +email: String, +org: String, +usage: Json.Json, +age: U32, ia: IA) -> IA:
  match m:
    case None{}:
      ia.skip(ia)
    case Some{+slot}:
      ia.dup2(slot, email, org, usage, age, ia)

def ia.usage(r: Result<&2, &2, String, Json.Json>, +email: String, +org: String, +age: U32, +seq: Json.Json, ia: IA) -> IA:
  match r:
    case Fail{e}:
      ia.err("usage for " ++ email ++ ": " ++ e, ia)
    case Done{u}:
      ia.slot(SSeq.find_slot(seq, email, org), email, org, u, age, ia)

def age.int(ps: List<&2, String>) -> Maybe<&2, U32>:
  match ps:
    case Con{i, t}:
      U32.read(i)
    case Nil{}:
      None{}

def age_secs(m: Maybe<&2, String>) -> Maybe<&2, U32>:
  match m:
    case Some{t}:
      age.int(String.split(t, '.'))
    case None{}:
      None{}

def ia.age(m: Maybe<&2, U32>, +row: Json.Json, +email: String, +org: String, +seq: Json.Json, +now: U32, +off: U32, ia: IA) -> IA:
  match m:
    case None{}:
      ia.err("usageAgeSeconds for " ++ email ++ " must be a non-negative number", ia)
    case Some{+age}:
      ia.usage(usage_from_json(jv("usage", row), now, off), email, org, age, seq, ia)

def ia.status(ok: Bool, +row: Json.Json, +email: String, +org: String, +seq: Json.Json, +now: U32, +off: U32, ia: IA) -> IA:
  match ok:
    case False{}:
      ia.skip(ia)
    case True{}:
      ia.age(age_secs(num_text(jv("usageAgeSeconds", row))), row, email, org, seq, now, off, ia)

def is_ok_status(j: Json.Json) -> Bool:
  match j:
    case Json.JStr{s}:
      String.eq(s, "ok")
    case _:
      False{}

def ia.ident3(empty: Bool, +e: String, +o: String, +row: Json.Json, +seq: Json.Json, +now: U32, +off: U32, ia: IA) -> IA:
  match empty:
    case True{}:
      ia.err("each account row needs an email and an organizationUuid", ia)
    case False{}:
      ia.status(is_ok_status(jv("usageStatus", row)), row, e, o, seq, now, off, ia)

def ia.ident2(+e: String, +o: String, +row: Json.Json, +seq: Json.Json, +now: U32, +off: U32, ia: IA) -> IA:
  ia.ident3(String.is_empty(e), e, o, row, seq, now, off, ia)

def ia.identity(email: Maybe<&2, String>, org: Json.Json, +row: Json.Json, +seq: Json.Json, +now: U32, +off: U32, ia: IA) -> IA:
  match email org:
    case Some{e} Json.JNull{}:
      ia.ident2(e, "", row, seq, now, off, ia)
    case Some{e} Json.JStr{o}:
      ia.ident2(e, o, row, seq, now, off, ia)
    case _ _:
      ia.err("each account row needs an email and an organizationUuid", ia)

def ia.row(+row: Json.Json, +seq: Json.Json, +now: U32, +off: U32, ia: IA) -> IA:
  match row:
    case Json.JObj{f}:
      ia.identity(Json.as_string(jv("email", row)), jv("organizationUuid", row), row, seq, now, off, ia)
    case _:
      ia.err("each account row must be a JSON object", ia)

def ia.go1(live: Bool, +row: Json.Json, +seq: Json.Json, +now: U32, +off: U32, ia: IA) -> IA:
  match live:
    case True{}:
      ia.row(row, seq, now, off, ia)
    case False{}:
      ia

def ia.step(+row: Json.Json, +seq: Json.Json, +now: U32, +off: U32, ia: IA) -> IA:
  match ia:
    case IA{rs, sk, slots, +err}:
      ia.go1(String.is_empty(err), row, seq, now, off, IA{rs, sk, slots, err})

def ia.rows(rs: List<&2, Json.Json>, +seq: Json.Json, +now: U32, +off: U32, ia: IA) -> IA:
  match rs:
    case Nil{}:
      ia
    case Con{h, t}:
      ia.rows(t, seq, now, off, ia.step(h, seq, now, off, ia))

# What an import will do: the readings to adopt (with their identities) and
# how many rows were skipped.
type Plan is Data:
  Plan{readings: List<&2, Urec.Reading>, skipped: U32}

def plan.err(ok: Bool, err: String, p: Plan) -> Result<&2, &2, String, Plan>:
  match ok:
    case True{}:
      Done{p}
    case False{}:
      Fail{err}

def plan.of(ia: IA) -> Result<&2, &2, String, Plan>:
  match ia:
    case IA{rs, sk, slots, +err}:
      plan.err(String.is_empty(err), err, Plan{List.reverse(&2, Urec.Reading, rs), sk})

def plan.accounts(m: Maybe<&2, Json.Json>, +seq: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Plan>:
  match m:
    case Some{Json.JArr{items}}:
      plan.of(ia.rows(Json.to_list(Json.JArr{items}), seq, now, off, IA{[], 0, [], ""}))
    case _:
      Fail{"usage document has no accounts list"}

def version_text(j: Json.Json) -> String:
  match j:
    case Json.JNum{t}:
      t
    case Json.JStr{s}:
      "'" ++ s ++ "'"
    case Json.JNull{}:
      "None"
    case _:
      "?"

def plan.version(ok: Bool, +t: String, +doc: Json.Json, +seq: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Plan>:
  match ok:
    case True{}:
      plan.accounts(Json.get("accounts", doc), seq, now, off)
    case False{}:
      Fail{"unsupported usage document schemaVersion: " ++ t ++ " (expected 1, as printed by 'cswap list --json')"}

def plan.doc2(ver: Json.Json, +doc: Json.Json, +seq: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Plan>:
  match ver:
    case Json.JNum{+t}:
      plan.version(String.eq(t, "1"), t, doc, seq, now, off)
    case v:
      Fail{"unsupported usage document schemaVersion: " ++ version_text(v) ++ " (expected 1, as printed by 'cswap list --json')"}

def plan.doc(+doc: Json.Json, +seq: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Plan>:
  plan.doc2(jv("schemaVersion", doc), doc, seq, now, off)

def plan.obj(+doc: Json.Json, +seq: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Plan>:
  match doc:
    case Json.JObj{f}:
      plan.doc(doc, seq, now, off)
    case _:
      Fail{"usage document must be a JSON object"}

def plan.parsed(r: Result<&2, &2, String, Json.Json>, +seq: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Plan>:
  match r:
    case Fail{e}:
      Fail{"usage document is not valid JSON: " ++ e}
    case Done{doc}:
      plan.obj(doc, seq, now, off)

# The plan for the text of a usage document, validated whole before any write.
def import_plan(+text: String, +seq: Json.Json, +now: U32, +off: U32) -> Result<&2, &2, String, Plan>:
  plan.parsed(Json.parse(text), seq, now, off)
