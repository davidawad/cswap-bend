import Base

# HTTPS through curl. Bend 2 has no TLS effect, so every request is a curl
# run whose whole config (URL, headers, body) arrives on stdin through
# `--config -`: a bearer token never appears in argv or the process list.

def quote.pick(esc: Bool, c: Char, rest: String) -> String:
  match esc:
    case True{}:
      SCon{'\\', SCon{c, rest}}
    case False{}:
      SCon{c, rest}

def quote.char(+c: Char, rest: String) -> String:
  quote.pick(Char.is_eq(c, '\\') || Char.is_eq(c, '"'), c, rest)

# The body of a quoted curl config value: `\` and `"` escaped.
def quote(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{h, t}:
      quote.char(h, quote(t))

def line(key: String, value: String) -> String:
  key ++ " = \"" ++ quote(value) ++ "\"\n"

def header.line(kv: String & String) -> String:
  (k, v) = kv
  line("header", k ++ ": " ++ v)

def headers(hs: List<(String & String)>) -> String:
  match hs:
    case Nil{}:
      ""
    case Con{kv, t}:
      header.line(kv) ++ headers(t)

def body.pick(empty: Bool, body: String) -> String:
  match empty:
    case True{}:
      ""
    case False{}:
      line("data-raw", body)

def body.line(+body: String) -> String:
  body.pick(String.is_empty(body), body)

# curl config for one request. `dump-header = -` puts the response headers on
# stdout ahead of the body; `write-out` appends the HTTP status as the last
# line. An empty body sends no data line (a GET stays a GET).
def config(method: String, url: String, hs: List<(String & String)>, body: String, timeout_s: U32) -> String:
  line("url", url)
    ++ line("request", method)
    ++ "silent\nshow-error\ndump-header = -\n"
    ++ line("max-time", U32.show(timeout_s))
    ++ line("write-out", "\\n%{http_code}")
    ++ headers(hs)
    ++ body.line(body)

# Header lookup, case-insensitive on the name. `name` must be lowercase and
# end with `:`.
def header.pick(hit: Bool, +name: String, +line: String) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{String.trim(String.drop(line, String.length(name)))}
    case False{}:
      None{}

def header.match(+name: String, +line: String) -> Maybe<&2, String>:
  header.pick(String.starts_with(String.to_lower(line), name), name, line)

def header.find(+name: String, ls: List<&2, String>, found: Maybe<&2, String>) -> Maybe<&2, String>:
  match ls found:
    case _ Some{v}:
      Some{v}
    case Nil{} None{}:
      None{}
    case Con{h, t} None{}:
      header.find(name, t, header.match(name, h))

def header(+name: String, raw: String) -> Maybe<&2, String>:
  header.find(name, String.lines(raw), None{})

# Run one request: answers curl's exit status and (stdout, stderr). stdout is
# the response headers, the body, then the HTTP status on the last line.
def run(cfg: String, timeout_ms: U32) -> IO(Result<&1, &1, U32 & String, U32 & (String & String)>):
  Process.run("curl", ["--config", "-"], cfg, 4194304, timeout_ms)

# ---- reading a response ----------------------------------------------------------

def after_headers.pick(blank: Bool, rest: List<&2, String>, deeper: List<&2, String>) -> List<&2, String>:
  match blank:
    case True{}:
      rest
    case False{}:
      deeper

# Lines after the header block (the first blank line).
def after_headers(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{+h, +t}:
      after_headers.pick(String.is_empty(String.trim(h)), t, after_headers(t))

def last_line.pick(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{s}:
      s

# The HTTP status `config` asked curl to append as the last line; 0 when absent.
def status(raw: String) -> U32:
  Maybe.default(&2, U32, U32.read(String.trim(last_line.pick(List.last(&2, String, String.lines(raw))))), 0)

def body.of(+ls: List<&2, String>) -> String:
  String.join(List.take(&2, String, ls, Nat.sub(List.length(&2, String, ls), 1n)), "\n")

# The body: what lies between the headers and the status line.
def body(raw: String) -> String:
  body.of(after_headers(String.lines(raw)))

# ---- test seam -------------------------------------------------------------

def rewrite.pick(live: Bool, base: String, +url: String) -> String:
  match live:
    case True{}:
      base ++ "/" ++ String.drop(url, 8n)
    case False{}:
      url

# With CSWAP_TEST_HTTP_BASE set (`base` non-empty), `https://host/path` goes to
# `base/host/path`: plain http, same headers and body (contract section 5).
def rewrite(+base: String, +url: String) -> String:
  rewrite.pick(Bool.not(String.is_empty(base)) && String.starts_with(url, "https://"), base, url)

def base.pick(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{v}:
      v

# The test base URL, or "" when unset.
def test_base() -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, String>, String, IO.get_env("CSWAP_TEST_HTTP_BASE"), r => IO.pure(String, base.pick(r)))

# ---- one request, parsed ---------------------------------------------------

# status, the raw header block (one line each, `\n` ended), the body.
type Reply is Data:
  Reply{status: U32, head: String, body: String}

def head.pick(blank: Bool, h: String, rest: String) -> String:
  match blank:
    case True{}:
      ""
    case False{}:
      h ++ "\n" ++ rest

# The header lines: everything before the first blank line.
def head.of(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      ""
    case Con{+h, t}:
      head.pick(String.is_empty(String.trim(h)), h, head.of(t))

def reply.ok(+out: String) -> Result<&2, &2, String, Reply>:
  Done{Reply{status(out), head.of(String.lines(out)), body(out)}}

# curl exit 28 is its own timeout; anything else that fails is the network.
def reply.exit(ok: Bool, timed_out: Bool, out: String) -> Result<&2, &2, String, Reply>:
  match ok timed_out:
    case True{} _:
      reply.ok(out)
    case False{} True{}:
      Fail{"timeout"}
    case False{} False{}:
      Fail{"network"}

def reply.of2(+st: U32, oe: String & String) -> Result<&2, &2, String, Reply>:
  (o, e) = oe
  reply.exit(U32.is_eq(st, 0), U32.is_eq(st, 28), o)

def reply.of(r: U32 & (String & String)) -> Result<&2, &2, String, Reply>:
  (st, oe) = r
  reply.of2(st, oe)

def reply(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Result<&2, &2, String, Reply>:
  match r:
    case Fail{e}:
      Fail{"network"}
    case Done{v}:
      reply.of(v)

# One request through curl (config on stdin, so the token never reaches argv),
# with the test seam applied. Fail carries the error kind: `timeout` or
# `network`.
def request(method: String, url: String, hs: List<(String & String)>, body: String, +timeout_s: U32) -> IO(Result<&2, &2, String, Reply>):
  IO.bind(String, Result<&2, &2, String, Reply>, test_base(),
    base => IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, Result<&2, &2, String, Reply>,
      run(config(method, rewrite(base, url), hs, body, timeout_s), (timeout_s * 1000 + 3000 : U32)),
      r => IO.pure(Result<&2, &2, String, Reply>, reply(r))))
