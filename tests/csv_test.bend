import Base
import ../src/fmt/csv.bend as C

# Ground equations for the CSV emitter (RFC 4180 quoting) and parser.

def q_plain() -> {C.field("abc") == "abc" : String}:
  {==}

def q_empty() -> {C.field("") == "" : String}:
  {==}

def q_space() -> {C.field(" a b ") == " a b " : String}:
  {==}

def q_comma() -> {C.field("a,b") == "\"a,b\"" : String}:
  {==}

def q_quote() -> {C.field("say \"hi\"") == "\"say \"\"hi\"\"\"" : String}:
  {==}

def q_lf() -> {C.field("a\nb") == "\"a\nb\"" : String}:
  {==}

def q_cr() -> {C.field("a\rb") == "\"a\rb\"" : String}:
  {==}

def q_only_quote() -> {C.field("\"") == "\"\"\"\"" : String}:
  {==}

def row_three() -> {C.row(["a", "b,c", ""]) == "a,\"b,c\"," : String}:
  {==}

def row_one() -> {C.row(["x"]) == "x" : String}:
  {==}

def row_none() -> {C.row([]) == "" : String}:
  {==}

def table_two() -> {C.table([["k", "v"], ["a", "1"]]) == "k,v\na,1\n" : String}:
  {==}

def p_simple() -> {C.parse("a,b\n1,2\n") == Done{[["a", "b"], ["1", "2"]]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def p_no_final_newline() -> {C.parse("a,b\n1,2") == Done{[["a", "b"], ["1", "2"]]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def p_crlf() -> {C.parse("a,b\r\n1,2\r\n") == Done{[["a", "b"], ["1", "2"]]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def p_quoted() -> {C.parse("\"a,b\",\"say \"\"hi\"\"\"\n") == Done{[["a,b", "say \"hi\""]]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def p_newline_in_quotes() -> {C.parse("\"a\nb\",c\n") == Done{[["a\nb", "c"]]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def p_empty_fields() -> {C.parse("a,,\n,\n") == Done{[["a", "", ""], ["", ""]]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def p_trailing_comma_eof() -> {C.parse("a,") == Done{[["a", ""]]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def p_empty_quoted() -> {C.parse("\"\",x\n") == Done{[["", "x"]]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def p_blank_lines() -> {C.parse("\na\n\nb\n") == Done{[["a"], ["b"]]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def p_nothing() -> {C.parse("") == Done{[]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def p_unterminated() -> {C.parse("\"abc") == Fail{"unterminated quoted field"} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def p_after_quote() -> {C.parse("\"a\"b,c\n") == Fail{"text after a closing quote"} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

# Round trip: the parser reads back what the emitter wrote, for fields that
# need every kind of quoting.
def rt_awkward() -> {C.parse(C.table([["a,b", "\"q\"", "line1\nline2", "", " sp "], ["x", "y", "z", "\"", ","]])) == Done{[["a,b", "\"q\"", "line1\nline2", "", " sp "], ["x", "y", "z", "\"", ","]]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

def rt_single_empty_field() -> {C.parse(C.table([[""], ["a"]])) == Done{[["a"]]} : Result<&2, &2, String, List<&2, List<&2, String>>>}:
  {==}

# ---- law: a record of awkward fields reads back as written -----------------------------------------

def tricky() -> List<&2, String>:
  ["", " ", "a b", "a,b", ",", ",,", "\"", "\"\"", "\"a\"", "a\"b", "a\nb", "\n", "a\r\nb", "\r", "a\rb", "x,\"y\",z", " lead", "trail ", "é,日本", "null", "1", "-", "a\tb", "line1\nline2\n", "\"\n\"", "'q'"]

def back(r: Result<&2, &2, String, List<&2, List<&2, String>>>, +s: String) -> Bool:
  match r:
    case Done{Con{Con{t, Con{x, Nil{}}}, Nil{}}}:
      String.eq(s, t) && String.eq(x, "x")
    case _:
      False{}

def back2(r: Result<&2, &2, String, List<&2, List<&2, String>>>, +s: String) -> Bool:
  match r:
    case Done{Con{Con{x, Con{t, Nil{}}}, Nil{}}}:
      String.eq(s, t) && String.eq(x, "x")
    case _:
      False{}

def rt_one(+s: String) -> Bool:
  back(C.parse(C.table([[s, "x"]])), s) && back2(C.parse(C.table([["x", s]])), s)

def rt_all(xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case Con{h, t}:
      rt_one(h) && rt_all(t)

def law_fields_round_trip() -> {rt_all(tricky()) == True{} : Bool}:
  {==}
