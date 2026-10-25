import Base
import ./pollrow.bend as Pollrow
import ./fs/write.bend as FWrite
import ./json.bend as Json
import ./fs.bend as Fs
import ./act.bend as Act
import ./lock.bend as Lock
import ./poll.bend as Poll

# API (also the daemon's usage store; do not copy it):
#   read_rows(root) -> IO(Json)          the accounts object; empty for a missing/torn/other-version file
#   row_of(rows, Id) -> Maybe<Json>      the row, only when it belongs to this (email, org) identity
#   reserve(root, ids, now, respect, repair, tick) -> Act(List<Claim>)   win the right to fetch (90 s lease)
#   record(root, recs, now) -> Act(List<slot>)   merge outcomes fenced by their lease (success, failure, sentinel)
#   adopt(root, readings, hold, now) -> Act(AR)  merge another machine's readings, with an optional hold
#   clear_dead(root, ids) -> Act(Unit)           reset a slot's row after its credential was replaced
# Every write is read-modify-write under <root>/cache/.usage.lock; no network call runs under it.
#
# cache/usage.json (usage_store.py): rows keyed by slot, guarded by the
# slot's (email, organizationUuid), read lock-free and written as
# read-modify-write under cache/.usage.lock. No network call runs under the
# lock: reserve() leases the rows, the caller fetches, record() merges what
# the lease still covers.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def usage_path(+root: String) -> String:
  root ++ "/cache/usage.json"

def usage_lock(+root: String) -> String:
  root ++ "/cache/.usage.lock"

# The identity a slot number currently maps to.
type Id is Data:
  Id{slot: String, email: String, org: String}

# A fetch lease: the slot and its fencing id.
type Claim is Data:
  Claim{slot: String, id: String}

def jv(+k: String, +j: Json.Json) -> Json.Json:
  Maybe.default(&2, Json.Json, Json.get(k, j), Json.JNull{})

def jstr(s: String) -> Json.Json:
  Json.JStr{s}

# An epoch as the reference stores it: a float.
def fl(+t: U32) -> Json.Json:
  Json.JNum{U32.show(t) ++ ".0"}

def empty_rows() -> Json.Json:
  Json.of_pairs([])

def obj_or_empty(j: Json.Json) -> Json.Json:
  match j:
    case Json.JObj{f}:
      Json.JObj{f}
    case _:
      empty_rows()

def rows.pick(ok: Bool, +j: Json.Json) -> Json.Json:
  match ok:
    case True{}:
      obj_or_empty(jv("accounts", j))
    case False{}:
      empty_rows()

def is_v2(j: Json.Json) -> Bool:
  match j:
    case Json.JNum{t}:
      String.eq(t, "2")
    case _:
      False{}

# The accounts object of a parsed usage.json; empty for any other schema.
def rows_of(+j: Json.Json) -> Json.Json:
  rows.pick(is_v2(jv("schemaVersion", j)), j)

def rows.parsed(r: Result<&2, &2, String, Json.Json>) -> Json.Json:
  match r:
    case Fail{e}:
      empty_rows()
    case Done{j}:
      rows_of(j)

def rows.text(r: Fs.Res(String)) -> Json.Json:
  match r:
    case Fail{e}:
      empty_rows()
    case Done{t}:
      rows.parsed(Json.parse(t))

# A missing, torn or other-version file reads as empty.
def read_rows(+root: String) -> IO(Json.Json):
  IO.bind(Fs.Res(String), Json.Json, Fs.read_file(usage_path(root)), r => IO.pure(Json.Json, rows.text(r)))

def matches(+row: Json.Json, +id: Id) -> Bool:
  match id:
    case Id{slot, email, org}:
      String.eq(Maybe.default(&2, String, Json.as_string(jv("email", row)), "\u{1}"), email)
        && String.eq(Maybe.default(&2, String, Json.as_string(Maybe.default(&2, Json.Json, Json.get("organizationUuid", row), Json.JStr{""})), "\u{1}"), org)

def fresh_row(+id: Id) -> Json.Json:
  match id:
    case Id{slot, email, org}:
      Json.of_pairs([("email", jstr(email)), ("organizationUuid", jstr(org))])

def row.if(ok: Bool, +row: Json.Json) -> Maybe<&2, Json.Json>:
  match ok:
    case True{}:
      Some{row}
    case False{}:
      None{}

def row.pick(m: Maybe<&2, Json.Json>, +id: Id) -> Maybe<&2, Json.Json>:
  match m:
    case None{}:
      None{}
    case Some{+row}:
      row.if(matches(row, id), row)

# The stored row of a slot, only when it belongs to this identity.
def row_of(+rows: Json.Json, +id: Id) -> Maybe<&2, Json.Json>:
  match id:
    case Id{slot, email, org}:
      row.pick(Json.get(slot, rows), id)

def write_rows(+root: String, +rows: Json.Json) -> Act.of(Unit):
  do ActM<Unit>:
    FWrite.mkdir_p(root ++ "/cache")
    FWrite.write_atomic(usage_path(root), Json.emit_pretty(Json.of_pairs([("schemaVersion", Json.JNum{"2"}), ("accounts", rows)])), "600")

def with_usage_lock(-A: Type, +root: String, act: Act.of(A)) -> Act.of(A):
  Lock.with_lock(A, usage_lock(root), 10000, act)

def read_act(+root: String) -> Act.of(Json.Json):
  Act.lift(Json.Json, read_rows(root))

type RR is Data:
  RR{rows: Json.Json, won: List<&2, Claim>}

def claim_row(+row: Json.Json, +claim: String, +now: U32) -> Json.Json:
  Json.set("claimUntil", fl((now + Poll.claim_ttl() : U32)), Json.set("claimId", jstr(claim), Json.set("lastAttemptAt", fl(now), row)))

def reserve.take(+rows: Json.Json, +id: Id, +row: Json.Json, +claim: String, +now: U32, won: List<&2, Claim>) -> RR:
  match id:
    case Id{slot, email, org}:
      RR{Json.set(slot, claim_row(row, claim, now), rows), Claim{slot, claim} <> won}

def reserve.fresh(+rows: Json.Json, +id: Id, +claim: String, +now: U32, won: List<&2, Claim>) -> RR:
  reserve.take(rows, id, fresh_row(id), claim, now, won)

def reserve.stored(ok: Bool, +rows: Json.Json, +id: Id, +row: Json.Json, +claim: String, +now: U32, won: List<&2, Claim>) -> RR:
  match ok:
    case True{}:
      reserve.take(rows, id, row, claim, now, won)
    case False{}:
      RR{rows, won}

def reserve.row(m: Maybe<&2, Json.Json>, +rows: Json.Json, +id: Id, +claim: String, +now: U32, +respect: Bool, +repair: Bool, won: List<&2, Claim>) -> RR:
  match m:
    case None{}:
      reserve.fresh(rows, id, claim, now, won)
    case Some{+row}:
      reserve.stored(Pollrow.row_eligible(Pollrow.row.of(row), now, respect, repair), rows, id, row, claim, now, won)

def claim_id(+slot: String, +now: U32, +tick: Nat) -> String:
  "c" ++ U32.show(now) ++ "-" ++ slot ++ "-" ++ Nat.show(tick)

def slot_of(+id: Id) -> String:
  match id:
    case Id{slot, email, org}:
      slot

def reserve.go(ids: List<&2, Id>, rr: RR, +now: U32, +respect: Bool, +repair: Bool, +tick: Nat) -> RR:
  match ids rr:
    case Nil{} _:
      rr
    case Con{+id, t} RR{+rows, won}:
      reserve.go(t, reserve.row(row_of(rows, id), rows, id, claim_id(slot_of(id), now, tick), now, respect, repair, won), now, respect, repair, 1n+tick)

def reserve.write(won: List<&2, Claim>, +root: String, +rows: Json.Json) -> Act.of(List<&2, Claim>):
  match won:
    case Nil{}:
      Act.pure(List<&2, Claim>, [])
    case Con{h, t}:
      Act.bind(Unit, List<&2, Claim>, write_rows(root, rows), u => Act.pure(List<&2, Claim>, h <> t))

def reserve.commit(+root: String, rr: RR) -> Act.of(List<&2, Claim>):
  match rr:
    case RR{rows, won}:
      reserve.write(won, root, rows)

def reserve.act(+root: String, ids: List<&2, Id>, +now: U32, +respect: Bool, +repair: Bool, +tick: Nat) -> Act.of(List<&2, Claim>):
  Act.bind(Json.Json, List<&2, Claim>, read_act(root), rows => reserve.commit(root, reserve.go(ids, RR{rows, []}, now, respect, repair, tick)))

# Atomically win the right to fetch: re-check each slot's eligibility and
# stamp a 90 s lease under the lock (UsageStore.reserve). `respect` is the
# on-demand mode (stale AND poll-due), `repair` also frees a reset-parked plan.
def reserve(+root: String, ids: List<&2, Id>, +now: U32, +respect: Bool, +repair: Bool, +tick: Nat) -> Act.of(List<&2, Claim>):
  with_usage_lock(List<&2, Claim>, root, reserve.act(root, ids, now, respect, repair, tick))

type RAd is Data:
  RAd{row: Json.Json, adopted: Bool}
