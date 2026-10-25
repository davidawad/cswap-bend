# cswap-bend API: `cswap rpc` and `cswap serve`

Two verbs let a program drive cswap without parsing human text or starting a
process per command.

```sh
cswap rpc   [--format json|toon|yaml]                 # requests on stdin, responses on stdout
cswap serve --socket PATH [--format json|toon|yaml]   # the same, on a unix socket
```

The protocol is the same on both. A request is one document, a response is one
document, in order. Every command runs in the server process with the output
format forced to json, so a `result` is exactly what `cswap <command> --format
json` prints, as a value.

## Framing

| `--format` | A message is | A response ends with |
|---|---|---|
| `json` (default) | one line of JSON (CRLF is fine); blank lines are skipped | a newline |
| `yaml`, `toon` | a block of lines ended by a blank line (YAML and TOON documents never hold a blank line: multi-line strings are quoted with `\n`) | a blank line |

A last message without its newline (or blank line) is still answered at end of
input. `rpc` exits 0 at end of input. `serve` runs until SIGTERM, SIGINT or
SIGHUP, which remove the socket file and exit 0.

## Request

```json
{"id": 1, "cmd": "list", "args": [], "opts": {}}
```

| Field | Meaning |
|---|---|
| `id` | anything; echoed in the response (`null` when missing) |
| `cmd` | the command: `list` (`ls`), `status`, `switch`, `add`, `add-token`, `remove` (`rm`), `import-usage`, `config`, `profile`, `upgrade`, `help`, `version` |
| `args` | positional words, strings or numbers (`["get", "autoswitch.threshold"]`, `["set", "autoswitch.threshold", 85]`) |
| `opts` | options, named without the dashes: `true` is the bare flag (`"force": true` is `--force`), a string or number is the value (`"strategy": "best"` is `--strategy best`), `false` and `null` are left out |

The command line built is `cmd args... opts... --no-input`, so no command ever
reads standard input or the connection:

* `remove` needs `"yes": true`, else it answers an error saying so.
* `add-token` needs the token in `args` (not `-`); an occupied slot is an error.
* `config import` / `profile import` take the document inline: `"opts":
  {"data": "<text>", "format": "yaml"}` (`format`: json, yaml, toon, csv). For
  these two commands `format` names the input; every response is json anyway.

Not served: `auto` (code `not_allowed`: the poller is the one decider, run
`cswap auto`), `tui` and `watch` (`not_allowed`: interactive), `menubar`,
`rpc`, `serve` and anything else (`unknown_command`).

## Response

Success:

```json
{"id": 1, "ok": true, "result": { ... the command's json document ... }}
```

A command with no JSON document of its own (`add`, `add-token`, `remove`,
`import-usage`, `config set`, `help`, ...) answers `{"schemaVersion": 1,
"message": "<its text>"}`.

Failure:

```json
{"id": 1, "ok": false, "error": {"code": "ConfigError", "message": "unknown setting 'x'", "exit": 1}}
```

| `code` | When |
|---|---|
| `bad_request` | the message is not a document, or lacks `cmd`, or `args` / `opts` have the wrong shape |
| `not_allowed`, `unknown_command` | see above |
| `usage` | the command line was refused (`exit` 2): a flag the command lacks, a missing argument |
| `ConfigError`, `ValidationError`, `AccountNotFoundError`, ... | the command failed and said why in its JSON error envelope (`exit` 1) |
| `Error` | the command failed with a plain message (`exit` 1) |

`exit` is the exit status the CLI would have had (2 for a request that was not
run).

## Examples

```
$ printf '%s\n' '{"id":1,"cmd":"config","args":["get","autoswitch.threshold"]}' | cswap rpc
{"id":1,"ok":true,"result":{"schemaVersion":1,"key":"autoswitch.threshold","value":90.0,"isSet":false}}
```

```
$ printf '%s\n' '{"id":"a","cmd":"remove","args":["3"]}' '{"id":"b","cmd":"remove","args":["3"],"opts":{"yes":true}}' | cswap rpc
{"id":"a","ok":false,"error":{"code":"Error","message":"removing Account-3 needs confirmation; pass --yes","exit":1}}
{"id":"b","ok":true,"result":{"schemaVersion":1,"message":"Removed Account-3 (c@example.test)"}}
```

```
$ printf '%s\n' '{"id":7,"cmd":"auto"}' | cswap rpc
{"id":7,"ok":false,"error":{"code":"not_allowed","message":"auto is not available over rpc: the poller is the one decider (run `cswap auto`)","exit":2}}
```

Import a settings document without a file:

```
{"id":1,"cmd":"config","args":["import"],"opts":{"data":"autoswitch:\n  threshold: 85\n","format":"yaml"}}
{"id":1,"ok":true,"result":{"schemaVersion":1,"source":"(data)","format":"yaml","keys":["autoswitch"]}}
```

YAML messages (`cswap rpc --format yaml`; the blank line ends the message):

```
id: 1
cmd: config
args:
  - get
  - autoswitch.threshold

```

```
id: 1
ok: true
result:
  schemaVersion: 1
  key: autoswitch.threshold
  value: 90.0
  isSet: false

```

A socket client (Python):

```python
import json, socket
c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
c.connect("/path/to/cswap.sock")
f = c.makefile("rw", newline="\n")
f.write(json.dumps({"id": 1, "cmd": "list"}) + "\n"); f.flush()
print(json.loads(f.readline())["result"]["accounts"])
```

`nc -U /path/to/cswap.sock` works the same way.

## Notes

* `serve` takes one connection at a time; a second client waits in the listen
  queue until the first closes. A client that closes (or half-closes) its end
  is answered for what it already sent, then the next client is accepted.
* The socket is created with mode 0600 (umask 0177 around `bind`, then
  `chmod`). A stale socket file at the path is replaced; any other file there
  is an error (exit 1) and is left alone. There is no TCP listener.
* The listen call is a foreign effect (`src/effs/usock.c`); the JavaScript lane
  answers ENOSYS, so `serve` needs the native build.
* `rpc` and `serve` do not coordinate with a running `cswap auto`: both use the
  same locks the CLI does, so a `switch` over rpc is as safe as one at the
  prompt.
* TOON writes numbers in canonical form (`90.0` becomes `90`); json and yaml
  keep the text the command printed.
