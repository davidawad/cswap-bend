import Base
import ./setload.bend as Setload
import ./setwrite.bend as Setwrite
import ./fs/write.bend as FWrite
import ./json.bend as Json
import ./fs.bend as Fs
import ./act.bend as Act
import ./cmd.bend as Cmd
import ./settings.bend as Settings

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

def err.msg(e: U32 & String) -> String:
  (c, m) = e
  m

# The text of a failed Act as the command's output (exit 1).
def fin(r: Fs.Res(Cmd.Out)) -> Cmd.Out:
  match r:
    case Fail{e}:
      Cmd.fail(err.msg(e))
    case Done{o}:
      o

def read_w.obj(+p: String, j: Json.Json) -> Act.of(Json.Json):
  match j:
    case Json.JObj{f}:
      Act.pure(Json.Json, Json.JObj{f})
    case _:
      Act.fail(Json.Json, 1, p ++ " is not a JSON object; fix or delete it before changing settings")

def read_w.parse(+p: String, r: Result<&2, &2, String, Json.Json>) -> Act.of(Json.Json):
  match r:
    case Fail{e}:
      Act.fail(Json.Json, 1, p ++ " is not valid JSON (" ++ e ++ "); fix or delete it before changing settings")
    case Done{j}:
      read_w.obj(p, j)

def read_w.text(+p: String, r: Fs.Res(String)) -> Act.of(Json.Json):
  match r:
    case Fail{e}:
      Act.fail(Json.Json, 1, "could not read " ++ p ++ ": " ++ err.msg(e))
    case Done{t}:
      read_w.parse(p, Json.parse(t))

def read_w.go(+p: String, ex: Bool) -> Act.of(Json.Json):
  match ex:
    case False{}:
      Act.pure(Json.Json, Setload.empty())
    case True{}:
      IO.bind(Fs.Res(String), Fs.Res(Json.Json), Fs.read_file(p), r => read_w.text(p, r))

# settings.json for a read-modify-write: a missing file is `{}`, a torn or
# non-object file is an error (never replaced by a near-Setload.empty one).
def load_raw_w(+root: String) -> Act.of(Json.Json):
  IO.bind(Bool, Fs.Res(Json.Json), Fs.exists(Setload.path(root)), ex => read_w.go(Setload.path(root), ex))

# Atomic 0600 write of settings.json; the backup dir is made and set 0700.
def write_settings(+root: String, +j: Json.Json) -> Act.of(Unit):
  do ActM<Unit>:
    FWrite.mkdir_p(root)
    FWrite.chmod("700", root)
    FWrite.write_atomic(Setload.path(root), Json.emit_pretty(j), "600")

def list.show(+root: String, json: Bool, +rs: List<&2, Setwrite.Row>) -> Cmd.Out:
  match json:
    case True{}:
      Cmd.doc(Json.of_pairs([("schemaVersion", Json.JNum{"1"}), ("path", Json.JStr{Setload.path(root)}),
        ("settings", Json.arr(Setwrite.rows.json(rs)))]))
    case False{}:
      Cmd.ok(Setwrite.list.text(rs))

def list.out(+root: String, json: Bool, raw: Json.Json) -> Cmd.Out:
  list.show(root, json, Setwrite.effective(raw))

def run.list(+root: String, json: Bool) -> IO(Cmd.Out):
  IO.bind(Json.Json, Cmd.Out, Setload.load_raw(root), raw => IO.pure(Cmd.Out, list.out(root, json, raw)))

def get.show2(json: Bool, +sp: Settings.Spec, value: Json.Json, set: Bool, text: String) -> Cmd.Out:
  match json:
    case True{}:
      Cmd.doc(Json.of_pairs([("schemaVersion", Json.JNum{"1"}), ("key", Json.JStr{Settings.dotted(sp)}),
        ("value", value), ("isSet", Json.JBool{set})]))
    case False{}:
      Cmd.ok(text)

def get.show(json: Bool, +r: Setwrite.Row) -> Cmd.Out:
  match r:
    case Setwrite.Row{+sp, +value, +set}:
      get.show2(json, sp, value, set, Setwrite.row.val(Setwrite.Row{sp, value, set}))

def get.row(json: Bool, m: Maybe<&2, Setwrite.Row>) -> Cmd.Out:
  match m:
    case Some{r}:
      get.show(json, r)
    case None{}:
      Cmd.failed(json, "ConfigError", "unknown setting")

def get.spec(json: Bool, r: Result<&2, &2, String, Settings.Spec>, raw: Json.Json) -> Cmd.Out:
  match r:
    case Fail{m}:
      Cmd.failed(json, "ConfigError", m)
    case Done{sp}:
      get.row(json, Setwrite.row.find(Settings.dotted(sp), Setwrite.effective(raw)))

def run.get(+root: String, key: String, json: Bool) -> IO(Cmd.Out):
  IO.bind(Json.Json, Cmd.Out, Setload.load_raw(root), raw => IO.pure(Cmd.Out, get.spec(json, Settings.spec_of(key), raw)))

def set.msg(+sp: Settings.Spec, +v: Json.Json) -> String:
  Settings.dotted(sp) ++ " = " ++ Setwrite.fmt.val(Setwrite.is_float(sp), v)

def set.act(+root: String, +sp: Settings.Spec, +v: Json.Json) -> Act.of(Cmd.Out):
  do ActM<Cmd.Out>:
    +raw : Json.Json <- load_raw_w(root)
    w : Unit <- write_settings(root, Setwrite.set_in(raw, sp, v))
    Act.pure(Cmd.Out, Cmd.ok(set.msg(sp, v)))

def set.parsed(+root: String, sp: Settings.Spec, p: Setwrite.Parsed) -> IO(Cmd.Out):
  match p:
    case Setwrite.Bad{m}:
      IO.pure(Cmd.Out, Cmd.fail(m))
    case Setwrite.Good{v}:
      IO.bind(Fs.Res(Cmd.Out), Cmd.Out, set.act(root, sp, v), r => IO.pure(Cmd.Out, fin(r)))

def set.spec(+root: String, r: Result<&2, &2, String, Settings.Spec>, value: String) -> IO(Cmd.Out):
  match r:
    case Fail{m}:
      IO.pure(Cmd.Out, Cmd.fail(m))
    case Done{+sp}:
      set.parsed(root, sp, Setwrite.parse_value(sp, value))

def run.set(+root: String, key: String, value: String) -> IO(Cmd.Out):
  set.spec(root, Settings.spec_of(key), value)

def dflt_of(sp: Settings.Spec) -> Json.Json:
  match sp:
    case Settings.Spec{section, key, kind, lo, hi, choices, dflt}:
      dflt

def unset.msg(+sp: Settings.Spec) -> String:
  Settings.dotted(sp) ++ " unset (default: " ++ Setwrite.fmt.val(Setwrite.is_float(sp), dflt_of(sp)) ++ ")"

def unset.write(+root: String, +sp: Settings.Spec, +raw: Json.Json) -> Act.of(Cmd.Out):
  do ActM<Cmd.Out>:
    w : Unit <- write_settings(root, Setwrite.unset_in(raw, sp))
    Act.pure(Cmd.Out, Cmd.ok(unset.msg(sp)))

def unset.pick(present: Bool, +root: String, +sp: Settings.Spec, +raw: Json.Json) -> Act.of(Cmd.Out):
  match present:
    case True{}:
      unset.write(root, sp, raw)
    case False{}:
      Act.pure(Cmd.Out, Cmd.Out{0, "", Settings.dotted(sp) ++ " is not set; nothing to do\n"})

def section_of_spec(sp: Settings.Spec) -> String:
  match sp:
    case Settings.Spec{section, key, kind, lo, hi, choices, dflt}:
      section

def key_of(sp: Settings.Spec) -> String:
  match sp:
    case Settings.Spec{section, key, kind, lo, hi, choices, dflt}:
      key

def unset.act(+root: String, +sp: Settings.Spec) -> Act.of(Cmd.Out):
  do ActM<Cmd.Out>:
    +raw : Json.Json <- load_raw_w(root)
    unset.pick(Setwrite.has.in(Json.get(section_of_spec(sp), raw), key_of(sp)), root, sp, raw)

def unset.spec(+root: String, r: Result<&2, &2, String, Settings.Spec>) -> IO(Cmd.Out):
  match r:
    case Fail{m}:
      IO.pure(Cmd.Out, Cmd.fail(m))
    case Done{sp}:
      IO.bind(Fs.Res(Cmd.Out), Cmd.Out, unset.act(root, sp), r2 => IO.pure(Cmd.Out, fin(r2)))

def run.unset(+root: String, key: String) -> IO(Cmd.Out):
  unset.spec(root, Settings.spec_of(key))

type Plan is Data:
  PList{}
  PGet{key: String}
  PSet{key: String, value: String}
  PUnset{key: String}
  PPath{}
  PBad{msg: String}

def join_sp(xs: List<String>) -> String:
  match xs:
    case Nil{}:
      ""
    case Con{h, Nil{}}:
      h
    case Con{h, t}:
      h ++ " " ++ join_sp(t)

# Extra words after a complete verb are an argparse error.
def plan.none(rest: List<String>, p: Plan) -> Plan:
  match rest:
    case Nil{}:
      p
    case Con{x, t}:
      PBad{"unrecognized arguments: " ++ join_sp(Con{x, t})}

def plan.get(rest: List<String>) -> Plan:
  match rest:
    case Nil{}:
      PBad{"the following arguments are required: KEY"}
    case Con{k, t}:
      plan.none(t, PGet{k})

def plan.unset(rest: List<String>) -> Plan:
  match rest:
    case Nil{}:
      PBad{"the following arguments are required: KEY"}
    case Con{k, t}:
      plan.none(t, PUnset{k})

def plan.set(rest: List<String>) -> Plan:
  match rest:
    case Nil{}:
      PBad{"the following arguments are required: KEY, VALUE"}
    case Con{k, Nil{}}:
      PBad{"the following arguments are required: VALUE"}
    case Con{k, Con{v, t}}:
      plan.none(t, PSet{k, v})

def plan.verb(l: Bool, g: Bool, s: Bool, u: Bool, p: Bool, a: String, rest: List<String>) -> Plan:
  match l g s u p:
    case True{} _ _ _ _:
      plan.none(rest, PList{})
    case False{} True{} _ _ _:
      plan.get(rest)
    case False{} False{} True{} _ _:
      plan.set(rest)
    case False{} False{} False{} True{} _:
      plan.unset(rest)
    case False{} False{} False{} False{} True{}:
      plan.none(rest, PPath{})
    case _ _ _ _ _:
      PBad{"argument action: invalid choice: '" ++ a ++ "' (choose from 'list', 'get', 'set', 'unset', 'path')"}

# `config [list | get KEY | set KEY VALUE | unset KEY | path]`, flags removed.
def plan.of(args: List<String>) -> Plan:
  match args:
    case Nil{}:
      PList{}
    case Con{+a, rest}:
      plan.verb(String.eq(a, "list"), String.eq(a, "get"), String.eq(a, "set"), String.eq(a, "unset"), String.eq(a, "path"), a, rest)

def plan.gate(json: Bool, p: Plan) -> Plan:
  match json:
    case True{}:
      PBad{"--json can only be used with list or get"}
    case False{}:
      p

def plan.json(json: Bool, p: Plan) -> Plan:
  match p:
    case PSet{k, v}:
      plan.gate(json, PSet{k, v})
    case PUnset{k}:
      plan.gate(json, PUnset{k})
    case PPath{}:
      plan.gate(json, PPath{})
    case _:
      p



def run(+root: String, p: Plan, json: Bool) -> IO(Cmd.Out):
  match p:
    case PList{}:
      run.list(root, json)
    case PGet{key}:
      run.get(root, key, json)
    case PSet{key, value}:
      run.set(root, key, value)
    case PUnset{key}:
      run.unset(root, key)
    case PPath{}:
      IO.pure(Cmd.Out, Cmd.ok(Setload.path(root)))
    case PBad{msg}:
      IO.pure(Cmd.Out, Cmd.Out{2, "", "cswap config: error: " ++ msg ++ "\n"})

# `cswap config ARGS...`: `args` are the words after `config` with the
# `--json` / `--debug` flags already taken off, `json` the --json flag.
def config(+root: String, args: List<String>, +json: Bool) -> IO(Cmd.Out):
  run(root, plan.json(json, plan.of(args)), json)
