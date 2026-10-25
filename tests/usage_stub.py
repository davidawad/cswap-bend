"""A tiny stub HTTP server for tests/usage_it.sh.

usage: usage_stub.py ROUTES.json LOG PORTFILE

ROUTES.json is a list of {method, path, token, responses: [{status, headers,
body}]}. A request matches on method, path and bearer token (token "" matches
a request without one). An optional "rt" also matches the refresh_token
of the request body. Matching routes answer their responses in order, the
last one repeating. Anything else gets 599. Every request is appended to LOG as
one line: METHOD PATH tok=.. beta=.. ver=.. ct=.. ua=.. body=<sorted compact
JSON or ->. Fake tokens only.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

routes = json.load(open(sys.argv[1]))
log_path = sys.argv[2]
counts = {}


def rt_of(raw):
    try:
        return json.loads(raw).get("refresh_token")
    except ValueError:
        return None


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def handle_any(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n).decode() if n else ""
        auth = self.headers.get("Authorization", "")
        tok = auth[len("Bearer "):] if auth.startswith("Bearer ") else ""
        try:
            body = json.dumps(json.loads(raw), sort_keys=True, separators=(",", ":")) if raw else "-"
        except ValueError:
            body = "RAW:" + raw
        line = "%s %s tok=%s beta=%s ver=%s ct=%s ua=%s body=%s\n" % (
            self.command, self.path, tok or "-",
            self.headers.get("anthropic-beta", "-"),
            self.headers.get("anthropic-version", "-"),
            self.headers.get("Content-Type", "-"),
            self.headers.get("User-Agent", "-"), body)
        with open(log_path, "a") as f:
            f.write(line)
        for i, r in enumerate(routes):
            if r["method"] == self.command and r["path"] == self.path and r["token"] == tok and ("rt" not in r or rt_of(raw) == r["rt"]):
                k = counts.get(i, 0)
                counts[i] = k + 1
                resp = r["responses"][min(k, len(r["responses"]) - 1)]
                break
        else:
            resp = {"status": 599, "headers": {}, "body": {"error": "unstubbed"}}
        data = json.dumps(resp["body"]).encode()
        self.send_response(resp["status"])
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        for k, v in resp.get("headers", {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    do_GET = handle_any
    do_POST = handle_any


srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
open(sys.argv[3], "w").write(str(srv.server_address[1]))
srv.serve_forever()
