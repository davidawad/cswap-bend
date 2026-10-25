#!/bin/sh
# `cswap auto` on scratch HOMEs with fake tokens and a seeded usage cache (no
# network): the events, exit codes, state file, status file, log line, the
# single-decider lock and the loop. The parity fixtures 21-31 and 33 run through
# the real CLI (`just parity-bend`).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
BEND=${BEND:-bend}
mkdir -p "$root/bin"
nice -n 19 "$BEND" "$here/it/store_main.bend" -o "$root/bin/store-it" > /dev/null
nice -n 19 "$BEND" "$here/it/daemon_main.bend" -o "$root/bin/daemon-it" > /dev/null
store="$root/bin/store-it"
auto="$root/bin/daemon-it"
H=$(mktemp -d "${TMPDIR:-/tmp}/cswap-daemon-it.XXXXXX")
pids=""
cleanup() {
  for p in $pids; do kill "$p" 2> /dev/null || true; done
  rm -rf "$H"
}
trap cleanup EXIT
export HOME="$H"
unset CLAUDE_CONFIG_DIR CSWAP_TEST_HTTP_BASE CSWAP_SWITCH_ORACLE_FILE CSWAP_STATE_DIR || true
export CSWAP_SWITCH_VERIFY_DELAY_MS=0
B="$H/.claude-swap-backup"

fail() {
  echo "daemon_it: $*" >&2
  exit 1
}
py() { nice -n 19 python3 -I -c "$@"; }
rc=0
out=
run() {
  rc=0
  out=$("$@" 2> "$H/stderr") || rc=$?
}
is() { [ "$1" = "$2" ] || fail "$3: got '$1', want '$2'"; }
# jq-like: field of the n-th JSONL line of $out
line_field() { printf '%s\n' "$out" | py 'import json,sys
n=int(sys.argv[1]); d=json.loads(sys.stdin.read().strip().split("\n")[n])
for k in sys.argv[2:]:
    d=d[int(k)] if isinstance(d,list) else d[k]
print(json.dumps(d) if isinstance(d,(dict,list)) else d)' "$@"; }

# ---- three setup-token accounts and a seeded cache --------------------------------------------
"$store" add-token sk-ant-oat01-FAKEAAA a@x.test > /dev/null
"$store" add-token sk-ant-oat01-FAKEBBB b@x.test > /dev/null
"$store" add-token sk-ant-oat01-FAKECCC c@x.test > /dev/null
A='{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKEAAA", "scopes": ["user:inference"]}}'
printf '%s' "{\"numStartups\": 7, \"oauthAccount\": {\"emailAddress\": \"a@x.test\", \"accountUuid\": \"\", \"organizationUuid\": null, \"organizationName\": null}}" > "$H/.claude.json"
mkdir -p "$H/.claude"
printf '%s' "$A" > "$H/.claude/.credentials.json"

# usage <a5h> <b5h> <c5h> [scoped-for-a]: fresh rows, nothing planned
seed() {
  py '
import json,sys,time
now=time.time()
def row(email,p5,scoped=None):
    g={"five_hour":{"pct":p5,"resets_at":time.strftime("%Y-%m-%dT%H:%M:%S+00:00",time.gmtime(now+7200)),"countdown":"2h","clock":"x"},
       "seven_day":{"pct":10.0,"resets_at":time.strftime("%Y-%m-%dT%H:%M:%S+00:00",time.gmtime(now+200000)),"countdown":"2d","clock":"x"}}
    if scoped: g["scoped"]=scoped
    return {"email":email,"organizationUuid":"","lastGood":g,"fetchedAt":now-5,"lastAttemptAt":now-5,"claimId":None,"claimUntil":0.0,
            "consecutiveFailures":0,"lastError":None,"backoffUntil":None,"authDeadStrikes":0,"struckFingerprint":None,"rejectedFingerprint":None,
            "nextPollAt":now+3000,"pollIntervalS":180.0}
a,b,c=[float(x) for x in sys.argv[2:5]]
scoped=json.loads(sys.argv[5]) if len(sys.argv)>5 else None
doc={"schemaVersion":2,"accounts":{"1":row("a@x.test",a,scoped),"2":row("b@x.test",b),"3":row("c@x.test",c)}}
import os
os.makedirs(sys.argv[1]+"/cache",exist_ok=True)
open(sys.argv[1]+"/cache/usage.json","w").write(json.dumps(doc,indent=2))
' "$B" "$@"
}

# ---- below the threshold: poll + no-switch, exit 2, nothing recorded but status and log ---------
seed 20 50 60
run "$auto" auto --once --json --threshold 85 --strategy best
is "$rc" 2 "below threshold exit"
is "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 2 "event count"
is "$(line_field 0 event)" poll "first event"
is "$(line_field 0 active)" '{"number": 1, "email": "a@x.test"}' "active"
is "$(line_field 0 headroomPct)" '{"1": 80.0, "2": 50.0, "3": 40.0}' "headroom"
is "$(line_field 1 reason)" below-threshold "reason"
is "$(line_field 1 detail)" "20% < 85%" "detail"
[ ! -e "$B/autoswitch_state.json" ] || fail "state written without a switch"

# the status file: who, when, per account
st="$B/daemon-status.json"
[ -f "$st" ] || fail "no status file"
[ "$(stat -c %a "$st" 2> /dev/null || stat -f %Lp "$st")" = 600 ] || fail "status mode"
py '
import json,sys
d=json.load(open(sys.argv[1]))
assert d["schemaVersion"]==1 and d["version"]=="cswap-bend 0.0.1",d
assert isinstance(d["pid"],int) and d["pid"]>0
assert d["active"]==1,d["active"]
assert d["started_at"].endswith("Z") and d["last_poll_at"].endswith("Z") and d["next_poll_at"].endswith("Z")
a=d["accounts"]
assert list(a)==["1","2","3"],list(a)
assert a["1"]["pct_5h"]==20.0 and a["1"]["pct_7d"]==10.0 and a["1"]["last_error"] is None and a["1"]["backoff_until"] is None
assert a["1"]["fetched_at"].endswith("Z")
c=d["config"]
assert c["threshold"]==85.0 and c["strategy"]=="best" and c["interval_seconds"]==60 and c["models"]==[],c
' "$st" || fail "status file shape"

# the log: one JSONL line per tick, with the source of every reading
log="$B/daemon.log"
[ -f "$log" ] || fail "no daemon.log"
py '
import json,sys
l=[json.loads(x) for x in open(sys.argv[1]) if x.strip()]
assert len(l)==1,l
e=l[0]
assert e["msg"]=="tick" and e["level"]=="info" and e["outcome"]=="no-action" and e["active"]=="1",e
assert [a["slot"] for a in e["accounts"]]==[1,2,3],e
assert all(a["source"]=="cache" for a in e["accounts"]),e
assert e["accounts"][0]["pct_5h"]==20.0
' "$log" || fail "log line"

# ---- at the limit: switches to the account with the most headroom, records it ---------------------
seed 100 70 50
run "$auto" auto --once --json --threshold 85 --strategy best
is "$rc" 0 "switch exit"
is "$(line_field 1 event)" switch "switch event"
is "$(line_field 1 trigger)" at-limit "trigger"
is "$(line_field 1 to)" '{"number": 3, "email": "c@x.test"}' "target is the roomiest"
is "$(line_field 1 dryRun)" False "not a dry run"
is "$(py 'import json,sys;print(json.load(open(sys.argv[1]))["accounts"]["3"]["email"])' "$B/sequence.json")" c@x.test "roster"
is "$(py 'import json,sys;print(json.load(open(sys.argv[1]))["activeAccountNumber"])' "$B/sequence.json")" 3 "active slot moved"
py '
import json,sys
d=json.load(open(sys.argv[1]))
assert list(d)[:2]==["schemaVersion","lastSwitchAt"],list(d)
assert d["lastSwitchTo"]=="3" and d["lastSwitchFrom"]==1 and d["leftTrigger"]=="at-limit" and d["leftHeadroom"]==0.0,d
assert isinstance(d["leftRecoveryAt"],float)
' "$B/autoswitch_state.json" || fail "state file"
[ "$(stat -c %a "$B/autoswitch_state.json" 2> /dev/null || stat -f %Lp "$B/autoswitch_state.json")" = 600 ] || fail "state mode"
py 'import json,sys;d=json.load(open(sys.argv[1]));assert d["oauthAccount"]["emailAddress"]=="c@x.test"' "$H/.claude.json" || fail "live login moved"

# ---- a dry run changes nothing -------------------------------------------------------------------
trash_state() { py 'import os,sys
for p in sys.argv[1:]:
    if os.path.exists(p): os.rename(p, p+".old")' "$@"; }
trash_state "$B/autoswitch_state.json"
printf '%s' "$A" > "$H/.claude/.credentials.json"
printf '%s' '{"numStartups": 7, "oauthAccount": {"emailAddress": "a@x.test", "accountUuid": "", "organizationUuid": null, "organizationName": null}}' > "$H/.claude.json"
py 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["activeAccountNumber"]=1;open(p,"w").write(json.dumps(d,indent=2))' "$B/sequence.json"
seed 100 50 70
run "$auto" auto --once --json --threshold 85 --dry-run
is "$rc" 0 "dry run exit"
is "$(line_field 1 dryRun)" True "dry run flagged"
[ ! -e "$B/autoswitch_state.json" ] || fail "dry run wrote state"
is "$(py 'import json,sys;print(json.load(open(sys.argv[1]))["oauthAccount"]["emailAddress"])' "$H/.claude.json")" a@x.test "dry run moved the login"

# ---- a typo in --model is reported once --------------------------------------------------------------
seed 20 50 60 '[{"name": "Opus", "pct": 10.0, "resets_at": "2099-01-01T00:00:00+00:00"}]'
run "$auto" auto --once --json --threshold 85 --model Opus,Nope
is "$(line_field 1 event)" config-warning "warning event"
case "$(line_field 1 message)" in
  "autoswitch.model: Nope matches no account's usage windows"*) ;;
  *) fail "warning text: $out" ;;
esac
is "$(line_field 0 windowsPct)" '{"1": {"5h": 20.0, "7d": 10.0, "Opus": 10.0}, "2": {"5h": 50.0, "7d": 10.0}, "3": {"5h": 60.0, "7d": 10.0}}' "model windows in the poll"

# ---- settings.json under the flags --------------------------------------------------------------------
printf '%s' '{"schemaVersion": 1, "autoswitch": {"threshold": 10}}' > "$B/settings.json"
seed 20 50 60
run "$auto" auto --once --json
is "$(line_field 0 threshold)" 50.0 "settings threshold is clamped to 50"
run "$auto" auto --once --json --threshold 70
is "$(line_field 0 threshold)" 70.0 "a flag beats settings.json"
run "$auto" auto --once --json --threshold abc
is "$rc" 2 "bad flag exit"
case "$(cat "$H/stderr")" in *"invalid float value: 'abc'"*) ;; *) fail "bad flag message: $(cat "$H/stderr")" ;; esac

# ---- one decider per backup root ----------------------------------------------------------------------
seed 20 50 60
"$auto" auto --json --interval 15 --threshold 85 > "$H/loop.out" 2> "$H/loop.err" &
loop=$!
pids="$pids $loop"
n=0
until [ -s "$H/loop.out" ]; do
  n=$((n + 1))
  [ "$n" -le 100 ] || fail "the loop printed nothing"
  sleep 0.1
done
run "$auto" auto --once --json
is "$rc" 1 "second decider exit"
case "$(cat "$H/stderr")" in
  *"Another \`cswap auto\` is already running on this backup root (pid $loop;"*) ;;
  *) fail "second decider message: $(cat "$H/stderr")" ;;
esac
[ -z "$out" ] || fail "second decider printed events"
is "$(cat "$B/daemon.pid" | tr -d '\n')" "$loop" "pid file names the loop"
# the loop's first tick is on stdout
is "$(head -n 1 "$H/loop.out" | py 'import json,sys;print(json.loads(sys.stdin.read())["event"])')" poll "loop first event"
kill "$loop"
wait "$loop" 2> /dev/null || true
# the kernel dropped the lock with the process: a new decider starts
run "$auto" auto --once --json --threshold 85
is "$rc" 2 "decider after the loop died"

# ---- --shadow: reads the cache, decides, logs, and changes nothing -------------------------------------
# A stub HTTP server stands behind the test seam; shadow mode must never reach it.
cat > "$H/stub.py" <<'PY'
import http.server, sys
log = sys.argv[1]
class Hd(http.server.BaseHTTPRequestHandler):
    def _any(self):
        open(log, "a").write(self.command + " " + self.path + "\n")
        self.send_response(500)
        self.end_headers()
    do_GET = do_POST = do_PUT = _any
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), Hd)
open(sys.argv[2], "w").write(str(srv.server_port))
srv.serve_forever()
PY
: > "$H/stub.requests"
nice -n 19 python3 -I "$H/stub.py" "$H/stub.requests" "$H/stub.port" &
stub=$!
pids="$pids $stub"
n=0
until [ -s "$H/stub.port" ]; do
  n=$((n + 1))
  [ "$n" -le 100 ] || fail "stub did not start"
  sleep 0.1
done
export CSWAP_TEST_HTTP_BASE="http://127.0.0.1:$(cat "$H/stub.port")"
# rows overdue for a poll (a live daemon would fetch), active over the threshold
seed 90 30 60
py 'import json,sys,time
p=sys.argv[1]+"/cache/usage.json"; d=json.load(open(p))
for r in d["accounts"].values(): r["nextPollAt"]=time.time()-100
open(p,"w").write(json.dumps(d,indent=2))' "$B"
snap() { (cd "$B" && find . -type f | sort | while read -r f; do printf '%s ' "$f"; cksum < "$f"; done; find . -type d | sort) | cksum; }
before=$(snap)
mkdir -p "$H/shadow"
run "$auto" auto --once --shadow --shadow-log "$H/shadow/s.jsonl" --threshold 85 --strategy best
is "$rc" 0 "shadow exit ($(cat "$H/stderr") $out)"
[ -s "$H/shadow/s.jsonl" ] || fail "shadow wrote no log line"
is "$(wc -l < "$H/shadow/s.jsonl" | tr -d ' ')" 1 "one line per tick"
sl() { py 'import json,sys
d=json.loads(open(sys.argv[1]).read().strip().split("\n")[-1]); v=d[sys.argv[2]]
print(json.dumps(v) if isinstance(v,(dict,list)) else v)' "$H/shadow/s.jsonl" "$1"; }
is "$(sl event)" switch "shadow decision"
is "$(sl trigger)" proactive "shadow trigger"
is "$(sl to)" '{"number": 2, "email": "b@x.test"}' "shadow target"
is "$(sl from)" '{"number": 1, "email": "a@x.test"}' "shadow source"
is "$(sl active)" 1 "shadow active"
case "$(sl events)" in *headroomPct*) ;; *) fail "no headroom in the shadow line" ;; esac
is "$(py 'import json,sys;print(json.load(open("'"$H"'/.claude.json"))["oauthAccount"]["emailAddress"])')" a@x.test "shadow switched the login"
is "$(snap)" "$before" "shadow changed something under the backup root"
[ ! -s "$H/stub.requests" ] || fail "shadow made HTTP requests: $(cat "$H/stub.requests")"
# a second tick appends; the shadow dir holds the only extra files
run "$auto" auto --once --shadow --shadow-log "$H/shadow/s.jsonl" --threshold 85 --strategy best
is "$(wc -l < "$H/shadow/s.jsonl" | tr -d ' ')" 2 "appends"
is "$(snap)" "$before" "second shadow tick changed the backup root"
# --shadow without --shadow-log is a usage error
run "$auto" auto --once --shadow
is "$rc" 2 "shadow without a log path"
case "$(cat "$H/stderr")" in *"--shadow needs --shadow-log"*) ;; *) fail "shadow usage message" ;; esac

# shadow-compare reads the shadow log: two real ticks against a synthetic Python auto.log
py 'import json,sys,time
t=time.time()
def iso(x): return time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime(x))
lines=[]
for dt in (0,10):
    ts=iso(t+dt)
    lines.append(ts+" "+json.dumps({"event":"loop-start","ts":ts}))
    lines.append(ts+" "+json.dumps({"event":"poll","ts":ts,"active":{"number":1,"email":"a@x.test"},"headroomPct":{"1":10.0,"2":70.0,"3":40.0}}))
    lines.append(ts+" "+json.dumps({"event":"switch","ts":ts,"trigger":"proactive","from":{"number":1,"email":"a@x.test"},"to":{"number":2,"email":"b@x.test"}}))
open(sys.argv[1],"w").write("\n".join(lines)+"\n")' "$H/auto.log"
nice -n 19 python3 -I "$root/scripts/shadow-compare" "$H/auto.log" "$H/shadow/s.jsonl" --json > "$H/compare.json"
cmp_field() { py 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    d=d[int(k)] if isinstance(d,list) else d[k]
print(json.dumps(d,sort_keys=True) if isinstance(d,(dict,list)) else d)' "$H/compare.json" "$@"; }
is "$(cmp_field paired)" 2 "shadow-compare pairs both ticks"
is "$(cmp_field agreed)" 2 "shadow-compare: the decisions agree"
is "$(cmp_field unpaired_bend)" "[]" "shadow-compare: no unpaired Bend tick"
is "$(cmp_field pairs 0 bend headroom)" '{"1": 10.0, "2": 70.0, "3": 40.0}' "shadow-compare reads the headroom"
is "$(cmp_field pairs 0 bend active)" 1 "shadow-compare reads the active slot"
is "$(cmp_field pairs 0 bend to)" 2 "shadow-compare reads the target"
is "$(cmp_field pairs 0 bend trigger)" proactive "shadow-compare reads the trigger"
is "$(py 'import json,sys;print(sum(1 for l in open(sys.argv[1]) if json.loads(l)))' "$H/shadow/s.jsonl")" 2 "every shadow line is JSON"

# the launchd templates' flags (shadow and live) are accepted by the real CLI's `auto`
if [ -n "${1:-}" ]; then
  cli=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  for tpl in com.david.cswap-bend-shadow com.david.cswap-bend; do
    sed -e "s|@BIN@|$cli|g" -e "s|@SHADOW_LOG@|$H/shadow/$tpl.jsonl|g" -e "s|@INTERVAL@|300|g" -e "s|@THRESHOLD@|85|g" \
      -e "s|@MODELS@|Fable,Opus|g" -e "s|@STRATEGY@|best|g" -e "s|@HOME@|$H|g" -e "s|@STATE_DIR@|$H|g" \
      "$root/deploy/$tpl.plist.in" > "$H/$tpl.plist"
    py 'import plistlib,sys
a=plistlib.load(open(sys.argv[1],"rb"))["ProgramArguments"]
open(sys.argv[2],"w").write("\0".join(a+["--once"]))' "$H/$tpl.plist" "$H/$tpl.argv"
    out=$(py 'import subprocess,sys
a=open(sys.argv[1]).read().split("\0")
r=subprocess.run(a,capture_output=True,text=True)
print(r.returncode); print(r.stderr.strip()); print(r.stdout.strip()[:200])' "$H/$tpl.argv")
    is "$(printf '%s\n' "$out" | sed -n 2p)" "" "$tpl: stderr ($out)"
    is "$(printf '%s\n' "$out" | sed -n 1p)" 0 "$tpl: exit ($out)"
  done
  # the live template switches (human output) in this scratch HOME
  case "$out" in *Switched*) ;; *) fail "live template: no switch event ($out)" ;; esac
  is "$(wc -l < "$H/shadow/com.david.cswap-bend-shadow.jsonl" | tr -d ' ')" 1 "shadow template: one tick logged"
  is "$(py 'import json,sys;print(json.loads(open(sys.argv[1]).readline())["event"])' "$H/shadow/com.david.cswap-bend-shadow.jsonl")" switch "shadow template: decision"
fi
kill "$stub" 2> /dev/null || true
echo "daemon_it: ok"
