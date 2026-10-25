import Base

# Files for the credential and roster stores. Base has no rename, chmod,
# unlink, readdir or mkdir, so those run /bin tools through Process.run
# (absolute path, literal argv, no shell). Failures are `(code, message)`
# like Base's own effects.

def Res(-A: Type) -> Type:
  Result<&1, &1, U32 & String, A>

def proc.timeout() -> U32:
  10000

def proc.max() -> U32:
  1048576

def tool.status(ok: Bool, status: U32, out: String, err: String) -> Res(String):
  match ok:
    case True{}:
      Done{out}
    case False{}:
      Fail{(status, err)}

# Run a tool; Done{stdout} on exit status 0, else Fail{(status, stderr)}.
def tool.out(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Res(String):
  match r:
    case Fail{e}:
      Fail{e}
    case Done{(+status, (out, err))}:
      tool.status(U32.is_eq(status, 0), status, out, err)

def tool.unit(r: Res(String)) -> Res(Unit):
  match r:
    case Fail{e}:
      Fail{e}
    case Done{out}:
      Done{Unit{}}

def tool(program: String, args: List<String>) -> IO(Res(String)):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, Res(String),
    Process.run(program, args, "", proc.max(), proc.timeout()),
    r => IO.pure(Res(String), tool.out(r)))

def tool_unit(program: String, args: List<String>) -> IO(Res(Unit)):
  IO.bind(Res(String), Res(Unit), tool(program, args), r => IO.pure(Res(Unit), tool.unit(r)))

# Run `next` only when the previous step worked.
def then(r: Res(Unit), next: IO(Res(Unit))) -> IO(Res(Unit)):
  match r:
    case Fail{e}:
      IO.pure(Res(Unit), Fail{e})
    case Done{u}:
      next

# ---- read ----------------------------------------------------------------------

def read.done(fr: File & Res(String)) -> IO(Res(String)):
  (f, r) = fr
  IO.bind(Unit, Res(String), File.close(f), u => IO.pure(Res(String), r))

def read.sized2(f: File, r: Res(U32)) -> IO(Res(String)):
  match r:
    case Fail{e}:
      IO.bind(Unit, Res(String), File.close(f), u => IO.pure(Res(String), Fail{e}))
    case Done{n}:
      IO.bind(File & Res(String), Res(String), File.read(f, n), read.done)

def read.sized(fr: File & Res(U32)) -> IO(Res(String)):
  (f, r) = fr
  read.sized2(f, r)

def read.open(r: Res(File)) -> IO(Res(String)):
  match r:
    case Fail{e}:
      IO.pure(Res(String), Fail{e})
    case Done{f}:
      IO.bind(File & Res(U32), Res(String), File.size(f), read.sized)

# The whole file as text. Fail{(errno, message)} when it cannot be read.
def read_file(path: String) -> IO(Res(String)):
  IO.bind(Res(File), Res(String), File.open(path, "r"), read.open)

# ---- exists, list ----------------------------------------------------------------

def exists.of(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> Bool:
  match r:
    case Fail{e}:
      False{}
    case Done{(+status, rest)}:
      U32.is_eq(status, 0)

# Does the path exist (a file, directory or the target of a symlink)?
def exists(path: String) -> IO(Bool):
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, Bool,
    Process.run("/bin/test", ["-e", path], "", proc.max(), proc.timeout()),
    r => IO.pure(Bool, exists.of(r)))

def names.keep(empty: Bool, h: String, rest: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      rest
    case False{}:
      h <> rest

def names(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      []
    case Con{+h, t}:
      names.keep(String.is_empty(h), h, names(t))

def list.of(r: Res(String)) -> Res(List<&2, String>):
  match r:
    case Fail{e}:
      Fail{e}
    case Done{out}:
      Done{names(String.lines(out))}

# Entry names of a directory (hidden ones included, `.` and `..` not),
# in `ls` order. A name holding a newline is not representable.
def list_dir(path: String) -> IO(Res(List<&2, String>)):
  IO.bind(Res(String), Res(List<&2, String>), tool("/bin/ls", ["-1A", "--", path]),
    r => IO.pure(Res(List<&2, String>), list.of(r)))

# ---- paths -------------------------------------------------------------------------

def sel.s(c: Bool, x: String, y: String) -> String:
  match c:
    case True{}:
      x
    case False{}:
      y

def slash.pick(hit: Bool, t: String, rest: String) -> String:
  match hit:
    case True{}:
      t
    case False{}:
      rest

# Drop through the first `/` (the input is a reversed path).
def slash.drop(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, +t}:
      slash.pick(Char.is_eq(c, '/'), t, slash.drop(t))

def dirname.fin(s: String, absolute: Bool) -> String:
  match s:
    case SNil{}:
      sel.s(absolute, "/", ".")
    case _:
      s

# Everything before the last `/`: "a/b/c" is "a/b", "/x" is "/", "x" is ".".
def dirname(+p: String) -> String:
  dirname.fin(String.reverse(slash.drop(String.reverse(p))), String.starts_with(p, "/"))


# ---- stdin -------------------------------------------------------------------------------

def read.stdin(r: Res(File)) -> IO(Res(String)):
  match r:
    case Fail{e}:
      IO.pure(Res(String), Fail{e})
    case Done{f}:
      IO.bind(File & Res(String), Res(String), File.read(f, 1048576), read.done)

# What is on standard input, up to 1 MiB, in one read: "" at end of file. The
# CLI reads stdin once (a token, a confirmation), so one read is enough.
def read_stdin() -> IO(Res(String)):
  IO.bind(Res(File), Res(String), File.open("/dev/stdin", "r"), read.stdin)
