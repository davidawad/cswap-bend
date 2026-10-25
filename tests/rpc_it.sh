#!/bin/sh
# `cswap rpc` (requests on stdin, one response per message on stdout) and `cswap serve --socket`
# (the same protocol on a unix socket) against a fake store: scratch HOME, fake tokens, seeded
# usage cache, no network. Never touches the real ~/.claude*, ~/.claude-swap-backup.
set -eu
cli=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
H=$(mktemp -d "${TMPDIR:-/tmp}/cswap-rpc-it.XXXXXX")
pids=""
cleanup() {
  for p in $pids; do kill "$p" 2> /dev/null || true; done
  rm -rf "$H"
}
trap cleanup EXIT
export HOME="$H"
unset CLAUDE_CONFIG_DIR CSWAP_SWITCH_ORACLE_FILE CSWAP_STATE_DIR || true
export CSWAP_TEST_HTTP_BASE=http://127.0.0.1:1
export CSWAP_SWITCH_VERIFY_DELAY_MS=0
export NO_COLOR=1
B="$H/.claude-swap-backup"
F="$B/settings.json"

fail() {
  echo "rpc_it: $*" >&2
  exit 1
}
py() { nice -n 19 python3 -I -c "$@"; }
is() { [ "$1" = "$2" ] || fail "$3: got '$1', want '$2'"; }
has() { case "$1" in *"$2"*) ;; *) fail "$3: lacks '$2': $1" ;; esac }
# line N (1-based) of $out as JSON, then the key path
rf() { printf '%s\n' "$out" | py 'import json,sys
n=int(sys.argv[1]); d=json.loads(sys.stdin.read().split("\n")[n-1])
for k in sys.argv[2:]:
    d=d[int(k)] if isinstance(d,list) else d[k]
print("null" if d is None else json.dumps(d,sort_keys=True) if isinstance(d,(dict,list)) else str(d).lower() if isinstance(d,bool) else d)' "$@"; }
lines() { printf '%s\n' "$out" | grep -c . || true; }

# ---- accounts: three setup tokens, a live login on slot 1, a seeded cache --------------------------
mkdir -p "$H/.claude"
for t in a b c; do
  printf 'sk-ant-oat01-FAKE-%s\n' "$t" | "$cli" add-token - --email "$t@x.test" > /dev/null
done
printf '%s' '{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKE-a", "scopes": ["user:inference"]}}' > "$H/.claude/.credentials.json"
printf '%s' '{"numStartups": 7, "oauthAccount": {"emailAddress": "a@x.test", "accountUuid": "", "organizationUuid": null, "organizationName": null}}' > "$H/.claude.json"
py 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["activeAccountNumber"]=1;open(p,"w").write(json.dumps(d,indent=2))' "$B/sequence.json"
py '
import json,sys,time,os
now=time.time()
def row(email,p5,p7):
    g={"five_hour":{"pct":p5,"resets_at":time.strftime("%Y-%m-%dT%H:%M:%S+00:00",time.gmtime(now+7200)),"countdown":"2h","clock":"x"},
       "seven_day":{"pct":p7,"resets_at":time.strftime("%Y-%m-%dT%H:%M:%S+00:00",time.gmtime(now+200000)),"countdown":"2d","clock":"x"}}
    return {"email":email,"organizationUuid":"","lastGood":g,"fetchedAt":now-5,"lastAttemptAt":now-5,"claimId":None,"claimUntil":0.0,
            "consecutiveFailures":0,"lastError":None,"backoffUntil":None,"authDeadStrikes":0,"struckFingerprint":None,"rejectedFingerprint":None,
            "nextPollAt":now+3000,"pollIntervalS":180.0}
doc={"schemaVersion":2,"accounts":{"1":row("a@x.test",20.0,10.0),"2":row("b@x.test",60.0,30.0),"3":row("c@x.test",30.0,40.0)}}
os.makedirs(sys.argv[1]+"/cache",exist_ok=True)
open(sys.argv[1]+"/cache/usage.json","w").write(json.dumps(doc,indent=2))
' "$B"

# ---- rpc over stdin, json ---------------------------------------------------------------------------
req="$H/req.jsonl"
cat > "$req" << 'EOF'
{"id":1,"cmd":"list"}
{"id":"two","cmd":"status"}

{"id":3,"cmd":"config","args":["get","autoswitch.threshold"]}
{"id":4,"cmd":"config","args":["set","autoswitch.threshold","85"]}
{"id":5,"cmd":"config","args":["set","bogus","1"]}
this is not json
{"id":7,"cmd":"auto"}
{"id":8,"cmd":"tui"}
{"id":9,"cmd":"frobnicate"}
{"id":10,"cmd":"remove","args":["3"]}
{"id":11,"cmd":"switch","args":["2"]}
{"id":12,"cmd":"switch","opts":{"strategy":"best"}}
{"id":13,"cmd":"profile","args":["set","night","strategy","drain-first"]}
{"id":14,"cmd":"profile","args":["list"]}
{"id":15,"cmd":"add-token","args":["sk-ant-oat01-FAKE-d"],"opts":{"email":"d@x.test"}}
{"id":16,"cmd":"add-token","args":["-"]}
{"id":17,"cmd":"remove","args":["4"],"opts":{"yes":true}}
{"id":18,"cmd":"list","opts":{"nope":true}}
{"id":19,"cmd":"config","args":["export"]}
{"id":20,"cmd":"config","args":["import"],"opts":{"data":"autoswitch:\n  cooldownSeconds: 120\n","format":"yaml"}}
{"id":21,"cmd":"config","args":["import"],"opts":{"data":"autoswitch:\n  threshold: 5\n","format":"yaml"}}
{"cmd":"version"}
{"id":[1,{"a":null}],"cmd":"help"}
EOF
rc=0
out=$("$cli" rpc < "$req" 2> "$H/stderr") || rc=$?
is "$rc" 0 "rpc exit code at end of input"
is "$(cat "$H/stderr")" "" "nothing on stderr"
is "$(lines)" 23 "one response per message (the blank line has none)"
is "$(rf 1 id)" 1 "id echoed"
is "$(rf 1 ok)" true "list ok"
is "$(rf 1 result schemaVersion)" 1 "list result is the json document"
is "$(rf 1 result accounts 0 email)" a@x.test "first account"
is "$(rf 1 result accounts 1 usage fiveHour pct)" 60.0 "usage in the result"
is "$(rf 2 id)" two "string id echoed"
is "$(rf 2 result active email)" a@x.test "status"
is "$(rf 3 result value)" 90.0 "config get"
is "$(rf 4 result message)" "autoswitch.threshold = 85" "config set wraps its message"
is "$(py 'import json,sys;print(json.load(open(sys.argv[1]))["autoswitch"]["threshold"])' "$F")" 85.0 "config set wrote the file"
is "$(rf 5 ok)" false "config set error"
is "$(rf 5 error code)" Error "error code"
has "$(rf 5 error message)" "unknown setting" "error message"
is "$(rf 5 error exit)" 1 "exit status"
is "$(rf 6 id)" null "bad json: no id"
is "$(rf 6 error code)" bad_request "bad json code"
is "$(rf 7 id)" 7 "auto id"
is "$(rf 7 error code)" not_allowed "auto refused"
has "$(rf 7 error message)" "auto is not available over rpc" "auto message"
is "$(rf 8 error code)" not_allowed "tui refused"
is "$(rf 9 error code)" unknown_command "unknown command"
is "$(rf 10 error code)" Error "remove without yes"
has "$(rf 10 error message)" "pass --yes" "remove message"
is "$(rf 11 result switched)" true "switch"
is "$(rf 11 result to number)" 2 "switch target"
is "$(rf 12 ok)" true "switch --strategy"
is "$(rf 13 result profile strategy)" drain-first "profile set"
is "$(rf 14 result profiles 0 name)" default "profile list"
is "$(rf 15 result message)" "Added Account 4: d@x.test [personal] (from token)" "add-token"
is "$(rf 16 error code)" Error "dash token refused"
has "$(rf 16 error message)" "the token must be on the command line" "dash token message"
is "$(rf 17 result message)" "Removed Account-4 (d@x.test)" "remove with yes"
is "$(rf 18 error code)" usage "unknown option is a usage error"
is "$(rf 18 error exit)" 2 "usage exit"
has "$(rf 19 result autoswitch)" "85.0" "config export result"
is "$(rf 20 ok)" true "config import with inline data"
is "$(rf 20 result format)" yaml "its format"
is "$(py 'import json,sys;print(json.load(open(sys.argv[1]))["autoswitch"]["cooldownSeconds"])' "$F")" 120.0 "import wrote the file"
is "$(rf 21 ok)" false "config import with a bad value"
has "$(rf 21 error message)" "autoswitch.threshold must be between 50 and 99.9" "its message"
is "$(rf 22 id)" null "request without id"
has "$(rf 22 result message)" "cswap-bend" "version"
is "$(rf 23 id)" '[1, {"a": null}]' "structured id echoed"
has "$(rf 23 result message)" "usage: cswap" "help"
# the result is what `--format json` prints
"$cli" list --format json < /dev/null > "$H/cli-list.json"
is "$(printf '%s\n' "$out" | head -n 1 | py 'import json,sys
V={"countdown","clock","usageAgeSeconds","expectedPct","aheadOfPace","projectedExhaustionAt","willLastToReset","usageRetryAt"}
def clean(x):
    if isinstance(x,dict): return {k:clean(v) for k,v in x.items() if k not in V}
    if isinstance(x,list): return [clean(v) for v in x]
    return x
print(json.dumps(clean(json.loads(sys.stdin.read())["result"]),sort_keys=True))')" "$(py 'import json,sys
V={"countdown","clock","usageAgeSeconds","expectedPct","aheadOfPace","projectedExhaustionAt","willLastToReset","usageRetryAt"}
def clean(x):
    if isinstance(x,dict): return {k:clean(v) for k,v in x.items() if k not in V}
    if isinstance(x,list): return [clean(v) for v in x]
    return x
print(json.dumps(clean(json.load(open(sys.argv[1]))),sort_keys=True))' "$H/cli-list.json")" "rpc result equals list --format json"

# ---- the responses come as the requests do: no waiting for end of input --------------------------------
py '
import json,subprocess,sys
p=subprocess.Popen([sys.argv[1],"rpc"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
for i in range(3):
    p.stdin.write(json.dumps({"id":i,"cmd":"config","args":["get","autoswitch.threshold"]})+"\n"); p.stdin.flush()
    r=json.loads(p.stdout.readline())
    assert r["id"]==i and r["ok"] is True, r
p.stdin.close()
assert p.wait(timeout=30)==0
print("interactive ok")
' "$cli" > "$H/interactive.out" 2>&1 || fail "interactive rpc: $(cat "$H/interactive.out")"

# ---- a last request without a newline is still answered -------------------------------------------------
out=$(printf '{"id":1,"cmd":"config","args":["get","autoswitch.threshold"]}' | "$cli" rpc)
is "$(rf 1 result key)" autoswitch.threshold "no trailing newline"

# ---- yaml and toon messages: a block ended by a blank line --------------------------------------------------
out=$(printf 'id: 1\ncmd: config\nargs:\n  - get\n  - autoswitch.threshold\n\nid: b\ncmd: nope\n\n' | "$cli" rpc --format yaml)
is "$(printf '%s\n' "$out" | head -n 7)" "id: 1
ok: true
result:
  schemaVersion: 1
  key: autoswitch.threshold
  value: 85.0
  isSet: true" "yaml response"
has "$out" "code: unknown_command" "yaml error"
out=$(printf 'id: 1\ncmd: config\nargs[2]: get,autoswitch.threshold\n\n' | "$cli" rpc --format toon)
has "$out" "value: 85" "toon response"
has "$out" "isSet: true" "toon isSet"
out=$(printf 'id: 1\ncmd: [\n\nid: 2\ncmd: help\n\n' | "$cli" rpc --format yaml)
has "$out" "code: bad_request" "a bad yaml message is answered"
has "$out" "id: 2" "and the next one still is"

# ---- usage errors ------------------------------------------------------------------------------------------------
rc=0
"$cli" rpc --format csv < /dev/null > /dev/null 2> "$H/stderr" || rc=$?
is "$rc" 2 "rpc --format csv"
has "$(cat "$H/stderr")" "invalid choice: 'csv' (choose from 'json', 'toon', 'yaml')" "message"
rc=0
"$cli" serve < /dev/null > /dev/null 2> "$H/stderr" || rc=$?
is "$rc" 2 "serve without --socket"
has "$(cat "$H/stderr")" "the following arguments are required: --socket" "message"
rc=0
"$cli" rpc --bogus < /dev/null > /dev/null 2> "$H/stderr" || rc=$?
is "$rc" 2 "rpc --bogus"

# ---- serve ---------------------------------------------------------------------------------------------------------
S="$H/cswap.sock"
"$cli" serve --socket "$S" < /dev/null > "$H/serve.out" 2> "$H/serve.err" &
srv=$!
pids="$pids $srv"
n=0
until [ -S "$S" ]; do
  n=$((n + 1))
  [ "$n" -le 200 ] || fail "serve made no socket: $(cat "$H/serve.err")"
  sleep 0.1
done
mode=$(stat -c %a "$S" 2> /dev/null || stat -f %Lp "$S")
is "$mode" 600 "socket mode"
cat > "$H/client.py" << 'EOF'
import json, socket, sys

def conn(path):
    c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    c.settimeout(60)
    c.connect(path)
    return c, c.makefile("rw", newline="\n")

path = sys.argv[1]
# two clients one after the other; several requests each, answered in order
for round_ in range(2):
    c, f = conn(path)
    for i, req in enumerate((
        {"id": [round_, 1], "cmd": "config", "args": ["get", "autoswitch.threshold"]},
        {"id": [round_, 2], "cmd": "list"},
        {"id": [round_, 3], "cmd": "auto"},
    )):
        f.write(json.dumps(req) + "\n")
        f.flush()
        r = json.loads(f.readline())
        assert r["id"] == [round_, i + 1], r
        if i == 0:
            assert r["ok"] is True and r["result"]["key"] == "autoswitch.threshold", r
        if i == 1:
            assert r["ok"] is True and len(r["result"]["accounts"]) == 3, r
        if i == 2:
            assert r["ok"] is False and r["error"]["code"] == "not_allowed", r
    c.close()
# a request without the final newline, then half-close: still answered
c, f = conn(path)
c.sendall(b'{"id":"tail","cmd":"config","args":["get","autoswitch.threshold"]}')
c.shutdown(socket.SHUT_WR)
r = json.loads(f.readline())
assert r["id"] == "tail" and r["ok"] is True, r
c.close()
# a bad message is answered and the connection stays usable
c, f = conn(path)
f.write("{nope\n")
f.flush()
r = json.loads(f.readline())
assert r["ok"] is False and r["error"]["code"] == "bad_request", r
f.write(json.dumps({"id": 9, "cmd": "status"}) + "\n")
f.flush()
r = json.loads(f.readline())
assert r["id"] == 9 and r["ok"] is True, r
c.close()
# yaml framing on the same socket is a server-wide choice: json here
print("client ok")
EOF
nice -n 19 python3 -I "$H/client.py" "$S" > "$H/client.out" 2>&1 || fail "socket client: $(cat "$H/client.out") $(cat "$H/serve.err")"
# the same through nc, when it speaks unix sockets
if command -v nc > /dev/null 2>&1 && nc -h 2>&1 | grep -q -- '-U'; then
  out=$(printf '{"id":1,"cmd":"config","args":["get","autoswitch.threshold"]}\n' | nc -U -w 20 "$S")
  is "$(rf 1 ok)" true "nc -U"
fi
kill -TERM "$srv"
rc=0
wait "$srv" || rc=$?
is "$rc" 0 "serve exits 0 on SIGTERM"
[ ! -e "$S" ] || fail "the socket file is still there after SIGTERM"
pids=""

# a stale socket is replaced; a regular file at the path is not
S2="$H/stale.sock"
py 'import socket,sys;s=socket.socket(socket.AF_UNIX);s.bind(sys.argv[1]);s.close()' "$S2"
[ -S "$S2" ] || fail "no stale socket made"
"$cli" serve --socket "$S2" < /dev/null > /dev/null 2> "$H/serve2.err" &
srv=$!
pids="$srv"
n=0
until py 'import socket,sys;c=socket.socket(socket.AF_UNIX);c.connect(sys.argv[1])' "$S2" 2> /dev/null; do
  n=$((n + 1))
  [ "$n" -le 200 ] || fail "the server never took over the stale socket: $(cat "$H/serve2.err")"
  sleep 0.1
done
kill -INT "$srv"
rc=0
wait "$srv" || rc=$?
is "$rc" 0 "serve exits 0 on SIGINT"
[ ! -e "$S2" ] || fail "the socket file is still there after SIGINT"
pids=""
printf 'x' > "$H/plain"
rc=0
"$cli" serve --socket "$H/plain" < /dev/null > /dev/null 2> "$H/stderr" || rc=$?
is "$rc" 1 "serve over a regular file"
has "$(cat "$H/stderr")" "cannot listen on" "message"
is "$(cat "$H/plain")" x "the file is untouched"
rc=0
"$cli" serve --socket "$H/no/such/dir/s.sock" < /dev/null > /dev/null 2> "$H/stderr" || rc=$?
is "$rc" 1 "serve in a missing directory"

# ---- serve in yaml ----------------------------------------------------------------------------------------------------
S3="$H/y.sock"
"$cli" serve --socket "$S3" --format yaml < /dev/null > /dev/null 2> "$H/serve3.err" &
srv=$!
pids="$srv"
n=0
until [ -S "$S3" ]; do
  n=$((n + 1))
  [ "$n" -le 200 ] || fail "yaml serve made no socket"
  sleep 0.1
done
got=$(py '
import socket,sys
c=socket.socket(socket.AF_UNIX); c.settimeout(60); c.connect(sys.argv[1])
c.sendall(b"id: 1\ncmd: config\nargs:\n  - get\n  - autoswitch.threshold\n\n")
buf=b""
while not buf.endswith(b"\n\n"):
    d=c.recv(4096)
    assert d
    buf+=d
print(buf.decode())' "$S3")
has "$got" "ok: true" "yaml over the socket"
has "$got" "key: autoswitch.threshold" "yaml result"
kill -TERM "$srv"
wait "$srv" || true
pids=""
echo "rpc_it: ok"
