import Base

# Text for the terminal dashboard: styled segments, truncation to a width,
# durations, percentages and usage bars. Pure; widths are in characters (a
# Bend String is a list of code points), so the box-drawing glyphs count one.

# What a segment looks like. `RPlain` carries no escape at all.
type Role is Data:
  RPlain{}
  RBold{}
  RAccent{}
  RAccentB{}
  RMuted{}
  ROk{}
  RWarn{}
  RCrit{}
  RTrack{}

# A run of text in one style; `dim` fades it (a stale measurement).
type Seg is Data:
  Seg{text: String, role: Role, dim: Bool}

def sg(+t: String, +r: Role) -> Seg:
  Seg{t, r, False{}}

def sel.s(+c: Bool, +x: String, +y: String) -> String:
  match c:
    case True{}:
      x
    case False{}:
      y

def sel.u(+c: Bool, +x: U32, +y: U32) -> U32:
  match c:
    case True{}:
      x
    case False{}:
      y

def spaces(+n: Nat) -> String:
  String.repeat(" ", n)

# Pad on the right / left to `w` characters (never truncates).
def pad_right(+s: String, +w: Nat) -> String:
  s ++ spaces(Nat.sub(w, String.length(s)))

def pad_left(+s: String, +w: Nat) -> String:
  spaces(Nat.sub(w, String.length(s))) ++ s

# ---- numbers --------------------------------------------------------------

# Centi-percent (4750 = 47.5 %) to a whole percent, halves to even as Python's
# `f"{pct:.0f}"` does.
def round_even(+c: U32) -> U32:
  sel.u(U32.is_lt((c % 100 : U32), 50), (c / 100 : U32),
    sel.u(U32.is_gt((c % 100 : U32), 50), ((c / 100 : U32) + 1 : U32),
      sel.u(U32.is_eq((((c / 100 : U32)) % 2 : U32), 0), (c / 100 : U32), ((c / 100 : U32) + 1 : U32))))

# " 47%" (width 4), as the reference's `{pct:3.0f}%`.
def pct_text(+c: U32) -> String:
  pad_left(U32.show(round_even(c)), 3n) ++ "%"

def hm(+s: U32) -> String:
  sel.s(U32.is_eq(((s % 3600) / 60 : U32), 0), U32.show((s / 3600 : U32)) ++ "h",
    U32.show((s / 3600 : U32)) ++ "h " ++ U32.show(((s % 3600) / 60 : U32)) ++ "m")

def dh(+s: U32) -> String:
  sel.s(U32.is_eq(((s % 86400) / 3600 : U32), 0), U32.show((s / 86400 : U32)) ++ "d",
    U32.show((s / 86400 : U32)) ++ "d " ++ U32.show(((s % 86400) / 3600 : U32)) ++ "h")

# ---- lines -----------------------------------------------------------------

# The shortest honest duration: 45s, 12m, 2h 13m, 2h, 3d 4h, 3d.
def duration(+s: U32) -> String:
  sel.s(U32.is_lt(s, 60), U32.show(s) ++ "s",
    sel.s(U32.is_lt(s, 3600), U32.show((s / 60 : U32)) ++ "m",
      sel.s(U32.is_lt(s, 86400), hm(s), dh(s))))

def seg_len(+s: Seg) -> Nat:
  match s:
    case Seg{t, r, d}:
      String.length(t)

def line_len(+l: List<&2, Seg>) -> Nat:
  match l:
    case Nil{}:
      0n
    case Con{s, t}:
      Nat.add(seg_len(s), line_len(t))

def cut(+s: Seg, +n: Nat) -> Seg:
  match s:
    case Seg{x, r, d}:
      Seg{String.take(x, n), r, d}

def take_pick(+over: Bool, +s: Seg, +n: Nat, +rest: List<&2, Seg>) -> List<&2, Seg>:
  match over:
    case True{}:
      Con{cut(s, n), Nil{}}
    case False{}:
      Con{s, rest}

# The first `n` characters of a line.
def take_chars(+l: List<&2, Seg>, +n: Nat) -> List<&2, Seg>:
  match l:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      take_pick(Nat.is_gt(seg_len(s), n), s, n, take_chars(t, Nat.sub(n, seg_len(s))))

def ellipsized(+l: List<&2, Seg>, +w: Nat) -> List<&2, Seg>:
  List.append(&2, Seg, take_chars(l, Nat.sub(w, 1n)), Con{sg("…", RMuted{}), Nil{}})

def fit_if(+over: Bool, +l: List<&2, Seg>, +w: Nat) -> List<&2, Seg>:
  match over:
    case True{}:
      ellipsized(l, w)
    case False{}:
      l

# ---- bars -------------------------------------------------------------------

# A line no wider than `w`: longer ones end in an ellipsis.
def fit(+l: List<&2, Seg>, +w: Nat) -> List<&2, Seg>:
  fit_if(Nat.is_gt(line_len(l), w), l, w)

def sev_ok(+warn: Bool) -> Role:
  match warn:
    case True{}:
      RWarn{}
    case False{}:
      ROk{}

def sev_warn(+c: U32) -> Role:
  sev_ok(U32.is_ge(c, 7000))

def sev_pick(+crit: Bool, +c: U32) -> Role:
  match crit:
    case True{}:
      RCrit{}
    case False{}:
      sev_warn(c)

# Bar colour from the centi-percent: red from 90 %, amber from 70 %.
def severity(+c: U32) -> Role:
  sev_pick(U32.is_ge(c, 9000), c)

def is_tick(+t: Maybe<&2, Nat>, +i: Nat) -> Bool:
  match t:
    case None{}:
      False{}
    case Some{k}:
      Nat.is_eq(k, i)

def cell_kind(+tick: Bool, +filled: Bool, +half: Bool, +r: Role, +dim: Bool) -> Seg:
  match tick filled half:
    case True{} _ _:
      sg("┃", RWarn{})
    case False{} True{} _:
      Seg{"━", r, dim}
    case False{} False{} True{}:
      Seg{"╸", r, dim}
    case False{} False{} False{}:
      sg("─", RTrack{})

def cell(+i: Nat, +full: Nat, +half: Bool, +tick: Maybe<&2, Nat>, +r: Role, +dim: Bool) -> Seg:
  cell_kind(is_tick(tick, i), Nat.is_lt(i, full), Nat.is_eq(i, full) && half, r, dim)

# `n` cells from index `i`.
def cells(+n: Nat, +i: Nat, +full: Nat, +half: Bool, +tick: Maybe<&2, Nat>, +r: Role, +dim: Bool) -> List<&2, Seg>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Con{cell(i, full, half, tick, r, dim), cells(p, Nat.add(i, 1n), full, half, tick, r, dim)}

# Where the threshold tick sits: round(threshold / 100 * width), kept in range.
def tick_at(+thr: Maybe<&2, U32>, +w: Nat) -> Maybe<&2, Nat>:
  match thr:
    case None{}:
      None{}
    case Some{t}:
      Some{Nat.min(Nat.sub(w, 1n), U32.to_nat((((t * U32.from_nat(w)) + 5000 : U32) / 10000 : U32)))}

# A usage bar of `w` cells for a centi-percent (None: an empty track).
def bar(+pct: Maybe<&2, U32>, +w: Nat, +thr: Maybe<&2, U32>, +stale: Bool) -> List<&2, Seg>:
  match pct:
    case None{}:
      Con{sg(String.repeat("─", w), RTrack{}), Nil{}}
    case Some{c}:
      cells(w, 0n, U32.to_nat(((U32.min(c, 10000) * U32.from_nat(w)) / 10000 : U32)), U32.is_ge((((U32.min(c, 10000) * U32.from_nat(w)) % 10000 : U32)), 5000), tick_at(thr, w), severity(c), stale)

# ---- painting -----------------------------------------------------------------

def sgr(+r: Role) -> String:
  match r:
    case RPlain{}:
      ""
    case RBold{}:
      "1"
    case RAccent{}:
      "38;5;173"
    case RAccentB{}:
      "1;38;5;173"
    case RMuted{}:
      "38;5;245"
    case ROk{}:
      "38;5;108"
    case RWarn{}:
      "38;5;179"
    case RCrit{}:
      "38;5;167"
    case RTrack{}:
      "38;5;238"

def codes(+r: Role, +dim: Bool) -> String:
  sel.s(String.is_empty(sgr(r)), sel.s(dim, "2", ""), sel.s(dim, sgr(r) ++ ";2", sgr(r)))

def paint_with(+color: Bool, +t: String, +c: String) -> String:
  sel.s(color && Bool.not(String.is_empty(c)), "\u{1B}[" ++ c ++ "m" ++ t ++ "\u{1B}[0m", t)

def paint_seg(+s: Seg, +color: Bool) -> String:
  match s:
    case Seg{t, r, d}:
      paint_with(color, t, codes(r, d))

def paint_all(+l: List<&2, Seg>, +color: Bool) -> String:
  match l:
    case Nil{}:
      ""
    case Con{s, t}:
      paint_seg(s, color) ++ paint_all(t, color)

def style_key(+s: Seg) -> String:
  match s:
    case Seg{t, r, d}:
      codes(r, d)

def same_style(+a: Seg, +b: Seg) -> Bool:
  String.eq(style_key(a), style_key(b))

def join_seg(+a: Seg, +b: Seg) -> Seg:
  match a b:
    case Seg{x, r, d} Seg{y, r2, d2}:
      Seg{x ++ y, r, d}

def merge_acc(+same: Bool, +cur: Seg, +s: Seg) -> Seg:
  match same:
    case True{}:
      join_seg(cur, s)
    case False{}:
      s

def merge_emit(+same: Bool, +cur: Seg, +rest: List<&2, Seg>) -> List<&2, Seg>:
  match same:
    case True{}:
      rest
    case False{}:
      Con{cur, rest}

def merge_go(+l: List<&2, Seg>, +cur: Seg) -> List<&2, Seg>:
  match l:
    case Nil{}:
      Con{cur, Nil{}}
    case Con{s, t}:
      merge_emit(same_style(cur, s), cur, merge_go(t, merge_acc(same_style(cur, s), cur, s)))

# Neighbouring segments in one style become one (one escape per run).
def merged(+l: List<&2, Seg>) -> List<&2, Seg>:
  match l:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      merge_go(t, s)

def paint(+l: List<&2, Seg>, +color: Bool) -> String:
  paint_all(merged(l), color)

def render_rest(+ls: List<&2, List<&2, Seg>>, +color: Bool) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{l, t}:
      "\n" ++ paint(l, color) ++ render_rest(t, color)

# Lines joined with newlines, each painted (or plain under NO_COLOR).
def render(+ls: List<&2, List<&2, Seg>>, +color: Bool) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{l, t}:
      paint(l, color) ++ render_rest(t, color)


# ---- merging neighbours ----------------------------------------------------------
