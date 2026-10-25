import Base
import ../json.bend as Json
import ./csv.bend as Csv

# The tabular shape of a command's JSON document, for `--format csv`.
#
#   list           one row per account
#   status         one row for the active account (no row when none)
#   config         one row per setting: key,value,is_set
#   profile list   one row per profile
#   auto           one row per event, fixed columns
#   export         one row per leaf: key,value (dotted keys)
#   anything else  one row: the document's leaves as dotted-key columns
#
# A cell is empty for null, true/false, the number's text, the string itself;
# an array of scalars is its items joined by `;`, anything else compact JSON.
# Pure.

type Col is Data:
  Col{h: String, p: List<&2, String>}

type Leaf is Data:
  Leaf{k: String, v: String}

# ---- cells -------------------------------------------------------------------

def or_null(m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case None{}:
      Json.JNull{}
    case Some{v}:
      v

def get_or_null(+j: Json.Json, +k: String) -> Json.Json:
  or_null(Json.get(k, j))

# The value at a key path; null when any step is missing.
def path(ks: List<&2, String>, +j: Json.Json) -> Json.Json:
  match ks:
    case Nil{}:
      j
    case Con{k, t}:
      path(t, get_or_null(j, k))

def is_scalar(j: Json.Json) -> Bool:
  match j:
    case Json.JArr{x}:
      False{}
    case Json.JObj{x}:
      False{}
    case _:
      True{}

# A scalar as its text; a container as compact JSON.
def scal(+j: Json.Json) -> String:
  match j:
    case Json.JNull{}:
      ""
    case Json.JBool{b}:
      Json.bool.show(b)
    case Json.JNum{t}:
      t
    case Json.JStr{s}:
      s
    case _:
      Json.emit(j)

def all_scalar(items: Json.Json) -> Bool:
  match items:
    case Json.JCons{h, t}:
      is_scalar(h) && all_scalar(t)
    case _:
      True{}

def sep_of(t: Json.Json) -> String:
  match t:
    case Json.JNil{}:
      ""
    case _:
      ";"

def joined(items: Json.Json) -> String:
  match items:
    case Json.JCons{h, +t}:
      scal(h) ++ sep_of(t) ++ joined(t)
    case _:
      ""

def cell.arr(ok: Bool, +items: Json.Json) -> String:
  match ok:
    case True{}:
      joined(items)
    case False{}:
      Json.emit(Json.JArr{items})

def cell(+j: Json.Json) -> String:
  match j:
    case Json.JArr{+items}:
      cell.arr(all_scalar(items), items)
    case _:
      scal(j)

# ---- columns --------------------------------------------------------------------

def col(h: String, p: List<&2, String>) -> Col:
  Col{h, p}

def headers(cols: List<&2, Col>) -> List<&2, String>:
  match cols:
    case Nil{}:
      []
    case Con{Col{h, p}, t}:
      h <> headers(t)

def cells(+j: Json.Json, cols: List<&2, Col>) -> List<&2, String>:
  match cols:
    case Nil{}:
      []
    case Con{Col{h, p}, t}:
      cell(path(p, j)) <> cells(j, t)

def rows(items: List<&2, Json.Json>, +cols: List<&2, Col>) -> List<&2, List<&2, String>>:
  match items:
    case Nil{}:
      []
    case Con{+h, t}:
      cells(h, cols) <> rows(t, cols)

def table(+cols: List<&2, Col>, items: List<&2, Json.Json>) -> String:
  Csv.table(headers(cols) <> rows(items, cols))

def account_cols() -> List<&2, Col>:
  [col("slot", ["number"]), col("email", ["email"]), col("org", ["organizationName"]), col("kind", ["usageStatus"]), col("active", ["active"]),
   col("5h_pct", ["usage", "fiveHour", "pct"]), col("5h_reset", ["usage", "fiveHour", "resetsAt"]),
   col("7d_pct", ["usage", "sevenDay", "pct"]), col("7d_reset", ["usage", "sevenDay", "resetsAt"]),
   col("fetched_at", ["usageFetchedAt"]), col("error", ["usageError"])]

def setting_cols() -> List<&2, Col>:
  [col("key", ["key"]), col("value", ["value"]), col("is_set", ["isSet"])]

def profile_cols() -> List<&2, Col>:
  [col("name", ["name"]), col("builtin", ["builtin"]), col("stored", ["stored"]), col("active", ["active"]), col("strategy", ["strategy"]),
   col("threshold", ["effective", "threshold"]), col("models", ["effective", "models"]), col("cooldown_s", ["effective", "cooldown_s"]), col("interval_s", ["effective", "interval_s"])]

def event_cols() -> List<&2, Col>:
  [col("event", ["event"]), col("ts", ["ts"]), col("profile", ["profile"]), col("strategy", ["strategy"]),
   col("active_slot", ["active", "number"]), col("from_slot", ["from", "number"]), col("to_slot", ["to", "number"]),
   col("trigger", ["trigger"]), col("reason", ["reason"]), col("detail", ["detail"]), col("message", ["message"]),
   col("threshold", ["threshold"]), col("seconds", ["seconds"]), col("until", ["until"]),
   col("slot", ["number"]), col("email", ["email"]), col("dry_run", ["dryRun"]), col("earliest_reset_at", ["earliestResetAt"])]

# The header line of the `auto` event stream.
def event_header() -> String:
  Csv.row(headers(event_cols())) ++ "\n"

# One event as a CSV row (no header, no line end).
def event_row(+e: Json.Json) -> String:
  Csv.row(cells(e, event_cols()))

# ---- leaves -----------------------------------------------------------------------

def dotted(+prefix: String, +k: String) -> String:
  Bool.pick(String, String.is_empty(prefix), k, prefix ++ "." ++ k)

def is_empty_obj(f: Json.Json) -> Bool:
  match f:
    case Json.JNil{}:
      True{}
    case _:
      False{}

def leaf.pick(empty: Bool, prefix: String, rest: List<&2, Leaf>) -> List<&2, Leaf>:
  match empty:
    case True{}:
      Leaf{prefix, "{}"} <> rest
    case False{}:
      rest

# The scalar leaves of a document with dotted keys; an array is one leaf.
def leaves(j: Json.Json, +prefix: String) -> List<&2, Leaf>:
  match j:
    case Json.JObj{+f}:
      leaf.pick(is_empty_obj(f), prefix, leaves(f, prefix))
    case Json.JField{k, v, +t}:
      List.append(&2, Leaf, leaves(v, dotted(prefix, k)), leaves(t, prefix))
    case Json.JNil{}:
      []
    case _:
      Leaf{prefix, cell(j)} <> []

def leaf_headers(ls: List<&2, Leaf>) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{Leaf{k, v}, t}:
      k <> leaf_headers(t)

def leaf_values(ls: List<&2, Leaf>) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{Leaf{k, v}, t}:
      v <> leaf_values(t)

def leaf_pairs(ls: List<&2, Leaf>) -> List<&2, List<&2, String>>:
  match ls:
    case Nil{}:
      []
    case Con{Leaf{k, v}, t}:
      [k, v] <> leaf_pairs(t)

def wide.of(+ls: List<&2, Leaf>) -> String:
  Csv.table([leaf_headers(ls), leaf_values(ls)])

# One row: the leaves as columns.
def wide(+j: Json.Json) -> String:
  wide.of(leaves(j, ""))

# key,value rows.
def kv(+j: Json.Json) -> String:
  Csv.table(["key", "value"] <> leaf_pairs(leaves(j, "")))

# ---- the dispatch ------------------------------------------------------------------

def items_at(+j: Json.Json, +k: String) -> List<&2, Json.Json>:
  Json.to_list(get_or_null(j, k))

# The active account of a status document as a list of at most one row.
def status_rows(a: Json.Json) -> List<&2, Json.Json>:
  match a:
    case Json.JObj{f}:
      [Json.set("active", Json.JBool{True{}}, Json.JObj{f})]
    case _:
      []

def some(m: Maybe<&2, Json.Json>) -> Bool:
  match m:
    case Some{e}:
      True{}
    case None{}:
      False{}

def has_error(+j: Json.Json) -> Bool:
  some(Json.get("error", j))

def by_key(+key: String, +j: Json.Json) -> String:
  Bool.pick(String, String.eq(key, "list"), table(account_cols(), items_at(j, "accounts")),
  Bool.pick(String, String.eq(key, "status"), table(account_cols(), status_rows(get_or_null(j, "active"))),
  Bool.pick(String, String.eq(key, "config-list"), table(setting_cols(), items_at(j, "settings")),
  Bool.pick(String, String.eq(key, "profile-list"), table(profile_cols(), items_at(j, "profiles")),
  Bool.pick(String, String.eq(key, "export"), kv(j), wide(j))))))

# The CSV text of a command's document. `key` names the command shape
# (list, status, config-list, profile-list, export); a document that is an
# error envelope is always one wide row.
def csv_of(+key: String, +j: Json.Json) -> String:
  Bool.pick(String, has_error(j), wide(j), by_key(key, j))
