import Base
import ./cmd.bend as Cmd
import ./fs.bend as Fs
import ./frame.bend as Fr
import ./rpc.bend as Rpc
import ./fmt/out.bend as O

# `cswap rpc` reads messages from standard input and writes the responses to
# standard output; `cswap serve --socket PATH` does the same for one client at
# a time on a unix socket (mode 0600, no TCP). Both end the same way: rpc at
# end of input, serve on SIGTERM / SIGINT / SIGHUP (the socket file is removed
# by the handler in effs/usock.c). A client that closes its end is served what
# it already sent, then the next client is accepted.

# A foreign effect: a non-blocking listening unix socket at `path` (mode 0600);
# a stale socket file there is replaced, any other file is an error. The
# Listener takes TCP.accept, and the sockets it accepts take TCP.recv/send.
def Usock.listen(path: String) -> IO(Result<&1, &1, U32 & String, Listener>):
  import "./effs/usock.c"
  import "./effs/usock.js"

def chunk() -> U32:
  65536

# ---- standard input ----------------------------------------------------------------

type SP is Type:
  SRead{f: File, buf: String}
  SFrames{f: File, buf: String}
  SHandle{f: File, msg: String, rest: String}
  STail{f: File, buf: String}
  SDone{f: File}

def s_chunk(has: Bool, f: File, buf: String, c: String) -> SP:
  match has:
    case True{}:
      SFrames{f, buf ++ c}
    case False{}:
      STail{f, buf}

def s_read(res: Fs.Res(String), f: File, buf: String) -> SP:
  match res:
    case Fail{e}:
      SDone{f}
    case Done{+c}:
      s_chunk(Bool.not(String.is_empty(c)), f, buf, c)

def after_read(r: File & Fs.Res(String), buf: String) -> SP:
  (f, res) = r
  s_read(res, f, buf)

def s_cut(m: Maybe<&2, Fr.Cut>, f: File, buf: String) -> SP:
  match m:
    case None{}:
      SRead{f, buf}
    case Some{Fr.Cut{msg, rest}}:
      SHandle{f, msg, rest}

def s_tail(blank: Bool, f: File, buf: String) -> SP:
  match blank:
    case True{}:
      SDone{f}
    case False{}:
      SHandle{f, buf, ""}

@unsafe def stdin_pump(p: SP, +fmt: O.Fmt) -> IO(Unit):
  match p:
    case SRead{f, buf}:
      IO.bind(File & Fs.Res(String), Unit, File.read(f, chunk()), r => stdin_pump(after_read(r, buf), fmt))
    case SFrames{f, +buf}:
      stdin_pump(s_cut(Fr.take(Rpc.is_block(fmt), buf), f, buf), fmt)
    case SHandle{f, msg, rest}:
      IO.bind(String, Unit, Rpc.handle(fmt, msg), resp => IO.bind(Unit, Unit, IO.write(resp), u => stdin_pump(SFrames{f, rest}, fmt)))
    case STail{f, +buf}:
      stdin_pump(s_tail(Fr.blank(buf), f, buf), fmt)
    case SDone{f}:
      File.close(f)

def rpc_start(r: Fs.Res(File), +fmt: O.Fmt) -> IO(Cmd.Out):
  match r:
    case Fail{e}:
      IO.pure(Cmd.Out, Cmd.Out{1, "", "cswap rpc: cannot read standard input\n"})
    case Done{f}:
      IO.bind(Unit, Cmd.Out, stdin_pump(SRead{f, ""}, fmt), u => IO.pure(Cmd.Out, Cmd.silent()))

# Serve the messages on standard input; ends at end of input.
def rpc(+fmt: O.Fmt) -> IO(Cmd.Out):
  IO.bind(Fs.Res(File), Cmd.Out, File.open("/dev/stdin", "r"), r => rpc_start(r, fmt))

# ---- one connection --------------------------------------------------------------------

type CP is Type:
  CRecv{s: Socket, buf: String}
  CFrames{s: Socket, buf: String}
  CHandle{s: Socket, msg: String, rest: String}
  CReply{s: Socket, resp: String, rest: String}
  CSend{s: Socket, resp: String, rest: String}
  CTail{s: Socket, buf: String}
  CClose{s: Socket}

def c_recv(res: Result<&1, &1, U32 & String, Maybe<&1, String>>, s: Socket, buf: String) -> CP:
  match res:
    case Fail{e}:
      CClose{s}
    case Done{None{}}:
      CTail{s, buf}
    case Done{Some{c}}:
      CFrames{s, buf ++ c}

def after_recv(r: Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>, buf: String) -> CP:
  (s, res) = r
  c_recv(res, s, buf)

def c_sent(res: Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, s: Socket, rest: String) -> CP:
  match res:
    case Fail{e}:
      CClose{s}
    case Done{u}:
      CFrames{s, rest}

def after_send(r: Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, rest: String) -> CP:
  (s, res) = r
  c_sent(res, s, rest)

def c_cut(m: Maybe<&2, Fr.Cut>, s: Socket, buf: String) -> CP:
  match m:
    case None{}:
      CRecv{s, buf}
    case Some{Fr.Cut{msg, rest}}:
      CHandle{s, msg, rest}

def c_tail(blank: Bool, s: Socket, buf: String) -> CP:
  match blank:
    case True{}:
      CClose{s}
    case False{}:
      CHandle{s, buf, ""}

def c_reply(empty: Bool, s: Socket, resp: String, rest: String) -> CP:
  match empty:
    case True{}:
      CFrames{s, rest}
    case False{}:
      CSend{s, resp, rest}

@unsafe def conn_pump(p: CP, +fmt: O.Fmt) -> IO(Unit):
  match p:
    case CRecv{s, buf}:
      IO.bind(Socket & Result<&1, &1, U32 & String, Maybe<&1, String>>, Unit, TCP.recv(s, chunk()), r => conn_pump(after_recv(r, buf), fmt))
    case CFrames{s, +buf}:
      conn_pump(c_cut(Fr.take(Rpc.is_block(fmt), buf), s, buf), fmt)
    case CHandle{s, msg, rest}:
      IO.bind(String, Unit, Rpc.handle(fmt, msg), resp => conn_pump(CReply{s, resp, rest}, fmt))
    case CReply{s, +resp, rest}:
      conn_pump(c_reply(String.is_empty(resp), s, resp, rest), fmt)
    case CSend{s, resp, rest}:
      IO.bind(Socket & Result<&1, &1, (U32 & String) & List<&2, U32>, Unit>, Unit, TCP.send(s, resp), r => conn_pump(after_send(r, rest), fmt))
    case CTail{s, +buf}:
      conn_pump(c_tail(Fr.blank(buf), s, buf), fmt)
    case CClose{s}:
      Socket.close(s)

# ---- the listener --------------------------------------------------------------------------

type AP is Type:
  AAcc{l: Listener}
  AConn{l: Listener, s: Socket}
  ARetry{l: Listener}

def a_got(res: Result<&1, &1, U32 & String, Socket>, l: Listener) -> AP:
  match res:
    case Fail{e}:
      ARetry{l}
    case Done{s}:
      AConn{l, s}

def after_accept(r: Listener & Result<&1, &1, U32 & String, Socket>) -> AP:
  (l, res) = r
  a_got(res, l)

@unsafe def accept_pump(p: AP, +fmt: O.Fmt) -> IO(Unit):
  match p:
    case AAcc{l}:
      IO.bind(Listener & Result<&1, &1, U32 & String, Socket>, Unit, TCP.accept(l), r => accept_pump(after_accept(r), fmt))
    case AConn{l, s}:
      IO.bind(Unit, Unit, conn_pump(CRecv{s, ""}, fmt), u => accept_pump(AAcc{l}, fmt))
    case ARetry{l}:
      IO.bind(Unit, Unit, IO.sleep(100), u => accept_pump(AAcc{l}, fmt))

def serve_start(r: Result<&1, &1, U32 & String, Listener>, +path: String, +fmt: O.Fmt) -> IO(Cmd.Out):
  match r:
    case Fail{(code, msg)}:
      IO.pure(Cmd.Out, Cmd.Out{1, "", "cswap serve: cannot listen on " ++ path ++ ": " ++ msg ++ "\n"})
    case Done{l}:
      IO.bind(Unit, Cmd.Out, accept_pump(AAcc{l}, fmt), u => IO.pure(Cmd.Out, Cmd.silent()))

# Serve clients on the unix socket at `path`, one at a time, until a signal.
def serve(+path: String, +fmt: O.Fmt) -> IO(Cmd.Out):
  IO.bind(Result<&1, &1, U32 & String, Listener>, Cmd.Out, Usock.listen(path), r => serve_start(r, path, fmt))
