import Base
import ./fmt/out.bend as O

# The command line of `cswap rpc [--format json|toon|yaml]` and
# `cswap serve --socket PATH [--format json|toon|yaml]`. Pure.

type Plan is Data:
  PRpc{fmt: O.Fmt}
  PServe{path: String, fmt: O.Fmt}
  PBad{msg: String}

type A is Data:
  A{fmt: Maybe<&2, String>, socket: Maybe<&2, String>, err: String, want: String}

def err(+a: A, msg: String) -> A:
  match a:
    case A{fmt, socket, e, w}:
      A{fmt, socket, Bool.pick(String, String.is_empty(e), msg, e), ""}

def got(+a: A, +v: String) -> A:
  match a:
    case A{fmt, socket, e, w}:
      Bool.pick(A, String.eq(w, "--format"), A{Some{v}, socket, e, ""}, A{fmt, Some{v}, e, ""})

def want(+a: A, +flag: String) -> A:
  match a:
    case A{fmt, socket, e, w}:
      A{fmt, socket, e, flag}

def pending(+a: A) -> Bool:
  match a:
    case A{fmt, socket, e, w}:
      Bool.not(String.is_empty(w))

def sel.a(c: Bool, +x: A, +y: A) -> A:
  match c:
    case True{}:
      x
    case False{}:
      y

def free(+h: String, +a: A) -> A:
  sel.a(String.eq(h, "--format") || String.eq(h, "--socket"), want(a, h),
  sel.a(String.starts_with(h, "--format="), got(want(a, "--format"), String.drop(h, 9n)),
  sel.a(String.starts_with(h, "--socket="), got(want(a, "--socket"), String.drop(h, 9n)),
  err(a, "unrecognized arguments: " ++ h))))

def step(+h: String, +a: A) -> A:
  sel.a(pending(a), got(a, h), free(h, a))

def go(args: List<&2, String>, +a: A) -> A:
  match args:
    case Nil{}:
      a
    case Con{h, t}:
      go(t, step(h, a))

def end(+a: A) -> A:
  match a:
    case A{fmt, socket, e, w}:
      Bool.pick(A, String.is_empty(w), a, err(a, "argument " ++ w ++ ": expected one argument"))

def fmt_of2(m: Maybe<&2, O.Fmt>, +name: String) -> Result<&2, &2, String, O.Fmt>:
  match m:
    case Some{O.FText{}}:
      Fail{"argument --format: invalid choice: '" ++ name ++ "' (choose from 'json', 'toon', 'yaml')"}
    case Some{O.FCsv{}}:
      Fail{"argument --format: invalid choice: '" ++ name ++ "' (choose from 'json', 'toon', 'yaml')"}
    case Some{f}:
      Done{f}
    case None{}:
      Fail{"argument --format: invalid choice: '" ++ name ++ "' (choose from 'json', 'toon', 'yaml')"}

def fmt_of(m: Maybe<&2, String>) -> Result<&2, &2, String, O.Fmt>:
  match m:
    case None{}:
      Done{O.FJson{}}
    case Some{+n}:
      fmt_of2(O.of_name(n), n)

def plan4(serve: Bool, +f: O.Fmt, socket: Maybe<&2, String>) -> Plan:
  match serve socket:
    case True{} Some{p}:
      PServe{p, f}
    case True{} None{}:
      PBad{"the following arguments are required: --socket"}
    case False{} _:
      PRpc{f}

def plan3(+verb: String, r: Result<&2, &2, String, O.Fmt>, socket: Maybe<&2, String>) -> Plan:
  match r:
    case Fail{m}:
      PBad{m}
    case Done{f}:
      plan4(String.eq(verb, "serve"), f, socket)

def plan2(+verb: String, +a: A) -> Plan:
  match a:
    case A{fmt, socket, e, w}:
      Bool.pick(Plan, String.is_empty(e), plan3(verb, fmt_of(fmt), socket), PBad{e})

# `verb` is rpc or serve; `args` the words after it.
def plan(+verb: String, args: List<&2, String>) -> Plan:
  plan2(verb, end(go(args, A{None{}, None{}, "", ""})))
