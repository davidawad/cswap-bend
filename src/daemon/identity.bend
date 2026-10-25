import Base
import ../json.bend as Json
import ../act.bend as Act
import ../fs.bend as Fs
import ../lock.bend as Lock
import ../store/base.bend as SBase
import ../store/seq.bend as SSeq
import ../store/io.bend as SIo

# autoswitch.py _note_token_identity: the refresh grant that just ran names who
# the stored credential really is. A slot whose credential belongs to another
# organization or account is not a safe target (identity-conflict); a slot with
# no recorded account uuid learns it (never an existing one, and not when the
# organization already disagrees).

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def str_of(+j: Json.Json, +k: String) -> String:
  String.trim(SSeq.field_str(j, k))

def rec_of(+m: Maybe<&2, Json.Json>, +slot: String) -> Json.Json:
  match m:
    case None{}:
      Json.JObj{Json.JNil{}}
    case Some{seq}:
      Maybe.default(&2, Json.Json, SSeq.slot_record(seq, slot), Json.JObj{Json.JNil{}})

def fill2(+empty: Bool, +seq: Json.Json, +slot: String, +uuid: String, +ts: String) -> Json.Json:
  match empty:
    case False{}:
      seq
    case True{}:
      SSeq.stamp(Json.set("accounts", Json.set(slot, Json.set("uuid", Json.JStr{uuid}, Maybe.default(&2, Json.Json, SSeq.slot_record(seq, slot), Json.JObj{Json.JNil{}})), SSeq.accounts_of(seq)), seq), ts)

# Fill an empty uuid, once, under the roster lock (switcher.backfill_account_uuid).
def fill(+seq: Json.Json, +slot: String, +uuid: String, +ts: String) -> Json.Json:
  fill2(String.is_empty(str_of(Maybe.default(&2, Json.Json, SSeq.slot_record(seq, slot), Json.JObj{Json.JNil{}}), "uuid")), seq, slot, uuid, ts)

def fill_with(+m: Maybe<&2, Json.Json>, +root: String, +slot: String, +uuid: String, +ts: String) -> Act.of(Unit):
  match m:
    case None{}:
      Act.pure(Unit, Unit{})
    case Some{seq}:
      SIo.write_seq(root, fill(seq, slot, uuid, ts))

def backfill_locked(+root: String, +slot: String, +uuid: String) -> Act.of(Unit):
  do ActM<Unit>:
    ts : String <- SIo.now_iso()
    m : Maybe<&2, Json.Json> <- SIo.read_seq(root)
    fill_with(m, root, slot, uuid, ts)

def backfill(+root: String, +slot: String, +uuid: String) -> Act.of(Unit):
  Lock.with_lock(Unit, SBase.lock_path(root), 10000, backfill_locked(root, slot, uuid))

def org_differs(+ta_org: String, +slot_org: String) -> Bool:
  Bool.not(String.is_empty(ta_org)) && Bool.not(String.is_empty(slot_org)) && Bool.not(String.eq(ta_org, slot_org))

def verdict(+conflict: Bool) -> String:
  match conflict:
    case True{}:
      "identity-conflict"
    case False{}:
      "ok"

def swallow(r: Fs.Res(Unit)) -> Act.of(Unit):
  Act.pure(Unit, Unit{})

def best_effort(m: Act.of(Unit)) -> Act.of(Unit):
  IO.bind(Fs.Res(Unit), Fs.Res(Unit), m, r => swallow(r))

def learned(+root: String, +slot: String, +ta_uuid: String) -> Act.of(String):
  do ActM<String>:
    best_effort(backfill(root, slot, ta_uuid))
    return "ok"

def learn2(+empty: Bool, +slot_uuid: String, +root: String, +slot: String, +ta_uuid: String) -> Act.of(String):
  match empty:
    case True{}:
      learned(root, slot, ta_uuid)
    case False{}:
      Act.pure(String, verdict(Bool.not(String.eq(slot_uuid, ta_uuid))))

def learn(+slot_uuid: String, +root: String, +slot: String, +ta_uuid: String) -> Act.of(String):
  learn2(String.is_empty(slot_uuid), slot_uuid, root, slot, ta_uuid)

def judged2(+conflict: Bool, +root: String, +slot: String, +ta_uuid: String, +rec: Json.Json) -> Act.of(String):
  match conflict:
    case True{}:
      Act.pure(String, "identity-conflict")
    case False{}:
      learn(str_of(rec, "uuid"), root, slot, ta_uuid)

def judged(+root: String, +slot: String, +ta_uuid: String, +ta_org: String, +rec: Json.Json) -> Act.of(String):
  judged2(org_differs(ta_org, str_of(rec, "organizationUuid")), root, slot, ta_uuid, rec)

def judged_in(+root: String, +slot: String, +ta_uuid: String, +ta_org: String, +m: Maybe<&2, Json.Json>) -> Act.of(String):
  judged(root, slot, ta_uuid, ta_org, rec_of(m, slot))

def known(+root: String, +slot: String, +ta_uuid: String, +ta_org: String) -> Act.of(String):
  do ActM<String>:
    m : Maybe<&2, Json.Json> <- SIo.read_seq(root)
    judged_in(root, slot, ta_uuid, ta_org, m)

def with_uuid(+empty: Bool, +root: String, +slot: String, +ta_uuid: String, +ta_org: String) -> Act.of(String):
  match empty:
    case True{}:
      Act.pure(String, "ok")
    case False{}:
      known(root, slot, ta_uuid, ta_org)

# "ok" or "identity-conflict" for the account the token endpoint named
# (JNull when it named none).
def check(+root: String, +slot: String, +acct: Json.Json) -> Act.of(String):
  with_uuid(String.is_empty(str_of(acct, "uuid")), root, slot, str_of(acct, "uuid"), str_of(acct, "organizationUuid"))
