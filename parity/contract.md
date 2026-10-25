# cswap behaviour contract (for the Bend 2 rewrite)

Reference implementation: claude-swap
0.27.2 (sdist sha256 `8ca851fd…0c81`, URL in
`reference/fetch`) with patches `reference/patches/0001-0003` applied. Citations
`file:line` point into `src/claude_swap/` of that patched tree.

This document says what the Bend cswap must do so it can replace the Python
one with no change to the files on disk, the auto-loop, or anything that reads
cswap's JSON. The golden fixtures in `fixtures/` turn the testable parts into
checks. `replay` runs those checks against any CLI:

```
docs/cswap-bend/replay /path/to/cswap            # PASS/FAIL per fixture, exit 0 iff all pass
docs/cswap-bend/replay --record <reference>      # re-record goldens (reference only)
docs/cswap-bend/fixtures/make-fixtures           # regenerate fixture inputs
```

Status of the reference: `replay` against the patched Python cswap passes
33/33 fixtures, stable over repeated runs (see "Proof" at the end).

**MUST** below means a fixture checks it, or that a cutover with both
implementations sharing one `~/.claude-swap-backup` breaks without it.
**SHOULD** means parity that is desirable but not checked.

---

## 0. Scope

What we keep:

- `list`, `status`, `switch` (bare, `<num|email|alias>`, `--strategy best|next-available`, `--model`)
- `add`, `add-token`, `remove`
- `auto` (`--once`, loop, `--json`, `--threshold`, `--interval`, `--cooldown`, `--model`, `--strategy`, `--dry-run`, `--include-api-key-accounts`)
- `import-usage` (`--hold`)
- `config` (`get|set|unset|list|path`)
- every on-disk format in §1

Out of scope for the rewrite. These are not exercised by fixtures. Their files
must still be preserved, never deleted or rewritten:

- `run` / `map` / `unmap` (session profiles under `sessions/`, `mappings.json`)
- `tui`, `watch`, `menubar`
- `export` / `import`, `upgrade`, `purge`
- `alias`, `swap`, `move`, `disable` / `enable`
  - The `disabled` flag in sequence.json MUST still be honoured (§1.2, fixture 13).
- `unclaimed`

**`--json` coverage: the bead asks for it on every kept verb, but the
reference does not have it everywhere.**

- The reference accepts `--json` only on `list`, `status`, `switch`, `auto`
  and `config get|list` (`cli.py:1357`).
- On `add`, `add-token`, `remove` and `import-usage` it is an argparse usage
  error (exit 2).
- The Bend version MAY add `--json` to those four verbs. If it does, the
  output MUST follow §2.6: `schemaVersion: 1`, the error envelope on failure,
  stdout stays pure JSON.
- The fixtures pin only the text-mode behaviour of those four verbs: exit
  code, files written, and key substrings. Adding `--json` therefore breaks
  no fixture.

## 1. On-disk formats (cutover compatibility)

### 1.0 Roots and paths

| what | path |
|---|---|
| backup root | `~/.claude-swap-backup` (the macOS layout; production is macOS). **MUST**: the replay fails a run that writes `~/.local/share/claude-swap`. The Python reference uses XDG on Linux (`paths.py:105-123`); the seam forces the macOS root. |
| Claude config home | `$CLAUDE_CONFIG_DIR` or `~/.claude` |
| live credential | `<config home>/.credentials.json` |
| global config | `~/.claude.json`. Exception: `<config home>/.config.json` is used when it is a non-empty regular file, or an empty writable one with no `.claude.json` (`paths.py:44-74`). |
| poller log | `<poller state dir>/auto.log`, written by `auto-loop.sh`, not by cswap |

**The macOS keychain is never touched (patch 0001).**
- `_use_keychain()` is always false, so reads return nothing and deletes do
  nothing.
- Claude Code itself still reads the `Claude Code-credentials` keychain item
  first.
- Bend MUST NOT read, write or delete keychain items either. Behaving
  differently from the reference here would change which credential Claude
  Code picks up.

### 1.1 Backup root layout

| path (relative to root) | mode | written by | content |
|---|---|---|---|
| `sequence.json` | 0600 | add, add-token, remove, switch | §1.2 |
| `credentials/` | 0700 | — | — |
| `credentials/.creds-<n>-<email>.enc` | 0600 | add, add-token, switch (outgoing backup), refresh | §1.3. `<email>` is the raw email, `@` kept, no slugging. |
| `credentials/.creds-<n>-<email>.enc.prev` | 0600 | switch, refresh | the previous generation, same encoding; written only when the old value was readable and different |
| `credentials/.unclaimed-*.enc`, `.unclaimed-manifest.json` | 0600 | switch | safety stash for a displaced live credential that no slot owns. Preserve it; rewrite-optional. |
| `configs/` | 0700 | — | — |
| `configs/.claude-config-<n>-<email>.json` | 0600 | add, add-token, switch (outgoing backup) | §1.4 |
| `cache/usage.json` | 0600 | list, status, switch, auto, import-usage | §1.5 |
| `settings.json` | 0600 | config set/unset | §1.6 |
| `autoswitch_state.json` | 0600 | auto | §1.7 |
| `mappings.json`, `menubar_settings.json`, `.migrations.json`, `sessions/` | — | out-of-scope verbs | preserve untouched |
| `claude-swap.log[.1-3]` | umask | everything | `%(asctime)s - %(levelname)s - %(message)s`, rotating at 1 MiB, 3 backups. Format SHOULD stay; nothing parses it. |
| lock files | umask | — | §1.8 |

**Atomic JSON writes.** Every JSON file cswap owns is written atomically:
1. Write a temp file in the same directory (`mkstemp(dir=parent, suffix=".tmp")`).
2. `os.replace` it onto the target.
3. `chmod 0600`.

Formatting is `json.dumps(…, indent=2)`, which means `ensure_ascii`, no
trailing newline, and keys in insertion order. Readers MUST accept any valid
JSON. Writers SHOULD keep the formatting, so diffs stay quiet while both
implementations run side by side.

### 1.2 `sequence.json`

It has no schema version.

```json
{
  "activeAccountNumber": 1,
  "lastUpdated": "2026-10-23T12:00:00Z",
  "sequence": [1, 2, 3, 4, 5, 6],
  "accounts": {
    "1": {"email": "owner@example.test", "uuid": "<accountUuid>",
          "organizationUuid": "<org uuid or \"\">", "organizationName": "<or \"\">",
          "added": "2026-10-13T12:00:00Z"},
    "2": {"email": "st2@example.test", "uuid": "", "organizationUuid": "",
          "organizationName": "", "added": "…"}
  }
}
```

- **`accounts` keys** are decimal strings. **`sequence`** holds ints, sorted
  ascending, and is the rotation order. An account missing from `sequence`
  is never listed.
- **Optional record keys.** These MUST round-trip:
  - `alias`: lowercase, `^[a-z0-9_.-]+$`, not all digits, not starting with `-`.
  - `disabled: true`: held out of rotation and auto. The key is removed on enable.
  - `kind: "api_key"`: absent means OAuth.
- **Identity** is the pair `(email, organizationUuid)`.
- **Resolving an identifier**, in order:
  1. all digits means a slot number;
  2. otherwise an alias, matched case-insensitively;
  3. otherwise an exact email. More than one email match is a `ConfigError`.
- **`activeAccountNumber` is advisory.**
  - It is written by add (not add-token) and by switch.
  - remove does not clear it.
  - The *live* account is always derived from `~/.claude.json`
    `oauthAccount.(emailAddress, organizationUuid)`. That is the
    `activeAccountNumber` that list/status print.
- **Next free slot** is `max(int(keys)) + 1`, or 1 when there are no accounts.
- **Timestamps** are `%Y-%m-%dT%H:%M:%SZ` UTC.
- **Torn or unparseable file:** `ConfigError("<path> exists but could not be
  parsed (…). Repair or move it, then retry — refusing to overwrite it
  unread.")`. It MUST NOT be overwritten.

### 1.3 `.enc` credential backups

The file is standard base64, with padding and no newline, of the UTF-8
credential string. It is not encrypted. Readers `strip()` and decode
strictly. Undecodable or empty content counts as "no stored credentials".

Credential payloads:

- **Full `/login`** (1 of the 6 production accounts). The exact bytes Claude
  Code wrote to `.credentials.json`, captured verbatim:
  `{"claudeAiOauth": {"accessToken", "refreshToken", "expiresAt" (epoch ms), "scopes": [...], "subscriptionType"?, "refreshTokenExpiresAt"?, …}, "mcpOAuth"?, …}`.
  - Unknown keys pass through untouched.
  - After a token refresh, cswap re-serialises compactly (`json.dumps`
    default separators). It sets `accessToken`, sets
    `expiresAt = now_ms + expires_in*1000`, and sets `refreshToken` and
    `scopes` when the response returns them.
- **Setup-token** (5 of 6). Exactly
  `{"claudeAiOauth": {"accessToken": "sk-ant-oat01-…", "scopes": ["user:inference"]}}`.
  It has no refresh token and no `expiresAt`, so it is never refreshed and
  never "expired". Fixtures 03 and 04 check this.
- **API key.** The raw `sk-ant-api…` string, not JSON (fixture 05). A value
  is classified as an API key when it is not JSON, starts with `sk-ant-`, and
  is neither `sk-ant-oat…` nor `sk-ant-ort…`.

A slot is *switchable* only when both its decoded credential and its config
backup exist and are non-empty.

**Fingerprints** are used in usage.json and autoswitch_state.json:
- `"sha256:" + hex(sha256(refreshToken))` when there is a refresh token;
- otherwise `"sha256-full:" + hex(sha256(whole credential string))`;
- `"sha256-at:" + hex(sha256(accessToken))` for a rejected access token.

### 1.4 `configs/.claude-config-<n>-<email>.json`

- **add, and the outgoing backup on switch:** the whole raw `~/.claude.json`
  text at capture time.
- **add-token:**
  `{"oauthAccount": {"emailAddress": "<email>", "accountUuid": "", "organizationUuid": null, "organizationName": null}}`,
  in compact form.

### 1.5 `cache/usage.json` (`usage_store.py`)

```json
{"schemaVersion": 2, "accounts": {"<slot>": {
  "email": "…", "organizationUuid": "",
  "lastGood": {"five_hour": {"pct": 12.0, "resets_at": "<ISO>", "countdown": "1h 30m", "clock": "13:30"},
               "seven_day": {…}, "spend": {"used", "limit", "pct", "currency", "resets_at"?},
               "scoped": [{"name": "Opus", "pct": 30.0, "resets_at": "<ISO>", …}]} | null,
  "fetchedAt": 1792740000.1, "lastAttemptAt": …, "claimId": "<hex>"|null, "claimUntil": 0.0,
  "consecutiveFailures": 0, "lastError": "http-429"|null, "backoffUntil": <epoch>|null,
  "last429At": <epoch>, "authDeadStrikes": 0, "struckFingerprint": null,
  "rejectedFingerprint": null, "nextPollAt": <epoch>|null, "pollIntervalS": 180.0,
  "heldUntil": <epoch>}}}
```

- **`schemaVersion` MUST be 2.** A file with any other version, or one that
  is unparseable, is read as empty and overwritten with v2 on the next write.
  There is no migration.
- **Rows are keyed by slot string and guarded by identity.** A row whose
  `email` / `organizationUuid` does not match the slot's current identity is
  treated as empty, and replaced on write. Rows for slots the writer does not
  know about, and unknown fields in a row, MUST be preserved.
- **Times** are float epoch seconds. `pct` is 0–100.
- **`lastGood` and `fetchedAt` change only on success.** A failure never
  touches them, so stale data is served while errors continue. `lastGood:
  null` means a success that returned no windows.
- **Sentinels are never persisted.** "token expired", "api key", "re-login
  needed", "no credentials", "keychain unavailable" and "foreign credential"
  are an overlay computed at read time.
- **Locking.** Every write is a read-modify-write under `cache/.usage.lock`.
  Network calls are never made while that lock is held. The cycle is: claim
  (`lastAttemptAt=now`, `claimId=uuid4hex`, `claimUntil=now+90`), unlock,
  fetch, lock, merge only if `claimId` still matches, unlock.
- **`lastError` values:**
  - `http-<code>`, `timeout`, `network`, `bad-response`
  - `no-access-token`, `refresh-failed`
  - `invalid_grant`, `no_refresh_token` (permanent: they add `authDeadStrikes`
    and set `struckFingerprint`)
  - `invalid_client`, `store-unmirrored`, `consume-busy`, `stash-unreadable`
  - any other exception class name, e.g. `KeyError`
- **Fixtures:** 03, 06, 08, 09 and 20 check rows after a fetch, after a
  failure, and after an adopt.

### 1.6 `settings.json`

```json
{"schemaVersion": 1,
 "autoswitch": {"threshold": 90.0, "intervalSeconds": 60.0, "cooldownSeconds": 300.0,
                "hysteresisPct": 10.0, "strategy": "best", "includeApiKeyAccounts": false,
                "unhealthyTicks": 3, "model": null},
 "ui": {"theme": "auto"}}
```

The values above are the defaults. Ranges and choices:

| key | range or choices |
|---|---|
| `threshold` | 50–99.9 |
| `intervalSeconds` | 15–3600 |
| `cooldownSeconds` | 0–86400 |
| `hysteresisPct` | 0–50 |
| `unhealthyTicks` | 1–100 |
| `strategy` | `best` \| `consume-first` |
| `model` | comma list or `all` |
| `theme` | `dark` \| `light` \| `auto` |

**Lenient load** (`settings.py:170-248`):
- A missing, unparseable or non-object file gives the defaults.
- A number outside its range is **clamped**, not rejected.
- A bool or non-number in a numeric field gives the default.
- A bool field is read with truthiness, so the string `"false"` counts as
  true.
- An unknown `strategy` value gives the default.
- Unknown keys and sections MUST survive every write.

**CLI overrides.** Flags given to `auto` / `switch` override the file and are
clamped the same way: `--threshold 120` becomes 99.9 and `--interval 5`
becomes 15. Model names are split on `,`, trimmed, and de-duplicated
case-insensitively.

**Strict write** (`config set`):
- An unknown key, an unparseable value, or a value out of range is an error
  (exit 1, file untouched).
- Bools accept `true|1|yes|false|0|no`.
- Only the touched key and `schemaVersion` are written.
- `config unset` removes the key, and removes the section if it is left
  empty.
- Fixture 32 checks this.

**Production note.**
- The author's live poller settings file set `threshold 98`
  and `strategy consume-first`.
- But `auto-loop.sh` always passes `--threshold 85 --model Fable,Opus
  --strategy best --interval 300` (overridable via `CSWAP_AUTO_*`), so the
  flags win.

### 1.7 `autoswitch_state.json`

```json
{"schemaVersion": 1,
 "quarantine": {"<slot>": {"email": "…", "reason": "invalid_grant|identity-conflict",
                           "at": "…Z", "refreshTokenFingerprint": "sha256:…|sha256-full:…|null"}},
 "lastSwitchAt": 1792740000.5, "lastSwitchTo": "3", "lastSwitchFrom": 1,
 "leftHeadroom": 10.0, "leftRecoveryAt": 1792747200.0, "leftTrigger": "proactive"}
```

- `lastSwitchTo` is a string; `lastSwitchFrom` is an int or null.
- `leftHeadroom` and `leftRecoveryAt` are null when unknown or infinite.
- The file is written under `.autoswitch_state.lock`. Unrelated keys are
  preserved.
- `--dry-run` never writes it (fixture 28).
- Fixtures 22, 25, 27 and 31 check the switch record.

### 1.8 Locks

| lock | kind | used for |
|---|---|---|
| `<root>/.lock` | `flock(LOCK_EX\|LOCK_NB)` polled every 0.1 s, **10 s** timeout. The file is opened `"w"` and never deleted. | switch and every roster mutation |
| `<root>/cache/.usage.lock` | same | usage store RMW |
| `<root>/.autoswitch_state.lock` | same | state file RMW |
| `<root>/credentials/.consume-<n>.lock` | same | serialising refresh-token use per slot |
| `<root>/credentials/.unclaimed-manifest.lock` | same | stash |
| `~/.claude/.oauth_refresh.lock`, then `~/.claude.lock` | **directory** locks (npm proper-lockfile protocol, which Claude Code uses). `mkdir` to take; held while its mtime is younger than 60 s; the holder touches it every 3 s; 9 s timeout per lock; `rmdir` to release. | writing the live credential |
| `~/.claude.json.lock` | directory lock, 10 s staleness | writing `~/.claude.json` |

- On timeout: `LockError("Failed to acquire lock - another instance may be
  running")` / `ClaudeCodeLockTimeout(…)`, exit 1.
- Lock order is consume, then `.lock`, then the CC credential pair, then the
  CC config lock.
- Bend MUST take the same flock files and the same directory locks. Both
  implementations, and Claude Code itself, run concurrently during cutover.
- flock is a foreign `.c` effect twin in Bend. Directory locks are plain
  `mkdir` / `rmdir` plus `utime`.

### 1.9 What switch writes outside the backup root

1. **`~/.claude/.credentials.json`** gets the target's decoded `.enc`
   (atomic, 0600).
   - If both the live and target values are JSON objects and the target has
     `claudeAiOauth`, the live values of `mcpOAuth`, `mcpOAuthClientConfig`,
     `mcpXaaIdp`, `mcpXaaIdpConfig` and `pluginSecrets` are carried over.
     The result is re-serialised compactly.
   - Then any `primaryApiKey` is removed from `~/.claude.json`.
   - Switching *to* an API key instead: set `primaryApiKey`, append
     `key[-20:]` to `customApiKeyResponses.approved`, and unlink
     `.credentials.json`.
2. **`~/.claude.json`**: only `oauthAccount` is replaced, with the target
   backup's `oauthAccount` object verbatim. Every other key is kept.
   - The write is atomic, indent=2, 0600.
   - The fields cswap reads from it are `emailAddress`, `organizationUuid`,
     `accountUuid` and `organizationName`. The whole object is copied.
   - A setup-token slot's object is
     `{"emailAddress", "accountUuid": "", "organizationUuid": null, "organizationName": null}`.
   - Fixtures 11 and 12 check this.
3. **Outgoing backup, taken before the write.**
   - The outgoing slot's config backup is refreshed from the live
     `~/.claude.json`.
   - Its `.enc` is rewritten (with `.prev` retention) when the live
     credential differs from the backup and is proven to be the same
     account.
   - When ownership is unproven, cswap asks the profile oracle (`GET
     /api/oauth/profile`, §3.3). A foreign credential goes to the unclaimed
     stash and never into a slot.
4. **`sequence.json`**: `activeAccountNumber = target`.
5. **Rollback.** Any failure rolls back every step in reverse and raises
   `SwitchError("Switch failed and was rolled back: …")`.

## 2. CLI surface and JSON schemas

### 2.0 Common rules

- **Exit codes:** 0 ok; 1 handled error (`ClaudeSwitchError`); 2 usage error
  (argparse); 130 Ctrl-C. `auto --once` has its own codes (§4.6).
- **With `--json`:**
  - stdout is exactly one JSON document, `indent=2`, or for `auto` one
    compact JSON object per line.
  - A handled error prints the envelope
    `{"schemaVersion": 1, "error": {"type": "<ExceptionClass>", "message": "…"}}`
    on stdout and exits 1 (fixture 18).
  - Human text never goes to stdout.
- **Error `type` values:** `ConfigError`, `SwitchError`, `SessionError`,
  `AccountNotFoundError`, `ValidationError`, `TransferError`, `LockError`,
  `ClaudeCodeLockTimeout`, `CredentialReadError`, `CredentialWriteError`,
  `MigrationError`.
- **JSON is additive.** Consumers ignore unknown keys. The replay therefore
  allows extra keys by default; `--strict` forbids them.
- **Root check:** running as root outside a container gives `Error: Do not
  run this script as root (unless running in a container)`, exit 1.
- **No token is ever printed**, on any stream, in any mode. The replay fails
  any run that prints a fixture token.

### 2.1 `list [--json]`

```json
{"schemaVersion": 1, "activeAccountNumber": 1 | null,
 "accounts": [ROW…],
 "duplicateAccountWarnings"?: [str], "lockstepUsageWarnings"?: [str], "unclaimedCredentials"?: [id]}
```

ROW always has these keys:
`number` (int), `email`, `organizationName`, `organizationUuid`,
`isOrganization` (bool), `active` (bool), `usageStatus`, `usage`.

ROW may also have:
- `alias`, `disabled: true`, `loginExpiresAt` (ISO);
- with `usage` non-null: `usageFetchedAt` (ISO Z) and `usageAgeSeconds`;
- with `usage` null: `lastGoodUsage`, `lastGoodFetchedAt`, `lastGoodAgeSeconds`,
  plus `usageError` and `usageRetryAt` when `usageStatus` is `unavailable`.

`usageStatus` is one of `ok`, `token_expired`, `api_key`,
`keychain_unavailable`, `relogin_required`, `foreign_credential`,
`no_credentials`, `unavailable`.

USAGE (camelCase projection of the internal dict):

```json
{"fiveHour"?: {"pct", "resetsAt"?, "countdown"?, "clock"?},
 "sevenDay"?: {…, "expectedPct"?, "aheadOfPace"?, "projectedExhaustionAt"?, "willLastToReset"?},
 "spend"?: {"used", "limit", "pct", "currency", "resetsAt"?, "countdown"?, "clock"?},
 "scoped"?: [{…sevenDay fields…, "name": "Opus"}]}
```

- **`countdown`** is `"{d}d {h}h"`, `"{h}h {m}m"` or `"{m}m"`. **`clock`**
  is local `%H:%M`, or `%b {day} %H:%M` when the reset falls on another day.
  Both are recomputed from `resetsAt` at print time.
- **Pace fields**, on `sevenDay` and `scoped` only:
  - Period P = 604800 s. Let `elapsed = P - ((reset - fetched_at) mod P)`.
  - The fields are omitted while `elapsed < 86400`.
  - `expectedPct = min(100, elapsed/P*100)`, rounded to 0.1.
  - `aheadOfPace = pct - expected >= 15`.
  - `projectedExhaustionAt` is a linear ETA.
  - `willLastToReset = pct + rate*(P - elapsed) <= 100`.
- **`usage` is decision-grade.** It is `lastGood` only when that is at most
  300 s old, or when trust is extended:
  - Trust is extended while the row is failing, planned (`now <
    nextPollAt`), claimed or held.
  - Extension is capped at 3600 s. After an `http-429` the cap is the window
    reset, or 7200 s when no reset is known.
  - Otherwise `usage` is null and `lastGoodUsage` carries the display copy.
- **No backup root at all:**
  `{"schemaVersion": 1, "activeAccountNumber": null, "accounts": []}`
  (fixture 01).
- **Side effects.** `list` fetches the usage of eligible rows (§3) and so
  writes `cache/usage.json`. It may also refresh an inactive full-login slot's
  token, which rewrites its `.enc`.
- **Fixtures:** 01, 03, 05, 07, 08, 09, 19, 20.

### 2.2 `status [--json]`

- **Logged out:** `{"schemaVersion": 1, "active": null}` (fixture 02).
- **Unmanaged live login:**
  `{"schemaVersion": 1, "active": {"email", "managed": false}}`.
- **Managed:**
  `{"schemaVersion": 1, "active": {number, email, organizationName, organizationUuid, isOrganization, managed: true, usageStatus, usage, alias?, …the freshness / lastGood / failure fields of §2.1}, "totalManagedAccounts": N}`.
  Fixtures 06, 10, 11.

### 2.3 `switch [--json]`

Forms:
- `switch` (rotation)
- `switch <num|email|alias> [--force]` (direct)
- `switch --strategy best|next-available [--model NAMES]`

```json
{"schemaVersion": 1, "switched": bool,
 "from": {"number": int|null, "email": str} | null, "to": {…} | null,
 "strategy": "rotation" | "best" | "next-available" | "direct",
 "reason": "switched" | "already-active" | "activated" | "unmanaged-account" | "only-one-account"
         | "usage-unavailable" | "already-best" | "candidates-exhausted" | "no-valid-target",
 "message": str, "warnings": [str],
 "models"?: [str], "modelSource"?: "cli" | "autoswitch.model"}
```

- **Rotation:**
  - Starting from `activeAccountNumber`, walk `sequence` cyclically.
  - Skip disabled and unswitchable slots. Each skip adds a warning such as
    `"Skipped Account-2 (disabled)"` (fixture 13).
  - With fewer than 2 slots, the result is `only-one-account`.
  - In JSON mode, an unmanaged live login gives `unmanaged-account`. Human
    mode auto-adds that login instead.
- **`best`:**
  - Headroom is `100 - max(pct of 5h, 7d and the --model scoped windows)`.
  - Pick the switchable, enabled candidate with the most known headroom.
  - Switch only if it is **strictly greater** than the active's. Ties stay,
    and on equal headroom the earliest slot wins.
  - Otherwise the result is `already-best` (fixture 16), `usage-unavailable`
    when comparison is impossible, or `candidates-exhausted`.
  - `--model Opus` makes the Opus scoped window binding (fixture 15). Without
    `--model`, the `autoswitch.model` setting applies.
- **`next-available`:** rotation that also skips candidates with headroom
  ≤ 0. Unknown headroom is never skipped.
- **Direct switch to the live slot:** `already-active`, strategy `direct`
  (fixture 17). `--force` re-activates the stored backup (`activated`).
- **Errors** (fixture 18):
  - unknown slot: `AccountNotFoundError("Account-9 does not exist")`
  - unknown email: `AccountNotFoundError("No account found with identifier: …")`
  - malformed identifier: `ValidationError("Invalid account identifier: …")`
  - no `sequence.json`: `ConfigError("No accounts are managed yet")`
- **Files written:** §1.9 (fixtures 11–15).

**Intentional differences in the Bend switch** (src/switch.bend):
- **No credential is destroyed.** The reference writes a "safety stash" when the
  live credential is unowned, and overwrites an outgoing slot backup when
  ownership is unresolved. Bend archives the live credential to
  `credentials/.removed/<utc-ts>-live-<email>.enc` (0600) before it replaces an
  unmanaged or foreign/alien live login, and `write_cred` keeps the replaced
  backup generation as `.enc.prev`.
- **Local ownership evidence.** When the live credential has the same lineage as
  *another* slot's backup, Bend treats it as that slot's (`foreign-synced`)
  without asking the oracle, and does not write it into the slot named by
  `~/.claude.json`. The reference only reaches that verdict through the oracle.
- **Post-switch verification (new).** Claude Code on macOS reads a keychain
  login before `~/.claude/.credentials.json`, so a file-only switch can be
  silently undone. After a real switch, and after the locks are released, Bend
  waits `delay` (default 2 s, `CSWAP_SWITCH_VERIFY_DELAY_MS` in the driver),
  re-reads `~/.claude.json` and, if `oauthAccount` no longer names the target,
  fails with the distinct error `live-login-overridden` (envelope type
  `live-login-overridden`, exit 1) naming the observed email and the remedy:
  "a Claude Code keychain login is overriding cswap; remove the 'Claude
  Code-credentials' keychain item". It never touches the keychain.
- **Usage for `best` / `next-available`** is read from `cache/usage.json` as it
  stands; Bend's switch does not fetch (the usage store owns fetching).
- The directory locks are taken and released without the 3 s mtime refresh
  thread: Bend holds them for well under a second.
- Not ported: session-profile scans (`cswap run`), the token-refresh grant,
  `--import` reconciliation of a diverged self-switch (`reconcile`).

### 2.4 `add`, `add-token`, `remove` (text mode)

**`add [--slot N] [--alias A]`** captures the live login:
1. Identity comes from `~/.claude.json` `oauthAccount`. The credential comes
   from `.credentials.json`, or else `primaryApiKey`.
2. A live API key is refused, pointing the user at add-token.
3. Ownership is checked with the profile oracle (`GET /api/oauth/profile`,
   fixture 06). A mismatch is a `ConfigError`. "Could not verify" prints a
   notice and continues.
4. **Known identity without `--slot`:** rewrite the slot in place and print
   `Updated credentials for Account N (…)`.
5. **New identity:** write the `.enc`, the config, and the record
   `{email, uuid, organizationUuid, organizationName, added[, alias]}`. Append
   to `sequence` and sort it, set `activeAccountNumber`, and print `Added
   Account N: <email> …`.
6. **Occupied `--slot`:** prompt `Overwrite slot N? [y/N]`.

**`add-token [TOKEN|-] [--email E] [--slot N]`**:
- **Token source:** `-` reads one line from stdin, which is how the fixtures
  call it, so the token is never on argv. With no argument, `getpass`
  prompts.
- **Default email:** `setup-token-<slot>@token.local`, or
  `api-key-<slot>@token.local` for an API key (fixture 04).
- **Record written:**
  `{email, uuid: "", organizationUuid: "", organizationName: "", added[, kind: "api_key"]}`.
- It does **not** change `activeAccountNumber` and makes **no** HTTP call.
- **Output:** `Added Account N: <email> [personal] (from token|API key)`, or
  `Updated …` for an existing `(email, "")` identity.
- **Errors:** an empty token gives `ValidationError("Token cannot be empty")`.
  A cross-kind collision is a `ValidationError`.
- **Fixtures:** 03, 04, 05.

**`remove <num|email>`**:
- Prompts `[y/N]`, reading stdin; only `y` confirms.
- Deletes the `.enc`, both `.prev` files, the legacy `.creds-None-<email>.enc`,
  the config, and the session profile. Drops the record and the `sequence`
  entry, and prunes mappings.
- Prints `Removed Account-N (<email>)` (fixture 19).
- Removing the live account only warns.

**Intentional difference: Bend `remove` never destroys a credential.**
- The reference deletes the `.enc`, both `.prev` files and the config. On
  2026-10-23 a remove deleted the only full login in that way.
- Bend moves them instead. `credentials/.creds-<n>-<email>.enc` goes to
  `credentials/.removed/<utc-ts>-<n>-<email>.enc` (0600, `<utc-ts>` like
  `20261023T120000Z`), `.enc.prev` to the same name plus `.prev`, and the
  config to `configs/.removed/<utc-ts>-<n>-<email>.json`.
- The same applies when `add` or `add-token` displaces an occupied slot or
  moves an account to another slot: the old files are archived, not deleted.
- Everything else about `remove` is unchanged: the prompt, the sequence.json
  edit, the `Removed Account-N (<email>)` line. The move is logged as
  `Removed account N: <email>; credential kept under credentials/.removed/`.
- A fixture that lists the credentials directory after `remove` would see the
  `.removed/` directory. Readers MUST ignore dot-directories there.

**Identity (email + organization) on write.**
- `add` refuses when `GET /api/oauth/profile` names another account or another
  organization than `~/.claude.json` does, with the reference's wording, and
  writes nothing. An unresolvable lookup registers with a `Notice:` line.
- `add-token` makes no HTTP call. A setup-token carries only `user:inference`,
  so the profile endpoint answers 403. Bend logs
  `identity unverified for slot N (<email>): ...` at WARNING in
  `claude-swap.log` instead of passing silently.

### 2.5 `import-usage <path|-> [--hold SECONDS]`

**Input** is another machine's `list --json` document.

**Validation.** All rows are validated before anything is written:
- `schemaVersion` must be 1.
- `accounts` must be a list.
- Every row needs an `email` and an `organizationUuid`.
- Rows with `usageStatus != "ok"` are skipped.
- `usageAgeSeconds` must be ≥ 0.
- Each window needs a finite `pct >= 0`.
- `resetsAt` must be ISO.
- At least one window is required.

Any violation raises `TransferError`, exit 1.

**Matching and write.**
- Rows are matched by `(email, organizationUuid)`; rows with no match are
  skipped.
- **Adopt:** `fetchedAt = now - age`, but only if that is newer than the
  stored value. `lastGood` is set from the row. Fetch state is untouched.

**`--hold`.**
- `heldUntil = min(now + hold, fetchedAt + 3600, earliest resetsAt)`.
- While a row is held, this machine does not fetch it.
- `--hold 0` lifts the hold. `--hold` must be finite and ≥ 0, else exit 2.

**Output.** stderr only; stdout stays empty:
- per matched slot, `Adopted usage for <email> → slot <N>` or `Kept slot
  <N>'s own reading for <email>: it is newer`;
- a summary line, `Done: A adopted, K kept, S skipped[; fetching held for up
  to Hs | ; holds lifted]`.

Fixture 20 covers adopt and hold, then checks that the next `list` fetches
only the unheld accounts.

### 2.6 `config`

- **`config get KEY --json`:**
  `{"schemaVersion": 1, "key", "value", "isSet"}`.
- **`config list --json`:**
  `{"schemaVersion": 1, "path", "settings": [{"key", "value", "isSet"}…]}`.
- **`config set KEY VALUE`, `config unset KEY`, `config path`:** text output.
  Errors exit 1.
- **Fixture:** 32.

### 2.7 `auto`

See §4. Every event is one JSON line, defined in §4.5.

## 3. Usage reads (HTTP), poll policy and backoff

### 3.1 Which endpoint

| token | how usage is read |
|---|---|
| has `user:profile` in `scopes` (full login), or has no `scopes` list | `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-swap/1.0`; 5 s timeout |
| `scopes` present without `user:profile` (setup-tokens), or a token that already got a 403 scope error this process | the haiku probe, §3.2 |
| usage endpoint answers 429 | try the probe. A probe success counts as a success. If the probe fails, the original 429 is the error. |
| usage endpoint answers 403 with `oauth_scope_insufficient` / `scope requirement` | remember the token as inference-only for this process, then probe |

**Usage endpoint response mapping:**
- `five_hour` / `seven_day` `{utilization, resets_at}` become
  `{"pct": utilization, "resets_at", "countdown", "clock"}`.
- `limits[]` entries with `scope.model.display_name` and a numeric `percent`
  become `scoped`.
- `extra_usage` (when `is_enabled` and the amounts are non-null) becomes
  `spend`, with `used = used_credits/100`, `limit = monthly_limit/100`, and
  `currency` defaulting to `"USD"`.

### 3.2 The setup-token probe (patch 0003)

```
POST https://api.anthropic.com/v1/messages            (20 s timeout)
Authorization: Bearer <token>
anthropic-version: 2023-06-01
anthropic-beta: claude-code-20250219,oauth-2025-04-20
content-type: application/json
{"model":"claude-haiku-5-5","max_tokens":1,
 "system":[{"type":"text","text":"You are Claude Code, Anthropic's official CLI for Claude."}],
 "messages":[{"role":"user","content":"."}]}
```

**Reading the response headers.**
- `anthropic-ratelimit-unified-{5h,7d}-utilization` is a fraction. It maps to
  `pct = round(f*100, 1)`.
- `-reset` is an epoch. It maps to `resets_at = ISO with +00:00`.
- A window with no utilization header is omitted.

**Status handling.**
- A **non-2xx response that still carries the headers** (429 when exhausted)
  is a valid reading (fixture 09, slot 2 at 100%).
- **2xx with no headers** gives `bad-response`.
- **Non-2xx without headers** gives `http-<code>`, with `Retry-After`
  (seconds) honoured.
- The probe never produces `scoped` or `spend`, so `--model` cannot bind a
  setup-token account.
- Fixtures 03, 08 and 09 check the exact request: method, URL, beta header
  and body.

**Bend transport.** No built-in TLS, so HTTPS goes through `curl --config -`
with the token on stdin, never on argv (the fabric-core `claude_probe`
pattern).

### 3.3 Other endpoints

- **Profile oracle:** `GET https://api.anthropic.com/api/oauth/profile`, 5 s
  timeout, gives `{account: {uuid, email}, organization: {uuid}}`. It is used
  only for identity and ownership (add; switch when outgoing bytes differ).
  Any failure means "unknown". A setup-token gets 403 here (fixture 12).
- **Token refresh:** `POST https://platform.claude.com/v1/oauth/token`, body
  `{"grant_type": "refresh_token", "refresh_token", "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e"}`.
  - It applies only to inactive full-login slots whose token is expired
    (`now_ms + 300000 >= expiresAt`) or got a 401.
  - The refresh is serialised under `credentials/.consume-<n>.lock`.
  - A 400/401/403 response with `error: invalid_grant | invalid_client`
    counts as permanent. Anything else is transient.
  - The *active* account is refreshed only under Claude Code's own lock
    protocol. If that is deferred, its usage reads `token expired`.

### 3.4 Eligibility and fetch planning (`usage_store.py`, `poll_policy.py`)

**Constants:**

| constant | value |
|---|---|
| serve TTL | 180 s |
| decision trust | 300 s |
| claim TTL | 90 s |
| trust ceiling | 3600 s (7200 s after a 429) |
| min interval | 180 s |
| urgent interval | 60 s |
| active ceiling | 300 s |
| candidate default / ceiling | 300 s / 600 s |
| exhausted interval | 600 s |
| movement delta | 1.0 pct |
| jitter | ±10 % |
| escalation margin | 15 pct |
| reset slack | 60 s |
| post-429 minimum | 360 s, ×1.5, cap 1800 s, inside a 3600 s window |

**A row is eligible to fetch** when it is not dead (`authDeadStrikes ≥ 1`),
not in backoff (`now < backoffUntil`), not held, and not claimed. Then:
- **list / status / switch:** `stale AND (nextPollAt is null OR now >=
  nextPollAt OR overslept)`, where `stale` means `now - fetchedAt > 180` or
  `fetchedAt` is null.
- **Scheduled auto tick:** `poll_due OR (stale AND (nextPollAt null OR
  overslept))`.
- **Auto escalation:** `poll_due OR stale`.
- `overslept` means `nextPollAt > now + max(pollIntervalS or 600, 600)*1.1 +
  60`.

Fetches run in parallel. The i-th fetch starts after i × 0.25 s.

**After a successful fetch**, the plan is computed by `plan_after_fetch`
(`poll_policy.py:195`):

```
default = 180 if active else 300 ; ceiling = 300 if active else 600
base = previous pollIntervalS or default
prev, new = binding pct before/after (100 - headroom)
unknown either        -> interval = default
|new - prev| >= 1.0   -> interval = max(180, base/2)                      (moving)
else                  -> interval = min(ceiling, max(180, base*1.5))
active and moving and no recent 429 and new >= threshold-15 -> interval = 60
recent 429 (last429At, or backoffUntil, within 3600 s) -> interval = min(1800, max(interval, base*1.5, 360))
headroom <= 0         -> interval = max(interval, 600)
nextPollAt = now + interval*(1 + 0.1*(2*rand-1))
headroom <= 0: nextPollAt = min(nextPollAt, limiting reset + 60)   (latest reset among windows >= 100 %)
else:          nextPollAt = min(nextPollAt, earliest future reset + 60)
store pollIntervalS = interval
```

- A newly activated account is pulled forward to `nextPollAt = max(now,
  fetchedAt + 180)`, `pollIntervalS = 180`.
- Fixture 08 shows the first-fetch defaults: 180 for the active account, 300
  for the others. In fixture 09, slot 2 is exhausted and gets 600.

**After a failure**, the plan is unchanged. The failure only sets backoff:

```
n = consecutiveFailures (after +1); rate_limited = (kind == "http-429")
computed = min(30 * 2**min(n-1, 32), 600)               # 30, 60, 120, 240, 480, 600
Retry-After absent  -> computed
Retry-After == 0    -> rate_limited ? min(max(computed, 300), 600) : computed
else asked = RA (+900 if rate_limited and RA > 600); asked = min(asked, 4500 if rate_limited else 3600)
                    -> max(asked, computed)
backoffUntil = now + that; last429At = now on http-429
```

Fixture 09 shows this: a 429 with Retry-After 120 gives a backoff of
`<rel:+120>`, while a 401 and a 500 give `+30`.

## 4. Autoswitch decision rules (`autoswitch.py`, as patched)

### 4.1 Definitions

- **Relevant windows:**
  - `5h` and `7d` when `pct` is numeric;
  - plus each `scoped` window whose name is in `--model`, compared
    case-insensitively (`all` means every scoped window);
  - in API order;
  - never `spend`.
- **Headroom:** `100 - max(pct)` over the relevant windows. With no windows
  it is unknown (null). Headroom `<= 0` means the account is at its limit.
- **Utilization:** `100 - headroom`.
- **Binding window:** the relevant window with the maximum pct; the first one
  wins ties.
- **Decision value of an account:** a sentinel if one applies, else
  `lastGood` if it is trusted (§2.1), else unknown.
- **Candidates:**
  - switchable (credential and config present);
  - not disabled, not quarantined, not the live account;
  - in `sequence` order;
  - API-key accounts only with `includeApiKeyAccounts`, and then only as a
    last resort.

### 4.2 One tick (`tick()`, never raises)

1. **Read state.** Read `autoswitch_state.json` without a lock. Release any
   quarantine whose slot email changed (`account-replaced`) or whose
   credential fingerprint changed (`credentials-replaced`). Each release
   emits `account-unquarantined`.
2. **Find the live slot**, from `~/.claude.json` identity. If there is none:
   emit `poll` (active null), then `no-switch` with reason
   `unmanaged-active-account` when a live login exists, else
   `no-active-account`. Return NO_ACTION (2).
   - `auto-loop.sh` keys its self-heal on `unmanaged-active-account`
     (fixture 30).
3. **Collect usage** with no network for fresh rows:
   - Fetch the active account if its row is missing, due, overslept or
     stale.
   - Add at most one due candidate per tick: the one with the oldest
     `max(fetchedAt, lastAttemptAt)`.
   - **Escalate** to fetching every candidate when the active headroom is
     unknown (and not "token expired"), or when active utilization is
     `>= threshold - 15`. Rows that are planned, exhausted, and whose
     `pollIntervalS > 600` are exempt.
4. **Emit `poll`.**
5. **Model-name check.** Once there is data for every relevant account: if a
   `--model` name matches no account's scoped windows, emit
   `config-warning`, once per process.
6. **Active is an API-key account** and API keys are not allowed: `no-switch
   active-api-key`, return 2.
7. **Classify the trigger:**
   - **Known headroom, `utilization < threshold`** (strictly):
     - strategy `best`: `no-switch below-threshold`, detail `"U% < T%"`
       (formatted with `%.10g`), return 2 (fixture 21);
     - strategy `consume-first`: trigger `consume-first`.
   - **Known headroom, `utilization >= threshold`:** trigger `at-limit` if
     headroom ≤ 0, else `proactive`.
   - **Unknown headroom with the "token expired" sentinel** (idle Claude
     Code): `no-switch active-idle`, return 2. This holds for up to 1800 s,
     measured in process memory; after that, failover counting starts.
   - **Any other unknown headroom (patch 0002):** `no-switch
     active-usage-unknown`, detail `"headroom unknown; not counted toward
     failover"`, return 2. **It never fails over.** This covers a failed
     fetch, untrusted stale data, the no-credentials / keychain / re-login /
     foreign sentinels, and usage with no windows. Fixture 23 has the active
     account's usage endpoint return 500.
   - **Failover:** reached only after the idle hold expires. It needs
     `unhealthyTicks` consecutive ticks; that counter lives in memory, so
     `--once` can never fail over. The trigger is `failover`.
8. **Cooldown** applies to `proactive` and `consume-first` only: `now -
   lastSwitchAt < cooldownSeconds` gives `no-switch cooldown`, return 2
   (fixture 24). `at-limit` and `failover` ignore cooldown (fixture 25).
9. **No candidates at all:** `no-switch no-candidates`, return BLOCKED (3)
   (fixture 29).
10. **Rank** (§4.3).
11. **Nothing ranked:**
    - No candidate has known headroom: `no-comparison` (3).
    - consume-first: `reset-unknown` or `already-consuming-soonest` (2).
    - Some OAuth candidate is unknown, or has headroom > 0:
      `no-qualifying-candidate` (3) (fixture 33).
    - Otherwise every account is exhausted: `all-exhausted`, with
      `earliestResetAt` = the minimum over blocked accounts of their
      latest-at-100 % window reset (null if any is unknown), return 3
      (fixture 26).
12. **Freshen, then switch.** Walk the ranked list in order:
    - A target whose token expires within 10 min is refreshed first.
    - A dead token (`invalid_grant`) or an org mismatch quarantines the
      target (`account-quarantined`) and moves on to the next.
    - A transient or systemic failure moves on, and ends in an `error` event
      (1) if nothing succeeds.
    - Then, under `.autoswitch_state.lock`: re-check cooldown, run the
      switch (§1.9), and record `lastSwitchAt / To / From, leftHeadroom,
      leftRecoveryAt, leftTrigger`.
    - Emit `switch`, return SWITCHED (0) (fixtures 22, 25, 27, 31).
    - `--dry-run` emits `switch` with `dryRun: true` and writes nothing
      (fixture 28).

### 4.3 Ranking (strategy `best`)

For each OAuth candidate with known headroom `h > 0` that is not the barred
account (the no-return bar is described below):

- **Gate for `proactive` triggers:**
  - The candidate must land **below** the threshold: `100 - h < threshold`.
  - It must beat the active account by the hysteresis margin:
    `h - active_h >= hysteresisPct` (default 10).
  - `at-limit` and `failover` triggers skip this gate.
- **Sort key:** `-h`, so the most headroom wins. A stable sort means
  `sequence` order breaks ties.
- **All-above mode:** when the active account and every known candidate are
  all at or over the threshold, ranking switches to soonest recovery. A
  candidate must recover more than 300 s before the active account. This
  applies when either recovery falls within 4 h, or when both the active and
  the best candidate are nearly spent (≤ 3 % headroom).

**No-return bar.** After a proactive switch away from account A, A is barred
as a target for proactive triggers, until both of the following hold:
1. A has recovered. That is, either:
   - A's headroom is more than `active_h * 2 + 3`, or
   - A's headroom is at least `min(leftHeadroom + 3, 100)`, or
   - A's binding window now recovers more than 300 s before
     `leftRecoveryAt`.

   After a failover departure, recovered instead means: A's headroom is more
   than `100 - threshold`, or A recovers within 4 h and more than 300 s
   before the active account.
2. A's headroom is at least `2 ×` the active account's headroom. When the
   active headroom is unknown, A's headroom must instead exceed
   `100 - threshold`.

A recovered but still-barred A is allowed after all if nothing else
qualifies. The bar is lifted if the user switched by hand in the meantime
(`lastSwitchTo != live`).

**`consume-first`** (not used in production; auto-loop passes `best`):
- Prefer the candidate whose 7-day window resets **strictly sooner** than the
  active account's.
- It re-fetches every account before committing.
- It refuses to act on stale data (`stale-usage`).

### 4.4 Settings sources

The order is: flags, then `settings.json`, then defaults. Clamping is in
§1.6. Fixture 31 runs with settings only (threshold 80); every other auto
fixture passes flags, the way `auto-loop.sh` does.

### 4.5 Events (`auto --json`, one per line)

Every event has `{"schemaVersion": 1, "event": KIND, "ts": "<UTC ISO, seconds, Z>", …}`.

| KIND | fields |
|---|---|
| `poll` | `active`: `{number, email}` or null; `headroomPct`: `{"<slot>": float or null}` for every managed account; `threshold`; `fetchErrors`?: `{"<slot>": lastError}`; `windowsPct`?: `{"<slot>": {"5h", "7d", "<Model>"…}}` |
| `switch` | `trigger`: `proactive` \| `at-limit` \| `failover` \| `consume-first`; `from`, `to`: `{number, email}` or null; `warnings`: [str]; `dryRun`: bool |
| `no-switch` | `reason`, `detail` (always present, may be `""`). Reasons: `unmanaged-active-account`, `no-active-account`, `active-api-key`, `below-threshold`, `active-idle`, `active-usage-unknown`, `cooldown`, `no-candidates`, `no-comparison`, `reset-unknown`, `already-consuming-soonest`, `no-qualifying-candidate`, `stale-usage`, `no-viable-target`, `already-active` |
| `all-exhausted` | `earliestResetAt`: ISO Z or null |
| `account-quarantined` | `number` (str), `email`, `reason`: `invalid_grant` \| `identity-conflict` |
| `account-unquarantined` | `number` (str), `email`, `reason`: `credentials-replaced` \| `account-replaced` |
| `sleep` | `seconds`, `until` (loop mode only, when the next delay is more than 1.5 × interval) |
| `error` | `message`, `transient: true` |
| `config-warning` | `message` |

**`auto-loop.sh` depends on these:**
- `"event": "switch"` / `"no-switch"`, matched by grep;
- the substring `unmanaged-active-account`;
- error envelopes on stdout.

### 4.6 `--once` exit codes, and the loop

**`--once` exit codes:** 0 switched (including a dry run), 1 error, 2 no
action, 3 blocked (no viable target / all exhausted).

**The loop:**
```
until stopped:
    tick()
    pick delay
    emit sleep if the delay is long
    wait the delay; SIGTERM or stop cuts it short
```

How the delay is picked:
- **All exhausted, reset known:** `min(max(reset+60 - now, interval), 600)`.
- **Blocked with no candidates, or no reset known; or the idle hold:**
  `max(interval, 300)`.
- **Otherwise:** `interval × U(0.9, 1.1)`, shortened to the active account's
  `nextPollAt` (but never under 60 s).
- **Errors** get no extra backoff.

**Loop exits:**
- SIGTERM exits the loop cleanly with code 0.
- Ctrl-C exits with code 130.
- `auto-loop.sh` restarts the process after `interval` seconds.

The loop is a fuel-bounded or `@unsafe` def in Bend. The replay does not
exercise loop mode; the tick it repeats is fully covered.

## 5. Test seam (how fixtures run any implementation)

The replay seeds a scratch `HOME` and runs `<cli> <argv>` with this
environment:

- `HOME=<scratch>`, `NO_COLOR=1`, `TZ=UTC`, `LC_ALL=C.UTF-8`
- `PATH` inherited
- `CSWAP_TEST_HTTP_BASE=http://127.0.0.1:<port>`
- `PYTHONPATH=seam/python`

**What a Bend cswap MUST honour.** When `CSWAP_TEST_HTTP_BASE` is set, every
`https://<host>/<path>` request goes to `$CSWAP_TEST_HTTP_BASE/<host>/<path>`
over plain HTTP: for curl, same headers and body, `http://` URL. The stub
server answers from the fixture's routes, matched on method, URL and bearer
token. Unstubbed requests get HTTP 599. The replay records every request and
compares the multiset (method, URL, which fake token, the
`anthropic-beta` / `anthropic-version` / `content-type` headers, JSON body)
against the golden. So an implementation must make the same requests: the
same eligibility, the same probe body, no extras.

**The Python seam** (`seam/python/sitecustomize.py`, inert without the env
var) does three things:
- redirects `urllib` to the stub;
- forces the backup root to `~/.claude-swap-backup` (a no-op on macOS, where the reference already uses it; needed on Linux, where the reference uses XDG). The seeded `home/` trees are platform-neutral (file credential store, `.enc` backups, no keychain), so the same goldens replay 33/33 on Linux and macOS;
- disables the PyPI update check, which is out of contract.

For a non-Python CLI, the `PYTHONPATH` entry is harmless.

**Fixture format** (`fixtures/<NN-name>/`):
- **`home/`** is the seed. Templates are `{{epoch:+N}}`, `{{ms:+N}}`,
  `{{iso:+N}}`, `{{isoz:+N}}` (relative to a per-fixture `now`),
  `{{tok:NAME}}` and `{{home}}`. A file `X.b64src` is seeded as `X`
  containing its base64; that is how the `.enc` files are made. JSON seeds
  are rendered structurally.
- **`fixture.json`** has a description, the contract sections covered, the
  fake tokens, and steps. Each step has `argv`, `stdin`, `http` routes, a
  `write` map of extra files, `stdout: json|jsonl|text`,
  `stdout_contains` / `stderr_contains`, the `capture` paths (a trailing `/`
  means a listing, minus lock / tmp / log files), and `requests:
  exact|any`.
- **`expected/step-N.json`** is the recorded golden: exit code, normalised
  stdout, the captured files (mode; parsed JSON; `.enc` decoded), and the
  requests.

**Normalisation:**
- Seed-echoed values stay exact, as templates.
- Values from the CLI's own clock are recorded as `<rel:+N>`, compared within
  `15 s + 22 %` to absorb runtime and poll-plan jitter. Examples:
  `lastUpdated`, `fetchedAt`, `nextPollAt`, `backoffUntil`, `ts`.
- `<volatile>` means presence only, for `countdown`, `clock`, ages and claim
  ids.
- Objects are compared as a superset (JSON is additive). Arrays must match in
  length and order.

**Secrets.** All tokens contain `FAKE` (the replay refuses anything else).
Emails are `@example.test`. Any token appearing on stdout or stderr fails the
fixture.

**Not covered by fixtures** (contract text only):
- loop mode and `sleep` events
- lock contention and timeouts
- the token refresh grant and quarantine
- consume-first
- the unclaimed stash and foreign-credential classification
- `CLAUDE_CONFIG_DIR` / `.config.json` selection
- API-key activation on switch

These are candidates for follow-ups once the Bend tree exists.

## 6. Fixture index

| fixture | covers |
|---|---|
| 01-list-empty | list with no root |
| 02-status-empty | status logged out |
| 03-add-token-setup | add-token from stdin; `.enc`/config/sequence format; list reads it through the probe |
| 04-add-token-default-email-slot | `--slot` with no `--email` gives `setup-token-4@token.local` |
| 05-add-token-api-key | raw API key, `kind: api_key`, `usageStatus api_key`, no HTTP |
| 06-add-current-login | add with the profile oracle; status reading `/api/oauth/usage` with scoped windows |
| 07-list-six-fresh | the production-shaped six accounts served from cache, no HTTP |
| 08-list-six-stale-fetch | cold cache: 1 usage call + 5 probes, usage.json v2 rows and plans |
| 09-list-fetch-errors | 429 to probe fallback, 429-with-headers = 100 %, 429/401/500 backoff |
| 10-status-managed | status JSON |
| 11-switch-to-setup-token | direct switch: credentials, `.claude.json` oauthAccount, backups, sequence |
| 12-switch-back-to-full | switch from a setup-token (profile oracle 403) back to the full login |
| 13-switch-rotate | rotation skips a disabled slot |
| 14-switch-best | best picks max headroom |
| 15-switch-best-model | `--model Opus` makes the scoped window binding |
| 16-switch-best-stay | already-best |
| 17-switch-already-active | already-active |
| 18-switch-errors | error envelopes, exit 1 |
| 19-remove | remove with confirmation |
| 20-import-usage-hold | adopt / skip / hold, then the next list fetches only unheld rows |
| 21-auto-below-threshold | below-threshold, exit 2 |
| 22-auto-proactive-best | proactive switch, state file, exit 0 |
| 23-auto-unknown-headroom | patch 0002: unknown never fails over |
| 24-auto-cooldown | cooldown |
| 25-auto-at-limit-ignores-cooldown | at-limit beats cooldown |
| 26-auto-all-exhausted | all-exhausted + earliestResetAt, exit 3 |
| 27-auto-model-binding | `--model Fable,Opus` binding window |
| 28-auto-dry-run | dry-run writes nothing |
| 29-auto-no-candidates | no-candidates, exit 3 |
| 30-auto-unmanaged-active | unmanaged-active-account (auto-loop self-heal) |
| 31-auto-settings-file | settings.json drives auto with no flags |
| 32-config | config set/get/list/unset + range error |
| 33-auto-hysteresis-blocks | hysteresis / landing-below-threshold, exit 3 |

## Proof

The run below used the reference built exactly as the installer builds it:
the sdist fetched from the pinned URL, sha256 verified, patches 0001–0003
applied, then installed into a scratch venv with Python 3.12.

```
$ docs/cswap-bend/replay /tmp/cswap/venv/bin/cswap
PASS  01-list-empty
…
PASS  33-auto-hysteresis-blocks
33/33 fixtures passed
```

A mutant wrapper changed the switch target in stdout and echoed a fake token
on stderr. The replay reported FAIL with the exact diff
(`stdout.to.number: 2 != expected 3`) and `SECRET LEAK`.
