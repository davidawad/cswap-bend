import Base
import ../json.bend as Json
import ./yamlw.bend as W
import ./yamlr.bend as R

# YAML for the JSON data model: `emit` writes block style (yamlw.bend),
# `parse` reads the subset cswap writes plus plain block maps, lists and
# scalars (yamlr.bend).

def emit(j: Json.Json) -> String:
  W.emit(j)

def flowy(+s: String) -> Bool:
  String.starts_with(String.trim_start(s), "{") || String.starts_with(String.trim_start(s), "[")

# JSON is YAML: a document that opens with `{` or `[` is read as JSON when it
# is JSON (nested flow collections, quoted keys), else by the block reader.
def parse.json(r: Result<&2, &2, String, Json.Json>, +s: String) -> Result<&2, &2, String, Json.Json>:
  match r:
    case Done{j}:
      Done{j}
    case Fail{e}:
      R.parse(s)

def parse.pick(flow: Bool, +s: String) -> Result<&2, &2, String, Json.Json>:
  match flow:
    case True{}:
      parse.json(Json.parse(s), s)
    case False{}:
      R.parse(s)

def parse(+s: String) -> Result<&2, &2, String, Json.Json>:
  parse.pick(flowy(s), s)
