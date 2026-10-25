import Base
import ./fmt.bend as F
import ./model.bend as M
import ./card.bend as C

# One frame of the dashboard as text: the title and auto-switch line, the
# accounts, the next best candidate and the tail of the daemon log. Pure: the
# same Snap and View always draw the same text.

# ---- numbers ------------------------------------------------------------------

# The candidate with the most headroom among the accounts that are neither
# active nor disabled; the first wins a tie.
type Best is Data:
  Best{slot: String, email: String, free: U32}

def frac2(+r: U32) -> String:
  F.sel.s(U32.is_eq((r % 10 : U32), 0), U32.show((r / 10 : U32)), F.sel.s(U32.is_lt(r, 10), "0" ++ U32.show(r), U32.show(r)))

# ---- the header ---------------------------------------------------------------------

# 9000 -> "90", 8550 -> "85.5", 8505 -> "85.05".
def pct_label(+c: U32) -> String:
  F.sel.s(U32.is_eq((c % 100 : U32), 0), U32.show((c / 100 : U32)), U32.show((c / 100 : U32)) ++ "." ++ frac2((c % 100 : U32)))

def version_of(+h: M.Hdr) -> String:
  match h:
    case M.Hdr{v, l, p, t, i, n}:
      v

def title(+h: M.Hdr) -> List<&2, F.Seg>:
  [F.sg("cswap tui", F.RBold{}), C.muted("  " ++ version_of(h))]

def live_of(+h: M.Hdr) -> Bool:
  match h:
    case M.Hdr{v, l, p, t, i, n}:
      l

def state_seg(+live: Bool) -> F.Seg:
  match live:
    case True{}:
      F.sg("● auto-switch LIVE", F.ROk{})
    case False{}:
      F.sg("○ auto-switch STOPPED", F.RWarn{})

def opt_text(+m: Maybe<&2, String>) -> List<&2, F.Seg>:
  match m:
    case None{}:
      []
    case Some{s}:
      [C.muted(" · " ++ s)]

def thr_some(+m: Maybe<&2, U32>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{c}:
      Some{"threshold " ++ pct_label(c) ++ "%"}

def thr_text(+h: M.Hdr) -> Maybe<&2, String>:
  match h:
    case M.Hdr{v, l, p, t, i, n}:
      thr_some(t)

def every_some(+m: Maybe<&2, U32>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{c}:
      Some{"every " ++ U32.show(c) ++ "s"}

def every_text(+h: M.Hdr) -> Maybe<&2, String>:
  match h:
    case M.Hdr{v, l, p, t, i, n}:
      every_some(i)

def live_pid(+live: Bool, +p: Maybe<&2, U32>) -> Maybe<&2, String>:
  match live p:
    case True{} Some{n}:
      Some{"pid " ++ U32.show(n)}
    case _ _:
      None{}

def pid_text(+h: M.Hdr) -> Maybe<&2, String>:
  match h:
    case M.Hdr{v, l, p, t, i, n}:
      live_pid(l, p)

def next_poll(+live: Bool, +n: Maybe<&2, U32>, +now: U32) -> Maybe<&2, String>:
  match live n:
    case True{} Some{t}:
      Some{F.sel.s(U32.is_gt(t, now), "next poll in " ++ F.duration((t - now : U32)), "polling now")}
    case _ _:
      None{}

def poll_text(+h: M.Hdr, +now: U32) -> Maybe<&2, String>:
  match h:
    case M.Hdr{v, l, p, t, i, n}:
      next_poll(l, n, now)

def state_line(+h: M.Hdr, +now: U32) -> List<&2, F.Seg>:
  List.append(&2, F.Seg, [state_seg(live_of(h))], List.append(&2, F.Seg, opt_text(thr_text(h)), List.append(&2, F.Seg, opt_text(every_text(h)), List.append(&2, F.Seg, opt_text(poll_text(h, now)), opt_text(pid_text(h))))))

# ---- the accounts -----------------------------------------------------------------------

def threshold_of(+h: M.Hdr) -> Maybe<&2, U32>:
  match h:
    case M.Hdr{v, l, p, t, i, n}:
      t

def is_multi(+b: List<&2, List<&2, F.Seg>>) -> Bool:
  Nat.is_gt(List.length(&2, List<&2, F.Seg>, b), 1n)

def lines_cat(+a: List<&2, List<&2, F.Seg>>, +b: List<&2, List<&2, F.Seg>>) -> List<&2, List<&2, F.Seg>>:
  List.append(&2, List<&2, F.Seg>, a, b)

def gap_if(+b: Bool) -> List<&2, List<&2, F.Seg>>:
  match b:
    case True{}:
      [[]]
    case False{}:
      []

def empty_or(+as: List<&2, M.Acct>, +bs: List<&2, List<&2, F.Seg>>) -> List<&2, List<&2, F.Seg>>:
  match as:
    case Nil{}:
      [[C.muted("No managed accounts yet. Add one with: cswap add")]]
    case _:
      bs

# ---- the next best account ---------------------------------------------------------------------

def block_pick(+active: Bool, +a: M.Acct, +v: M.View, +h: M.Hdr, +now: U32, +off: U32) -> List<&2, List<&2, F.Seg>>:
  match active:
    case True{}:
      C.card(a, v, threshold_of(h), now, off)
    case False{}:
      [C.mini(a, now)]

def block(+a: M.Acct, +v: M.View, +h: M.Hdr, +now: U32, +off: U32) -> List<&2, List<&2, F.Seg>>:
  block_pick(M.acct_active(a), a, v, h, now, off)

def block_join(+b: List<&2, List<&2, F.Seg>>, +rest: List<&2, List<&2, F.Seg>>, +prev: Bool, +first: Bool) -> List<&2, List<&2, F.Seg>>:
  lines_cat(gap_if(Bool.not(first) && (prev || is_multi(b))), lines_cat(b, rest))

# The account lines in slot order. A blank line separates blocks when either
# side is a multi-line card.
def blocks(+as: List<&2, M.Acct>, +v: M.View, +h: M.Hdr, +now: U32, +off: U32, +prev: Bool, +first: Bool) -> List<&2, List<&2, F.Seg>>:
  match as:
    case Nil{}:
      Nil{}
    case Con{a, t}:
      block_join(block(a, v, h, now, off), blocks(t, v, h, now, off, is_multi(block(a, v, h, now, off)), False{}), prev, first)

def accounts_lines(+s: M.Snap, +v: M.View) -> List<&2, List<&2, F.Seg>>:
  match s:
    case M.Snap{now, off, h, as, lg}:
      empty_or(as, blocks(as, v, h, now, off, False{}, True{}))

def max_opt(+a: Maybe<&2, U32>, +b: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match a b:
    case None{} _:
      b
    case Some{x} None{}:
      a
    case Some{x} Some{y}:
      Some{U32.max(x, y)}

# Headroom is what is left of the busiest known window.
def busiest(+ws: List<&2, M.Win>, +acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ws:
    case Nil{}:
      acc
    case Con{w, t}:
      busiest(t, max_opt(acc, M.win_pct(w)))

def free_some(+m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{c}:
      Some{(10000 - U32.min(c, 10000) : U32)}

def free_of(+a: M.Acct) -> Maybe<&2, U32>:
  free_some(busiest(M.acct_wins(a), None{}))

def eligible(+a: M.Acct) -> Bool:
  Bool.not(M.acct_active(a)) && Bool.not(M.acct_disabled(a))

def best_free(+b: Best) -> U32:
  match b:
    case Best{s, e, f}:
      f

def better(+cur: Maybe<&2, Best>, +f: U32) -> Bool:
  match cur:
    case None{}:
      True{}
    case Some{b}:
      U32.is_gt(f, best_free(b))

def take_if(+yes: Bool, +a: M.Acct, +x: U32, +cur: Maybe<&2, Best>) -> Maybe<&2, Best>:
  match yes:
    case True{}:
      Some{Best{M.acct_slot(a), M.acct_email(a), x}}
    case False{}:
      cur

def take(+a: M.Acct, +f: Maybe<&2, U32>, +cur: Maybe<&2, Best>) -> Maybe<&2, Best>:
  match f:
    case None{}:
      cur
    case Some{x}:
      take_if(better(cur, x), a, x, cur)

def next_pick(+ok: Bool, +a: M.Acct, +cur: Maybe<&2, Best>) -> Maybe<&2, Best>:
  match ok:
    case True{}:
      take(a, free_of(a), cur)
    case False{}:
      cur

def next_best(+as: List<&2, M.Acct>, +cur: Maybe<&2, Best>) -> Maybe<&2, Best>:
  match as:
    case Nil{}:
      cur
    case Con{a, t}:
      next_best(t, next_pick(eligible(a), a, cur))

def best_name(+b: Best) -> String:
  match b:
    case Best{s, e, f}:
      s ++ " " ++ e

# ---- the daemon log --------------------------------------------------------------------------------

def best_line(+m: Maybe<&2, Best>) -> List<&2, F.Seg>:
  match m:
    case None{}:
      [C.muted("next best  none (no other account has a reading)")]
    case Some{b}:
      [C.muted("next best  "), F.sg(best_name(b), F.RAccent{}), C.muted(" · " ++ pct_label(best_free(b)) ++ "% free")]

def log_each(+ls: List<&2, String>) -> List<&2, List<&2, F.Seg>>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      Con{[C.muted("  " ++ l)], log_each(t)}

def log_lines(+ls: List<&2, String>) -> List<&2, List<&2, F.Seg>>:
  match ls:
    case Nil{}:
      [[C.muted("  no daemon log yet")]]
    case _:
      log_each(ls)

def log_of(+s: M.Snap) -> List<&2, String>:
  match s:
    case M.Snap{now, off, h, as, lg}:
      lg

def hdr_of(+s: M.Snap) -> M.Hdr:
  match s:
    case M.Snap{now, off, h, as, lg}:
      h

def now_of(+s: M.Snap) -> U32:
  match s:
    case M.Snap{now, off, h, as, lg}:
      now

def accts_of(+s: M.Snap) -> List<&2, M.Acct>:
  match s:
    case M.Snap{now, off, h, as, lg}:
      as

# ---- the frame ------------------------------------------------------------------------------------------

def head_lines(+s: M.Snap) -> List<&2, List<&2, F.Seg>>:
  [title(hdr_of(s)), state_line(hdr_of(s), now_of(s)), []]

def foot_lines(+s: M.Snap) -> List<&2, List<&2, F.Seg>>:
  lines_cat([[], best_line(next_best(accts_of(s), None{})), [], [F.sg("daemon log", F.RBold{})]], log_lines(log_of(s)))

def fit_all(+ls: List<&2, List<&2, F.Seg>>, +w: Nat) -> List<&2, List<&2, F.Seg>>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      Con{F.fit(l, w), fit_all(t, w)}

def viewcolor(+v: M.View) -> Bool:
  match v:
    case M.View{w, c}:
      c

# The whole frame: each line cut to the terminal width, painted unless NO_COLOR.
def frame(+s: M.Snap, +v: M.View) -> String:
  F.render(fit_all(lines_cat(head_lines(s), lines_cat(accounts_lines(s, v), foot_lines(s))), U32.to_nat(C.view_width(v))), viewcolor(v))
