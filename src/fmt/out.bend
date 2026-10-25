import Base
import ../json.bend as Json
import ../cmd.bend as Cmd
import ./shape.bend as Shape
import ./yaml.bend as Yaml
import ./toon.bend as Toon
import ./code.bend as Code

# Output formats: the `--format` names, a JSON document rendered in a format,
# and a command's output converted to a format. Pure.

type Fmt is Data:
  FText{}
  FJson{}
  FCsv{}
  FYaml{}
  FToon{}

# The format a code (code.bend) stands for.
def of_code(+n: U32) -> Fmt:
  Bool.pick(Fmt, U32.is_eq(n, 1), FJson{},
  Bool.pick(Fmt, U32.is_eq(n, 2), FCsv{},
  Bool.pick(Fmt, U32.is_eq(n, 3), FYaml{},
  Bool.pick(Fmt, U32.is_eq(n, 4), FToon{}, FText{}))))

def of_name.code(m: Maybe<&2, U32>) -> Maybe<&2, Fmt>:
  match m:
    case Some{n}:
      Some{of_code(n)}
    case None{}:
      None{}

def of_name(+s: String) -> Maybe<&2, Fmt>:
  of_name.code(Code.of_name(s))

def name(f: Fmt) -> String:
  match f:
    case FText{}:
      "text"
    case FJson{}:
      "json"
    case FCsv{}:
      "csv"
    case FYaml{}:
      "yaml"
    case FToon{}:
      "toon"

def is_text(f: Fmt) -> Bool:
  match f:
    case FText{}:
      True{}
    case _:
      False{}

def is_json(f: Fmt) -> Bool:
  match f:
    case FJson{}:
      True{}
    case _:
      False{}

# The document in the format, ending in a newline. `key` names the CSV shape
# (see shape.bend).
def render(f: Fmt, +key: String, +j: Json.Json) -> String:
  match f:
    case FCsv{}:
      Shape.csv_of(key, j)
    case FYaml{}:
      Yaml.emit(j) ++ "\n"
    case FToon{}:
      Toon.emit(j) ++ "\n"
    case _:
      Json.emit_pretty(j) ++ "\n"

# ---- a command's output as a document -----------------------------------------------

def is_container(j: Json.Json) -> Bool:
  match j:
    case Json.JObj{x}:
      True{}
    case Json.JArr{x}:
      True{}
    case _:
      False{}

def is_doc(r: Result<&2, &2, String, Json.Json>) -> Bool:
  match r:
    case Done{j}:
      is_container(j)
    case Fail{e}:
      False{}

def unwrap_doc(r: Result<&2, &2, String, Json.Json>) -> Json.Json:
  match r:
    case Done{j}:
      j
    case Fail{e}:
      Json.JNull{}

def message_doc(+m: String) -> Json.Json:
  Json.of_pairs([("schemaVersion", Json.JNum{"1"}), ("message", Json.JStr{m})])

def strip_error(+m: String) -> String:
  Bool.pick(String, String.starts_with(m, "Error: "), String.drop(m, 7n), m)

def error_doc(+m: String) -> Json.Json:
  Json.of_pairs([("schemaVersion", Json.JNum{"1"}), ("error", Json.of_pairs([("type", Json.JStr{"Error"}), ("message", Json.JStr{strip_error(String.trim_end(m))})]))])

def text_of(+out: String, +err: String) -> String:
  Bool.pick(String, String.is_empty(String.trim(out)), String.trim_end(err), String.trim_end(out))

def plain(+code: U32, +out: String, +err: String) -> Maybe<&2, Json.Json>:
  Bool.pick(Maybe<&2, Json.Json>, U32.is_eq(code, 0), Some{message_doc(text_of(out, err))},
  Bool.pick(Maybe<&2, Json.Json>, U32.is_eq(code, 1) && String.is_empty(out) && Bool.not(String.is_empty(err)), Some{error_doc(err)}, None{}))

def doc2(ok: Bool, r: Result<&2, &2, String, Json.Json>, +code: U32, +out: String, +err: String) -> Maybe<&2, Json.Json>:
  match ok:
    case True{}:
      Some{unwrap_doc(r)}
    case False{}:
      plain(code, out, err)

# The JSON document a command's output stands for: its own JSON when stdout
# holds an object or array; else `{schemaVersion, message}` for a success and
# `{schemaVersion, error:{type, message}}` for an exit-1 error that went to
# stderr; none for a usage error (exit 2).
def doc_of(o: Cmd.Out) -> Maybe<&2, Json.Json>:
  match o:
    case Cmd.Out{code, +out, err}:
      doc2(is_doc(Json.parse(out)), Json.parse(out), code, out, err)

def keep_err(code: U32, out: String, err: String) -> String:
  Bool.pick(String, U32.is_eq(code, 0) && Bool.not(String.is_empty(String.trim(out))), err, "")

def conv2(f: Fmt, key: String, o: Cmd.Out, j: Json.Json) -> Cmd.Out:
  match o:
    case Cmd.Out{+code, out, err}:
      Cmd.Out{code, render(f, key, j), keep_err(code, out, err)}

def conv(f: Fmt, key: String, o: Cmd.Out, m: Maybe<&2, Json.Json>) -> Cmd.Out:
  match m:
    case None{}:
      o
    case Some{j}:
      conv2(f, key, o, j)

# The command's output in format `f` (text leaves it alone, and so does json
# when the command already printed JSON: that output is the --json output).
def convert(f: Fmt, key: String, +o: Cmd.Out) -> Cmd.Out:
  match f:
    case FText{}:
      o
    case _:
      conv(f, key, o, doc_of(o))

# ---- the `auto` event stream -------------------------------------------------------------

# Printed once before the first event (CSV: the header line).
def stream_head(f: Fmt) -> String:
  match f:
    case FCsv{}:
      Shape.event_header()
    case _:
      ""

# One event as the text IO.print puts on its own line(s): a JSON line, a CSV
# row, a `---` YAML document, a TOON document followed by a blank line.
def event_text(f: Fmt, +e: Json.Json) -> String:
  match f:
    case FCsv{}:
      Shape.event_row(e)
    case FYaml{}:
      "---\n" ++ Yaml.emit(e)
    case FToon{}:
      Toon.emit(e) ++ "\n"
    case _:
      Json.emit_py(e)
