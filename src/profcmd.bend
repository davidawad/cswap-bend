import Base
import ./json.bend as Json
import ./act.bend as Act
import ./cmd.bend as Cmd
import ./fs.bend as Fs
import ./setload.bend as Setload
import ./setwrite.bend as Setwrite
import ./setcmd.bend as Setcmd
import ./profile.bend as P
import ./policy/safe.bend as SF
import ./daemon/config.bend as Cfg
import ./profview.bend as PV

# `cswap profile list|show [NAME]|use NAME|set NAME KEY VALUE|remove NAME`,
# each with `--json`. The profiles live in settings.json (src/profile.bend);
# a write changes only `profiles` / `active_profile` and keeps every other key.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

# ----------------------------------------------------------------- commands

# What a command settled on: an answer without writing, or the settings to
# write and the answer to give once they are.
type Plan2 is Data:
  Answer{out: Cmd.Out}
  Wr{raw: Json.Json, out: Cmd.Out}

def doc(pairs: List<(String & Json.Json)>) -> Cmd.Out:
  Cmd.doc(Json.of_pairs(Con{("schemaVersion", Json.JNum{"1"}), pairs}))

def err(+json: Bool, +msg: String) -> Cmd.Out:
  Cmd.failed(json, "ConfigError", msg)

def unknown_msg(+name: String) -> String:
  "unknown profile '" ++ name ++ "'; `cswap profile list` shows the profiles"

def active_json(+m: Maybe<&2, String>) -> Maybe<&2, Json.Json>:
  match m:
    case Some{s}:
      Some{Json.JStr{s}}
    case None{}:
      None{}

def list_doc(+raw: Json.Json) -> Cmd.Out:
  doc([("active", PV.opt_json(active_json(P.active(raw)))), ("profiles", Json.arr(PV.prof_jsons(raw, Cfg.from_settings(raw), P.names(raw))))])

def list_out(+json: Bool, +raw: Json.Json) -> Cmd.Out:
  match json:
    case True{}:
      list_doc(raw)
    case False{}:
      Cmd.ok(PV.table(PV.rows_of(raw, Cfg.from_settings(raw), P.names(raw))))

def yes_no(+b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

def show_text2(+r: PV.Row) -> String:
  match r:
    case PV.Row{m, n, s, t, ms, c, i, src}:
      "name:       " ++ n ++ "\nstrategy:   " ++ s ++ "\nthreshold:  " ++ t ++ "\nmodels:     " ++ ms ++ "\ncooldown_s: " ++ c ++ "\ninterval_s: " ++ i ++ "\nsource:     " ++ src ++ "\nactive:     " ++ yes_no(String.eq(m, "*"))

def show_text(+raw: Json.Json, +cfg: Cfg.Cfg, +p: P.Prof) -> String:
  show_text2(PV.row_of(raw, cfg, p))

def show_out(+json: Bool, +raw: Json.Json, +p: P.Prof) -> Cmd.Out:
  match json:
    case True{}:
      doc([("profile", PV.prof_json(raw, Cfg.from_settings(raw), p))])
    case False{}:
      Cmd.ok(show_text(raw, Cfg.from_settings(raw), p))

def show_found(+json: Bool, +raw: Json.Json, +name: String, +m: Maybe<&2, P.Prof>) -> Cmd.Out:
  match m:
    case None{}:
      err(json, unknown_msg(name))
    case Some{p}:
      show_out(json, raw, p)

def show_name(+raw: Json.Json, +n: Maybe<&2, String>) -> String:
  match n:
    case Some{x}:
      x
    case None{}:
      Maybe.default(&2, String, P.active(raw), "default")

def show_out2(+json: Bool, +raw: Json.Json, +name: String) -> Cmd.Out:
  show_found(json, raw, name, P.find(raw, name))

def run.list(+root: String, +json: Bool) -> IO(Cmd.Out):
  IO.bind(Json.Json, Cmd.Out, Setload.load_raw(root), raw => IO.pure(Cmd.Out, list_out(json, raw)))

def show_run(+json: Bool, +n: Maybe<&2, String>, +raw: Json.Json) -> IO(Cmd.Out):
  IO.pure(Cmd.Out, show_out2(json, raw, show_name(raw, n)))

def run.show(+root: String, +json: Bool, +n: Maybe<&2, String>) -> IO(Cmd.Out):
  IO.bind(Json.Json, Cmd.Out, Setload.load_raw(root), raw => show_run(json, n, raw))

# ---- use

def use_ok(+json: Bool, +raw: Json.Json, +name: String, +p: P.Prof) -> Cmd.Out:
  match json:
    case True{}:
      doc([("activeProfile", Json.JStr{name}), ("profile", PV.prof_json(raw, Cfg.from_settings(raw), p))])
    case False{}:
      Cmd.ok("active profile: " ++ name ++ " (" ++ SF.name(P.algo_base(p)) ++ ")")

def use_plan2(+m: Maybe<&2, P.Prof>, +json: Bool, +raw: Json.Json, +name: String) -> Plan2:
  match m:
    case None{}:
      Answer{err(json, unknown_msg(name))}
    case Some{p}:
      Wr{P.use(raw, name), use_ok(json, P.use(raw, name), name, p)}

def use_plan(+json: Bool, +raw: Json.Json, +name: String) -> Plan2:
  use_plan2(P.find(raw, name), json, raw, name)

# ---- set

def set_ok(+json: Bool, +raw: Json.Json, +name: String, +key: String, +value: String, +p: P.Prof) -> Cmd.Out:
  match json:
    case True{}:
      doc([("profile", PV.prof_json(raw, Cfg.from_settings(raw), p))])
    case False{}:
      Cmd.ok("profile " ++ name ++ ": " ++ key ++ " = " ++ value)

def set_plan3(+u: P.Upd, +json: Bool, +raw: Json.Json, +name: String, +key: String, +value: String) -> Plan2:
  match u:
    case P.UBad{m}:
      Answer{err(json, m)}
    case P.UOk{p}:
      Wr{P.store(raw, p), set_ok(json, P.store(raw, p), name, key, value, p)}

def set_base(+m: Maybe<&2, P.Prof>, +name: String) -> P.Prof:
  Maybe.default(&2, P.Prof, m, P.bare(name, SF.ABest{}))

def set_plan2(+valid: Bool, +json: Bool, +raw: Json.Json, +name: String, +key: String, +value: String) -> Plan2:
  match valid:
    case False{}:
      Answer{err(json, "invalid profile name '" ++ name ++ "': use letters, digits, '-' and '_', starting with a letter or digit")}
    case True{}:
      set_plan3(P.update(set_base(P.find(raw, name), name), key, value), json, raw, name, key, value)

def set_plan1(+is_default: Bool, +json: Bool, +raw: Json.Json, +name: String, +key: String, +value: String) -> Plan2:
  match is_default:
    case True{}:
      Answer{err(json, "profile 'default' follows the autoswitch settings and cannot be changed; create another profile, or use `cswap config set`")}
    case False{}:
      set_plan2(P.valid_name(name), json, raw, name, key, value)

def set_plan(+json: Bool, +raw: Json.Json, +name: String, +key: String, +value: String) -> Plan2:
  set_plan1(String.eq(name, "default"), json, raw, name, key, value)

# ---- remove

def gone_note(+was_active: Bool) -> String:
  match was_active:
    case True{}:
      "\nactive profile cleared (back to default)"
    case False{}:
      ""

def gone_ok(+json: Bool, +raw: Json.Json, +name: String, +was_active: Bool) -> Cmd.Out:
  match json:
    case True{}:
      doc([("removed", Json.JStr{name}), ("activeProfile", PV.opt_json(active_json(P.active(raw))))])
    case False{}:
      Cmd.ok("removed profile " ++ name ++ gone_note(was_active))

def gone_missing(+builtin: Bool, +name: String) -> String:
  match builtin:
    case True{}:
      "profile '" ++ name ++ "' is built in and has no stored override to remove"
    case False{}:
      unknown_msg(name)

def gone_plan3(+stored: Bool, +json: Bool, +raw: Json.Json, +name: String) -> Plan2:
  match stored:
    case True{}:
      Wr{P.remove(raw, name), gone_ok(json, P.remove(raw, name), name, String.eq(Maybe.default(&2, String, P.active(raw), ""), name))}
    case False{}:
      Answer{err(json, gone_missing(P.is_builtin(name), name))}

def gone_plan1(+is_default: Bool, +json: Bool, +raw: Json.Json, +name: String) -> Plan2:
  match is_default:
    case True{}:
      Answer{err(json, "profile 'default' is built in and cannot be removed")}
    case False{}:
      gone_plan3(P.has_stored(raw, name), json, raw, name)

def gone_plan(+json: Bool, +raw: Json.Json, +name: String) -> Plan2:
  gone_plan1(String.eq(name, "default"), json, raw, name)

# ---- running a plan

def finish(+root: String, +w: Plan2) -> Act.of(Cmd.Out):
  match w:
    case Answer{o}:
      Act.pure(Cmd.Out, o)
    case Wr{raw, o}:
      do ActM<Cmd.Out>:
        u : Unit <- Setcmd.write_settings(root, raw)
        Act.pure(Cmd.Out, o)

def edit(+root: String, +plan: Plan2) -> IO(Cmd.Out):
  IO.bind(Fs.Res(Cmd.Out), Cmd.Out, finish(root, plan), r => IO.pure(Cmd.Out, Setcmd.fin(r)))

def use.act(+root: String, +json: Bool, +name: String) -> Act.of(Plan2):
  do ActM<Plan2>:
    +raw : Json.Json <- Setcmd.load_raw_w(root)
    Act.pure(Plan2, use_plan(json, raw, name))

def set.act(+root: String, +json: Bool, +name: String, +key: String, +value: String) -> Act.of(Plan2):
  do ActM<Plan2>:
    +raw : Json.Json <- Setcmd.load_raw_w(root)
    Act.pure(Plan2, set_plan(json, raw, name, key, value))

def gone.act(+root: String, +json: Bool, +name: String) -> Act.of(Plan2):
  do ActM<Plan2>:
    +raw : Json.Json <- Setcmd.load_raw_w(root)
    Act.pure(Plan2, gone_plan(json, raw, name))

# Read settings.json strictly (a torn file is an error, never replaced), plan, write.
def planned(+root: String, r: Fs.Res(Plan2)) -> IO(Cmd.Out):
  match r:
    case Fail{e}:
      IO.pure(Cmd.Out, Cmd.fail(Setcmd.err.msg(e)))
    case Done{w}:
      edit(root, w)

def run.use(+root: String, +json: Bool, +name: String) -> IO(Cmd.Out):
  IO.bind(Fs.Res(Plan2), Cmd.Out, use.act(root, json, name), r => planned(root, r))

def run.set(+root: String, +json: Bool, +name: String, +key: String, +value: String) -> IO(Cmd.Out):
  IO.bind(Fs.Res(Plan2), Cmd.Out, set.act(root, json, name, key, value), r => planned(root, r))

def run.gone(+root: String, +json: Bool, +name: String) -> IO(Cmd.Out):
  IO.bind(Fs.Res(Plan2), Cmd.Out, gone.act(root, json, name), r => planned(root, r))

# ----------------------------------------------------------------- argv

type Plan is Data:
  PList{}
  PShow{name: Maybe<&2, String>}
  PUse{name: String}
  PSet{name: String, key: String, value: String}
  PRemove{name: String}
  PBad{msg: String}

def join_sp(xs: List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, Nil{}}:
      h
    case Con{h, t}:
      h ++ " " ++ join_sp(t)

def plan.none(rest: List<String>, +p: Plan) -> Plan:
  match rest:
    case Nil{}:
      p
    case o:
      PBad{"unrecognized arguments: " ++ join_sp(rest)}

def plan.show(rest: List<String>) -> Plan:
  match rest:
    case Nil{}:
      PShow{None{}}
    case Con{n, t}:
      plan.none(t, PShow{Some{n}})

def plan.use(rest: List<String>) -> Plan:
  match rest:
    case Nil{}:
      PBad{"the following arguments are required: NAME"}
    case Con{n, t}:
      plan.none(t, PUse{n})

def plan.gone(rest: List<String>) -> Plan:
  match rest:
    case Nil{}:
      PBad{"the following arguments are required: NAME"}
    case Con{n, t}:
      plan.none(t, PRemove{n})

def plan.set(rest: List<String>) -> Plan:
  match rest:
    case Nil{}:
      PBad{"the following arguments are required: NAME, KEY, VALUE"}
    case Con{n, Nil{}}:
      PBad{"the following arguments are required: KEY, VALUE"}
    case Con{n, Con{k, Nil{}}}:
      PBad{"the following arguments are required: VALUE"}
    case Con{n, Con{k, Con{v, t}}}:
      plan.none(t, PSet{n, k, v})

def plan.verb(+l: Bool, +sh: Bool, +u: Bool, +st: Bool, +dl: Bool, +a: String, rest: List<String>) -> Plan:
  match l sh u st dl:
    case True{} _ _ _ _:
      plan.none(rest, PList{})
    case False{} True{} _ _ _:
      plan.show(rest)
    case False{} False{} True{} _ _:
      plan.use(rest)
    case False{} False{} False{} True{} _:
      plan.set(rest)
    case False{} False{} False{} False{} True{}:
      plan.gone(rest)
    case _ _ _ _ _:
      PBad{"argument action: invalid choice: '" ++ a ++ "' (choose from 'list', 'show', 'use', 'set', 'remove')"}

# `profile [list | show [NAME] | use NAME | set NAME KEY VALUE | remove NAME]`, flags removed.
def plan.of(args: List<String>) -> Plan:
  match args:
    case Nil{}:
      PList{}
    case Con{+a, rest}:
      plan.verb(String.eq(a, "list") || String.eq(a, "ls"), String.eq(a, "show"), String.eq(a, "use"), String.eq(a, "set"), String.eq(a, "remove"), a, rest)

def run(+root: String, +p: Plan, +json: Bool) -> IO(Cmd.Out):
  match p:
    case PList{}:
      run.list(root, json)
    case PShow{n}:
      run.show(root, json, n)
    case PUse{n}:
      run.use(root, json, n)
    case PSet{n, k, v}:
      run.set(root, json, n, k, v)
    case PRemove{n}:
      run.gone(root, json, n)
    case PBad{msg}:
      IO.pure(Cmd.Out, Cmd.Out{2, "", "cswap profile: error: " ++ msg ++ "\n"})

# `cswap profile ARGS...`: `args` are the words after `profile` with the
# `--json` / `--debug` flags already taken off, `json` the --json flag.
def profile(+root: String, args: List<String>, +json: Bool) -> IO(Cmd.Out):
  run(root, plan.of(args), json)
