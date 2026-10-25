#!/bin/sh
# The daemon's freshen / quarantine / ranked-walk behaviour (autoswitch.py
# _freshen_target, _quarantine, _release_recovered_quarantines and the
# `for num in ordered` loop), against a local stub for the OAuth token
# endpoint. Fake tokens only; the real API is never called.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
BEND=${BEND:-bend}
mkdir -p "$root/bin"
[ -x "$root/bin/store-it" ] || nice -n 19 "$BEND" "$here/it/store_main.bend" -o "$root/bin/store-it" > /dev/null
nice -n 19 "$BEND" "$here/it/daemon_main.bend" -o "$root/bin/daemon-it" > /dev/null
store="$root/bin/store-it"
auto="$root/bin/daemon-it"
D=$(mktemp -d "${TMPDIR:-/tmp}/cswap-walk-it.XXXXXX")
pid=""
sleeper=""
fakeclaude=""
cleanup() {
  [ -z "$pid" ] || kill "$pid" 2> /dev/null || true
  rm -rf "$D"
}
trap cleanup EXIT
fail() {
  echo "daemon_walk_it: $*" >&2
  exit 1
}
py() { nice -n 19 python3 -I -c "$@"; }
is() { [ "$1" = "$2" ] || fail "$3: got '$1', want '$2'"; }

TOK=/platform.claude.com/v1/oauth/token
unset CLAUDE_CONFIG_DIR CSWAP_SWITCH_ORACLE_FILE CSWAP_STATE_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR || true
export CSWAP_SWITCH_VERIFY_DELAY_MS=0

# ---- the stub: one token route per refresh token ------------------------------------------------------
# routes <rt:kind>...   kind: ok | dead | trans
start_stub() {
  [ -z "$pid" ] || kill "$pid" 2> /dev/null || true
  rm -f "$D/port"
  : > "$D/log"
  py 'import json,sys
out=[]
for a in sys.argv[2:]:
    rt,kind=a.split(":")
    if kind=="ok":
        r={"status":200,"headers":{},"body":{"access_token":"NEW-AT-"+rt,"refresh_token":"NEW-RT-"+rt,"expires_in":3600,"scope":"user:profile user:inference"}}
    elif kind.startswith("acct="):
        u,org=kind[5:].split("/")
        body={"access_token":"NEW-AT-"+rt,"refresh_token":"NEW-RT-"+rt,"expires_in":3600,"scope":"user:profile user:inference","account":{"uuid":u,"email_address":"x@y.test"}}
        if org: body["organization"]={"uuid":org}
        r={"status":200,"headers":{},"body":body}
    elif kind=="client":
        r={"status":401,"headers":{},"body":{"error":"invalid_client"}}
    elif kind=="dead":
        r={"status":400,"headers":{},"body":{"error":"invalid_grant","error_description":"FAKE"}}
    else:
        r={"status":500,"headers":{},"body":{"error":"boom"}}
    out.append({"method":"POST","path":"'"$TOK"'","token":"","rt":rt,"responses":[r]})
json.dump(out,open(sys.argv[1],"w"))' "$D/routes.json" "$@"
  python3 -I "$here/usage_stub.py" "$D/routes.json" "$D/log" "$D/port" &
  pid=$!
  n=0
  while [ ! -s "$D/port" ]; do
    n=$((n + 1))
    [ "$n" -le 100 ] || fail "stub never started"
    sleep 0.05
  done
  export CSWAP_TEST_HTTP_BASE="http://127.0.0.1:$(cat "$D/port")"
}
posts() { grep -c "^POST $TOK" "$D/log" || true; }

# ---- a world: slot 1 is live and over the threshold, slots 2..N are candidates -------------------------
# Slot k has the lineage RT-k. Usage keeps slot 2 the best target, then 3, ...
world() { # N
  rm -rf "$D/h"
  H="$D/h"
  mkdir -p "$H"
  export HOME="$H"
  B="$H/.claude-swap-backup"
  "$store" add-token sk-ant-oat01-FAKEAAA s1@x.test > /dev/null
  k=2
  while [ "$k" -le "$1" ]; do
    "$store" add-token "sk-ant-oat01-FAKE$k" "s$k@x.test" > /dev/null
    k=$((k + 1))
  done
  printf '%s' '{"numStartups": 7, "oauthAccount": {"emailAddress": "s1@x.test", "accountUuid": "", "organizationUuid": null, "organizationName": null}}' > "$H/.claude.json"
  mkdir -p "$H/.claude"
  printf '%s' '{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKEAAA", "scopes": ["user:inference"]}}' > "$H/.claude/.credentials.json"
  py 'import json,sys,time,os
now=time.time(); n=int(sys.argv[2]); acc={}
def g(p): return {"pct":p,"resets_at":time.strftime("%Y-%m-%dT%H:%M:%S+00:00",time.gmtime(now+7200)),"countdown":"2h","clock":"x"}
for k in range(1,n+1):
    p=90.0 if k==1 else 20.0+k
    acc[str(k)]={"email":"s%d@x.test"%k,"organizationUuid":"","lastGood":{"five_hour":g(p),"seven_day":dict(g(10.0),resets_at=time.strftime("%Y-%m-%dT%H:%M:%S+00:00",time.gmtime(now+200000)))},
      "fetchedAt":now-5,"lastAttemptAt":now-5,"claimId":None,"claimUntil":0.0,"consecutiveFailures":0,"lastError":None,"backoffUntil":None,
      "authDeadStrikes":0,"struckFingerprint":None,"rejectedFingerprint":None,"nextPollAt":now+3000,"pollIntervalS":180.0}
os.makedirs(sys.argv[1]+"/cache",exist_ok=True)
open(sys.argv[1]+"/cache/usage.json","w").write(json.dumps({"schemaVersion":2,"accounts":acc},indent=2))' "$B" "$1"
}

# oauthize <slot> <expiresAt-ms> [rt]: the slot's stored credential becomes a refreshable lineage
oauthize() {
  py 'import base64,json,sys,os
b,slot,exp=sys.argv[1:4]; rt=sys.argv[4] if len(sys.argv)>4 else "RT-"+slot
p="%s/credentials/.creds-%s-s%s@x.test.enc"%(b,slot,slot)
c={"claudeAiOauth":{"accessToken":"AT-"+slot,"refreshToken":rt,"expiresAt":int(exp),"scopes":["user:inference"]}}
open(p,"w").write(base64.b64encode(json.dumps(c).encode()).decode())
os.chmod(p,0o600)' "$B" "$@"
}
FAR=4102444800000
EXPIRED=1000

rc=0
out=
tick() { # extra flags
  rc=0
  out=$("$auto" auto --once --json --threshold 85 --strategy best "$@" 2> "$D/stderr") || rc=$?
}
evs() { printf '%s\n' "$out" | py 'import json,sys;print(",".join(json.loads(l)["event"] for l in sys.stdin.read().strip().split("\n") if l))'; }
ev_field() { # n field...  (n-th event)
  printf '%s\n' "$out" | py 'import json,sys
d=json.loads(sys.stdin.read().strip().split("\n")[int(sys.argv[1])])
for k in sys.argv[2:]:
    d=d[int(k)] if isinstance(d,list) else d[k]
print(json.dumps(d) if isinstance(d,(dict,list)) else d)' "$@"
}
state_q() { # slot field -> quarantine entry field, or "none"
  py 'import json,sys,os
p=sys.argv[1]+"/autoswitch_state.json"
q=(json.load(open(p)) if os.path.exists(p) else {}).get("quarantine") or {}
e=q.get(sys.argv[2])
print("none" if e is None else (e if len(sys.argv)<4 else e.get(sys.argv[3])))' "$B" "$@"
}
live_at() { py 'import json,sys;print(json.load(open(sys.argv[1]+"/.claude/.credentials.json"))["claudeAiOauth"]["accessToken"])' "$H"; }
enc_at() { py 'import base64,json,sys;print(json.loads(base64.b64decode(open("%s/credentials/.creds-%s-s%s@x.test.enc"%(sys.argv[1],sys.argv[2],sys.argv[2])).read()))["claudeAiOauth"]["accessToken"])' "$B" "$1"; }
fp() { py 'import hashlib,sys;print("sha256:"+hashlib.sha256(sys.argv[1].encode()).hexdigest())' "$1"; }
log_level() { py 'import json,sys;print(json.loads(open(sys.argv[1]+"/daemon.log").read().strip().split("\n")[-1])["level"])' "$B"; }
tree() { (cd "$B" && find . -type f ! -name "daemon*" | sort | while read -r f; do printf '%s ' "$f"; cksum < "$f"; done) | cksum; }

# ---- freshen: an expired target is refreshed (one token POST) and then switched to ----------------------
world 3
oauthize 2 $EXPIRED
oauthize 3 $FAR
start_stub RT-2:ok
tick
is "$rc" 0 "freshen exit"
is "$(posts)" 1 "freshen: exactly one token POST"
is "$(grep -c 'refresh_token":"RT-2"' "$D/log")" 1 "freshen: slot 2's lineage was consumed"
is "$(ev_field 1 event)" switch "freshen: switched"
is "$(ev_field 1 to number)" 2 "freshen: the best target"
is "$(enc_at 2)" NEW-AT-RT-2 "freshen: the stored credential is the successor"
is "$(live_at)" NEW-AT-RT-2 "freshen: the switch carried the refreshed token"
is "$(state_q 2)" none "freshen: not quarantined"

# a token well inside its life is not refreshed (autoswitch.py: FRESHEN_BUFFER_MS)
world 3
oauthize 2 $FAR
start_stub
tick
is "$(posts)" 0 "fresh token: no POST"
is "$(ev_field 1 to number)" 2 "fresh token: switched"
# 4 minutes left is inside the 5-minute buffer: refreshed
world 3
oauthize 2 "$(py 'import time;print(int(time.time()*1000)+240000)')"
start_stub RT-2:ok
tick
is "$(posts)" 1 "near expiry: refreshed"

# ---- freshen failure falls through to the walk --------------------------------------------------------------
world 3
oauthize 2 $EXPIRED
oauthize 3 $FAR
start_stub RT-2:trans
tick
is "$rc" 0 "transient: exit"
is "$(posts)" 1 "transient: one POST"
is "$(evs)" "poll,switch" "transient: next choice switched"
is "$(ev_field 1 to number)" 3 "transient: second choice"
is "$(state_q 2)" none "transient: skipped, not quarantined"
is "$(live_at)" "AT-3" "transient: slot 3's credential is live"

# ---- dead first choice: quarantined, second choice switched --------------------------------------------------
world 3
oauthize 2 $EXPIRED
oauthize 3 $FAR
start_stub RT-2:dead
tick
is "$rc" 0 "dead: exit"
is "$(evs)" "poll,account-quarantined,switch" "dead: events"
is "$(ev_field 1 number)" 2 "dead: quarantined slot"
is "$(ev_field 1 email)" s2@x.test "dead: quarantined email"
is "$(ev_field 1 reason)" invalid_grant "dead: reason"
is "$(ev_field 2 to number)" 3 "dead: second choice switched"
is "$(state_q 2 reason)" invalid_grant "dead: state reason"
is "$(state_q 2 email)" s2@x.test "dead: state email"
is "$(state_q 2 refreshTokenFingerprint)" "$(fp RT-2)" "dead: fingerprint is the refresh token's hash"

# the quarantined slot is no longer a candidate: live back on slot 1, no POST this time
printf '%s' '{"numStartups": 7, "oauthAccount": {"emailAddress": "s1@x.test", "accountUuid": "", "organizationUuid": null, "organizationName": null}}' > "$H/.claude.json"
printf '%s' '{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKEAAA", "scopes": ["user:inference"]}}' > "$H/.claude/.credentials.json"
rm -f "$B/autoswitch_state.json.tmp"
py 'import json,sys;p=sys.argv[1]+"/autoswitch_state.json";d=json.load(open(p));d.pop("lastSwitch",None);d.pop("last_switch",None);open(p,"w").write(json.dumps(d,indent=2))' "$B"
: > "$D/log"
tick --cooldown 0
is "$(posts)" 0 "quarantined: no POST for it"
is "$(ev_field 1 to number)" 3 "quarantined: dropped from candidates"

# ---- the credential replaced: released on the next tick -------------------------------------------------------
# a dry run (a below-threshold tick) first: quarantine entries survive a --dry-run tick untouched
oauthize 2 $FAR RT-2-RELOGIN
before=$(tree)
tick --dry-run
is "$(tree)" "$before" "dry run: nothing under the backup root changed"
case "$(evs)" in *unquarantined*) fail "dry run released a quarantine: $(evs)" ;; esac
is "$(state_q 2 email)" s2@x.test "dry run: the quarantine entry is still there"
tick
case "$(evs)" in *account-unquarantined*) ;; *) fail "no release event: $(evs)" ;; esac
is "$(ev_field 0 event)" account-unquarantined "release comes before the poll"
is "$(ev_field 0 reason)" credentials-replaced "release reason"
is "$(ev_field 0 number)" 2 "release slot"
is "$(state_q 2)" none "released: entry gone from the state"

# an account replaced (removed and re-added with another email) is released as account-replaced
world 3
oauthize 2 $EXPIRED
start_stub RT-2:dead
tick
is "$(state_q 2 reason)" invalid_grant "replaced: quarantined first"
"$store" remove 2 > /dev/null
"$store" add-token-slot sk-ant-oat01-FAKEOTHER other@x.test 2 > /dev/null
tick
is "$(ev_field 0 event)" account-unquarantined "replaced: release event"
is "$(ev_field 0 reason)" account-replaced "replaced: reason"

# ---- dry run: no refresh, no quarantine write ------------------------------------------------------------------
world 3
oauthize 2 $EXPIRED
start_stub RT-2:dead
before=$(tree)
tick --dry-run
is "$rc" 0 "dry run: exit"
is "$(posts)" 0 "dry run: no token POST"
is "$(ev_field 1 dryRun)" True "dry run: the decision is reported"
is "$(ev_field 1 to number)" 2 "dry run: the best target"
is "$(tree)" "$before" "dry run: nothing written"
is "$(state_q 2)" none "dry run: no quarantine"

# ---- all candidates dead: no-viable-target, exit 3 -----------------------------------------------------------------
world 3
oauthize 2 $EXPIRED
oauthize 3 $EXPIRED
start_stub RT-2:dead RT-3:dead
tick
is "$rc" 3 "all dead: exit"
is "$(evs)" "poll,account-quarantined,account-quarantined,no-switch" "all dead: events"
is "$(ev_field 3 reason)" no-viable-target "all dead: reason"
is "$(state_q 2 reason)" invalid_grant "all dead: slot 2 quarantined"
is "$(state_q 3 reason)" invalid_grant "all dead: slot 3 quarantined"
is "$(posts)" 2 "all dead: each lineage tried once"
is "$(log_level)" warn "all dead: a blocked tick is logged as a warning"
# a live-account switch must not have happened
is "$(live_at)" "sk-ant-oat01-FAKEAAA" "all dead: the login is untouched"

# ---- only a transient failure: an error, exit 1, nothing quarantined -----------------------------------------------
world 3
oauthize 2 $EXPIRED
oauthize 3 $EXPIRED
start_stub RT-2:trans RT-3:trans
tick
is "$rc" 1 "transient only: exit"
is "$(evs)" "poll,error" "transient only: events"
is "$(ev_field 1 message)" "could not freshen any candidate (network?)" "transient only: message"
is "$(ev_field 1 transient)" True "transient only: flagged transient"
is "$(log_level)" error "transient only: a failed tick is logged as an error"
is "$(state_q 2)" none "transient only: slot 2 not quarantined"
is "$(state_q 3)" none "transient only: slot 3 not quarantined"

# a dead one and a transient one: still an error (the transient one may recover), the dead one quarantined
world 3
oauthize 2 $EXPIRED
oauthize 3 $EXPIRED
start_stub RT-2:dead RT-3:trans
tick
is "$rc" 1 "mixed: exit"
is "$(evs)" "poll,account-quarantined,error" "mixed: events"

# ---- network down: connection refused is transient ------------------------------------------------------------------
world 3
oauthize 2 $EXPIRED
oauthize 3 $EXPIRED
export CSWAP_TEST_HTTP_BASE="http://127.0.0.1:1"
tick
is "$rc" 1 "network down: exit"
is "$(ev_field 1 event)" error "network down: error event"
is "$(ev_field 1 message)" "could not freshen any candidate (network?)" "network down: message"
is "$(state_q 2)" none "network down: nothing quarantined"

# ---- the ranking is walked past a dead credential that is not OAuth at all ------------------------------------------
world 3
py 'import base64,os,sys
p=sys.argv[1]+"/credentials/.creds-2-s2@x.test.enc"
open(p,"w").write(base64.b64encode(b"{\"somethingElse\": {}}").decode()); os.chmod(p,0o600)' "$B"
oauthize 3 $FAR
start_stub
tick
is "$(evs)" "poll,account-quarantined,switch" "no oauth block: quarantined, next switched"
is "$(ev_field 1 reason)" invalid_grant "no oauth block: reason (extract_oauth_data is empty)"

# ---- the walk is capped per tick; the rest is finished next tick ------------------------------------------------------
world 19
k=2
spec=""
while [ "$k" -le 19 ]; do
  oauthize "$k" $EXPIRED
  spec="$spec RT-$k:dead"
  k=$((k + 1))
done
# shellcheck disable=SC2086
start_stub $spec
tick
is "$rc" 3 "cap: exit"
is "$(posts)" 17 "cap: 17 candidates tried in one tick"
is "$(ev_field "$(($(printf '%s\n' "$out" | wc -l | tr -d ' ') - 1))" reason)" no-viable-target "cap: reason"
tick
is "$rc" 3 "cap: second tick"
is "$(posts)" 18 "cap: the 18th candidate on the next tick"
is "$(state_q 19 reason)" invalid_grant "cap: the last one is quarantined by then"
# ---- systemic refusals: one named cause, no quarantine, exit 1 ----------------------------------------------------------
MSG_CLIENT="could not freshen: cswap's OAuth client was rejected — systemic, not this account"
MSG_UNMIRRORED="could not freshen: CLAUDE_SECURESTORAGE_CONFIG_DIR is set — unset it or run cswap from a normal shell"
MSG_BUSY="could not freshen: another cswap surface holds the slot — retries next pass"
world 3
oauthize 2 $EXPIRED
oauthize 3 $EXPIRED
start_stub RT-2:client RT-3:client
tick
is "$rc" 1 "invalid_client: exit"
is "$(evs)" "poll,error" "invalid_client: events"
is "$(ev_field 1 message)" "$MSG_CLIENT" "invalid_client: message"
is "$(ev_field 1 transient)" True "invalid_client: transient flag"
is "$(state_q 2)" none "invalid_client: no quarantine (slot 2)"
is "$(state_q 3)" none "invalid_client: no quarantine (slot 3)"
is "$(posts)" 2 "invalid_client: both candidates were tried"

# a rejected client on the first choice does not stop a viable second one
world 3
oauthize 2 $EXPIRED
oauthize 3 $FAR
start_stub RT-2:client
tick
is "$rc" 0 "invalid_client then ok: exit"
is "$(ev_field 1 to number)" 3 "invalid_client then ok: second choice"

# CLAUDE_SECURESTORAGE_CONFIG_DIR set: store-unmirrored, before any POST
world 3
oauthize 2 $EXPIRED
oauthize 3 $EXPIRED
start_stub RT-2:ok RT-3:ok
CLAUDE_SECURESTORAGE_CONFIG_DIR="$D/elsewhere" tick
is "$rc" 1 "store-unmirrored: exit"
is "$(ev_field 1 message)" "$MSG_UNMIRRORED" "store-unmirrored: message"
is "$(posts)" 0 "store-unmirrored: nothing POSTed"
is "$(state_q 2)" none "store-unmirrored: no quarantine"

# consume-busy: another surface holds the slot's consume lock
hold() { # slot
  rm -f "$D/held"
  py 'import fcntl,sys,time
f=open(sys.argv[1]+"/credentials/.consume-"+sys.argv[2]+".lock","a"); fcntl.flock(f,fcntl.LOCK_EX); open(sys.argv[3],"w").write("held"); time.sleep(60)' "$B" "$1" "$D/held" &
  holder=$!
  n=0
  while [ ! -s "$D/held" ]; do
    n=$((n + 1))
    [ "$n" -le 100 ] || fail "lock holder did not start"
    sleep 0.05
  done
}
world 2
oauthize 2 $EXPIRED
start_stub RT-2:ok
hold 2
CSWAP_CONSUME_TIMEOUT_MS=300 tick
kill "$holder" 2> /dev/null || true
is "$rc" 1 "consume-busy: exit"
is "$(ev_field 1 message)" "$MSG_BUSY" "consume-busy: message"
is "$(posts)" 0 "consume-busy: nothing POSTed"
is "$(state_q 2)" none "consume-busy: no quarantine"

# precedence: invalid_client (needs a person) is named over consume-busy (clears itself), whichever sorts later
world 3
oauthize 2 $EXPIRED
oauthize 3 $EXPIRED
start_stub RT-3:client
hold 2
CSWAP_CONSUME_TIMEOUT_MS=300 tick
kill "$holder" 2> /dev/null || true
is "$(ev_field 1 message)" "$MSG_CLIENT" "precedence: the actionable cause is named"

# ---- skip-live-session: an account a running Claude consumes is left alone ---------------------------------------------
mkdir -p "$D/claude-bin"
ln -sf /bin/sleep "$D/claude-bin/claude"
lstart() { LC_ALL=C TZ=UTC ps -o lstart= -p "$1" | sed 's/^ *//'; }
record() { # slot pid procStart-or-empty
  dir="$B/sessions/$1-s$1_x.test/sessions"
  mkdir -p "$dir"
  py 'import json,sys
d={"pid":int(sys.argv[2]),"sessionId":"x"}
if sys.argv[3]: d["procStart"]=sys.argv[3]
open(sys.argv[1],"w").write(json.dumps(d))' "$dir/$2.json" "$2" "$3"
}
sleep 600 &
sleeper=$!
"$D/claude-bin/claude" 600 &
fakeclaude=$!
cleanup() {
  kill "$sleeper" "$fakeclaude" 2> /dev/null || true
  [ -z "$pid" ] || kill "$pid" 2> /dev/null || true
  rm -rf "$D"
}

# a live session on slot 2: skipped (no POST, not quarantined); slot 3 is switched to
world 3
oauthize 2 $EXPIRED
oauthize 3 $FAR
record 2 "$sleeper" "$(lstart "$sleeper")"
start_stub RT-2:ok
tick
is "$rc" 0 "live session: exit"
is "$(posts)" 0 "live session: the account is not refreshed"
is "$(ev_field 1 to number)" 3 "live session: next choice"
is "$(state_q 2)" none "live session: not quarantined"

# the only candidate has a live session: nothing viable, blocked
world 2
oauthize 2 $FAR
record 2 "$sleeper" "$(lstart "$sleeper")"
start_stub
tick
is "$rc" 3 "live session only: exit"
is "$(evs)" "poll,no-switch" "live session only: events"
is "$(ev_field 1 reason)" no-viable-target "live session only: reason"

# a record with no procStart still counts while the pid is alive
world 2
oauthize 2 $FAR
record 2 "$sleeper" ""
start_stub
tick
is "$rc" 3 "unstamped record: exit"

# a numeric stamp (Linux ticks) cannot be checked here: it passes, so the session counts
world 2
oauthize 2 $FAR
record 2 "$sleeper" "123456"
start_stub
tick
is "$rc" 3 "tick stamp: counts when unknowable"

# a dead pid is no session
world 2
oauthize 2 $FAR
record 2 999999 ""
start_stub
tick
is "$rc" 0 "dead pid: exit"
is "$(ev_field 1 to number)" 2 "dead pid: switched"

# a recycled pid (a non-claude that started long after the record) is no session
world 2
oauthize 2 $FAR
record 2 "$sleeper" "Mon Jan  1 00:00:00 2024"
start_stub
tick
is "$rc" 0 "recycled pid: exit"

# ...unless the stranger is itself a claude
world 2
oauthize 2 $FAR
record 2 "$fakeclaude" "Mon Jan  1 00:00:00 2024"
start_stub
tick
is "$rc" 3 "recycled pid held by another claude: still live"

# an unreadable record is no session (a scan, not a guard)
world 2
oauthize 2 $FAR
mkdir -p "$B/sessions/2-s2_x.test/sessions"
printf 'not json' > "$B/sessions/2-s2_x.test/sessions/1.json"
start_stub
tick
is "$rc" 0 "unreadable record: exit"

# ---- identity-conflict: a credential that authenticates as someone else ---------------------------------------------------
# set_slot <slot> <field> <value>: edit the roster record
set_slot() {
  py 'import json,sys
p=sys.argv[1]+"/sequence.json"; d=json.load(open(p)); d["accounts"][sys.argv[2]][sys.argv[3]]=sys.argv[4]; open(p,"w").write(json.dumps(d,indent=2))' "$B" "$1" "$2" "$3"
}
slot_field() { py 'import json,sys;print(json.load(open(sys.argv[1]+"/sequence.json"))["accounts"][sys.argv[2]].get(sys.argv[3]))' "$B" "$1" "$2"; }

# a blank uuid is learned from the token endpoint, and the switch goes ahead
world 3
oauthize 2 $EXPIRED
start_stub "RT-2:acct=U-TWO/ORG-1"
tick
is "$rc" 0 "backfill: exit"
is "$(ev_field 1 to number)" 2 "backfill: switched"
is "$(slot_field 2 uuid)" U-TWO "backfill: the uuid was learned"

# the same account: fine, the recorded uuid is untouched
world 3
oauthize 2 $EXPIRED
set_slot 2 uuid U-TWO
start_stub "RT-2:acct=U-TWO/"
tick
is "$(ev_field 1 to number)" 2 "same account: switched"

# another account: quarantined as identity-conflict, the next choice switched
world 3
oauthize 2 $EXPIRED
oauthize 3 $FAR
set_slot 2 uuid U-TWO
start_stub "RT-2:acct=U-STRANGER/"
tick
is "$rc" 0 "conflict: exit"
is "$(evs)" "poll,account-quarantined,switch" "conflict: events"
is "$(ev_field 1 reason)" identity-conflict "conflict: reason"
is "$(ev_field 2 to number)" 3 "conflict: second choice switched"
is "$(state_q 2 reason)" identity-conflict "conflict: state reason"
is "$(slot_field 2 uuid)" U-TWO "conflict: the recorded uuid is never rewritten"
is "$(enc_at 2)" NEW-AT-RT-2 "conflict: the refresh itself was kept (the grant was consumed)"

# the organization disagrees: a conflict even with no uuid on file, and nothing is learned
world 3
oauthize 2 $EXPIRED
oauthize 3 $FAR
set_slot 2 organizationUuid ORG-A
py 'import json,sys
p=sys.argv[1]+"/cache/usage.json"; d=json.load(open(p)); d["accounts"]["2"]["organizationUuid"]="ORG-A"; open(p,"w").write(json.dumps(d,indent=2))' "$B"
start_stub "RT-2:acct=U-ANY/ORG-B"
tick
is "$(ev_field 1 reason)" identity-conflict "org conflict: reason"
is "$(slot_field 2 uuid)" "" "org conflict: no uuid backfilled"

# no account in the response: nothing to compare
world 3
oauthize 2 $EXPIRED
set_slot 2 uuid U-TWO
start_stub RT-2:ok
tick
is "$(ev_field 1 to number)" 2 "no account named: switched"

# an API-key account is never skipped for a live session (autoswitch.py checks the kind first)
world 2
"$store" remove 2 > /dev/null
"$store" add-token-slot sk-ant-api03-FAKEAPIKEYAPIKEYAPIKEYAPIKEY apikey@x.test 2 > /dev/null
mkdir -p "$B/sessions/2-apikey_x.test/sessions"
printf '{"pid": %s}' "$sleeper" > "$B/sessions/2-apikey_x.test/sessions/$sleeper.json"
py 'import json,sys
p=sys.argv[1]+"/cache/usage.json"; d=json.load(open(p)); d["accounts"]["2"]["email"]="apikey@x.test"; open(p,"w").write(json.dumps(d,indent=2))' "$B"
start_stub
tick --include-api-key-accounts
is "$rc" 0 "api key with a live session: exit"
is "$(ev_field 1 to number)" 2 "api key with a live session: still switched to"
cleanup
echo "daemon_walk_it: ok"
