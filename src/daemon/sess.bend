import Base
import ../json.bend as Json
import ../fs.bend as Fs
import ../act.bend as Act

# Is a Claude session running against a slot's session profile?
# (switcher._live_session_pids / process_detection.scan_sessions): the records
# <root>/sessions/<slot>-<slug(email)>/sessions/*.json each name a pid; one
# counts only when that pid is alive and is still the process that wrote the
# record. A record that cannot be read counts as no session (a scan, not a
# guard). The check is ps-based, like the reference's on macOS and Linux.

def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

# ---- the profile directory -------------------------------------------------------------------------

def keep_char(+n: U32) -> Bool:
  (U32.is_ge(n, 48) && U32.is_le(n, 57)) || (U32.is_ge(n, 65) && U32.is_le(n, 90)) || (U32.is_ge(n, 97) && U32.is_le(n, 122)) || U32.is_eq(n, 46) || U32.is_eq(n, 95) || U32.is_eq(n, 45)

def pick_char(+k: Bool, +c: Char) -> Char:
  match k:
    case True{}:
      c
    case False{}:
      '_'

def slug_char(+c: Char) -> Char:
  pick_char(keep_char(Char.to_u32(c)), c)

def slug_list(+cs: List<&2, Char>) -> List<&2, Char>:
  match cs:
    case Nil{}:
      []
    case Con{h, t}:
      slug_char(h) <> slug_list(t)

# session.slugify_email (ASCII addresses; a non-ASCII character becomes `_`).
def slugify(+email: String) -> String:
  String.from_list(slug_list(String.to_list(email)))

def dir_of(+root: String, +slot: String, +email: String) -> String:
  root ++ "/sessions/" ++ slot ++ "-" ++ slugify(email) ++ "/sessions"

# ---- asking ps ----------------------------------------------------------------------------------------

def ps_some(+empty: Bool, +t: String) -> Maybe<&2, String>:
  match empty:
    case True{}:
      None{}
    case False{}:
      Some{t}

def ps_nonempty(+ok: Bool, +t: String) -> Maybe<&2, String>:
  match ok:
    case True{}:
      ps_some(String.is_empty(t), t)
    case False{}:
      None{}

def ps_text(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Maybe<&2, String>:
  match r:
    case Fail{e}:
      None{}
    case Done{(st, (out, err))}:
      ps_nonempty(U32.is_eq(st, 0), String.trim(out))

# `ps -o COLS= -p PID` under LC_ALL=C TZ=UTC; None when unknowable.
def ps(+cols: String, +pid: U32) -> IO(Maybe<&2, String>):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, Maybe<&2, String>, Process.run("/usr/bin/env", ["LC_ALL=C", "TZ=UTC", "ps", "-o", cols, "-p", U32.show(pid)], "", 4096, 5000), r => IO.pure(Maybe<&2, String>, ps_text(r)))

# ---- ps -o lstart= ("Wed Sep  2 20:35:59 2026") as epoch seconds ---------------------------------

def month_hit(+hit: Bool, +i: U32, +rest: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match hit:
    case True{}:
      Some{i}
    case False{}:
      rest

def month_from(+ms: List<&2, String>, +m: String, +i: U32) -> Maybe<&2, U32>:
  match ms:
    case Nil{}:
      None{}
    case Con{h, t}:
      month_hit(String.eq(h, m), i, month_from(t, m, (i + 1 : U32)))

def month_idx(+m: String) -> Maybe<&2, U32>:
  month_from(["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"], m, 1)

def word_keep(+empty: Bool, +h: String, +rest: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      rest
    case False{}:
      h <> rest

def words(+ws: List<&2, String>) -> List<&2, String>:
  match ws:
    case Nil{}:
      []
    case Con{h, t}:
      word_keep(String.is_empty(h), h, words(t))

def sel_u(+c: Bool, +x: U32, +y: U32) -> U32:
  match c:
    case True{}:
      x
    case False{}:
      y

def days5(+a: U32, +b: U32, +doy: U32) -> U32:
  ((((a + b : U32) + doy : U32) - 719468) : U32)

def days4(+era: U32, +yoe: U32, +doy: U32) -> U32:
  days5((era * 146097 : U32), ((((yoe * 365 : U32) + (yoe / 4 : U32) : U32) - (yoe / 100 : U32)) : U32), doy)

def days3(+era: U32, +yoe: U32, +dm1: U32, +mp: U32) -> U32:
  days4(era, yoe, ((((153 * mp : U32) + 2 : U32) / 5 : U32) + dm1 : U32))

def days2(+yy: U32, +m: U32, +d: U32) -> U32:
  days3((yy / 400 : U32), (yy % 400 : U32), (d - 1 : U32), sel_u(U32.is_gt(m, 2), (m - 3 : U32), (m + 9 : U32)))

# days since 1970-01-01 of a civil date (years from 1970 on).
def days_civil(+y: U32, +m: U32, +d: U32) -> U32:
  days2(sel_u(U32.is_le(m, 2), (y - 1 : U32), y), m, d)

def num(+s: String) -> U32:
  Maybe.default(&2, U32, U32.read(s), 0)

def clock_secs(+ps: List<&2, String>) -> Maybe<&2, U32>:
  match ps:
    case Con{h, Con{m, Con{s, Nil{}}}}:
      Some{(((num(h) * 3600 : U32) + (num(m) * 60 : U32) : U32) + num(s) : U32)}
    case _:
      None{}

def lstart_ok(+ok: Bool, +y: U32, +m: U32, +d: U32, +c: U32) -> Maybe<&2, U32>:
  match ok:
    case True{}:
      Some{((days_civil(y, m, d) * 86400 : U32) + c : U32)}
    case False{}:
      None{}

# ---- does the process at the pid still belong to the record? ----------------------------------

def lstart_fields(+m: Maybe<&2, U32>, +d: Maybe<&2, U32>, +c: Maybe<&2, U32>, +y: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m d c y:
    case Some{mm} Some{dd} Some{cc} Some{yy}:
      lstart_ok(U32.is_ge(yy, 1970), yy, mm, dd, cc)
    case _ _ _ _:
      None{}

def lstart_dy(+m: Maybe<&2, U32>, +ws: List<&2, String>) -> Maybe<&2, U32>:
  match ws:
    case Con{day, Con{clk, Con{yr, Nil{}}}}:
      lstart_fields(m, U32.read(day), clock_secs(String.split(clk, ':')), U32.read(yr))
    case _:
      None{}

def lstart_dmy(+ws: List<&2, String>) -> Maybe<&2, U32>:
  match ws:
    case Con{mon, t}:
      lstart_dy(month_idx(mon), t)
    case Nil{}:
      None{}

def lstart_of(+ws: List<&2, String>) -> Maybe<&2, U32>:
  match ws:
    case Con{wd, t}:
      lstart_dmy(t)
    case Nil{}:
      None{}

def lstart_secs(+text: String) -> Maybe<&2, U32>:
  lstart_of(words(String.split(text, ' ')))

def all_digits(+cs: List<&2, Char>) -> Bool:
  match cs:
    case Nil{}:
      True{}
    case Con{c, t}:
      Char.is_digit(c) && all_digits(t)

def is_ticks(+t: String) -> Bool:
  Bool.not(String.is_empty(t)) && all_digits(String.to_list(t))

def nth_hit(+hit: Bool, +h: String, +rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{h}
    case False{}:
      rest

# Field 22 of /proc/<pid>/stat (counted from the last `)`), the Linux stamp.
def nth_word(+ws: List<&2, String>, +n: U32) -> Maybe<&2, String>:
  match ws:
    case Nil{}:
      None{}
    case Con{h, t}:
      nth_hit(U32.is_eq(n, 0), h, nth_word(t, (n - 1 : U32)))

def last_part(+ps: List<&2, String>, +d: String) -> String:
  match ps:
    case Nil{}:
      d
    case Con{h, t}:
      last_part(t, h)

def stat_ticks(+text: String) -> Maybe<&2, String>:
  nth_word(words(String.split(last_part(String.split(text, ')'), ""), ' ')), 19)

def ticks_match(+want: String, +m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{t}:
      String.eq(t, want)

def stat_text(r: Fs.Res(String)) -> Maybe<&2, String>:
  match r:
    case Fail{e}:
      None{}
    case Done{t}:
      stat_ticks(t)

def matches_ticks(+pid: U32, +want: String) -> IO(Bool):
  IO.bind(Fs.Res(String), Bool, Fs.read_file("/proc/" ++ U32.show(pid) ++ "/stat"), r => IO.pure(Bool, ticks_match(want, stat_text(r))))

def looks_claude(+m: Maybe<&2, String>) -> Bool:
  match m:
    case None{}:
      True{}
    case Some{t}:
      String.contains(String.to_lower(t), "claude")

def stranger2(+recent: Bool, +pid: U32) -> IO(Bool):
  match recent:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      IO.bind(Maybe<&2, String>, Bool, ps("comm=,args=", pid), t => IO.pure(Bool, looks_claude(t)))

# Only a stranger that started later than the record's claude disqualifies it.
def stranger(+recorded: U32, +started: Maybe<&2, U32>, +pid: U32) -> IO(Bool):
  match started:
    case None{}:
      IO.pure(Bool, True{})
    case Some{st}:
      stranger2(U32.is_le(st, (recorded + 120 : U32)), pid)

def started_of(+m: Maybe<&2, String>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{t}:
      lstart_secs(t)

def by_lstart(+pid: U32, +rec: Maybe<&2, U32>) -> IO(Bool):
  match rec:
    case None{}:
      IO.pure(Bool, True{})
    case Some{recorded}:
      IO.bind(Maybe<&2, String>, Bool, ps("lstart=", pid), t => stranger(recorded, started_of(t), pid))

def stamped2(+ticks: Bool, +pid: U32, +stamp: String) -> IO(Bool):
  match ticks:
    case True{}:
      matches_ticks(pid, stamp)
    case False{}:
      by_lstart(pid, lstart_secs(stamp))

def stamped(+pid: U32, +stamp: String) -> IO(Bool):
  stamped2(is_ticks(stamp), pid, stamp)

def with_stamp(+pid: U32, +m: Maybe<&2, String>) -> IO(Bool):
  match m:
    case None{}:
      IO.pure(Bool, True{})
    case Some{stamp}:
      stamped(pid, stamp)

def alive_then(+up: Bool, +pid: U32, +stamp: Maybe<&2, String>) -> IO(Bool):
  match up:
    case True{}:
      with_stamp(pid, stamp)
    case False{}:
      IO.pure(Bool, False{})

def pid_live(+pid: U32, +stamp: Maybe<&2, String>) -> IO(Bool):
  IO.bind(Maybe<&2, String>, Bool, ps("pid=", pid), t => alive_then(Maybe.is_some(&2, String, t), pid, stamp))

# ---- one record ---------------------------------------------------------------------------------

def stamp_of(+j: Json.Json) -> Maybe<&2, String>:
  Json.as_string(Maybe.default(&2, Json.Json, Json.get("procStart", j), Json.JNull{}))

def pid_of(+j: Json.Json) -> Maybe<&2, U32>:
  Json.as_u32(Maybe.default(&2, Json.Json, Json.get("pid", j), Json.JNull{}))

def pid_live_gt1(+ok: Bool, +p: U32, +stamp: Maybe<&2, String>) -> IO(Bool):
  match ok:
    case True{}:
      pid_live(p, stamp)
    case False{}:
      IO.pure(Bool, False{})

def record_live2(+pid: Maybe<&2, U32>, +stamp: Maybe<&2, String>) -> IO(Bool):
  match pid:
    case None{}:
      IO.pure(Bool, False{})
    case Some{p}:
      pid_live_gt1(U32.is_gt(p, 1), p, stamp)

def record_live(r: Result<&2, &2, String, Json.Json>) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{+j}:
      record_live2(pid_of(j), stamp_of(j))

def file_live(r: Fs.Res(String)) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{t}:
      record_live(Json.parse(t))

# ---- the directory ---------------------------------------------------------------------------------------

def any_live(+dir: String, +names: List<&2, String>) -> IO(Bool):
  match names:
    case Nil{}:
      IO.pure(Bool, False{})
    case Con{n, t}:
      IO.bind(Fs.Res(String), Bool, Fs.read_file(dir ++ "/" ++ n), r => IO.bind(Bool, Bool, file_live(r), hit => IO.bind(Bool, Bool, any_live(dir, t), rest => IO.pure(Bool, hit || rest))))

def rest_live(+hit: Bool, +dir: String, +t: List<&2, String>) -> IO(Bool):
  match hit:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      any_live(dir, t)

def json_keep(+ok: Bool, +h: String, +rest: List<&2, String>) -> List<&2, String>:
  match ok:
    case True{}:
      h <> rest
    case False{}:
      rest

def json_names(+ns: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}:
      []
    case Con{h, t}:
      json_keep(String.ends_with(h, ".json"), h, json_names(t))

def scan(+dir: String, r: Fs.Res(List<&2, String>)) -> IO(Bool):
  match r:
    case Fail{e}:
      IO.pure(Bool, False{})
    case Done{ns}:
      any_live(dir, json_names(ns))

# Is a Claude session live against this slot's session profile?
def live(+root: String, +slot: String, +email: String) -> IO(Bool):
  IO.bind(Fs.Res(List<&2, String>), Bool, Fs.list_dir(dir_of(root, slot, email)), r => scan(dir_of(root, slot, email), r))
