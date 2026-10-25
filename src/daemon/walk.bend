import Base
import ../json.bend as Json
import ../act.bend as Act
import ../clock.bend as Clock
import ../store/base.bend as SBase
import ./events.bend as Ev
import ./cadence.bend as Cad
import ./dec.bend as Dc
import ./apply.bend as Ap
import ./tick.bend as Tk
import ./gather.bend as G
import ./freshen.bend as Fr
import ./quarantine.bend as Q

# Walking the ranked targets (autoswitch.py's `for num in ordered`): the
# policy names the best one; its token is freshened first; a dead credential is
# quarantined and the policy asked again without it; a transient failure moves
# on too. Nothing viable is `no-viable-target` (or an error when the network was
# the reason).

# What the walk has met so far.

type Trail is Data:
  Trail{skip: List<&2, String>, events: List<&2, Json.Json>, transient: Bool, first: Maybe<&2, Tk.Out>, sys: String}

# What one attempt came to: finished, or retry with this trail.
type Move is Data:
  MDone{out: Tk.Out}
  MRetry{trail: Trail}

# Fixed inputs of the walk.
type W is Data:
  W{env: Tk.Env, t0: U32, ts: String, m: Maybe<&2, G.Snap>}

# What freshening a candidate came to.
type Verdict is Data:
  VOk{}
  VDead{}
  VConflict{}
  VSkip{}
  VSys{}
  VTrans{}

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def no_trail() -> Trail:
  Trail{[], [], False{}, None{}, ""}

def trail_skip(t: Trail) -> List<&2, String>:
  match t:
    case Trail{s, e, tr, f, sy}:
      s

def trail_transient(t: Trail) -> Bool:
  match t:
    case Trail{s, e, tr, f, sy}:
      tr

# The first decision's Out (its poll events), else the one at hand.
def lead_of(t: Trail, +o: Tk.Out) -> Tk.Out:
  match t:
    case Trail{s, e, tr, Some{f}, sy}:
      f
    case _:
      o

def with_events(+o: Tk.Out, +extra: List<&2, Json.Json>) -> Tk.Out:
  match o:
    case Tk.Out{Dc.TickRes{i, evs}, m, a, es, ac, ck}:
      Tk.Out{Dc.TickRes{i, List.append(&2, Json.Json, evs, extra)}, m, a, es, ac, ck}

def trail_events(t: Trail) -> List<&2, Json.Json>:
  match t:
    case Trail{s, e, tr, f, sy}:
      e

def with_info(+o: Tk.Out, i: Cad.Info) -> Tk.Out:
  match o:
    case Tk.Out{Dc.TickRes{i0, evs}, m, a, es, ac, ck}:
      Tk.Out{Dc.TickRes{i, evs}, m, a, es, ac, ck}

# The poll events first, then what acting on the decision produced.
def merged(+o: Tk.Out, res: Dc.TickRes) -> Tk.Out:
  match o res:
    case Tk.Out{Dc.TickRes{i0, lead}, m, a, es, ac, ck} Dc.TickRes{info, evs}:
      Tk.Out{Dc.TickRes{info, List.append(&2, Json.Json, lead, evs)}, m, a, es, ac, ck}

def applied(+o: Tk.Out, c: Dc.Ctx, d: Dc.Dec) -> Act.of(Tk.Out):
  do ActM<Tk.Out>:
    res : Dc.TickRes <- Ap.apply(c, d)
    return merged(o, res)

def info_of(o: Cad.Outcome, +np: Maybe<&2, U32>) -> Cad.Info:
  Cad.Info{o, None{}, False{}, False{}, np}

def msg2(+a: Bool, +b: Bool, +c: Bool) -> String:
  match a b c:
    case True{} _ _:
      "CLAUDE_SECURESTORAGE_CONFIG_DIR is set — unset it or run cswap from a normal shell"
    case False{} True{} _:
      "cswap's OAuth client was rejected — systemic, not this account"
    case False{} False{} True{}:
      "a stashed successor is unreadable — unlock the keychain or fix the file, then retry; `cswap unclaimed` inspects it"
    case False{} False{} False{}:
      "another cswap surface holds the slot — retries next pass"

def sys_message(+s: String) -> String:
  msg2(String.eq(s, "store-unmirrored"), String.eq(s, "invalid_client"), String.eq(s, "stash-unreadable"))

def failed_with(+o: Tk.Out, +ts: String, +msg: String) -> Tk.Out:
  with_info(with_events(o, [Ev.error(ts, msg, True{})]), info_of(Cad.Failed{}, None{}))

def gave_up3(+nothing_systemic: Bool, +transient: Bool, +sy: String, +o: Tk.Out, +ts: String) -> Tk.Out:
  match nothing_systemic transient:
    case False{} _:
      failed_with(o, ts, "could not freshen: " ++ sys_message(sy))
    case True{} True{}:
      failed_with(o, ts, "could not freshen any candidate (network?)")
    case True{} False{}:
      with_info(with_events(o, [Ev.no_switch(ts, "no-viable-target", "")]), info_of(Cad.Blocked{}, None{}))

def trail_sys(+t: Trail) -> String:
  match t:
    case Trail{s, e, tr, f, sy}:
      sy

# Every candidate failed to freshen: a systemic refusal, or the network, is an
# error; otherwise there was simply nothing viable.
def gave_up(+t: Trail, +o: Tk.Out, +ts: String) -> Tk.Out:
  gave_up3(String.is_empty(trail_sys(t)), trail_transient(t), trail_sys(t), with_events(lead_of(t, o), trail_events(t)), ts)

def extend(+t: Trail, +slot: String, +more: List<&2, Json.Json>, +transient: Bool, +o: Tk.Out) -> Trail:
  Trail{slot <> trail_skip(t), List.append(&2, Json.Json, trail_events(t), more), trail_transient(t) || transient, Some{lead_of(t, o)}, trail_sys(t)}

def worse2(+take_new: Bool, +old: String, +new: String) -> String:
  match take_new:
    case True{}:
      new
    case False{}:
      old

# The most actionable systemic cause wins (a lower rank), so one needing a human
# never hides behind one that clears itself.
def worse(+old: String, +new: String) -> String:
  worse2(String.is_empty(old) || U32.is_lt(Fr.systemic_rank(new), Fr.systemic_rank(old)), old, new)

def extend_sys(+t: Trail, +slot: String, +status: String, +o: Tk.Out) -> Trail:
  Trail{slot <> trail_skip(t), trail_events(t), trail_transient(t), Some{lead_of(t, o)}, worse(trail_sys(t), status)}

# ---- the walk ---------------------------------------------------------------------------------------------

def w_env(w: W) -> Tk.Env:
  match w:
    case W{e, t, s, m}:
      e

def w_t0(w: W) -> U32:
  match w:
    case W{e, t, s, m}:
      t

def w_ts(w: W) -> String:
  match w:
    case W{e, t, s, m}:
      s

def w_m(w: W) -> Maybe<&2, G.Snap>:
  match w:
    case W{e, t, s, m}:
      m

def done_with(w: W, +tr: Trail, +o: Tk.Out, c: Dc.Ctx, d: Dc.Dec) -> Act.of(Move):
  do ActM<Move>:
    r : Tk.Out <- applied(with_events(lead_of(tr, o), trail_events(tr)), c, d)
    return MDone{r}

def quarantined(+w: W, tr: Trail, +o: Tk.Out, +slot: String, +email: String, +reason: String) -> Act.of(Move):
  do ActM<Move>:
    q : Json.Json <- Q.quarantine(SBase.root_of(Tk.env_ctx(w_env(w))), slot, email, reason, w_ts(w))
    return MRetry{extend(tr, slot, [q], False{}, o)}

def verdict2(+is_sys: Bool, +st: String) -> Verdict:
  match is_sys:
    case True{}:
      VSys{}
    case False{}:
      VTrans{}

def verdict1(+ok: Bool, +dead: Bool, +conflict: Bool, +skip: Bool, +st: String) -> Verdict:
  match ok dead conflict skip:
    case True{} _ _ _:
      VOk{}
    case False{} True{} _ _:
      VDead{}
    case False{} False{} True{} _:
      VConflict{}
    case False{} False{} False{} True{}:
      VSkip{}
    case _ _ _ _:
      verdict2(U32.is_lt(0, Fr.systemic_rank(st)), st)

def verdict(+st: String) -> Verdict:
  verdict1(String.eq(st, "ok"), String.eq(st, "invalid_grant"), String.eq(st, "identity-conflict"), String.eq(st, "skip-live-session"), st)

def route(+v: Verdict, +st: String, w: W, tr: Trail, +o: Tk.Out, c: Dc.Ctx, d: Dc.Dec, +slot: String, +email: String) -> Act.of(Move):
  match v:
    case VOk{}:
      done_with(w, tr, o, c, d)
    case VDead{}:
      quarantined(w, tr, o, slot, email, "invalid_grant")
    case VConflict{}:
      quarantined(w, tr, o, slot, email, "identity-conflict")
    case VSkip{}:
      Act.pure(Move, MRetry{extend(tr, slot, [], False{}, o)})
    case VSys{}:
      Act.pure(Move, MRetry{extend_sys(tr, slot, st, o)})
    case VTrans{}:
      Act.pure(Move, MRetry{extend(tr, slot, [], True{}, o)})

def try_target(+w: W, tr: Trail, +o: Tk.Out, c: Dc.Ctx, d: Dc.Dec, +slot: String, +email: String) -> Act.of(Move):
  do ActM<Move>:
    +st : String <- Fr.status(SBase.root_of(Tk.env_ctx(w_env(w))), slot, email, w_t0(w))
    route(verdict(st), st, w, tr, o, c, d, slot, email)

def on_go(+w: W, +tr: Trail, +o: Tk.Out, +c: Dc.Ctx, +d: Dc.Dec, +slot: String, +email: String) -> Act.of(Move):
  Act.cond(Move, Tk.env_dry(w_env(w)), done_with(w, tr, o, c, d), try_target(w, tr, o, c, d, slot, email))

def on_other(+w: W, +tr: Trail, +o: Tk.Out, c: Dc.Ctx, d: Dc.Dec) -> Act.of(Move):
  Act.cond(Move, List.is_empty(&2, String, trail_skip(tr)), done_with(w, tr, o, c, d), Act.pure(Move, MDone{gave_up(tr, o, w_ts(w))}))

def on_act(w: W, tr: Trail, +o: Tk.Out, c: Dc.Ctx, d: Dc.Dec) -> Act.of(Move):
  match d:
    case Dc.DGo{+to, +email, trig, lh, lr}:
      on_go(w, tr, o, c, d, to, email)
    case _:
      on_other(w, tr, o, c, d)

def next(w: W, tr: Trail, +nx: Tk.Next) -> Act.of(Move):
  match nx:
    case Tk.NDone{o}:
      Act.pure(Move, MDone{lead_of(tr, o)})
    case Tk.NAct{o, c, d}:
      on_act(w, tr, o, c, d)

# Decide again (without the slots already ruled out) and act.
def attempt(+w: W, +tr: Trail) -> Act.of(Move):
  next(w, tr, Tk.tick(Tk.with_skip(w_env(w), trail_skip(tr)), w_t0(w), w_m(w)))

def retry(w: W, mv: Move) -> Act.of(Move):
  match mv:
    case MDone{o}:
      Act.pure(Move, MDone{o})
    case MRetry{tr}:
      attempt(w, tr)

def settle(+w: W, mv: Move) -> Tk.Out:
  match mv:
    case MDone{o}:
      o
    case MRetry{tr}:
      gave_up(tr, Tk.idle_out(w_env(w), w_ts(w), False{}), w_ts(w))

def again(w: W, a: Act.of(Move)) -> Act.of(Move):
  Act.bind(Move, Move, a, mv => retry(w, mv))

def again4(+w: W, a: Act.of(Move)) -> Act.of(Move):
  again(w, again(w, again(w, again(w, a))))

def walk(+w: W) -> Act.of(Tk.Out):
  Act.bind(Move, Tk.Out, again4(w, again4(w, again4(w, again4(w, attempt(w, no_trail()))))), mv => Act.pure(Tk.Out, settle(w, mv)))

# Up to 16 candidates are tried per tick (autoswitch.py walks the whole ranking;
# Bend has no mutual recursion for an unbounded loop here). A longer ranking is
# finished on the next tick: the ones found dead are quarantined by then.
def run(+env: Tk.Env, +t0: U32, +ts: String, +m: Maybe<&2, G.Snap>) -> Act.of(Tk.Out):
  walk(W{env, t0, ts, m})
