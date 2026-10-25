#!/bin/sh
# The command line end to end in a scratch HOME: usage errors, exit codes,
# the confirmation prompts on stdin, the archive on remove, the text views.
# Fake tokens only; no network (nothing here fetches).
set -eu
cli=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
# Every request goes to a closed local port: nothing here may reach the real API.
export CSWAP_TEST_HTTP_BASE=http://127.0.0.1:1
d=$(mktemp -d "${TMPDIR:-/tmp}/cswap-cli-it.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() {
  echo "cli_it: $*" >&2
  exit 1
}
run() { # name argv... ; stdin from $IN (default empty); out in $d/out, err in $d/err, code in $rc
  shift
  rc=0
  HOME="$d" NO_COLOR=1 "$cli" "$@" < "${IN:-/dev/null}" > "$d/out" 2> "$d/err" || rc=$?
}
want() { # name needle file
  grep -qF -- "$2" "$d/$3" || { echo "--- $1: $3 lacks: $2" >&2; cat "$d/$3" >&2; exit 1; }
}
code() { [ "$rc" = "$2" ] || fail "$1: exit $rc, want $2"; }

run help help
code help 0
want help "usage: cswap <command>" out
want help "add-token [TOKEN|-]" out

run version --version
code version 0
want version "cswap-bend" out

run nocmd
code nocmd 2
want nocmd "no command given" err

run bogus bogus
code bogus 2
want bogus "unrecognized arguments: bogus" err

run menubar menubar
code menubar 2
want menubar "menubar is not supported in cswap-bend" err
run menubar2 menubar --install-service
code menubar2 2
want menubar2 "use 'cswap tui'" err

# upgrade and update say how this build is upgraded, and succeed.
for v in upgrade update; do
  run "$v" "$v"
  code "$v" 0
  want "$v" "just build" out
  want "$v" "deploy/install-live" out
done

# watch is the dashboard: one frame with --once, a usage error on a bad flag.
run watch watch --once
code watch 0
want watch "No managed accounts yet" out
run watch2 watch --bogus
code watch2 2
want watch2 "usage: cswap tui" err

# help lists tui, watch, menubar and upgrade.
run help2 help
for w in "cswap tui " "cswap watch " "cswap menubar " "cswap upgrade " "update=upgrade"; do want help2 "$w" out; done

run json-add add --json
code json-add 2
want json-add "--json can only be used with" err

# An empty store lists nothing and says so.
run list list
code list-empty 0
want list-empty "No accounts are managed yet." out

# add-token reads the token from stdin; the token never reaches an output.
printf 'sk-ant-oat01-FAKE-cli-one\n' > "$d/in1"
IN="$d/in1" run add1 add-token - --email one@example.test
code add1 0
want add1 "Added Account 1: one@example.test" out
! grep -q FAKE "$d/out" "$d/err" || fail "add1: token in output"

printf '   \n' > "$d/blank"
IN="$d/blank" run blank add-token -
code blank 1
want blank "Error: Token cannot be empty" err

# An occupied slot asks before overwriting: no cancels, yes overwrites.
printf 'sk-ant-oat01-FAKE-cli-two\n' > "$d/in2"
IN="$d/in2" run occ add-token - --email two@example.test --slot 1
code occ 0
want occ "Slot 1 already occupied" out
want occ "Cancelled" out
[ -f "$d/.claude-swap-backup/credentials/.creds-1-one@example.test.enc" ] || fail "occupied slot lost its credential"

# list over an account with no usage yet: the probe cannot connect, so the row
# reads unavailable with the network error, and the exit stays 0.
run list2 list --json
code list2 0
want list2 '"usageStatus": "unavailable"' out
want list2 '"usageError": "network"' out
run list3 list
code list3 0
want list3 "usage unavailable (network)" out

# remove: n cancels, y archives (never deletes) the credential.
printf 'n\n' > "$d/no"
IN="$d/no" run rm-no remove 1
code rm-no 0
want rm-no "Cancelled" out
[ -f "$d/.claude-swap-backup/credentials/.creds-1-one@example.test.enc" ] || fail "cancelled remove deleted the credential"
printf 'y\n' > "$d/yes"
IN="$d/yes" run rm-yes remove 1
code rm-yes 0
want rm-yes "Removed Account-1 (one@example.test)" out
[ ! -f "$d/.claude-swap-backup/credentials/.creds-1-one@example.test.enc" ] || fail "remove left the credential in place"
ls "$d/.claude-swap-backup/credentials/.removed" | grep -q 'one@example.test.enc$' || fail "remove did not archive the credential"

run rm-gone remove 9
code rm-gone 1
want rm-gone "Error:" err

# The dashboard draws one frame of an empty scratch state and exits 0.
run tui tui --once --no-color
code tui 0

echo "cli_it: ok"
