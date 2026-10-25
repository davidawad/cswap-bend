import Base
import ../json.bend as Json
import ../fs.bend as Fs
import ../fs/write.bend as FsW
import ../act.bend as Act
import ./config.bend as Cfg

# <state>/daemon-status.json, written atomically (0600) at the end of each
# tick so `cswap daemon status` can say what the loop is doing without
# touching the network. Percentages are centi-percent U32 (printed 12.5);
# times are ISO UTC stamps. `config` is the effective autoswitch config of the
# running loop (settings.json overridden by the command line), so `cswap tui`
# shows what the daemon uses and not the file default.

type Entry is Data:
  Entry{slot: String, pct5: Maybe<&2, U32>, pct7: Maybe<&2, U32>, fetched_at: Maybe<&2, String>, backoff_until: Maybe<&2, String>, last_error: Maybe<&2, String>}

type Status is Data:
  Status{pid: U32, version: String, started_at: String, last_poll_at: Maybe<&2, String>, next_poll_at: Maybe<&2, String>, active: Maybe<&2, String>, entries: List<&2, Entry>, cfg: Cfg.Cfg}

def status_path(+state_dir: String) -> String:
  state_dir ++ "/daemon-status.json"

def pick_s(+c: Bool, +x: String, +y: String) -> String:
  match c:
    case True{}:
      x
    case False{}:
      y

def two(+n: U32) -> String:
  pick_s(U32.is_lt(n, 10), "0" ++ U32.show(n), U32.show(n))

def frac(+c: U32) -> String:
  pick_s(U32.is_eq((c % 10 : U32), 0), U32.show((c / 10 : U32)), two(c))

def pct(+c: U32) -> Json.Json:
  Json.JNum{U32.show((c / 100 : U32)) ++ "." ++ frac((c % 100 : U32))}

def opt_pct(+m: Maybe<&2, U32>) -> Json.Json:
  match m:
    case Some{c}:
      pct(c)
    case None{}:
      Json.JNull{}

def opt_str(+m: Maybe<&2, String>) -> Json.Json:
  match m:
    case Some{s}:
      Json.JStr{s}
    case None{}:
      Json.JNull{}

def f(+k: String, +v: Json.Json, +rest: Json.Json) -> Json.Json:
  Json.JField{k, v, rest}

def entry_json(e: Entry) -> Json.Json:
  match e:
    case Entry{s, p5, p7, fa, bu, le}:
      Json.JObj{f("pct_5h", opt_pct(p5), f("pct_7d", opt_pct(p7), f("fetched_at", opt_str(fa), f("backoff_until", opt_str(bu), f("last_error", opt_str(le), Json.JNil{})))))}

def entry_slot(e: Entry) -> String:
  match e:
    case Entry{s, p5, p7, fa, bu, le}:
      s

def entries_chain(+es: List<&2, Entry>) -> Json.Json:
  match es:
    case Nil{}:
      Json.JNil{}
    case Con{e, t}:
      f(entry_slot(e), entry_json(e), entries_chain(t))

def opt_num(+m: Maybe<&2, String>) -> Json.Json:
  match m:
    case Some{s}:
      Json.JNum{s}
    case None{}:
      Json.JNull{}

def str_arr(+xs: List<&2, String>) -> List<&2, Json.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{Json.JStr{h}, str_arr(t)}

def cfg_json(+c: Cfg.Cfg) -> Json.Json:
  Json.JObj{f("threshold", pct(Cfg.cfg_threshold(c)), f("interval_seconds", Json.JNum{U32.show(Cfg.cfg_interval(c))}, f("cooldown_seconds", Json.JNum{U32.show(Cfg.cfg_cooldown(c))},
    f("strategy", Json.JStr{Cfg.cfg_strategy(c)}, f("models", Json.arr(str_arr(Cfg.cfg_models(c))), f("include_api_keys", Json.JBool{Cfg.cfg_include_api(c)}, Json.JNil{}))))))}

def to_json(s: Status) -> Json.Json:
  match s:
    case Status{pid, version, started, last_poll, next_poll, active, es, cfg}:
      Json.JObj{f("schemaVersion", Json.JNum{"1"}, f("pid", Json.JNum{U32.show(pid)}, f("version", Json.JStr{version}, f("started_at", Json.JStr{started},
        f("last_poll_at", opt_str(last_poll), f("next_poll_at", opt_str(next_poll), f("active", opt_num(active), f("config", cfg_json(cfg), f("accounts", Json.JObj{entries_chain(es)}, Json.JNil{})))))))))}

# Replace the status file (temp file + rename, 0600).
def write(+state_dir: String, s: Status) -> Act.of(Unit):
  FsW.write_atomic(status_path(state_dir), Json.emit_pretty(to_json(s)), "600")
