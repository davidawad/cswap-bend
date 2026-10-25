#!/bin/sh
# --format json|csv|yaml|toon|text end to end through the real CLI, on a scratch HOME with fake
# tokens and a seeded usage cache (no network): list, status, switch, config, profile, add/remove,
# import-usage, the `auto` event stream, and config/profile export and import in every format.
# Never touches the real ~/.claude*, ~/.claude-swap-backup.
set -eu
cli=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
H=$(mktemp -d "${TMPDIR:-/tmp}/cswap-formats-it.XXXXXX")
cleanup() { rm -rf "$H"; }
trap cleanup EXIT
export HOME="$H"
unset CLAUDE_CONFIG_DIR CSWAP_SWITCH_ORACLE_FILE CSWAP_STATE_DIR || true
export CSWAP_TEST_HTTP_BASE=http://127.0.0.1:1
export CSWAP_SWITCH_VERIFY_DELAY_MS=0
export NO_COLOR=1
B="$H/.claude-swap-backup"
F="$B/settings.json"

fail() {
  echo "formats_it: $*" >&2
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
lacks() { case "$1" in *"$2"*) fail "$3: has '$2': $1" ;; *) ;; esac }
# field of the JSON in $out: jf KEY KEY...
jf() { printf '%s\n' "$out" | py 'import json,sys
d=json.loads(sys.stdin.read())
for k in sys.argv[1:]:
    d=d[int(k)] if isinstance(d,list) else d[k]
print("null" if d is None else json.dumps(d) if isinstance(d,(dict,list)) else d)' "$@"; }
# the CSV in $out as JSON rows
csvrows() { printf '%s\n' "$out" | py 'import csv,io,json,sys
print(json.dumps(list(csv.reader(io.StringIO(sys.stdin.read(), newline="")))))'; }
# volatile keys (clocks and countdowns) dropped from a JSON text on stdin, sorted and compact
stable() { py 'import json,sys
V={"countdown","clock","usageAgeSeconds","expectedPct","aheadOfPace","projectedExhaustionAt","willLastToReset","usageRetryAt","ts"}
def clean(x):
    if isinstance(x,dict): return {k:clean(v) for k,v in x.items() if k not in V}
    if isinstance(x,list): return [clean(v) for v in x]
    return x
print(json.dumps(clean(json.loads(sys.stdin.read())),sort_keys=True))'; }
have_ruby=no
if command -v ruby > /dev/null 2>&1 && ruby -ryaml -rjson -e 'exit 0' 2> /dev/null; then have_ruby=yes; fi
# YAML text on stdin as JSON (Psych), when ruby is there; else the JSON text of the same command
yaml_json() { ruby -ryaml -rjson -e 'puts JSON.generate(YAML.safe_load(STDIN.read, permitted_classes: [], aliases: false))'; }

# ---- three setup-token accounts, a live login on slot 1, a seeded cache ---------------------------
mkdir -p "$H/.claude"
for t in a b c; do
  printf 'sk-ant-oat01-FAKE-%s\n' "$t" | "$cli" add-token - --email "$t@x.test" > /dev/null
done
printf '%s' '{"claudeAiOauth": {"accessToken": "sk-ant-oat01-FAKE-a", "scopes": ["user:inference"]}}' > "$H/.claude/.credentials.json"
printf '%s' '{"numStartups": 7, "oauthAccount": {"emailAddress": "a@x.test", "accountUuid": "", "organizationUuid": null, "organizationName": null}}' > "$H/.claude.json"
py 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["activeAccountNumber"]=1;open(p,"w").write(json.dumps(d,indent=2))' "$B/sequence.json"
seed() { # A5 B5 C5: five-hour use of a, b, c; the weekly use is 10, 30, 40
  py '
import json,sys,time,os
now=time.time()
a5,b5,c5=[float(x) for x in sys.argv[2:5]]
def row(email,p5,p7):
    g={"five_hour":{"pct":p5,"resets_at":time.strftime("%Y-%m-%dT%H:%M:%S+00:00",time.gmtime(now+7200)),"countdown":"2h","clock":"x"},
       "seven_day":{"pct":p7,"resets_at":time.strftime("%Y-%m-%dT%H:%M:%S+00:00",time.gmtime(now+200000)),"countdown":"2d","clock":"x"}}
    return {"email":email,"organizationUuid":"","lastGood":g,"fetchedAt":now-5,"lastAttemptAt":now-5,"claimId":None,"claimUntil":0.0,
            "consecutiveFailures":0,"lastError":None,"backoffUntil":None,"authDeadStrikes":0,"struckFingerprint":None,"rejectedFingerprint":None,
            "nextPollAt":now+3000,"pollIntervalS":180.0}
doc={"schemaVersion":2,"accounts":{"1":row("a@x.test",a5,10.0),"2":row("b@x.test",b5,30.0),"3":row("c@x.test",c5,40.0)}}
os.makedirs(sys.argv[1]+"/cache",exist_ok=True)
open(sys.argv[1]+"/cache/usage.json","w").write(json.dumps(doc,indent=2))
' "$B" "$@"
}
seed 20 60 30

# ---- --json is --format json ----------------------------------------------------------------------
run list --json
list_json=$out
run list --format json
is "$(printf '%s' "$out" | stable)" "$(printf '%s' "$list_json" | stable)" "list --format json equals list --json"
run config get autoswitch.threshold --json
want=$out
run config get autoswitch.threshold --format json
is "$out" "$want" "config get: byte-identical"
run --format json config get autoswitch.threshold
is "$out" "$want" "the flag may come first"
run status --json
want=$(printf '%s' "$out" | stable)
run status --format=json
is "$(printf '%s' "$out" | stable)" "$want" "status: --format=json"

# ---- list in every format ------------------------------------------------------------------------------
run list --format csv
code 0 "list csv"
rows=$(csvrows)
is "$(printf '%s' "$rows" | py 'import json,sys;r=json.load(sys.stdin);print(len(r), r[0])')" "4 ['slot', 'email', 'org', 'kind', 'active', '5h_pct', '5h_reset', '7d_pct', '7d_reset', 'fetched_at', 'error']" "csv header and row count"
is "$(printf '%s' "$rows" | py 'import json,sys;r=json.load(sys.stdin);print(r[1][:6], r[1][7], r[2][:6], r[3][5])')" "['1', 'a@x.test', '', 'ok', 'true', '20.0'] 10.0 ['2', 'b@x.test', '', 'ok', 'false', '60.0'] 30.0" "csv rows"
has "$(printf '%s' "$rows" | py 'import json,sys;print(json.load(sys.stdin)[1][6])')" "T" "csv reset is a timestamp"
run list --format yaml
code 0 "list yaml"
has "$out" "accounts:" "yaml accounts"
has "$out" "  - number: 1" "yaml first account"
has "$out" "    email: a@x.test" "yaml email"
if [ "$have_ruby" = yes ]; then
  is "$(printf '%s\n' "$out" | yaml_json | stable)" "$(printf '%s' "$list_json" | stable)" "list yaml parses to the list json (Psych)"
fi
run list --format toon
code 0 "list toon"
has "$out" "schemaVersion: 1" "toon header"
has "$out" "accounts[3]" "toon array length"
run list --format text
is "$out" "$(printf '%s' "$("$cli" list < /dev/null)")" "list --format text is the default"
run list --format xml
code 2 "bad format"
has "$err" "argument --format: invalid choice: 'xml' (choose from 'text', 'json', 'csv', 'yaml', 'toon')" "bad format message"
run list --format
code 2 "format needs a value"
has "$err" "argument --format: expected one argument" "format needs a value message"
run list --format csv --token-status
code 2 "csv with --token-status"

# ---- status ----------------------------------------------------------------------------------------------
run status --format csv
rows=$(csvrows)
is "$(printf '%s' "$rows" | py 'import json,sys;r=json.load(sys.stdin);print(len(r), r[1][:5])')" "2 ['1', 'a@x.test', '', 'ok', 'true']" "status csv: one row for the active account"
run status --format yaml
has "$out" "totalManagedAccounts: 3" "status yaml"
run status --format toon
has "$out" "totalManagedAccounts: 3" "status toon"

# ---- switch ------------------------------------------------------------------------------------------------
run switch 2 --format yaml
code 0 "switch yaml"
has "$out" "message:" "switch yaml message"
has "$out" "to:" "switch yaml target"
run switch 1 --format csv
code 0 "switch csv"
is "$(csvrows | py 'import json,sys;r=json.load(sys.stdin);print(r[0][:2], len(r))')" "['schemaVersion', 'switched'] 2" "switch csv is one wide row"
run switch 9 --format json
code 1 "switch unknown"
is "$(jf error type)" AccountNotFoundError "switch error envelope in json"
run switch 9 --format csv
code 1 "switch unknown csv"
has "$out" "schemaVersion,error.type,error.message" "error envelope as csv"

# ---- config -----------------------------------------------------------------------------------------------------
run config --format csv
is "$(printf '%s\n' "$out" | head -n 2)" "key,value,is_set
autoswitch.threshold,90.0,false" "config list csv"
run config get autoswitch.threshold --format yaml
is "$out" "schemaVersion: 1
key: autoswitch.threshold
value: 90.0
isSet: false" "config get yaml"
run config get autoswitch.threshold --format toon
is "$out" "schemaVersion: 1
key: autoswitch.threshold
value: 90
isSet: false" "config get toon (canonical number)"
run config set autoswitch.threshold 85 --format json
code 0 "config set json"
is "$(jf message)" "autoswitch.threshold = 85" "config set wraps its message"
run config set bogus 1 --format json
code 1 "config set error"
is "$(jf error type)" Error "error envelope"
has "$(jf error message)" "unknown setting" "its message"
is "$err" "" "nothing on stderr in json mode"
run config set autoswitch.threshold 85.5
code 0 "plain config set still text"
has "$out" "autoswitch.threshold = 85.5" "plain text"

# ---- profile ------------------------------------------------------------------------------------------------------
run profile set night strategy drain-first
run profile set night models "opus,sonnet"
run profile set night threshold 95
run profile list --format csv
is "$(csvrows | py 'import json,sys;r=json.load(sys.stdin);print(r[0]);print([x for x in r if x[0]=="night"])')" "['name', 'builtin', 'stored', 'active', 'strategy', 'threshold', 'models', 'cooldown_s', 'interval_s']
[['night', 'false', 'true', 'false', 'drain-first', '95.0', 'opus;sonnet', '300', '60']]" "profile list csv"
run profile show night --format yaml
has "$out" "strategy: drain-first" "profile show yaml"
run profile use night --format toon
has "$out" "activeProfile: night" "profile use toon"

# ---- add-token, remove, import-usage -------------------------------------------------------------------------
run add-token sk-ant-oat01-FAKE-d --email d@x.test --format json
code 0 "add-token json"
has "$(jf message)" "Added Account 4: d@x.test" "add-token message"
run add-token sk-ant-oat01-FAKE-z --email z@x.test --slot 1 --no-input
code 1 "occupied slot with --no-input"
run add-token - --no-input
code 1 "dash token with --no-input"
has "$err" "the token must be on the command line" "dash token message"
run remove 4 --no-input
code 1 "remove needs --yes under --no-input"
has "$err" "needs confirmation; pass --yes" "remove message"
run remove 4 --yes --format yaml
code 0 "remove --yes"
has "$out" "message: Removed Account-4" "remove yaml"
run list --json
printf '%s' "$out" > "$H/usage-export.json"
run import-usage "$H/usage-export.json" --format json
code 0 "import-usage json"
has "$(jf message)" "Kept slot" "import-usage keeps the newer own reading"

# ---- the auto event stream ---------------------------------------------------------------------------------------------
run profile use default
printf '%s' '{"schemaVersion": 1, "autoswitch": {"threshold": 85}}' > "$F"
seed 90 60 30
run auto --once --dry-run --json
json_events=$out
run auto --once --dry-run --format json
is "$(printf '%s\n' "$out" | while read -r l; do printf '%s' "$l" | stable; done)" "$(printf '%s\n' "$json_events" | while read -r l; do printf '%s' "$l" | stable; done)" "auto --format json equals --json"
run auto --once --dry-run --format csv
code 0 "auto csv"
rows=$(csvrows)
is "$(printf '%s' "$rows" | py 'import json,sys;r=json.load(sys.stdin);print(len(r), r[0][0], r[0][1], r[1][0], r[2][0], r[2][5:7])')" "3 event ts poll switch ['1', '3']" "auto csv: header, a poll row, a switch row"
run auto --once --dry-run --format yaml
code 0 "auto yaml"
is "$(printf '%s\n' "$out" | grep -c '^---$')" 2 "one --- per event"
has "$out" "event: switch" "yaml switch event"
if [ "$have_ruby" = yes ]; then
  is "$(printf '%s\n' "$out" | ruby -ryaml -rjson -e 'puts YAML.load_stream(STDIN.read).map { |d| d["event"] }.join(",")')" "poll,switch" "Psych reads the yaml stream"
fi
run auto --once --dry-run --format toon
code 0 "auto toon"
has "$out" "event: poll" "toon poll"
is "$(printf '%s\n' "$out" | grep -c '^$')" 1 "a blank line between toon documents"
run auto --once --dry-run --format text
has "$out" "would switch Account-1" "auto text is the human line"
run auto --once --format xml
code 2 "auto bad format"
has "$err" "argument --format: invalid choice: 'xml'" "auto bad format message"
run --format csv auto --once --dry-run
code 0 "auto with the flag first"
has "$out" "event,ts," "csv header"

# ---- config export / import ------------------------------------------------------------------------------------------------
printf '%s' '{"schemaVersion": 1, "autoswitch": {"threshold": 80.0, "future": [1, 2]}, "zzz": {"keep": true}, "profiles": {"old": {"strategy": "sticky", "note": "mine"}, "night": {"strategy": "drain-first", "models": ["opus", "sonnet"], "threshold": 95.0}}, "active_profile": "night"}' > "$F"
run config export
code 0 "export json"
is "$(printf '%s' "$out" | stable)" "$(py 'import json,sys;print(json.dumps(json.load(open(sys.argv[1])),sort_keys=True))' "$F")" "export is the file"
for f in json yaml toon csv; do
  run config export --format "$f"
  code 0 "export $f"
  printf '%s\n' "$out" > "$H/exp.$f"
done
if [ "$have_ruby" = yes ]; then
  is "$(yaml_json < "$H/exp.yaml" | stable)" "$(stable < "$H/exp.json")" "exported yaml parses to the exported json"
fi
is "$(head -n 1 "$H/exp.csv")" "key,value" "csv export header"
has "$(cat "$H/exp.csv")" "profiles.night.models,opus;sonnet" "csv export joins lists with ;"
# a fresh home takes each export back and ends up with the same settings
for f in json yaml toon csv; do
  H2=$(mktemp -d "${TMPDIR:-/tmp}/cswap-formats-it2.XXXXXX")
  rc=0
  HOME="$H2" "$cli" config import "$H/exp.$f" --json > "$H/imp.out" 2> "$H/imp.err" < /dev/null || rc=$?
  [ "$rc" = 0 ] || fail "import $f: exit $rc: $(cat "$H/imp.err")"
  is "$(py 'import json,sys;print(json.load(open(sys.argv[1]))["format"])' "$H/imp.out")" "$f" "import $f: format reported"
  got=$(py 'import json,sys;print(json.dumps(json.load(open(sys.argv[1])),sort_keys=True))' "$H2/.claude-swap-backup/settings.json")
  want=$(py 'import json,sys;d=json.load(open(sys.argv[1]));print(json.dumps(d,sort_keys=True))' "$F")
  if [ "$f" = csv ]; then
    # csv carries scalars: the list-valued unknown key autoswitch.future comes back as text
    got=$(printf '%s' "$got" | py 'import json,sys;d=json.load(sys.stdin);d["autoswitch"]["future"]=[1,2];print(json.dumps(d,sort_keys=True))')
  fi
  is "$got" "$want" "import $f round trip"
  [ "$(stat -c %a "$H2/.claude-swap-backup/settings.json" 2> /dev/null || stat -f %Lp "$H2/.claude-swap-backup/settings.json")" = 600 ] || fail "settings.json mode after import $f"
  rm -rf "$H2"
done
# extension and --format
cp "$H/exp.yaml" "$H/by-ext.yml"
run config import "$H/by-ext.yml"
code 0 "import by extension"
has "$out" "as yaml" "yaml from .yml"
cp "$H/exp.json" "$H/noext"
run config import "$H/noext"
code 1 "unknown extension"
has "$err" "cannot tell the format of" "unknown extension message"
run config import "$H/noext" --format json
code 0 "explicit format"
run config import "$H/noext" --format xml
code 1 "bad explicit format"
run config import
code 2 "import needs a file"
run config import "$H/nonexistent.json"
code 1 "missing file"
has "$err" "could not read" "missing file message"
run config import - --no-input --format json
code 1 "stdin forbidden"
has "$err" "standard input is not available" "stdin message"
# stdin
rc=0
out=$(printf '{"autoswitch": {"cooldownSeconds": 120}}' | "$cli" config import - --format json 2> "$H/stderr") || rc=$?
code 0 "import from stdin"
is "$(py 'import json,sys;print(json.load(open(sys.argv[1]))["autoswitch"]["cooldownSeconds"])' "$F")" 120.0 "stdin value written"
is "$(py 'import json,sys;d=json.load(open(sys.argv[1]));print(d["zzz"], d["autoswitch"]["future"], d["autoswitch"]["threshold"])' "$F")" "{'keep': True} [1, 2] 80.0" "merge keeps unknown and unmentioned keys"
# validation: one bad value and nothing is written
before=$(py 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$F")
printf 'autoswitch:\n  threshold: 75\n  strategy: nope\n' > "$H/bad.yaml"
run config import "$H/bad.yaml"
code 1 "bad value"
has "$err" "autoswitch.strategy must be one of" "same message as config set"
is "$(py 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$F")" "$before" "nothing written on a bad value"
printf 'profiles:\n  x:\n    threshold: 5\n' > "$H/bad2.yaml"
run config import "$H/bad2.yaml"
code 1 "bad profile value"
has "$err" "threshold must be between 50 and 99.9" "profile range message"
printf 'active_profile: ghost\n' > "$H/bad3.yaml"
run config import "$H/bad3.yaml"
code 1 "unknown active profile"
has "$err" "active_profile 'ghost' names no profile" "active profile message"
printf 'key,value\nautoswitch.threshold,abc\n' > "$H/bad.csv"
run config import "$H/bad.csv"
code 1 "bad csv value"
# null unsets; --replace replaces
printf 'autoswitch:\n  cooldownSeconds: null\nzzz: null\n' > "$H/unset.yaml"
run config import "$H/unset.yaml"
code 0 "null unsets"
is "$(py 'import json,sys;d=json.load(open(sys.argv[1]));print("cooldownSeconds" in d["autoswitch"], "zzz" in d)' "$F")" "False False" "unset keys are gone"
printf 'autoswitch:\n  threshold: 66\n' > "$H/only.yaml"
run config import "$H/only.yaml" --replace
code 0 "replace"
is "$(py 'import json,sys;d=json.load(open(sys.argv[1]));print(sorted(d))' "$F")" "['autoswitch', 'schemaVersion']" "replace drops what the document lacks"

# ---- profile export / import ----------------------------------------------------------------------------------------------
printf '%s' '{"schemaVersion": 1, "autoswitch": {"threshold": 80}, "zzz": 1, "profiles": {"night": {"strategy": "drain-first", "threshold": 95.0}, "old": {"strategy": "sticky", "note": "mine"}}, "active_profile": "night"}' > "$F"
run profile export night
code 0 "profile export one"
is "$(printf '%s' "$out" | stable)" '{"profiles": {"night": {"strategy": "drain-first", "threshold": 95.0}}}' "one profile"
run profile export --format yaml
has "$out" "active_profile: night" "all profiles as yaml"
printf '%s\n' "$out" > "$H/prof.yaml"
run profile export sticky
code 1 "export a built-in"
run profile export nope
code 1 "export unknown"
printf 'profiles:\n  day:\n    strategy: round-robin\n    threshold: 60\n  night:\n    cooldown_s: 30\n' > "$H/day.yaml"
run profile import "$H/day.yaml"
code 0 "profile import"
is "$(py 'import json,sys;d=json.load(open(sys.argv[1]));print(d["profiles"]["day"], d["profiles"]["night"], d["zzz"])' "$F")" "{'strategy': 'round-robin', 'threshold': 60.0} {'strategy': 'drain-first', 'threshold': 95.0, 'cooldown_s': 30.0} 1" "profiles merged per key, the rest kept"
run profile import "$H/prof.yaml"
code 0 "re-import the export"
run profile import "$H/exp.json"
code 1 "profile import refuses settings keys"
has "$err" "profile import takes profiles and active_profile only" "message"
printf 'profiles:\n  default:\n    strategy: best\n' > "$H/def.yaml"
run profile import "$H/def.yaml"
code 1 "default cannot be imported"

# ---- help names the new options -----------------------------------------------------------------------------------------------------
run help
has "$out" "--format FORMAT" "help: --format"
has "$out" "cswap config import FILE|-" "help: config import"
has "$out" "--no-input" "help: --no-input"
echo "formats_it: ok"
