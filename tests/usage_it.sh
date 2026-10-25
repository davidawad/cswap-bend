#!/bin/sh
# usage fetch and OAuth refresh against a local stub HTTP server: the
# requests made (exact lines) and the outcomes, through the
# CSWAP_TEST_HTTP_BASE seam. Fake tokens only; the real API is never called.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
BEND=${BEND:-bend}
mkdir -p "$root/bin"
nice -n 19 "$BEND" "$here/it/usage_main.bend" -o "$root/bin/usage-it" > /dev/null
it="$root/bin/usage-it"
d=$(mktemp -d "${TMPDIR:-/tmp}/cswap-usage-it.XXXXXX")
pid=""
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2> /dev/null || true
  rm -rf "$d"
}
trap cleanup EXIT
fail() {
  echo "usage_it: $*" >&2
  exit 1
}

USAGE=/api.anthropic.com/api/oauth/usage
MSG=/api.anthropic.com/v1/messages
TOK=/platform.claude.com/v1/oauth/token
BODY='{"max_tokens":1,"messages":[{"content":".","role":"user"}],"model":"claude-haiku-5-5","system":[{"text":"You are Claude Code, Anthropic'"'"'s official CLI for Claude.","type":"text"}]}'
FAR=4102444800
FARMS=4102444800000
RL5="anthropic-ratelimit-unified-5h"
RL7="anthropic-ratelimit-unified-7d"

start_stub() { # routes-file
  [ -z "$pid" ] || kill "$pid" 2> /dev/null || true
  rm -f "$d/port"
  python3 -I "$here/usage_stub.py" "$1" "$d/log" "$d/port" &
  pid=$!
  n=0
  while [ ! -s "$d/port" ]; do
    n=$((n + 1))
    [ "$n" -le 100 ] || fail "stub never started"
    sleep 0.05
  done
  export CSWAP_TEST_HTTP_BASE="http://127.0.0.1:$(cat "$d/port")"
}

cat > "$d/routes.json" << EOF2
[
 {"method":"GET","path":"$USAGE","token":"FAKE-profile-at","responses":[{"status":200,"headers":{},"body":{
   "five_hour":{"utilization":42.5,"resets_at":"2100-01-01T00:00:00+00:00"},
   "seven_day":{"utilization":10,"resets_at":null},
   "limits":[{"scope":{"model":{"display_name":"Fable"}},"percent":73,"resets_at":"2100-01-02T00:00:00+00:00"}]}}]},
 {"method":"POST","path":"$MSG","token":"FAKE-setup-at","responses":[{"status":200,"headers":{
   "$RL5-utilization":"0.25","$RL5-reset":"$FAR","$RL7-utilization":"0.5","$RL7-reset":"$FAR"},"body":{"id":"msg_FAKE"}}]},
 {"method":"GET","path":"$USAGE","token":"FAKE-noscope-at","responses":[{"status":403,"headers":{},"body":{"error":{"type":"permission_error","message":"OAuth token does not meet scope requirement user:profile","details":{"error_code":"oauth_scope_insufficient"}}}}]},
 {"method":"POST","path":"$MSG","token":"FAKE-noscope-at","responses":[{"status":200,"headers":{
   "$RL5-utilization":"0.4","$RL5-reset":"$FAR","$RL7-utilization":"0.8","$RL7-reset":"$FAR"},"body":{"id":"msg_FAKE"}}]},
 {"method":"GET","path":"$USAGE","token":"FAKE-forbidden-at","responses":[{"status":403,"headers":{},"body":{"error":"nope"}}]},
 {"method":"GET","path":"$USAGE","token":"FAKE-rl-at","responses":[{"status":429,"headers":{"retry-after":"30"},"body":{"error":"slow"}}]},
 {"method":"POST","path":"$MSG","token":"FAKE-rl-at","responses":[{"status":200,"headers":{
   "$RL5-utilization":"0.1","$RL5-reset":"$FAR","$RL7-utilization":"0.2","$RL7-reset":"$FAR"},"body":{"id":"msg_FAKE"}}]},
 {"method":"GET","path":"$USAGE","token":"FAKE-rlfail-at","responses":[{"status":429,"headers":{"retry-after":"45"},"body":{"error":"slow"}}]},
 {"method":"POST","path":"$MSG","token":"FAKE-rlfail-at","responses":[{"status":500,"headers":{},"body":{"error":"boom"}}]},
 {"method":"POST","path":"$MSG","token":"FAKE-full-setup-at","responses":[{"status":429,"headers":{
   "$RL5-utilization":"1.0","$RL5-reset":"$FAR","$RL7-utilization":"0.8","$RL7-reset":"$FAR","retry-after":"60"},"body":{"error":"limited"}}]},
 {"method":"POST","path":"$MSG","token":"FAKE-bare429-at","responses":[{"status":429,"headers":{"retry-after":"90"},"body":{"error":"limited"}}]},
 {"method":"POST","path":"$MSG","token":"FAKE-nohdr-at","responses":[{"status":200,"headers":{},"body":{"id":"msg_FAKE"}}]},
 {"method":"GET","path":"$USAGE","token":"FAKE-old-at","responses":[{"status":401,"headers":{},"body":{"error":"expired"}}]},
 {"method":"POST","path":"$TOK","token":"","responses":[{"status":200,"headers":{},"body":{
   "access_token":"FAKE-new-at","refresh_token":"FAKE-new-rt","expires_in":3600,"scope":"user:profile user:inference"}}]},
 {"method":"GET","path":"$USAGE","token":"FAKE-new-at","responses":[{"status":200,"headers":{},"body":{"five_hour":{"utilization":5,"resets_at":null}}}]},
 {"method":"GET","path":"$USAGE","token":"FAKE-active-at","responses":[{"status":401,"headers":{},"body":{"error":"expired"}}]}
]
EOF2
start_stub "$d/routes.json"

cred() { # name access refresh expiresAt scopes-json-or-empty
  scopes=""
  [ -z "$5" ] || scopes=",\"scopes\":$5"
  printf '{"claudeAiOauth":{"accessToken":"%s","refreshToken":"%s","expiresAt":%s%s},"other":{"keep":true}}' "$2" "$3" "$4" "$scopes" > "$d/$1.cred"
}
run() { # name mode
  : > "$d/log"
  "$it" fetch "$d/$1.cred" "$2" > "$d/out" 2> "$d/err" || fail "$1: exit $?"
  [ ! -s "$d/err" ] || fail "$1: stderr: $(cat "$d/err")"
}
want_log() { # name expected-lines
  if [ -z "$2" ]; then : > "$d/want"; else printf '%s\n' "$2" > "$d/want"; fi
  cmp -s "$d/want" "$d/log" || {
    echo "--- $1: requests differ; want" >&2
    cat "$d/want" >&2
    echo "--- got" >&2
    cat "$d/log" >&2
    exit 1
  }
}
want_out() { # name text
  grep -qF -- "$2" "$d/out" || {
    echo "--- $1: output lacks: $2" >&2
    cat "$d/out" >&2
    exit 1
  }
}
no_token_in_out() { # name token...
  nm=$1
  shift
  for t in "$@"; do ! grep -qF -- "$t" "$d/out" || fail "$nm: token $t in output"; done
}
GET_USAGE() { echo "GET $USAGE tok=$1 beta=oauth-2025-04-20 ver=- ct=- ua=claude-swap/1.0 body=-"; }
POST_MSG() { echo "POST $MSG tok=$1 beta=claude-code-20250219,oauth-2025-04-20 ver=2023-06-01 ct=application/json ua=claude-swap/1.0 body=$BODY"; }
POST_TOK() { echo "POST $TOK tok=- beta=- ver=- ct=application/json ua=claude-swap/1.0 body={\"client_id\":\"9d1c250a-e61b-44d9-88ed-5944d1962f5e\",\"grant_type\":\"refresh_token\",\"refresh_token\":\"$1\"}"; }

# 1. profile token: the usage endpoint only, with scoped windows.
cred profile FAKE-profile-at FAKE-profile-rt $FARMS '["user:profile","user:inference"]'
run profile inactive
want_log profile "$(GET_USAGE FAKE-profile-at)"
want_out profile 'error=none'
want_out profile '"five_hour":{"pct":42.5,"resets_at":"2100-01-01T00:00:00+00:00","countdown":'
want_out profile '"seven_day":{"pct":10}'
want_out profile '"scoped":[{"name":"Fable","pct":73.0,"resets_at":"2100-01-02T00:00:00+00:00"'
want_out profile 'credential=none'
no_token_in_out profile FAKE-profile-at FAKE-profile-rt

# 2. setup-token (scopes without user:profile): the probe only.
cred setup FAKE-setup-at FAKE-setup-rt $FARMS '["user:inference"]'
run setup inactive
want_log setup "$(POST_MSG FAKE-setup-at)"
want_out setup 'error=none'
want_out setup '"five_hour":{"pct":25.0,"resets_at":"2100-01-01T00:00:00+00:00"'
want_out setup '"seven_day":{"pct":50.0,"resets_at":"2100-01-01T00:00:00+00:00"'
no_token_in_out setup FAKE-setup-at

# 3. no scopes list, usage endpoint 403 scope error: probe next.
cred noscope FAKE-noscope-at FAKE-noscope-rt $FARMS ''
run noscope inactive
want_log noscope "$(GET_USAGE FAKE-noscope-at)
$(POST_MSG FAKE-noscope-at)"
want_out noscope 'error=none'
want_out noscope '"five_hour":{"pct":40.0,'
want_out noscope '"seven_day":{"pct":80.0,'

# 3b. any other 403 stays http-403, no probe.
cred forbidden FAKE-forbidden-at FAKE-forbidden-rt $FARMS ''
run forbidden inactive
want_log forbidden "$(GET_USAGE FAKE-forbidden-at)"
want_out forbidden 'error=http-403'
want_out forbidden 'usage=null'

# 4. usage endpoint 429: the probe answers, a success.
cred rl FAKE-rl-at FAKE-rl-rt $FARMS '["user:profile"]'
run rl inactive
want_log rl "$(GET_USAGE FAKE-rl-at)
$(POST_MSG FAKE-rl-at)"
want_out rl 'error=none'
want_out rl '"five_hour":{"pct":10.0,'

# 4b. 429 and the probe fails too: the original 429, with its Retry-After.
cred rlfail FAKE-rlfail-at FAKE-rlfail-rt $FARMS '["user:profile"]'
run rlfail inactive
want_log rlfail "$(GET_USAGE FAKE-rlfail-at)
$(POST_MSG FAKE-rlfail-at)"
want_out rlfail 'error=http-429'
want_out rlfail 'retry=45'

# 5. exhausted setup-token: the probe's 429 still carries the headers, a
# valid 100% reading, not an error.
cred exhausted FAKE-full-setup-at FAKE-full-setup-rt $FARMS '["user:inference"]'
run exhausted inactive
want_log exhausted "$(POST_MSG FAKE-full-setup-at)"
want_out exhausted 'error=none'
want_out exhausted '"five_hour":{"pct":100.0,'
want_out exhausted '"seven_day":{"pct":80.0,'

# 5b. probe non-2xx without the headers: http-429 with Retry-After; 2xx
# without the headers: bad-response.
cred bare FAKE-bare429-at FAKE-bare429-rt $FARMS '["user:inference"]'
run bare inactive
want_out bare 'error=http-429'
want_out bare 'retry=90'
cred nohdr FAKE-nohdr-at FAKE-nohdr-rt $FARMS '["user:inference"]'
run nohdr inactive
want_out nohdr 'error=bad-response'

# 6. 401 on an inactive account: refresh, then retry once with the new token.
cred old FAKE-old-at FAKE-old-rt $FARMS '["user:profile","user:inference"]'
run old inactive
want_log old "$(GET_USAGE FAKE-old-at)
$(POST_TOK FAKE-old-rt)
$(GET_USAGE FAKE-new-at)"
want_out old 'error=none'
want_out old '"five_hour":{"pct":5}'
want_out old '"accessToken": "FAKE-new-at"'
want_out old '"refreshToken": "FAKE-new-rt"'
want_out old '"scopes": ["user:profile", "user:inference"]'
want_out old '"other": {"keep": true}'

# 6b. an active account is never refreshed: its 401 is the error.
cred active FAKE-active-at FAKE-active-rt $FARMS '["user:profile"]'
run active active
want_log active "$(GET_USAGE FAKE-active-at)"
want_out active 'error=http-401'
want_out active 'credential=none'

# 6c. an expired inactive token is refreshed before the first request.
cred expired FAKE-old-at FAKE-old-rt 1000 '["user:profile"]'
run expired inactive
want_log expired "$(POST_TOK FAKE-old-rt)
$(GET_USAGE FAKE-new-at)"
want_out expired 'error=none'
want_out expired '"accessToken": "FAKE-new-at"'

# ---- the consume gate (credentials/.consume-<slot>.lock) ------------------
R="$d"
CD="$d/credentials"
mkdir -p "$CD"
SLOT=1
EMAIL=gate@example.test
ENC="$CD/.creds-$SLOT-$EMAIL.enc"
put_enc() { printf '%s' "$(cat "$1")" | base64 | tr -d '\n' > "$ENC"; }
mode_of() { python3 -I -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1"; }
unb64() { base64 -d < "$1" 2> /dev/null || base64 -D < "$1"; }
grun() { # cmd-args...; output to $d/out, log reset first
  : > "$d/log"
  "$it" "$@" > "$d/out" 2> "$d/err" || fail "gate: exit $?"
  [ ! -s "$d/err" ] || fail "gate: stderr: $(cat "$d/err")"
}
hold() { # seconds: hold the consume lock from a Python process (locking.py's flock)
  : > "$d/holder"
  python3 -I -c 'import fcntl,sys,time
f=open(sys.argv[1],"w"); fcntl.flock(f,fcntl.LOCK_EX); print("held",flush=True); time.sleep(float(sys.argv[2]))' \
    "$CD/.consume-$SLOT.lock" "$1" > "$d/holder" &
  holder=$!
  n=0
  while ! grep -q held "$d/holder" 2> /dev/null; do
    n=$((n + 1))
    [ "$n" -le 100 ] || fail "lock holder never held"
    sleep 0.05
  done
}

# G1. snapshot == stored: one POST, the rotated credential written back 0600,
# the previous generation kept in .enc.prev.
cred g1 FAKE-old-at FAKE-old-rt $FARMS '["user:profile"]'
put_enc "$d/g1.cred"
grun gate "$d/g1.cred" $SLOT $EMAIL "$R"
want_log g1 "$(POST_TOK FAKE-old-rt)"
want_out g1 'error=none'
want_out g1 '"accessToken": "FAKE-new-at"'
[ "$(unb64 "$ENC")" = "$(sed 's/.*credential=//p;d' "$d/out" | head -1)" ] || fail "g1: .enc does not hold the rotated credential"
[ "$(mode_of "$ENC")" = 600 ] || fail "g1: .enc mode $(mode_of "$ENC")"
[ "$(unb64 "$ENC.prev")" = "$(cat "$d/g1.cred")" ] || fail "g1: .enc.prev is not the old generation"
[ "$(mode_of "$ENC.prev")" = 600 ] || fail "g1: .enc.prev mode"

# G2. a fresher generation under the lock: no POST, adopted, store untouched.
cred g2old FAKE-old-at FAKE-old-rt $FARMS '["user:profile"]'
cred g2new FAKE-fresh-at FAKE-fresh-rt $FARMS '["user:profile"]'
put_enc "$d/g2new.cred"
before=$(cat "$ENC")
grun gate "$d/g2old.cred" $SLOT $EMAIL "$R"
want_log g2 ""
want_out g2 'error=none'
want_out g2 '"accessToken":"FAKE-fresh-at"'
[ "$(cat "$ENC")" = "$before" ] || fail "g2: .enc changed"

# G2b. fresher but expired: the gate consumes the fresher refresh token, never the snapshot's.
cred g2x FAKE-fresh-at FAKE-fresh-rt 1000 '["user:profile"]'
put_enc "$d/g2x.cred"
grun gate "$d/g2old.cred" $SLOT $EMAIL "$R"
want_log g2b "$(POST_TOK FAKE-fresh-rt)"
want_out g2b '"accessToken": "FAKE-new-at"'

# G2c. a fresher .enc written while a Python holder owns the lock: the Bend
# side waits, then re-reads, skips the POST and adopts it.
put_enc "$d/g2old.cred"
hold 1
( sleep 0.3; printf '%s' "$(cat "$d/g2new.cred")" | base64 | tr -d '\n' > "$ENC" ) &
writer=$!
CSWAP_CONSUME_TIMEOUT_MS=8000 grun gate "$d/g2old.cred" $SLOT $EMAIL "$R"
wait "$writer" "$holder"
want_log g2c ""
want_out g2c '"accessToken":"FAKE-fresh-at"'

# G3. busy past the timeout: consume-busy, and no POST.
put_enc "$d/g1.cred"
hold 4
CSWAP_CONSUME_TIMEOUT_MS=500 grun gate "$d/g1.cred" $SLOT $EMAIL "$R"
want_log g3 ""
want_out g3 'error=consume-busy'
want_out g3 'credential=none'

# G3b. fetch_usage with the gate while busy: consume-busy surfaces, no usage
# request with the stale token.
cred g3 FAKE-old-at FAKE-old-rt 1000 '["user:profile"]'
put_enc "$d/g3.cred"
CSWAP_CONSUME_TIMEOUT_MS=500 grun fetchg "$d/g3.cred" inactive $SLOT $EMAIL "$R"
want_log g3b ""
want_out g3b 'error=consume-busy'
want_out g3b 'struck=no'
wait "$holder"

# G4. the lock released after 1 s: the Bend side waits it out, then POSTs once.
put_enc "$d/g1.cred"
hold 1
CSWAP_CONSUME_TIMEOUT_MS=8000 grun gate "$d/g1.cred" $SLOT $EMAIL "$R"
wait "$holder"
want_log g4 "$(POST_TOK FAKE-old-rt)"
want_out g4 'error=none'

# G5. fetch_usage through the gate: refresh under the lock, then the usage read.
put_enc "$d/expired.cred"
grun fetchg "$d/expired.cred" inactive $SLOT $EMAIL "$R"
want_log g5 "$(POST_TOK FAKE-old-rt)
$(GET_USAGE FAKE-new-at)"
want_out g5 'error=none'
want_out g5 '"accessToken": "FAKE-new-at"'

# G5b. the store moved to a fresher generation after the caller read its
# snapshot: fetch_usage uses it with no POST.
cred g5 FAKE-new-at FAKE-fresh-rt $FARMS '["user:profile"]'
put_enc "$d/g5.cred"
grun fetchg "$d/expired.cred" inactive $SLOT $EMAIL "$R"
want_log g5b "$(GET_USAGE FAKE-new-at)"
want_out g5b 'error=none'

# G6. a slot whose .enc is gone is not consumed.
mv "$ENC" "$ENC.gone"
grun gate "$d/g1.cred" $SLOT $EMAIL "$R"
want_log g6 ""
want_out g6 'error=transient'

# 7. invalid_grant: the lineage is dead; no usage request, struck.
cat > "$d/routes2.json" << EOF2
[{"method":"POST","path":"$TOK","token":"","responses":[{"status":400,"headers":{},"body":{"error":"invalid_grant","error_description":"FAKE"}}]}]
EOF2
start_stub "$d/routes2.json"
cred dead FAKE-dead-at FAKE-dead-rt 1000 '["user:profile"]'
run dead inactive
want_log dead "$(POST_TOK FAKE-dead-rt)"
want_out dead 'error=invalid_grant'
want_out dead 'struck=yes'
want_out dead 'credential=none'
no_token_in_out dead FAKE-dead-at FAKE-dead-rt

# 7b. the refresh command alone, and no refresh token.
: > "$d/log"
"$it" refresh "$d/dead.cred" > "$d/out"
want_out refresh 'error=invalid_grant'
printf '{"claudeAiOauth":{"accessToken":"FAKE-x"}}' > "$d/nort.cred"
"$it" refresh "$d/nort.cred" > "$d/out"
want_out nort 'error=no_refresh_token'
printf 'not json' > "$d/junk.cred"
"$it" refresh "$d/junk.cred" > "$d/out"
want_out junk 'error=transient'
"$it" fetch "$d/junk.cred" inactive > "$d/out"
want_out junk 'error=no-access-token'

# 8. transport: a closed port is `network`, with no token in the output.
export CSWAP_TEST_HTTP_BASE="http://127.0.0.1:1"
cred net FAKE-net-at FAKE-net-rt $FARMS '["user:profile"]'
run net inactive
want_out net 'error=network'
no_token_in_out net FAKE-net-at

echo "usage_it: ok"
