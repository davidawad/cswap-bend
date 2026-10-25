#!/bin/sh
# Behaviour profiles end to end through the real CLI, on a scratch HOME with
# fake tokens and a seeded usage cache (no network): `cswap profile list|show|
# use|set|remove` (text and --json, every other settings key kept), `switch`
# under a profile (--profile, the active profile, the legacy rotation when none
# is in play), and `auto` (the profile and strategy on each decision event, the
# profile laid over the settings, `profile use` taking effect on the next tick of
# a running loop). Never touches the real ~/.claude*, ~/.claude-swap-backup.
set -eu
cli=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
H=$(mktemp -d "${TMPDIR:-/tmp}/cswap-profile-it.XXXXXX")
pids=""
cleanup() {
  for p in $pids; do kill "$p" 2> /dev/null || true; done
  rm -rf "$H"
}
trap cleanup EXIT
export HOME="$H"
unset CLAUDE_CONFIG_DIR CSWAP_SWITCH_ORACLE_FILE CSWAP_STATE_DIR || true
# Every request goes to a closed local port: nothing here may reach the real API.
export CSWAP_TEST_HTTP_BASE=http://127.0.0.1:1
export CSWAP_SWITCH_VERIFY_DELAY_MS=0
export NO_COLOR=1
B="$H/.claude-swap-backup"
F="$B/settings.json"

fail() {
  echo "profile_it: $*" >&2
  exit 1
}
py() { nice -n 19 python3 -I -c "$@"; }
rc=0
out=
err=
run() {
  rc=0
  out=$("$cli" "$@" 2> "$H/stderr" < /dev/null) || rc=$?
  err=$(cat "$H/stderr")
}
is() { [ "$1" = "$2" ] || fail "$3: got '$1', want '$2'"; }
code() { is "$rc" "$1" "$2: exit code"; }
has() { case "$1" in *"$2"*) ;; *) fail "$3: lacks '$2': $1" ;; esac }
# field of the JSON in $out: jf KEY KEY...
jf() { printf '%s\n' "$out" | py 'import json,sys
d=json.loads(sys.stdin.read())
for k in sys.argv[1:]:
    d=d[int(k)] if isinstance(d,list) else d[k]
print("null" if d is None else json.dumps(d) if isinstance(d,(dict,list)) else d)' "$@"; }
# field of the n-th JSONL line of $out
lf() { printf '%s\n' "$out" | py 'import json,sys
n=int(sys.argv[1]); d=json.loads(sys.stdin.read().strip().split("\n")[n])
for k in sys.argv[2:]:
    d=d[int(k)] if isinstance(d,list) else d[k]
print("null" if d is None else json.dumps(d) if isinstance(d,(dict,list)) else d)' "$@"; }
sget() { py 'import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    d=d[int(k)] if isinstance(d,list) else d[k]
print("null" if d is None else json.dumps(d) if isinstance(d,(dict,list)) else d)' "$F" "$@"; }

# ---- no profiles: the built-ins are there, `default` is active ---------------------------------
run profile list
code 0 "list empty"
has "$out" "* default        best" "default is active"
has "$out" "round-robin" "round-robin built in"
has "$out" "drain-first" "drain-first built in"
[ ! -e "$F" ] || fail "list wrote settings.json"
run profile list --json
is "$(jf active)" null "no active profile"
is "$(jf profiles 0 name)" default "first profile"
is "$(jf profiles 0 active)" True "default is active"
is "$(jf profiles 3 name)" soonest-reset "fourth profile"
is "$(jf profiles 3 strategy)" soonest-reset "its strategy"
is "$(jf profiles 3 effective threshold)" 90.0 "effective threshold comes from the settings"
run profile show
has "$out" "name:       default" "show defaults to default"
run profile show sticky --json
is "$(jf profile builtin)" True "sticky is built in"
is "$(jf profile stored)" False "and not stored"
run profile show nope
code 1 "show unknown"
has "$err" "unknown profile 'nope'" "show unknown message"
run profile show nope --json
code 1 "show unknown json"
is "$(jf error type)" ConfigError "error envelope"

# ---- set: every other key survives ------------------------------------------------------------
mkdir -p "$B"
printf '%s' '{"schemaVersion": 1, "autoswitch": {"threshold": 80, "intervalSeconds": 120}, "zzz": {"keep": [1, 2]}, "profiles": {"old": {"strategy": "sticky", "note": "mine"}}}' > "$F"
run profile set night strategy drain-first
code 0 "set strategy"
has "$out" "profile night: strategy = drain-first" "set message"
run profile set night threshold 95
run profile set night models "Opus, fable"
run profile set night cooldown_s 60
run profile set night interval_s 30
is "$(sget zzz)" '{"keep": [1, 2]}' "unrelated key kept"
is "$(sget autoswitch threshold)" 80 "autoswitch block kept"
is "$(sget profiles old note)" mine "another profile's unknown key kept"
is "$(sget profiles night)" '{"strategy": "drain-first", "threshold": 95.0, "models": ["Opus", "fable"], "cooldown_s": 60.0, "interval_s": 30.0}' "stored profile"
[ "$(stat -c %a "$F" 2> /dev/null || stat -f %Lp "$F")" = 600 ] || fail "settings.json mode"
run profile set night note hi
code 1 "unknown key"
has "$err" "unknown profile key 'note'; valid keys: strategy, threshold, models, cooldown_s, interval_s" "unknown key message"
run profile set night threshold 120
code 1 "threshold range"
has "$err" "threshold must be between 50 and 99.9" "range message"
run profile set night strategy fastest
code 1 "bad strategy"
has "$err" "strategy must be one of: best, round-robin, soonest-reset, sticky, drain-first" "strategy message"
run profile set "bad name" strategy best
code 1 "bad name"
has "$err" "invalid profile name" "bad name message"
run profile set default threshold 80
code 1 "default is fixed"
has "$err" "'default' follows the autoswitch settings" "default message"
run profile set night threshold inherit
code 0 "inherit"
is "$(py 'import json,sys;print("threshold" in json.load(open(sys.argv[1]))["profiles"]["night"])' "$F")" False "inherit drops the key"
run profile set sticky threshold 70 --json
code 0 "override a built-in"
is "$(jf profile builtin)" True "still built in"
is "$(jf profile stored)" True "now stored"
is "$(jf profile strategy)" sticky "keeps the built-in strategy"
is "$(jf profile effective threshold)" 70.0 "override threshold"
is "$(jf profile effective interval_s)" 120 "interval inherited from the settings"

# ---- use / list / show --------------------------------------------------------------------------
run profile use nope
code 1 "use unknown"
run profile use night --json
code 0 "use"
is "$(jf activeProfile)" night "active profile"
is "$(sget active_profile)" night "stored"
run profile list
has "$out" "* night" "night marked active"
has "$out" "  default" "default no longer active"
run profile show
has "$out" "name:       night" "show follows the active profile"
has "$out" "strategy:   drain-first" "its strategy"
has "$out" "models:     Opus,fable" "its models"
has "$out" "threshold:  (80)" "inherited threshold shown in parentheses"
run profile list --json
is "$(jf active)" night "active in list"

# ---- remove --------------------------------------------------------------------------------------
run profile remove default
code 1 "remove default"
run profile remove round-robin
code 1 "remove built-in"
has "$err" "built in and has no stored override" "built-in message"
run profile remove nope
code 1 "remove unknown"
run profile remove night --json
code 0 "remove active"
is "$(jf removed)" night "removed"
is "$(jf activeProfile)" null "active cleared"
is "$(py 'import json,sys;d=json.load(open(sys.argv[1]));print("active_profile" in d, sorted(d["profiles"]))' "$F")" "False ['old', 'sticky']" "settings after remove"
run profile remove sticky
run profile remove old
is "$(py 'import json,sys;d=json.load(open(sys.argv[1]));print("profiles" in d, d["zzz"])' "$F")" "False {'keep': [1, 2]}" "empty profiles dropped, the rest kept"
run profile bogus
code 2 "bad action"
run profile set a b
code 2 "set arity"

# ---- three setup-token accounts, a live login on slot 1, a seeded cache ---------------------------
for t in a b c; do
  printf 'sk-ant-oat01-FAKE-%s\n' "$t" | "$cli" add-token - --email "$t@x.test" > /dev/null
done
login() { # live login = account $1 (a, b or c)
  printf '%s' "{\"claudeAiOauth\": {\"accessToken\": \"sk-ant-oat01-FAKE-$1\", \"scopes\": [\"user:inference\"]}}" > "$H/.claude/.credentials.json"
  printf '%s' "{\"numStartups\": 7, \"oauthAccount\": {\"emailAddress\": \"$1@x.test\", \"accountUuid\": \"\", \"organizationUuid\": null, \"organizationName\": null}}" > "$H/.claude.json"
  py 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["activeAccountNumber"]=int(sys.argv[2]);open(p,"w").write(json.dumps(d,indent=2))' "$B/sequence.json" "$2"
}
mkdir -p "$H/.claude"
# seed A5 B5 C5 B7 C7 BRESET CRESET: five-hour use of each account, the weekly use of b and c
# (a is 10), and when the weekly window of b and c resets (seconds from now)
seed() {
  py '
import json,sys,time,os
now=time.time()
a5,b5,c5,b7,c7,br,cr=[float(x) for x in sys.argv[2:9]]
def row(email,p5,p7,reset):
    g={"five_hour":{"pct":p5,"resets_at":time.strftime("%Y-%m-%dT%H:%M:%S+00:00",time.gmtime(now+7200)),"countdown":"2h","clock":"x"},
       "seven_day":{"pct":p7,"resets_at":time.strftime("%Y-%m-%dT%H:%M:%S+00:00",time.gmtime(now+reset)),"countdown":"2d","clock":"x"}}
    return {"email":email,"organizationUuid":"","lastGood":g,"fetchedAt":now-5,"lastAttemptAt":now-5,"claimId":None,"claimUntil":0.0,
            "consecutiveFailures":0,"lastError":None,"backoffUntil":None,"authDeadStrikes":0,"struckFingerprint":None,"rejectedFingerprint":None,
            "nextPollAt":now+3000,"pollIntervalS":180.0}
doc={"schemaVersion":2,"accounts":{"1":row("a@x.test",a5,10.0,200000),"2":row("b@x.test",b5,b7,br),"3":row("c@x.test",c5,c7,cr)}}
os.makedirs(sys.argv[1]+"/cache",exist_ok=True)
open(sys.argv[1]+"/cache/usage.json","w").write(json.dumps(doc,indent=2))
' "$B" "$@"
}
# a: 20 %. b: 60 % (headroom 40, weekly resets in 300000 s). c: 30 % (headroom 70, resets in 100000 s).
seed 20 60 30 40 10 300000 100000
login a 1
printf '%s' '{"schemaVersion": 1, "profiles": {"night": {"strategy": "round-robin"}}}' > "$F"

# ---- switch: no profile in play is the legacy rotation (next slot), byte for byte ----------------
run switch --json
code 0 "legacy rotation"
is "$(jf to number)" 2 "legacy rotation goes to the next slot"
is "$(jf strategy)" rotation "legacy strategy label"
login a 1

# ---- switch --profile ---------------------------------------------------------------------------
run switch --profile nope --json
code 1 "unknown --profile"
is "$(jf error type)" ConfigError "unknown --profile envelope"
run switch --profile
code 2 "--profile needs a value"
has "$err" "argument --profile: expected one argument" "usage message"
run switch 2 --profile round-robin
code 2 "--profile with a target"
run switch --profile round-robin --json
code 0 "round-robin"
is "$(jf to number)" 2 "round-robin goes to the next slot, not the roomiest"
is "$(jf profile)" round-robin "profile in the result"
is "$(jf strategy)" round-robin "strategy in the result"
login a 1
run switch --profile=sticky --json
is "$(jf to number)" 3 "sticky takes the most headroom"
login a 1
run switch --profile drain-first --json
is "$(jf to number)" 2 "drain-first takes the busiest account under the threshold"
login a 1
run switch --profile soonest-reset --json
is "$(jf to number)" 3 "soonest-reset takes the window that resets first"
login a 1
run switch --profile default --json
is "$(jf to number)" 2 "default is the legacy rotation"
login a 1
run switch --profile best --json
is "$(jf to number)" 3 "best takes the most headroom"
login a 1

# the active profile steers a bare switch; --profile beats it
run profile use night
run switch --json
is "$(jf to number)" 2 "active profile round-robin"
login a 1
run switch --profile sticky --json
is "$(jf to number)" 3 "--profile beats the active profile"
login a 1
run profile use default
run switch --json
is "$(jf to number)" 2 "default active: legacy rotation"
login a 1

# nothing moves while the active account's usage is unreadable; an exhausted or unreadable
# candidate is never the target
seed 100 100 100 10 10 300000 100000
run switch --profile round-robin --json
code 0 "all exhausted"
is "$(jf switched)" False "nothing to switch to"
is "$(jf reason)" all-exhausted "reason"
seed 20 100 30 40 10 300000 100000
run switch --profile round-robin --json
is "$(jf to number)" 3 "an exhausted account is skipped"
login a 1

# ---- auto: the decision events carry the profile and the strategy -------------------------------
seed 20 60 30 40 10 300000 100000
printf '%s' '{"schemaVersion": 1, "autoswitch": {"threshold": 85}}' > "$F"
run auto --once --json
code 2 "no profile"
is "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 2 "event count"
is "$(lf 1 reason)" below-threshold "reason"
is "$(py 'import json,sys;print("profile" in json.loads(sys.argv[1].split("\n")[1]))' "$out")" False "no profile field without a profile"
run auto --once --json --profile sticky
code 2 "--profile sticky"
is "$(lf 1 profile)" sticky "event profile"
is "$(lf 1 strategy)" sticky "event strategy"
is "$(lf 1 reason)" below-threshold "reason again"
run auto --once --json --profile nope
code 2 "unknown profile"
has "$err" "unknown profile 'nope'" "message"
run auto --once --json --profile
code 2 "profile needs a value"

# the profile's threshold replaces the settings'; the flag replaces the profile's
run profile set strict threshold 15
code 1 "range"
run profile set strict threshold 55
run auto --once --json --profile strict
is "$(lf 0 threshold)" 55.0 "profile threshold"
is "$(lf 1 profile)" strict "custom profile tagged"
is "$(lf 1 strategy)" best "a custom profile defaults to best"
run auto --once --json --profile strict --threshold 70
is "$(lf 0 threshold)" 70.0 "flag over profile"

# the active profile is used with no flag; a decision made under it is tagged, and a switch too
login a 1
seed 90 60 30 40 10 300000 100000
run profile set rr strategy round-robin
run profile set rr threshold 85
run profile use rr
run auto --once --json --dry-run
code 0 "round-robin switch"
is "$(lf 1 event)" switch "switch event"
is "$(lf 1 to number)" 2 "round-robin target"
is "$(lf 1 profile)" rr "switch tagged with the profile"
is "$(lf 1 strategy)" round-robin "switch tagged with the strategy"
run profile set rr strategy sticky
run auto --once --json --dry-run
is "$(lf 1 to number)" 3 "sticky target"
is "$(lf 1 strategy)" sticky "sticky tag"
run profile use default
run auto --once --json --dry-run
is "$(lf 1 to number)" 3 "default is best: the roomiest"
is "$(lf 1 profile)" default "default tagged"
is "$(lf 1 strategy)" best "default strategy"
# the daemon log names them too
tail -n 1 "$B/daemon.log" | py 'import json,sys;d=json.loads(sys.stdin.read());assert d["profile"]=="default" and d["strategy"]=="best",d' || fail "log line lacks the profile"

# ---- the loop reads the active profile again every tick -----------------------------------------
login a 1
seed 20 60 30 40 10 300000 100000
run profile use default
"$cli" auto --json --interval 15 --threshold 85 > "$H/loop.out" 2> "$H/loop.err" &
loop=$!
pids="$pids $loop"
n=0
until [ -s "$H/loop.out" ]; do
  n=$((n + 1))
  [ "$n" -le 100 ] || fail "the loop printed nothing"
  sleep 0.1
done
# tick one ran under the default profile (tagged `default`); switch the active profile
run profile use drain-first
n=0
until grep -q '"profile": "drain-first"' "$H/loop.out"; do
  n=$((n + 1))
  [ "$n" -le 400 ] || fail "the running loop never picked up the new profile: $(cat "$H/loop.out") $(cat "$H/loop.err")"
  sleep 0.1
done
grep -q '"profile": "default"' "$H/loop.out" || fail "the first tick was not tagged default"
grep -q '"strategy": "drain-first"' "$H/loop.out" || fail "second tick lacks the strategy"
kill "$loop"
wait "$loop" 2> /dev/null || true

echo "profile_it: ok"
