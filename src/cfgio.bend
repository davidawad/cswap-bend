import Base
import ./json.bend as Json
import ./act.bend as Act
import ./cmd.bend as Cmd
import ./fs.bend as Fs
import ./setcmd.bend as Setcmd
import ./setload.bend as Setload
import ./setimp.bend as Imp
import ./profile.bend as P
import ./profcmd.bend as Profcmd
import ./clibase.bend as Clibase

# `cswap config export | import` and `cswap profile export | import`: the
# whole settings file (or just the profiles) out as a document, a settings
# document in from a file or standard input, in json, yaml, toon or csv.
# Export prints JSON; `--format` (the global one) converts it. Import checks
# every known key as `config set` / `profile set` does, keeps what it does
# not know, merges into the settings on disk (`--replace` replaces them) and
# writes the file atomically; nothing is written when any value is bad.

# What the input held: its format, its top-level keys and the checked document.
type Doc is Data:
  Doc{fmt: String, keys: List<&2, String>, norm: Json.Json}

type Parsed is Data:
  Parsed{fmt: String, doc: Json.Json}

# FILE (or `-`), `--format NAME`, `--replace`, `--data TEXT` (the document
# itself, instead of a file), and the flag whose value is due (`want`).
type IA is Data:
  IA{file: Maybe<&2, String>, fmt: Maybe<&2, String>, replace: Bool, err: String, want: String, data: Maybe<&2, String>}

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

# ---- the arguments of an import ---------------------------------------------------------

def ia.err(+a: IA, msg: String) -> IA:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      IA{file, fmt, replace, Bool.pick(String, String.is_empty(err), msg, err), "", data}

def ia.val(+a: IA, +v: String) -> IA:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      Bool.pick(IA, String.eq(w, "--data"), IA{file, fmt, replace, err, "", Some{v}}, IA{file, Some{v}, replace, err, "", data})

def ia.want(+a: IA, +flag: String) -> IA:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      IA{file, fmt, replace, err, flag, data}

def ia.rep(+a: IA) -> IA:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      IA{file, fmt, True{}, err, w, data}

def ia.file2(m: Maybe<&2, String>, +h: String, +a: IA) -> IA:
  match m a:
    case None{} IA{file, fmt, replace, err, w, data}:
      IA{Some{h}, fmt, replace, err, w, data}
    case Some{f} _:
      ia.err(a, "unrecognized arguments: " ++ h)

def ia.get_file(+a: IA) -> Maybe<&2, String>:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      file

def ia.file(+h: String, +a: IA) -> IA:
  ia.file2(ia.get_file(a), h, a)

def ia.is_pending(+a: IA) -> Bool:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      Bool.not(String.is_empty(w))

def sel.ia(c: Bool, +x: IA, +y: IA) -> IA:
  match c:
    case True{}:
      x
    case False{}:
      y

def ia.free(+h: String, +a: IA) -> IA:
  sel.ia(String.eq(h, "--format") || String.eq(h, "--data"), ia.want(a, h),
  sel.ia(String.starts_with(h, "--format="), ia.val(ia.want(a, "--format"), String.drop(h, 9n)),
  sel.ia(String.starts_with(h, "--data="), ia.val(ia.want(a, "--data"), String.drop(h, 7n)),
  sel.ia(String.eq(h, "--replace"), ia.rep(a),
  sel.ia(String.starts_with(h, "-") && Bool.not(String.eq(h, "-")), ia.err(a, "unrecognized arguments: " ++ h),
  ia.file(h, a))))))

def ia.step(+h: String, +a: IA) -> IA:
  sel.ia(ia.is_pending(a), ia.val(a, h), ia.free(h, a))

def ia.go(args: List<&2, String>, +a: IA) -> IA:
  match args:
    case Nil{}:
      a
    case Con{h, t}:
      ia.go(t, ia.step(h, a))

def ia.need(file: Bool, data: Bool, +a: IA) -> IA:
  match file data:
    case False{} False{}:
      ia.err(a, "the following arguments are required: FILE")
    case True{} True{}:
      ia.err(a, "give a FILE or --data, not both")
    case _ _:
      a

def ia.end2(+a: IA) -> IA:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      ia.need(Maybe.is_some(&2, String, file), Maybe.is_some(&2, String, data), a)

def ia.end(+a: IA) -> IA:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      ia.end2(Bool.pick(IA, String.is_empty(w), a, ia.err(a, "argument " ++ w ++ ": expected one argument")))

def ia.parse(args: List<&2, String>) -> IA:
  ia.end(ia.go(args, IA{None{}, None{}, False{}, "", "", None{}}))

# ---- reading --------------------------------------------------------------------------------

def failed(+code: U32, +msg: String) -> Act.of(String):
  Act.fail(String, code, msg)

def read_stdin(noin: Bool) -> Act.of(String):
  match noin:
    case True{}:
      failed(2, "standard input is not available here; give a file")
    case False{}:
      Fs.read_stdin()

def read_path(r: Fs.Res(String), +path: String) -> Act.of(String):
  match r:
    case Done{t}:
      Act.pure(String, t)
    case Fail{e}:
      failed(1, "could not read " ++ path ++ ": " ++ Setcmd.err.msg(e))

def read_input2(dash: Bool, +path: String, noin: Bool) -> Act.of(String):
  match dash:
    case True{}:
      read_stdin(noin)
    case False{}:
      IO.bind(Fs.Res(String), Fs.Res(String), Fs.read_file(path), r => read_path(r, path))

def lift_str(r: Result<&2, &2, String, String>) -> Act.of(String):
  match r:
    case Done{s}:
      Act.pure(String, s)
    case Fail{m}:
      failed(1, m)

def lift_json(r: Result<&2, &2, String, Json.Json>) -> Act.of(Json.Json):
  match r:
    case Done{j}:
      Act.pure(Json.Json, j)
    case Fail{m}:
      Act.fail(Json.Json, 1, m)

def lift_unit(r: Result<&2, &2, String, Unit>) -> Act.of(Unit):
  match r:
    case Done{u}:
      Act.pure(Unit, Unit{})
    case Fail{m}:
      Act.fail(Unit, 1, m)

def keys_check(only: Bool, +doc: Json.Json) -> Act.of(Unit):
  match only:
    case True{}:
      lift_unit(Imp.profile_only(Json.keys(doc)))
    case False{}:
      Act.pure(Unit, Unit{})

def active_found(m: Maybe<&2, P.Prof>, +name: String) -> Act.of(Unit):
  match m:
    case Some{p}:
      Act.pure(Unit, Unit{})
    case None{}:
      Act.fail(Unit, 1, "active_profile '" ++ name ++ "' names no profile; `cswap profile list` shows the profiles")

# ---- merging ---------------------------------------------------------------------------------

def active_check(m: Maybe<&2, String>, +merged: Json.Json) -> Act.of(Unit):
  match m:
    case None{}:
      Act.pure(Unit, Unit{})
    case Some{+name}:
      active_found(P.find(merged, name), name)

# --replace for `profile import` drops the stored profiles first.
def base_of(only: Bool, replace: Bool, +raw: Json.Json) -> Json.Json:
  Bool.pick(Json.Json, only && replace, Json.del("active_profile", Json.del("profiles", raw)), raw)

def combine(+replace: Bool, +only: Bool, +norm: Json.Json, +raw: Json.Json) -> Json.Json:
  Setload.with_version(Bool.pick(Json.Json, replace && Bool.not(only), Imp.strip(norm), Imp.merge(norm, base_of(only, replace, raw))))

# ---- the result ----------------------------------------------------------------------------------

def key_names(ks: List<&2, String>) -> String:
  String.join(ks, ", ")

def strs(ks: List<&2, String>) -> List<&2, Json.Json>:
  match ks:
    case Nil{}:
      []
    case Con{h, t}:
      Json.JStr{h} <> strs(t)

def done_out(json: Bool, +path: String, +f: String, +keys: List<&2, String>) -> Cmd.Out:
  match json:
    case True{}:
      Cmd.doc(Json.of_pairs([("schemaVersion", Json.JNum{"1"}), ("source", Json.JStr{path}), ("format", Json.JStr{f}), ("keys", Json.arr(strs(keys)))]))
    case False{}:
      Cmd.ok("Imported " ++ Nat.show(List.length(&2, String, keys)) ++ " key(s) from " ++ path ++ " as " ++ f ++ ": " ++ key_names(keys))

def ia.get_fmt(+a: IA) -> Maybe<&2, String>:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      fmt

def ia.get_replace(+a: IA) -> Bool:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      replace

def ia.get_data(+a: IA) -> Maybe<&2, String>:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      data

def read_src(data: Maybe<&2, String>, +path: String, noin: Bool) -> Act.of(String):
  match data:
    case Some{t}:
      Act.pure(String, t)
    case None{}:
      read_input2(String.eq(path, "-"), path, noin)

def parse_input(+path: String, fmt: Maybe<&2, String>, data: Maybe<&2, String>, noin: Bool) -> Act.of(Parsed):
  do ActM<Parsed>:
    +text : String <- read_src(data, path, noin)
    +f : String <- lift_str(Imp.pick_format(fmt, path))
    +doc : Json.Json <- lift_json(Imp.parse_doc(f, text))
    Act.pure(Parsed, Parsed{f, doc})

def check_doc(only: Bool, +doc: Json.Json) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    keys_check(only, doc)
    lift_json(Imp.normalize(doc))

def loaded(+p: Parsed, only: Bool) -> Act.of(Doc):
  match p:
    case Parsed{f, doc}:
      Act.bind(Json.Json, Doc, check_doc(only, doc), norm => Act.pure(Doc, Doc{f, Json.keys(doc), norm}))

def load_doc(+path: String, fmt: Maybe<&2, String>, data: Maybe<&2, String>, noin: Bool, only: Bool) -> Act.of(Doc):
  Act.bind(Parsed, Doc, parse_input(path, fmt, data, noin), p => loaded(p, only))

def save_doc(+root: String, +path: String, +d: Doc, replace: Bool, json: Bool, only: Bool) -> Act.of(Cmd.Out):
  match d:
    case Doc{f, keys, norm}:
      do ActM<Cmd.Out>:
        +raw : Json.Json <- Setcmd.load_raw_w(root)
        +merged : Json.Json = combine(replace, only, norm, raw)
        active_check(P.active(merged), merged)
        Setcmd.write_settings(root, merged)
        Act.pure(Cmd.Out, done_out(json, path, f, keys))

def import_run(+root: String, +path: String, fmt: Maybe<&2, String>, data: Maybe<&2, String>, replace: Bool, noin: Bool, json: Bool, +only: Bool) -> Act.of(Cmd.Out):
  Act.bind(Doc, Cmd.Out, load_doc(path, fmt, data, noin, only), d => save_doc(root, path, d, replace, json, only))

def import_act(+root: String, +a: IA, noin: Bool, json: Bool, only: Bool) -> Act.of(Cmd.Out):
  import_run(root, Maybe.default(&2, String, ia.get_file(a), "(data)"), ia.get_fmt(a), ia.get_data(a), ia.get_replace(a), noin, json, only)

def ia.err_of(+a: IA) -> String:
  match a:
    case IA{file, fmt, replace, err, w, data}:
      err

def import_ok(ok: Bool, +err: String, +a: IA, +root: String, noin: Bool, json: Bool, only: Bool) -> IO(Cmd.Out):
  match ok:
    case True{}:
      IO.bind(Fs.Res(Cmd.Out), Cmd.Out, import_act(root, a, noin, json, only), r => IO.pure(Cmd.Out, Setcmd.fin(r)))
    case False{}:
      IO.pure(Cmd.Out, Cmd.Out{2, "", "cswap: error: " ++ err ++ "\n"})

# ---- export ------------------------------------------------------------------------------------------

def import_gate(+a: IA, +root: String, noin: Bool, json: Bool, only: Bool) -> IO(Cmd.Out):
  import_ok(String.is_empty(ia.err_of(a)), ia.err_of(a), a, root, noin, json, only)

def import_cmd(+root: String, args: List<&2, String>, noin: Bool, json: Bool, only: Bool) -> IO(Cmd.Out):
  import_gate(ia.parse(args), root, noin, json, only)

def config_export(+root: String) -> IO(Cmd.Out):
  IO.bind(Json.Json, Cmd.Out, Setload.load_raw(root), raw => IO.pure(Cmd.Out, Cmd.doc(raw)))

def with_active(m: Maybe<&2, String>, +doc: Json.Json) -> Json.Json:
  match m:
    case Some{n}:
      Json.set("active_profile", Json.JStr{n}, doc)
    case None{}:
      doc

def all_profiles(+raw: Json.Json) -> Json.Json:
  with_active(P.active(raw), Json.of_pairs([("profiles", P.obj_of(Json.get("profiles", raw)))]))

def one_profile(stored: Bool, +raw: Json.Json, +name: String) -> Cmd.Out:
  match stored:
    case True{}:
      Cmd.doc(Json.of_pairs([("profiles", Json.of_pairs([(name, P.obj_of(Json.get(name, P.obj_of(Json.get("profiles", raw)))))]))]))
    case False{}:
      Cmd.fail(Profcmd.gone_missing(P.is_builtin(name), name))

def profile_export_out(m: Maybe<&2, String>, +raw: Json.Json) -> Cmd.Out:
  match m:
    case None{}:
      Cmd.doc(all_profiles(raw))
    case Some{+name}:
      one_profile(P.has_stored(raw, name), raw, name)

def profile_export(+root: String, n: Maybe<&2, String>) -> IO(Cmd.Out):
  IO.bind(Json.Json, Cmd.Out, Setload.load_raw(root), raw => IO.pure(Cmd.Out, profile_export_out(n, raw)))

# ---- dispatch ------------------------------------------------------------------------------------------

def usage(+verb: String, +msg: String) -> Cmd.Out:
  Cmd.Out{2, "", "cswap " ++ verb ++ ": error: " ++ msg ++ "\n"}

def export_args(+verb: String, rest: List<&2, String>, run: IO(Cmd.Out)) -> IO(Cmd.Out):
  match rest:
    case Nil{}:
      run
    case Con{h, t}:
      IO.pure(Cmd.Out, usage(verb, "unrecognized arguments: " ++ String.join(Con{h, t}, " ")))

def profile_name_args(+root: String, rest: List<&2, String>) -> IO(Cmd.Out):
  match rest:
    case Nil{}:
      profile_export(root, None{})
    case Con{n, Nil{}}:
      profile_export(root, Some{n})
    case Con{n, Con{x, t}}:
      IO.pure(Cmd.Out, usage("profile", "unrecognized arguments: " ++ String.join(Con{x, t}, " ")))

def config2(+root: String, +word: String, +rest: List<&2, String>, args: List<&2, String>, +json: Bool, noin: Bool) -> IO(Cmd.Out):
  Bool.pick(IO(Cmd.Out), String.eq(word, "export"), export_args("config", rest, config_export(root)),
  Bool.pick(IO(Cmd.Out), String.eq(word, "import"), import_cmd(root, rest, noin, json, False{}), Setcmd.config(root, Clibase.affine(args), json)))

# `cswap config ARGS...` (the words after `config`, --json/--debug taken off).
def config(+root: String, args: List<&2, String>, json: Bool, noin: Bool) -> IO(Cmd.Out):
  match args:
    case Nil{}:
      Setcmd.config(root, Clibase.affine(args), json)
    case Con{+h, +t}:
      config2(root, h, t, Con{h, t}, json, noin)

def profile2(+root: String, +word: String, +rest: List<&2, String>, args: List<&2, String>, +json: Bool, noin: Bool) -> IO(Cmd.Out):
  Bool.pick(IO(Cmd.Out), String.eq(word, "export"), profile_name_args(root, rest),
  Bool.pick(IO(Cmd.Out), String.eq(word, "import"), import_cmd(root, rest, noin, json, True{}), Profcmd.profile(root, Clibase.affine(args), json)))

# `cswap profile ARGS...`.
def profile(+root: String, args: List<&2, String>, json: Bool, noin: Bool) -> IO(Cmd.Out):
  match args:
    case Nil{}:
      Profcmd.profile(root, Clibase.affine(args), json)
    case Con{+h, +t}:
      profile2(root, h, t, Con{h, t}, json, noin)
