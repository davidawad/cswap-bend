import Base
import ./usage/text.bend as UText

# The command line, as cli.py's argparse reads it: a leading verb (or its
# legacy --flag spelling), then flags and positionals in any order. A parse is
# a Parsed: a command to run, or the usage error argparse would print (exit 2).

type Parsed is Data:
  PHelp{}
  PVersion{}
  PList{json: Bool, token_status: Bool}
  PStatus{json: Bool}
  PAdd{slot: Maybe<&2, U32>, alias: Maybe<&2, String>}
  PAddToken{token: Maybe<&2, String>, email: Maybe<&2, String>, slot: Maybe<&2, U32>}
  PRemove{ident: String}
  PImportUsage{path: String, hold: Maybe<&2, U32>}
  PConfig{args: List<&2, String>, json: Bool}
  PProfile{args: List<&2, String>, json: Bool}
  PSwitch{ident: Maybe<&2, String>, force: Bool, strategy: Maybe<&2, String>, model: Maybe<&2, String>, json: Bool}
  PTui{args: List<&2, String>}
  PAuto{args: List<&2, String>}
  PDeferred{name: String}
  PBad{msg: String}

# One token of the command line: a flag with its value ("" for a switch), or a
# positional (empty name).
type Opt is Data:
  Opt{name: String, value: String}

type KV is Data:
  KV{k: String, v: String}

def verbs() -> List<&2, KV>:
  [KV{"help", "help"}, KV{"--help", "help"}, KV{"-h", "help"}, KV{"--version", "version"}, KV{"list", "list"}, KV{"ls", "list"}, KV{"--list", "list"},
   KV{"status", "status"}, KV{"--status", "status"}, KV{"add", "add"}, KV{"--add-account", "add"}, KV{"add-token", "add-token"}, KV{"--add-token", "add-token"},
   KV{"remove", "remove"}, KV{"rm", "remove"}, KV{"--remove-account", "remove"}, KV{"import-usage", "import-usage"}, KV{"--import-usage", "import-usage"},
   KV{"config", "config"}, KV{"profile", "profile"}, KV{"switch", "switch"}, KV{"--switch", "switch"}, KV{"--switch-to", "switch"}, KV{"auto", "auto"},
   KV{"run", "run"}, KV{"map", "map"}, KV{"unmap", "unmap"}, KV{"unclaimed", "unclaimed"}, KV{"alias", "alias"}, KV{"swap", "swap"}, KV{"move", "move"},
   KV{"disable", "disable"}, KV{"enable", "enable"}, KV{"export", "export"}, KV{"import", "import"}, KV{"purge", "purge"}, KV{"upgrade", "upgrade"},
   KV{"update", "upgrade"}, KV{"tui", "tui"}, KV{"watch", "watch"}, KV{"menubar", "menubar"}]

def verb.step(hit: Bool, v: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

def verb.find(+t: String, vs: List<&2, KV>) -> Maybe<&2, String>:
  match vs:
    case Nil{}:
      None{}
    case Con{KV{k, v}, rest}:
      verb.step(String.eq(k, t), v, verb.find(t, rest))

def verb.pick(+t: String) -> String:
  Maybe.default(&2, String, verb.find(t, verbs()), "")

# The canonical verb a first token names, "" when it is none.
def verb_of(+t: String) -> String:
  verb.pick(t)

def valued() -> List<&2, String>:
  ["--slot", "--email", "--alias", "--hold", "--strategy", "--model", "--account"]

def switches() -> List<&2, String>:
  ["--json", "--token-status", "--debug", "--force", "--full", "--install-service", "--uninstall-service", "--service-status"]

def has_str(+x: String, xs: List<&2, String>) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case Con{h, t}:
      String.eq(h, x) || has_str(x, t)

def is_flag(+t: String) -> Bool:
  String.starts_with(t, "-") && Nat.is_gt(String.length(t), 1n)

def split_eq.go(ps: List<&2, String>) -> String & Maybe<&2, String>:
  match ps:
    case Con{k, Nil{}}:
      (k, None{})
    case Con{k, Con{v, rest}}:
      (k, Some{String.join(v <> rest, "=")})
    case Nil{}:
      ("", None{})

# `--slot=3` as ("--slot", "3"); a bare flag has no value part.
def split_eq(+t: String) -> String & Maybe<&2, String>:
  split_eq.go(String.split(t, '='))

def opt.has(+name: String, os: List<&2, Opt>) -> Bool:
  match os:
    case Nil{}:
      False{}
    case Con{Opt{n, v}, t}:
      String.eq(n, name) || opt.has(name, t)

def opt.pick(hit: Bool, v: String, rest: Maybe<&2, String>) -> Maybe<&2, String>:
  match hit:
    case True{}:
      Some{v}
    case False{}:
      rest

def opt.val(+name: String, os: List<&2, Opt>) -> Maybe<&2, String>:
  match os:
    case Nil{}:
      None{}
    case Con{Opt{n, v}, t}:
      opt.pick(String.eq(n, name), v, opt.val(name, t))

def pos.pick(hit: Bool, v: String, rest: List<&2, String>) -> List<&2, String>:
  match hit:
    case True{}:
      v <> rest
    case False{}:
      rest

def positionals(os: List<&2, Opt>) -> List<&2, String>:
  match os:
    case Nil{}:
      []
    case Con{Opt{n, v}, t}:
      pos.pick(String.is_empty(n), v, positionals(t))

def first_of(xs: List<&2, String>) -> Maybe<&2, String>:
  match xs:
    case Con{h, t}:
      Some{h}
    case Nil{}:
      None{}

def prog() -> String:
  "cswap"

def usage_line() -> String:
  "usage: cswap <command> [args] [options]"

def flag.msg(on: Bool, msg: String, rest: String) -> String:
  match on:
    case True{}:
      msg
    case False{}:
      rest

def first.pick(empty: Bool, rest: String, h: String) -> String:
  match empty:
    case True{}:
      rest
    case False{}:
      h

def first_err(msgs: List<&2, String>) -> String:
  match msgs:
    case Nil{}:
      ""
    case Con{+h, t}:
      first.pick(String.is_empty(h), first_err(t), h)

def err_if(on: Bool, msg: String) -> String:
  flag.msg(on, msg, "")

def pos_err(+vb: String, +ps: List<&2, String>, +max: Nat) -> String:
  err_if(Nat.is_gt(List.length(&2, String, ps), max), "unrecognized arguments: " ++ String.join(List.drop(&2, String, ps, max), " "))

def strategy_err(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{+v}:
      err_if(Bool.not(has_str(v, ["best", "next-available"])), "argument --strategy: invalid choice: '" ++ v ++ "' (choose from 'best', 'next-available')")

def common_errs(+vb: String, +os: List<&2, Opt>) -> List<&2, String>:
  [err_if(opt.has("--token-status", os) && Bool.not(String.eq(vb, "list")), "--token-status can only be used with 'list'"),
   err_if(opt.has("--json", os) && Bool.not(has_str(vb, ["list", "status", "switch"])), "--json can only be used with 'list', 'status', or 'switch'"),
   err_if(opt.has("--json", os) && opt.has("--token-status", os), "--token-status cannot be combined with --json"),
   err_if(opt.has("--strategy", os) && Bool.not(String.eq(vb, "switch")), "--strategy can only be used with bare 'switch'"),
   err_if(opt.has("--model", os) && Bool.not(opt.has("--strategy", os)), "--model can only be used with 'switch --strategy best' or 'switch --strategy next-available'"),
   err_if(opt.has("--slot", os) && Bool.not(has_str(vb, ["add", "add-token"])), "--slot can only be used with 'add' or 'add-token'"),
   err_if(opt.has("--email", os) && Bool.not(String.eq(vb, "add-token")), "--email can only be used with 'add-token'"),
   err_if(opt.has("--account", os) && Bool.not(String.eq(vb, "export")), "--account can only be used with 'export'"),
   err_if(opt.has("--alias", os) && Bool.not(String.eq(vb, "add")), "--alias can only be used with 'add'"),
   err_if(opt.has("--force", os) && Bool.not(has_str(vb, ["import", "switch"])), "--force can only be used with 'import' or 'switch <num|email>'"),
   err_if(opt.has("--full", os) && Bool.not(String.eq(vb, "export")), "--full can only be used with 'export'"),
   err_if(opt.has("--hold", os) && Bool.not(String.eq(vb, "import-usage")), "--hold can only be used with 'import-usage'"),
   err_if(opt.has("--strategy", os) && String.eq(vb, "switch") && Bool.not(List.is_empty(&2, String, positionals(os))), "--strategy can only be used with bare 'switch'"),
   err_if(opt.has("--force", os) && String.eq(vb, "switch") && List.is_empty(&2, String, positionals(os)), "--force can only be used with 'import' or 'switch <num|email>'"),
   strategy_err(opt.val("--strategy", os)),
   err_if((opt.has("--install-service", os) || opt.has("--uninstall-service", os) || opt.has("--service-status", os)) && Bool.not(String.eq(vb, "menubar")),
     "--install-service, --uninstall-service and --service-status can only be used with 'menubar'")]

type Slot is Data:
  SlotOk{n: Maybe<&2, U32>}
  SlotBad{msg: String}

def slot.read(r: Maybe<&2, U32>, +s: String) -> Slot:
  match r:
    case Some{n}:
      SlotOk{Some{n}}
    case None{}:
      SlotBad{"argument --slot: invalid int value: '" ++ s ++ "'"}

def slot.of(m: Maybe<&2, String>) -> Slot:
  match m:
    case None{}:
      SlotOk{None{}}
    case Some{+s}:
      slot.read(U32.read(s), s)

type Hold is Data:
  HoldOk{secs: Maybe<&2, U32>}
  HoldBad{msg: String}

def hold.bad() -> Hold:
  HoldBad{"--hold must be a non-negative number of seconds"}

def hold.int(r: Maybe<&2, U32>) -> Hold:
  match r:
    case Some{n}:
      HoldOk{Some{n}}
    case None{}:
      hold.bad()

def hold.parts(ps: List<&2, String>) -> Hold:
  match ps:
    case Con{i, t}:
      hold.int(U32.read(i))
    case Nil{}:
      hold.bad()

def hold.norm(m: Maybe<&2, String>) -> Hold:
  match m:
    case Some{t}:
      hold.parts(String.split(t, '.'))
    case None{}:
      hold.bad()

def hold.of(m: Maybe<&2, String>) -> Hold:
  match m:
    case None{}:
      HoldOk{None{}}
    case Some{s}:
      hold.norm(UText.float(s))

def bad_text(msg: String) -> String:
  usage_line() ++ "\n" ++ prog() ++ ": error: " ++ msg

def bad(msg: String) -> Parsed:
  PBad{bad_text(msg)}

def sel.p(c: Bool, a: Parsed, b: Parsed) -> Parsed:
  match c:
    case True{}:
      a
    case False{}:
      b

def with_err(+e: String, p: Parsed) -> Parsed:
  sel.p(String.is_empty(e), p, bad(e))

def build.add(sl: Slot, alias: Maybe<&2, String>) -> Parsed:
  match sl:
    case SlotOk{n}:
      PAdd{n, alias}
    case SlotBad{msg}:
      bad(msg)

def build.token(sl: Slot, token: Maybe<&2, String>, email: Maybe<&2, String>) -> Parsed:
  match sl:
    case SlotOk{n}:
      PAddToken{token, email, n}
    case SlotBad{msg}:
      bad(msg)

def build.import(h: Hold, path: Maybe<&2, String>) -> Parsed:
  match h path:
    case HoldBad{msg} _:
      bad(msg)
    case HoldOk{secs} Some{p}:
      PImportUsage{p, secs}
    case HoldOk{secs} None{}:
      bad("argument --import-usage: expected one argument")

def build.remove(m: Maybe<&2, String>) -> Parsed:
  match m:
    case Some{i}:
      PRemove{i}
    case None{}:
      bad("argument --remove-account: expected one argument")

def max_pos(one: Bool) -> Nat:
  match one:
    case True{}:
      1n
    case False{}:
      0n

def arity(+vb: String, +ps: List<&2, String>) -> String:
  pos_err(vb, ps, max_pos(has_str(vb, ["add-token", "remove", "import-usage", "switch"])))

# A verb and the command it builds.
type Alt is Data:
  Alt{key: String, val: Parsed}

def choose.pick(hit: Bool, v: Parsed, rest: Parsed) -> Parsed:
  match hit:
    case True{}:
      v
    case False{}:
      rest

def choose(+vb: String, alts: List<&2, Alt>, dflt: Parsed) -> Parsed:
  match alts:
    case Nil{}:
      dflt
    case Con{Alt{k, v}, t}:
      choose.pick(String.eq(k, vb), v, choose(vb, t, dflt))

def build.cmd(+vb: String, +os: List<&2, Opt>, +ps: List<&2, String>) -> Parsed:
  choose(vb, [
    Alt{"help", PHelp{}}, Alt{"version", PVersion{}},
    Alt{"list", PList{opt.has("--json", os), opt.has("--token-status", os)}},
    Alt{"status", PStatus{opt.has("--json", os)}},
    Alt{"add", build.add(slot.of(opt.val("--slot", os)), opt.val("--alias", os))},
    Alt{"add-token", build.token(slot.of(opt.val("--slot", os)), first_of(ps), opt.val("--email", os))},
    Alt{"remove", build.remove(first_of(ps))},
    Alt{"switch", PSwitch{first_of(ps), opt.has("--force", os), opt.val("--strategy", os), opt.val("--model", os), opt.has("--json", os)}},
    Alt{"import-usage", build.import(hold.of(opt.val("--hold", os)), first_of(ps))}],
    PDeferred{vb})

def build.go(+vb: String, +os: List<&2, Opt>, +ps: List<&2, String>) -> Parsed:
  with_err(arity(vb, ps), build.cmd(vb, os, ps))

def build.verb(+vb: String, +os: List<&2, Opt>) -> Parsed:
  build.go(vb, os, positionals(os))

def build(+vb: String, +os: List<&2, Opt>) -> Parsed:
  with_err(first_err(common_errs(vb, os)), build.verb(vb, os))

def not_flag(+t: String) -> Bool:
  Bool.not(String.eq(t, "--json") || String.eq(t, "--debug"))

def config.keep(keep: Bool, h: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      h <> rest
    case False{}:
      rest

def config_args(ts: List<&2, String>) -> List<&2, String>:
  match ts:
    case Nil{}:
      []
    case Con{+h, t}:
      config.keep(not_flag(h), h, config_args(t))

type Scan is Data:
  Scan{opts: List<&2, Opt>, pending: String, err: String}

def sel.s(c: Bool, a: String, b: String) -> String:
  match c:
    case True{}:
      a
    case False{}:
      b

def first_msg(+err: String, +name: String) -> String:
  sel.s(String.is_empty(err), "unrecognized arguments: " ++ name, err)

def scan.fail(err: String, +name: String) -> String:
  first_msg(err, name)

def scan.flag2(valued: Bool, switch: Bool, +name: String, inline: Maybe<&2, String>, opts: List<&2, Opt>, err: String) -> Scan:
  match valued switch inline:
    case True{} _ Some{v}:
      Scan{Opt{name, v} <> opts, "", err}
    case True{} _ None{}:
      Scan{opts, name, err}
    case False{} True{} _:
      Scan{Opt{name, ""} <> opts, "", err}
    case False{} False{} _:
      Scan{opts, "", scan.fail(err, name)}

def scan.flag(kv: String & Maybe<&2, String>, opts: List<&2, Opt>, err: String) -> Scan:
  (+k, v) = kv
  scan.flag2(has_str(k, valued()), has_str(k, switches()), k, v, opts, err)

def scan.free(flag: Bool, +t: String, opts: List<&2, Opt>, err: String) -> Scan:
  match flag:
    case True{}:
      scan.flag(split_eq(t), opts, err)
    case False{}:
      Scan{Opt{"", t} <> opts, "", err}

def scan.step2(pending: Bool, +h: String, +name: String, opts: List<&2, Opt>, err: String) -> Scan:
  match pending:
    case True{}:
      Scan{Opt{name, h} <> opts, "", err}
    case False{}:
      scan.free(is_flag(h), h, opts, err)

def scan.step(+h: String, sc: Scan) -> Scan:
  match sc:
    case Scan{opts, +pending, err}:
      scan.step2(Bool.not(String.is_empty(pending)), h, pending, opts, err)

def scan.go(ts: List<&2, String>, sc: Scan) -> Scan:
  match ts:
    case Nil{}:
      sc
    case Con{h, t}:
      scan.go(t, scan.step(h, sc))

def scan.dangling(+pending: String, err: String) -> String:
  sel.s(String.is_empty(pending), err, "argument " ++ pending ++ ": expected one argument")

def scan.end(sc: Scan) -> Scan:
  match sc:
    case Scan{opts, pending, err}:
      Scan{List.reverse(&2, Opt, opts), "", scan.dangling(pending, err)}

def scan(ts: List<&2, String>) -> Scan:
  scan.end(scan.go(ts, Scan{[], "", ""}))

def scan.done(+err: String, +vb: String, +opts: List<&2, Opt>) -> Parsed:
  sel.p(String.is_empty(err), build(vb, opts), bad(err))

def parse.scan(+vb: String, sc: Scan) -> Parsed:
  match sc:
    case Scan{opts, pending, err}:
      scan.done(err, vb, opts)

def parse.verb(+vb: String, +rest: List<&2, String>) -> Parsed:
  sel.p(String.eq(vb, "tui") || String.eq(vb, "watch"), PTui{rest}, sel.p(String.eq(vb, "auto"), PAuto{rest}, sel.p(String.eq(vb, "config"), PConfig{config_args(rest), has_str("--json", rest)}, sel.p(String.eq(vb, "profile"), PProfile{config_args(rest), has_str("--json", rest)}, sel.p(has_str(vb, ["help", "version", "list", "status", "add", "add-token", "remove", "import-usage", "switch"]), parse.scan(vb, scan(rest)), PDeferred{vb})))))

def parse.first(+vb: String, +h: String, +rest: List<&2, String>) -> Parsed:
  sel.p(String.is_empty(vb), bad("unrecognized arguments: " ++ h), parse.verb(vb, rest))

# The command a command line asks for, or the usage error (PBad) argparse
# would print.
def parse(ts: List<&2, String>) -> Parsed:
  match ts:
    case Nil{}:
      bad("no command given - try 'cswap help'")
    case Con{+h, rest}:
      parse.first(verb_of(h), h, rest)
