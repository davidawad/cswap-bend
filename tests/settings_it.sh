#!/bin/sh
# `config` against a scratch backup dir: fixture 32's steps (set, get --json,
# list --json, an out-of-range set that leaves the file alone, unset), the
# 0600 file and 0700 dir, and the strict-write refusals. The driver is built
# from a temp copy of src/ (a tiny main over Settings.config), so no file is
# added to the repo. Never touches the real ~/.claude-swap-backup, ~/.claude
# or ~/.claude.json: everything lives under a temp dir.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
BEND=${BEND:-bend}
T=$(mktemp -d "${TMPDIR:-/tmp}/cswap-settings-it.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/src" "$T/it"
cp -R "$root/src/." "$T/src/"
cat > "$T/it/main.bend" << 'EOF'
import Base
import ../src/setcmd.bend as Setcmd
import ../src/cmd.bend as Cmd

# settings-it ROOT json|text ARGS...: prints exit=N, then stdout, then stderr.
def show(o: Cmd.Out) -> IO(Unit):
  match o:
    case Cmd.Out{code, out, err}:
      IO.print("exit=" ++ U32.show(code) ++ "\n--stdout--\n" ++ out ++ "--stderr--\n" ++ err)

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{root, Con{j, rest}}}:
      IO.bind(Cmd.Out, Unit, Setcmd.config(root, rest, String.eq(j, "json")), show)
    case _:
      IO.print("usage: settings-it ROOT json|text ARGS...")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
EOF
(cd "$T/it" && nice -n 19 "$BEND" main.bend -o "$T/settings-it" > /dev/null)
it="$T/settings-it"
B="$T/home/.claude-swap-backup"
F="$B/settings.json"

fail() {
  echo "settings_it: $*" >&2
  exit 1
}
mode() { stat -c %a "$1" 2> /dev/null || stat -f %Lp "$1"; }
# run config; $out is the whole report (exit line, stdout, stderr)
cfg() {
  out=$("$it" "$B" "$@")
}
has() {
  case "$out" in *"$1"*) ;; *) fail "$2: output lacks '$1': $out" ;; esac
}
code() {
  case "$out" in "exit=$1"*) ;; *) fail "$2: want exit $1: $out" ;; esac
}
same() {
  [ "$(cat "$F")" = "$1" ] || fail "$2: settings.json is: $(cat "$F")"
}

# step 1: set a float; written as 85.0, file 0600, dir 0700
cfg text set autoswitch.threshold 85
code 0 "step 1"
has "autoswitch.threshold = 85" "step 1"
same '{
  "schemaVersion": 1,
  "autoswitch": {
    "threshold": 85.0
  }
}' "step 1"
[ "$(mode "$F")" = 600 ] || fail "step 1: file mode $(mode "$F")"
[ "$(mode "$B")" = 700 ] || fail "step 1: dir mode $(mode "$B")"

# step 2: a choice
cfg text set autoswitch.strategy best
code 0 "step 2"
has "autoswitch.strategy = best" "step 2"

# step 3: get --json
cfg json get autoswitch.threshold
code 0 "step 3"
has '"key": "autoswitch.threshold",
  "value": 85.0,
  "isSet": true' "step 3"

# step 4: list --json, defaults for the unset keys
cfg json list
code 0 "step 4"
has "\"path\": \"$F\"" "step 4"
has '"key": "autoswitch.intervalSeconds",
      "value": 60.0,
      "isSet": false' "step 4"
has '"key": "autoswitch.strategy",
      "value": "best",
      "isSet": true' "step 4"
has '"key": "autoswitch.model",
      "value": null,
      "isSet": false' "step 4"

# step 5: out of range, exit 1, file untouched
before=$(cat "$F")
cfg text set autoswitch.threshold 120
code 1 "step 5"
has "Error: autoswitch.threshold must be between 50 and 99.9" "step 5"
same "$(printf '%s' "$before")" "step 5"

# step 6: unset removes only that key
cfg text unset autoswitch.strategy
code 0 "step 6"
has "autoswitch.strategy unset (default: best)" "step 6"
same '{
  "schemaVersion": 1,
  "autoswitch": {
    "threshold": 85.0
  }
}' "step 6"

# unset of the last key drops its section; unset of an unset key writes nothing
cfg text unset autoswitch.threshold
code 0 "unset last"
same '{
  "schemaVersion": 1
}' "unset last"
cfg text unset autoswitch.threshold
code 0 "unset twice"
has "autoswitch.threshold is not set; nothing to do" "unset twice"

# strict write refusals leave the file alone
for bad in "autoswitch.nope 1" "autoswitch.threshold abc" "autoswitch.unhealthyTicks 3.5" \
  "autoswitch.strategy worst" "autoswitch.includeApiKeyAccounts maybe" "ui.theme blue" "autoswitch.model ' '"; do
  eval "cfg text set $bad"
  code 1 "refusal '$bad'"
  same '{
  "schemaVersion": 1
}' "refusal '$bad'"
done
cfg json get autoswitch.nope
code 1 "json unknown key"
has '"type": "ConfigError"' "json unknown key"

# bool words, unknown keys survive a write
printf '{"extra": {"keep": [1, 2]}, "autoswitch": {"threshold": 60}}' > "$F"
cfg text set autoswitch.includeApiKeyAccounts yes
code 0 "bool yes"
has "autoswitch.includeApiKeyAccounts = true" "bool yes"
same '{
  "extra": {
    "keep": [
      1,
      2
    ]
  },
  "autoswitch": {
    "threshold": 60,
    "includeApiKeyAccounts": true
  },
  "schemaVersion": 1
}' "bool yes"

# a torn file is an error on write and is never replaced; a read still answers
printf '{"autoswitch": ' > "$F"
cfg text set autoswitch.threshold 80
code 1 "torn write"
has "is not valid JSON" "torn write"
[ "$(cat "$F")" = '{"autoswitch": ' ] || fail "torn write: file was replaced"
cfg json get autoswitch.threshold
code 0 "torn read"
has '"value": 90.0' "torn read"

# path, flags
cfg text path
code 0 "path"
has "$F" "path"
cfg json set autoswitch.threshold 80
code 2 "json set"
echo "settings_it: ok"
