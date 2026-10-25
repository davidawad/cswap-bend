#!/usr/bin/env python3
"""Replay the `switch` steps of parity fixtures 11-18 against the Bend driver
(tests/it/switch_main.bend). Other steps (status) belong to other beads.
usage: switch_replay.py /path/to/switch-it"""
import sys
sys.dont_write_bytecode = True
import importlib.machinery
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time
import types
from pathlib import Path

root = Path(__file__).resolve().parent.parent
loader = importlib.machinery.SourceFileLoader("replay", str(root / "parity" / "replay"))
spec = importlib.util.spec_from_loader("replay", loader)
replay = importlib.util.module_from_spec(spec)
loader.exec_module(replay)

# The replay gives the CLI a fixed environment; the wrapper adds the short
# post-switch delay (the verify step is tested in switch_it.sh).
wrapper = Path(tempfile.mkdtemp(prefix="cswap-switch-cli-")) / "cswap"
wrapper.write_text('#!/bin/sh\nCSWAP_SWITCH_VERIFY_DELAY_MS=${CSWAP_SWITCH_VERIFY_DELAY_MS:-0} exec "%s" "$@"\n' % os.path.abspath(sys.argv[1]))
wrapper.chmod(0o755)
cli = [str(wrapper)]
args = types.SimpleNamespace(record=False, strict=False, verbose=True, keep=False)
failed = 0
names = sorted(p.name for p in replay.FIXTURES.iterdir() if p.name[:2] in {"11", "12", "13", "14", "15", "16", "17", "18"})
for name in names:
    fx_dir = replay.FIXTURES / name
    fx = json.loads((fx_dir / "fixture.json").read_text())
    scratch = Path(tempfile.mkdtemp(prefix=f"cswap-switch-{name}-"))
    home = scratch / "home"
    ctx = replay.Ctx(int(time.time()), home, fx.get("tokens", {}))
    problems = []
    for idx, step in enumerate(fx["steps"]):
        if step["argv"][0] != "switch":
            continue
        ps, _ = replay.run_step(cli, fx_dir, idx, step, ctx, args)
        problems += [f"step {idx + 1}: {p}" for p in ps]
    print(("PASS " if not problems else "FAIL ") + name)
    for p in problems:
        print("     ", p)
    failed += bool(problems)
    shutil.rmtree(scratch, ignore_errors=True)
sys.exit(1 if failed else 0)
