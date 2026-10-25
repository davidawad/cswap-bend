import Base

# ---- environment and paths -----------------------------------------------------------

# `home` is $HOME; `config_home` is $CLAUDE_CONFIG_DIR or ~/.claude (it holds
# .credentials.json); `global_base` is $CLAUDE_CONFIG_DIR or $HOME (it holds
# .claude.json). The legacy <config home>/.config.json is not consulted.

type Ctx is Data:
  Ctx{home: String, config_home: String, global_base: String}

def ctx_of2(+home: String, +dir: String, +unset: Bool) -> Ctx:
  match unset:
    case True{}:
      Ctx{home, home ++ "/.claude", home}
    case False{}:
      Ctx{home, dir, dir}

def ctx_of(+home: String, +claude_config_dir: String) -> Ctx:
  ctx_of2(home, claude_config_dir, String.is_empty(claude_config_dir))

def root_of(+ctx: Ctx) -> String:
  match ctx:
    case Ctx{home, c, g}:
      home ++ "/.claude-swap-backup"

def live_creds_path(+ctx: Ctx) -> String:
  match ctx:
    case Ctx{home, c, g}:
      c ++ "/.credentials.json"

def global_config_path(+ctx: Ctx) -> String:
  match ctx:
    case Ctx{home, c, g}:
      g ++ "/.claude.json"

def seq_path(+root: String) -> String:
  root ++ "/sequence.json"

def lock_path(+root: String) -> String:
  root ++ "/.lock"

def log_path(+root: String) -> String:
  root ++ "/claude-swap.log"

def creds_dir(+root: String) -> String:
  root ++ "/credentials"

def configs_dir(+root: String) -> String:
  root ++ "/configs"

def removed_dir(+root: String) -> String:
  creds_dir(root) ++ "/.removed"

def removed_configs_dir(+root: String) -> String:
  configs_dir(root) ++ "/.removed"

def enc_path(+root: String, +slot: String, +email: String) -> String:
  creds_dir(root) ++ "/.creds-" ++ slot ++ "-" ++ email ++ ".enc"

def prev_path(+root: String, +slot: String, +email: String) -> String:
  enc_path(root, slot, email) ++ ".prev"

def config_path(+root: String, +slot: String, +email: String) -> String:
  configs_dir(root) ++ "/.claude-config-" ++ slot ++ "-" ++ email ++ ".json"

# credentials/.removed/<utc-ts>-<slot>-<email>.enc, `ts` like 20261023T120000Z.
def removed_enc_path(+root: String, +ts: String, +slot: String, +email: String) -> String:
  removed_dir(root) ++ "/" ++ ts ++ "-" ++ slot ++ "-" ++ email ++ ".enc"

def removed_config_path(+root: String, +ts: String, +slot: String, +email: String) -> String:
  removed_configs_dir(root) ++ "/" ++ ts ++ "-" ++ slot ++ "-" ++ email ++ ".json"

# ---- small string tools ------------------------------------------------------------

def sel.s(+c: Bool, +x: String, +y: String) -> String:
  match c:
    case True{}:
      x
    case False{}:
      y

def strip_chars.pick(+skip: Bool, +c: Char, +rest: String) -> String:
  match skip:
    case True{}:
      rest
    case False{}:
      SCon{c, rest}

# Drop every char of `drop` from `s`.
def strip_chars(+s: String, +drop: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      strip_chars.pick(String.contains(drop, SCon{c, SNil{}}), c, strip_chars(t, drop))

# 2026-10-23T12:00:00Z becomes 20261023T120000Z, safe in a file name.
def compact_ts(+iso: String) -> String:
  strip_chars(iso, "-:")

# The reference's `%(asctime)s` stamp: `2026-10-23 12:00:00,000`.
def log_stamp(+iso: String) -> String:
  String.take(iso, 10n) ++ " " ++ String.take(String.drop(iso, 11n), 8n) ++ ",000"

def log_line(+iso: String, +level: String, +msg: String) -> String:
  log_stamp(iso) ++ " - " ++ level ++ " - " ++ msg ++ "\n"

# ---- validation ---------------------------------------------------------------------

def is_oauth_token(+t: String) -> Bool:
  String.starts_with(t, "sk-ant-oat") || String.starts_with(t, "sk-ant-ort")

def not_(+b: Bool) -> Bool:
  Bool.not(b)

def looks_like_api_key2(+t: String) -> Bool:
  not_(String.starts_with(t, "{")) && String.starts_with(t, "sk-ant-") && not_(is_oauth_token(t))

# A bare `sk-ant-` value that is not an OAuth token is a managed API key.
def looks_like_api_key(+text: String) -> Bool:
  looks_like_api_key2(String.trim(text))

def email_char(+c: Char) -> Bool:
  Char.is_digit(c) || Char.is_alpha(c) || Char.is_eq(c, '.') || Char.is_eq(c, '-') || Char.is_eq(c, '_') || Char.is_eq(c, '%') || Char.is_eq(c, '+')

def domain_char(+c: Char) -> Bool:
  Char.is_digit(c) || Char.is_alpha(c) || Char.is_eq(c, '.') || Char.is_eq(c, '-')

def sel.b(+c: Bool, +x: Bool, +y: Bool) -> Bool:
  match c:
    case True{}:
      x
    case False{}:
      y

def all_chars(+s: String, +local: Bool) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{+c, t}:
      sel.b(local, email_char(c), domain_char(c)) && all_chars(t, local)

def all_alpha(+s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Char.is_alpha(c) && all_alpha(t)

def nonempty(+s: String) -> Bool:
  not_(String.is_empty(s))

def valid_host2(+tld: Maybe<&2, String>, +n: Nat, +chars: Bool) -> Bool:
  match tld:
    case None{}:
      False{}
    case Some{t}:
      chars && Nat.is_ge(n, 2n) && all_alpha(t) && Nat.is_ge(String.length(t), 2n)

# host = prefix.tld: the last dot-separated part is 2+ letters and what is
# left of it is a non-empty run of host characters.
def valid_host(+segs: List<&2, String>, +host: String) -> Bool:
  valid_host2(List.last(&2, String, segs), List.length(&2, String, segs), all_chars(host, False{}))

def valid_email2(+parts: List<&2, String>) -> Bool:
  match parts:
    case Con{local, Con{host, Nil{}}}:
      nonempty(local) && all_chars(local, True{}) && valid_host(String.split(host, '.'), host)
    case _:
      False{}

# local@host.tld by `^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$`.
def valid_email(+e: String) -> Bool:
  valid_email2(String.split(e, '@'))

def all_digits(+s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      Char.is_digit(c) && all_digits(t)

# models.normalize_alias: lowercase, non-empty, not all digits, no leading `-`.
def alias_ok(+a: String) -> Bool:
  nonempty(a) && not_(all_digits(a)) && not_(String.starts_with(a, "-"))
