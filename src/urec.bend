import Base
import ./pollrow.bend as Pollrow
import ./fs/write.bend as FWrite
import ./json.bend as Json
import ./fs.bend as Fs
import ./act.bend as Act
import ./lock.bend as Lock
import ./poll.bend as Poll
import ./ustore.bend as Ustore

# One finished fetch. kind: 0 success, 1 failure, 2 sentinel (nothing to store
# but the lease). `struck` is the fingerprint of the refresh token the server
# rejected for good (JNull otherwise).
type Rec is Data:
  Rec{id: Ustore.Id, claim: String, kind: U32, usage: Json.Json, error: String, retry: Maybe<&2, U32>, struck: Json.Json, plan: Maybe<&2, Poll.Sched>}

def release(+row: Json.Json) -> Json.Json:
  Json.set("claimUntil", Json.JNum{"0.0"}, Json.set("claimId", Json.JNull{}, row))

def with_plan(m: Maybe<&2, Poll.Sched>, +row: Json.Json) -> Json.Json:
  match m:
    case None{}:
      row
    case Some{Poll.Sched{next, interval}}:
      Json.set("pollIntervalS", Ustore.fl(interval), Json.set("nextPollAt", Ustore.fl(next), row))

def apply_ok(+row: Json.Json, +usage: Json.Json, plan: Maybe<&2, Poll.Sched>, +now: U32) -> Json.Json:
  Json.set("authDeadStrikes", Json.JNum{"0"},
    Json.set("rejectedFingerprint", Json.JNull{},
      Json.set("backoffUntil", Json.JNull{},
        Json.set("lastError", Json.JNull{},
          Json.set("consecutiveFailures", Json.JNum{"0"},
            with_plan(plan, Json.set("fetchedAt", Ustore.fl(now), Json.set("lastGood", usage, Json.set("lastAttemptAt", Ustore.fl(now), release(row))))))))))

def is_permanent(+e: String) -> Bool:
  String.eq(e, "invalid_grant") || String.eq(e, "no_refresh_token")

def with_strike(perm: Bool, +strikes: U32, struck: Json.Json, +row: Json.Json) -> Json.Json:
  match perm:
    case True{}:
      Json.set("struckFingerprint", struck, Json.set("authDeadStrikes", Json.JNum{U32.show((strikes + 1 : U32))}, row))
    case False{}:
      row

def with_429(rl: Bool, +now: U32, +row: Json.Json) -> Json.Json:
  match rl:
    case True{}:
      Json.set("last429At", Ustore.fl(now), row)
    case False{}:
      row

def apply_fail2(+row: Json.Json, +error: String, retry: Maybe<&2, U32>, struck: Json.Json, +failures: U32, +strikes: U32, +now: U32) -> Json.Json:
  with_strike(is_permanent(error), strikes, struck,
    Json.set("backoffUntil", Ustore.fl((now + Pollrow.failure_backoff(failures, retry, String.eq(error, "http-429")) : U32)),
      with_429(String.eq(error, "http-429"), now,
        Json.set("lastError", Ustore.jstr(error), Json.set("consecutiveFailures", Json.JNum{U32.show(failures)},
          Json.set("lastAttemptAt", Ustore.fl(now), release(row)))))))

def apply_fail(+row: Json.Json, +error: String, retry: Maybe<&2, U32>, struck: Json.Json, +now: U32) -> Json.Json:
  apply_fail2(row, error, retry, struck, (Maybe.default(&2, U32, Pollrow.num.field("consecutiveFailures", row), 0) + 1 : U32),
    Maybe.default(&2, U32, Pollrow.num.field("authDeadStrikes", row), 0), now)

def apply_kind2(fail: Bool, +row: Json.Json, +error: String, retry: Maybe<&2, U32>, struck: Json.Json, +now: U32) -> Json.Json:
  match fail:
    case True{}:
      apply_fail(row, error, retry, struck, now)
    case False{}:
      release(row)

def apply_kind.pick(ok: Bool, +kind: U32, +row: Json.Json, +usage: Json.Json, +error: String, retry: Maybe<&2, U32>, struck: Json.Json, plan: Maybe<&2, Poll.Sched>, +now: U32) -> Json.Json:
  match ok:
    case True{}:
      apply_ok(row, usage, plan, now)
    case False{}:
      apply_kind2(U32.is_eq(kind, 1), row, error, retry, struck, now)

def apply_kind(+kind: U32, +row: Json.Json, +usage: Json.Json, +error: String, retry: Maybe<&2, U32>, struck: Json.Json, plan: Maybe<&2, Poll.Sched>, +now: U32) -> Json.Json:
  apply_kind.pick(U32.is_eq(kind, 0), kind, row, usage, error, retry, struck, plan, now)

type RA is Data:
  RA{rows: Json.Json, done: List<&2, String>}

def record.fenced(ok: Bool, +rows: Json.Json, +slot: String, +row: Json.Json, +kind: U32, +usage: Json.Json, +error: String, retry: Maybe<&2, U32>, struck: Json.Json, plan: Maybe<&2, Poll.Sched>, done: List<&2, String>, +now: U32) -> RA:
  match ok:
    case True{}:
      RA{Json.set(slot, apply_kind(kind, row, usage, error, retry, struck, plan, now), rows), slot <> done}
    case False{}:
      RA{rows, done}

def record.apply(m: Maybe<&2, Json.Json>, +rows: Json.Json, +slot: String, +claim: String, +kind: U32, +usage: Json.Json, +error: String, retry: Maybe<&2, U32>, struck: Json.Json, plan: Maybe<&2, Poll.Sched>, done: List<&2, String>, +now: U32) -> RA:
  match m:
    case None{}:
      RA{rows, done}
    case Some{+row}:
      record.fenced(String.eq(Maybe.default(&2, String, Json.as_string(Ustore.jv("claimId", row)), ""), claim), rows, slot, row, kind, usage, error, retry, struck, plan, done, now)

def record.one(+rows: Json.Json, +r: Rec, done: List<&2, String>, +now: U32) -> RA:
  match r:
    case Rec{id, claim, kind, usage, error, retry, struck, plan}:
      record.apply(Ustore.row_of(rows, id), rows, Ustore.slot_of(id), claim, kind, usage, error, retry, struck, plan, done, now)

def record.go(rs: List<&2, Rec>, ra: RA, +now: U32) -> RA:
  match rs ra:
    case Nil{} _:
      ra
    case Con{h, t} RA{+rows, done}:
      record.go(t, record.one(rows, h, done, now), now)

def record.write(done: List<&2, String>, +root: String, +rows: Json.Json) -> Act.of(List<&2, String>):
  match done:
    case Nil{}:
      Act.pure(List<&2, String>, [])
    case Con{h, t}:
      Act.bind(Unit, List<&2, String>, Ustore.write_rows(root, rows), u => Act.pure(List<&2, String>, h <> t))

def record.commit(+root: String, ra: RA) -> Act.of(List<&2, String>):
  match ra:
    case RA{rows, done}:
      record.write(done, root, rows)

def record.act(+root: String, rs: List<&2, Rec>, +now: U32) -> Act.of(List<&2, String>):
  Act.bind(Json.Json, List<&2, String>, Ustore.read_act(root), rows => record.commit(root, record.go(rs, RA{rows, []}, now)))

# Merge outcomes fenced by the leases that produced them: a late writer whose
# lease or identity was replaced is ignored. Success resets the failure
# fields; a failure never touches lastGood and fetchedAt. Returns the slots
# accepted.
def record(+root: String, rs: List<&2, Rec>, +now: U32) -> Act.of(List<&2, String>):
  Ustore.with_usage_lock(List<&2, String>, root, record.act(root, rs, now))

type Reading is Data:
  Reading{id: Ustore.Id, usage: Json.Json, age: U32}

def hold.pick(later: Bool, +held: U32, +row: Json.Json) -> Json.Json:
  match later:
    case True{}:
      Json.set("heldUntil", Ustore.fl(held), row)
    case False{}:
      Json.del("heldUntil", row)

def hold.apply(+held: U32, +now: U32, +row: Json.Json) -> Json.Json:
  hold.pick(U32.is_gt(held, now), held, row)

def hold.reset(m: Maybe<&2, U32>, +held: U32) -> U32:
  match m:
    case Some{r}:
      Poll.min_u(held, r)
    case None{}:
      held

def hold.row(+h: U32, +stored: U32, +now: U32, +row: Json.Json) -> Json.Json:
  hold.apply(hold.reset(Poll.earliest_reset(Poll.relevant(Pollrow.last_good.of(row), ["all"]), None{}), Poll.min_u((now + h : U32), (stored + Poll.trust_ceiling() : U32))), now, row)

def adopt.hold(hold: Maybe<&2, U32>, +stored: U32, +now: U32, +row: Json.Json) -> Json.Json:
  match hold:
    case None{}:
      row
    case Some{h}:
      hold.row(h, stored, now, row)

def adopt.newer(replace: Bool, +usage: Json.Json, +at: U32, stored: Maybe<&2, U32>, hold: Maybe<&2, U32>, +now: U32, +row: Json.Json) -> Ustore.RAd:
  match replace:
    case True{}:
      Ustore.RAd{adopt.hold(hold, at, now, Json.set("fetchedAt", Ustore.fl(at), Json.set("lastGood", usage, row))), True{}}
    case False{}:
      Ustore.RAd{adopt.hold(hold, Maybe.default(&2, U32, stored, at), now, row), False{}}

def is_newer(stored: Maybe<&2, U32>, +at: U32) -> Bool:
  match stored:
    case None{}:
      True{}
    case Some{s}:
      U32.is_gt(at, s)

def adopt.row(+row: Json.Json, +usage: Json.Json, +age: U32, hold: Maybe<&2, U32>, +now: U32) -> Ustore.RAd:
  adopt.newer(is_newer(Pollrow.num.field("fetchedAt", row), Poll.sub0(now, age)), usage, Poll.sub0(now, age), Pollrow.num.field("fetchedAt", row), hold, now, row)

def adopt.stored(m: Maybe<&2, Json.Json>, +id: Ustore.Id) -> Json.Json:
  match m:
    case Some{row}:
      row
    case None{}:
      Ustore.fresh_row(id)

type AR is Data:
  AR{rows: Json.Json, adopted: List<&2, String>, kept: List<&2, String>}

def adopt.sort(yes: Bool, +slot: String, +rows: Json.Json, adopted: List<&2, String>, kept: List<&2, String>) -> AR:
  match yes:
    case True{}:
      AR{rows, slot <> adopted, kept}
    case False{}:
      AR{rows, adopted, slot <> kept}

def adopt.put(+rd: Ustore.RAd, +slot: String, +rows: Json.Json, adopted: List<&2, String>, kept: List<&2, String>) -> AR:
  match rd:
    case Ustore.RAd{row, yes}:
      adopt.sort(yes, slot, Json.set(slot, row, rows), adopted, kept)

def adopt.go(rs: List<&2, Reading>, ar: AR, +hold: Maybe<&2, U32>, +now: U32) -> AR:
  match rs ar:
    case Nil{} _:
      ar
    case Con{Reading{+id, usage, age}, t} AR{+rows, adopted, kept}:
      adopt.go(t, adopt.put(adopt.row(adopt.stored(Ustore.row_of(rows, id), id), usage, age, hold, now), Ustore.slot_of(id), rows, adopted, kept), hold, now)

def adopt.finish(+root: String, ar: AR) -> Act.of(AR):
  match ar:
    case AR{+rows, adopted, kept}:
      Act.bind(Unit, AR, Ustore.write_rows(root, rows), u => Act.pure(AR, AR{rows, adopted, kept}))

def adopt.act(+root: String, rs: List<&2, Reading>, hold: Maybe<&2, U32>, +now: U32) -> Act.of(AR):
  Act.bind(Json.Json, AR, Ustore.read_act(root), rows => adopt.finish(root, adopt.go(rs, AR{rows, [], []}, hold, now)))

# Merge measurements another machine took (UsageStore.adopt): a reading
# replaces lastGood only when newer than the stored one; `hold` (seconds)
# keeps collectors off the slot, never past the reading's earliest window
# reset nor an hour past the stored measurement; Some{0} lifts a hold.
def adopt(+root: String, rs: List<&2, Reading>, hold: Maybe<&2, U32>, +now: U32) -> Act.of(AR):
  Ustore.with_usage_lock(AR, root, adopt.act(root, rs, hold, now))

def cleared(+row: Json.Json) -> Json.Json:
  Json.set("backoffUntil", Json.JNull{}, Json.set("lastError", Json.JNull{}, Json.set("consecutiveFailures", Json.JNum{"0"},
    Json.set("struckFingerprint", Json.JNull{}, Json.set("authDeadStrikes", Json.JNum{"0"}, release(row))))))

def clear.row(m: Maybe<&2, Json.Json>, +rows: Json.Json, +id: Ustore.Id) -> Json.Json:
  match m:
    case Some{row}:
      Json.set(Ustore.slot_of(id), cleared(row), rows)
    case None{}:
      Json.set(Ustore.slot_of(id), cleared(Ustore.fresh_row(id)), rows)

def clear.go(ids: List<&2, Ustore.Id>, +rows: Json.Json) -> Json.Json:
  match ids:
    case Nil{}:
      rows
    case Con{+id, t}:
      clear.go(t, clear.row(Ustore.row_of(rows, id), rows, id))

def clear.act(+root: String, ids: List<&2, Ustore.Id>) -> Act.of(Unit):
  Act.bind(Json.Json, Unit, Ustore.read_act(root), rows => Ustore.write_rows(root, clear.go(ids, rows)))

# Lift the dead-token quarantine of slots whose credential was replaced.
def clear_dead(+root: String, ids: List<&2, Ustore.Id>) -> Act.of(Unit):
  Ustore.with_usage_lock(Unit, root, clear.act(root, ids))

