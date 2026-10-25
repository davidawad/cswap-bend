# Cutover: from the Python poller to the Bend daemon

The Python `claude-swap auto` poller (launchd job `com.david.cswap-auto`) keeps
running the whole time. The Bend daemon first runs beside it in **shadow
mode**: it makes every decision the poller would make and logs it, but never
switches. When the two agree for three days, the Bend daemon takes over for a
week. Both read and write the same `~/.claude-swap-backup`, so nothing needs
migrating, and rollback is one command.

Nothing in this document is automatic. Installing the shadow job, flipping and
rolling back are decisions for a person.

## 0. Before you start

- `main` builds and `just ci` is green (parity-bend passes every fixture).
- `bin/cswap-bend --version` prints the version you mean to run.
- The live poller is healthy: `tail -n 5 "$LEGACY_STATE_DIR/auto.log"`
  shows a `poll` line within the last interval.

## 1. Install the shadow daemon (3 days)

```sh
deploy/install-shadow            # dry run: prints every step and the LaunchAgent
deploy/install-shadow --live     # build, copy to ~/.local/share/cswap-bend/<sha>/, load
```

The shadow job runs

```
cswap-bend auto --shadow --shadow-log ~/.local/state/cswap-bend-shadow/shadow.jsonl \
  --interval 300 --threshold 85 --model Fable,Opus --strategy best
```

The interval, threshold, models and strategy are read from the live poller's
plist (`~/.config/cswap-legacy/com.david.cswap-auto.plist`), so the shadow
decides under the settings the poller uses. It does not switch, does not write
the live credential and does not touch `com.david.cswap-auto`.

Each tick appends one JSON line to the shadow log: `ts`, `active`, `event`
(`switch` or `no-switch`), `reason`, `trigger`, `from`, `to`, `accounts`
(headroom per slot) and `events`.

Uninstall at any time: `deploy/install-shadow --uninstall --live`.

## 2. Compare (daily)

```sh
scripts/shadow-compare \
  "$LEGACY_STATE_DIR/auto.log" \
  ~/.local/state/cswap-bend-shadow/shadow.jsonl
scripts/shadow-compare ... --json        # the same, machine-readable
scripts/shadow-compare ... --interval 600
```

Every Bend tick is paired with the nearest Python tick within one interval
(default 300 s). A pair **agrees** when both decided the same thing: both
switch to the same target, or neither switches. The report lists the pairs,
the agreement rate, the ticks with no partner, and every divergence with both
sides' per-slot headroom:

- `event`: one side switched and the other stayed;
- `target`: both switched, to different accounts.

It always exits 0; reading the report is the check.

### Explaining a divergence

A divergence is *explained* when you can name the cause and it is not a bug in
Bend. Typical causes: the two read an account's usage at different moments
(headroom differs across the threshold); one side was in cooldown; the Python
poller's usage cache was held by an import. Write each one down with its
timestamp. A divergence you cannot explain is a failure.

## 3. Pass criteria

Shadow (3 days):

- no unexplained divergence in the daily reports;
- the shadow log has a tick for every interval (no gaps beyond the pairing
  window): `unpaired` counts stay near zero outside restarts;
- the shadow never wrote the live credential (`~/.claude/.credentials.json`
  untouched by it; the Python poller remains the only writer).

Bend as the live poller (1 week, after the flip):

- no switch the operator cannot explain;
- no missed exhaustion: no stretch where the active account sat at 100% in
  `list --json` while a candidate with headroom existed and no switch followed.

## 4. Flip

1. Pass the shadow criteria and save the last report:
   `scripts/shadow-compare ... > /tmp/shadow-report.txt`.
2. Dry run, read it: `deploy/install-live --report /tmp/shadow-report.txt`.
   It refuses without a non-empty `--report`. It prints every step: stop and
   unload the Python job `com.david.cswap-auto` (its agent file stays), unload
   and remove the shadow job, build and copy the binary, and write and load
   `com.david.cswap-bend` (`cswap-bend auto`, no `--shadow`, with the poller's
   interval, threshold, models and strategy).
3. Flip: `deploy/install-live --report /tmp/shadow-report.txt --live`. The
   Python poller is stopped only after the binary and the agent file are ready.
   If the Bend job then fails to load, or launchctl does not list it, or any
   later step fails, the script puts the Python poller back in the same run
   (bootstraps `com.david.cswap-auto` from its kept agent file and checks that
   launchctl lists it) and exits 1 with "Python poller restored", or "Python
   poller NOT restored: <why>" if that fails too. No exit leaves zero pollers
   running, except the second message, which tells you to run the dotfiles
   installer by hand.
4. Watch `cswap-bend list --json` and `~/.local/state/cswap-bend/stderr.log`
   through the first full interval; confirm a `poll` line and no errors.

## 5. Rollback

Rollback is one command:

```sh
deploy/install-live --uninstall --live
```

It unloads and removes `com.david.cswap-bend`, then runs
the legacy poller's install script (`~/.config/cswap-legacy/install`), which rebuilds and reloads
the Python poller `com.david.cswap-auto`. If that installer is missing
or fails, it loads `com.david.cswap-auto` from its kept agent file instead and
exits 1 so the failure is seen. By hand it is the same two steps:
`launchctl bootout gui/$(id -u)/com.david.cswap-bend`, then the installer.

`~/.claude-swap-backup` is shared and in the reference format, so no data
moves. A `remove` done by Bend archives to `credentials/.removed/` rather than
deleting; those files stay put and the Python side ignores them.

If a bad switch already happened, `cswap switch <slot> --force` (either
implementation) re-activates the stored backup of the slot you want.
