import Base
import ../json.bend as Json
import ../fs.bend as Fs
import ../act.bend as Act
import ../store.bend as Store
import ../store/base.bend as SBase
import ../store/io.bend as SIo
import ../store/ops.bend as SOps
import ../store/seq.bend as SSeq
import ../usage.bend as Usage
import ../swlive.bend as L
import ../swbase.bend as SwB
import ../policy/types.bend as T
import ./rows.bend as Rows
import ./state.bend as St

# What a tick looks at: the roster, the live login, the autoswitch state, the
# cached usage rows, and per managed account its credential and the policy's
# view of it (kind, disabled, usage row).

# One managed account: its identity, its stored credential, and the policy's
# `Account` (a quarantined, disabled or unswitchable one is passed as disabled).

type Ent is Data:
  Ent{slot: String, email: String, org: String, creds: String, acct: T.Account}

type Snap is Data:
  Snap{seq: Json.Json, live: L.Live, active: Maybe<&2, String>, state: Json.Json, rows: Json.Json, ents: List<&2, Ent>}

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def is_true(+m: Maybe<&2, Json.Json>) -> Bool:
  match m:
    case Some{Json.JBool{b}}:
      b
    case _:
      False{}

def refresh_of(+creds: String) -> String:
  SSeq.field_str(SSeq.get_or("claudeAiOauth", Json.unwrap(Json.parse(creds)), Json.JNull{}), "refreshToken")

def kind2(+api: Bool, +refresh: Bool) -> T.AcctKind:
  match api refresh:
    case True{} _:
      T.ApiKey{}
    case False{} True{}:
      T.FullLogin{}
    case False{} False{}:
      T.SetupToken{}

def kind_of(+api_rec: Bool, +creds: String) -> T.AcctKind:
  kind2(api_rec || SBase.looks_like_api_key(creds), SBase.nonempty(refresh_of(creds)))

def ent_of(+slot: String, +rec: Json.Json, +creds: String, +cfg_ok: Bool, +quarantined: Bool) -> Ent:
  Ent{slot, SSeq.field_str(rec, "email"), SSeq.field_str(rec, "organizationUuid"), creds,
    T.Account{U32.to_nat(SSeq.str_u32(slot)), SSeq.field_str(rec, "email"), kind_of(SSeq.is_api_key_rec(rec), creds),
      is_true(Json.get("disabled", rec)) || quarantined || Bool.not(SBase.nonempty(creds) && cfg_ok)}}

def mem_str(+x: String, +xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      String.eq(h, x) || mem_str(x, t)

def has_config(+root: String, +seq: Json.Json, +slot: String) -> Act.of(Bool):
  do ActM<Bool>:
    cfg : Maybe<&2, String> <- L.read_text_opt(SBase.config_path(root, slot, SIo.slot_email(seq, slot)))
    return SBase.nonempty(SwB.text_or(cfg))

def cred_of(+root: String, +seq: Json.Json, +slot: String) -> Act.of(String):
  SIo.read_cred(root, slot, SIo.slot_email(seq, slot))

def ent_one(+root: String, +seq: Json.Json, +slot: String, +st: Json.Json) -> Act.of(Ent):
  do ActM<Ent>:
    creds : String <- cred_of(root, seq, slot)
    ok : Bool <- has_config(root, seq, slot)
    return ent_of(slot, SSeq.get_or(slot, SSeq.accounts_of(seq), Json.JNull{}), creds, ok, mem_str(slot, St.quarantined_slots(st)))

def ents_of(+root: String, +seq: Json.Json, +slots: List<&2, String>, +st: Json.Json) -> Act.of(List<&2, Ent>):
  match slots:
    case Nil{}:
      Act.pure(List<&2, Ent>, [])
    case Con{s, t}:
      do ActM<List<&2, Ent>>:
        e : Ent <- ent_one(root, seq, s, st)
        rest : List<&2, Ent> <- ents_of(root, seq, t, st)
        return e <> rest

def rows3(+v: String, +j: Json.Json) -> Json.Json:
  Store.sel.j(String.eq(v, "2"), SSeq.accounts_of(j), Json.JObj{Json.JNil{}})

def rows2(r: Result<&2, &2, String, Json.Json>) -> Json.Json:
  match r:
    case Fail{e}:
      Json.JObj{Json.JNil{}}
    case Done{+j}:
      rows3(SOps.field_json(j, "schemaVersion"), j)

# The cached rows (accounts object); {} for a missing, torn or other-schema file.
def rows_of(r: Fs.Res(String)) -> Json.Json:
  match r:
    case Fail{e}:
      SSeq.accounts_of(Json.JNull{})
    case Done{t}:
      rows2(Json.parse(t))

def read_rows(+root: String) -> IO(Json.Json):
  IO.bind(Fs.Res(String), Json.Json, Fs.read_file(root ++ "/cache/usage.json"), r => IO.pure(Json.Json, rows_of(r)))

def ents_for(+ctx: SBase.Ctx, +seq: Json.Json, +st: Json.Json) -> Act.of(List<&2, Ent>):
  ents_of(SBase.root_of(ctx), seq, SwB.slots_of(seq), st)

def state_of(+ctx: SBase.Ctx) -> Act.of(Json.Json):
  Act.lift(Json.Json, St.read_state(SBase.root_of(ctx)))

def load(+ctx: SBase.Ctx, +seq: Json.Json) -> Act.of(Snap):
  do ActM<Snap>:
    +live : L.Live <- L.read_live(ctx)
    +st : Json.Json <- state_of(ctx)
    rows : Json.Json <- Act.lift(Json.Json, read_rows(SBase.root_of(ctx)))
    ents : List<&2, Ent> <- ents_for(ctx, seq, st)
    return Snap{seq, live, L.lv_slot(live, seq), st, rows, ents}

def some_snap(s: Snap) -> Act.of(Maybe<&2, Snap>):
  Act.pure(Maybe<&2, Snap>, Some{s})

def snapshot2(+ctx: SBase.Ctx, +m: Maybe<&2, Json.Json>) -> Act.of(Maybe<&2, Snap>):
  match m:
    case None{}:
      Act.pure(Maybe<&2, Snap>, None{})
    case Some{seq}:
      Act.bind(Snap, Maybe<&2, Snap>, load(ctx, seq), s => some_snap(s))

# Look the whole picture up.
def snapshot(+ctx: SBase.Ctx) -> Act.of(Maybe<&2, Snap>):
  do ActM<Maybe<&2, Snap>>:
    m : Maybe<&2, Json.Json> <- SIo.read_seq(SBase.root_of(ctx))
    snapshot2(ctx, m)

def snap_ents(+s: Snap) -> List<&2, Ent>:
  match s:
    case Snap{seq, live, active, st, rows, ents}:
      ents

def snap_active(+s: Snap) -> Maybe<&2, String>:
  match s:
    case Snap{seq, live, active, st, rows, ents}:
      active

def snap_state(+s: Snap) -> Json.Json:
  match s:
    case Snap{seq, live, active, st, rows, ents}:
      st

def snap_rows(+s: Snap) -> Json.Json:
  match s:
    case Snap{seq, live, active, st, rows, ents}:
      rows

def in_skip(+slot: String, +skip: List<&2, String>) -> Bool:
  mem_str(slot, skip)

def disable_ent(e: Ent, +skip: List<&2, String>) -> Ent:
  match e:
    case Ent{+slot, email, org, creds, T.Account{n, ae, k, d}}:
      Ent{slot, email, org, creds, T.Account{n, ae, k, d || in_skip(slot, skip)}}

def disable_ents(+es: List<&2, Ent>, +skip: List<&2, String>) -> List<&2, Ent>:
  match es:
    case Nil{}:
      []
    case Con{e, t}:
      disable_ent(e, skip) <> disable_ents(t, skip)

def skip_one(s: Snap, +skip: List<&2, String>) -> Snap:
  match s:
    case Snap{seq, live, active, st, rows, ents}:
      Snap{seq, live, active, st, rows, disable_ents(ents, skip)}

# The snapshot with the given slots held out of the candidates.
def skip_snap(+m: Maybe<&2, Snap>, +skip: List<&2, String>) -> Maybe<&2, Snap>:
  match m:
    case None{}:
      None{}
    case Some{s}:
      Some{skip_one(s, skip)}
