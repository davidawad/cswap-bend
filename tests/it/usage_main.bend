import Base
import ../../src/fs.bend as Fs
import ../../src/usage.bend as Usage
import ../../src/json.bend as Json
import ../../src/usage/cred.bend as UCred
import ../../src/usage/gate.bend as UGate

# A CLI over usage for tests/usage_it.sh:
#   usage-it fetch CREDFILE active|inactive | refresh CREDFILE
#   usage-it fetchg CREDFILE active|inactive SLOT EMAIL DIR | gate CREDFILE SLOT EMAIL DIR
# Prints key=value lines: error, retry, struck, usage, credential.

def or.none(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      "none"
    case Some{s}:
      s

def or.nat(m: Maybe<&2, U32>) -> String:
  match m:
    case None{}:
      "none"
    case Some{n}:
      U32.show(n)

def yes(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      "no"
    case Some{s}:
      "yes"

def show.outcome(o: Usage.Outcome, c: Maybe<&2, String>) -> String:
  match o:
    case Usage.Outcome{usage, error, retry, struck}:
      "error=" ++ or.none(error) ++ "\nretry=" ++ or.nat(retry) ++ "\nstruck=" ++ yes(struck)
        ++ "\nusage=" ++ Json.emit(usage) ++ "\ncredential=" ++ or.none(c)

def show.fetched(f: Usage.Fetched) -> String:
  match f:
    case Usage.Fetched{o, c}:
      show.outcome(o, c)

def show.refresh(r: Result<&2, &2, String, String>) -> String:
  match r:
    case Fail{e}:
      "error=" ++ e
    case Done{c}:
      "credential=" ++ c

def active.of(+s: String) -> Bool:
  String.eq(s, "active")

def with.fetch(active: Bool, cred: String) -> IO(Unit):
  IO.bind(Usage.Fetched, Unit, Usage.fetch_usage(cred, active), f => IO.print(show.fetched(f)))

def with.refresh(cred: String) -> IO(Unit):
  IO.bind(Result<&2, &2, String, String>, Unit, UCred.refresh(cred), r => IO.print(show.refresh(r)))

def run.cmd(is_fetch: Bool, mode: String, cred: String) -> IO(Unit):
  match is_fetch:
    case True{}:
      with.fetch(active.of(mode), cred)
    case False{}:
      with.refresh(cred)

def run.read(is_fetch: Bool, mode: String, r: Fs.Res(String)) -> IO(Unit):
  IO.bind(String, Unit, IO.pass(String, r), cred => run.cmd(is_fetch, mode, cred))

def run.file(+cmd: String, mode: String, path: String) -> IO(Unit):
  IO.bind(Fs.Res(String), Unit, Fs.read_file(path), r => run.read(String.eq(cmd, "fetch"), mode, r))

def show.gated(g: UGate.Gated) -> String:
  match g:
    case UGate.Gated{c, e, consumed, acct}:
      "error=" ++ or.none(e) ++ "\ncredential=" ++ or.none(c) ++ "\nconsumed=" ++ yes(consumed)

def g.fetch(active: Bool, slot: String, email: String, dir: String, cred: String) -> IO(Unit):
  IO.bind(Usage.Fetched, Unit, Usage.fetch_usage_gated(cred, active, slot, email, dir), f => IO.print(show.fetched(f)))

def g.gate(slot: String, email: String, dir: String, cred: String) -> IO(Unit):
  IO.bind(UGate.Gated, Unit, UGate.refresh_gated(slot, email, cred, dir), g => IO.print(show.gated(g)))

def g.pick(is_fetch: Bool, mode: String, slot: String, email: String, dir: String, cred: String) -> IO(Unit):
  match is_fetch:
    case True{}:
      g.fetch(active.of(mode), slot, email, dir, cred)
    case False{}:
      g.gate(slot, email, dir, cred)

def g.run(is_fetch: Bool, mode: String, slot: String, email: String, dir: String, r: Fs.Res(String)) -> IO(Unit):
  IO.bind(String, Unit, IO.pass(String, r), cred => g.pick(is_fetch, mode, slot, email, dir, cred))

def g.file(+cmd: String, mode: String, slot: String, email: String, dir: String, path: String) -> IO(Unit):
  IO.bind(Fs.Res(String), Unit, Fs.read_file(path), r => g.run(String.eq(cmd, "fetchg"), mode, slot, email, dir, r))

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{cmd, Con{path, Con{mode, Con{slot, Con{email, Con{dir, Nil{}}}}}}}}:
      g.file(cmd, mode, slot, email, dir, path)
    case Con{prog, Con{cmd, Con{path, Con{slot, Con{email, Con{dir, Nil{}}}}}}}:
      g.file(cmd, "inactive", slot, email, dir, path)
    case Con{prog, Con{cmd, Con{path, Con{mode, Nil{}}}}}:
      run.file(cmd, mode, path)
    case Con{prog, Con{cmd, Con{path, Nil{}}}}:
      run.file(cmd, "inactive", path)
    case _:
      IO.die(Unit, 2, "usage")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
