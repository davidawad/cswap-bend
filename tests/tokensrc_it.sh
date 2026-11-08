#!/bin/sh
# User token config end to end in a scratch HOME (dot-plk73m): the active pick
# file overrides the ~/.claude.json identity for status, switch writes the pick,
# and the switched-to credential is the stdout of the account's command.
# Fake tokens only; no network.
set -eu
cli=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
export CSWAP_TEST_HTTP_BASE=http://127.0.0.1:1
d=$(mktemp -d "${TMPDIR:-/tmp}/cswap-tokensrc-it.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() { echo "tokensrc_it: $*" >&2; exit 1; }
export HOME="$d" NO_COLOR=1
mkdir -p "$d/.claude"
echo fake-token-aaaaaaaaaaaaaaaaaaaaaaaa | "$cli" add-token - --email a@x.com --slot 1 > /dev/null
echo fake-token-bbbbbbbbbbbbbbbbbbbbbbbb | "$cli" add-token - --email b@x.com --slot 2 > /dev/null
printf '{"oauthAccount":{"emailAddress":"a@x.com","organizationUuid":""}}' > "$d/.claude.json"
printf '#!/bin/sh\necho tok-$1\n' > "$d/tok.sh"
chmod +x "$d/tok.sh"
printf '{"account":"b@x.com","organizationUuid":""}' > "$d/active.json"
printf '{"accounts":{"a@x.com":{"command":["%s/tok.sh","a@x.com"]}},"active":{"file":"%s/active.json"}}' "$d" "$d" > "$d/cfg.json"

"$cli" status | grep -q 'Account-1' || fail "baseline status should follow ~/.claude.json"
export CSWAP_TOKEN_CONFIG="$d/cfg.json"
"$cli" status | grep -q 'Account-2 (b@x.com' || fail "status must follow the active pick, not ~/.claude.json"
CSWAP_SWITCH_VERIFY_DELAY_MS=0 CSWAP_SWITCH_ORACLE_FILE=/nonexistent "$cli" switch 1 > /dev/null || fail "switch failed"
grep -q '"account": "a@x.com"' "$d/active.json" || fail "switch must record the active pick"
[ ! -e "$d/.claude/.credentials.json" ] || fail "a setup-token switch must not write ~/.claude/.credentials.json"
printf 'REAL-LOGIN' > "$d/.claude/.credentials.json"
CSWAP_SWITCH_VERIFY_DELAY_MS=0 CSWAP_SWITCH_ORACLE_FILE=/nonexistent "$cli" switch 2 > /dev/null || fail "switch 2 failed"
[ "$(cat "$d/.claude/.credentials.json")" = REAL-LOGIN ] || fail "a switch must leave ~/.claude/.credentials.json untouched"
# a session rewriting ~/.claude.json cannot flip the pick
printf '{"oauthAccount":{"emailAddress":"a@x.com","organizationUuid":""}}' > "$d/.claude.json"
"$cli" status | grep -q 'Account-2 (b@x.com' || fail "a rewritten ~/.claude.json must not change status"
echo "tokensrc_it: ok"
