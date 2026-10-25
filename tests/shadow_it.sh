#!/bin/sh
# scripts/shadow-compare on synthetic logs: pairing within the interval,
# agreement, a divergent event, a divergent target, unpaired ticks, the
# lines it must ignore, and exit 0 whatever it is given.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
d=$(mktemp -d "${TMPDIR:-/tmp}/cswap-shadow-it.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() {
  echo "shadow_it: $*" >&2
  exit 1
}
cmp_() { python3 -I "$root/scripts/shadow-compare" "$@"; }

cat > "$d/py.log" << 'PYEOF'
2026-10-23T10:00:00Z loop-start cswap=/x
2026-10-23T10:00:05Z {"schemaVersion": 1, "event": "poll", "ts": "2026-10-23T10:00:05Z", "active": {"number": 1, "email": "a@x.test"}, "headroomPct": {"1": 40.0, "2": 90.0, "3": null}, "threshold": 85.0}
2026-10-23T10:00:05Z {"schemaVersion": 1, "event": "no-switch", "ts": "2026-10-23T10:00:05Z", "reason": "below-threshold"}
agent-pick: noise line
2026-10-23T10:05:05Z {"schemaVersion": 1, "event": "poll", "ts": "2026-10-23T10:05:05Z", "active": {"number": 1, "email": "a@x.test"}, "headroomPct": {"1": 10.0, "2": 90.0, "3": 70.0}, "threshold": 85.0}
2026-10-23T10:05:06Z {"schemaVersion": 1, "event": "switch", "ts": "2026-10-23T10:05:06Z", "trigger": "proactive", "from": {"number": 1, "email": "a@x.test"}, "to": {"number": 2, "email": "b@x.test"}, "dryRun": false}
2026-10-23T10:10:05Z {"schemaVersion": 1, "event": "poll", "ts": "2026-10-23T10:10:05Z", "active": {"number": 2, "email": "b@x.test"}, "headroomPct": {"1": 10.0, "2": 5.0, "3": 70.0}, "threshold": 85.0}
2026-10-23T10:10:06Z {"schemaVersion": 1, "event": "switch", "ts": "2026-10-23T10:10:06Z", "trigger": "failover", "from": {"number": 2}, "to": {"number": 3}, "dryRun": false}
2026-10-23T10:15:05Z {"schemaVersion": 1, "event": "poll", "ts": "2026-10-23T10:15:05Z", "active": {"number": 3}, "headroomPct": {"1": 10.0, "3": 60.0}, "threshold": 85.0}
2026-10-23T10:15:05Z {"schemaVersion": 1, "event": "no-switch", "ts": "2026-10-23T10:15:05Z", "reason": "below-threshold"}
2026-10-23T10:20:05Z not json {
PYEOF

cat > "$d/bend.jsonl" << 'BEOF'
{"ts":"2026-10-23T10:00:30Z","active":1,"event":"no-switch","reason":"below-threshold","trigger":null,"from":null,"to":null,"accounts":[{"number":1,"headroomPct":40.0},{"number":2,"headroomPct":90.0}],"events":[]}
{"ts":"2026-10-23T10:05:40Z","active":{"number":1,"email":"a@x.test"},"event":"no-switch","reason":"cooldown","accounts":{"1":10.0,"2":90.0,"3":70.0}}
{"ts":"2026-10-23T10:10:40Z","active":2,"event":"switch","trigger":"failover","from":2,"to":1,"accounts":{"1":{"headroomPct":10.0},"2":{"headroomPct":5.0}}}
{"ts":"2026-10-23T10:15:20Z","active":3,"event":"no-switch","reason":"below-threshold","accounts":[]}
{"ts":"2026-10-23T11:00:00Z","active":3,"event":"no-switch","reason":"below-threshold","accounts":[]}
BEOF

cmp_ "$d/py.log" "$d/bend.jsonl" --json > "$d/out.json"
python3 -I - "$d/out.json" << 'PYEOF' || fail "summary wrong"
import json, sys
r = json.load(open(sys.argv[1]))
assert r["paired"] == 4, r["paired"]
assert r["agreed"] == 2, r["agreed"]
assert abs(r["agreement"] - 0.5) < 1e-9
kinds = [x["divergence"] for x in r["divergences"]]
assert kinds == ["event", "target"], kinds
ev, tg = r["divergences"]
assert ev["python"]["event"] == "switch" and ev["python"]["to"] == 2
assert ev["bend"]["event"] == "no-switch" and ev["bend"]["reason"] == "cooldown"
assert ev["python"]["headroom"]["3"] == 70.0 and ev["bend"]["headroom"]["3"] == 70.0
assert tg["python"]["to"] == 3 and tg["bend"]["to"] == 1
assert tg["python"]["headroom"]["2"] == 5.0 and tg["bend"]["headroom"]["2"] == 5.0
assert len(r["unpaired_bend"]) == 1 and r["unpaired_bend"][0]["ts"] == "2026-10-23T11:00:00Z"
assert r["pairs"][0]["dt"] == 25.0
PYEOF

# The text report names the divergences and both sides' headroom.
cmp_ "$d/py.log" "$d/bend.jsonl" > "$d/out.txt"
grep -q "4 paired tick(s), 2 agree" "$d/out.txt" || fail "text summary"
grep -q "agreement: 50.0%" "$d/out.txt" || fail "text agreement"
grep -q "event at py 2026-10-23T10:05:05Z" "$d/out.txt" || fail "event divergence missing"
grep -q "target at py 2026-10-23T10:10:05Z" "$d/out.txt" || fail "target divergence missing"
grep -q "headroom: 1=10 2=90 3=70" "$d/out.txt" || fail "headroom missing"

# A narrow window pairs nothing.
cmp_ "$d/py.log" "$d/bend.jsonl" --interval 1 --json > "$d/narrow.json"
python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); assert r["paired"]==0 and r["agreement"] is None' "$d/narrow.json" || fail "narrow window"

# A missing log is reported, and the exit is still 0.
cmp_ "$d/nope.log" "$d/bend.jsonl" > "$d/missing.txt" 2>&1 || fail "missing log exited nonzero"
grep -q "cannot read" "$d/missing.txt" || fail "missing log not reported"
: > "$d/empty"
cmp_ "$d/empty" "$d/empty" > /dev/null || fail "empty logs exited nonzero"

# install-shadow: a dry run prints the steps and the rendered LaunchAgent with
# the live poller's settings, and creates nothing.
mkdir -p "$d/home/.config/cswap-legacy"
cat > "$d/home/.config/cswap-legacy/com.david.cswap-auto.plist" << 'PLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>EnvironmentVariables</key><dict>
<key>CSWAP_AUTO_THRESHOLD</key><string>77</string>
<key>CSWAP_AUTO_MODEL</key><string>Alpha,Beta</string>
<key>CSWAP_AUTO_INTERVAL</key><string>120</string>
</dict></dict></plist>
PLEOF
before=$(find "$d/home" | sort)
SHADOW_HOME="$d/home" SHADOW_SHA=abc1234 sh "$root/deploy/install-shadow" > "$d/dry.txt" || fail "dry run failed"
[ "$before" = "$(find "$d/home" | sort)" ] || fail "dry run created files"
grep -q "DRY RUN" "$d/dry.txt" || fail "dry run banner"
grep -q "interval=120 threshold=77 models=Alpha,Beta strategy=best" "$d/dry.txt" || fail "settings not read from the poller plist"
grep -q "<string>--shadow</string>" "$d/dry.txt" || fail "plist lacks --shadow"
grep -q "$d/home/.local/share/cswap-bend/abc1234/cswap-bend" "$d/dry.txt" || fail "binary path"
grep -q "shadow.jsonl" "$d/dry.txt" || fail "shadow log path"
! grep -q "@[A-Z_]*@" "$d/dry.txt" || fail "unrendered placeholder"
SHADOW_HOME="$d/home" SHADOW_SHA=abc1234 sh "$root/deploy/install-shadow" --uninstall > "$d/un.txt" || fail "uninstall dry run failed"
grep -q "DRY RUN" "$d/un.txt" || fail "uninstall banner"
[ "$before" = "$(find "$d/home" | sort)" ] || fail "uninstall dry run changed files"

echo "shadow_it: ok"
