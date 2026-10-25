import Base
import ../json.bend as Json
import ./base.bend as SBase

# ---- sequence.json, as Json -------------------------------------------------------

def jstr(+s: String) -> Json.Json:
  Json.JStr{s}

def jnum(+n: U32) -> Json.Json:
  Json.JNum{U32.show(n)}

def obj1(+k: String, +v: Json.Json) -> Json.Json:
  Json.JObj{Json.JField{k, v, Json.JNil{}}}

# A new roster: no accounts, nobody active.
def seq_fresh(+ts: String) -> Json.Json:
  Json.JObj{Json.JField{"activeAccountNumber", Json.JNull{}, Json.JField{"lastUpdated", jstr(ts),
    Json.JField{"sequence", Json.JArr{Json.JNil{}}, Json.JField{"accounts", Json.JObj{Json.JNil{}}, Json.JNil{}}}}}}

def get_or2(+m: Maybe<&2, Json.Json>, +d: Json.Json) -> Json.Json:
  match m:
    case None{}:
      d
    case Some{v}:
      v

def get_or(+key: String, +j: Json.Json, +d: Json.Json) -> Json.Json:
  get_or2(Json.get(key, j), d)

def str_or(+m: Maybe<&2, String>, +d: String) -> String:
  match m:
    case None{}:
      d
    case Some{s}:
      s

# A string field, "" when missing or not a string.
def field_str(+rec: Json.Json, +key: String) -> String:
  str_or(Maybe.bind(&2, Json.Json, String, Json.get(key, rec), Json.as_string), "")

def unwrap_obj(+j: Json.Json) -> Json.Json:
  match j:
    case Json.JObj{fields}:
      fields
    case _:
      Json.JNil{}

def unwrap_arr(+j: Json.Json) -> Json.Json:
  match j:
    case Json.JArr{items}:
      items
    case _:
      Json.JNil{}

def accounts_of(+seq: Json.Json) -> Json.Json:
  get_or("accounts", seq, Json.JObj{Json.JNil{}})

# The fields chain of `accounts`, and the items chain of `sequence`.
def fields_of(+seq: Json.Json) -> Json.Json:
  unwrap_obj(accounts_of(seq))

def items_of(+seq: Json.Json) -> Json.Json:
  unwrap_arr(get_or("sequence", seq, Json.JNil{}))

def rec_is(+rec: Json.Json, +email: String, +org: String) -> Bool:
  String.eq(field_str(rec, "email"), email) && String.eq(field_str(rec, "organizationUuid"), org)

def pick_slot(+hit: Bool, +k: String, +rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{k}
    case False{}:
      rest

def find_in(+fields: Json.Json, +email: String, +org: String) -> Maybe<&2, String>:
  match fields:
    case Json.JField{k, v, t}:
      pick_slot(rec_is(v, email, org), k, find_in(t, email, org))
    case _:
      None{}

# The slot whose record is (email, organizationUuid), as `_find_account_slot`.
def find_slot(+seq: Json.Json, +email: String, +org: String) -> Maybe<&2, String>:
  find_in(fields_of(seq), email, org)

def sel.u(+c: Bool, +x: U32, +y: U32) -> U32:
  match c:
    case True{}:
      x
    case False{}:
      y

def max_u32(+a: U32, +b: U32) -> U32:
  sel.u(U32.is_gt(a, b), a, b)

def str_u32(+s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

def max_in(+fields: Json.Json, +acc: U32) -> U32:
  match fields:
    case Json.JField{k, v, t}:
      max_in(t, max_u32(acc, str_u32(k)))
    case _:
      acc

# max(slot) + 1, or 1 for an empty roster.
def next_slot(+seq: Json.Json) -> U32:
  (max_in(fields_of(seq), 0) + 1 : U32)

def slot_record(+seq: Json.Json, +num: String) -> Maybe<&2, Json.Json>:
  Json.get(num, accounts_of(seq))

def is_api_key_rec(+rec: Json.Json) -> Bool:
  String.eq(field_str(rec, "kind"), "api_key")

def num_of(+m: Maybe<&2, U32>, +rest: List<&2, U32>) -> List<&2, U32>:
  match m:
    case None{}:
      rest
    case Some{n}:
      n <> rest

# The slot numbers listed in `sequence`.
def nums_of(+items: Json.Json) -> List<&2, U32>:
  match items:
    case Json.JCons{h, t}:
      num_of(Json.as_u32(h), nums_of(t))
    case _:
      []

def seq_nums(+seq: Json.Json) -> List<&2, U32>:
  nums_of(items_of(seq))

def insert_pick(+lt: Bool, +eq: Bool, +n: U32, +h: U32, +t: List<&2, U32>, +ins: List<&2, U32>) -> List<&2, U32>:
  match lt eq:
    case True{} _:
      n <> h <> t
    case False{} True{}:
      h <> t
    case False{} False{}:
      h <> ins

def insert_sorted(+n: U32, +xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      [n]
    case Con{h, t}:
      insert_pick(U32.is_lt(n, h), U32.is_eq(n, h), n, h, t, insert_sorted(n, t))

def without_pick(+drop: Bool, +h: U32, +rest: List<&2, U32>) -> List<&2, U32>:
  match drop:
    case True{}:
      rest
    case False{}:
      h <> rest

def without(+n: U32, +xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      without_pick(U32.is_eq(n, h), h, without(n, t))

def nums_json2(+xs: List<&2, U32>) -> List<&2, Json.Json>:
  match xs:
    case Nil{}:
      []
    case Con{h, t}:
      jnum(h) <> nums_json2(t)

def nums_json(+xs: List<&2, U32>) -> Json.Json:
  Json.arr(nums_json2(xs))

def stamp(+seq: Json.Json, +ts: String) -> Json.Json:
  Json.set("lastUpdated", jstr(ts), seq)

def set_active(+seq: Json.Json, +n: U32) -> Json.Json:
  Json.set("activeAccountNumber", jnum(n), seq)

# Record `rec` under slot `num` (replacing in place or appending) and list the
# slot in `sequence`, kept sorted.
def put_account(+seq: Json.Json, +num: String, +rec: Json.Json) -> Json.Json:
  Json.set("sequence", nums_json(insert_sorted(str_u32(num), seq_nums(seq))),
    Json.set("accounts", Json.set(num, rec, accounts_of(seq)), seq))

# Forget slot `num`: its record and its place in `sequence`.
def drop_account(+seq: Json.Json, +num: String) -> Json.Json:
  Json.set("sequence", nums_json(without(str_u32(num), seq_nums(seq))),
    Json.set("accounts", Json.del(num, accounts_of(seq)), seq))

def alias_in(+fields: Json.Json, +a: String) -> Maybe<&2, String>:
  match fields:
    case Json.JField{k, v, t}:
      pick_slot(String.eq(String.to_lower(field_str(v, "alias")), a) && SBase.nonempty(a), k, alias_in(t, a))
    case _:
      None{}

def find_alias(+seq: Json.Json, +alias: String) -> Maybe<&2, String>:
  alias_in(fields_of(seq), String.to_lower(alias))

def emails_pick(+hit: Bool, +k: String, +rest: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      k <> rest
    case False{}:
      rest

def emails_in(+fields: Json.Json, +email: String) -> List<&2, String>:
  match fields:
    case Json.JField{k, v, t}:
      emails_pick(String.eq(field_str(v, "email"), email), k, emails_in(t, email))
    case _:
      []

def slots_for_email(+seq: Json.Json, +email: String) -> List<&2, String>:
  emails_in(fields_of(seq), email)

def org_tag2(+n: String) -> String:
  SBase.sel.s(String.is_empty(n), "personal", n)

def org_tag(+rec: Json.Json) -> String:
  org_tag2(field_str(rec, "organizationName"))

def amb_org(+rec: Json.Json) -> Maybe<&2, String>:
  Some{org_tag(rec)}

def amb_details(+seq: Json.Json, +slots: List<&2, String>) -> List<&2, String>:
  match slots:
    case Nil{}:
      []
    case Con{n, t}:
      (n ++ " [" ++ str_or(Maybe.bind(&2, Json.Json, String, slot_record(seq, n), r => amb_org(r)), "personal") ++ "]") <> amb_details(seq, t)

# The reference's ambiguity text for an email in several orgs.
def ambiguous_msg(+seq: Json.Json, +email: String, +slots: List<&2, String>) -> String:
  "Email '" ++ email ++ "' is ambiguous — matches accounts: " ++ String.join(amb_details(seq, slots), ", ")
    ++ ". Use account number instead (e.g., cswap --switch-to 1)."

# A slot number, an alias, an email: in that order (`_resolve_account_identifier`).
type Resolved is Data:
  RSlot{num: String}
  RNone{}
  RAmb{msg: String}

def resolve_email(+seq: Json.Json, +ident: String, +slots: List<&2, String>) -> Resolved:
  match slots:
    case Nil{}:
      RNone{}
    case Con{n, Nil{}}:
      RSlot{n}
    case _:
      RAmb{ambiguous_msg(seq, ident, slots)}

def resolve_by_alias(+seq: Json.Json, +ident: String, +m: Maybe<&2, String>) -> Resolved:
  match m:
    case Some{n}:
      RSlot{n}
    case None{}:
      resolve_email(seq, ident, slots_for_email(seq, ident))

def resolve_digits(+digits: Bool, +seq: Json.Json, +ident: String) -> Resolved:
  match digits:
    case True{}:
      RSlot{ident}
    case False{}:
      resolve_by_alias(seq, ident, find_alias(seq, ident))

def resolve(+seq: Json.Json, +ident: String) -> Resolved:
  resolve_digits(SBase.all_digits(ident) && SBase.nonempty(ident), seq, ident)
