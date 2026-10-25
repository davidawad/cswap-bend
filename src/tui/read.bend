import Base
import ../json.bend as Json
import ../store/seq.bend as SSeq
import ./model.bend as M
import ./num.bend as N

# Building a Snap from the text of the files the dashboard follows. Pure: the
# caller reads the files, the clock and the daemon's liveness.
#
# The daemon's status file (<state>/daemon-status.json, src/daemon/status.bend)
# has these fields, named here and nowhere else:

def f_pid() -> String:
  "pid"

def f_next_poll() -> String:
  "next_poll_at"

def f_active() -> String:
  "active"

def f_accounts() -> String:
  "accounts"

def f_last_error() -> String:
  "last_error"

def f_backoff() -> String:
  "backoff_until"

# ---- windows -----------------------------------------------------------------------------

def win_pct(+label: String, +w: Json.Json, +p: Maybe<&2, U32>) -> Maybe<&2, M.Win>:
  match p:
    case None{}:
      None{}
    case Some{c}:
      Some{M.Win{label, p, N.iso_at("resets_at", w)}}

# One window object of cache/usage.json: {"pct": 47.0, "resets_at": "<ISO>"}.
def win_of(+label: String, +w: Json.Json) -> Maybe<&2, M.Win>:
  win_pct(label, w, N.centi_at("pct", w))

def win_opt(+label: String, +m: Maybe<&2, Json.Json>) -> Maybe<&2, M.Win>:
  match m:
    case None{}:
      None{}
    case Some{w}:
      win_of(label, w)

def win_key(+label: String, +key: String, +good: Json.Json) -> Maybe<&2, M.Win>:
  win_opt(label, Json.get(key, good))

def cons_win(+m: Maybe<&2, M.Win>, +rest: List<&2, M.Win>) -> List<&2, M.Win>:
  match m:
    case None{}:
      rest
    case Some{w}:
      Con{w, rest}

def scoped_win(+w: Json.Json) -> Maybe<&2, M.Win>:
  win_of(N.str_at("name", w), w)

def scoped(+items: List<&2, Json.Json>) -> List<&2, M.Win>:
  match items:
    case Nil{}:
      Nil{}
    case Con{w, t}:
      cons_win(scoped_win(w), scoped(t))

# The windows of a lastGood object, in the reference's order: 5h, 7d, then the
# per-model windows.
def wins_of(+good: Json.Json) -> List<&2, M.Win>:
  cons_win(win_key("5h", "five_hour", good), cons_win(win_key("7d", "seven_day", good), scoped(Json.to_list(N.get_or_null("scoped", good)))))

# ---- one account --------------------------------------------------------------------------

def age_of(+fetched: Maybe<&2, U32>, +now: U32) -> Maybe<&2, U32>:
  match fetched:
    case None{}:
      None{}
    case Some{t}:
      Some{N.sel(U32.is_gt(now, t), (now - t : U32), 0)}

def api_key(+rec: Json.Json) -> Bool:
  String.eq(N.str_at("kind", rec), "api_key")

def non_empty_pick(+blank: Bool, +s: String) -> Maybe<&2, String>:
  match blank:
    case True{}:
      None{}
    case False{}:
      Some{s}

def non_empty(+s: String) -> Maybe<&2, String>:
  non_empty_pick(String.is_empty(s), s)

def first_text(+a: String, +b: String) -> String:
  N.str_or(non_empty(a), b)

def error_of(+row: Json.Json, +st: Json.Json) -> String:
  first_text(N.str_at("lastError", row), N.str_at(f_last_error(), st))

def note_pick(+key: Bool, +err: String) -> String:
  match key:
    case True{}:
      "API key (no quota)"
    case False{}:
      err

def note_of(+rec: Json.Json, +row: Json.Json, +st: Json.Json, +wins: List<&2, M.Win>) -> String:
  note_pick(api_key(rec), error_of(row, st))

def flag_of(+m: Maybe<&2, Json.Json>) -> Bool:
  match m:
    case Some{Json.JBool{b}}:
      b
    case _:
      False{}

# ---- every account ----------------------------------------------------------------------------

def flag(+rec: Json.Json, +key: String) -> Bool:
  flag_of(Json.get(key, rec))

def acct_with(+slot: String, +rec: Json.Json, +row: Json.Json, +st: Json.Json, +active: Bool, +now: U32, +wins: List<&2, M.Win>) -> M.Acct:
  M.Acct{slot, N.str_at("email", rec), N.str_at("alias", rec), SSeq.org_tag(rec), active, flag(rec, "disabled"), wins, age_of(N.secs_at("fetchedAt", row), now), note_of(rec, row, st, wins)}

def acct_of(+slot: String, +rec: Json.Json, +row: Json.Json, +st: Json.Json, +active: Bool, +now: U32) -> M.Acct:
  acct_with(slot, rec, row, st, active, now, wins_of(N.get_or_null("lastGood", row)))

def is_active(+slot: String, +active: Maybe<&2, U32>) -> Bool:
  match active:
    case None{}:
      False{}
    case Some{n}:
      String.eq(slot, U32.show(n))

def first_some(+a: Maybe<&2, U32>, +b: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match a:
    case None{}:
      b
    case Some{x}:
      a

# ---- the header --------------------------------------------------------------------------------

# The live slot: the daemon's view first, else the roster's advisory field.
def active_slot(+status: Json.Json, +seq: Json.Json) -> Maybe<&2, U32>:
  first_some(N.uint_at(f_active(), status), N.uint_at("activeAccountNumber", seq))

def settings_block(+settings: Json.Json) -> Json.Json:
  N.get_or_null("autoswitch", settings)

def whole(+m: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match m:
    case None{}:
      None{}
    case Some{c}:
      Some{(c / 100 : U32)}

def f_config() -> String:
  "config"

def f_interval() -> String:
  "interval_seconds"

def first_u(+a: Maybe<&2, U32>, +b: Maybe<&2, U32>) -> Maybe<&2, U32>:
  first_some(a, b)

# The running daemon's own config (its status file) wins while it is alive;
# a stopped daemon, or an older status file without one, reads settings.json.
def pick_j(+live: Bool, +j: Json.Json) -> Json.Json:
  match live:
    case True{}:
      j
    case False{}:
      Json.JNull{}

def daemon_cfg(+live: Bool, +status: Json.Json) -> Json.Json:
  pick_j(live, N.get_or_null(f_config(), status))

def thr_of(+live: Bool, +status: Json.Json, +settings: Json.Json) -> Maybe<&2, U32>:
  first_u(N.centi_at("threshold", daemon_cfg(live, status)), N.centi_at("threshold", settings_block(settings)))

def every_of(+live: Bool, +status: Json.Json, +settings: Json.Json) -> Maybe<&2, U32>:
  first_u(N.uint_at(f_interval(), daemon_cfg(live, status)), whole(N.centi_at("intervalSeconds", settings_block(settings))))

def hdr_of(+version: String, +live: Bool, +status: Json.Json, +settings: Json.Json) -> M.Hdr:
  M.Hdr{version, live, N.uint_at(f_pid(), status), thr_of(live, status, settings), every_of(live, status, settings), N.iso_at(f_next_poll(), status)}

# ---- the log ----------------------------------------------------------------------------------

# "12:03:11  info tick no-action": the time of day of ts, level, msg, outcome.
def clock_part(+ts: String) -> String:
  String.take(String.drop(ts, 11n), 8n)

def join_pick(+empty: Bool, +a: String, +b: String) -> String:
  match empty:
    case True{}:
      a
    case False{}:
      a ++ " " ++ b

def join_sp(+a: String, +b: String) -> String:
  join_pick(String.is_empty(b), a, b)

def log_line(+j: Json.Json) -> String:
  join_sp(join_sp(join_sp(clock_part(N.str_at("ts", j)) ++ " ", N.str_at("level", j)), N.str_at("msg", j)), N.str_at("outcome", j))

def log_pick(+j: Json.Json, +line: String) -> String:
  match j:
    case Json.JObj{f}:
      log_line(j)
    case _:
      String.trim(line)

def log_text(+line: String) -> String:
  log_pick(N.parse_text(line), line)

def keep_line(+blank: Bool, +l: String, +rest: List<&2, String>) -> List<&2, String>:
  match blank:
    case True{}:
      rest
    case False{}:
      Con{log_text(l), rest}

# ---- the snapshot ------------------------------------------------------------------------------

def log_lines(+ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case Con{l, t}:
      keep_line(String.is_empty(String.trim(l)), l, log_lines(t))

def acct_opt(+slot: String, +rec: Maybe<&2, Json.Json>, +cache: Json.Json, +status: Json.Json, +active: Maybe<&2, U32>, +now: U32) -> Maybe<&2, M.Acct>:
  match rec:
    case None{}:
      None{}
    case Some{r}:
      Some{acct_of(slot, r, N.get_or_null(slot, N.get_or_null(f_accounts(), cache)), N.get_or_null(slot, N.get_or_null(f_accounts(), status)), is_active(slot, active), now)}

def acct_cons(+m: Maybe<&2, M.Acct>, +rest: List<&2, M.Acct>) -> List<&2, M.Acct>:
  match m:
    case None{}:
      rest
    case Some{a}:
      Con{a, rest}

def accts(+nums: List<&2, U32>, +seq: Json.Json, +cache: Json.Json, +status: Json.Json, +active: Maybe<&2, U32>, +now: U32) -> List<&2, M.Acct>:
  match nums:
    case Nil{}:
      Nil{}
    case Con{n, t}:
      acct_cons(acct_opt(U32.show(n), Json.get(U32.show(n), SSeq.accounts_of(seq)), cache, status, active, now), accts(t, seq, cache, status, active, now))

def snap_of(+version: String, +live: Bool, +now: U32, +off: U32, +seq: Json.Json, +cache: Json.Json, +status: Json.Json, +settings: Json.Json, +log_t: String) -> M.Snap:
  M.Snap{now, off, hdr_of(version, live, status, settings), accts(SSeq.seq_nums(seq), seq, cache, status, active_slot(status, seq), now), log_lines(String.lines(log_t))}

# Everything the dashboard shows, from the text of sequence.json,
# cache/usage.json, daemon-status.json, settings.json and the tail of
# daemon.log. Missing or unparseable files read as empty.
def snap(+version: String, +live: Bool, +now: U32, +off: U32, +seq_t: String, +cache_t: String, +status_t: String, +settings_t: String, +log_t: String) -> M.Snap:
  snap_of(version, live, now, off, N.parse_text(seq_t), N.parse_text(cache_t), N.parse_text(status_t), N.parse_text(settings_t), log_t)
