import Base
import ../src/tui/fmt.bend as F
import ../src/tui/model.bend as M
import ../src/tui/num.bend as N
import ../src/tui/read.bend as R
import ../src/tui/view.bend as V
import ../src/tui/run.bend as Run

# Ground equations for the pure parts of the dashboard. The clock of the
# fixtures is 2026-10-23T09:00:00Z = 1792746000.

# ---- numbers and durations

def round_down() -> {F.round_even(4749) == 47 : U32}:
  {==}

def round_half_to_even_up() -> {F.round_even(4750) == 48 : U32}:
  {==}

def round_half_to_even_down() -> {F.round_even(4650) == 46 : U32}:
  {==}

def pct_pad() -> {F.pct_text(4700) == " 47%" : String}:
  {==}

def pct_full() -> {F.pct_text(10000) == "100%" : String}:
  {==}

def pct_zero() -> {F.pct_text(0) == "  0%" : String}:
  {==}

def dur_seconds() -> {F.duration(45) == "45s" : String}:
  {==}

def dur_minutes() -> {F.duration(720) == "12m" : String}:
  {==}

def dur_hours_minutes() -> {F.duration(7980) == "2h 13m" : String}:
  {==}

def dur_whole_hours() -> {F.duration(7200) == "2h" : String}:
  {==}

def dur_days_hours() -> {F.duration(100800) == "1d 4h" : String}:
  {==}

def dur_whole_days() -> {F.duration(86400) == "1d" : String}:
  {==}

def label_whole() -> {V.pct_label(9000) == "90" : String}:
  {==}

def label_half() -> {V.pct_label(8550) == "85.5" : String}:
  {==}

def label_hundredths() -> {V.pct_label(8505) == "85.05" : String}:
  {==}

# ---- bars

def plain(l: List<&2, F.Seg>) -> String:
  F.paint(l, False{})

def bar_half_full() -> {plain(F.bar(Some{5000}, 10n, None{}, False{})) == "━━━━━─────" : String}:
  {==}

def bar_half_cell() -> {plain(F.bar(Some{5500}, 10n, None{}, False{})) == "━━━━━╸────" : String}:
  {==}

def bar_unknown() -> {plain(F.bar(None{}, 10n, None{}, False{})) == "──────────" : String}:
  {==}

def bar_full() -> {plain(F.bar(Some{10000}, 10n, None{}, False{})) == "━━━━━━━━━━" : String}:
  {==}

def bar_threshold_tick() -> {plain(F.bar(Some{4700}, 10n, Some{9000}, False{})) == "━━━━╸────┃" : String}:
  {==}

def bar_over_threshold() -> {plain(F.bar(Some{9500}, 10n, Some{9000}, False{})) == "━━━━━━━━━┃" : String}:
  {==}

# ---- width, colour

def fit_short() -> {plain(F.fit([F.sg("hello", F.RPlain{})], 8n)) == "hello" : String}:
  {==}

def fit_cut() -> {plain(F.fit([F.sg("hello world", F.RPlain{})], 6n)) == "hello…" : String}:
  {==}

def fit_across_segments() -> {plain(F.fit([F.sg("ab", F.RPlain{}), F.sg("cdef", F.RMuted{})], 4n)) == "abc…" : String}:
  {==}

def fit_exact() -> {plain(F.fit([F.sg("abcd", F.RPlain{})], 4n)) == "abcd" : String}:
  {==}

def paint_off() -> {F.paint([F.sg("a", F.RCrit{})], False{}) == "a" : String}:
  {==}

def paint_on() -> {F.paint([F.sg("a", F.RCrit{})], True{}) == "\u{1B}[38;5;167ma\u{1B}[0m" : String}:
  {==}

def paint_plain_role() -> {F.paint([F.sg("a", F.RPlain{})], True{}) == "a" : String}:
  {==}

def paint_dim() -> {F.paint([F.Seg{"x", F.ROk{}, True{}}], True{}) == "\u{1B}[38;5;108;2mx\u{1B}[0m" : String}:
  {==}

def paint_merges_runs() -> {F.paint([F.sg("a", F.ROk{}), F.sg("b", F.ROk{}), F.sg("c", F.RWarn{})], True{}) == "\u{1B}[38;5;108mab\u{1B}[0m\u{1B}[38;5;179mc\u{1B}[0m" : String}:
  {==}

def severity_bands() -> {F.paint([F.sg("x", F.severity(6999)), F.sg("y", F.severity(7000)), F.sg("z", F.severity(9000))], True{}) == "\u{1B}[38;5;108mx\u{1B}[0m\u{1B}[38;5;179my\u{1B}[0m\u{1B}[38;5;167mz\u{1B}[0m" : String}:
  {==}

# ---- reading numbers

def centi_fraction() -> {N.centi_text("47.5") == Some{4750} : Maybe<&2, U32>}:
  {==}

def centi_whole() -> {N.centi_text("47") == Some{4700} : Maybe<&2, U32>}:
  {==}

def centi_small() -> {N.centi_text("0.05") == Some{5} : Maybe<&2, U32>}:
  {==}

def centi_truncates() -> {N.centi_text("47.555") == Some{4755} : Maybe<&2, U32>}:
  {==}

def centi_rejects_text() -> {N.centi_text("abc") == None{} : Maybe<&2, U32>}:
  {==}

def centi_rejects_exponent() -> {N.centi_text("1e2") == None{} : Maybe<&2, U32>}:
  {==}

def secs_of_float() -> {N.secs_of(N.parse_text("1792740000.1")) == Some{1792740000} : Maybe<&2, U32>}:
  {==}

# ---- a recorded status file (src/daemon/status.bend) and settings

def status_text() -> String:
  "{\"schemaVersion\": 1, \"pid\": 4242, \"version\": \"cswap-bend 0.0.1\", \"started_at\": \"2026-10-23T07:00:00Z\", \"last_poll_at\": \"2026-10-23T08:59:45Z\", \"next_poll_at\": \"2026-10-23T09:00:45Z\", \"active\": 2, \"accounts\": {\"2\": {\"pct_5h\": 20.0, \"pct_7d\": 10.0, \"fetched_at\": \"2026-10-23T08:59:30Z\", \"backoff_until\": null, \"last_error\": null}}}"

def settings_text() -> String:
  "{\"autoswitch\": {\"threshold\": 85.5, \"intervalSeconds\": 60}}"

def header_from_files() -> {R.hdr_of("v", True{}, N.parse_text(status_text()), N.parse_text(settings_text())) == M.Hdr{"v", True{}, Some{4242}, Some{8550}, Some{60}, Some{1792746045}} : M.Hdr}:
  {==}

def active_from_status() -> {R.active_slot(N.parse_text(status_text()), N.parse_text("{\"activeAccountNumber\": 1}")) == Some{2} : Maybe<&2, U32>}:
  {==}

def active_falls_back_to_roster() -> {R.active_slot(N.parse_text("not json"), N.parse_text("{\"activeAccountNumber\": 1}")) == Some{1} : Maybe<&2, U32>}:
  {==}

def window_from_cache() -> {R.win_of("5h", N.parse_text("{\"pct\": 47.0, \"resets_at\": \"2026-10-23T11:13:00+00:00\"}")) == Some{M.Win{"5h", Some{4700}, Some{1792753980}}} : Maybe<&2, M.Win>}:
  {==}

def window_without_pct() -> {R.win_of("5h", N.parse_text("{\"resets_at\": \"2026-10-23T11:13:00+00:00\"}")) == None{} : Maybe<&2, M.Win>}:
  {==}

def log_json_line() -> {R.log_text("{\"ts\": \"2026-10-23T08:59:45Z\", \"level\": \"info\", \"msg\": \"tick\", \"outcome\": \"no-action\", \"active\": \"1\", \"accounts\": []}") == "08:59:45  info tick no-action" : String}:
  {==}

def log_raw_line() -> {R.log_text("  boom  ") == "boom" : String}:
  {==}

def log_skips_blank() -> {R.log_lines(["", "x", "  "]) == ["x"] : List<&2, String>}:
  {==}

# ---- arguments

def args_flags() -> {Run.parse(3n, ["--once", "--interval", "5"], Run.default_opts()) == Run.Opts{True{}, 5, True{}, ""} : Run.Opts}:
  {==}

def args_no_color() -> {Run.parse(1n, ["--no-color"], Run.default_opts()) == Run.Opts{False{}, 2, False{}, ""} : Run.Opts}:
  {==}

def args_unknown() -> {Run.parse(1n, ["--x"], Run.default_opts()) == Run.Opts{False{}, 2, True{}, "unknown argument --x"} : Run.Opts}:
  {==}

def args_interval_zero() -> {Run.parse(2n, ["--interval", "0"], Run.default_opts()) == Run.Opts{False{}, 2, True{}, "--interval needs a whole number of seconds"} : Run.Opts}:
  {==}

def args_interval_missing() -> {Run.parse(1n, ["--interval"], Run.default_opts()) == Run.Opts{False{}, 2, True{}, "--interval needs a whole number of seconds"} : Run.Opts}:
  {==}
