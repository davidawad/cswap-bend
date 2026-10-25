set shell := ["sh", "-eu", "-c"]

bend := env_var_or_default("BEND", "bend")
blr_dir := env_var_or_default("BLR_DIR", justfile_directory() + "/../bend-lint-rules")

# List the recipes.
default:
    @just --list

# Fail unless `bend version` matches .bend-version.
check-versions:
    test "$({{ bend }} version)" = "$(cat .bend-version)" || { echo "bend version mismatch: want $(cat .bend-version), have $({{ bend }} version)" >&2; exit 1; }

# Type-check every source file and run every ground-equation test.
# Type-check every module and ground-test file, CI_JOBS (default 6) at a time.
check:
    printf '%s\n' src/*.bend src/daemon/*.bend src/fmt/*.bend tests/*_test.bend | xargs -P "${CI_JOBS:-6}" -I{} sh -c 'sh scripts/check-file "$1" "$2" || { echo "FAIL $2" >&2; exit 1; }' _ "{{ bend }}" {}
    @echo "check: ok"

# Prove LAWS.bend, then recheck with the Lean-proven kernel.
laws:
    {{ bend }} PROOF.bend
    if command -v lean >/dev/null || [ -d "$HOME/.elan/toolchains" ]; then {{ bend }} PROOF.bend --verdict; else echo "gate_skipped:lean (bend --verdict needs Lean v4.34.0 via elan)" >&2; fi

# bend-lint on every module under src/ (including the subdirectories), CI_JOBS (default 6) at a time, with the bend-lint-rules pack (dead code, complexity, fan-in/out, file length). Each module is linted as its own entry, as a library (bend-lint.json makes every def an entry); findings are errors.
lint:
    if [ -d "{{ blr_dir }}/upstream/bend" ]; then (cd "{{ blr_dir }}" && cargo build --quiet) && printf '%s\n' src/*.bend src/*/*.bend | xargs -P "${CI_JOBS:-6}" -I{} sh -c 'cd "$1" && target/debug/blr lint "$2/$3" || { echo "FAIL lint $3" >&2; exit 1; }' _ "{{ blr_dir }}" "$PWD" {}; else echo "gate_skipped:blr (run just setup in {{ blr_dir }})" >&2; fi

# Native binary at bin/cswap-bend.
build:
    mkdir -p bin
    {{ bend }} src/main.bend -o bin/cswap-bend

# Integration tests: each tests/*_it.sh runs against bin/cswap-bend.
it: build
    for t in tests/*_it.sh; do [ -e "$t" ] || continue; sh "$t" bin/cswap-bend || { echo "FAIL $t" >&2; exit 1; }; done
    @echo "it: ok"

# Everything CI runs.
ci: check-versions check laws lint it parity-bend

# Replay the parity fixtures against a cswap-compatible CLI: `just parity` or `just parity CLI=/path/to/cswap` (default: the installed Python reference). Not part of ci: the Bend CLI does not exist yet.
parity CLI=(env_var("HOME") + "/.local/bin/cswap"):
    cli="{{ CLI }}"; nice -n 19 python3 -I parity/replay "${cli#CLI=}"

# Fixtures the Bend CLI passes so far (grow this list as auto and the rest land).
bend_fixtures := "01-list-empty,02-status-empty,03-add-token-setup,04-add-token-default-email-slot,05-add-token-api-key,06-add-current-login,07-list-six-fresh,08-list-six-stale-fetch,09-list-fetch-errors,10-status-managed,11-switch-to-setup-token,12-switch-back-to-full,13-switch-rotate,14-switch-best,15-switch-best-model,16-switch-best-stay,17-switch-already-active,18-switch-errors,19-remove,20-import-usage-hold,21-auto-below-threshold,22-auto-proactive-best,23-auto-unknown-headroom,24-auto-cooldown,25-auto-at-limit-ignores-cooldown,26-auto-all-exhausted,27-auto-model-binding,28-auto-dry-run,29-auto-no-candidates,30-auto-unmanaged-active,31-auto-settings-file,32-config,33-auto-hysteresis-blocks"

# Replay exactly those fixtures against bin/cswap-bend.
parity-bend: build
    nice -n 19 python3 -I parity/replay bin/cswap-bend --only {{ bend_fixtures }}
