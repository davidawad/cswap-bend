import Base
import ./cfgio.bend as Cfgio
import ./cliops.bend as Cliops
import ./clilist.bend as Clilist
import ./cliswitch.bend as Cliswitch
import ./profswitch.bend as Profswitch
import ./profflag.bend as Profflag
import ./store/base.bend as SBase
import ./cmd.bend as Cmd
import ./args.bend as Args
import ./store.bend as Store
import ./settings.bend as Settings
import ./tui/run.bend as Tui
import ./daemon/entry.bend as Entry
import ./clibase.bend as Clibase
import ./gflags.bend as Gf
import ./setload.bend as Setload
import ./fmt/out.bend as O
import ./fmt/code.bend as Code

def help_text() -> String:
  "usage: cswap <command> [args] [options]\n\nMulti-Account Switcher for Claude Code\n\nCommands:\n"
    ++ "  cswap help                       show this help\n"
    ++ "  cswap list                       list managed accounts\n"
    ++ "  cswap status                     show current account\n"
    ++ "  cswap switch                     rotate to the next account\n"
    ++ "  cswap switch <num|email>         switch to a specific account\n"
    ++ "  cswap add                        add the current account\n"
    ++ "  cswap add-token [TOKEN|-]        register a setup-token or API key\n"
    ++ "  cswap remove <num|email>         remove an account\n"
    ++ "  cswap auto                       auto-switch when nearing rate limits\n"
    ++ "  cswap config [set KEY VALUE]     show or change settings (settings.json)\n"
    ++ "  cswap profile [list|show|use|set|remove]  behaviour profiles (strategy, threshold, models, cooldown, interval)\n"
    ++ "  cswap import-usage <path>        adopt usage another machine read (list --json)\n"
    ++ "  cswap config export              the whole settings.json (profiles included); --format json|yaml|toon|csv\n"
    ++ "  cswap config import FILE|-       merge a settings file in (.json .yaml .yml .toon, .csv as key,value rows)\n"
    ++ "  cswap profile export [NAME]      the profiles (or one) as a document\n"
    ++ "  cswap profile import FILE|-      merge profiles in\n"
    ++ "  cswap rpc                        one request per line on stdin, one response per line on stdout (docs/API.md)\n"
    ++ "  cswap serve --socket PATH        the same protocol on a unix socket (mode 0600)\n"
    ++ "  cswap tui                        read-only dashboard, redrawn every 2 s until killed (--once, --interval N)\n"
    ++ "  cswap watch                      same dashboard as tui (periodic refresh, no key bindings)\n"
    ++ "  cswap menubar                    not supported in cswap-bend (exit 2); use cswap tui\n"
    ++ "  cswap upgrade                    show how to upgrade this build (rebuild from the repo)\n\n"
    ++ "Aliases: ls=list  rm=remove  update=upgrade\n\n"
    ++ "options:\n"
    ++ "  -h, --help            show this help message and exit\n"
    ++ "  --version             show program's version number and exit\n"
    ++ "  --debug               Enable debug logging\n"
    ++ "  --json                Emit machine-readable JSON to stdout (use with 'list', 'status', or 'switch').\n"
    ++ "  --format FORMAT       text (default), json (same as --json), csv, yaml or toon, for list, status, switch,\n"
    ++ "                        config, profile, import-usage and the 'auto' event stream\n"
    ++ "  --no-input            Never read standard input; a prompt becomes an error\n"
    ++ "  --yes                 Answer the 'remove' confirmation\n"
    ++ "  --slot NUM            Specify slot number when adding account (use with 'add' or 'add-token')\n"
    ++ "  --email EMAIL         Email address for the account. Optional with 'add-token'; defaults to\n"
    ++ "                        setup-token-{slot}@token.local (or api-key-{slot}@token.local for API keys)\n"
    ++ "  --alias NAME          Set a short display alias for the account (use with 'add')\n"
    ++ "  --hold SECONDS        With 'import-usage': keep this machine from fetching the imported accounts\n"
    ++ "                        for this many seconds (0 lifts an earlier hold)\n\n"
    ++ "Flags combine with subcommands:\n"
    ++ "  cswap list --json\n"
    ++ "  cswap import-usage usage.json --hold 600  # adopt another machine's list --json\n"
    ++ "  cswap add --slot 3                        # add to a specific slot\n"
    ++ "  cswap add-token sk-ant-oat01-... --email me@example.com\n"
    ++ "  cswap config set autoswitch.threshold 80\n"

def with_ctx(f: SBase.Ctx -> IO(Cmd.Out)) -> IO(Cmd.Out):
  IO.bind(SBase.Ctx, Cmd.Out, Store.ctx_env(), f)

def not_yet(+name: String) -> Cmd.Out:
  Cmd.Out{2, "", "cswap: " ++ name ++ " is not implemented yet in cswap-bend\n"}

def upgrade_text() -> String:
  "cswap-bend does not upgrade itself. It is built from source, so to upgrade this build:\n"
    ++ "  1. git pull in the cswap-bend repo (your checkout)\n"
    ++ "  2. just build            (writes bin/cswap-bend)\n"
    ++ "  3. deploy it: deploy/install-live copies the binary to ~/.local/share/cswap-bend/<sha>/ and reloads the launchd job (read its header first)\n"

def menubar_text() -> String:
  "cswap: menubar is not supported in cswap-bend; use 'cswap tui' (or 'cswap watch') for a live dashboard\n"

def deferred_pick(+up: Bool, +mb: Bool, +name: String) -> Cmd.Out:
  match up mb:
    case True{} _:
      Cmd.Out{0, upgrade_text(), ""}
    case False{} True{}:
      Cmd.Out{2, "", menubar_text()}
    case False{} False{}:
      not_yet(name)

def deferred(+name: String) -> Cmd.Out:
  deferred_pick(String.eq(name, "upgrade"), String.eq(name, "menubar"), name)

def config_cmd(+ctx: SBase.Ctx, ts: List<&2, String>, +json: Bool, +ni: Cliops.Ni) -> IO(Cmd.Out):
  Cfgio.config(SBase.root_of(ctx), ts, json, Cliops.ni_noin(ni))

def account_cmd(+ni: Cliops.Ni, +p: Args.Parsed) -> IO(Cmd.Out):
  match p:
    case Args.PAdd{slot, alias}:
      with_ctx(ctx => Clibase.run_act(False{}, Cliops.add_cmd(ctx, alias, slot, ni)))
    case Args.PAddToken{token, email, slot}:
      with_ctx(ctx => Clibase.run_act(False{}, Cliops.add_token_cmd(ctx, token, email, slot, ni)))
    case Args.PRemove{ident}:
      with_ctx(ctx => Clibase.run_act(False{}, Cliops.remove_cmd(ctx, ident, ni)))
    case Args.PImportUsage{path, hold}:
      with_ctx(ctx => Clibase.run_act(False{}, Cliops.import_cmd(ctx, path, hold)))
    case Args.PDeferred{name}:
      IO.pure(Cmd.Out, deferred(name))
    case _:
      IO.pure(Cmd.Out, not_yet("command"))

def view_cmd(+ni: Cliops.Ni, +p: Args.Parsed) -> IO(Cmd.Out):
  match p:
    case Args.PList{+json, token_status}:
      with_ctx(ctx => Clibase.run_act(json, Clilist.list_cmd(ctx, json)))
    case Args.PStatus{+json}:
      with_ctx(ctx => Clibase.run_act(json, Clilist.status_cmd(ctx, json)))
    case Args.PSwitch{ident, force, strategy, model, json}:
      with_ctx(ctx => Cliswitch.switch_cmd(ctx, ident, force, strategy, model, json))
    case _:
      account_cmd(ni, p)

def other_cmd(+ni: Cliops.Ni, +p: Args.Parsed) -> IO(Cmd.Out):
  match p:
    case Args.PProfile{ts, json}:
      with_ctx(ctx => Cfgio.profile(SBase.root_of(ctx), ts, json, Cliops.ni_noin(ni)))
    case _:
      view_cmd(ni, p)

# One case per command family; a command that arrives later (auto) is one more
# case here and one more entry in Args.build.cmd.
def dispatch(+ni: Cliops.Ni, +p: Args.Parsed) -> IO(Cmd.Out):
  match p:
    case Args.PHelp{}:
      IO.pure(Cmd.Out, Cmd.Out{0, help_text(), ""})
    case Args.PVersion{}:
      IO.pure(Cmd.Out, Cmd.ok(Clibase.version()))
    case Args.PBad{msg}:
      IO.pure(Cmd.Out, Cmd.Out{2, "", msg ++ "\n"})
    case Args.PTui{ts}:
      IO.bind(Unit, Cmd.Out, Tui.main(Clibase.affine(ts), Clibase.version()), u => IO.pure(Cmd.Out, Cmd.silent()))
    case Args.PAuto{ts}:
      Entry.auto_cmd(ts, Clibase.version())
    case Args.PConfig{ts, json}:
      with_ctx(ctx => config_cmd(ctx, ts, json, ni))
    case _:
      other_cmd(ni, p)

def shared(ts: List<String>) -> List<&2, String>:
  match ts:
    case Nil{}:
      []
    case Con{h, t}:
      h <> shared(t)

def tail_of(ts: List<String>) -> List<&2, String>:
  match ts:
    case Con{h, t}:
      shared(t)
    case Nil{}:
      []

# `switch` follows a behaviour profile when `--profile NAME` (or the active
# profile) names one; every other command runs as parsed.
def switch_route(+ni: Cliops.Ni, +over: Maybe<&2, String>, +p: Args.Parsed) -> IO(Cmd.Out):
  match p:
    case Args.PSwitch{ident, force, strategy, model, json}:
      with_ctx(ctx => Profswitch.switch_cmd(ctx, over, ident, force, strategy, model, json))
    case _:
      dispatch(ni, p)

def run5(+ni: Cliops.Ni, +ok: Bool, +h: String, +rest: List<&2, String>, +over: Maybe<&2, String>, +err: String) -> IO(Cmd.Out):
  match ok:
    case True{}:
      switch_route(ni, over, Args.parse(h <> rest))
    case False{}:
      dispatch(ni, Args.PBad{Args.bad_text(err)})

def run4(+ni: Cliops.Ni, +h: String, +sp: Profflag.Split) -> IO(Cmd.Out):
  match sp:
    case Profflag.Split{rest, over, err, pending}:
      run5(ni, String.is_empty(err), h, rest, over, err)

def run3(+ni: Cliops.Ni, +is_switch: Bool, +h: String, +t: List<&2, String>, +args: List<&2, String>) -> IO(Cmd.Out):
  match is_switch:
    case True{}:
      run4(ni, h, Profflag.split(t))
    case False{}:
      dispatch(ni, Args.parse(args))

def run2(+ni: Cliops.Ni, +args: List<&2, String>) -> IO(Cmd.Out):
  match args:
    case Nil{}:
      dispatch(ni, Args.parse(args))
    case Con{h, t}:
      run3(ni, String.eq(Args.verb_of(h), "switch"), h, t, Con{h, t})

# ---- --format, --no-input, --yes ---------------------------------------------------------------------

def usage_out(+msg: String) -> Cmd.Out:
  Cmd.Out{2, "", Args.bad_text(msg) ++ "\n"}

def words.step(skip: Bool, flag: Bool, +h: String, rest: List<&2, String>) -> List<&2, String>:
  match skip flag:
    case True{} _:
      rest
    case False{} True{}:
      rest
    case False{} False{}:
      h <> rest

# The words that are not options (and not the value of --format).
def words(args: List<&2, String>, skip: Bool) -> List<&2, String>:
  match args:
    case Nil{}:
      []
    case Con{+h, t}:
      words.step(skip, String.starts_with(h, "-"), h, words(t, String.eq(h, "--format")))

def first_verb(args: List<&2, String>) -> String:
  match args:
    case Nil{}:
      ""
    case Con{h, t}:
      Args.verb_of(h)

def word0(+args: List<&2, String>) -> String:
  Maybe.default(&2, String, List.head(&2, String, words(args, False{})), "")

def word1(+args: List<&2, String>) -> String:
  Maybe.default(&2, String, List.head(&2, String, List.drop(&2, String, words(args, False{}), 1n)), "")

# `config import` and `profile import` use --format for the input file.
def keeps_format(+v0: String, +v1: String) -> Bool:
  (String.eq(v0, "config") || String.eq(v0, "profile")) && String.eq(v1, "import")

# `--json` for the verbs that print a JSON document of their own; every other
# command's text is wrapped by O.convert.
def has_json(+v0: String, +v1: String) -> Bool:
  String.eq(v0, "list") || String.eq(v0, "status") || String.eq(v0, "switch") || String.eq(v0, "profile")
    || (String.eq(v0, "config") && (String.is_empty(v1) || String.eq(v1, "list") || String.eq(v1, "get") || String.eq(v1, "export") || String.eq(v1, "import")))

def add_json(on: Bool, +args: List<&2, String>) -> List<&2, String>:
  match on:
    case True{}:
      List.append(&2, String, args, ["--json"])
    case False{}:
      args

def with_json(+args: List<&2, String>) -> List<&2, String>:
  add_json(has_json(Args.verb_of(word0(args)), word1(args)) && Bool.not(Setload.has_str(args, "--json")), args)

# Which CSV shape (src/fmt/shape.bend) a command's document has.
def shape_key2(+v0: String, +v1: String) -> String:
  Bool.pick(String, String.eq(v0, "list"), "list",
  Bool.pick(String, String.eq(v0, "status"), "status",
  Bool.pick(String, String.eq(v0, "config") && (String.is_empty(v1) || String.eq(v1, "list")), "config-list",
  Bool.pick(String, String.eq(v0, "profile") && (String.is_empty(v1) || String.eq(v1, "list") || String.eq(v1, "ls")), "profile-list",
  Bool.pick(String, String.eq(v1, "export"), "export", v0)))))

def shape_key(+args: List<&2, String>) -> String:
  shape_key2(Args.verb_of(word0(args)), word1(args))

def fmt_bad(+name: String) -> Cmd.Out:
  usage_out("argument --format: invalid choice: '" ++ name ++ "' (choose from " ++ Code.choices() ++ ")")

def ni_of(+g: Gf.G) -> Cliops.Ni:
  match g:
    case Gf.G{rest, fmt, noin, yes, err, p}:
      Cliops.Ni{noin, yes}

def g_rest(+g: Gf.G) -> List<&2, String>:
  match g:
    case Gf.G{rest, fmt, noin, yes, err, p}:
      rest

def g_fmt(+g: Gf.G) -> Maybe<&2, String>:
  match g:
    case Gf.G{rest, fmt, noin, yes, err, p}:
      fmt

def g_err(+g: Gf.G) -> String:
  match g:
    case Gf.G{rest, fmt, noin, yes, err, p}:
      err

def converted(+f: O.Fmt, +key: String, o: Cmd.Out) -> IO(Cmd.Out):
  IO.pure(Cmd.Out, O.convert(f, key, o))

def run_conv(+ni: Cliops.Ni, +f: O.Fmt, +args: List<&2, String>) -> IO(Cmd.Out):
  IO.bind(Cmd.Out, Cmd.Out, run2(ni, with_json(args)), o => converted(f, shape_key(args), o))

def run_fmt(+ni: Cliops.Ni, +f: O.Fmt, +args: List<&2, String>) -> IO(Cmd.Out):
  match f:
    case O.FText{}:
      run2(ni, args)
    case _:
      run_conv(ni, f, args)

# `auto` and the dashboard take their own options (--format included).
def is_own(+v: String) -> Bool:
  String.eq(v, "auto") || String.eq(v, "tui") || String.eq(v, "watch")

def with_fmt_name(m: Maybe<&2, String>, +args: List<&2, String>) -> List<&2, String>:
  match m:
    case None{}:
      args
    case Some{n}:
      List.append(&2, String, args, ["--format", n])

def named.of(+n: String, m: Maybe<&2, O.Fmt>) -> Result<&2, &2, String, O.Fmt>:
  match m:
    case Some{f}:
      Done{f}
    case None{}:
      Fail{n}

def named(m: Maybe<&2, String>) -> Result<&2, &2, String, O.Fmt>:
  match m:
    case None{}:
      Done{O.FText{}}
    case Some{+n}:
      named.of(n, O.of_name(n))

def forced(force: Maybe<&2, O.Fmt>, m: Maybe<&2, String>) -> Result<&2, &2, String, O.Fmt>:
  match force:
    case Some{f}:
      Done{f}
    case None{}:
      named(m)

def exec_own(+g: Gf.G) -> IO(Cmd.Out):
  run2(ni_of(g), with_fmt_name(g_fmt(g), g_rest(g)))

def exec3(+g: Gf.G, r: Result<&2, &2, String, O.Fmt>) -> IO(Cmd.Out):
  match r:
    case Fail{n}:
      IO.pure(Cmd.Out, fmt_bad(n))
    case Done{f}:
      run_fmt(ni_of(g), f, g_rest(g))

def exec2b(own: Bool, +g: Gf.G, force: Maybe<&2, O.Fmt>) -> IO(Cmd.Out):
  match own:
    case True{}:
      exec_own(g)
    case False{}:
      exec3(g, forced(force, g_fmt(g)))

def exec2a(ok: Bool, +g: Gf.G, force: Maybe<&2, O.Fmt>) -> IO(Cmd.Out):
  match ok:
    case True{}:
      exec2b(is_own(Args.verb_of(word0(g_rest(g)))), g, force)
    case False{}:
      IO.pure(Cmd.Out, usage_out(g_err(g)))

def exec2(+g: Gf.G, force: Maybe<&2, O.Fmt>) -> IO(Cmd.Out):
  exec2a(String.is_empty(g_err(g)), g, force)

def exec_line2(own: Bool, +args: List<&2, String>, force: Maybe<&2, O.Fmt>) -> IO(Cmd.Out):
  match own:
    case True{}:
      run2(Cliops.Ni{False{}, False{}}, args)
    case False{}:
      exec2(Gf.split(keeps_format(Args.verb_of(word0(args)), word1(args)), args), force)

# Run a command line (the words after the program name). `force` fixes the
# output format (the rpc loop asks for json); without it `--format` decides.
# A line that starts with `auto`, `tui` or `watch` is passed on untouched.
def exec_line(+args: List<&2, String>, force: Maybe<&2, O.Fmt>) -> IO(Cmd.Out):
  exec_line2(is_own(first_verb(args)), args, force)

# The command for `IO.args` (its head is the program name).
def run(ts: List<String>) -> IO(Cmd.Out):
  exec_line(tail_of(ts), None{})
