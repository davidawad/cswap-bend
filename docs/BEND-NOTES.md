# Bend 2 notes for this repo

Facts learned while writing this code against bend 2.0.38. Read `bend guide`
first; this file lists only what the guide leaves implicit and cost a
compile cycle to discover.

## Checker rules that shape every file

- A `match` scrutinizes parameters and fields only, never a computed value.
  To branch on `f(x)`, pass it to a helper def that matches its parameter
  (`header.pick(String.starts_with(..), ..)` in `src/http.bend`).
- Defs must appear before the defs that call them.
- No mutual recursion. Fold the second function into the first with an
  accumulator parameter (`header.find(name, lines, found)`).
- A parameter cannot be matched after something else has matched or bound
  past it. Match several values at once instead: `match ls found:` with
  `case Con{h, t} None{}:`.
- A `do` block binds with `x : T <- m` and `x : T = v`, but cannot
  destructure a tuple. Hand the tuple to a def that does `(a, b) = r`.
- `A & B` is `Type`-kinded. Inside a type argument it needs parens:
  `List<(String & String)>`, and such a list is affine (no `&2`).
- `match` on a char literal is not available; compare with `Char.is_eq`.
- `||`, `&&` work on `Bool` anywhere; arithmetic needs `(a + b : U32)`.

## Modules

- `import ./x.bend as X` prefixes every def of `x.bend` with `X.`. So a
  module names its own defs without a prefix (`def quote`), and callers
  write `Http.quote`.
- Tests import with a relative path: `import ../src/http.bend as Http`.

## Numbers and time

- `U32` is the machine number; there is no `U64`. Unix seconds fit in `U32`
  until 2106. `IO.now()` answers a `Nat`.
- `Nat` literals take an `n` suffix (`3n`).

## Tests and proofs

- A unit test is a ground equation: `def t() -> {f(x) == y : T}: {==}`.
  `bend file --check-only` evaluates both sides; a mismatch prints expected
  and observed and fails.
- `LAWS.bend` holds the claims (humans write it), `PROOF.bend` imports it
  `as Laws` and proves `law foo` with `def Laws.foo(..)`.
- `bend PROOF.bend --verdict` rechecks with the Lean kernel (Lean
  v4.34.0 via elan). It refuses proofs that rely on `@unsafe` or foreign
  code, so keep the decision core pure and free of effects.

## Effects

- Base effects: files (open, read, write, size, close), `Process.run`,
  `IO.sleep`, `IO.now`, `IO.get_env`, `IO.args`, TCP/UDP, channels and
  fork/join. There is no rename, chmod, unlink or flock: run `mv`/`chmod`
  through `Process.run`, or add a foreign `.c`/`.js` effect pair
  (`bend guide effects`).
- No TLS: HTTPS is curl through `Process.run("curl", ["--config", "-"], cfg, ..)`
  with the whole config on stdin (`src/http.bend`), so tokens never reach argv.
- Termination is checked. The daemon's forever loop is an `@unsafe` def,
  kept outside anything `PROOF.bend` imports.
- `bend f.bend -o bin/f` builds a native binary (clang); about one second
  for this repo.

## Effects with failure: `src/act.bend` and `do ActM<A>:`

- `Act.of(A)` is `IO(Fs.Res(A))`. `do` needs the monad's name defined in the
  file that uses it (`def ActM`, `ActM.pure`, `ActM.bind`, thin wrappers over
  `Act.pure`/`Act.bind`); an import alias is not enough.
- Inside a `do`, `x : T <- step` stops at the first Fail. A binder is affine:
  `+y : T = x` makes a reusable copy. Branch with `Act.cond(c, a, b)` or a def
  that matches its parameter; a `do` cannot match a computed value.
- Reusing a parameter or pattern binder needs `+` (`+id: Ident`,
  `case Done{+j}`). When the checker says `x (consumed more than once)`, put
  `+` on that binder.
- A def passed by name (`IO.bind(.., f)`) must not have `+` parameters; wrap it
  in a lambda (`r => f(r)`).
- `match f(x):` never works; hand `f(x)` to a def that matches its parameter.

## Lessons from `src/usage.bend`

- A `.pick` helper that calls back into the def that called it is mutual
  recursion ("an unfilled law"). Compute the recursive result in the caller and
  pass it in as an argument (`strip0.pick(.., rest)`).
- A value used twice needs `+` on its parameter, and on a pattern field
  (`case Err{kind, retry, +body}`); the message is "consumed more than once".
  A plain `String` or `Json` is Data, so `+` is always allowed for them.
- An imported module's types and constructors are qualified too: the type is
  `Json.Json`, constructors `Json.JStr{..}`, patterns `case Json.JObj{f}:`.
  Spell `Maybe<&2, Json.Json>` in full.
- There is no `|>`. Conditions such as `Bool.not(..)` or `String.is_empty(..)`
  are computed values too: they go through a `.pick(cond: Bool, ..)` def.
- `IO.get_env` of an unset variable answers `Fail`, not an empty string.
- A `do IO<T>:` block ends with the IO expression to run (a helper that
  matches); `return v` wraps a pure value. Branching on a result means calling
  a def that matches its parameter and returns the next IO.
- A golden-test `now` must be a literal; `Clock.now_s` is a foreign effect, and
  a def that reaches it makes `--check-only` print the foreign-code verdict
  (`scripts/check-file` allows exactly that one).
- Python's `round(x, 1)` and `float` repr are reproduced as decimal text
  (`usage.pct1`, `usage.float`, `usage.div100`): the checker has `F32` only,
  and a decimal shift is exact where the reference's float division is not.
- Shell tests: a bare `wait` also waits for the background stub server and
  hangs; `wait "$pid"` the helpers by name.
- A refresh gate has no sha256 here, and needs none: lineage identity is
  compared as text (`rt:<refreshToken>` or `full:<credential>`).

## Switch-era lessons

- A `type` must come before the first def that names its constructors; keep
  types at the top of the file (the checker error is "a declared constructor
  (unknown: X)").
- A closure parameter is affine, so it cannot be threaded through `Act.cond`
  (both branches are built). Pass options as a Data record (`Opts{delay_ms,
  oracle}` with an `Oracle` enum) instead of a function.
- `Tuple{a, b}` matches a pair in a multi-scrutinee `case`.
- `Dirlock.mtime` is a foreign effect (stat); `mkdir`/`rmdir` through
  `/bin/mkdir`, `/bin/rmdir` are the lock itself, so a failed `mkdir` is
  "held".
- The parity replay hands the CLI a fixed environment; a wrapper script that
  sets extra variables is the way to tune a driver for it
  (`tests/switch_replay.py`).

## Writing proofs for a decision core

- Data constructors take positional fields: `Config{9000n, Nil{}, ...}`, not
  `Config{threshold: 9000n}`. Field names exist only in the `type` line.
- `Maybe<Nat>` is affine (`&1`); inside a `Data` type or a reusable `+`
  parameter spell `Maybe<&2, Nat>`. `List<&2, T>` likewise.
- A `Nat` literal needs the `n` suffix (`10000n` is fine for the sizes here).
  `Nat.show`, `Nat.divmod`, `Nat.max`, `Nat.sub` (truncating) are in Base.
- Mark every parameter `+` that is used more than once, proof arguments
  included (`+hc: {.. == True{} : Bool}`). A pattern over a `+` value hands
  out `+` fields. A pair `A & B` is a `Type`, never `+`.
- `a && b && c` is `Bool.and(Bool.and(a, b), c)`.
- Branching on a computed value needs a helper def that matches its parameter
  (`x.pick(hit: Bool, ..)`). To prove something about such a chain, write one
  lemma per helper, each matching the same parameter and calling the next
  lemma in its arms (`decide_acct` -> `decide_kind` -> ... in `PROOF.bend`),
  so the proof never matches a computed value.
- Refuting `e : {False{} == True{} : Bool}`: rewrite through a Type-valued
  motive. `ft_disc` sends `True` to `Empty` and `False` to `Unit`;
  `%e : ft_disc(_)` then `Unit{}` is an `Empty`, and `Empty.absurd(A, ..)` is
  anything. `tf_disc` is the mirror.
- `Equal.sym(A, a, b, e)` takes the type and both sides explicitly. To rewrite
  `x` to `True{}` in the goal given `p : {x == True{}}`:
  `%Equal.sym(Bool, x, True{}, p) : {goal with _ where x is}`. `P` must be the
  goal in the checker's normalized form: put `?g` there to print it.
- A hypothesis is an ordinary `for h: {a == b : T}` binder in a law; the proof
  def takes it as an extra parameter.
- In a multi-way `match a b c:` a parameter cannot be matched again inside an
  arm; add the case to the pattern list instead.
- The predicates the laws speak about (`landed_usable`, `none_above`, ...) live
  in `src/policy.bend` beside the code, so LAWS.bend states each in one line.
  They ignore the `need` gate on purpose.
- `just ci` is heavy: run it niced, with the bend binary named explicitly:
  `BEND=$HOME/.bend/bin/bend nice -n 19 just --working-directory DIR --justfile DIR/justfile ci`.

## Splitting the core into modules, part 2

- `bend-lint` caps a file at 500 lines (`style/file-length`), so the core is
  eight modules under `src/policy/`: `types` (T), `usage` (U), `rank` (R), `pick` (K),
  `bar` (B), `exhaust` (E), `decide` (D), `spec` (S). A module imports another
  as `import ./usage.bend as U` and writes `U.headroom(..)`, `T.Usage{..}`.
  The same file imported under the same alias is the same set of names
  everywhere, so a test or proof imports `T`, `U`, `D`, `S` and writes
  `D.decide(..)` without caring who imports whom.
- Lint each module as its own entry: `bend-lint.json` sets `dead/def` entries
  to `*` (a library has no `main`), and `just lint` loops over `src/*.bend`.
  Severity is `error`, so a finding fails `just ci`.
- A def name cannot have an all-digit segment (`pick.rec.2` is rejected); a
  pattern variable cannot be `is`.
- Parameter order is match order: a `match x:` on a later parameter after
  another `match` on an earlier one is rejected ("matched after a local
  statement"). Put the parameter you match first, first.
- Functions with more than ten arms trip `complexity/cyclomatic`; split a
  twelve-way `match` into a six-way one with a `case o:` that calls the next.
- A Nat literal around 10^5 or more overflows the checker's stack
  (`262800n` is fine, `500000n` is not): keep fixture times small.
- A test file that evaluates many `decide` calls overflows the stack as one
  module; split it (`tests/policy_test.bend`, `modes_a_test.bend`,
  `modes_b_test.bend` share the same helper defs).
- Proof lemma style that worked for a 15-stage decision:
  * keep one untagged result (`Pm`) from each picker and tag it with a literal
    `Mode` at the call site (`pk.of(MRec0{}, pm)`), so each lemma sees a
    concrete mode and `landed_*` reduces;
  * state a lemma over a context rebuilt from its parts (`mkrk(..)`), so
    accessors like `K.rk.active(rk)` reduce to the parts;
  * make the decision's own data (`Switch.bar`) and the context's data come
    from one expression (`rk.bar_of(rk)`), instead of proving them equal;
  * recompute a derived value (`env.ah(e)`) at each use rather than passing it
    down with a hypothesis;
  * to move a hypothesis `rkA == rkB` into a goal, rewrite the goal:
    `%e : {S.pmg(p, as, _, f) == True{} : Bool}`.
- A reference check is cheap: `AutoSwitchEngine._rank_candidates` takes plain
  dicts, so `object.__new__(AutoSwitchEngine)` plus `_models = ()` runs the
  Python ranking next to the Bend fixtures (patch `importlib.metadata.version`
  first).

## The dashboard (`src/tui/`)

- Bend 2 has no way to read keys: `Process.run` hands its child an empty stdin
  and Base has no stdin effect. So `cswap tui` redraws until it is killed and
  has no `q` or `s <slot>` binding (use `cswap switch`). The loop is an
  `@unsafe` def with `IO.sleep`; `--once` draws one frame and exits.
- An escape in a string literal is `"\u{1B}"` (`"\x1b"` and `"\u001b"` are
  rejected). A `String` counts code points, so `━ ╸ ─ ┃ …` are one column each.
- Draw in styled segments (`Seg{text, role, dim}`), cut to the width on the
  segments, and only then paint: ANSI escapes never reach the width math, and
  NO_COLOR is one flag in `paint`. Neighbouring segments in one style are merged
  so a bar costs one escape per run.
- Everything between the files and the frame is pure and tested by ground
  equations (`tests/tui_test.bend`, `tests/tui_view_test.bend`); the
  integration test (`tests/tui_it.sh`) draws `--once` from
  `tests/fixtures/tui/state` with `CSWAP_TUI_NOW` and `TZ=UTC` pinned and
  compares to golden text. Removing the escapes from the coloured frame must
  give the plain golden, which pins both together.
- The status file's field names live in `src/tui/read.bend` (`f_pid` and its
  neighbours) and mirror `src/daemon/status.bend`. Bars come from
  `cache/usage.json` (the status file has no model windows or reset times).
- `Process.run("kill", ["-0", pid])` answers "is the daemon alive" without
  touching the daemon; `tail -n 8` reads the end of a log without loading it.
- A `List<String>` argument is affine; to use it twice, rebuild it as
  `List<&2, String>` (`Run.share`).
- Passing a def with `+` parameters as a function value fails; give a
  `.pick`-style helper a plain Maybe instead of a callback.
## The daemon (`src/daemon/`)

- A tick is `gather` (roster, live login, cache rows) -> `plan` (who is due) ->
  `fetch` (usage endpoint or probe, merged into cache/usage.json under
  `cache/.usage.lock`) -> `view` (rows to the policy's `Usage`/`Account`) ->
  `policy/decide` -> `apply` (events, the switch under `.autoswitch_state.lock`,
  the state record). `auto.bend` owns `--once` and the `@unsafe` loop;
  `entry.bend` is what the CLI dispatches `auto` to.
- `cadence`, `config`, `events`, `state`, `status`, `rows` are pure and tested by
  ground equations; `tests/daemon_events_test.bend` is generated from Python's
  `json.dumps` (`scripts/gen-daemon-events-test.py`).
- The loop has no signal handling: SIGTERM ends the process, the kernel drops
  the pid-file flock, and the stale `daemon.pid` is harmless.
- Bend has no random source and no `getpid`: the poll deadline has no jitter, and
  the pid comes from `sh -c 'echo $PPID'`.
- Percentages are centi-percent `U32`/`Nat` end to end (the policy's unit); they
  print as Python prints the float (`60.0`, `42.5`, `87.66`).
- Lesson: never `match f(x):` — hand `f(x)` to a def that matches its parameter.
  A grep for `^\s*match [A-Za-z_.]+\(` finds every offender at once.

## Daemon config reaches the dashboard

- `cswap auto --threshold 85` overrides settings.json for that process only, so the
  dashboard cannot learn the threshold from settings. The daemon writes its
  effective `Cfg` (threshold, interval_seconds, cooldown_seconds, strategy,
  models, include_api_keys) as the `config` object of `daemon-status.json` every
  tick; `tui/read.bend` prefers it while the daemon's pid is alive and falls
  back to settings.json when it is stopped or the file predates `config`.
  The reference (claude-swap 0.27.2 `tui/app.py`) only reads settings, so there
  is nothing to match.
- `watch` is the same dashboard as `tui` (the reference's `watch` opens its
  interactive TUI on the watch page); `menubar` is unsupported (exit 2);
  `upgrade`/`update` print the rebuild-and-deploy steps (exit 0).

## Formats, rpc and the socket server

- A build of `src/main.bend` takes about 40 s now (the TOON codec is in it);
  check one module with `sh scripts/check-file bend FILE` and build rarely.
- `bend` prints "ALL PROOFS CHECK" only when no def reaches a foreign effect
  or an `@unsafe` def. For those files `scripts/check-file` accepts exactly the
  one "defs rely on unsafe or foreign code" verdict; do not read the long list.
- Termination: "a decreasing self-call (arguments are read left to right: each
  passed unchanged until one shrinks)". Put the shrinking argument first, and
  the accumulator after it (`path(ks, j)`, not `path(j, ks)`).
- A pattern binder or a parameter used twice needs `+`, including `Nat` and
  `U32` ones, lists of `&2`, and the fields of a nested pattern
  (`Some{+n}`). Handles (`File`, `Socket`, `Listener`) never take `+`.
- Do not write a mutually recursive pair. For a loop that has to hand a handle
  back and forth, make the state a `type X is Type:` with one constructor per
  step and write one `@unsafe def pump(p: X, ..)` that matches it
  (`src/server.bend`: `stdin_pump`, `conn_pump`, `accept_pump`). The helpers
  that turn a result into the next step (`after_read`, `s_cut`) are plain
  defs placed before it. `scripts` has no tool for this; `Type` (not `Data`)
  is what lets a constructor hold a `Socket`.
- The same trick parses indentation without mutual recursion
  (`src/fmt/yamlr.bend`): split a block's lines into entries by indent, and let
  one fuel-bounded `val(fuel, plan)` walk `Plan` values (`PBlk`, `PArr`,
  `PObj`, `PItems`, `PFieldI`, `PFieldB`); the `plan.*` helpers are
  non-recursive.
- Callees come before callers. The fix is mechanical: when the checker names
  a def "an unfilled law", move that def above the one that calls it.
- `match` on `String.is_empty(x)`, `U32.is_eq(..)` or any call: no. Give the
  value to a def whose parameter is the scrutinee (`exec2a(ok: Bool, ..)`).
  `Bool.pick(T, c, a, b)` is the expression form; it evaluates only the arm
  taken, so recursive calls in the arms are fine.
- A string pattern is `SCon{Chr{c}, t}` with `c: U32` (a code point); there is
  no char-literal `match`. Compare with `U32.is_eq(c, 58)`.
- A user effect cannot return a new handle type, but it can return `Listener`
  or `Socket`. `src/effs/usock.c` creates a unix-domain listening socket and
  hands it back as a `Listener`; `TCP.accept`, `TCP.recv`, `TCP.send` and
  `Socket.close` then work on it unchanged because they only call
  `accept`/`recv`/`send` on the descriptor. The C side installs a
  SIGTERM/SIGINT/SIGHUP handler that unlinks the socket and `_exit(0)`s, and
  ignores SIGPIPE.
- `File.read` on `/dev/stdin` is a plain `read(2)`: it answers what is there
  (a short read on a pipe), so a request/response loop can read a chunk at a
  time and answer as lines arrive. An empty string is end of input.
- `IO.print` writes the text and a newline; `IO.write` writes the text as is.
- Tests that cut the output of a command with `$(...)` lose trailing newlines;
  count the blank lines between documents, not after the last one.
- Gotchas of the repo's hooks: an auto-commit hook commits every edit; commit
  with one `git add`/`git commit` per call; `rm` in any command text is
  refused (use `trash` with an absolute path); redirecting into a computed
  path in a compound command can trip the dcg backstop (write the file with the
  editor tool instead).
