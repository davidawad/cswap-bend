import Base
import ../json.bend as Json
import ../act.bend as Act
import ../fs.bend as Fs
import ../clock.bend as Clock
import ../store.bend as Store
import ../store/base.bend as SBase
import ../store/seq.bend as SSeq
import ../swlive.bend as L
import ../switch.bend as Sw
import ../swbase.bend as SwB
import ./dec.bend as Dc
import ./events.bend as Ev
import ./cadence.bend as Cad
import ./state.bend as St
import ./config.bend as Cfg

# Acting on a decision: print the event, and for a switch run it under the
# autoswitch state lock (cooldown re-checked there, as `_perform` does),
# record it, and say what the sleeper needs to know. A switch that fails
# becomes an `error` event, never a crash.

# What the policy decided, in the units the daemon acts on. Headroom is
# centi-percent, times unix seconds.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def warnings_of(+w: Json.Json) -> List<&2, String>:
  SwB.texts_of(w)

def switched_res(+c: Dc.Ctx, +trigger: String, +r: Json.Json) -> Dc.TickRes:
  Dc.one(Dc.info(Cad.Switched{}, None{}, False{}, False{}, Dc.ctx_np(c)), Ev.switch(Dc.ctx_ts(c), trigger, SSeq.get_or("from", r, Json.JNull{}), SSeq.get_or("to", r, Json.JNull{}), warnings_of(SSeq.get_or("warnings", r, Json.JNull{})), False{}))

def num_of(+m: Maybe<&2, Json.Json>) -> Maybe<&2, U32>:
  match m:
    case Some{j}:
      Json.as_u32(j)
    case None{}:
      None{}

def from_number(+r: Json.Json) -> Maybe<&2, U32>:
  num_of(Json.get("number", SSeq.get_or("from", r, Json.JNull{})))

def record_sw(+c: Dc.Ctx, +root: String, +to: String, +trigger: String, +lh: Maybe<&2, U32>, +lr: Maybe<&2, U32>, +r: Json.Json) -> Act.of(Dc.TickRes):
  do ActM<Dc.TickRes>:
    st : Json.Json <- Act.lift(Json.Json, St.read_state(root))
    St.write_state(root, St.record_switch(st, Dc.ctx_now(c), to, from_number(r), lh, lr, trigger))
    return switched_res(c, trigger, r)

def after_switch2(+switched: Bool, +c: Dc.Ctx, +root: String, +to: String, +trigger: String, +lh: Maybe<&2, U32>, +lr: Maybe<&2, U32>, +r: Json.Json) -> Act.of(Dc.TickRes):
  match switched:
    case False{}:
      Act.pure(Dc.TickRes, Dc.none_res(c, "already-active", SSeq.field_str(r, "reason")))
    case True{}:
      record_sw(c, root, to, trigger, lh, lr, r)

def bool_of(+m: Maybe<&2, Json.Json>) -> Bool:
  match m:
    case Some{Json.JBool{b}}:
      b
    case _:
      False{}

def is_switched(+r: Json.Json) -> Bool:
  bool_of(Json.get("switched", r))

def after_switch(+c: Dc.Ctx, +root: String, go: Dc.Dec, +r: Json.Json) -> Act.of(Dc.TickRes):
  match go:
    case Dc.DGo{to, email, trigger, lh, lr}:
      after_switch2(is_switched(r), c, root, to, trigger, lh, lr, r)
    case _:
      Act.pure(Dc.TickRes, Dc.error_res(c, "internal: not a switch"))

def cooldown_applies(+trigger: String) -> Bool:
  String.eq(trigger, "proactive") || String.eq(trigger, "consume-first")

def cfg_cooldown(+cf: Cfg.Cfg) -> U32:
  match cf:
    case Cfg.Cfg{th, iv, cd, hy, st, ia, ut, ms}:
      cd

def run_switch(+c: Dc.Ctx, +root: String, go: Dc.Dec, +to: String, +trigger: String) -> Act.of(Dc.TickRes):
  do ActM<Dc.TickRes>:
    r : Json.Json <- Sw.switch_to(Dc.ctx_store(c), to, False{}, Dc.ctx_opts(c))
    after_switch(c, root, go, r)

def locked_switch2(+cool: Bool, +c: Dc.Ctx, +root: String, go: Dc.Dec, +to: String, +trigger: String) -> Act.of(Dc.TickRes):
  Act.cond(Dc.TickRes, cool, Act.pure(Dc.TickRes, Dc.none_res(c, "cooldown", "")), run_switch(c, root, go, to, trigger))

def in_cool(+c: Dc.Ctx, +st: Json.Json, +trigger: String) -> Bool:
  cooldown_applies(trigger) && St.in_cooldown(st, Dc.ctx_now(c), cfg_cooldown(Dc.ctx_cfg(c)))

def locked_switch(+c: Dc.Ctx, +root: String, go: Dc.Dec, +to: String, +trigger: String) -> Act.of(Dc.TickRes):
  do ActM<Dc.TickRes>:
    st : Json.Json <- Act.lift(Json.Json, St.read_state(root))
    locked_switch2(in_cool(c, st, trigger), c, root, go, to, trigger)

def dry_res(+c: Dc.Ctx, +trigger: String, +to: String, +email: String) -> Dc.TickRes:
  Dc.one(Dc.info(Cad.Switched{}, None{}, False{}, False{}, Dc.ctx_np(c)), Ev.switch(Dc.ctx_ts(c), trigger, Dc.ctx_active(c), Ev.ref(to, email), [], True{}))

def go_res(+c: Dc.Ctx, go: Dc.Dec) -> Act.of(Dc.TickRes):
  match go:
    case Dc.DGo{+to, +email, +trigger, lh, lr}:
      Act.cond(Dc.TickRes, Dc.ctx_dry(c), Act.pure(Dc.TickRes, dry_res(c, trigger, to, email)),
        St.with_state_lock(Dc.TickRes, SBase.root_of(Dc.ctx_store(c)), locked_switch(c, SBase.root_of(Dc.ctx_store(c)), go, to, trigger)))
    case _:
      Act.pure(Dc.TickRes, Dc.error_res(c, "internal: not a switch"))

# A failed switch is an error event, not a crashed tick.
def recover(+c: Dc.Ctx, r: Fs.Res(Dc.TickRes)) -> Act.of(Dc.TickRes):
  match r:
    case Done{t}:
      Act.pure(Dc.TickRes, t)
    case Fail{(code, msg)}:
      Act.pure(Dc.TickRes, Dc.error_res(c, msg))

def go_safe(+c: Dc.Ctx, go: Dc.Dec) -> Act.of(Dc.TickRes):
  IO.bind(Fs.Res(Dc.TickRes), Fs.Res(Dc.TickRes), go_res(c, go), r => recover(c, r))

# Act on `d`.
def apply(+c: Dc.Ctx, d: Dc.Dec) -> Act.of(Dc.TickRes):
  match d:
    case Dc.DNone{reason, detail}:
      Act.pure(Dc.TickRes, Dc.none_res(c, reason, detail))
    case Dc.DExhausted{earliest}:
      Act.pure(Dc.TickRes, Dc.exhausted_res(c, earliest))
    case Dc.DGo{to, email, trigger, lh, lr}:
      go_safe(c, d)
