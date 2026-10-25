import Base
import ./json.bend as Json
import ./clock.bend as Clock
import ./poll.bend as Poll
import ./view.bend as View

# The human view of a usage reading (switcher.py _format_usage_lines and
# _usage_entry_lines), without colour: NO_COLOR is what this prints always.

def sel_n(c: Bool, +x: Nat, +y: Nat) -> Nat:
  match c:
    case True{}:
      x
    case False{}:
      y

def sel_l(c: Bool, x: List<&2, String>, y: List<&2, String>) -> List<&2, String>:
  match c:
    case True{}:
      x
    case False{}:
      y

def sp(+n: Nat) -> String:
  String.repeat(" ", n)

def padl(+s: String, +w: Nat) -> String:
  sp(Nat.sub(w, String.length(s))) ++ s

def padr(+s: String, +w: Nat) -> String:
  s ++ sp(Nat.sub(w, String.length(s)))

# `{pct:>3.0f}`: tenths rounded to a whole percent, halves to even, width 3.
def whole.pick(+w0: U32, +r: U32) -> U32:
  Clock.sel(U32.is_gt(r, 5), (w0 + 1 : U32), Clock.sel(U32.is_eq(r, 5), (w0 + (w0 % 2) : U32), w0))

def whole(+t: U32) -> U32:
  whole.pick((t / 10 : U32), (t % 10 : U32))

def pct_text(+t: U32) -> String:
  padl(U32.show(whole(t)) ++ "%", 4n)

def money.put(comma: Bool, +c: Char, acc: String) -> String:
  match comma:
    case True{}:
      SCon{c, SCon{',', acc}}
    case False{}:
      SCon{c, acc}

def money.group(r: String, +n: Nat, acc: String) -> String:
  match r:
    case SNil{}:
      acc
    case SCon{+c, +t}:
      money.group(t, 1n+n, money.put(Nat.is_gt(n, 0n) && Nat.is_eq(Nat.mod(n, 3n), 0n), c, acc))

def money.commas(+d: String) -> String:
  money.group(String.reverse(d), 0n, "")

def money.fmt(+c: U32) -> String:
  money.commas(U32.show((c / 100 : U32))) ++ "." ++ Clock.pad2((c % 100 : U32))

def money.cents(+i: String, +f: String) -> String:
  money.fmt(Maybe.default(&2, U32, Maybe.bind(&2, U32, U32, U32.read(i), x => Maybe.bind(&2, U32, U32, Clock.num(f ++ "000", 0n, 2n), y => Maybe.bind(&2, U32, U32, Clock.num(f ++ "000", 2n, 1n), z => Some{(x * 100 + y + Clock.sel(U32.is_ge(z, 5), 1, 0) : U32)}))), 0))

def money.parts(ps: List<&2, String>) -> String:
  match ps:
    case Con{i, Con{f, Nil{}}}:
      money.cents(i, f)
    case Con{i, Nil{}}:
      money.cents(i, "")
    case _:
      "0.00"

# `${:,.2f}` of a JSON number.
def money(j: Json.Json) -> String:
  match j:
    case Json.JNum{t}:
      money.parts(String.split(t, '.'))
    case _:
      "0.00"

type Line is Data:
  Line{label: String, body: String}

def tenths_of(+w: Json.Json) -> U32:
  Maybe.default(&2, U32, Poll.tenths.json(View.jv("pct", w)), 0)

def marker.ahead(m: Maybe<&2, View.Pace>) -> String:
  match m:
    case Some{View.Pace{e, a, eta, last}}:
      Clock.sel.s(a, "  (ahead of pace)", "")
    case None{}:
      ""

def body.cell(+pct: U32, c: Maybe<&2, View.Cell>, +marker: String) -> String:
  match c:
    case Some{View.Cell{cd, ck}}:
      pct_text(pct) ++ "   resets " ++ padr(ck, 12n) ++ "  in " ++ cd ++ marker
    case None{}:
      pct_text(pct) ++ marker

def window_line(+label: String, +w: Json.Json, +marker: String, +now: U32, +off: U32) -> Line:
  Line{label, body.cell(tenths_of(w), View.fresh(w, now, off), marker)}

def spend.body(c: Maybe<&2, View.Cell>, +pct: U32, +used: String, +limit: String) -> String:
  match c:
    case Some{View.Cell{cd, ck}}:
      pct_text(pct) ++ "   resets " ++ padr(ck, 12n) ++ "  $" ++ used ++ " / $" ++ limit
    case None{}:
      pct_text(pct) ++ "   $" ++ used ++ " / $" ++ limit

def spend_line(+s: Json.Json, +now: U32, +off: U32) -> Line:
  Line{"$$", spend.body(View.fresh(s, now, off), tenths_of(s), money(View.jv("used", s)), money(View.jv("limit", s)))}

def cons_m(m: Maybe<&2, Line>, rest: List<&2, Line>) -> List<&2, Line>:
  match m:
    case Some{l}:
      l <> rest
    case None{}:
      rest

def win_m(+label: String, m: Maybe<&2, Json.Json>, weekly: Bool, +fetched: Maybe<&2, U32>, +now: U32, +off: U32) -> Maybe<&2, Line>:
  match m:
    case None{}:
      None{}
    case Some{+w}:
      Some{window_line(label, w, Clock.sel.s(weekly, marker.ahead(View.pace_of(w, fetched)), ""), now, off)}

def spend_m(m: Maybe<&2, Json.Json>, +now: U32, +off: U32) -> Maybe<&2, Line>:
  match m:
    case Some{s}:
      Some{spend_line(s, now, off)}
    case None{}:
      None{}

def scoped_marker(+w: Json.Json, +fetched: Maybe<&2, U32>) -> String:
  Clock.sel.s(U32.is_ge(tenths_of(w), 1000), "  (!)", marker.ahead(View.pace_of(w, fetched)))

def scoped_lines(ws: List<&2, Json.Json>, +fetched: Maybe<&2, U32>, +now: U32, +off: U32) -> List<&2, Line>:
  match ws:
    case Nil{}:
      []
    case Con{+w, t}:
      window_line(Maybe.default(&2, String, Json.as_string(View.jv("name", w)), "?"), w, scoped_marker(w, fetched), now, off) <> scoped_lines(t, fetched, now, off)

def usage_rows(+u: Json.Json, +fetched: Maybe<&2, U32>, +now: U32, +off: U32) -> List<&2, Line>:
  cons_m(spend_m(Json.get("spend", u), now, off),
    cons_m(win_m("5h", Json.get("five_hour", u), False{}, fetched, now, off),
      cons_m(win_m("7d", Json.get("seven_day", u), True{}, fetched, now, off),
        scoped_lines(Json.to_list(View.jv("scoped", u)), fetched, now, off))))

def width(ls: List<&2, Line>, +w: Nat) -> Nat:
  match ls:
    case Nil{}:
      1n+w
    case Con{Line{+l, b}, t}:
      width(t, sel_n(Nat.is_gt(String.length(l), w), String.length(l), w))

def fmt_lines(ls: List<&2, Line>, +w: Nat) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{Line{l, b}, t}:
      (padr(l ++ ":", w) ++ " " ++ b) <> fmt_lines(t, w)

def age_text(+secs: U32) -> String:
  Clock.sel.s(U32.is_lt(secs, 60), "just now", Clock.sel.s(U32.is_lt(secs, 3600), U32.show((secs / 60 : U32)) ++ "m ago",
    Clock.sel.s(U32.is_lt(secs, 86400), U32.show((secs / 3600 : U32)) ++ "h ago", U32.show((secs / 86400 : U32)) ++ "d ago")))

def tree(ls: List<&2, String>, +last: Nat, +i: Nat) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{h, t}:
      (Clock.sel.s(Nat.is_eq(i, last), "\u{2514} ", "\u{251C} ") ++ h) <> tree(t, last, 1n+i)

def last_idx(ls: List<&2, String>) -> Nat:
  Nat.sub(List.length(&2, String, ls), 1n)

def append_last(ls: List<&2, String>, +note: String) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{h, Nil{}}:
      [h ++ note]
    case Con{h, Con{h2, t2}}:
      h <> append_last(h2 <> t2, note)

def with_age(ls: List<&2, String>, +note: String) -> List<&2, String>:
  append_last(ls, note)

def note.pick(old: Bool, +a: U32, ls: List<&2, String>) -> List<&2, String>:
  match old:
    case True{}:
      with_age(ls, " \u{B7} " ++ age_text(a))
    case False{}:
      ls

def age_note(+age: Maybe<&2, U32>, ls: List<&2, String>) -> List<&2, String>:
  match age:
    case Some{+a}:
      note.pick(U32.is_gt(a, 180), a, ls)
    case None{}:
      ls

def measured2(+ls: List<&2, String>, +age: Maybe<&2, U32>) -> List<&2, String>:
  tree(age_note(age, ls), last_idx(ls), 0n)

def measured(+u: Json.Json, +fetched: Maybe<&2, U32>, +age: Maybe<&2, U32>, +now: U32, +off: U32) -> List<&2, String>:
  measured2(fmt_lines(usage_rows(u, fetched, now, off), width(usage_rows(u, fetched, now, off), 0n)), age)

def error_note(+k: String) -> String:
  Clock.sel.s(String.eq(k, "consume-busy"), "another cswap surface holds the slot - retries next pass",
    Clock.sel.s(String.eq(k, "invalid_client"), "cswap's OAuth client was rejected - systemic, not this account",
      Clock.sel.s(String.eq(k, "store-unmirrored"), "CLAUDE_SECURESTORAGE_CONFIG_DIR set - unset it or run from a normal shell", k)))

def unavailable(le: Maybe<&2, String>) -> List<&2, String>:
  match le:
    case Some{k}:
      ["usage unavailable (" ++ error_note(k) ++ ")"]
    case None{}:
      ["usage unavailable"]

def sentinel_note(+s: String) -> String:
  Clock.sel.s(String.eq(s, "token_expired"), "token expired - refresh deferred this pass; retries automatically",
    Clock.sel.s(String.eq(s, "foreign_credential"), "live credential belongs to another account - a switch repairs it",
      Clock.sel.s(String.eq(s, "api_key"), "API key (no quota)",
        Clock.sel.s(String.eq(s, "keychain_unavailable"), "keychain unavailable - locked or in use; try again",
          Clock.sel.s(String.eq(s, "relogin_required"), "re-login needed - refresh token dead; log in with Claude Code, then run: cswap add",
            Clock.sel.s(String.eq(s, "no_credentials"), "no credentials", s))))))

def last_seen2(b: Maybe<&2, U32>, +age: Maybe<&2, U32>) -> List<&2, String>:
  match b age:
    case Some{p} Some{a}:
      ["\u{2514} last seen " ++ U32.show(whole(p)) ++ "% used \u{B7} " ++ age_text(a)]
    case _ _:
      []

def last_seen(+lg: Json.Json, +fetched: Maybe<&2, U32>, +age: Maybe<&2, U32>, +off: U32, models: List<&2, String>) -> List<&2, String>:
  last_seen2(Poll.binding(lg, []), age)

def sentinel_lines(+s: String, +lg: Json.Json, +fetched: Maybe<&2, U32>, +age: Maybe<&2, U32>, +off: U32) -> List<&2, String>:
  sentinel_note(s) <> sel_l(String.eq(s, "api_key"), [], last_seen(lg, fetched, age, off, []))
