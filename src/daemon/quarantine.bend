import Base
import ../json.bend as Json
import ../act.bend as Act
import ../store/io.bend as SIo
import ./events.bend as Ev
import ./state.bend as St
import ./freshen.bend as Fr

# Accounts whose refresh token is dead sit in autoswitch_state.json's
# quarantine until the user logs in again (autoswitch.py _quarantine and
# _release_recovered_quarantines).

type Rel is Data:
  Rel{slot: String, email: String, reason: String}

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def fp_opt2(+empty: Bool, +fp: String) -> Maybe<&2, String>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Some{fp}

def fp_opt(+fp: String) -> Maybe<&2, String>:
  fp_opt2(String.is_empty(fp), fp)

def write_q(+root: String, +slot: String, +email: String, +reason: String, +ts: String, +fp: String) -> Act.of(Unit):
  St.with_state_lock(Unit, root,
    do ActM<Unit>:
      st : Json.Json <- Act.lift(Json.Json, St.read_state(root))
      St.write_state(root, St.quarantine(st, slot, email, reason, ts, fp_opt(fp))))

# Put an account in quarantine (stored with the fingerprint of the credential
# that died) and answer the event.
def quarantine(+root: String, +slot: String, +email: String, +reason: String, +ts: String) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    creds : String <- SIo.read_cred(root, slot, email)
    fp : String <- Act.lift(String, Fr.fingerprint(creds))
    write_q(root, slot, email, reason, ts, fp)
    return Ev.quarantined(ts, slot, email, reason)

# ---- release ---------------------------------------------------------------------------------------------

def keep(+m: Maybe<&2, Rel>, +rest: List<&2, Rel>) -> List<&2, Rel>:
  match m:
    case Some{r}:
      r <> rest
    case None{}:
      rest

def replaced(+slot: String, +entry_email: String) -> Maybe<&2, Rel>:
  Some{Rel{slot, entry_email, "account-replaced"}}

def changed(+differs: Bool, +slot: String, +email: String) -> Maybe<&2, Rel>:
  match differs:
    case True{}:
      Some{Rel{slot, email, "credentials-replaced"}}
    case False{}:
      None{}

def opt_eq(+a: Maybe<&2, String>, +b: Maybe<&2, String>) -> Bool:
  match a b:
    case None{} None{}:
      True{}
    case Some{x} Some{y}:
      String.eq(x, y)
    case _ _:
      False{}

def fp_differs(+entry: Maybe<&2, String>, +fp: String) -> Bool:
  Bool.not(opt_eq(entry, fp_opt(fp)))

def gone(+email_now: String, +entry_email: String) -> Bool:
  String.is_empty(email_now) || Bool.not(String.eq(email_now, entry_email))

def compare_fp(+root: String, +st: Json.Json, +slot: String, +email_now: String) -> Act.of(Maybe<&2, Rel>):
  do ActM<Maybe<&2, Rel>>:
    creds : String <- SIo.read_cred(root, slot, email_now)
    fp : String <- Act.lift(String, Fr.fingerprint(creds))
    return changed(fp_differs(St.entry_fp(st, slot), fp), slot, email_now)

def check_slot(+root: String, +seq: Json.Json, +st: Json.Json, +slot: String) -> Act.of(Maybe<&2, Rel>):
  Act.cond(Maybe<&2, Rel>, gone(SIo.slot_email(seq, slot), St.entry_email(st, slot)),
    Act.pure(Maybe<&2, Rel>, replaced(slot, St.entry_email(st, slot))),
    compare_fp(root, st, slot, SIo.slot_email(seq, slot)))

def rels(+root: String, +seq: Json.Json, +st: Json.Json, +slots: List<&2, String>) -> Act.of(List<&2, Rel>):
  match slots:
    case Nil{}:
      Act.pure(List<&2, Rel>, [])
    case Con{s, t}:
      do ActM<List<&2, Rel>>:
        m : Maybe<&2, Rel> <- check_slot(root, seq, st, s)
        rest : List<&2, Rel> <- rels(root, seq, st, t)
        return keep(m, rest)

def drop_all(+rs: List<&2, Rel>, +st: Json.Json) -> Json.Json:
  match rs:
    case Nil{}:
      st
    case Con{Rel{s, e, r}, t}:
      drop_all(t, St.release(st, s))

def events_of(+ts: String, +rs: List<&2, Rel>) -> List<&2, Json.Json>:
  match rs:
    case Nil{}:
      []
    case Con{Rel{s, e, r}, t}:
      Ev.unquarantined(ts, s, e, r) <> events_of(ts, t)

def write_released(+root: String, +rs: List<&2, Rel>) -> Act.of(Unit):
  St.with_state_lock(Unit, root,
    do ActM<Unit>:
      st : Json.Json <- Act.lift(Json.Json, St.read_state(root))
      St.write_state(root, drop_all(rs, st)))

def release_events(+root: String, +rs: List<&2, Rel>, +ts: String) -> Act.of(List<&2, Json.Json>):
  match rs:
    case Nil{}:
      Act.pure(List<&2, Json.Json>, [])
    case Con{r, t}:
      do ActM<List<&2, Json.Json>>:
        write_released(root, Con{r, t})
        return events_of(ts, Con{r, t})

# Lift the quarantine of an account whose email or credential changed since
# it was quarantined (the user logged in again); answer the events.
def release_recovered(+root: String, +seq: Json.Json, +ts: String) -> Act.of(List<&2, Json.Json>):
  do ActM<List<&2, Json.Json>>:
    +st : Json.Json <- Act.lift(Json.Json, St.read_state(root))
    rs : List<&2, Rel> <- rels(root, seq, st, St.quarantined_slots(st))
    release_events(root, rs, ts)
