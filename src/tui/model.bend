import Base

# What the dashboard draws: one value, built by read.bend from the files the
# daemon and the CLI keep, drawn by view.bend. Percentages are centi-percent
# (4750 = 47.5 %); times are unix seconds.

# One usage window: "5h", "7d" or a model name; None pct is unknown.
type Win is Data:
  Win{label: String, pct: Maybe<&2, U32>, reset: Maybe<&2, U32>}

# One managed account. `age` is the seconds since its last good reading;
# `note` explains an unreadable one ("" when there is nothing to say).
type Acct is Data:
  Acct{slot: String, email: String, alias: String, tag: String, active: Bool, disabled: Bool, wins: List<&2, Win>, age: Maybe<&2, U32>, note: String}

# The auto-switch line: is the daemon running, and its settings.
type Hdr is Data:
  Hdr{version: String, live: Bool, pid: Maybe<&2, U32>, threshold: Maybe<&2, U32>, interval: Maybe<&2, U32>, next_poll: Maybe<&2, U32>}

# Everything for one frame. `off` is the local UTC offset biased by 86400
# (Clock.tz), `log` the last daemon.log lines, already formatted.
type Snap is Data:
  Snap{now: U32, off: U32, hdr: Hdr, accts: List<&2, Acct>, log: List<&2, String>}

# How to draw it: terminal width in columns, colour on or off (NO_COLOR).
type View is Data:
  View{width: U32, color: Bool}

def win_label(+w: Win) -> String:
  match w:
    case Win{l, p, r}:
      l

def win_pct(+w: Win) -> Maybe<&2, U32>:
  match w:
    case Win{l, p, r}:
      p

def win_reset(+w: Win) -> Maybe<&2, U32>:
  match w:
    case Win{l, p, r}:
      r

def acct_wins(+a: Acct) -> List<&2, Win>:
  match a:
    case Acct{s, e, al, t, ac, d, w, g, n}:
      w

def acct_slot(+a: Acct) -> String:
  match a:
    case Acct{s, e, al, t, ac, d, w, g, n}:
      s

def acct_active(+a: Acct) -> Bool:
  match a:
    case Acct{s, e, al, t, ac, d, w, g, n}:
      ac

def acct_disabled(+a: Acct) -> Bool:
  match a:
    case Acct{s, e, al, t, ac, d, w, g, n}:
      d

def acct_email(+a: Acct) -> String:
  match a:
    case Acct{s, e, al, t, ac, d, w, g, n}:
      e

def acct_age(+a: Acct) -> Maybe<&2, U32>:
  match a:
    case Acct{s, e, al, t, ac, d, w, g, n}:
      g

def acct_note(+a: Acct) -> String:
  match a:
    case Acct{s, e, al, t, ac, d, w, g, n}:
      n
