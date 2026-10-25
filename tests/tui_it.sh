#!/bin/sh
# `cswap tui` against a scratch state directory: one frame (--once) compared to
# golden text, colour handling, the width cut, the loop, and bad arguments.
# Fake data only (tests/fixtures/tui/state); the clock and the zone are pinned.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
BEND=${BEND:-bend}
mkdir -p "$root/bin"
nice -n 19 "$BEND" "$here/it/tui_main.bend" -o "$root/bin/tui-it" > /dev/null
it="$root/bin/tui-it"
fx="$here/fixtures/tui"
d=$(mktemp -d "${TMPDIR:-/tmp}/cswap-tui-it.XXXXXX")
loop_pid=""
cleanup() {
  [ -z "$loop_pid" ] || kill "$loop_pid" 2> /dev/null || true
  rm -rf "$d"
}
trap cleanup EXIT
fail() {
  echo "tui_it: $*" >&2
  exit 1
}

NOW=1792746000
# a scratch HOME whose backup root is the fixture; $1 is the daemon pid
home() {
  rm -rf "$d/home"
  mkdir -p "$d/home/.claude-swap-backup"
  cp -R "$fx/state/." "$d/home/.claude-swap-backup/"
  sed "s/@PID@/$1/" "$fx/state/daemon-status.json" > "$d/home/.claude-swap-backup/daemon-status.json"
}
frame() { # columns, extra env words..., then flags
  cols=$1
  shift
  HOME="$d/home" TZ=UTC CSWAP_TUI_NOW=$NOW COLUMNS=$cols env "$@"
}
same() { # golden, actual
  diff -u "$1" "$2" > "$d/diff" || { cat "$d/diff" >&2; fail "frame differs from $1"; }
}

# a live daemon: this shell's own pid; the golden shows PID in its place
home $$
frame 100 NO_COLOR=1 "$it" --once | sed "s/pid $$/pid PID/" > "$d/live.txt"
same "$fx/once-live.txt" "$d/live.txt"

# the live header shows the daemon's own config (85 / 30s), not settings.json (90 / 60s)
grep -q "threshold 85% · every 30s" "$d/live.txt" || fail "live header must show the daemon's threshold"

# an older status file without a config block: the settings.json values
sed '/"config": {/,/^  },/d' "$d/home/.claude-swap-backup/daemon-status.json" > "$d/old-status.json"
cp "$d/old-status.json" "$d/home/.claude-swap-backup/daemon-status.json"
frame 100 NO_COLOR=1 "$it" --once | grep -q "threshold 90% · every 60s" || fail "no config block: settings fallback"

# a dead one: settings.json, even though the stale status file has a config
home 999999
frame 100 NO_COLOR=1 "$it" --once > "$d/stopped.txt"
same "$fx/once-stopped.txt" "$d/stopped.txt"

# narrower than the content: bars shrink, long lines end in an ellipsis
frame 60 NO_COLOR=1 "$it" --once > "$d/narrow.txt"
same "$fx/once-narrow.txt" "$d/narrow.txt"
awk 'length($0) > 60 { exit 1 }' "$d/narrow.txt" || fail "a line is wider than COLUMNS"

# --no-color is NO_COLOR; an empty NO_COLOR is not set
frame 100 "$it" --once --no-color > "$d/nc.txt"
same "$fx/once-stopped.txt" "$d/nc.txt"
frame 100 NO_COLOR= "$it" --once > "$d/empty.txt"
grep -q "$(printf '\033')" "$d/empty.txt" || fail "empty NO_COLOR must not disable colour"

# colour: escapes present, and removing them leaves the plain frame
frame 100 "$it" --once > "$d/color.txt"
grep -q "$(printf '\033\\[38;5;')" "$d/color.txt" || fail "no colour escapes"
sed "s/$(printf '\033')\\[[0-9;]*m//g" "$d/color.txt" > "$d/stripped.txt"
same "$fx/once-stopped.txt" "$d/stripped.txt"
! grep -q "$(printf '\033')" "$d/stopped.txt" || fail "NO_COLOR frame has escapes"

# no state at all: an empty dashboard, not an error
rm -rf "$d/empty" && mkdir -p "$d/empty"
HOME="$d/empty" TZ=UTC CSWAP_TUI_NOW=$NOW COLUMNS=100 NO_COLOR=1 "$it" --once > "$d/none.txt"
grep -q "No managed accounts yet" "$d/none.txt" || fail "empty state"
grep -q "no daemon log yet" "$d/none.txt" || fail "empty log"

# the loop redraws every N seconds until killed
home 999999
(HOME="$d/home" TZ=UTC CSWAP_TUI_NOW=$NOW NO_COLOR=1 "$it" --interval 1 > "$d/loop.txt") &
loop_pid=$!
sleep 3
kill "$loop_pid" 2> /dev/null || true
wait "$loop_pid" 2> /dev/null || true
loop_pid=""
n=$(grep -c "$(printf '\033')\\[H" "$d/loop.txt" || true)
[ "$n" -ge 2 ] || fail "loop drew $n frames in 3 s"

# bad arguments: exit 2 with a usage line
for bad in "--bogus" "--interval" "--interval 0" "--interval x"; do
  # shellcheck disable=SC2086
  set +e
  HOME="$d/home" "$it" $bad > /dev/null 2> "$d/err"
  rc=$?
  set -e
  [ "$rc" = 2 ] || fail "$bad: exit $rc, want 2"
  grep -q "^usage: cswap tui" "$d/err" || fail "$bad: no usage line"
done
echo "tui_it: ok"
