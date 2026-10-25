import Base
import ./json.bend as Json
import ./act.bend as Act
import ./cmd.bend as Cmd
import ./fs.bend as Fs
import ./setload.bend as Setload
import ./setwrite.bend as Setwrite
import ./profile.bend as P
import ./policy/safe.bend as SF
import ./daemon/config.bend as Cfg
import ./daemon/events.bend as Ev

# How `cswap profile` prints profiles: JSON and the table.
# (`cswap profile list|show|use|set|remove` is src/profcmd.bend.)
# The profiles live in settings.json (src/profile.bend);
# a write changes only `profiles` / `active_profile` and keeps every other key.

# ------------------------------------------------------------------ views

def is_active.of(+a: Maybe<&2, String>, +name: String) -> Bool:
  match a:
    case Some{x}:
      String.eq(x, name)
    case None{}:
      String.eq(name, "default")

# `default` is the active profile while `active_profile` is unset.
def is_active(+raw: Json.Json, +name: String) -> Bool:
  is_active.of(P.active(raw), name)

def opt_json(+m: Maybe<&2, Json.Json>) -> Json.Json:
  match m:
    case Some{j}:
      j
    case None{}:
      Json.JNull{}

def models_arr(+ms: List<&2, String>) -> Json.Json:
  Json.arr(P.strs_json(ms))

def eff_json(+e: Cfg.Cfg) -> Json.Json:
  Json.of_pairs([("strategy", Json.JStr{Cfg.cfg_strategy(e)}), ("threshold", Ev.fl(Cfg.cfg_threshold(e))), ("models", models_arr(Cfg.cfg_models(e))),
    ("cooldown_s", Json.JNum{U32.show(Cfg.cfg_cooldown(e))}), ("interval_s", Json.JNum{U32.show(Cfg.cfg_interval(e))})])

def num_or_null(+m: Maybe<&2, String>) -> Json.Json:
  opt_json(P.num_json(m))

def prof_json2(+p: P.Prof, +is_builtin: Bool, +stored: Bool, +active: Bool, +e: Cfg.Cfg) -> Json.Json:
  match p:
    case P.Prof{n, algo, th, ms, cd, iv}:
      Json.of_pairs([("name", Json.JStr{n}), ("builtin", Json.JBool{is_builtin}), ("stored", Json.JBool{stored}), ("active", Json.JBool{active}),
        ("strategy", Json.JStr{SF.name(algo)}), ("threshold", num_or_null(th)), ("models", opt_json(P.models_json(ms))), ("cooldown_s", num_or_null(cd)),
        ("interval_s", num_or_null(iv)), ("effective", eff_json(e))])

# A profile as the commands print it: what it sets, and what it comes to over the settings.
def prof_json(+raw: Json.Json, +cfg: Cfg.Cfg, +p: P.Prof) -> Json.Json:
  prof_json2(p, P.is_builtin(P.name_of(p)), P.has_stored(raw, P.name_of(p)), is_active(raw, P.name_of(p)), P.with_prof(cfg, p))

def cell(+set: Maybe<&2, String>, +eff: String) -> String:
  match set:
    case Some{t}:
      t
    case None{}:
      "(" ++ eff ++ ")"

def models_eff(+ms: List<&2, String>) -> String:
  match ms:
    case Nil{}:
      "all"
    case o:
      String.join(ms, ",")

def models_cell(+set: Maybe<&2, String>, +eff: List<&2, String>) -> String:
  match set:
    case Some{t}:
      models_eff(Cfg.parse_models(t))
    case None{}:
      "(" ++ models_eff(eff) ++ ")"

type Row is Data:
  Row{mark: String, name: String, strategy: String, threshold: String, models: String, cooldown: String, interval: String, source: String}

def source_of(+is_builtin: Bool, +stored: Bool) -> String:
  match is_builtin stored:
    case True{} True{}:
      "built-in, overridden"
    case True{} False{}:
      "built-in"
    case False{} _:
      "custom"

def row_of2(+p: P.Prof, +mark: String, +src: String, +e: Cfg.Cfg) -> Row:
  match p:
    case P.Prof{n, algo, th, ms, cd, iv}:
      Row{mark, n, SF.name(algo), cell(th, Ev.pct_label(Cfg.cfg_threshold(e))), models_cell(ms, Cfg.cfg_models(e)), cell(cd, U32.show(Cfg.cfg_cooldown(e))), cell(iv, U32.show(Cfg.cfg_interval(e))), src}

def mark(+active: Bool) -> String:
  match active:
    case True{}:
      "*"
    case False{}:
      " "

def row_of(+raw: Json.Json, +cfg: Cfg.Cfg, +p: P.Prof) -> Row:
  row_of2(p, mark(is_active(raw, P.name_of(p))), source_of(P.is_builtin(P.name_of(p)), P.has_stored(raw, P.name_of(p))), P.with_prof(cfg, p))

def rows_push(+m: Maybe<&2, P.Prof>, +raw: Json.Json, +cfg: Cfg.Cfg, +rest: List<&2, Row>) -> List<&2, Row>:
  match m:
    case Some{p}:
      row_of(raw, cfg, p) <> rest
    case None{}:
      rest

def rows_of(+raw: Json.Json, +cfg: Cfg.Cfg, +ns: List<&2, String>) -> List<&2, Row>:
  match ns:
    case Nil{}:
      []
    case Con{n, t}:
      rows_push(P.find(raw, n), raw, cfg, rows_of(raw, cfg, t))

def header() -> Row:
  Row{" ", "NAME", "STRATEGY", "THRESHOLD", "MODELS", "COOLDOWN_S", "INTERVAL_S", "SOURCE"}

def col_name(+rs: List<&2, Row>) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{Row{m, n, s, t, ms, c, i, src}, t2}:
      n <> col_name(t2)

def col_strategy(+rs: List<&2, Row>) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{Row{m, n, s, t, ms, c, i, src}, t2}:
      s <> col_strategy(t2)

def col_threshold(+rs: List<&2, Row>) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{Row{m, n, s, t, ms, c, i, src}, t2}:
      t <> col_threshold(t2)

def col_models(+rs: List<&2, Row>) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{Row{m, n, s, t, ms, c, i, src}, t2}:
      ms <> col_models(t2)

def col_cooldown(+rs: List<&2, Row>) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{Row{m, n, s, t, ms, c, i, src}, t2}:
      c <> col_cooldown(t2)

def col_interval(+rs: List<&2, Row>) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{Row{m, n, s, t, ms, c, i, src}, t2}:
      i <> col_interval(t2)

type Widths is Data:
  Widths{n: Nat, s: Nat, t: Nat, m: Nat, c: Nat, i: Nat}

def widths(+rs: List<&2, Row>) -> Widths:
  Widths{Setwrite.width(col_name(rs), 0n), Setwrite.width(col_strategy(rs), 0n), Setwrite.width(col_threshold(rs), 0n), Setwrite.width(col_models(rs), 0n), Setwrite.width(col_cooldown(rs), 0n), Setwrite.width(col_interval(rs), 0n)}

def line(+w: Widths, +r: Row) -> String:
  match w r:
    case Widths{wn, ws, wt, wm, wc, wi} Row{m, n, s, t, ms, c, i, src}:
      m ++ " " ++ Setwrite.pad(n, wn) ++ "  " ++ Setwrite.pad(s, ws) ++ "  " ++ Setwrite.pad(t, wt) ++ "  " ++ Setwrite.pad(ms, wm) ++ "  " ++ Setwrite.pad(c, wc) ++ "  " ++ Setwrite.pad(i, wi) ++ "  " ++ src

def lines(+w: Widths, +rs: List<&2, Row>) -> List<&2, String>:
  match rs:
    case Nil{}:
      []
    case Con{r, t}:
      line(w, r) <> lines(w, t)

# A table; a parenthesised cell is inherited from the autoswitch settings.
def table(+rs: List<&2, Row>) -> String:
  String.join(lines(widths(Con{header(), rs}), Con{header(), rs}), "\n")

def prof_push(+m: Maybe<&2, P.Prof>, +raw: Json.Json, +cfg: Cfg.Cfg, +rest: List<&2, Json.Json>) -> List<&2, Json.Json>:
  match m:
    case Some{p}:
      prof_json(raw, cfg, p) <> rest
    case None{}:
      rest

def prof_jsons(+raw: Json.Json, +cfg: Cfg.Cfg, +ns: List<&2, String>) -> List<&2, Json.Json>:
  match ns:
    case Nil{}:
      []
    case Con{n, t}:
      prof_push(P.find(raw, n), raw, cfg, prof_jsons(raw, cfg, t))

