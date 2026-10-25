import Base
import ../src/http.bend as Http

# Ground equations: `bend --check-only` evaluates both sides; a mismatch fails.

def quote_plain() -> {Http.quote("abc") == "abc" : String}:
  {==}

def quote_escapes() -> {Http.quote("a\"b\\c") == "a\\\"b\\\\c" : String}:
  {==}

def line_shape() -> {Http.line("url", "https://x") == "url = \"https://x\"\n" : String}:
  {==}

def header_found() -> {Http.header("content-type:", "HTTP/2 200\nContent-Type: application/json\n\n{}") == Some{"application/json"} : Maybe<&2, String>}:
  {==}

def header_missing() -> {Http.header("retry-after:", "HTTP/2 200\nContent-Type: x\n") == None{} : Maybe<&2, String>}:
  {==}
