import Base
import ../json.bend as Json
import ./ylex.bend as L
import ./yscal.bend as S

# The YAML reader: the block subset cswap writes plus plain block maps, block
# sequences and scalars. Supported: `key: value`, `key:` with an indented
# block (or a `- ` sequence at the key's own indent), `- item`, `- key: v`
# (a mapping that starts on the dash line), `[]`, `{}`, flat flow `[a, b]` and
# `{a: 1}`, plain / 'single' / "double" quoted scalars (JSON escapes), comments,
# a leading `---`. Not supported (a clear error): tabs for indentation,
# anchors/aliases/tags, block scalars (| >), multi-line scalars, several
# documents.
#
# The structure is found without mutual recursion: lines are split into the
# entries of a block (by indent), and one fuel-bounded `val` walks plans.

type Ln is Data:
  Ln{ind: Nat, text: String}

# What `val` does next.
type Plan is Data:
  PRes{r: Result<&2, &2, String, Json.Json>}
  PBlk{ls: List<&2, Ln>}
  PArr{es: List<&2, List<&2, Ln>>}
  PObj{es: List<&2, List<&2, Ln>>}
  PItems{b: List<&2, Ln>, r: List<&2, List<&2, Ln>>}
  PFieldI{k: String, v: Result<&2, &2, String, Json.Json>, r: List<&2, List<&2, Ln>>}
  PFieldB{k: String, b: List<&2, Ln>, r: List<&2, List<&2, Ln>>}

# ---- lines -------------------------------------------------------------------------

# Leading spaces; a tab in the indentation is an error (-1 is not a Nat, so
# the flag travels beside).
def lead.count(s: String, +n: Nat) -> Nat:
  match s:
    case SCon{Chr{c}, t}:
      Bool.pick(Nat, U32.is_eq(c, 32), lead.count(t, Nat.add(n, 1n)), n)
    case SNil{}:
      n

def tab_lead(s: String) -> Bool:
  match s:
    case SCon{Chr{+c}, t}:
      Bool.pick(Bool, U32.is_eq(c, 32), tab_lead(t), U32.is_eq(c, 9))
    case SNil{}:
      False{}

def is_comment(+t: String) -> Bool:
  String.is_empty(t) || U32.is_eq(S.first_code(t), 35)

type Acc is Data:
  Acc{ls: List<&2, Ln>, seen: Bool, err: String}

def acc.add(+a: Acc, +raw: String) -> Acc:
  match a:
    case Acc{ls, seen, err}:
      Acc{Ln{lead.count(raw, 0n), String.trim_start(raw)} <> ls, True{}, err}

def acc.fail(+a: Acc, msg: String) -> Acc:
  match a:
    case Acc{ls, seen, err}:
      Acc{ls, seen, Bool.pick(String, String.is_empty(err), msg, err)}

def acc.skip(+a: Acc) -> Acc:
  a

def acc.marker(+a: Acc, +seen: Bool) -> Acc:
  Bool.pick(Acc, seen, acc.fail(a, "several documents are not supported"), a)

def acc.seen(+a: Acc) -> Bool:
  match a:
    case Acc{ls, seen, err}:
      seen

def acc.line2(blank: Bool, marker: Bool, tab: Bool, +a: Acc, +raw: String) -> Acc:
  match blank marker tab:
    case True{} _ _:
      a
    case False{} True{} _:
      acc.marker(a, acc.seen(a))
    case False{} False{} True{}:
      acc.fail(a, "tabs are not allowed for indentation")
    case False{} False{} False{}:
      acc.add(a, raw)

def acc.line(+a: Acc, +raw: String) -> Acc:
  acc.line2(is_comment(String.trim_start(raw)), String.eq(String.trim_end(raw), "---"), tab_lead(raw), a, String.trim_end(raw))

def acc.go(rs: List<&2, String>, +a: Acc) -> Acc:
  match rs:
    case Nil{}:
      a
    case Con{r, t}:
      acc.go(t, acc.line(a, r))

def lines.fin(+a: Acc) -> Result<&2, &2, String, List<&2, Ln>>:
  match a:
    case Acc{ls, seen, err}:
      Bool.pick(Result<&2, &2, String, List<&2, Ln>>, String.is_empty(err), Done{List.reverse(&2, Ln, ls)}, Fail{err})

def lines_of(+text: String) -> Result<&2, &2, String, List<&2, Ln>>:
  lines.fin(acc.go(String.split(text, '\n'), Acc{[], False{}, ""}))

# ---- splitting a block into entries ---------------------------------------------------

def all_ge(ls: List<&2, Ln>, +n: Nat) -> Bool:
  match ls:
    case Nil{}:
      True{}
    case Con{Ln{i, t}, r}:
      Nat.is_ge(i, n) && all_ge(r, n)

def is_dash(+t: String) -> Bool:
  String.eq(t, "-") || String.starts_with(t, "- ")

def key_empty.of(kv: S.KV) -> Bool:
  match kv:
    case S.KOk{k, rest}:
      String.is_empty(rest)
    case _:
      False{}

def key_empty(+t: String) -> Bool:
  key_empty.of(S.split_kv(t))

type Sp is Data:
  Sp{done: List<&2, List<&2, Ln>>, cur: List<&2, Ln>, hold: Bool}

def sp.start(+sp: Sp, +l: Ln, hold: Bool) -> Sp:
  match sp:
    case Sp{done, cur, h}:
      Sp{Bool.pick(List<&2, List<&2, Ln>>, List.is_empty(&2, Ln, cur), done, List.reverse(&2, Ln, cur) <> done), [l], hold}

def sp.more(+sp: Sp, +l: Ln) -> Sp:
  match sp:
    case Sp{done, cur, h}:
      Sp{done, l <> cur, h}

def sp.hold(+sp: Sp) -> Bool:
  match sp:
    case Sp{done, cur, h}:
      h

# A line at the block's indent opens an entry, except a `- ` line right under
# an empty `key:` of a mapping (the sequence PyYAML writes at the key's indent).
def sp.step2(new: Bool, +sp: Sp, +l: Ln, +t: String) -> Sp:
  match new:
    case True{}:
      sp.start(sp, l, key_empty(t))
    case False{}:
      sp.more(sp, l)

def sp.step(+n: Nat, +map: Bool, +sp: Sp, +l: Ln) -> Sp:
  match l:
    case Ln{i, t}:
      sp.step2(Nat.is_eq(i, n) && Bool.not(map && sp.hold(sp) && is_dash(t)), sp, Ln{i, t}, t)

def sp.go(ls: List<&2, Ln>, +n: Nat, +map: Bool, +sp: Sp) -> Sp:
  match ls:
    case Nil{}:
      sp
    case Con{l, t}:
      sp.go(t, n, map, sp.step(n, map, sp, l))

def sp.fin(+sp: Sp) -> List<&2, List<&2, Ln>>:
  match sp:
    case Sp{done, cur, h}:
      List.reverse(&2, List<&2, Ln>, Bool.pick(List<&2, List<&2, Ln>>, List.is_empty(&2, Ln, cur), done, List.reverse(&2, Ln, cur) <> done))

def split(ls: List<&2, Ln>, +n: Nat, +map: Bool) -> List<&2, List<&2, Ln>>:
  sp.fin(sp.go(ls, n, map, Sp{[], [], False{}}))

# ---- plans ---------------------------------------------------------------------------

def bad(msg: String) -> Plan:
  PRes{Fail{msg}}

def item.text(+t: String) -> String:
  Bool.pick(String, String.eq(t, "-"), "", String.trim_start(String.drop(t, 1n)))

def item.rest(+r: String) -> String:
  Bool.pick(String, String.is_empty(S.uncomment(r)), "", r)

def item.block(+n: Nat, +t: String, +rest: String, +body: List<&2, Ln>) -> List<&2, Ln>:
  Bool.pick(List<&2, Ln>, String.is_empty(rest), body, Ln{Nat.add(n, Nat.sub(String.length(t), String.length(rest))), rest} <> body)

def items.head(dash: Bool, +n: Nat, +t: String, body: List<&2, Ln>, r: List<&2, List<&2, Ln>>) -> Plan:
  match dash:
    case True{}:
      PItems{item.block(n, t, item.rest(item.text(t)), body), r}
    case False{}:
      bad("expected '- ' to start a sequence item")

def plan.items(es: List<&2, List<&2, Ln>>) -> Plan:
  match es:
    case Nil{}:
      PRes{Done{Json.JNil{}}}
    case Con{Con{Ln{n, +t}, body}, r}:
      items.head(is_dash(t), n, t, body, r)
    case Con{Nil{}, r}:
      bad("empty sequence entry")

def field.extra(v: Result<&2, &2, String, Json.Json>, +k: String) -> Plan:
  match v:
    case Fail{e}:
      bad(e)
    case Done{x}:
      bad("unexpected indented lines after the value of '" ++ k ++ "'")

def field.both(no_body: Bool, +k: String, +rest: String, r: List<&2, List<&2, Ln>>) -> Plan:
  match no_body:
    case True{}:
      PFieldI{k, S.scalar(rest), r}
    case False{}:
      field.extra(S.scalar(rest), k)

def field.inline(empty: Bool, +k: String, +rest: String, body: List<&2, Ln>, r: List<&2, List<&2, Ln>>) -> Plan:
  match empty:
    case True{}:
      PFieldB{k, body, r}
    case False{}:
      field.both(List.is_empty(&2, Ln, body), k, rest, r)

def field.kv(kv: S.KV, body: List<&2, Ln>, r: List<&2, List<&2, Ln>>) -> Plan:
  match kv:
    case S.KOk{k, +rest}:
      field.inline(String.is_empty(S.uncomment(rest)), k, rest, body, r)
    case S.KBad{m}:
      bad(m)
    case S.KNone{}:
      bad("expected 'key: value'")

def plan.fields(es: List<&2, List<&2, Ln>>) -> Plan:
  match es:
    case Nil{}:
      PRes{Done{Json.JNil{}}}
    case Con{Con{Ln{n, t}, body}, r}:
      field.kv(S.split_kv(t), body, r)
    case Con{Nil{}, r}:
      bad("empty mapping entry")

type BKind is Data:
  KSeq{}
  KMap{}
  KScalar{}

def kind.of2(dash: Bool, kv: S.KV) -> BKind:
  match dash kv:
    case True{} _:
      KSeq{}
    case False{} S.KNone{}:
      KScalar{}
    case False{} _:
      KMap{}

def kind.of(+t: String) -> BKind:
  kind.of2(is_dash(t), S.split_kv(t))

def blk.scalar(single: Bool, +t: String) -> Plan:
  match single:
    case True{}:
      PRes{S.scalar(t)}
    case False{}:
      bad("unexpected indentation")

def blk.kind(k: BKind, +n: Nat, +t: String, ls: List<&2, Ln>, +all: List<&2, Ln>) -> Plan:
  match k:
    case KSeq{}:
      PArr{split(all, n, False{})}
    case KMap{}:
      PObj{split(all, n, True{})}
    case KScalar{}:
      blk.scalar(List.is_empty(&2, Ln, ls), t)

def blk.fit(ok: Bool, +n: Nat, +t: String, ls: List<&2, Ln>, +all: List<&2, Ln>) -> Plan:
  match ok:
    case True{}:
      blk.kind(kind.of(t), n, t, ls, all)
    case False{}:
      bad("inconsistent indentation")

def plan.blk(+ls: List<&2, Ln>) -> Plan:
  match ls:
    case Nil{}:
      PRes{Done{Json.JNull{}}}
    case Con{Ln{n, t}, rest}:
      blk.fit(all_ge(rest, n), n, t, rest, Con{Ln{n, t}, rest})

# ---- the walk --------------------------------------------------------------------------

def item.cons(x: Result<&2, &2, String, Json.Json>, rest: Result<&2, &2, String, Json.Json>) -> Result<&2, &2, String, Json.Json>:
  S.item.cons(x, rest)

def val(fuel: Nat, pl: Plan) -> Result<&2, &2, String, Json.Json>:
  match fuel pl:
    case 0n _:
      Fail{"nesting too deep"}
    case 1n++p PRes{r}:
      r
    case 1n++p PBlk{ls}:
      val(p, plan.blk(ls))
    case 1n++p PArr{es}:
      S.wrap.arr(val(p, plan.items(es)))
    case 1n++p PObj{es}:
      S.wrap.obj(val(p, plan.fields(es)))
    case 1n++p PItems{b, r}:
      item.cons(val(p, PBlk{b}), val(p, plan.items(r)))
    case 1n++p PFieldI{k, v, r}:
      S.field.cons(k, v, val(p, plan.fields(r)))
    case 1n++p PFieldB{k, b, r}:
      S.field.cons(k, val(p, PBlk{b}), val(p, plan.fields(r)))

def parse.run(ls: List<&2, Ln>, +fuel: Nat) -> Result<&2, &2, String, Json.Json>:
  val(fuel, PBlk{ls})

def parse.lines(r: Result<&2, &2, String, List<&2, Ln>>) -> Result<&2, &2, String, Json.Json>:
  match r:
    case Fail{e}:
      Fail{e}
    case Done{+ls}:
      parse.run(ls, Nat.add(Nat.mul(4n, List.length(&2, Ln, ls)), 8n))

# The value of a YAML document in the supported subset; `Fail` says what is not.
def parse(+text: String) -> Result<&2, &2, String, Json.Json>:
  parse.lines(lines_of(text))
