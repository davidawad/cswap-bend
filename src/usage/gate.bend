import Base
import ../clock.bend as Clock
import ../fs.bend as Fs
import ../lock.bend as Lock
import ../b64.bend as B64
import ../fs/write.bend as FsW
import ../store/base.bend as SBase
import ./norm.bend as UNorm
import ./cred.bend as UCred
import ../json.bend as Json

# ---- the refresh consume gate ----------------------------------------------
#
# A refresh token is single-use, and the Python cswap shares the slots, so the
# POST runs under the same per-slot flock the reference takes
# (credentials/.consume-<slot>.lock): re-read the slot's .enc under it, never
# consume a superseded snapshot, POST, write the rotated credential back, then
# release.

# cred: the slot's now-current credential (adopted or rotated); error: the
# refresh failure or `consume-busy` / `store-unmirrored`; consumed: the bytes
# the gate POSTed or adopted (a strike binds to those, not the snapshot).

type Gated is Data:
  Gated{cred: Maybe<&2, String>, error: Maybe<&2, String>, consumed: Maybe<&2, String>, account: Json.Json}

type Gate is Data:
  NoGate{}
  Gate{slot: String, email: String, root: String}

def enc.path(+root: String, +slot: String, +email: String) -> String:
  SBase.enc_path(root, slot, email)

def consume.path(+root: String, +slot: String) -> String:
  SBase.creds_dir(root) ++ "/.consume-" ++ slot ++ ".lock"

def fp.pick(+m: Maybe<&2, String>, +cred: String) -> String:
  match m:
    case Some{r}:
      "rt:" ++ r
    case None{}:
      "full:" ++ cred

# Lineage identity, as the reference's credential_fingerprint (refresh token
# when there is one, else the whole credential), kept as text: it is only ever
# compared for equality, so no hash is needed.
def fp(+cred: String) -> String:
  fp.pick(UCred.refresh_token(UCred.oauth.of(cred)), cred)

def gated.err(+k: String, +consumed: Maybe<&2, String>) -> Gated:
  Gated{None{}, Some{k}, consumed, Json.JNull{}}

def gated.ok(+c: String, +consumed: Maybe<&2, String>) -> Gated:
  Gated{Some{c}, None{}, consumed, Json.JNull{}}

def gated.ok_a(+c: String, +consumed: Maybe<&2, String>, +acct: Json.Json) -> Gated:
  Gated{Some{c}, None{}, consumed, acct}

def done.g(g: Gated) -> IO(Fs.Res(Gated)):
  IO.pure(Fs.Res(Gated), Done{g})

def stored(r: Fs.Res(String)) -> Maybe<&2, String>:
  match r:
    case Fail{e}:
      None{}
    case Done{t}:
      UNorm.nonempty(B64.decode(t))

# The world moved past the caller's snapshot and the current generation is
# fresh: the refresh the caller wanted has happened.
def adopt.pick(+cur: Maybe<&2, String>, +snap: Maybe<&2, String>, +ex: Bool) -> Bool:
  match cur snap:
    case Some{a} Some{b}:
      Bool.not(String.eq(a, b)) && Bool.not(ex)
    case _ _:
      False{}

def adopt(+cur: String, +snapshot: String, +now: U32) -> Bool:
  adopt.pick(UCred.access_token(UCred.oauth.of(cur)), UCred.access_token(UCred.oauth.of(snapshot)), UCred.expired(UCred.oauth.of(cur), now))

def write.back(+path: String, +old_text: String, +new: String, +acct: Json.Json) -> IO(Fs.Res(Gated)):
  IO.bind(Fs.Res(Unit), Fs.Res(Gated), FsW.write_atomic(path ++ ".prev", old_text, "600"),
    u => IO.bind(Fs.Res(Unit), Fs.Res(Gated), FsW.write_atomic(path, B64.encode(new), "600"),
      w => done.g(gated.ok_a(new, Some{new}, acct))))

# CAS on the lineage: write the successor only when the store still holds the
# generation we consumed; a moved store keeps its newer lineage.
def cas.pick(+same: Bool, +path: String, +text: String, +new: String, +acct: Json.Json, +now_cred: String) -> IO(Fs.Res(Gated)):
  match same:
    case True{}:
      write.back(path, text, new, acct)
    case False{}:
      done.g(gated.ok(now_cred, Some{now_cred}))

def cas.store(+m: Maybe<&2, String>, +path: String, +text: String, +cur: String, +new: String, +acct: Json.Json) -> IO(Fs.Res(Gated)):
  match m:
    case None{}:
      done.g(gated.ok_a(new, Some{cur}, acct))
    case Some{+now_cred}:
      cas.pick(String.eq(fp(now_cred), fp(cur)), path, text, new, acct, now_cred)

def act.post(r: Result<&2, &2, String, UCred.Granted>, +path: String, +text: String, +cur: String) -> IO(Fs.Res(Gated)):
  match r:
    case Fail{k}:
      done.g(gated.err(k, Some{cur}))
    case Done{UCred.Granted{new, acct}}:
      IO.bind(Fs.Res(String), Fs.Res(Gated), Fs.read_file(path), r2 => cas.store(stored(r2), path, text, cur, new, acct))

def act.decide(+adopt: Bool, +path: String, +text: String, +cur: String) -> IO(Fs.Res(Gated)):
  match adopt:
    case True{}:
      done.g(gated.ok(cur, Some{cur}))
    case False{}:
      IO.bind(Result<&2, &2, String, UCred.Granted>, Fs.Res(Gated), UCred.refresh_acct(cur), r => act.post(r, path, text, cur))

def act.cur(+m: Maybe<&2, String>, +path: String, +text: String, +snapshot: String) -> IO(Fs.Res(Gated)):
  match m:
    case None{}:
      done.g(gated.err("transient", None{}))
    case Some{+cur}:
      IO.bind(U32, Fs.Res(Gated), Clock.now_s(), now => act.decide(adopt(cur, snapshot, now), path, text, cur))

def act.read(r: Fs.Res(String), +path: String, +snapshot: String) -> IO(Fs.Res(Gated)):
  match r:
    case Fail{e}:
      done.g(gated.err("transient", None{}))
    case Done{+text}:
      act.cur(stored(Done{text}), path, text, snapshot)

def gate.act(+path: String, +snapshot: String) -> IO(Fs.Res(Gated)):
  IO.bind(Fs.Res(String), Fs.Res(Gated), Fs.read_file(path), r => act.read(r, path, snapshot))

def busy.err(+code: U32) -> Gated:
  gated.err(Clock.sel.s(U32.is_eq(code, 11), "consume-busy", "transient"), None{})

def locked.fail(ce: U32 & String) -> Gated:
  (c, m) = ce
  busy.err(c)

def locked.res(r: Fs.Res(Gated)) -> Gated:
  match r:
    case Done{g}:
      g
    case Fail{e}:
      locked.fail(e)

def timeout.of(r: Result<&1, &1, U32 & String, String>) -> U32:
  match r:
    case Fail{e}:
      10000
    case Done{v}:
      Maybe.default(&2, U32, U32.read(v), 10000)

def gated.locked(+slot: String, +email: String, +snapshot: String, +root: String, +ms: U32) -> IO(Gated):
  IO.bind(Fs.Res(Gated), Gated,
    Lock.with_lock(Gated, consume.path(root, slot), ms, gate.act(enc.path(root, slot, email), snapshot)),
    r => IO.pure(Gated, locked.res(r)))

def gated.go(+slot: String, +email: String, +snapshot: String, +root: String) -> IO(Gated):
  IO.bind(Result<&1, &1, U32 & String, String>, Gated, IO.get_env("CSWAP_CONSUME_TIMEOUT_MS"),
    t => gated.locked(slot, email, snapshot, root, timeout.of(t)))

def gated.env2(+set: Bool, +slot: String, +email: String, +snapshot: String, +root: String) -> IO(Gated):
  match set:
    case True{}:
      IO.pure(Gated, gated.err("store-unmirrored", None{}))
    case False{}:
      gated.go(slot, email, snapshot, root)

def gated.env(r: Result<&1, &1, U32 & String, String>, +slot: String, +email: String, +snapshot: String, +root: String) -> IO(Gated):
  match r:
    case Fail{e}:
      gated.go(slot, email, snapshot, root)
    case Done{+v}:
      gated.env2(Bool.not(String.is_empty(v)), slot, email, snapshot, root)

# consume_backup_grant: refresh the slot's credential under its consume lock.
# `snapshot` is the caller's copy; the gate consumes the freshest copy it can
# read from <root>/credentials/.creds-<slot>-<email>.enc, or adopts a fresher fresh one
# without any POST. Busy past the timeout (10 s, or
# CSWAP_CONSUME_TIMEOUT_MS) is `consume-busy`.
def refresh_gated(+slot: String, +email: String, +snapshot: String, +root: String) -> IO(Gated):
  IO.bind(Result<&1, &1, U32 & String, String>, Gated, IO.get_env("CLAUDE_SECURESTORAGE_CONFIG_DIR"),
    r => gated.env(r, slot, email, snapshot, root))

def plain.pick(r: Result<&2, &2, String, String>, +cred: String) -> Gated:
  match r:
    case Done{c}:
      gated.ok(c, Some{cred})
    case Fail{k}:
      gated.err(k, Some{cred})

# Gate or direct POST, by the caller's choice.
def refresh_via(g: Gate, +cred: String) -> IO(Gated):
  match g:
    case NoGate{}:
      IO.bind(Result<&2, &2, String, String>, Gated, UCred.refresh(cred), r => IO.pure(Gated, plain.pick(r, cred)))
    case Gate{slot, email, root}:
      refresh_gated(slot, email, cred, root)
