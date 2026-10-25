import Base
import ./types.bend as T

# Usage rows: relevant windows, trusted headroom, poll eligibility, backoff.

# ------------------------------------------------------- percent labels

def pct.two(+t: Nat, +o: Nat) -> String:
  match o:
    case 0n:
      Nat.show(t)
    case 1n+p:
      Nat.show(t) ++ Nat.show(o)

def pct.frac.pair(qr: Nat & Nat) -> String:
  (t, o) = qr
  pct.two(t, o)

def pct.frac(+q: Nat, +r: Nat) -> String:
  match r:
    case 0n:
      Nat.show(q)
    case 1n+p:
      Nat.show(q) ++ "." ++ pct.frac.pair(Nat.divmod(r, 10n))

def pct.label.pair(qr: Nat & Nat) -> String:
  (q, r) = qr
  pct.frac(q, r)

# 4000 -> "40", 8550 -> "85.5": the reference's `%.10g` for two-digit inputs.
def pct.label(+c: Nat) -> String:
  pct.label.pair(Nat.divmod(c, 100n))

# ------------------------------------------------------------- windows

def win.opt(+p: Maybe<&2, Nat>, +r: Maybe<&2, Nat>, +rest: List<&2, T.Win>) -> List<&2, T.Win>:
  match p:
    case None{}:
      rest
    case Some{x}:
      Con{T.Win{x, r}, rest}

def win.keep(+hit: Bool, +w: T.Win, +rest: List<&2, T.Win>) -> List<&2, T.Win>:
  match hit:
    case True{}:
      Con{w, rest}
    case False{}:
      rest

# `n` is lowercase; the configured name is lowercased here. `all` matches any.
def model.wanted(+n: String, +ms: List<&2, String>) -> Bool:
  match ms:
    case Nil{}:
      False{}
    case Con{m, t}:
      String.eq(n, String.to_lower(m)) || String.eq("all", String.to_lower(m)) || model.wanted(n, t)

def win.scoped.one(+s: T.Scoped, +ms: List<&2, String>, +rest: List<&2, T.Win>) -> List<&2, T.Win>:
  match s:
    case T.Scoped{name, p, r}:
      win.keep(model.wanted(String.to_lower(name), ms), T.Win{p, r}, rest)

def win.scoped(+ss: List<&2, T.Scoped>, +ms: List<&2, String>) -> List<&2, T.Win>:
  match ss:
    case Nil{}:
      Nil{}
    case Con{s, t}:
      win.scoped.one(s, ms, win.scoped(t, ms))

# The relevant windows, in API order: 5h, 7d, then the wanted scoped ones.
# Never spend.
def windows(+u: T.Usage, +ms: List<&2, String>) -> List<&2, T.Win>:
  match u:
    case T.Usage{slot, five, fr, seven, sr, ss, fa, bo, er, nfl, np, pi, ad, hu, cu, se}:
      win.opt(five, fr, win.opt(seven, sr, win.scoped(ss, ms)))

def win.max.step(+acc: Maybe<&2, Nat>, +p: Nat) -> Maybe<&2, Nat>:
  match acc:
    case None{}:
      Some{p}
    case Some{x}:
      Some{Nat.max(x, p)}

def win.max(+ws: List<&2, T.Win>, +acc: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match ws:
    case Nil{}:
      acc
    case Con{w, t}:
      match w:
        case T.Win{p, r}:
          win.max(t, win.max.step(acc, p))

def head.of(+m: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{p}:
      Some{Nat.sub(T.full(), p)}

# 100 - max(pct) over the relevant windows; None with no windows.
def headroom.raw(+u: T.Usage, +ms: List<&2, String>) -> Maybe<&2, Nat>:
  head.of(win.max(windows(u, ms), None{}))

# ----------------------------------------------------------- freshness

def err.is_none(+e: T.ErrKind) -> Bool:
  match e:
    case T.ErrNone{}:
      True{}
    case o:
      False{}

def before.opt(+now: Nat, +m: Maybe<&2, Nat>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{n}:
      Nat.is_lt(now, n)

# Trust is extended while the row is failing (consecutive failures > 0, as the
# reference), planned, held or claimed.
def fresh.ext(+now: Nat, +nf: Nat, +np: Maybe<&2, Nat>, +hu: Nat, +cu: Nat) -> Bool:
  Nat.is_gt(nf, 0n) || before.opt(now, np) || Nat.is_lt(now, hu) || Nat.is_lt(now, cu)

def win.reset(+w: T.Win) -> Maybe<&2, Nat>:
  match w:
    case T.Win{p, r}:
      r

def soon.min(+a: Maybe<&2, Nat>, +b: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match a b:
    case None{} _:
      b
    case Some{x} None{}:
      a
    case Some{x} Some{y}:
      Some{Nat.min(x, y)}

# The soonest reset among the relevant windows (past ones included): once it
# passes, that window is zeroed and the snapshot is obsolete.
def win.soonest(+ws: List<&2, T.Win>, +acc: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match ws:
    case Nil{}:
      acc
    case Con{w, t}:
      win.soonest(t, soon.min(acc, win.reset(w)))

# No window reset known: only the age ceiling applies.
def soon.ok(+now: Nat, +soonest: Maybe<&2, Nat>) -> Bool:
  match soonest:
    case None{}:
      True{}
    case Some{s}:
      Nat.is_lt(now, s)

# How long a failing row's reading may be trusted. After an http-429 the
# account's windows did not move, so the reading is a valid lower bound until
# the soonest window resets: now < min(earliest reset, fetched_at + 7200 s).
# Any other failure is no evidence the reading still holds: at most 3600 s.
def within.ceiling(+e: T.ErrKind, +age: Nat, +now: Nat, +soonest: Maybe<&2, Nat>) -> Bool:
  match e:
    case T.ErrHttp429{}:
      Nat.is_lt(age, 7200n) && soon.ok(now, soonest)
    case o:
      Nat.is_le(age, 3600n)

def fresh.age(+age: Nat, +ext: Bool, +within: Bool) -> Bool:
  Nat.is_le(age, 300n) || (ext && within)

# A reading is decision-grade when it is at most 300 s old, or its trust is
# extended (the row is failing, planned, held or claimed) and within the
# ceiling of `within.ceiling`.
def fresh.at(+fa: Maybe<&2, Nat>, +now: Nat, +e: T.ErrKind, +nf: Nat, +np: Maybe<&2, Nat>, +hu: Nat, +cu: Nat, +soonest: Maybe<&2, Nat>) -> Bool:
  match fa:
    case None{}:
      False{}
    case Some{f}:
      fresh.age(Nat.sub(now, f), fresh.ext(now, nf, np, hu, cu), within.ceiling(e, Nat.sub(now, f), now, soonest))

def fresh(+u: T.Usage, +now: Nat, +ms: List<&2, String>) -> Bool:
  match u:
    case T.Usage{slot, five, fr, seven, sr, ss, fa, bo, +er, nfl, np, pi, ad, hu, cu, +se}:
      fresh.at(fa, now, er, nfl, np, hu, cu, win.soonest(windows(u, ms), None{}))

def sent.none(+s: T.Sentinel) -> Bool:
  match s:
    case T.NoSentinel{}:
      True{}
    case o:
      False{}

# A decision-grade reading: fresh, and not hidden behind a sentinel.
def trusted(+u: T.Usage, +now: Nat, +ms: List<&2, String>) -> Bool:
  match u:
    case T.Usage{slot, five, fr, seven, sr, ss, fa, bo, +er, nfl, np, pi, ad, hu, cu, +se}:
      sent.none(se) && fresh.at(fa, now, er, nfl, np, hu, cu, win.soonest(windows(u, ms), None{}))

def head.if(+ok: Bool, +h: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      h
    case False{}:
      None{}

# The decision value of an account: None when there is no trusted reading or
# the reading carries no relevant window.
def headroom(+u: T.Usage, +now: Nat, +ms: List<&2, String>) -> Maybe<&2, Nat>:
  head.if(trusted(u, now, ms), headroom.raw(u, ms))

def usage.slot(+u: T.Usage) -> Nat:
  match u:
    case T.Usage{slot, five, fr, seven, sr, ss, fa, bo, er, nfl, np, pi, ad, hu, cu, se}:
      slot

def usage.backoff_until(+u: T.Usage) -> Nat:
  match u:
    case T.Usage{slot, five, fr, seven, sr, ss, fa, bo, er, nfl, np, pi, ad, hu, cu, se}:
      bo

def in_backoff(+u: T.Usage, +now: Nat) -> Bool:
  Nat.is_lt(now, usage.backoff_until(u))

def usage.sentinel(+u: T.Usage) -> T.Sentinel:
  match u:
    case T.Usage{slot, five, fr, seven, sr, ss, fa, bo, er, nfl, np, pi, ad, hu, cu, se}:
      se

def usage.of.pick(+hit: Bool, +u: T.Usage, +rest: Maybe<&2, T.Usage>) -> Maybe<&2, T.Usage>:
  match hit:
    case True{}:
      Some{u}
    case False{}:
      rest

# The first usage row of a slot; None is "no reading".
def usage.of(+slot: Nat, +us: List<&2, T.Usage>) -> Maybe<&2, T.Usage>:
  match us:
    case Nil{}:
      None{}
    case Con{u, t}:
      usage.of.pick(Nat.is_eq(slot, usage.slot(u)), u, usage.of(slot, t))

def account.slot(+a: T.Account) -> Nat:
  match a:
    case T.Account{slot, email, kind, disabled}:
      slot

def account.of.pick(+hit: Bool, +a: T.Account, +rest: Maybe<&2, T.Account>) -> Maybe<&2, T.Account>:
  match hit:
    case True{}:
      Some{a}
    case False{}:
      rest

def account.of(+slot: Nat, +as: List<&2, T.Account>) -> Maybe<&2, T.Account>:
  match as:
    case Nil{}:
      None{}
    case Con{a, t}:
      account.of.pick(Nat.is_eq(slot, account.slot(a)), a, account.of(slot, t))

# Headroom of a row, if there is a row.
def head.row(+m: Maybe<&2, T.Usage>, +now: Nat, +ms: List<&2, String>) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{u}:
      headroom(u, now, ms)

# ------------------------------------------------------- poll policy

def poll.stale(+fa: Maybe<&2, Nat>, +now: Nat, +ttl: Nat) -> Bool:
  match fa:
    case None{}:
      True{}
    case Some{f}:
      Nat.is_gt(Nat.sub(now, f), ttl)

def poll.planned_due(+np: Maybe<&2, Nat>, +now: Nat) -> Bool:
  match np:
    case None{}:
      False{}
    case Some{n}:
      Nat.is_ge(now, n)

# next_poll_at lies further out than max(interval, 600) * 1.1 + 60 s.
def poll.overslept(+np: Maybe<&2, Nat>, +now: Nat, +pi: Nat) -> Bool:
  match np:
    case None{}:
      False{}
    case Some{n}:
      Nat.is_gt(Nat.mul(10n, Nat.sub(Nat.sub(n, now), 60n)), Nat.mul(11n, Nat.max(pi, 600n)))

def poll.unplanned(+np: Maybe<&2, Nat>) -> Bool:
  match np:
    case None{}:
      True{}
    case Some{n}:
      False{}

def poll.ready(+np: Maybe<&2, Nat>, +now: Nat, +pi: Nat, +fa: Maybe<&2, Nat>, +ttl: Nat) -> Bool:
  poll.planned_due(np, now)
    || (poll.stale(fa, now, ttl) && (poll.unplanned(np) || poll.overslept(np, now, pi)))

def poll.gate(+blocked: Bool, +ready: Bool) -> Bool:
  match blocked:
    case True{}:
      False{}
    case False{}:
      ready

# Is this row due a fetch on a scheduled auto tick? Never inside backoff,
# dead (one auth strike), held or claimed; then the plan or staleness decides.
def poll_due(+u: T.Usage, +now: Nat, +cfg: T.Config) -> Bool:
  match u:
    case T.Usage{slot, five, fr, seven, sr, ss, fa, +bo, er, nfl, np, pi, ad, hu, cu, se}:
      match cfg:
        case T.Config{thr, ms, st, iv, cd, hy, ttl, ut, ia}:
          poll.gate(
            Nat.is_lt(now, bo) || Nat.is_ge(ad, 1n) || Nat.is_lt(now, hu) || Nat.is_lt(now, cu),
            poll.ready(np, now, pi, fa, ttl)
          )

# ------------------------------------------------------------ backoff

def backoff.cap(+k: Nat) -> Nat:
  Nat.min(600n, Nat.mul(30n, Nat.pow(2n, Nat.min(Nat.sub(k, 1n), 5n))))

def backoff.zero(+rl: Bool, +computed: Nat) -> Nat:
  match rl:
    case True{}:
      Nat.min(Nat.max(computed, 300n), 600n)
    case False{}:
      computed

def backoff.bump(+big: Bool, +ra: Nat) -> Nat:
  match big:
    case True{}:
      Nat.add(ra, 900n)
    case False{}:
      ra

def backoff.asked(+rl: Bool, +ra: Nat) -> Nat:
  match rl:
    case True{}:
      Nat.min(4500n, backoff.bump(Nat.is_gt(ra, 600n), ra))
    case False{}:
      Nat.min(3600n, ra)

def backoff.some(+rl: Bool, +ra: Nat, +computed: Nat) -> Nat:
  Nat.max(backoff.asked(rl, ra), computed)

def backoff.retry.some(+r: Nat, +rl: Bool, +computed: Nat) -> Nat:
  match r:
    case 0n:
      backoff.zero(rl, computed)
    case 1n+p:
      backoff.some(rl, r, computed)

def backoff.rate_limited(+e: T.ErrKind) -> Bool:
  match e:
    case T.ErrHttp429{}:
      True{}
    case o:
      False{}

def backoff.retry(+rl: Bool, +ra: Maybe<&2, Nat>, +computed: Nat) -> Nat:
  match ra:
    case None{}:
      computed
    case Some{r}:
      backoff.retry.some(r, rl, computed)

# Seconds of backoff after the n-th consecutive failure: 30, 60, 120, 240,
# 480, 600; a server's Retry-After raises it (Retry-After 0 on an http-429
# means at least 300 s).
def backoff_for(+n: Nat, +e: T.ErrKind, +ra: Maybe<&2, Nat>) -> Nat:
  backoff.retry(backoff.rate_limited(e), ra, backoff.cap(n))
