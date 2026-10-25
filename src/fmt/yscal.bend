import Base
import ../json.bend as Json
import ./ylex.bend as L

# YAML scalars as the reader sees them: plain words, quoted strings, a flat
# flow sequence or mapping, and a `key: value` line. Pure.

# ---- comments -----------------------------------------------------------------

def comment.pick(hit: Bool, n: Nat, rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{n}
    case False{}:
      rest

# Where a comment starts: a `#` at the start or after a space.
def comment.find(s: String, +n: Nat, +prev: Bool) -> Maybe<&2, Nat>:
  match s:
    case SNil{}:
      None{}
    case SCon{Chr{+c}, t}:
      comment.pick(prev && U32.is_eq(c, 35), n, comment.find(t, Nat.add(n, 1n), L.is_space(c)))

def comment.cut(m: Maybe<&2, Nat>, +s: String) -> String:
  match m:
    case None{}:
      s
    case Some{n}:
      String.take(s, n)

# The text without a trailing comment, trimmed.
def uncomment(+s: String) -> String:
  String.trim(comment.cut(comment.find(s, 0n, True{}), s))

# ---- quoted strings -------------------------------------------------------------

def sq.emit(skip: Bool, +c: U32, rest: String) -> String:
  match skip:
    case True{}:
      rest
    case False{}:
      SCon{Chr{c}, rest}

# `''` inside single quotes is one quote. `prevq`: the last character was a
# kept quote.
def sq.unesc(s: String, +prevq: Bool) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{+c}, t}:
      sq.emit(prevq && U32.is_eq(c, 39), c, sq.unesc(t, Bool.not(prevq) && U32.is_eq(c, 39)))

def dq.val(r: Result<&2, &2, String, Json.Json>) -> L.JR():
  match r:
    case Done{Json.JStr{s}}:
      Done{Json.JStr{s}}
    case Done{x}:
      Fail{"bad double-quoted string"}
    case Fail{e}:
      Fail{"bad double-quoted string: " ++ e}

def first_code(s: String) -> U32:
  match s:
    case SNil{}:
      0
    case SCon{Chr{c}, t}:
      c

def unquote.q(isd: Bool, +tok: String) -> L.JR():
  match isd:
    case True{}:
      dq.val(Json.parse(tok))
    case False{}:
      Done{Json.JStr{sq.unesc(String.take(String.drop(tok, 1n), Nat.sub(String.length(tok), 2n)), False{})}}

# A quoted token (quotes included) as the string it spells.
def unquote(+tok: String) -> L.JR():
  unquote.q(U32.is_eq(first_code(tok), 34), tok)

def str_of(r: L.JR()) -> Result<&2, &2, String, String>:
  match r:
    case Done{Json.JStr{s}}:
      Done{s}
    case Done{x}:
      Fail{"expected a string"}
    case Fail{e}:
      Fail{e}

# ---- one atom ----------------------------------------------------------------------

def after_ok(+after: String) -> Bool:
  String.is_empty(after) || U32.is_eq(first_code(after), 35)

def quoted.fin(ok: Bool, +tok: String) -> L.JR():
  match ok:
    case True{}:
      unquote(tok)
    case False{}:
      Fail{"unexpected text after a quoted string"}

def quoted.tok(m: Maybe<&2, Nat>, +s: String) -> L.JR():
  match m:
    case None{}:
      Fail{"unterminated quoted string"}
    case Some{+n}:
      quoted.fin(after_ok(String.trim(String.drop(s, n))), String.take(s, n))

def special(+c: U32) -> Bool:
  U32.is_eq(c, 124) || U32.is_eq(c, 62)

def tagged(+c: U32) -> Bool:
  U32.is_eq(c, 38) || U32.is_eq(c, 42) || U32.is_eq(c, 33)

def atom.pick(isq: Bool, isb: Bool, ist: Bool, +s: String) -> L.JR():
  match isq isb ist:
    case True{} _ _:
      quoted.tok(L.token_len(s), s)
    case False{} True{} _:
      Fail{"block scalars are not supported"}
    case False{} False{} True{}:
      Fail{"anchors, aliases and tags are not supported"}
    case False{} False{} False{}:
      Done{L.resolve(uncomment(s))}

# A plain or quoted scalar (trimmed text).
def atom(+s: String) -> L.JR():
  atom.pick(U32.is_eq(first_code(s), 34) || U32.is_eq(first_code(s), 39), special(first_code(s)), tagged(first_code(s)), s)

# ---- flow collections (flat: scalars only) -------------------------------------------

type Sp is Data:
  Sp{done: List<&2, String>, cur: String, q: U32}

def sp.push(+c: U32, +sp: Sp) -> Sp:
  match sp:
    case Sp{done, cur, q}:
      Sp{done, SCon{Chr{c}, cur}, q}

def sp.cut(+sp: Sp) -> Sp:
  match sp:
    case Sp{done, cur, q}:
      Sp{String.trim(String.reverse(cur)) <> done, "", q}

def sp.quote(+c: U32, +sp: Sp) -> Sp:
  match sp:
    case Sp{done, cur, q}:
      Sp{done, SCon{Chr{c}, cur}, c}

def sp.close(+c: U32, +sp: Sp) -> Sp:
  match sp:
    case Sp{done, cur, q}:
      Sp{done, SCon{Chr{c}, cur}, 0}

def sp.outside(+c: U32, +sp: Sp) -> Sp:
  Bool.pick(Sp, U32.is_eq(c, 44), sp.cut(sp),
  Bool.pick(Sp, U32.is_eq(c, 34) || U32.is_eq(c, 39), sp.quote(c, sp), sp.push(c, sp)))

def sp.q_of(sp: Sp) -> U32:
  match sp:
    case Sp{done, cur, q}:
      q

def sp.inside(+c: U32, +sp: Sp) -> Sp:
  Bool.pick(Sp, U32.is_eq(c, sp.q_of(sp)), sp.close(c, sp), sp.push(c, sp))

def sp.step(+c: U32, +sp: Sp) -> Sp:
  Bool.pick(Sp, U32.is_eq(sp.q_of(sp), 0), sp.outside(c, sp), sp.inside(c, sp))

def sp.go(s: String, +sp: Sp) -> Sp:
  match s:
    case SNil{}:
      sp
    case SCon{Chr{c}, t}:
      sp.go(t, sp.step(c, sp))

def sp.fin(+sp: Sp) -> List<&2, String>:
  match sp:
    case Sp{done, cur, q}:
      List.reverse(&2, String, String.trim(String.reverse(cur)) <> done)

# The comma-separated pieces of a flow body, quotes respected.
def split_top(+s: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(String.trim(s)), [], sp.fin(sp.go(s, Sp{[], "", 0})))

def item.cons(x: L.JR(), rest: L.JR()) -> L.JR():
  match x rest:
    case Done{a} Done{b}:
      Done{Json.JCons{a, b}}
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

def flow.items(ps: List<&2, String>) -> L.JR():
  match ps:
    case Nil{}:
      Done{Json.JNil{}}
    case Con{+p, r}:
      item.cons(atom(p), flow.items(r))

def wrap.arr(r: L.JR()) -> L.JR():
  match r:
    case Done{c}:
      Done{Json.JArr{c}}
    case Fail{e}:
      Fail{e}

def wrap.obj(r: L.JR()) -> L.JR():
  match r:
    case Done{c}:
      Done{Json.JObj{c}}
    case Fail{e}:
      Fail{e}

def inner(+s: String) -> String:
  String.take(String.drop(s, 1n), Nat.sub(String.length(s), 2n))

def last_code(s: String) -> U32:
  first_code(String.reverse(s))

def seq.fin(closed: Bool, +s: String) -> L.JR():
  match closed:
    case True{}:
      wrap.arr(flow.items(split_top(inner(s))))
    case False{}:
      Fail{"unterminated flow sequence"}

# ---- key: value ----------------------------------------------------------------------

type KV is Data:
  KNone{}
  KBad{msg: String}
  KOk{key: String, rest: String}

# Index of the first `:` that ends a key (followed by a space or the end).
def colon.pick(hit: Bool, n: Nat, rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{n}
    case False{}:
      rest

def colon.find(s: String, +n: Nat) -> Maybe<&2, Nat>:
  match s:
    case SNil{}:
      None{}
    case SCon{Chr{c}, SNil{}}:
      colon.pick(U32.is_eq(c, 58), n, None{})
    case SCon{Chr{+c}, SCon{Chr{+d}, t}}:
      colon.pick(U32.is_eq(c, 58) && L.is_space(d), n, colon.find(SCon{Chr{d}, t}, Nat.add(n, 1n)))

def kv.plain(m: Maybe<&2, Nat>, +s: String) -> KV:
  match m:
    case None{}:
      KNone{}
    case Some{+n}:
      KOk{String.trim(String.take(s, n)), String.trim(String.drop(s, Nat.add(n, 1n)))}

def kv.colon(+k: String, +after: String) -> KV:
  match after:
    case SCon{Chr{c}, t}:
      Bool.pick(KV, U32.is_eq(c, 58) && (String.is_empty(t) || L.is_space(first_code(t))), KOk{k, String.trim(t)}, KNone{})
    case SNil{}:
      KNone{}

def kv.after(r: Result<&2, &2, String, String>, +after: String) -> KV:
  match r:
    case Fail{e}:
      KBad{e}
    case Done{k}:
      kv.colon(k, after)

def kv.quoted(m: Maybe<&2, Nat>, +s: String) -> KV:
  match m:
    case None{}:
      KNone{}
    case Some{+n}:
      kv.after(str_of(unquote(String.take(s, n))), String.drop(s, n))

def kv.pick(isq: Bool, isflow: Bool, +s: String) -> KV:
  match isq isflow:
    case True{} _:
      kv.quoted(L.token_len(s), s)
    case False{} True{}:
      KNone{}
    case False{} False{}:
      kv.plain(colon.find(s, 0n), s)

# The `key: rest` a line spells, when it spells one.
def split_kv(+s: String) -> KV:
  kv.pick(U32.is_eq(first_code(s), 34) || U32.is_eq(first_code(s), 39), U32.is_eq(first_code(s), 91) || U32.is_eq(first_code(s), 123), s)

def field.cons(k: String, x: L.JR(), rest: L.JR()) -> L.JR():
  match x rest:
    case Done{a} Done{b}:
      Done{Json.JField{k, a, b}}
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}

def map.piece(kv: KV) -> L.JR():
  match kv:
    case KOk{k, rest}:
      field.cons(k, atom(rest), Done{Json.JNil{}})
    case KBad{m}:
      Fail{m}
    case KNone{}:
      Fail{"expected key: value in a flow mapping"}

# Merge one piece's field in front of the chain.
def map.cons(x: L.JR(), rest: L.JR()) -> L.JR():
  match x rest:
    case Done{Json.JField{k, v, n}} Done{b}:
      Done{Json.JField{k, v, b}}
    case Fail{e} _:
      Fail{e}
    case _ Fail{e}:
      Fail{e}
    case _ _:
      Fail{"bad flow mapping"}

def map.items(ps: List<&2, String>) -> L.JR():
  match ps:
    case Nil{}:
      Done{Json.JNil{}}
    case Con{+p, r}:
      map.cons(map.piece(split_kv(p)), map.items(r))

def map.fin(closed: Bool, +s: String) -> L.JR():
  match closed:
    case True{}:
      wrap.obj(map.items(split_top(inner(s))))
    case False{}:
      Fail{"unterminated flow mapping"}

def flow.pick(isseq: Bool, ismap: Bool, +s: String) -> L.JR():
  match isseq ismap:
    case True{} _:
      seq.fin(U32.is_eq(last_code(s), 93), s)
    case False{} True{}:
      map.fin(U32.is_eq(last_code(s), 125), s)
    case False{} False{}:
      atom(s)

# A value after `key:` or `- `: flow collection, quoted or plain scalar.
def scalar(+s: String) -> L.JR():
  flow.pick(U32.is_eq(first_code(s), 91), U32.is_eq(first_code(s), 123), s)
