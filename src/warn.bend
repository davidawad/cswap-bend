import Base
import ./pollrow.bend as Pollrow
import ./usage/gate.bend as UGate
import ./store/seq.bend as SSeq
import ./json.bend as Json
import ./view.bend as View
import ./collect.bend as Collect

# The list payload's additive warnings (switcher.py _duplicate_account_warnings
# and _lockstep_usage_warnings). Credentials are compared by lineage identity
# as text (UGate.fp), so no hash is spawned.

def dash() -> String:
  " \u{2014} "

type Seen is Data:
  Seen{key: String, slot: String}

def seen.pick(hit: Bool, s: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{s}
    case False{}:
      rest

def seen_find(+key: String, xs: List<&2, Seen>) -> Maybe<&2, String>:
  match xs:
    case Nil{}:
      None{}
    case Con{Seen{k, s}, t}:
      seen.pick(String.eq(k, key), s, seen_find(key, t))

def append_str(xs: List<&2, String>, +x: String) -> List<&2, String>:
  List.append(&2, String, xs, [x])

def win_key2(p: Maybe<&2, Json.Json>, r: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match p r:
    case Some{Json.JNum{t}} Some{Json.JStr{s}}:
      Some{t ++ "@" ++ s}
    case _ _:
      None{}

def win_key(+w: Json.Json) -> Maybe<&2, String>:
  win_key2(Json.get("pct", w), Json.get("resets_at", w))

def key3(a: Maybe<&2, String>, b: Maybe<&2, String>) -> Maybe<&2, String>:
  match a b:
    case Some{x} Some{y}:
      Some{x ++ "|" ++ y}
    case _ _:
      None{}

def key2(a: Maybe<&2, Json.Json>, b: Maybe<&2, Json.Json>) -> Maybe<&2, String>:
  match a b:
    case Some{x} Some{y}:
      key3(win_key(x), win_key(y))
    case _ _:
      None{}

def usage_key(+u: Json.Json) -> Maybe<&2, String>:
  key2(Json.get("five_hour", u), Json.get("seven_day", u))

type LS is Data:
  LS{seen: List<&2, Seen>, msgs: List<&2, String>}

def ls_seen(ls: LS) -> List<&2, Seen>:
  match ls:
    case LS{s, m}:
      s

def lock.seen(other: Maybe<&2, String>, +k: String, +slot: String, ls: LS) -> LS:
  match other ls:
    case Some{o} LS{s, msgs}:
      LS{s, append_str(msgs, "Account-" ++ o ++ " and Account-" ++ slot ++ " report identical usage and reset times" ++ dash() ++ "they may be the same account (issue #117). If it persists, log in with the missing account and re-add it: cswap add --slot N")}
    case None{} LS{s, msgs}:
      LS{Seen{k, slot} <> s, msgs}

def lock.step(m: Maybe<&2, String>, +slot: String, +ls: LS) -> LS:
  match m:
    case None{}:
      ls
    case Some{+k}:
      lock.seen(seen_find(k, ls_seen(ls)), k, slot, ls)

def lock.live(sentinel: Maybe<&2, String>, +row: Pollrow.Row, +slot: String, models: List<&2, String>, +now: U32, ls: LS) -> LS:
  match sentinel:
    case Some{s}:
      ls
    case None{}:
      lock.step(usage_key(Pollrow.decision_usage(row, models, now)), slot, ls)

def lock.acct(+a: View.Acct, models: List<&2, String>, +now: U32, ls: LS) -> LS:
  match a:
    case View.Acct{num, email, org_name, org_uuid, active, alias, disabled, login, sentinel, row}:
      lock.live(sentinel, row, U32.show(num), models, now, ls)

def lock.go(as: List<&2, View.Acct>, +models: List<&2, String>, +now: U32, ls: LS) -> LS:
  match as:
    case Nil{}:
      ls
    case Con{h, t}:
      lock.go(t, models, now, lock.acct(h, models, now, ls))

def msgs_of(ls: LS) -> List<&2, String>:
  match ls:
    case LS{s, m}:
      m

# Slots whose 5h and 7d usage and resets match to the digit.
def lockstep(as: List<&2, View.Acct>, models: List<&2, String>, +now: U32) -> List<&2, String>:
  msgs_of(lock.go(as, models, now, LS{[], []}))

type DS is Data:
  DS{fps: List<&2, Seen>, ids: List<&2, Seen>, msgs: List<&2, String>}

def uuid_of(+seq: Json.Json, +slot: String) -> String:
  String.trim(Maybe.default(&2, String, Json.as_string(Maybe.default(&2, Json.Json, Maybe.bind(&2, Json.Json, Json.Json, SSeq.slot_record(seq, slot), r => Json.get("uuid", r)), Json.JNull{})), ""))

def ds_fps(ds: DS) -> List<&2, Seen>:
  match ds:
    case DS{f, i, m}:
      f

def dup.fp3(other: Maybe<&2, String>, +fp: String, +slot: String, +email: String, ds: DS) -> DS:
  match other ds:
    case Some{o} DS{f, i, m}:
      DS{f, i, append_str(m, "Account-" ++ o ++ " and Account-" ++ slot ++ " hold the same credential (" ++ email ++ ")" ++ dash() ++ "one slot's backup was overwritten. Log in with the missing account and re-add it: cswap add --slot N")}
    case None{} DS{f, i, m}:
      DS{Seen{fp, slot} <> f, i, m}

def dup.fp2(has: Bool, +fp: String, +slot: String, +email: String, +ds: DS) -> DS:
  match has:
    case False{}:
      ds
    case True{}:
      dup.fp3(seen_find(fp, ds_fps(ds)), fp, slot, email, ds)

def dup.fp(+creds: String, +slot: String, +email: String, ds: DS) -> DS:
  dup.fp2(Bool.not(String.is_empty(creds)), UGate.fp(creds), slot, email, ds)

def ds_ids(ds: DS) -> List<&2, Seen>:
  match ds:
    case DS{f, i, m}:
      i

def dup.id3(other: Maybe<&2, String>, +key: String, +slot: String, +email: String, ds: DS) -> DS:
  match other ds:
    case Some{o} DS{f, i, m}:
      DS{f, i, append_str(m, "Account-" ++ o ++ " and Account-" ++ slot ++ " both authenticate as " ++ email ++ dash() ++ "remove or re-login one of them.")}
    case None{} DS{f, i, m}:
      DS{f, Seen{key, slot} <> i, m}

def dup.id2(has: Bool, +key: String, +slot: String, +email: String, +ds: DS) -> DS:
  match has:
    case False{}:
      ds
    case True{}:
      dup.id3(seen_find(key, ds_ids(ds)), key, slot, email, ds)

def dup.id(+uuid: String, +org: String, +slot: String, +email: String, ds: DS) -> DS:
  dup.id2(Bool.not(String.is_empty(uuid)), uuid ++ "@" ++ org, slot, email, ds)

def dup.info(+i: Collect.Info, +seq: Json.Json, ds: DS) -> DS:
  match i:
    case Collect.Info{num, email, org_name, org_uuid, alias, disabled, active, creds}:
      dup.id(uuid_of(seq, U32.show(num)), org_uuid, U32.show(num), email, dup.fp(creds, U32.show(num), email, ds))

def dup.go(xs: List<&2, Collect.Info>, +seq: Json.Json, ds: DS) -> DS:
  match xs:
    case Nil{}:
      ds
    case Con{h, t}:
      dup.go(t, seq, dup.info(h, seq, ds))

def ds_msgs(ds: DS) -> List<&2, String>:
  match ds:
    case DS{f, i, m}:
      m

# Slots that provably authenticate as the same account.
def duplicates(infos: List<&2, Collect.Info>, +seq: Json.Json) -> List<&2, String>:
  ds_msgs(dup.go(infos, seq, DS{[], [], []}))
