import Base

# CSV, RFC 4180 quoting. A field is quoted when it holds a comma, a double
# quote, CR or LF; inside quotes a double quote is written twice. Records end
# in LF (the parser takes LF or CRLF). Pure: no effects.

# ---- emitter -----------------------------------------------------------------

def special(+c: U32) -> Bool:
  U32.is_eq(c, 44) || U32.is_eq(c, 34) || U32.is_eq(c, 10) || U32.is_eq(c, 13)

def needs(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{Chr{c}, t}:
      special(c) || needs(t)

def dq(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{+c}, t}:
      Bool.pick(String, U32.is_eq(c, 34), "\"\"", SCon{Chr{c}, SNil{}}) ++ dq(t)

def field.q(c: Bool, +s: String) -> String:
  Bool.pick(String, c, "\"" ++ dq(s) ++ "\"", s)

# One field, quoted when it must be.
def field(+s: String) -> String:
  field.q(needs(s), s)

# One record, without the line end.
def row(fs: List<&2, String>) -> String:
  match fs:
    case Nil{}:
      ""
    case Con{h, Nil{}}:
      field(h)
    case Con{h, Con{h2, t2}}:
      field(h) ++ "," ++ row(h2 <> t2)

# Records, each ending in LF.
def table(rs: List<&2, List<&2, String>>) -> String:
  match rs:
    case Nil{}:
      ""
    case Con{r, t}:
      row(r) ++ "\n" ++ table(t)

# ---- parser ------------------------------------------------------------------

type Mode is Data:
  MStart{}
  MPlain{}
  MQuoted{}
  MClosed{}

# rows and row are reversed; cur is the reversed text of the field in progress.
type St is Data:
  St{rows: List<&2, List<&2, String>>, row: List<&2, String>, cur: String, mode: Mode, err: String}

def start() -> St:
  St{[], [], "", MStart{}, ""}

def with_mode(+st: St, m: Mode) -> St:
  match st:
    case St{rows, row, cur, mode, err}:
      St{rows, row, cur, m, err}

def push(+c: U32, +st: St) -> St:
  match st:
    case St{rows, row, cur, mode, err}:
      St{rows, row, SCon{Chr{c}, cur}, mode, err}

# The field in progress ends; the next field starts in `m`.
def end_field(+st: St, m: Mode) -> St:
  match st:
    case St{rows, row, cur, mode, err}:
      St{rows, String.reverse(cur) <> row, "", m, err}

def end_row(+st: St) -> St:
  match st:
    case St{rows, row, cur, mode, err}:
      St{List.reverse(&2, String, row) <> rows, [], cur, MStart{}, err}

def end_both(+st: St) -> St:
  end_row(end_field(st, MStart{}))

def fail(+st: St, msg: String) -> St:
  match st:
    case St{rows, row, cur, mode, err}:
      St{rows, row, cur, mode, Bool.pick(String, String.is_empty(err), msg, err)}

def row_empty(+st: St) -> Bool:
  match st:
    case St{rows, row, cur, mode, err}:
      List.is_empty(&2, String, row)

def blank.pick(empty: Bool, +st: St) -> St:
  match empty:
    case True{}:
      st
    case False{}:
      end_both(st)

def sel.st(c: Bool, +a: St, +b: St) -> St:
  match c:
    case True{}:
      a
    case False{}:
      b

def at_start(+c: U32, +st: St) -> St:
  sel.st(U32.is_eq(c, 34), with_mode(st, MQuoted{}),
  sel.st(U32.is_eq(c, 44), end_field(st, MStart{}),
  sel.st(U32.is_eq(c, 10), blank.pick(row_empty(st), st),
  sel.st(U32.is_eq(c, 13), st,
  with_mode(push(c, st), MPlain{})))))

def in_plain(+c: U32, +st: St) -> St:
  sel.st(U32.is_eq(c, 44), end_field(st, MStart{}),
  sel.st(U32.is_eq(c, 10), end_both(st),
  sel.st(U32.is_eq(c, 13), st,
  push(c, st))))

def in_quoted(+c: U32, +st: St) -> St:
  sel.st(U32.is_eq(c, 34), with_mode(st, MClosed{}), push(c, st))

def after_quote(+c: U32, +st: St) -> St:
  sel.st(U32.is_eq(c, 34), with_mode(push(34, st), MQuoted{}),
  sel.st(U32.is_eq(c, 44), end_field(st, MStart{}),
  sel.st(U32.is_eq(c, 10), end_both(st),
  sel.st(U32.is_eq(c, 13), st,
  fail(st, "text after a closing quote")))))

def step(m: Mode, +c: U32, +st: St) -> St:
  match m:
    case MStart{}:
      at_start(c, st)
    case MPlain{}:
      in_plain(c, st)
    case MQuoted{}:
      in_quoted(c, st)
    case MClosed{}:
      after_quote(c, st)

def mode_of(+st: St) -> Mode:
  match st:
    case St{rows, row, cur, mode, err}:
      mode

def go(s: String, +st: St) -> St:
  match s:
    case SNil{}:
      st
    case SCon{Chr{c}, t}:
      go(t, step(mode_of(st), c, st))

# The input ended: close the record in progress.
def close(m: Mode, +st: St) -> St:
  match m:
    case MStart{}:
      blank.pick(row_empty(st), st)
    case MQuoted{}:
      fail(st, "unterminated quoted field")
    case MPlain{}:
      end_both(st)
    case MClosed{}:
      end_both(st)

def result(+st: St) -> Result<&2, &2, String, List<&2, List<&2, String>>>:
  match st:
    case St{rows, row, cur, mode, err}:
      Bool.pick(Result<&2, &2, String, List<&2, List<&2, String>>>, String.is_empty(err), Done{List.reverse(&2, List<&2, String>, rows)}, Fail{err})

def parse.fin(+st: St) -> Result<&2, &2, String, List<&2, List<&2, String>>>:
  result(close(mode_of(st), st))

# Records of fields. Blank lines are skipped; `Fail` names a quoting error.
def parse(s: String) -> Result<&2, &2, String, List<&2, List<&2, String>>>:
  parse.fin(go(s, start()))
