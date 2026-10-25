#!/bin/sh
# store on a scratch HOME with fake tokens: add-token, read, remove (archive,
# never delete), displacement, the identity check of add. Never touches the
# real ~/.claude-swap-backup, ~/.claude or ~/.claude.json: HOME is a temp dir.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
BEND=${BEND:-bend}
mkdir -p "$root/bin"
nice -n 19 "$BEND" "$here/it/store_main.bend" -o "$root/bin/store-it" > /dev/null
it="$root/bin/store-it"
H=$(mktemp -d "${TMPDIR:-/tmp}/cswap-store-it.XXXXXX")
trap 'rm -rf "$H"' EXIT
export HOME="$H"
unset CLAUDE_CONFIG_DIR STORE_IT_PROFILE || true
B="$H/.claude-swap-backup"

fail() {
  echo "store_it: $*" >&2
  exit 1
}
mode() { stat -c %a "$1" 2> /dev/null || stat -f %Lp "$1"; }
py() { nice -n 19 python3 -I -c "$@"; }
# run the store; capture stdout+stderr and the exit code without tripping set -e
run() {
  rc=0
  out=$("$it" "$@" 2>&1) || rc=$?
}
expect_ok() {
  run "$@"
  [ "$rc" = 0 ] || fail "'$*' failed ($rc): $out"
}
expect_err() {
  want=$1
  shift
  run "$@"
  [ "$rc" != 0 ] || fail "'$*' should have failed, printed: $out"
  case "$out" in *"$want"*) ;; *) fail "'$*' error lacks '$want': $out" ;; esac
}
contains() {
  case "$1" in *"$2"*) ;; *) fail "missing '$2' in: $1" ;; esac
}

# ---- add-token ------------------------------------------------------------------
expect_ok add-token sk-ant-oat01-FAKEONE
[ "$out" = "Added Account 1: setup-token-1@token.local [personal] (from token)" ] || fail "msg: $out"
enc="$B/credentials/.creds-1-setup-token-1@token.local.enc"
cfg="$B/configs/.claude-config-1-setup-token-1@token.local.json"
[ -f "$enc" ] && [ -f "$cfg" ] || fail "slot 1 files missing"
[ "$(mode "$enc")" = 600 ] || fail "enc mode $(mode "$enc")"
[ "$(mode "$cfg")" = 600 ] || fail "config mode $(mode "$cfg")"
[ "$(mode "$B/sequence.json")" = 600 ] || fail "sequence mode"
for d in "$B" "$B/credentials" "$B/configs"; do [ "$(mode "$d")" = 700 ] || fail "dir mode $d"; done
[ "$(py 'import base64,sys;print(base64.b64decode(open(sys.argv[1]).read()).decode())' "$enc")" = \
  '{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKEONE", "scopes": ["user:inference"]}}' ] || fail "enc payload"
[ "$(cat "$cfg")" = '{"oauthAccount": {"emailAddress": "setup-token-1@token.local", "accountUuid": "", "organizationUuid": null, "organizationName": null}}' ] || fail "config payload"

expect_ok add-token sk-ant-api03-FAKEKEY
[ "$out" = "Added Account 2: api-key-2@token.local [personal] (from API key)" ] || fail "api msg: $out"
[ "$(py 'import base64,sys;print(base64.b64decode(open(sys.argv[1]).read()).decode())' "$B/credentials/.creds-2-api-key-2@token.local.enc")" = sk-ant-api03-FAKEKEY ] || fail "api key stored raw"

expect_ok add-token sk-ant-oat01-FAKETHREE carol@example.test
[ "$out" = "Added Account 3: carol@example.test [personal] (from token)" ] || fail "email msg: $out"

# sequence.json is what json.dumps(indent=2) writes, in this shape
py '
import json,sys
t=open(sys.argv[1]).read()
d=json.loads(t)
assert t==json.dumps(d,indent=2),"not json.dumps(indent=2)"
assert list(d)==["activeAccountNumber","lastUpdated","sequence","accounts"],list(d)
assert d["activeAccountNumber"] is None
assert d["sequence"]==[1,2,3],d["sequence"]
assert list(d["accounts"])==["1","2","3"]
assert d["accounts"]["2"]["kind"]=="api_key" and "kind" not in d["accounts"]["1"]
assert list(d["accounts"]["1"])==["email","uuid","organizationUuid","organizationName","added"]
' "$B/sequence.json" || fail "sequence.json shape"

# refresh in place keeps the old generation as .prev
expect_ok add-token sk-ant-oat01-FAKETHREE2 carol@example.test
[ "$out" = "Updated token for Account 3 (carol@example.test [personal])." ] || fail "update msg: $out"
[ -f "$B/credentials/.creds-3-carol@example.test.enc.prev" ] || fail ".prev missing"
[ "$(py 'import base64,sys,json;print(json.loads(base64.b64decode(open(sys.argv[1]).read()))["claudeAiOauth"]["accessToken"])' "$B/credentials/.creds-3-carol@example.test.enc.prev")" = sk-ant-oat01-FAKETHREE ] || fail ".prev holds the old token"

# validation
expect_err "Token cannot be empty" add-token ""
expect_err "Invalid email format: nope" add-token sk-ant-oat01-X nope
expect_err "already exists as an OAuth account" add-token sk-ant-api03-OTHER carol@example.test
[ "$(py 'import json,sys;print(json.load(open(sys.argv[1]))["sequence"])' "$B/sequence.json")" = "[1, 2, 3]" ] || fail "failed add changed the roster"

# an occupied slot needs confirmation; with it the old account is archived
expect_err "Slot 1 already occupied" add-token sk-ant-oat01-NEWONE dave@example.test 1
expect_ok add-token-slot sk-ant-oat01-NEWONE dave@example.test 1
[ "$out" = "Added Account 1: dave@example.test [personal] (from token)" ] || fail "displace msg: $out"
ls "$B/credentials/.removed" | grep -q -- '-1-setup-token-1@token.local.enc$' || fail "displaced credential was not archived"
[ ! -e "$enc" ] || fail "displaced .enc still in place"

# ---- read -----------------------------------------------------------------------
expect_ok read 1
[ "$out" = '{"claudeAiOauth": {"accessToken": "sk-ant-oat01-NEWONE", "scopes": ["user:inference"]}}' ] || fail "read 1: $out"
expect_ok read carol@example.test
contains "$out" sk-ant-oat01-FAKETHREE2
expect_ok read 2
[ "$out" = sk-ant-api03-FAKEKEY ] || fail "read api key: $out"
expect_err "No account found with identifier" read nobody@example.test

# ---- remove: archived, never deleted ---------------------------------------------
before=$(py 'import base64,sys;print(base64.b64decode(open(sys.argv[1]).read()).decode())' "$B/credentials/.creds-3-carol@example.test.enc")
expect_ok remove carol@example.test
[ "$out" = "Removed Account-3 (carol@example.test)" ] || fail "remove msg: $out"
[ ! -e "$B/credentials/.creds-3-carol@example.test.enc" ] || fail "enc still in place after remove"
kept=$(ls "$B/credentials/.removed" | grep -- '-3-carol@example.test.enc$')
[ -n "$kept" ] || fail "removed credential was not kept"
[ "$(mode "$B/credentials/.removed/$kept")" = 600 ] || fail "archive mode"
[ "$(py 'import base64,sys;print(base64.b64decode(open(sys.argv[1]).read()).decode())' "$B/credentials/.removed/$kept")" = "$before" ] || fail "archived credential differs"
case "$kept" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z-3-*) ;; *) fail "archive name $kept" ;; esac
[ "$(py 'import json,sys;d=json.load(open(sys.argv[1]));print(d["sequence"],sorted(d["accounts"]))' "$B/sequence.json")" = "[1, 2] ['1', '2']" ] || fail "roster after remove"
grep -q 'Removed account 3' "$B/claude-swap.log" || fail "removal not logged"
expect_err "Account-3 does not exist" remove 3
expect_err "Invalid account identifier" remove 'not an id'
expect_ok remove 2
ls "$B/credentials/.removed" | grep -q -- '-2-api-key-2@token.local.enc$' || fail "api key not archived"

# ---- add: the identity check -----------------------------------------------------
H2=$(mktemp -d "${TMPDIR:-/tmp}/cswap-store-it2.XXXXXX")
trap 'rm -rf "$H" "$H2"' EXIT
export HOME="$H2"
B="$H2/.claude-swap-backup"
mkdir -p "$H2/.claude"
printf '%s' '{"oauthAccount": {"emailAddress": "me@example.test", "accountUuid": "uuid-me", "organizationUuid": "org-1", "organizationName": "Acme"}, "keep": 1}' > "$H2/.claude.json"
printf '%s' '{"claudeAiOauth": {"accessToken": "sk-ant-oat01-LIVE", "refreshToken": "r", "expiresAt": 9999999999999, "scopes": ["user:profile"]}}' > "$H2/.claude/.credentials.json"

# another account's token: refused, nothing written
printf '%s' '{"account": {"uuid": "uuid-other", "email": "other@example.test"}, "organization": {"uuid": "org-1"}}' > "$H2/profile.json"
export STORE_IT_PROFILE="$H2/profile.json"
expect_err "The stored credential does not belong to me@example.test: the token resolves to account uuid-other, not uuid-me" add
[ ! -e "$B/credentials/.creds-1-me@example.test.enc" ] || fail "mismatch wrote a credential"
[ "$(py 'import json,sys;print(json.load(open(sys.argv[1]))["accounts"])' "$B/sequence.json")" = "{}" ] || fail "mismatch changed the roster"

# same account, different organization: refused
printf '%s' '{"account": {"uuid": "uuid-me", "email": "me@example.test"}, "organization": {"uuid": "org-2"}}' > "$H2/profile.json"
expect_err "belongs to organization org-2, not org-1" add

# matching identity: added with an alias
printf '%s' '{"account": {"uuid": "uuid-me", "email": "me@example.test"}, "organization": {"uuid": "org-1"}}' > "$H2/profile.json"
expect_ok add Work
[ "$out" = "Added Account 1: me@example.test [Acme]" ] || fail "add msg: $out"
py '
import json,sys
d=json.load(open(sys.argv[1]))
a=d["accounts"]["1"]
assert d["activeAccountNumber"]==1 and d["sequence"]==[1]
assert (a["email"],a["uuid"],a["organizationUuid"],a["organizationName"],a["alias"])==("me@example.test","uuid-me","org-1","Acme","work"),a
' "$B/sequence.json" || fail "added record"
[ "$(cat "$B/configs/.claude-config-1-me@example.test.json")" = "$(cat "$H2/.claude.json")" ] || fail "config backup is not the raw .claude.json"
expect_ok read work
contains "$out" sk-ant-oat01-LIVE
expect_ok add
contains "$out" "Updated credentials for Account 1 (me@example.test [Acme])."

# unresolvable owner: registers with a notice
unset STORE_IT_PROFILE
expect_ok add
contains "$out" "Notice: could not verify that the stored credential belongs to me@example.test (the identity lookup did not resolve)"

# a live API key is refused
printf '%s' 'sk-ant-api03-LIVEKEY' > "$H2/.claude/.credentials.json"
expect_err "Active login is an API-key account" add
