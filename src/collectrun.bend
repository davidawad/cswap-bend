import Base
import ./store/base.bend as SBase
import ./urec.bend as Urec
import ./pollrow.bend as Pollrow
import ./usage/cred.bend as UCred
import ./json.bend as Json
import ./clock.bend as Clock
import ./act.bend as Act
import ./poll.bend as Poll
import ./ustore.bend as Ustore
import ./usage.bend as Usage
import ./view.bend as View
import ./collect.bend as Collect

def claim.pick(hit: Bool, id: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{id}
    case False{}:
      rest

def claim_of(cs: List<&2, Ustore.Claim>, +slot: String) -> Maybe<&2, String>:
  match cs:
    case Nil{}:
      None{}
    case Con{Ustore.Claim{s, id}, t}:
      claim.pick(String.eq(s, slot), id, claim_of(t, slot))

def struck_json(m: Maybe<&2, String>) -> IO(Json.Json):
  match m:
    case None{}:
      IO.pure(Json.Json, Json.JNull{})
    case Some{cred}:
      IO.bind(String, Json.Json, Collect.fingerprint(cred), f => IO.pure(Json.Json, Json.JStr{f}))

def run_fetch(active: Bool, +creds: String, +slot: String, +email: String, +root: String) -> IO(Usage.Fetched):
  match active:
    case True{}:
      Usage.fetch_usage(creds, True{})
    case False{}:
      Usage.fetch_usage_gated(creds, False{}, slot, email, root)

def rec.ok2(+id: Ustore.Id, +claim: String, +usage: Json.Json, active: Bool, +plan: Poll.Sched) -> Urec.Rec:
  Urec.Rec{id, claim, 0, usage, "", None{}, Json.JNull{}, Some{plan}}

def rec.ok(+r: Pollrow.Row, +id: Ustore.Id, +claim: String, +usage: Json.Json, +active: Bool, +models: List<&2, String>, +threshold: U32, +now: U32) -> Urec.Rec:
  match r:
    case Pollrow.Row{fetched, lg, la, fl, le, bu, np, iv, l429, st, sfp, cu, hu}:
      rec.ok2(id, claim, usage, active, Poll.plan_after_fetch(iv, lg, usage, active, threshold, models, Pollrow.recent_429(r, now), now))

def rec.err(error: Maybe<&2, String>, retry: Maybe<&2, U32>, struck: Json.Json, ok: Urec.Rec, +id: Ustore.Id, +claim: String) -> Urec.Rec:
  match error:
    case None{}:
      ok
    case Some{e}:
      Urec.Rec{id, claim, 1, Json.JNull{}, e, retry, struck, None{}}

def rec.of(o: Usage.Outcome, +id: Ustore.Id, +claim: String, +row: Json.Json, +active: Bool, +models: List<&2, String>, +threshold: U32, +now: U32, struck: Json.Json) -> Urec.Rec:
  match o:
    case Usage.Outcome{usage, error, retry, st}:
      rec.err(error, retry, struck, rec.ok(Pollrow.row.of(row), id, claim, usage, active, models, threshold, now), id, claim)

def outcome_struck(o: Usage.Outcome) -> Maybe<&2, String>:
  match o:
    case Usage.Outcome{usage, error, retry, st}:
      st

def rec.fetched(f: Usage.Fetched, +id: Ustore.Id, +claim: String, +row: Json.Json, +active: Bool, +models: List<&2, String>, +threshold: U32, +now: U32) -> IO(Urec.Rec):
  match f:
    case Usage.Fetched{+o, cred}:
      IO.bind(Json.Json, Urec.Rec, struck_json(outcome_struck(o)), sj => IO.pure(Urec.Rec, rec.of(o, id, claim, row, active, models, threshold, now, sj)))

def fetch_info(+info: Collect.Info, +row: Json.Json, +claim: String, +root: String, +models: List<&2, String>, +threshold: U32, +now: U32) -> IO(Urec.Rec):
  match info:
    case Collect.Info{num, email, org_name, org_uuid, alias, disabled, active, creds}:
      IO.bind(Usage.Fetched, Urec.Rec, run_fetch(active, creds, U32.show(num), email, root),
        f => rec.fetched(f, Ustore.Id{U32.show(num), email, org_uuid}, claim, row, active, models, threshold, now))

def fetch_st(+st: Collect.St, +claim: String, +root: String, +models: List<&2, String>, +threshold: U32, +now: U32) -> IO(Urec.Rec):
  match st:
    case Collect.St{info, row, sentinel, healed}:
      fetch_info(info, row, claim, root, models, threshold, now)

# A state with the lease it won, if any.
type Job is Data:
  Job{st: Collect.St, claim: Maybe<&2, String>}

def jobs(ss: List<&2, Collect.St>, +cs: List<&2, Ustore.Claim>) -> List<&2, Job>:
  match ss:
    case Nil{}:
      []
    case Con{+h, t}:
      Job{h, claim_of(cs, Collect.st_slot(h))} <> jobs(t, cs)

def fetch_all(js: List<&2, Job>, +root: String, +models: List<&2, String>, +threshold: U32, +now: U32) -> IO(List<&2, Urec.Rec>):
  match js:
    case Nil{}:
      IO.pure(List<&2, Urec.Rec>, [])
    case Con{Job{st, None{}}, t}:
      fetch_all(t, root, models, threshold, now)
    case Con{Job{st, Some{claim}}, t}:
      IO.bind(Urec.Rec, List<&2, Urec.Rec>, fetch_st(st, claim, root, models, threshold, now),
        r => IO.bind(List<&2, Urec.Rec>, List<&2, Urec.Rec>, fetch_all(t, root, models, threshold, now), rest => IO.pure(List<&2, Urec.Rec>, r <> rest)))

def healed.cons(h: Bool, +id: Ustore.Id, rest: List<&2, Ustore.Id>) -> List<&2, Ustore.Id>:
  match h:
    case True{}:
      id <> rest
    case False{}:
      rest

def fetchable.cons(ok: Bool, +id: Ustore.Id, rest: List<&2, Ustore.Id>) -> List<&2, Ustore.Id>:
  match ok:
    case True{}:
      id <> rest
    case False{}:
      rest

# Slots with nothing that rules out a fetch.
def fetchable(ss: List<&2, Collect.St>) -> List<&2, Ustore.Id>:
  match ss:
    case Nil{}:
      []
    case Con{+s, t}:
      fetchable.cons(Maybe.is_none(&2, String, Collect.st_sentinel(s)), Collect.st_id(s), fetchable(t))

def clear_if(+root: String, ids: List<&2, Ustore.Id>) -> Act.of(Unit):
  match ids:
    case Nil{}:
      Act.pure(Unit, Unit{})
    case Con{h, t}:
      Urec.clear_dead(root, h <> t)

def login_secs(+d: String) -> Maybe<&2, String>:
  Maybe.bind(&2, U32, String, U32.read(String.take(d, Nat.sub(String.length(d), 3n))), t => Some{Clock.iso8601_utc(t)})

def login.pick(ok: Bool, +i: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      login_secs(i)
    case False{}:
      None{}

def login.int(ps: List<&2, String>) -> Maybe<&2, String>:
  match ps:
    case Con{+i, t}:
      login.pick(Clock.all_digits(i) && Nat.is_gt(String.length(i), 3n), i)
    case Nil{}:
      None{}

def login.num(j: Json.Json) -> Maybe<&2, String>:
  match j:
    case Json.JNum{t}:
      login.int(String.split(t, '.'))
    case _:
      None{}

# oauth.login_expires_at_iso: refreshTokenExpiresAt (epoch ms) as ISO, when the
# stored login records one.
def login_expires(+creds: String) -> Maybe<&2, String>:
  login.num(Pollrow.jget("refreshTokenExpiresAt", UCred.oauth.of(creds)))

def acct.info(+info: Collect.Info, +row: Json.Json, sentinel: Maybe<&2, String>) -> View.Acct:
  match info:
    case Collect.Info{num, email, org_name, org_uuid, alias, disabled, active, creds}:
      View.Acct{num, email, org_name, org_uuid, active, alias, disabled, login_expires(creds), sentinel, Pollrow.row.of(row)}

def acct.of(+s: Collect.St) -> View.Acct:
  match s:
    case Collect.St{info, row, sentinel, healed}:
      acct.info(info, row, sentinel)

def accts(ss: List<&2, Collect.St>) -> List<&2, View.Acct>:
  match ss:
    case Nil{}:
      []
    case Con{h, t}:
      acct.of(h) <> accts(t)

def pass.final(+root: String, xs: List<&2, Collect.Info>, +now: U32) -> Act.of(List<&2, View.Acct>):
  Act.bind(Json.Json, List<&2, View.Acct>, Ustore.read_act(root),
    rows => Act.bind(List<&2, Collect.St>, List<&2, View.Acct>, Act.lift(List<&2, Collect.St>, Collect.states(xs, rows, now)), ss => Act.pure(List<&2, View.Acct>, accts(ss))))

def pass.fetch(+root: String, +ss: List<&2, Collect.St>, +models: List<&2, String>, +threshold: U32, +now: U32, +tick: Nat, xs: List<&2, Collect.Info>) -> Act.of(List<&2, View.Acct>):
  Act.bind(List<&2, Ustore.Claim>, List<&2, View.Acct>, Ustore.reserve(root, fetchable(ss), now, True{}, True{}, tick),
    cs => Act.bind(List<&2, Urec.Rec>, List<&2, View.Acct>, Act.lift(List<&2, Urec.Rec>, fetch_all(jobs(ss, cs), root, models, threshold, now)),
      rs => Act.bind(List<&2, String>, List<&2, View.Acct>, Urec.record(root, rs, now),
        done => pass.final(root, xs, now))))

def healed_ids(ss: List<&2, Collect.St>) -> List<&2, Ustore.Id>:
  match ss:
    case Nil{}:
      []
    case Con{+s, t}:
      healed.cons(Collect.st_healed(s), Collect.st_id(s), healed_ids(t))

def pass.heal(+root: String, ss: List<&2, Collect.St>, +models: List<&2, String>, +threshold: U32, +now: U32, +tick: Nat, +xs: List<&2, Collect.Info>) -> Act.of(List<&2, View.Acct>):
  Act.bind(Unit, List<&2, View.Acct>, clear_if(root, healed_ids(ss)),
    u => Act.bind(Json.Json, List<&2, View.Acct>, Ustore.read_act(root),
      rows => Act.bind(List<&2, Collect.St>, List<&2, View.Acct>, Act.lift(List<&2, Collect.St>, Collect.states(xs, rows, now)),
        s2 => pass.fetch(root, s2, models, threshold, now, tick, xs))))

# One usage pass over `xs`: lease what is eligible, fetch it, merge the
# outcomes, and answer an Acct per account with the state read after the merge.
def collect(+ctx: SBase.Ctx, +xs: List<&2, Collect.Info>, +now: U32, +models: List<&2, String>, +threshold: U32, +tick: Nat) -> Act.of(List<&2, View.Acct>):
  Act.bind(Json.Json, List<&2, View.Acct>, Ustore.read_act(SBase.root_of(ctx)),
    rows => Act.bind(List<&2, Collect.St>, List<&2, View.Acct>, Act.lift(List<&2, Collect.St>, Collect.states(xs, rows, now)),
      ss => pass.heal(SBase.root_of(ctx), ss, models, threshold, now, tick, xs)))
