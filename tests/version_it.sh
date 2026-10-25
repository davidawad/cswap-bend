#!/bin/sh
# The binary runs and reports its version.
set -eu
out=$("$1" --version)
case "$out" in
  "cswap-bend "*) ;;
  *)
    echo "unexpected version output: $out" >&2
    exit 1
    ;;
esac
