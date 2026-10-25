#!/bin/sh
# now_s answers wall-clock unix seconds, and its ISO form agrees with date(1).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
mkdir -p "$root/bin"
BEND=${BEND:-bend}
nice -n 19 "$BEND" "$here/it/clock_main.bend" -o "$root/bin/clock-it" >/dev/null
before=$(date -u +%s)
out=$("$root/bin/clock-it")
after=$(date -u +%s)
secs=${out%% *}
iso=${out#* }
[ "$secs" -ge "$before" ] && [ "$secs" -le "$after" ] || { echo "now_s $secs outside [$before,$after]" >&2; exit 1; }
want=$(date -u -r "$secs" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$secs" +%Y-%m-%dT%H:%M:%SZ)
[ "$iso" = "$want" ] || { echo "iso $iso != $want" >&2; exit 1; }
