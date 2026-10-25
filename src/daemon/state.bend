import Base
import ../json.bend as Json
import ../fs.bend as Fs
import ../fs/write.bend as FsW
import ../act.bend as Act
import ../lock.bend as Lock
import ../store.bend as Store
import ../store/base.bend as SBase
import ../store/seq.bend as SSeq

# autoswitch_state.json (contract 1.7): the last switch, the account it left,
# and the quarantine of accounts whose refresh token is dead. Read lock-free,
# written read-modify-write under <root>/.autoswitch_state.lock, unknown keys
# kept. `--dry-run` never writes it.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def state_path(+root: String) -> String:
  root ++ "/autoswitch_state.json"

def lock_path(+root: String) -> String:
  root ++ "/.autoswitch_state.lock"

def empty() -> Json.Json:
  Json.JObj{Json.JNil{}}

def obj_or_empty(+j: Json.Json) -> Json.Json:
  match j:
    case Json.JObj{f}:
      j
    case _:
      empty()

def parsed(r: Result<&2, &2, String, Json.Json>) -> Json.Json:
  match r:
    case Done{j}:
      obj_or_empty(j)
    case Fail{e}:
      empty()

def read2(r: Fs.Res(String)) -> Json.Json:
  match r:
    case Done{t}:
      parsed(Json.parse(t))
    case Fail{e}:
      empty()

# The state object; {} when the file is missing, torn or not an object.
def read_state(+root: String) -> IO(Json.Json):
  IO.bind(Fs.Res(String), Json.Json, Fs.read_file(state_path(root)), r => IO.pure(Json.Json, read2(r)))

def write_state(+root: String, +j: Json.Json) -> Act.of(Unit):
  FsW.write_atomic(state_path(root), Json.emit_pretty(j), "600")

# Hold the state lock around `act`.
def with_state_lock(-A: Type, +root: String, act: Act.of(A)) -> Act.of(A):
  Lock.with_lock(A, lock_path(root), 10000, act)

# ---- the last switch --------------------------------------------------------------------------

def fl(+t: U32) -> Json.Json:
  Json.JNum{U32.show(t) ++ ".0"}

def opt(+m: Maybe<&2, U32>, f: U32 -> Json.Json) -> Json.Json:
  match m:
    case None{}:
      Json.JNull{}
    case Some{v}:
      f(v)

def two(+n: U32) -> String:
  SBase.sel.s(U32.is_lt(n, 10), "0" ++ U32.show(n), U32.show(n))

def frac(+c: U32) -> String:
  SBase.sel.s(U32.is_eq((c % 10 : U32), 0), U32.show((c / 10 : U32)), two(c))

def cents_json(+c: U32) -> Json.Json:
  Json.JNum{U32.show((c / 100 : U32)) ++ "." ++ frac((c % 100 : U32))}

def int_json(+n: U32) -> Json.Json:
  Json.JNum{U32.show(n)}

# What `_perform` records after a switch. `left_headroom` is centi-percent,
# `left_recovery` unix seconds (None for the reference's inf).
def record_switch(+st: Json.Json, +now: U32, +to: String, +from: Maybe<&2, U32>, +left_headroom: Maybe<&2, U32>, +left_recovery: Maybe<&2, U32>, +trigger: String) -> Json.Json:
  Json.set("leftTrigger", Json.JStr{trigger},
  Json.set("leftRecoveryAt", opt(left_recovery, u => fl(u)),
  Json.set("leftHeadroom", opt(left_headroom, h => cents_json(h)),
  Json.set("lastSwitchFrom", opt(from, n => int_json(n)),
  Json.set("lastSwitchTo", Json.JStr{to},
  Json.set("lastSwitchAt", fl(now),
  Json.set("schemaVersion", Json.JNum{"1"}, obj_or_empty(st))))))))

# ---- quarantine ------------------------------------------------------------------------------

def quarantine_of(+st: Json.Json) -> Json.Json:
  obj_or_empty(SSeq.get_or("quarantine", st, empty()))

def opt_text(+m: Maybe<&2, String>) -> Json.Json:
  match m:
    case None{}:
      Json.JNull{}
    case Some{s}:
      Json.JStr{s}

def entry(+email: String, +reason: String, +at: String, +fp: Maybe<&2, String>) -> Json.Json:
  Json.JObj{Json.JField{"email", Json.JStr{email}, Json.JField{"reason", Json.JStr{reason}, Json.JField{"at", Json.JStr{at},
    Json.JField{"refreshTokenFingerprint", opt_text(fp), Json.JNil{}}}}}}

def quarantine(+st: Json.Json, +slot: String, +email: String, +reason: String, +at: String, +fp: Maybe<&2, String>) -> Json.Json:
  Json.set("quarantine", Json.set(slot, entry(email, reason, at, fp), quarantine_of(st)), Json.set("schemaVersion", Json.JNum{"1"}, obj_or_empty(st)))

def release(+st: Json.Json, +slot: String) -> Json.Json:
  Json.set("quarantine", Json.del(slot, quarantine_of(st)), Json.set("schemaVersion", Json.JNum{"1"}, obj_or_empty(st)))

def quarantined_slots(+st: Json.Json) -> List<&2, String>:
  Json.keys(quarantine_of(st))

def entry_email(+st: Json.Json, +slot: String) -> String:
  SSeq.field_str(SSeq.get_or(slot, quarantine_of(st), Json.JNull{}), "email")

def entry_fp2(+m: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match m:
    case Some{Json.JStr{s}}:
      Some{s}
    case _:
      None{}

def entry_fp(+st: Json.Json, +slot: String) -> Maybe<&2, String>:
  entry_fp2(Json.get("refreshTokenFingerprint", SSeq.get_or(slot, quarantine_of(st), Json.JNull{})))

def first_part(+t: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, String.split(t, '.')), "")

def last2(+m: Maybe<&2, Json.Json>) -> Maybe<&2, U32>:
  match m:
    case Some{Json.JNum{t}}:
      U32.read(first_part(t))
    case _:
      None{}

# lastSwitchAt as seconds, None when absent or not a number.
def last_switch_at(+st: Json.Json) -> Maybe<&2, U32>:
  last2(Json.get("lastSwitchAt", st))

def cool2(+m: Maybe<&2, U32>, +now: U32, +cooldown: U32) -> Bool:
  match m:
    case Some{l}:
      U32.is_lt((now - l : U32), cooldown)
    case None{}:
      False{}

# `now - lastSwitchAt < cooldown`
def in_cooldown(+st: Json.Json, +now: U32, +cooldown: U32) -> Bool:
  cool2(last_switch_at(st), now, cooldown)
