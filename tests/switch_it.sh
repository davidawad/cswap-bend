#!/bin/sh
# switch on scratch HOMEs with fake tokens: the files it writes, the rules it
# keeps (no credential destroyed, locks released, other keys kept), and the
# live-login-overridden check. The parity fixtures 11-18 run in
# tests/switch_replay.py. Never touches the real ~/.claude*, ~/.claude-swap-backup.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
BEND=${BEND:-bend}
mkdir -p "$root/bin"
nice -n 19 "$BEND" "$here/it/store_main.bend" -o "$root/bin/store-it" > /dev/null
nice -n 19 "$BEND" "$here/it/switch_main.bend" -o "$root/bin/switch-it" > /dev/null
store="$root/bin/store-it"
sw="$root/bin/switch-it"
H=$(mktemp -d "${TMPDIR:-/tmp}/cswap-switch-it.XXXXXX")
trap 'rm -rf "$H"' EXIT
export HOME="$H"
unset CLAUDE_CONFIG_DIR CSWAP_TEST_HTTP_BASE CSWAP_SWITCH_ORACLE_FILE || true
export CSWAP_SWITCH_VERIFY_DELAY_MS=0
B="$H/.claude-swap-backup"

fail() {
  echo "switch_it: $*" >&2
  exit 1
}
mode() { stat -c %a "$1" 2> /dev/null || stat -f %Lp "$1"; }
py() { nice -n 19 python3 -I -c "$@"; }
jget() { py 'import json,sys;d=json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    d=d[int(k)] if isinstance(d,list) else d[k]
print(json.dumps(d) if isinstance(d,(dict,list)) else d)' "$@"; }
rc=0
out=
run() {
  rc=0
  out=$("$@" 2>&1) || rc=$?
}
expect_ok() {
  run "$@"
  [ "$rc" = 0 ] || fail "'$*' failed ($rc): $out"
}
jfield() { printf '%s' "$out" | py 'import json,sys;d=json.load(sys.stdin)
for k in sys.argv[1:]:
    d=d[int(k)] if isinstance(d,list) else d[k]
print(json.dumps(d) if isinstance(d,(dict,list)) else d)' "$@"; }
is() { [ "$1" = "$2" ] || fail "$3: got '$1', want '$2'"; }

live_login() { # email creds-json
  printf '%s' "{\"numStartups\": 7, \"oauthAccount\": {\"emailAddress\": \"$1\", \"accountUuid\": \"\", \"organizationUuid\": null, \"organizationName\": null, \"displayName\": \"Dee\"}, \"theme\": \"dark\", \"primaryApiKey\": \"sk-ant-api03-STALE\"}" > "$H/.claude.json"
  mkdir -p "$H/.claude"
  printf '%s' "$2" > "$H/.claude/.credentials.json"
}

# ---- three slots: two setup-tokens and a managed API key ------------------------------------
"$store" add-token sk-ant-oat01-FAKEAAA a@x.test > /dev/null
"$store" add-token sk-ant-oat01-FAKEBBB b@x.test > /dev/null
"$store" add-token sk-ant-api03-FAKECCCCCCCCCCCCCCCCCCCCCCCC > /dev/null
A='{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKEAAA", "scopes": ["user:inference"]}}'
B_CREDS='{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKEBBB", "scopes": ["user:inference"]}}'
live_login a@x.test "$A"
py 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["activeAccountNumber"]=1;open(p,"w").write(json.dumps(d,indent=2))' "$B/sequence.json"

# ---- direct switch: credentials, oauthAccount, other keys, sequence --------------------------
expect_ok "$sw" switch 2 --json
is "$(jfield switched)" True "switched"
is "$(jfield strategy)" direct "strategy"
is "$(jfield message)" "Switched to Account-2 (b@x.test)" "message"
is "$(cat "$H/.claude/.credentials.json")" "$B_CREDS" "live credential is slot 2's"
is "$(mode "$H/.claude/.credentials.json")" 600 "credential mode"
py '
import json,sys
t=open(sys.argv[1]).read()
d=json.loads(t)
assert t==json.dumps(d,indent=2),"config is not json.dumps(indent=2)"
assert list(d)==["numStartups","oauthAccount","theme"],list(d)   # key order kept, primaryApiKey dropped
assert d["numStartups"]==7 and d["theme"]=="dark"
assert d["oauthAccount"]=={"emailAddress":"b@x.test","accountUuid":"","organizationUuid":None,"organizationName":None},d["oauthAccount"]
' "$H/.claude.json" || fail "config after switch"
is "$(mode "$H/.claude.json")" 600 "config mode"
is "$(jget "$B/sequence.json" activeAccountNumber)" 2 "activeAccountNumber"
is "$(mode "$B/sequence.json")" 600 "sequence mode"
for d in .oauth_refresh.lock; do [ ! -e "$H/.claude/$d" ] || fail "lock dir $d left behind"; done
[ ! -e "$H/.claude.lock" ] && [ ! -e "$H/.claude.json.lock" ] || fail "claude lock dirs left behind"

# the outgoing account's config backup is the live config it had
[ -f "$B/configs/.claude-config-1-a@x.test.json" ] || fail "outgoing config backup missing"

# ---- already on it, then forced ---------------------------------------------------------------
expect_ok "$sw" switch 2 --json
is "$(jfield switched)" False "already-active switched"
is "$(jfield reason)" already-active "already-active reason"
expect_ok "$sw" switch 2 --force --json
is "$(jfield reason)" activated "forced reason"
is "$(jfield message)" "Activated Account-2 (b@x.test) from stored backup" "forced message"

# ---- errors are enveloped, exit 1, nothing changes --------------------------------------------
before=$(cat "$B/sequence.json")
run "$sw" switch 9 --json
[ "$rc" = 1 ] && is "$(jfield error type)" AccountNotFoundError "unknown slot type" && is "$(jfield error message)" "Account-9 does not exist" "unknown slot"
run "$sw" switch 'not an id' --json
[ "$rc" = 1 ] && is "$(jfield error type)" ValidationError "bad id"
run "$sw" switch nobody@x.test --json
[ "$rc" = 1 ] && is "$(jfield error message)" "No account found with identifier: nobody@x.test" "unknown email"
is "$(cat "$B/sequence.json")" "$before" "errors leave the roster alone"

# ---- API-key target: no credentials file, primaryApiKey + approval; back to OAuth undoes it ---
expect_ok "$sw" switch 3 --json
[ ! -e "$H/.claude/.credentials.json" ] || fail "an API-key switch must leave no .credentials.json"
py '
import json,sys
d=json.load(open(sys.argv[1]))
k="sk-ant-api03-FAKECCCCCCCCCCCCCCCCCCCCCCCC"
assert d["primaryApiKey"]==k,d.get("primaryApiKey")
assert d["customApiKeyResponses"]=={"approved":[k[-20:]],"rejected":[]},d["customApiKeyResponses"]
assert d["oauthAccount"]["emailAddress"]=="api-key-3@token.local"
assert d["numStartups"]==7
' "$H/.claude.json" || fail "API-key activation config"
[ -f "$B/credentials/.removed/"*-2-b@x.test.enc ] 2> /dev/null && fail "switching away must not archive a managed slot"
expect_ok "$sw" switch 1 --json
is "$(cat "$H/.claude/.credentials.json")" "$A" "OAuth credential restored"
py 'import json,sys;d=json.load(open(sys.argv[1]));assert "primaryApiKey" not in d and d["oauthAccount"]["emailAddress"]=="a@x.test"' "$H/.claude.json" || fail "primaryApiKey must go when an OAuth account is activated"

# ---- MCP logins ride along to the next account ------------------------------------------------
live_login a@x.test '{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKEAAA", "scopes": ["user:inference"]}, "mcpOAuth": {"srv": {"t": 1}}, "pluginSecrets": {"p": 2}}'
expect_ok "$sw" switch 2 --json
is "$(cat "$H/.claude/.credentials.json")" '{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKEBBB", "scopes": ["user:inference"]}, "mcpOAuth": {"srv": {"t": 1}}, "pluginSecrets": {"p": 2}}' "shared fields carried over"

# ---- rotation: next slot in order, a disabled one is skipped with a warning --------------------
live_login a@x.test "$A"
py 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["activeAccountNumber"]=1;d["accounts"]["2"]["disabled"]=True;open(p,"w").write(json.dumps(d,indent=2))' "$B/sequence.json"
expect_ok "$sw" switch --json
is "$(jfield strategy)" rotation "rotation strategy"
is "$(jfield to number)" 3 "rotation target"
is "$(jfield warnings)" '["Skipped Account-2 (disabled)"]' "rotation warning"
py 'import json,sys;p=sys.argv[1];d=json.load(open(p));del d["accounts"]["2"]["disabled"];open(p,"w").write(json.dumps(d,indent=2))' "$B/sequence.json"

# ---- an unmanaged live login is archived, never destroyed -------------------------------------
Z='{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKEZZZ", "refreshToken": "sk-ant-ort01-FAKEZZZ", "scopes": ["user:inference"]}}'
live_login z@x.test "$Z"
expect_ok "$sw" switch 1 --json
is "$(jfield from number)" None "unmanaged from has no number"
is "$(jfield from email)" z@x.test "unmanaged from email"
kept=$(ls "$B/credentials/.removed" | grep -- '-live-z@x.test.enc$') || fail "the unmanaged live login was not archived"
is "$(py 'import base64,sys;print(base64.b64decode(open(sys.argv[1]).read()).decode())' "$B/credentials/.removed/$kept")" "$Z" "archived live credential"
is "$(mode "$B/credentials/.removed/$kept")" 600 "archive mode"
is "$(cat "$H/.claude/.credentials.json")" "$A" "slot 1 is live now"

# ---- the live credential belongs to another slot: not written into this one --------------------
live_login a@x.test "$B_CREDS"
slot1=$(cat "$B/credentials/.creds-1-a@x.test.enc")
expect_ok "$sw" switch 2 --json
case "$(jfield warnings)" in *"already matches Account-2's stored backup"*) ;; *) fail "foreign-synced warning missing: $out" ;; esac
is "$(cat "$B/credentials/.creds-1-a@x.test.enc")" "$slot1" "slot 1's backup was not poisoned"

# ---- a diverged live credential that the oracle names as someone else: preserved aside ---------
live_login a@x.test '{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKESTRANGER", "refreshToken": "sk-ant-ort01-FAKESTRANGER"}}'
py 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["activeAccountNumber"]=1;open(p,"w").write(json.dumps(d,indent=2))' "$B/sequence.json"
printf '%s' '{"account": {"uuid": "u-stranger", "email": "stranger@x.test"}, "organization": {"uuid": "o-stranger"}}' > "$H/profile.json"
export CSWAP_SWITCH_ORACLE_FILE="$H/profile.json"
slot1=$(cat "$B/credentials/.creds-1-a@x.test.enc")
expect_ok "$sw" switch 2 --json
case "$(jfield warnings)" in *"does not match a managed account"*) ;; *) fail "alien warning missing: $out" ;; esac
is "$(cat "$B/credentials/.creds-1-a@x.test.enc")" "$slot1" "alien credential was written into slot 1"
ls "$B/credentials/.removed" | grep -q -- '-live-a@x.test.enc$' || fail "alien live credential not preserved"
unset CSWAP_SWITCH_ORACLE_FILE

# ---- Claude Code's directory locks: a stale one is taken over, a fresh one is waited for --------
live_login b@x.test "$B_CREDS"
py 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["activeAccountNumber"]=2;open(p,"w").write(json.dumps(d,indent=2))' "$B/sequence.json"
mkdir "$H/.claude.json.lock"
touch -t 202001010000 "$H/.claude.json.lock"
expect_ok "$sw" switch 1 --json
[ ! -e "$H/.claude.json.lock" ] || fail "stale lock dir not cleaned up"
live_login b@x.test "$B_CREDS"
mkdir "$H/.claude.lock"
(
  sleep 1
  rmdir "$H/.claude.lock"
) &
holder=$!
t0=$(date +%s)
expect_ok "$sw" switch 1 --json
wait "$holder" 2> /dev/null || true
[ "$(date +%s)" -ge "$t0" ] || fail "clock"
[ ! -e "$H/.claude.lock" ] || fail "lock dir left behind"

# ---- the switch did not stick: a keychain login rewrote oauthAccount during the delay ------------
live_login a@x.test "$A"
py 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["activeAccountNumber"]=1;open(p,"w").write(json.dumps(d,indent=2))' "$B/sequence.json"
CSWAP_SWITCH_VERIFY_DELAY_MS=1500 "$sw" switch 2 --json > "$H/override.out" 2>&1 &
sp=$!
n=0
until grep -q '"b@x.test"' "$H/.claude.json" 2> /dev/null; do
  n=$((n + 1))
  [ "$n" -le 100 ] || fail "switch never wrote the config"
  sleep 0.05
done
# what Claude Code does with a keychain login: put its own account back
py 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["oauthAccount"]["emailAddress"]="keychain@x.test";open(p,"w").write(json.dumps(d,indent=2))' "$H/.claude.json"
rc=0
wait "$sp" || rc=$?
out=$(cat "$H/override.out")
[ "$rc" = 1 ] || fail "override should exit 1 (got $rc): $out"
is "$(jfield error type)" live-login-overridden "override error type"
case "$(jfield error message)" in
  *"reads keychain@x.test"*"a Claude Code keychain login is overriding cswap; remove the 'Claude Code-credentials' keychain item") ;;
  *) fail "override message: $out" ;;
esac
# it reports, it does not "fix" anything: the files are as the switch left them
is "$(cat "$H/.claude/.credentials.json")" "$B_CREDS" "credentials stay as written"

# and with no override the same switch is quiet
live_login a@x.test "$A"
py 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["activeAccountNumber"]=1;open(p,"w").write(json.dumps(d,indent=2))' "$B/sequence.json"
CSWAP_SWITCH_VERIFY_DELAY_MS=300 expect_ok "$sw" switch 2 --json
is "$(jfield reason)" switched "no override, no error"
