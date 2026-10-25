#!/bin/sh
# fs against a real directory: mkdir_p, write_atomic (mode, replace, no
# leftovers), read_file, exists, list_dir, remove. Fake data only.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
BEND=${BEND:-bend}
mkdir -p "$root/bin"
nice -n 19 "$BEND" "$here/it/fs_main.bend" -o "$root/bin/fs-it" > /dev/null
it="$root/bin/fs-it"
d=$(mktemp -d "${TMPDIR:-/tmp}/cswap-fs-it.XXXXXX")
trap 'rm -rf "$d"' EXIT

fail() {
  echo "fs_it: $*" >&2
  exit 1
}
mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

"$it" mkdir "$d/a/b/c" > /dev/null
[ -d "$d/a/b/c" ] || fail "mkdir_p did not create nested dirs"
"$it" mkdir "$d/a/b/c" > /dev/null || fail "mkdir_p on an existing dir must succeed"

[ "$("$it" exists "$d/a")" = yes ] || fail "exists: dir"
[ "$("$it" exists "$d/nope")" = no ] || fail "exists: missing"

f="$d/a/creds.enc"
data=$(printf 'secret \303\251 \342\202\254 "quoted" \\ back')
"$it" write "$f" "$data" 600 > /dev/null || fail "write_atomic failed"
[ "$(mode "$f")" = 600 ] || fail "mode is $(mode "$f"), want 600"
[ "$("$it" read "$f")" = "$data" ] || fail "read does not match what was written"
[ "$("$it" ls "$d/a")" = "$(printf 'b\ncreds.enc')" ] || fail "ls shows leftovers: $("$it" ls "$d/a")"

"$it" write "$f" "second" 644 > /dev/null || fail "overwrite failed"
[ "$(mode "$f")" = 644 ] || fail "overwrite mode is $(mode "$f"), want 644"
[ "$("$it" read "$f")" = second ] || fail "overwrite content"
[ "$("$it" ls "$d/a")" = "$(printf 'b\ncreds.enc')" ] || fail "ls shows leftovers after overwrite"

printf '' > "$d/a/.hidden"
"$it" ls "$d/a" | grep -qx .hidden || fail "ls must list dotfiles"

"$it" rm "$f" > /dev/null || fail "remove failed"
[ "$("$it" exists "$f")" = no ] || fail "file still there after remove"
"$it" rm "$f" > /dev/null || fail "remove of a missing file must succeed"

if "$it" write "$d/missing-dir/x" data 600 > /dev/null 2>&1; then fail "write into a missing dir must fail"; fi
[ "$(ls -A "$d")" = a ] || fail "failed write left files behind: $(ls -A "$d")"
if "$it" read "$d/nope" > /dev/null 2>&1; then fail "read of a missing file must fail"; fi
if "$it" ls "$d/nope" > /dev/null 2>&1; then fail "ls of a missing dir must fail"; fi
