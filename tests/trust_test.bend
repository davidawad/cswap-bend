import Base
import ../src/policy/types.bend as T
import ../src/policy/usage.bend as U

# How long a failing row's last reading is trusted (contract 2.1, reference
# usage_store._rate_limited_trust_ok). A reading is read at `now`; it was
# fetched at 0, so its age is `now`. After an http-429 trust lasts until
# min(earliest relevant-window reset, 7200 s); any other failure: 3600 s.

def row(+e: T.ErrKind, r5: Maybe<&2, Nat>, r7: Maybe<&2, Nat>, ss: List<&2, T.Scoped>) -> T.Usage:
  T.Usage{1n, Some{5000n}, r5, Some{1000n}, r7, ss, Some{0n}, 0n, e, T.failing(e), None{}, 0n, 0n, 0n, 0n, T.NoSentinel{}}

def e429() -> T.ErrKind:
  T.ErrHttp429{}

def eother() -> T.ErrKind:
  T.ErrOther{}

def trusted(u: T.Usage, now: Nat) -> Bool:
  U.trusted(u, now, Nil{})

# ---- 429 with a known earliest reset before 7200 s

def r429_before_reset() -> {trusted(row(e429(), Some{5000n}, Some{9000n}, Nil{}), 4000n) == True{} : Bool}:
  {==}

def r429_at_reset() -> {trusted(row(e429(), Some{5000n}, Some{9000n}, Nil{}), 5000n) == False{} : Bool}:
  {==}

def r429_earliest_passed_later_window_does_not_help() -> {trusted(row(e429(), Some{5000n}, Some{9000n}, Nil{}), 6000n) == False{} : Bool}:
  {==}

def r429_earliest_is_the_other_window() -> {trusted(row(e429(), Some{9000n}, Some{5000n}, Nil{}), 5500n) == False{} : Bool}:
  {==}

def r429_one_reset_unknown() -> {trusted(row(e429(), Some{5000n}, None{}, Nil{}), 6000n) == False{} : Bool}:
  {==}

# ---- 429 with every reset after 7200 s: the age ceiling binds

def r429_far_resets_inside_ceiling() -> {trusted(row(e429(), Some{9000n}, Some{9500n}, Nil{}), 7100n) == True{} : Bool}:
  {==}

def r429_far_resets_at_ceiling() -> {trusted(row(e429(), Some{9000n}, Some{9500n}, Nil{}), 7200n) == False{} : Bool}:
  {==}

# ---- 429 with no reset known: 7200 s alone

def r429_no_reset_inside() -> {trusted(row(e429(), None{}, None{}, Nil{}), 7100n) == True{} : Bool}:
  {==}

def r429_no_reset_at_ceiling() -> {trusted(row(e429(), None{}, None{}, Nil{}), 7200n) == False{} : Bool}:
  {==}

def r429_no_reset_beyond_an_hour() -> {trusted(row(e429(), None{}, None{}, Nil{}), 3700n) == True{} : Bool}:
  {==}

# ---- any other failure: 3600 s, resets ignored

def other_inside() -> {trusted(row(eother(), None{}, None{}, Nil{}), 3600n) == True{} : Bool}:
  {==}

def other_past_an_hour() -> {trusted(row(eother(), None{}, None{}, Nil{}), 3601n) == False{} : Bool}:
  {==}

def other_ignores_a_passed_reset() -> {trusted(row(eother(), Some{1000n}, Some{1000n}, Nil{}), 3000n) == True{} : Bool}:
  {==}

def other_ignores_a_far_reset() -> {trusted(row(eother(), Some{9000n}, Some{9000n}, Nil{}), 3700n) == False{} : Bool}:
  {==}

# ---- the plain 300 s window is untouched

def fresh_reading_needs_no_extension() -> {trusted(row(T.ErrNone{}, None{}, None{}, Nil{}), 300n) == True{} : Bool}:
  {==}

def stale_reading_without_failure() -> {trusted(row(T.ErrNone{}, None{}, None{}, Nil{}), 301n) == False{} : Bool}:
  {==}

def fresh_reading_ignores_a_passed_reset() -> {trusted(row(e429(), Some{100n}, Some{100n}, Nil{}), 200n) == True{} : Bool}:
  {==}

# ---- a per-model window counts only when that model is selected

def scoped() -> List<&2, T.Scoped>:
  [T.Scoped{"Opus", 9700n, Some{3000n}}]

def model_window_reset_counts() -> {U.trusted(row(e429(), Some{9000n}, Some{9500n}, scoped()), 4000n, ["opus"]) == False{} : Bool}:
  {==}

def model_window_reset_ignored_otherwise() -> {U.trusted(row(e429(), Some{9000n}, Some{9500n}, scoped()), 4000n, Nil{}) == True{} : Bool}:
  {==}

# ---- headroom follows trust

def headroom_trusted() -> {U.headroom(row(e429(), Some{5000n}, Some{9000n}, Nil{}), 4000n, Nil{}) == Some{5000n} : Maybe<&2, Nat>}:
  {==}

def headroom_unknown_after_reset() -> {U.headroom(row(e429(), Some{5000n}, Some{9000n}, Nil{}), 5000n, Nil{}) == None{} : Maybe<&2, Nat>}:
  {==}
