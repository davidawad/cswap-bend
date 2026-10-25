import Base
import ../fs.bend as Fs

# ---- write ---------------------------------------------------------------------

def create.done(r: Fs.Res(File)) -> IO(Fs.Res(Unit)):
  match r:
    case Fail{e}:
      IO.pure(Fs.Res(Unit), Fail{e})
    case Done{f}:
      IO.bind(Unit, Fs.Res(Unit), File.close(f), u => IO.pure(Fs.Res(Unit), Done{Unit{}}))

# Create an empty file (a no-op on an existing one).
def create(path: String) -> IO(Fs.Res(Unit)):
  IO.bind(Fs.Res(File), Fs.Res(Unit), File.open(path, "a"), create.done)

def put.close(fr: File & Fs.Res(Unit)) -> IO(Fs.Res(Unit)):
  (f, r) = fr
  IO.bind(Unit, Fs.Res(Unit), File.close(f), u => IO.pure(Fs.Res(Unit), r))

def put.write(data: String, r: Fs.Res(File)) -> IO(Fs.Res(Unit)):
  match r:
    case Fail{e}:
      IO.pure(Fs.Res(Unit), Fail{e})
    case Done{f}:
      IO.bind(File & Fs.Res(Unit), Fs.Res(Unit), File.write(f, data), put.close)

# Truncate and write `data` (the file keeps its mode if it exists).
def put(path: String, data: String) -> IO(Fs.Res(Unit)):
  IO.bind(Fs.Res(File), Fs.Res(Unit), File.open(path, "w"), r => put.write(data, r))

def chmod(mode: String, path: String) -> IO(Fs.Res(Unit)):
  Fs.tool_unit("/bin/chmod", ["--", mode, path])

def rename(src: String, dst: String) -> IO(Fs.Res(Unit)):
  Fs.tool_unit("/bin/mv", ["-f", "--", src, dst])

# Delete a file; a missing file is not an error.
def remove(path: String) -> IO(Fs.Res(Unit)):
  Fs.tool_unit("/bin/rm", ["-f", "--", path])

def mkdir_p(path: String) -> IO(Fs.Res(Unit)):
  Fs.tool_unit("/bin/mkdir", ["-p", "--", path])

def publish.fail(r: Fs.Res(Unit), +tmp: String) -> IO(Fs.Res(Unit)):
  match r:
    case Done{u}:
      IO.pure(Fs.Res(Unit), Done{u})
    case Fail{e}:
      IO.bind(Fs.Res(Unit), Fs.Res(Unit), remove(tmp), c => IO.pure(Fs.Res(Unit), Fail{e}))

def publish.mv(r: Fs.Res(Unit), +tmp: String, +path: String) -> IO(Fs.Res(Unit)):
  match r:
    case Fail{e}:
      publish.fail(Fail{e}, tmp)
    case Done{u}:
      IO.bind(Fs.Res(Unit), Fs.Res(Unit), rename(tmp, path), m => publish.fail(m, tmp))

def publish.put(r: Fs.Res(Unit), +tmp: String, +path: String, +data: String) -> IO(Fs.Res(Unit)):
  match r:
    case Fail{e}:
      publish.fail(Fail{e}, tmp)
    case Done{u}:
      IO.bind(Fs.Res(Unit), Fs.Res(Unit), put(tmp, data), w => publish.mv(w, tmp, path))

def publish.chmod(r: Fs.Res(Unit), +tmp: String, +path: String, +data: String, +mode: String) -> IO(Fs.Res(Unit)):
  match r:
    case Fail{e}:
      publish.fail(Fail{e}, tmp)
    case Done{u}:
      IO.bind(Fs.Res(Unit), Fs.Res(Unit), chmod(mode, tmp), c => publish.put(c, tmp, path, data))

def publish.create(+tmp: String, +path: String, +data: String, +mode: String) -> IO(Fs.Res(Unit)):
  IO.bind(Fs.Res(Unit), Fs.Res(Unit), create(tmp), c => publish.chmod(c, tmp, path, data, mode))

def publish.tmp(r: Fs.Res(U32), +path: String, +data: String, +mode: String) -> IO(Fs.Res(Unit)):
  match r:
    case Fail{e}:
      IO.pure(Fs.Res(Unit), Fail{e})
    case Done{n}:
      publish.create(path ++ ".tmp-" ++ U32.show(n), path, data, mode)

# Write `data` to a sibling temp file, give it `mode` (an octal string such
# as "600") while it is still empty, then rename it over `path`. The
# secret is never on disk at another mode, and readers see the old file or
# the new one, never half of it.
def write_atomic(path: String, data: String, mode: String) -> IO(Fs.Res(Unit)):
  IO.bind(Fs.Res(U32), Fs.Res(Unit), IO.random_u32(), r => publish.tmp(r, path, data, mode))

# ---- append ---------------------------------------------------------------------------

# Append `data` to a file, creating it (a log line at a time).
def append(path: String, data: String) -> IO(Fs.Res(Unit)):
  IO.bind(Fs.Res(File), Fs.Res(Unit), File.open(path, "a"), r => put.write(data, r))
