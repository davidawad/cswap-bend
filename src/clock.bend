import Base

# Wall-clock time as unix seconds, and ISO 8601 text both ways. `U32` holds
# unix seconds until 2106. Dates before 1970 are not representable: they
# parse to None.

# Unix seconds now. The foreign effect calls time(2); Base's IO.now is a
# monotonic tick, not wall time.
def Clock.now_s() -> IO(U32):
  import "./effs/now_s.c"
  import "./effs/now_s.js"

def now_s() -> IO(U32):
  Clock.now_s()

def sel(c: Bool, x: U32, y: U32) -> U32:
  match c:
    case True{}:
      x
    case False{}:
      y

def sel.s(c: Bool, x: String, y: String) -> String:
  match c:
    case True{}:
      x
    case False{}:
      y

# ---- seconds to text -------------------------------------------------------

def pad2(+n: U32) -> String:
  sel.s(U32.is_lt(n, 10), "0" ++ U32.show(n), U32.show(n))

def pad4(+n: U32) -> String:
  sel.s(U32.is_lt(n, 10), "000", sel.s(U32.is_lt(n, 100), "00", sel.s(U32.is_lt(n, 1000), "0", ""))) ++ U32.show(n)

# Civil date (year, (month, day)) of a day count since 1970-01-01
# (Hinnant's civil_from_days, all unsigned: z + 719468 is positive).
def civil.adj(+y: U32, +m: U32, d: U32) -> U32 & (U32 & U32):
  (sel(U32.is_le(m, 2), (y + 1 : U32), y), (m, d))

def civil.ymd(+y: U32, +mp: U32, +doy: U32) -> U32 & (U32 & U32):
  civil.adj(y, sel(U32.is_lt(mp, 10), (mp + 3 : U32), (mp - 9 : U32)), (doy - ((153 * mp + 2) / 5) + 1 : U32))

def civil.fin(+yoe: U32, +era: U32, +doy: U32) -> U32 & (U32 & U32):
  civil.ymd((yoe + era * 400 : U32), ((5 * doy + 2) / 153 : U32), doy)

def civil.doy(+era: U32, +doe: U32, +yoe: U32) -> U32 & (U32 & U32):
  civil.fin(yoe, era, (doe - (365 * yoe + yoe / 4 - yoe / 100) : U32))

def civil.yoe(+era: U32, +doe: U32) -> U32 & (U32 & U32):
  civil.doy(era, doe, ((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365 : U32))

def civil.doe(+z: U32) -> U32 & (U32 & U32):
  civil.yoe((z / 146097 : U32), (z % 146097 : U32))

def civil(days: U32) -> U32 & (U32 & U32):
  civil.doe((days + 719468 : U32))

def iso.fmt(ymd: U32 & (U32 & U32), +s: U32, suffix: String) -> String:
  (y, (m, d)) = ymd
  pad4(y) ++ "-" ++ pad2(m) ++ "-" ++ pad2(d) ++ "T"
    ++ pad2((s / 3600 : U32)) ++ ":" ++ pad2(((s / 60) % 60 : U32)) ++ ":" ++ pad2((s % 60 : U32)) ++ suffix

# `2026-10-30T09:00:00Z`, as the reference's strftime writes it.
def iso8601_utc(+t: U32) -> String:
  iso.fmt(civil((t / 86400 : U32)), (t % 86400 : U32), "Z")

# `2026-10-30T09:00:00+00:00`, as the reference's isoformat writes it.
def iso8601_offset(+t: U32) -> String:
  iso.fmt(civil((t / 86400 : U32)), (t % 86400 : U32), "+00:00")

# ---- text to seconds -------------------------------------------------------

def all_digits(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Char.is_digit(c) && all_digits(t)

def num.pick(ok: Bool, s: String) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      U32.read(s)
    case False{}:
      None{}

# The n digits of `s` at offset `off`, as a number.
def num(+s: String, off: Nat, +n: Nat) -> Maybe<&2, U32>:
  +slice = String.take(String.drop(s, off), n)
  num.pick(all_digits(slice) && Nat.is_eq(String.length(slice), n), slice)

def at.pick(m: Maybe<&2, Char>, a: Char, b: Char) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{+c}:
      Char.is_eq(c, a) || Char.is_eq(c, b)

# True when the char at `i` is `a` or `b`.
def at(+s: String, i: Nat, a: Char, b: Char) -> Bool:
  at.pick(String.get(s, i), a, b)

def valid(+y: U32, +mo: U32, +d: U32, +h: U32, +mi: U32, +s: U32) -> Bool:
  U32.is_ge(y, 1970) && U32.is_ge(mo, 1) && U32.is_le(mo, 12) && U32.is_ge(d, 1) && U32.is_le(d, 31)
    && U32.is_lt(h, 24) && U32.is_lt(mi, 60) && U32.is_lt(s, 60)

def days.era(+era: U32, +yoe: U32, +doy: U32) -> U32:
  (era * 146097 + (yoe * 365 + yoe / 4 - yoe / 100 + doy) - 719468 : U32)

def days.fin(+y: U32, +mp: U32, +d: U32) -> U32:
  days.era((y / 400 : U32), (y % 400 : U32), (((153 * mp + 2) / 5) + d - 1 : U32))

# Days since 1970-01-01 of a civil date (days_from_civil; y >= 1970).
def days(+y: U32, +m: U32, +d: U32) -> U32:
  days.fin(sel(U32.is_le(m, 2), (y - 1 : U32), y), sel(U32.is_gt(m, 2), (m - 3 : U32), (m + 9 : U32)), d)

def digits_end.pick(d: Bool, c: Char, t: String, dropped: String) -> String:
  match d:
    case True{}:
      dropped
    case False{}:
      SCon{c, t}

# Drop a leading run of digits.
def digits_end(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, +t}:
      digits_end.pick(Char.is_digit(c), c, t, digits_end(t))

def frac.pick(dot: Bool, c: Char, t: String) -> String:
  match dot:
    case True{}:
      digits_end(t)
    case False{}:
      SCon{c, t}

def frac(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      frac.pick(Char.is_eq(c, '.') || Char.is_eq(c, ','), c, t)

def tz.min.sel(a: Bool, b: Bool, c: Bool, +t: String) -> Maybe<&2, U32>:
  match a b c:
    case True{} _ _:
      Some{0}
    case False{} True{} _:
      num(t, 3n, 2n)
    case False{} False{} True{}:
      num(t, 2n, 2n)
    case False{} False{} False{}:
      None{}

def tz.min.pick(+n: Nat, +t: String) -> Maybe<&2, U32>:
  tz.min.sel(Nat.is_eq(n, 2n), Nat.is_eq(n, 5n), Nat.is_eq(n, 4n), t)

def tz.min(+t: String) -> Maybe<&2, U32>:
  tz.min.pick(String.length(t), t)

def tz.off.pick(ok: Bool, neg: Bool, +mag: U32) -> Maybe<&2, U32>:
  match ok:
    case False{}:
      None{}
    case True{}:
      Some{sel(neg, (86400 - mag : U32), (86400 + mag : U32))}

# The zone offset in seconds, biased by 86400 so it stays unsigned: `Z`,
# `+HH:MM`, `-HH`, `+HHMM`, or none (read as UTC, as the reference's naive
# stamps are).
def tz.off(neg: Bool, +h: U32, +m: U32) -> Maybe<&2, U32>:
  tz.off.pick(U32.is_lt(h, 24) && U32.is_lt(m, 60), neg, (h * 3600 + m * 60 : U32))

def tz.hm(neg: Bool, +t: String) -> Maybe<&2, U32>:
  do Maybe<&2, U32>:
    h : U32 <- num(t, 0n, 2n)
    m : U32 <- tz.min(t)
    tz.off(neg, h, m)

def tz.z(t: String) -> Maybe<&2, U32>:
  match t:
    case SNil{}:
      Some{86400}
    case SCon{c, u}:
      None{}

def tz.head(z: Bool, plus: Bool, minus: Bool, t: String) -> Maybe<&2, U32>:
  match z plus minus:
    case True{} _ _:
      tz.z(t)
    case False{} True{} _:
      tz.hm(False{}, t)
    case False{} False{} True{}:
      tz.hm(True{}, t)
    case False{} False{} False{}:
      None{}

def tz(s: String) -> Maybe<&2, U32>:
  match s:
    case SNil{}:
      Some{86400}
    case SCon{+c, t}:
      tz.head(Char.is_eq(c, 'Z') || Char.is_eq(c, 'z'), Char.is_eq(c, '+'), Char.is_eq(c, '-'), t)

# local = utc + offset, so utc = local - offset (offset = biased - 86400).
def shift(+local: U32, biased: U32) -> U32:
  (local + 86400 - biased : U32)

def finish(ok: Bool, +local: U32, off: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match ok off:
    case False{} _:
      None{}
    case True{} None{}:
      None{}
    case True{} Some{o}:
      Some{shift(local, o)}

def parse.fin(+s: String, +y: U32, +mo: U32, +d: U32, +h: U32, +mi: U32, +sec: U32) -> Maybe<&2, U32>:
  finish(valid(y, mo, d, h, mi, sec) && at(s, 4n, '-', '-') && at(s, 7n, '-', '-')
    && at(s, 10n, 'T', ' ') && at(s, 13n, ':', ':') && at(s, 16n, ':', ':'),
    (days(y, mo, d) * 86400 + h * 3600 + mi * 60 + sec : U32), tz(frac(String.drop(s, 19n))))

def parse.time(+s: String, y: U32, mo: U32, d: U32) -> Maybe<&2, U32>:
  do Maybe<&2, U32>:
    h : U32 <- num(s, 11n, 2n)
    mi : U32 <- num(s, 14n, 2n)
    sec : U32 <- num(s, 17n, 2n)
    parse.fin(s, y, mo, d, h, mi, sec)

# Unix seconds of `2026-10-30T09:00:00+00:00`, `...Z`, `...00.123456Z`, a
# `-HH:MM` offset, or a bare stamp (read as UTC); None when malformed.
def parse_iso8601(+s: String) -> Maybe<&2, U32>:
  do Maybe<&2, U32>:
    y : U32 <- num(s, 0n, 4n)
    mo : U32 <- num(s, 5n, 2n)
    d : U32 <- num(s, 8n, 2n)
    parse.time(s, y, mo, d)

