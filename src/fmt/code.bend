import Base

# The output formats as small numbers, for records that cannot name the Fmt
# type (the `auto` flags): 0 text, 1 json, 2 csv, 3 yaml, 4 toon. out.bend
# turns a code into a Fmt.

# The code of a `--format` argument, none for an unknown name.
def of_name(+s: String) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, String.eq(s, "text"), Some{0},
  Bool.pick(Maybe<&2, U32>, String.eq(s, "json"), Some{1},
  Bool.pick(Maybe<&2, U32>, String.eq(s, "csv"), Some{2},
  Bool.pick(Maybe<&2, U32>, String.eq(s, "yaml") || String.eq(s, "yml"), Some{3},
  Bool.pick(Maybe<&2, U32>, String.eq(s, "toon"), Some{4}, None{})))))

def choices() -> String:
  "'text', 'json', 'csv', 'yaml', 'toon'"

def invalid(+flag: String, +v: String) -> String:
  "argument " ++ flag ++ ": invalid choice: '" ++ v ++ "' (choose from " ++ choices() ++ ")"
