import Base
import ../json.bend as Json
import ../act.bend as Act
import ../store/io.bend as SIo
import ../store/base.bend as SBase
import ../usage/cred.bend as UCred
import ../usage/gate.bend as UGate
import ./sess.bend as Sess
import ./identity.bend as Id

# Making a switch target safe to switch to (autoswitch.py _freshen_target) and
# naming credentials the way usage.json and the state file do.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

# ---- fingerprints ------------------------------------------------------------------------------

def hex_of(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{(st, (out, err))}:
      Maybe.default(&2, String, List.head(&2, String, String.split(String.trim(out), ' ')), "")

# Hex sha256 of a text, through shasum(1) with the text on stdin (never argv).
def sha256(+text: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, String, Process.run("shasum", ["-a", "256"], text, 4096, 5000), r => IO.pure(String, hex_of(r)))

def tagged(+tag: String, +h: String) -> String:
  tag ++ h

def hashed(+tag: String, +text: String) -> IO(String):
  IO.bind(String, String, sha256(text), h => IO.pure(String, tagged(tag, h)))

def fp_pick(+rt: Maybe<&2, String>, +creds: String) -> IO(String):
  match rt:
    case Some{t}:
      hashed("sha256:", t)
    case None{}:
      hashed("sha256-full:", creds)

def fp_nonempty(+empty: Bool, +creds: String) -> IO(String):
  match empty:
    case True{}:
      IO.pure(String, "")
    case False{}:
      fp_pick(UCred.refresh_token(UCred.oauth.of(creds)), creds)

# ---- freshen ---------------------------------------------------------------------------------------

# oauth.credential_fingerprint: the refresh token's hash, else the whole
# credential's. "" for an empty credential.
def fingerprint(+creds: String) -> IO(String):
  fp_nonempty(String.is_empty(creds), creds)

def has_oauth(+o: Json.Json) -> Bool:
  match o:
    case Json.JObj{f}:
      True{}
    case _:
      False{}

def rank2(+a: Bool, +b: Bool, +c: Bool, +d: Bool) -> U32:
  match a b c d:
    case True{} _ _ _:
      1
    case False{} True{} _ _:
      2
    case False{} False{} True{} _:
      3
    case False{} False{} False{} True{}:
      4
    case _ _ _ _:
      0

# The deterministic refusals every candidate hits identically (autoswitch.py
# _SYSTEMIC_MESSAGES), most actionable first.
def systemic_rank(+s: String) -> U32:
  rank2(String.eq(s, "store-unmirrored"), String.eq(s, "invalid_client"), String.eq(s, "stash-unreadable"), String.eq(s, "consume-busy"))

def transient_or_systemic(+plain: Bool, +e: String) -> String:
  match plain:
    case True{}:
      "transient"
    case False{}:
      e

def kind_of(+dead: Bool, +e: String) -> String:
  match dead:
    case True{}:
      "invalid_grant"
    case False{}:
      transient_or_systemic(U32.is_eq(systemic_rank(e), 0), e)

def refresh_status(+error: Maybe<&2, String>) -> String:
  match error:
    case None{}:
      "ok"
    case Some{e}:
      kind_of(String.eq(e, "invalid_grant") || String.eq(e, "no_refresh_token"), e)

def judged_grant(+error: Maybe<&2, String>, +root: String, +slot: String, +acct: Json.Json) -> Act.of(String):
  match error:
    case None{}:
      Id.check(root, slot, acct)
    case Some{e}:
      Act.pure(String, refresh_status(Some{e}))

# "ok", "invalid_grant" (a dead credential: quarantine it) or "transient".
def after_refresh(g: UGate.Gated, +root: String, +slot: String) -> Act.of(String):
  match g:
    case UGate.Gated{cred, error, consumed, acct}:
      judged_grant(error, root, slot, acct)

def refresh_now(+root: String, +slot: String, +email: String, +creds: String) -> Act.of(String):
  do ActM<String>:
    g : UGate.Gated <- Act.lift(UGate.Gated, UGate.refresh_gated(slot, email, creds, root))
    after_refresh(g, root, slot)

def check2(+oauth: Bool, +near: Bool, +root: String, +slot: String, +email: String, +creds: String) -> Act.of(String):
  match oauth near:
    case False{} _:
      Act.pure(String, "invalid_grant")
    case True{} True{}:
      refresh_now(root, slot, email, creds)
    case True{} False{}:
      Act.pure(String, "ok")

def check(+root: String, +slot: String, +email: String, +creds: String, +now: U32) -> Act.of(String):
  check2(has_oauth(UCred.oauth.of(creds)), UCred.expired(UCred.oauth.of(creds), (now + 300 : U32)), root, slot, email, creds)

def judge2(+empty: Bool, +root: String, +slot: String, +email: String, +creds: String, +now: U32) -> Act.of(String):
  match empty:
    case True{}:
      Act.pure(String, "transient")
    case False{}:
      check(root, slot, email, creds, now)

def judge(+root: String, +slot: String, +email: String, +creds: String, +now: U32) -> Act.of(String):
  judge2(String.is_empty(creds), root, slot, email, creds, now)

# Ensure a candidate's stored token outlives Claude Code's next minutes: a
# credential within 10 minutes of expiry is refreshed under its consume lock.
def judge4(+live: Bool, +root: String, +slot: String, +email: String, +creds: String, +now: U32) -> Act.of(String):
  Act.cond(String, live, Act.pure(String, "skip-live-session"), judge(root, slot, email, creds, now))

# A Claude session consuming this account owns its token: the daemon leaves it.
def judge5(+root: String, +slot: String, +email: String, +creds: String, +now: U32) -> Act.of(String):
  do ActM<String>:
    live : Bool <- Act.lift(Bool, Sess.live(root, slot, email))
    judge4(live, root, slot, email, creds, now)

def judge3(+api: Bool, +root: String, +slot: String, +email: String, +creds: String, +now: U32) -> Act.of(String):
  Act.cond(String, api, Act.pure(String, "ok"), judge5(root, slot, email, creds, now))

# Ensure a candidate's stored token outlives Claude Code's next minutes: a
# credential within 10 minutes of expiry is refreshed under its consume lock.
# An API key never expires.
def status(+root: String, +slot: String, +email: String, +now: U32) -> Act.of(String):
  do ActM<String>:
    +creds : String <- SIo.read_cred(root, slot, email)
    judge3(SBase.looks_like_api_key(creds), root, slot, email, creds, now)
