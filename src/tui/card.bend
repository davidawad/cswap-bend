import Base
import ./fmt.bend as F
import ./model.bend as M
import ../usage/norm.bend as UNorm

# The account lines of the dashboard: the active account as a card with one
# bar per window, the others as one line each. Pure.

def plain(+t: String) -> F.Seg:
  F.sg(t, F.RPlain{})

def muted(+t: String) -> F.Seg:
  F.sg(t, F.RMuted{})

def cat(+a: List<&2, F.Seg>, +b: List<&2, F.Seg>) -> List<&2, F.Seg>:
  List.append(&2, F.Seg, a, b)

def alias_of(+a: M.Acct) -> String:
  match a:
    case M.Acct{s, e, al, t, ac, d, w, g, n}:
      al

def names_pick(+bare: Bool, +a: M.Acct) -> List<&2, F.Seg>:
  match bare:
    case True{}:
      [plain(M.acct_email(a))]
    case False{}:
      [F.sg(alias_of(a), F.RAccentB{}), plain(" (" ++ M.acct_email(a) ++ ")")]

# "alias (email)" with the alias in the accent colour, or just the email.
def names(+a: M.Acct) -> List<&2, F.Seg>:
  names_pick(String.is_empty(alias_of(a)), a)

def tag_of(+a: M.Acct) -> String:
  match a:
    case M.Acct{s, e, al, t, ac, d, w, g, n}:
      t

def flag_if(+c: Bool, +s: F.Seg) -> List<&2, F.Seg>:
  match c:
    case True{}:
      [s]
    case False{}:
      []

# The measurement age note, shown once a reading is at least 3 minutes old.
def age_note(+g: Maybe<&2, U32>) -> List<&2, F.Seg>:
  match g:
    case None{}:
      []
    case Some{s}:
      flag_if(U32.is_ge(s, 180), muted("   · " ++ F.duration(s) ++ " ago"))

def is_stale(+g: Maybe<&2, U32>) -> Bool:
  match g:
    case None{}:
      False{}
    case Some{s}:
      U32.is_gt(s, 300)

def tail_flags(+a: M.Acct) -> List<&2, F.Seg>:
  cat(flag_if(M.acct_active(a), F.sg("   ● active", F.RAccentB{})), cat(flag_if(M.acct_disabled(a), muted("   (disabled)")), age_note(M.acct_age(a))))

def head_line(+a: M.Acct) -> List<&2, F.Seg>:
  cat([F.sg(F.pad_left(M.acct_slot(a), 2n) ++ "  ", F.RBold{})], cat(names(a), cat([muted("  [" ++ tag_of(a) ++ "]")], tail_flags(a))))

# ---- the bars --------------------------------------------------------------

def label_width(+ws: List<&2, M.Win>, +acc: Nat) -> Nat:
  match ws:
    case Nil{}:
      acc
    case Con{w, t}:
      label_width(t, Nat.max(acc, String.length(M.win_label(w))))

def bar_width(+width: U32, +lw: Nat) -> Nat:
  Nat.max(12n, Nat.min(30n, Nat.sub(Nat.sub(U32.to_nat(width), 42n), lw)))

# "resets 2h 13m" (or "resets now"); empty when no reset is known.
def reset_short(+r: Maybe<&2, U32>, +now: U32) -> String:
  match r:
    case None{}:
      ""
    case Some{t}:
      F.sel.s(U32.is_gt(t, now), "resets " ++ F.duration((t - now : U32)), "resets now")

# The same with the local clock time of the reset: "resets 2h 13m · 20:39".
def reset_full(+r: Maybe<&2, U32>, +now: U32, +off: U32) -> String:
  match r:
    case None{}:
      ""
    case Some{t}:
      F.sel.s(U32.is_gt(t, now), reset_short(r, now) ++ " · " ++ UNorm.clock.text(t, now, off), reset_short(r, now))

def is_model(+w: M.Win) -> Bool:
  Bool.not(String.eq(M.win_label(w), "5h")) && Bool.not(String.eq(M.win_label(w), "7d"))

def is_full(+p: Maybe<&2, U32>) -> Bool:
  match p:
    case None{}:
      False{}
    case Some{c}:
      U32.is_ge(c, 10000)

def maxed(+w: M.Win) -> Bool:
  is_model(w) && is_full(M.win_pct(w))

def mark(+w: M.Win, +s: String) -> String:
  F.sel.s(maxed(w), F.sel.s(String.is_empty(s), "(!)", s ++ "  (!)"), s)

def pick_suffix(+full: String, +short: String, +room: Nat) -> String:
  F.sel.s(Nat.is_le(String.length(full), room), full, short)

# The suffix of a row: the clock form where it fits, a (!) for a maxed model.
def suffix(+w: M.Win, +now: U32, +off: U32, +room: Nat) -> String:
  mark(w, pick_suffix(reset_full(M.win_reset(w), now, off), reset_short(M.win_reset(w), now), room))

def pct_seg(+p: Maybe<&2, U32>, +stale: Bool) -> F.Seg:
  match p:
    case None{}:
      muted("  usage unknown")
    case Some{c}:
      F.Seg{" " ++ F.pct_text(c), F.severity(c), stale}

def pad2(+s: String) -> String:
  F.sel.s(String.is_empty(s), "", "  " ++ s)

def view_width(+v: M.View) -> U32:
  match v:
    case M.View{w, c}:
      w

# Columns left for the suffix after indent, label, bar, percent and gap.
def room(+v: M.View, +lw: Nat, +bw: Nat) -> Nat:
  Nat.sub(U32.to_nat(view_width(v)), Nat.add(Nat.add(4n, lw), Nat.add(Nat.add(1n, bw), 7n)))

# The indent, the label and the bar of a row.
def row_head(+w: M.Win, +lw: Nat, +bw: Nat, +thr: Maybe<&2, U32>, +stale: Bool) -> List<&2, F.Seg>:
  cat([plain("    "), muted(F.pad_right(M.win_label(w), lw) ++ " ")], F.bar(M.win_pct(w), bw, thr, stale))

# One row: indent, label, bar, percent, suffix.
def row(+w: M.Win, +lw: Nat, +bw: Nat, +v: M.View, +thr: Maybe<&2, U32>, +stale: Bool, +now: U32, +off: U32) -> List<&2, F.Seg>:
  cat(row_head(w, lw, bw, thr, stale), [pct_seg(M.win_pct(w), stale), muted(pad2(suffix(w, now, off, room(v, lw, bw))))])

def rows(+ws: List<&2, M.Win>, +lw: Nat, +bw: Nat, +v: M.View, +thr: Maybe<&2, U32>, +stale: Bool, +now: U32, +off: U32) -> List<&2, List<&2, F.Seg>>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{w, t}:
      Con{row(w, lw, bw, v, thr, stale, now, off), rows(t, lw, bw, v, thr, stale, now, off)}

def unavailable(+a: M.Acct) -> List<&2, F.Seg>:
  [plain("    "), muted("usage unavailable" ++ F.sel.s(String.is_empty(M.acct_note(a)), "", " · " ++ M.acct_note(a)))]

def card_rows(+a: M.Acct, +ws: List<&2, M.Win>, +v: M.View, +thr: Maybe<&2, U32>, +now: U32, +off: U32) -> List<&2, List<&2, F.Seg>>:
  match ws:
    case Nil{}:
      [unavailable(a)]
    case _:
      rows(ws, label_width(ws, 0n), bar_width(view_width(v), label_width(ws, 0n)), v, thr, is_stale(M.acct_age(a)), now, off)

# The full card of the active account.
def card(+a: M.Acct, +v: M.View, +thr: Maybe<&2, U32>, +now: U32, +off: U32) -> List<&2, List<&2, F.Seg>>:
  Con{head_line(a), card_rows(a, M.acct_wins(a), v, thr, now, off)}

# ---- the one-line form ----------------------------------------------------------

def reset_in(+p: Maybe<&2, U32>, +r: Maybe<&2, U32>, +now: U32) -> List<&2, F.Seg>:
  flag_if(is_full(p) && Bool.not(String.is_empty(reset_short(r, now))), muted(" (" ++ reset_short(r, now) ++ ")"))

def pct_part(+w: M.Win, +c: U32, +now: U32) -> List<&2, F.Seg>:
  cat([muted(M.win_label(w) ++ " "), F.sg(U32.show(F.round_even(c)) ++ "%", F.severity(c))], reset_in(M.win_pct(w), M.win_reset(w), now))

def part_pick(+model: Bool, +full: Bool, +w: M.Win, +p: Maybe<&2, U32>, +now: U32) -> List<&2, F.Seg>:
  match model p:
    case True{} _:
      flag_if(full, F.sg(M.win_label(w) ++ " (!)", F.RCrit{}))
    case False{} None{}:
      []
    case False{} Some{c}:
      pct_part(w, c, now)

def mini_part(+w: M.Win, +now: U32) -> List<&2, F.Seg>:
  part_pick(is_model(w), maxed(w), w, M.win_pct(w), now)

def push_part(+p: List<&2, F.Seg>, +rest: List<&2, List<&2, F.Seg>>) -> List<&2, List<&2, F.Seg>>:
  match p:
    case Nil{}:
      rest
    case _:
      Con{p, rest}

def mini_parts(+ws: List<&2, M.Win>, +now: U32) -> List<&2, List<&2, F.Seg>>:
  match ws:
    case Nil{}:
      Nil{}
    case Con{w, t}:
      push_part(mini_part(w, now), mini_parts(t, now))

def joined_rest(+ps: List<&2, List<&2, F.Seg>>) -> List<&2, F.Seg>:
  match ps:
    case Nil{}:
      []
    case Con{p, t}:
      cat([F.sg(" · ", F.RTrack{})], cat(p, joined_rest(t)))

def joined(+ps: List<&2, List<&2, F.Seg>>) -> List<&2, F.Seg>:
  match ps:
    case Nil{}:
      []
    case Con{p, t}:
      cat(p, joined_rest(t))

def mini_body(+a: M.Acct, +ps: List<&2, List<&2, F.Seg>>) -> List<&2, F.Seg>:
  match ps:
    case Nil{}:
      [muted(F.sel.s(String.is_empty(M.acct_note(a)), "usage unknown", M.acct_note(a)))]
    case _:
      joined(ps)

def mini_head(+a: M.Acct) -> List<&2, F.Seg>:
  cat([F.sg(F.pad_left(M.acct_slot(a), 2n) ++ "  ", F.RBold{})], cat(names(a), cat([muted("  [" ++ tag_of(a) ++ "]")], flag_if(M.acct_disabled(a), muted("  (disabled)")))))

# An inactive account on one line: "2  work@acme.dev  [personal]   5h 92% · 7d 63%".
def mini(+a: M.Acct, +now: U32) -> List<&2, F.Seg>:
  cat(mini_head(a), cat([plain("   ")], mini_body(a, mini_parts(M.acct_wins(a), now))))
