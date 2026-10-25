import Base
import ./json.bend as Json

# What a CLI command answers: the exit code and the text for each stream.
# `out` and `err` carry their own newlines. main prints them and exits.

type Out is Data:
  Out{code: U32, out: String, err: String}

def ok(text: String) -> Out:
  Out{0, text ++ "\n", ""}

def silent() -> Out:
  Out{0, "", ""}

# A handled error, text mode: `Error: <message>` on stderr, exit 1.
def fail(msg: String) -> Out:
  Out{1, "", "Error: " ++ msg ++ "\n"}

# A usage error (argparse): the message on stderr, exit 2.
def usage(msg: String) -> Out:
  Out{2, "", "cswap: error: " ++ msg ++ "\n"}

# The --json error envelope: stdout, exit 1.
def json_fail(kind: String, msg: String) -> Out:
  Out{1, Json.emit_pretty(Json.of_pairs([
    ("schemaVersion", Json.JNum{"1"}),
    ("error", Json.of_pairs([("type", Json.JStr{kind}), ("message", Json.JStr{msg})]))])) ++ "\n", ""}

# `json` picks the envelope or the text error.
def failed(json: Bool, kind: String, msg: String) -> Out:
  match json:
    case True{}:
      json_fail(kind, msg)
    case False{}:
      fail(msg)

# A JSON document on stdout, indent=2.
def doc(j: Json.Json) -> Out:
  Out{0, Json.emit_pretty(j) ++ "\n", ""}
