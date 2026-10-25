#!/bin/sh
# lock against real processes: two Bend processes contend on one lock file,
# and a Python fcntl.flock holder (the reference's locking.py primitive)
# blocks the Bend side, and the other way round.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
BEND=${BEND:-bend}
mkdir -p "$root/bin"
nice -n 19 "$BEND" "$here/it/lock_main.bend" -o "$root/bin/lock-it" > /dev/null
it="$root/bin/lock-it"
d=$(mktemp -d "${TMPDIR:-/tmp}/cswap-lock-it.XXXXXX")
pids=""
cleanup() {
  for p in $pids; do kill "$p" 2> /dev/null || true; done
  rm -rf "$d"
}
trap cleanup EXIT

fail() {
  echo "lock_it: $*" >&2
  exit 1
}

# Wait up to ~5s for a holder to print "held" into its log.
await_held() {
  n=0
  while ! grep -q held "$1" 2> /dev/null; do
    n=$((n + 1))
    [ "$n" -le 100 ] || fail "holder never reported held ($1)"
    sleep 0.05
  done
}

lock="$d/state/.lock"

# 1. Free lock: acquired at once, parent directory created.
[ "$("$it" try "$lock" 0)" = acquired ] || fail "free lock not acquired"
[ -d "$d/state" ] || fail "parent dir not created"

# 2. Bend holder blocks a Bend waiter, then lets a patient one in.
"$it" hold "$lock" 1500 > "$d/h1.log" &
pids="$pids $!"
await_held "$d/h1.log"
[ "$("$it" try "$lock" 0)" = timeout ] || fail "contended lock acquired with timeout 0"
[ "$("$it" try "$lock" 300)" = timeout ] || fail "contended lock acquired within 300ms"
[ "$("$it" try "$lock" 5000)" = acquired ] || fail "patient waiter never got the lock"
grep -q released "$d/h1.log" || fail "holder did not release"

# 3. A Python flock holder (same call locking.py makes) blocks Bend.
nice -n 19 python3 -I -c '
import fcntl, sys, time
f = open(sys.argv[1], "w")
fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
print("held", flush=True)
time.sleep(1.5)
' "$lock" > "$d/py.log" &
pids="$pids $!"
await_held "$d/py.log"
[ "$("$it" try "$lock" 300)" = timeout ] || fail "Python holder did not block Bend"
[ "$("$it" try "$lock" 5000)" = acquired ] || fail "Bend never got the lock after Python released"

# 4. A Bend holder blocks a Python waiter (LOCK_NB raises BlockingIOError).
"$it" hold "$lock" 2000 > "$d/h2.log" &
pids="$pids $!"
await_held "$d/h2.log"
out=$(nice -n 19 python3 -I -c '
import fcntl, sys
f = open(sys.argv[1], "w")
try:
    fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    print("acquired")
except BlockingIOError:
    print("blocked")
' "$lock")
[ "$out" = blocked ] || fail "Bend holder did not block Python (got $out)"
wait

# 5. Death releases: a holder killed mid-hold frees the lock.
"$it" hold "$lock" 60000 > "$d/h3.log" &
holder=$!
pids="$pids $holder"
await_held "$d/h3.log"
kill -9 "$holder"
wait "$holder" 2> /dev/null || true
[ "$("$it" try "$lock" 2000)" = acquired ] || fail "lock still held after the holder was killed"
