import Base

# Data types of the pure decision core, and the JSON names the CLI emits.
#
# Units: percentages are centi-percent Nat (100 % = 10000, so 85.5 % = 8550);
# times are unix seconds as Nat; a Nat of 0 in `backoff_until`, `held_until`
# and `claim_until` means "not set"; a `Maybe<Nat>` reset that is None is the
# reference's `inf` ("unknown or already past").
#
# Reference: claude_swap 0.27.2 autoswitch.py / poll_policy.py / usage_store.py
# / oauth.py, with patch 0002 (unknown headroom never counts toward failover).

type AcctKind is Data:
  SetupToken{}
  FullLogin{}
  ApiKey{}

type Account is Data:
  Account{slot: Nat, email: String, kind: AcctKind, disabled: Bool}

# A per-model scoped window (Opus, Fable, ...).
type Scoped is Data:
  Scoped{name: String, pct: Nat, reset: Maybe<&2, Nat>}

type ErrKind is Data:
  ErrNone{}
  ErrHttp429{}
  ErrOther{}

# A derived state laid over a stored row at read time. `TokenExpired` is the
# idle-Claude-Code sentinel; every sentinel hides the row's windows.
# 0 when the last fetch left no error, else 1: how a row built without a
# stored failure count says whether it is failing.
def failing(+e: ErrKind) -> Nat:
  match e:
    case ErrNone{}:
      0n
    case o:
      1n

type Sentinel is Data:
  NoSentinel{}
  TokenExpired{}
  OtherSentinel{}

# One account's usage row. `five`/`seven` are None when the API sent no such
# window. `fetched_at` is None before the first success.
type Usage is Data:
  Usage{slot: Nat, five: Maybe<&2, Nat>, five_reset: Maybe<&2, Nat>, seven: Maybe<&2, Nat>, seven_reset: Maybe<&2, Nat>, scoped: List<&2, Scoped>, fetched_at: Maybe<&2, Nat>, backoff_until: Nat, last_error: ErrKind, failures: Nat, next_poll_at: Maybe<&2, Nat>, poll_interval: Nat, auth_dead: Nat, held_until: Nat, claim_until: Nat, sentinel: Sentinel}

# One relevant window: the utilization and, if the API sent one, its reset.
type Win is Data:
  Win{pct: Nat, reset: Maybe<&2, Nat>}

type Strategy is Data:
  Best{}
  ConsumeFirst{}

type Config is Data:
  Config{
    threshold: Nat,
    models: List<&2, String>,
    strategy: Strategy,
    interval: Nat,
    cooldown: Nat,
    hysteresis: Nat,
    serve_ttl: Nat,
    unhealthy_ticks: Nat,
    include_api: Bool
  }

type Trigger is Data:
  Proactive{}
  AtLimit{}
  Failover{}
  ConsumeFirstT{}

# What the last switch recorded (autoswitch_state.json): the headroom and
# binding recovery of the account it left, and the trigger. `NoSnap` is a
# record written before the snapshot existed.
type Snap is Data:
  NoSnap{}
  Snap{headroom: Maybe<&2, Nat>, recovery: Maybe<&2, Nat>, trigger: Maybe<&2, Trigger>}

type State is Data:
  State{last_at: Maybe<&2, Nat>, last_to: Maybe<&2, Nat>, last_from: Maybe<&2, Nat>, snap: Snap}

# The engine's in-memory counters: consecutive unhealthy ticks, and when the
# idle hold for an expired token began. `Mem{0n, None{}}` is a fresh process.
type Mem is Data:
  Mem{unhealthy: Nat, idle_since: Maybe<&2, Nat>}

type Reason is Data:
  UnmanagedActive{}
  ActiveApiKey{}
  BelowThreshold{}
  ActiveIdle{}
  ActiveUsageUnknown{}
  Cooldown{}
  NoCandidates{}
  NoComparison{}
  ResetUnknown{}
  AlreadyConsumingSoonest{}
  NoQualifyingCandidate{}
  AllExhausted{earliest: Maybe<&2, Nat>}

# How the target was ranked: by headroom (`MHead`), by weekly reset
# (consume-first, `MReset`), by recovery (all accounts above the threshold:
# `MRec0` back soon, `MRec1` back late, `MFallback` the one-way fallback), or
# as the last-resort API-key account (`MApiLast`).
type Mode is Data:
  MHead{}
  MReset{}
  MRec0{}
  MRec1{}
  MFallback{}
  MApiLast{}

# `Switch.rec` is the winner's ranking time (reset or recovery) when the mode
# ranks by one; `bar` is the no-return bar that applied to this pick.
type Decision is Data:
  NoSwitch{reason: Reason, detail: String}
  Switch{to: Nat, trigger: Trigger, reason: String, headroom: Nat, mode: Mode, rec: Maybe<&2, Nat>, bar: Maybe<&2, Nat>}

def full() -> Nat:
  10000n

def default_config() -> Config:
  Config{9000n, Nil{}, Best{}, 60n, 300n, 1000n, 180n, 3n, False{}}

def fresh_state() -> State:
  State{None{}, None{}, None{}, NoSnap{}}

def fresh_mem() -> Mem:
  Mem{0n, None{}}

# ------------------------------------------------- names (JSON reason values)

def reason.name.more(+r: Reason) -> String:
  match r:
    case Cooldown{}:
      "cooldown"
    case NoCandidates{}:
      "no-candidates"
    case NoComparison{}:
      "no-comparison"
    case ResetUnknown{}:
      "reset-unknown"
    case AlreadyConsumingSoonest{}:
      "already-consuming-soonest"
    case NoQualifyingCandidate{}:
      "no-qualifying-candidate"
    case o:
      "all-exhausted"

def reason.name(+r: Reason) -> String:
  match r:
    case UnmanagedActive{}:
      "unmanaged-active-account"
    case ActiveApiKey{}:
      "active-api-key"
    case BelowThreshold{}:
      "below-threshold"
    case ActiveIdle{}:
      "active-idle"
    case ActiveUsageUnknown{}:
      "active-usage-unknown"
    case o:
      reason.name.more(o)

def trigger.name(+t: Trigger) -> String:
  match t:
    case Proactive{}:
      "proactive"
    case AtLimit{}:
      "at-limit"
    case Failover{}:
      "failover"
    case ConsumeFirstT{}:
      "consume-first"

# Exit codes of `auto --once`: 0 switched, 2 no action, 3 blocked.
def reason.exit(+r: Reason) -> U32:
  match r:
    case NoCandidates{}:
      3
    case NoComparison{}:
      3
    case NoQualifyingCandidate{}:
      3
    case AllExhausted{e}:
      3
    case o:
      2

def exit_code(+d: Decision) -> U32:
  match d:
    case NoSwitch{r, detail}:
      reason.exit(r)
    case Switch{to, t, why, h, mode, rec, bar}:
      0
