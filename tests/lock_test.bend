import Base
import ../src/lock.bend as Lock

# The pure parts of lock: the contention paths run in tests/lock_it.sh.

def tries_zero_means_one_attempt() -> {Lock.tries(0) == 0n : Nat}:
  {==}

def tries_per_100ms() -> {Lock.tries(300) == 3n : Nat}:
  {==}

def tried_held() -> {Lock.tried.bool(Done{1}) == Done{True{}} : Result<&1, &1, U32 & String, Bool>}:
  {==}

def tried_contended() -> {Lock.tried.bool(Done{0}) == Done{False{}} : Result<&1, &1, U32 & String, Bool>}:
  {==}

def tried_error_passes_through() -> {Lock.tried.bool(Fail{(38, "nosys")}) == Fail{(38, "nosys")} : Result<&1, &1, U32 & String, Bool>}:
  {==}
