#!/bin/sh
# Parity fixtures 11-18 (their switch steps) against the Bend driver.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
BEND=${BEND:-bend}
mkdir -p "$root/bin"
nice -n 19 "$BEND" "$here/it/switch_main.bend" -o "$root/bin/switch-it" > /dev/null
nice -n 19 python3 -I "$here/switch_replay.py" "$root/bin/switch-it"
