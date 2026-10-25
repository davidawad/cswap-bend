#!/bin/sh
# Regenerate docs/showcase/list-six.png: `cswap list` over six generic sample
# accounts (parity fixture 07, example.test addresses, fake tokens).
# Needs: bin/cswap-bend (just build), python3, ImageMagick `magick`, a
# monospace font file with box-drawing glyphs (FONT, default macOS Menlo).
# usage: sh docs/showcase/make-screenshots.sh        (run from the repository root)
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd -P)
font=${FONT:-/System/Library/Fonts/Menlo.ttc}
cli=${CLI:-$root/bin/cswap-bend}
txt=$(mktemp)
trap 'rm -f "$txt"' EXIT

home=$(python3 -I "$root/parity/replay" "$cli" --only 07-list-six-fresh --keep 2>&1 | sed -n 's/^ *kept //p' | head -n 1)
{
  echo '$ cswap list'
  HOME=$home TZ=UTC NO_COLOR=1 "$cli" list
} > "$txt"

magick -background '#1e1e2e' -fill '#cdd6f4' -font "$font" -pointsize 20 \
  label:@"$txt" -bordercolor '#1e1e2e' -border 28x24 \
  -strip -colors 16 PNG8:"$root/docs/showcase/list-six.png"
echo "$root/docs/showcase/list-six.png"
