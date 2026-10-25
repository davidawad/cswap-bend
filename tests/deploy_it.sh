#!/bin/sh
# deploy/install-live on a fake HOME: the --report speed bump, the dry run
# (prints every step, changes nothing), a live run and an uninstall against the
# fake HOME with launchctl switched off, and the rendered LaunchAgent.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
d=$(mktemp -d "${TMPDIR:-/tmp}/cswap-deploy-it.XXXXXX")
trap 'rm -rf "$d"' EXIT
fail() {
  echo "deploy_it: $*" >&2
  exit 1
}
home=$d/home
mkdir -p "$home/.config/cswap-legacy" "$home/Library/LaunchAgents"
cat > "$home/.config/cswap-legacy/com.david.cswap-auto.plist" << 'PLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>EnvironmentVariables</key><dict>
<key>CSWAP_AUTO_THRESHOLD</key><string>77</string>
<key>CSWAP_AUTO_MODEL</key><string>Alpha,Beta</string>
<key>CSWAP_AUTO_INTERVAL</key><string>120</string>
<key>CSWAP_AUTO_STRATEGY</key><string>next-available</string>
</dict></dict></plist>
PLEOF
printf 'shadow-compare: 4 paired tick(s), 4 agree\n' > "$d/report.txt"
: > "$d/empty.txt"
printf 'poller\n' > "$home/Library/LaunchAgents/com.david.cswap-auto.plist"
printf 'shadow\n' > "$home/Library/LaunchAgents/com.david.cswap-bend-shadow.plist"
printf '#!/bin/sh\necho bend\n' > "$d/fake-bend"
chmod 755 "$d/fake-bend"
printf '#!/bin/sh\necho restored > "%s/restored"\n' "$d" > "$d/fake-install"
chmod 755 "$d/fake-install"

env_() { SHADOW_HOME=$home SHADOW_SHA=abc1234 SHADOW_NO_LAUNCHCTL=1 LIVE_BIN=$d/fake-bend LIVE_RESTORE_INSTALL=$d/fake-install "$@"; }
snap() { find "$home" -type f | sort | xargs cat | cksum; }
before=$(snap)

# The speed bump: no report, a missing report and an empty report all refuse,
# even on a dry run, and change nothing.
rc=0
env_ sh "$root/deploy/install-live" > "$d/o1.txt" 2> "$d/e1.txt" || rc=$?
[ "$rc" = 1 ] || fail "no --report exited $rc, want 1"
grep -q "refused: pass --report" "$d/e1.txt" || fail "no --report message"
rc=0
env_ sh "$root/deploy/install-live" --report "$d/nope.txt" > /dev/null 2> "$d/e2.txt" || rc=$?
[ "$rc" = 1 ] || fail "missing report exited $rc"
grep -q "missing or empty" "$d/e2.txt" || fail "missing report message"
rc=0
env_ sh "$root/deploy/install-live" --report "$d/empty.txt" > /dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "empty report exited $rc"
[ "$(snap)" = "$before" ] || fail "a refusal changed files"

# A dry run prints every step and changes nothing.
env_ sh "$root/deploy/install-live" --report "$d/report.txt" > "$d/dry.txt" || fail "dry run failed"
[ "$(snap)" = "$before" ] || fail "dry run changed files"
[ ! -e "$home/.local" ] || fail "dry run created directories"
grep -q "DRY RUN" "$d/dry.txt" || fail "dry run banner"
grep -q "interval=120 threshold=77 models=Alpha,Beta strategy=next-available" "$d/dry.txt" || fail "settings not read from the poller plist"
grep -q "launchctl bootout gui/.*/com.david.cswap-auto" "$d/dry.txt" || fail "does not stop the Python job"
grep -q "com.david.cswap-bend-shadow" "$d/dry.txt" || fail "does not unload the shadow job"
grep -q "<string>auto</string>" "$d/dry.txt" || fail "plist lacks auto"
! grep -q -- "--shadow" "$d/dry.txt" || fail "live plist must not carry --shadow"
! grep -q "@[A-Z_]*@" "$d/dry.txt" || fail "unrendered placeholder"
grep -q "install-live --uninstall --live" "$d/dry.txt" || fail "no undo line"

# An uninstall dry run names the restore step and changes nothing.
env_ sh "$root/deploy/install-live" --uninstall > "$d/undry.txt" || fail "uninstall dry run failed"
grep -q "run $d/fake-install" "$d/undry.txt" || fail "uninstall does not name the restore step"
[ "$(snap)" = "$before" ] || fail "uninstall dry run changed files"
[ ! -e "$d/restored" ] || fail "uninstall dry run ran the installer"

# A live run (fake HOME, launchctl off): binary copied, agent written, shadow
# agent removed, the Python agent file kept.
env_ sh "$root/deploy/install-live" --report "$d/report.txt" --live > "$d/live.txt" || fail "live run failed"
[ -x "$home/.local/share/cswap-bend/abc1234/cswap-bend" ] || fail "binary not installed"
[ -s "$home/Library/LaunchAgents/com.david.cswap-bend.plist" ] || fail "agent not written"
[ ! -e "$home/Library/LaunchAgents/com.david.cswap-bend-shadow.plist" ] || fail "shadow agent not removed"
[ -e "$home/Library/LaunchAgents/com.david.cswap-auto.plist" ] || fail "Python agent file was removed"
python3 -I -c 'import plistlib,sys; p=plistlib.load(open(sys.argv[1],"rb")); a=p["ProgramArguments"]; assert a[1]=="auto" and "--shadow" not in a, a; assert a[a.index("--model")+1]=="Alpha,Beta"' "$home/Library/LaunchAgents/com.david.cswap-bend.plist" || fail "agent plist wrong"
grep -q "launchctl bootout gui/.*/com.david.cswap-auto skipped" "$d/live.txt" || fail "Python job not unloaded"
grep -q "bootstrap" "$d/live.txt" || fail "agent not loaded"

# Uninstall: the agent goes, the installer restores the Python poller.
env_ sh "$root/deploy/install-live" --uninstall --live > /dev/null || fail "uninstall failed"
[ ! -e "$home/Library/LaunchAgents/com.david.cswap-bend.plist" ] || fail "agent not removed"
[ -e "$d/restored" ] || fail "installer not run"
[ -x "$home/.local/share/cswap-bend/abc1234/cswap-bend" ] || fail "uninstall removed the binary"

# Uninstall with no installer: the Python poller still comes back from its kept
# agent file, and the run exits 1 so the missing installer is noticed.
rc=0
SHADOW_HOME=$home SHADOW_SHA=abc1234 SHADOW_NO_LAUNCHCTL=1 LIVE_RESTORE_INSTALL=$d/missing sh "$root/deploy/install-live" --uninstall --live > /dev/null 2> "$d/e3.txt" || rc=$?
[ "$rc" = 1 ] || fail "missing installer exited $rc"
grep -q "missing or not executable; Python poller restored" "$d/e3.txt" || fail "missing installer message: $(cat "$d/e3.txt")"

# ---- a launchctl that can fail: the Python poller must always come back ----
# The stub keeps the loaded labels in $d/loaded and logs every call.
cat > "$d/fake-launchctl" << 'LCEOF'
#!/bin/sh
echo "$*" >> "$LC_DIR/calls"
case "$1" in
  bootstrap)
    label=$(basename "$3" .plist)
    if [ "$label" = com.david.cswap-bend ] && [ "${LC_FAIL_BEND:-0}" = 1 ]; then exit 1; fi
    if [ "$label" = com.david.cswap-auto ] && [ "${LC_FAIL_PYTHON:-0}" = 1 ]; then exit 1; fi
    echo "$label" >> "$LC_DIR/loaded"
    ;;
  bootout)
    label=${2##*/}
    grep -v "^$label\$" "$LC_DIR/loaded" > "$LC_DIR/loaded.new" || true
    mv "$LC_DIR/loaded.new" "$LC_DIR/loaded"
    ;;
  list)
    while read -r l; do
      if [ "$l" = com.david.cswap-bend ] && [ "${LC_HIDE_BEND:-0}" = 1 ]; then continue; fi
      printf '123\t0\t%s\n' "$l"
    done < "$LC_DIR/loaded"
    ;;
esac
LCEOF
chmod 755 "$d/fake-launchctl"
lc_env() { LC_DIR=$d SHADOW_HOME=$home SHADOW_SHA=abc1234 SHADOW_LAUNCHCTL=$d/fake-launchctl LIVE_BIN=$d/fake-bend LIVE_RESTORE_INSTALL=$d/fake-install "$@"; }
reset_lc() { printf 'com.david.cswap-auto\ncom.david.cswap-bend-shadow\n' > "$d/loaded"; : > "$d/calls"; }
printf 'poller\n' > "$home/Library/LaunchAgents/com.david.cswap-auto.plist"

# A good flip: the Bend job is loaded and listed, the Python and shadow jobs are not.
reset_lc
lc_env sh "$root/deploy/install-live" --report "$d/report.txt" --live > "$d/lc-ok.txt" 2>&1 || fail "good flip failed: $(cat "$d/lc-ok.txt")"
grep -qx com.david.cswap-bend "$d/loaded" || fail "Bend job not loaded"
! grep -qx com.david.cswap-auto "$d/loaded" || fail "Python job still loaded after a good flip"
! grep -qx com.david.cswap-bend-shadow "$d/loaded" || fail "shadow job still loaded"

# The Bend load fails: the run rolls the Python job back itself and exits 1.
reset_lc
rc=0
LC_FAIL_BEND=1 lc_env sh "$root/deploy/install-live" --report "$d/report.txt" --live > /dev/null 2> "$d/lc-fail.txt" || rc=$?
[ "$rc" = 1 ] || fail "failed load exited $rc, want 1"
grep -q "Bend load failed" "$d/lc-fail.txt" || fail "no failure message"
grep -q "Python poller restored" "$d/lc-fail.txt" || fail "no restore message: $(cat "$d/lc-fail.txt")"
grep -qx com.david.cswap-auto "$d/loaded" || fail "Python job not re-bootstrapped"
! grep -qx com.david.cswap-bend "$d/loaded" || fail "Bend job left loaded"
grep -q "bootstrap gui/[0-9]* $home/Library/LaunchAgents/com.david.cswap-auto.plist" "$d/calls" || fail "the Python agent file was not bootstrapped"

# The Bend job loads but launchctl does not list it: same rollback.
reset_lc
rc=0
LC_HIDE_BEND=1 lc_env sh "$root/deploy/install-live" --report "$d/report.txt" --live > /dev/null 2> "$d/lc-hide.txt" || rc=$?
[ "$rc" = 1 ] || fail "unlisted job exited $rc"
grep -q "not listed" "$d/lc-hide.txt" || fail "unlisted message"
grep -q "Python poller restored" "$d/lc-hide.txt" || fail "no restore after an unlisted job"
grep -qx com.david.cswap-auto "$d/loaded" || fail "Python job missing after an unlisted job"
! grep -qx com.david.cswap-bend "$d/loaded" || fail "Bend job left loaded after being unlisted"

# The restore itself fails: say so, still exit 1.
reset_lc
rc=0
LC_FAIL_BEND=1 LC_FAIL_PYTHON=1 lc_env sh "$root/deploy/install-live" --report "$d/report.txt" --live > /dev/null 2> "$d/lc-both.txt" || rc=$?
[ "$rc" = 1 ] || fail "double failure exited $rc"
grep -q "NOT restored: launchctl bootstrap of com.david.cswap-auto failed" "$d/lc-both.txt" || fail "NOT restored message: $(cat "$d/lc-both.txt")"

# The Python agent file is gone: NOT restored, with the reason.
reset_lc
mv "$home/Library/LaunchAgents/com.david.cswap-auto.plist" "$d/auto.plist.saved"
rc=0
LC_FAIL_BEND=1 lc_env sh "$root/deploy/install-live" --report "$d/report.txt" --live > /dev/null 2> "$d/lc-nofile.txt" || rc=$?
mv "$d/auto.plist.saved" "$home/Library/LaunchAgents/com.david.cswap-auto.plist"
[ "$rc" = 1 ] || fail "missing agent file exited $rc"
grep -q "NOT restored: the agent file .* is missing" "$d/lc-nofile.txt" || fail "missing agent message: $(cat "$d/lc-nofile.txt")"

# Uninstall whose installer fails: the poller is loaded from its agent file.
reset_lc
printf 'com.david.cswap-bend\n' > "$d/loaded"
printf '#!/bin/sh\nexit 3\n' > "$d/bad-install"
chmod 755 "$d/bad-install"
rc=0
LC_DIR=$d SHADOW_HOME=$home SHADOW_SHA=abc1234 SHADOW_LAUNCHCTL=$d/fake-launchctl LIVE_RESTORE_INSTALL=$d/bad-install sh "$root/deploy/install-live" --uninstall --live > /dev/null 2> "$d/lc-bad.txt" || rc=$?
[ "$rc" = 1 ] || fail "failing installer exited $rc"
grep -q "failed; Python poller restored" "$d/lc-bad.txt" || fail "failing installer message: $(cat "$d/lc-bad.txt")"
grep -qx com.david.cswap-auto "$d/loaded" || fail "Python job not loaded after a failing installer"
! grep -qx com.david.cswap-bend "$d/loaded" || fail "Bend job left loaded after uninstall"

# A refusal (no report) never stops anything.
reset_lc
rc=0
lc_env sh "$root/deploy/install-live" --live > /dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "no-report live run exited $rc"
grep -qx com.david.cswap-auto "$d/loaded" || fail "a refused run unloaded the Python job"
[ ! -s "$d/calls" ] || fail "a refused run called launchctl"

echo "deploy_it: ok"
