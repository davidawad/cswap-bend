import Base
import ../src/usage.bend as Usage
import ../src/json.bend as Json
import ../src/http.bend as Http
import ../src/usage/text.bend as UText
import ../src/usage/norm.bend as UNorm
import ../src/usage/req.bend as UReq
import ../src/usage/cred.bend as UCred
import ../src/usage/gate.bend as UGate

# Ground equations for the pure parts of src/usage.bend.

def float_int() -> {UText.float("50") == Some{"50.0"} : Maybe<&2, String>}:
  {==}

def float_trim() -> {UText.float("05.50") == Some{"5.5"} : Maybe<&2, String>}:
  {==}

def float_neg() -> {UText.float("-3.25") == Some{"-3.25"} : Maybe<&2, String>}:
  {==}

def float_exp() -> {UText.float("1e3") == None{} : Maybe<&2, String>}:
  {==}

def div100_cents() -> {UText.div100("1234") == Some{"12.34"} : Maybe<&2, String>}:
  {==}

def div100_small() -> {UText.div100("5.5") == Some{"0.055"} : Maybe<&2, String>}:
  {==}

def div100_round() -> {UText.div100("1000.0") == Some{"10.0"} : Maybe<&2, String>}:
  {==}

def pct1_quarter() -> {UText.pct1("0.25") == Some{"25.0"} : Maybe<&2, String>}:
  {==}

def pct1_one() -> {UText.pct1("1.0") == Some{"100.0"} : Maybe<&2, String>}:
  {==}

def pct1_round() -> {UText.pct1("0.4256") == Some{"42.6"} : Maybe<&2, String>}:
  {==}

def pct1_int() -> {UText.pct1("1") == Some{"100.0"} : Maybe<&2, String>}:
  {==}

def pct1_bad() -> {UText.pct1("abc") == None{} : Maybe<&2, String>}:
  {==}

def now() -> U32:
  1792756800

def utc() -> U32:
  86400

def j(s: String) -> Json.Json:
  Json.unwrap(Json.parse(s))

# ---- header mapping --------------------------------------------------------

def hdr_both() -> {UText.usage_from_ratelimit_headers("HTTP/2 200\r\nanthropic-ratelimit-unified-5h-utilization: 0.25\r\nanthropic-ratelimit-unified-5h-reset: 1792764300\r\nAnthropic-Ratelimit-Unified-7d-Utilization: 0.5\r\nanthropic-ratelimit-unified-7d-reset: 1793034000\r\n") == Some{j("{\"five_hour\":{\"utilization\":25.0,\"resets_at\":\"2026-10-23T14:05:00+00:00\"},\"seven_day\":{\"utilization\":50.0,\"resets_at\":\"2026-10-26T17:00:00+00:00\"}}")} : Maybe<&2, Json.Json>}:
  {==}

def hdr_no_reset() -> {UText.usage_from_ratelimit_headers("anthropic-ratelimit-unified-5h-utilization: 1.0\r\n") == Some{j("{\"five_hour\":{\"utilization\":100.0}}")} : Maybe<&2, Json.Json>}:
  {==}

def hdr_none() -> {UText.usage_from_ratelimit_headers("HTTP/2 429\r\nretry-after: 30\r\n") == None{} : Maybe<&2, Json.Json>}:
  {==}

# ---- reset text ------------------------------------------------------------

def cd_hm() -> {UNorm.countdown(7500) == "2h 5m" : String}:
  {==}

def cd_dh() -> {UNorm.countdown(277200) == "3d 5h" : String}:
  {==}

def cd_m() -> {UNorm.countdown(600) == "10m" : String}:
  {==}

def cd_past() -> {UNorm.countdown(UNorm.remaining(1, 5)) == "0m" : String}:
  {==}

def clock_same_day() -> {UNorm.clock.text(1792764300, 1792756800, 86400) == "14:05" : String}:
  {==}

def clock_other_day() -> {UNorm.clock.text(1793034000, 1792756800, 86400) == "Oct 26 17:00" : String}:
  {==}

def clock_offset() -> {UNorm.clock.text(1792764300, 1792756800, 106200) == "19:35" : String}:
  {==}

# ---- build_usage_result ----------------------------------------------------

def build_windows() -> {UNorm.build_usage_result(j("{\"five_hour\":{\"utilization\":42.5,\"resets_at\":\"2026-10-23T14:05:00+00:00\"},\"seven_day\":{\"utilization\":10,\"resets_at\":null}}"), now(), utc()) == j("{\"five_hour\":{\"pct\":42.5,\"resets_at\":\"2026-10-23T14:05:00+00:00\",\"countdown\":\"2h 5m\",\"clock\":\"14:05\"},\"seven_day\":{\"pct\":10}}") : Json.Json}:
  {==}

def build_spend() -> {UNorm.build_usage_result(j("{\"extra_usage\":{\"is_enabled\":true,\"used_credits\":1234,\"monthly_limit\":5000,\"utilization\":24.68}}"), now(), utc()) == j("{\"spend\":{\"used\":12.34,\"limit\":50.0,\"pct\":24.68,\"currency\":\"USD\"}}") : Json.Json}:
  {==}

def build_spend_null_limit() -> {UNorm.build_usage_result(j("{\"five_hour\":{\"utilization\":1},\"extra_usage\":{\"is_enabled\":true,\"used_credits\":1234,\"monthly_limit\":null,\"utilization\":null}}"), now(), utc()) == j("{\"five_hour\":{\"pct\":1}}") : Json.Json}:
  {==}

def build_spend_disabled() -> {UNorm.build_usage_result(j("{\"extra_usage\":{\"is_enabled\":false,\"used_credits\":1,\"monthly_limit\":2,\"utilization\":3}}"), now(), utc()) == Json.JNull{} : Json.Json}:
  {==}

def build_scoped() -> {UNorm.build_usage_result(j("{\"limits\":[{\"scope\":{\"model\":{\"display_name\":\"Fable\"}},\"percent\":73,\"resets_at\":\"2026-10-26T17:00:00+00:00\"},{\"scope\":{\"model\":{\"display_name\":\"\"}},\"percent\":5},{\"scope\":{},\"percent\":6},{\"scope\":{\"model\":{\"display_name\":\"Opus\"}},\"percent\":\"x\"},{\"scope\":{\"model\":{\"display_name\":\"Opus\"}},\"percent\":2.5}]}"), now(), utc()) == j("{\"scoped\":[{\"name\":\"Fable\",\"pct\":73.0,\"resets_at\":\"2026-10-26T17:00:00+00:00\",\"countdown\":\"3d 5h\",\"clock\":\"Oct 26 17:00\"},{\"name\":\"Opus\",\"pct\":2.5}]}") : Json.Json}:
  {==}

def build_empty() -> {UNorm.build_usage_result(j("{}"), now(), utc()) == Json.JNull{} : Json.Json}:
  {==}

# ---- request text ----------------------------------------------------------

def usage_cfg() -> {UText.usage.config("FAKE-at") == "url = \"https://api.anthropic.com/api/oauth/usage\"\nrequest = \"GET\"\nsilent\nshow-error\ndump-header = -\nmax-time = \"5\"\nwrite-out = \"\\\\n%{http_code}\"\nheader = \"Authorization: Bearer FAKE-at\"\nheader = \"anthropic-beta: oauth-2025-04-20\"\nheader = \"User-Agent: claude-swap/1.0\"\n" : String}:
  {==}

def probe_body() -> {UText.probe.body() == "{\"model\": \"claude-haiku-5-5\", \"max_tokens\": 1, \"system\": [{\"type\": \"text\", \"text\": \"You are Claude Code, Anthropic's official CLI for Claude.\"}], \"messages\": [{\"role\": \"user\", \"content\": \".\"}]}" : String}:
  {==}

def refresh_body() -> {UText.refresh.body("FAKE-rt") == "{\"grant_type\": \"refresh_token\", \"refresh_token\": \"FAKE-rt\", \"client_id\": \"9d1c250a-e61b-44d9-88ed-5944d1962f5e\"}" : String}:
  {==}

# ---- error classification --------------------------------------------------

def retry_secs() -> {UReq.retry_after("HTTP/2 429\r\nRetry-After: 30\r\n") == Some{30} : Maybe<&2, U32>}:
  {==}

def retry_fraction() -> {UReq.retry_after("retry-after: 1.9\r\n") == Some{1} : Maybe<&2, U32>}:
  {==}

def retry_negative() -> {UReq.retry_after("retry-after: -5\r\n") == Some{0} : Maybe<&2, U32>}:
  {==}

def retry_date() -> {UReq.retry_after("retry-after: Wed, 21 Oct 2026 07:28:00 GMT\r\n") == None{} : Maybe<&2, U32>}:
  {==}

def retry_missing() -> {UReq.retry_after("HTTP/2 429\r\n") == None{} : Maybe<&2, U32>}:
  {==}

def scope_403() -> {UReq.scope_error(UReq.Err{"http-403", None{}, "{\"details\":{\"error_code\":\"oauth_scope_insufficient\"}}"}) == True{} : Bool}:
  {==}

def scope_403_text() -> {UReq.scope_error(UReq.Err{"http-403", None{}, "does not meet scope requirement user:profile"}) == True{} : Bool}:
  {==}

def scope_403_other() -> {UReq.scope_error(UReq.Err{"http-403", None{}, "forbidden"}) == False{} : Bool}:
  {==}

def scope_429() -> {UReq.scope_error(UReq.Err{"http-429", None{}, "oauth_scope_insufficient"}) == False{} : Bool}:
  {==}

def http_err() -> {UReq.http.err(Http.Reply{429, "HTTP/2 429\r\nretry-after: 30\r\n", "x"}) == UReq.Err{"http-429", Some{30}, "x"} : UReq.Err}:
  {==}

def probe_headers_429() -> {UReq.probe.result(Done{Http.Reply{429, "anthropic-ratelimit-unified-5h-utilization: 1.0\r\n", "{}"}}) == Done{j("{\"five_hour\":{\"utilization\":100.0}}")} : Result<&2, &2, UReq.Err, Json.Json>}:
  {==}

def probe_2xx_no_headers() -> {UReq.probe.result(Done{Http.Reply{200, "HTTP/2 200\r\n", "{}"}}) == Fail{UReq.Err{"bad-response", None{}, ""}} : Result<&2, &2, UReq.Err, Json.Json>}:
  {==}

def probe_5xx_no_headers() -> {UReq.probe.result(Done{Http.Reply{500, "retry-after: 7\r\n", "boom"}}) == Fail{UReq.Err{"http-500", Some{7}, "boom"}} : Result<&2, &2, UReq.Err, Json.Json>}:
  {==}

def probe_transport() -> {UReq.probe.result(Fail{"timeout"}) == Fail{UReq.Err{"timeout", None{}, ""}} : Result<&2, &2, UReq.Err, Json.Json>}:
  {==}

def usage_bad_json() -> {UReq.usage.result(Done{Http.Reply{200, "", "<html>"}}) == Fail{UReq.Err{"bad-response", None{}, ""}} : Result<&2, &2, UReq.Err, Json.Json>}:
  {==}

def usage_ok() -> {UReq.usage.result(Done{Http.Reply{200, "", "{\"a\":1}"}}) == Done{j("{\"a\":1}")} : Result<&2, &2, UReq.Err, Json.Json>}:
  {==}

def usage_non_object() -> {UReq.usage.result(Done{Http.Reply{200, "", "[1]"}}) == Fail{UReq.Err{"AttributeError", None{}, ""}} : Result<&2, &2, UReq.Err, Json.Json>}:
  {==}

def usage_500() -> {UReq.usage.result(Done{Http.Reply{500, "", "err"}}) == Fail{UReq.Err{"http-500", None{}, "err"}} : Result<&2, &2, UReq.Err, Json.Json>}:
  {==}

# ---- credential fields -----------------------------------------------------

def inf_setup() -> {UCred.inference_only(j("{\"scopes\":[\"user:inference\"]}")) == True{} : Bool}:
  {==}

def inf_full() -> {UCred.inference_only(j("{\"scopes\":[\"user:inference\",\"user:profile\"]}")) == False{} : Bool}:
  {==}

def inf_missing() -> {UCred.inference_only(j("{}")) == False{} : Bool}:
  {==}

def inf_empty() -> {UCred.inference_only(j("{\"scopes\":[]}")) == False{} : Bool}:
  {==}

def exp_past() -> {UCred.expired(j("{\"expiresAt\":1000}"), 1792756800) == True{} : Bool}:
  {==}

def exp_soon() -> {UCred.expired(j("{\"expiresAt\":1792757000000}"), 1792756800) == True{} : Bool}:
  {==}

def exp_later() -> {UCred.expired(j("{\"expiresAt\":1792757200000}"), 1792756800) == False{} : Bool}:
  {==}

def exp_missing() -> {UCred.expired(j("{}"), 1792756800) == False{} : Bool}:
  {==}

def exp_text() -> {UCred.expired(j("{\"expiresAt\":\"soon\"}"), 1792756800) == False{} : Bool}:
  {==}

def token_none() -> {UCred.access_token(UCred.oauth.of("{\"claudeAiOauth\":{\"accessToken\":\"\"}}")) == None{} : Maybe<&2, String>}:
  {==}

def oauth_not_object() -> {UCred.oauth.of("{\"claudeAiOauth\":[]}") == Json.JNull{} : Json.Json}:
  {==}

# ---- refresh grant ---------------------------------------------------------

def cred() -> String:
  "{\"claudeAiOauth\": {\"accessToken\": \"FAKE-old\", \"refreshToken\": \"FAKE-oldrt\", \"expiresAt\": 5}, \"k\": 1}"

def grant(st: U32, body: String) -> Result<&2, &2, String, String>:
  UCred.granted.cred(UCred.grant.result(Done{Http.Reply{st, "", body}}, j(cred()), UCred.oauth.of(cred()), now()))

def grant_ok() -> {grant(200, "{\"access_token\":\"FAKE-new\",\"refresh_token\":\"FAKE-newrt\",\"expires_in\":3600,\"scope\":\"user:profile  user:inference\"}") == Done{"{\"claudeAiOauth\": {\"accessToken\": \"FAKE-new\", \"refreshToken\": \"FAKE-newrt\", \"expiresAt\": 1792760400000, \"scopes\": [\"user:profile\", \"user:inference\"]}, \"k\": 1}"} : Result<&2, &2, String, String>}:
  {==}

def grant_keeps_rt() -> {grant(200, "{\"access_token\":\"FAKE-new\",\"expires_in\":60}") == Done{"{\"claudeAiOauth\": {\"accessToken\": \"FAKE-new\", \"refreshToken\": \"FAKE-oldrt\", \"expiresAt\": 1792756860000}, \"k\": 1}"} : Result<&2, &2, String, String>}:
  {==}

def grant_missing_field() -> {grant(200, "{\"access_token\":\"FAKE-new\"}") == Fail{"transient"} : Result<&2, &2, String, String>}:
  {==}

def grant_not_json() -> {grant(200, "oops") == Fail{"transient"} : Result<&2, &2, String, String>}:
  {==}

def grant_invalid_grant() -> {grant(400, "{\"error\":\"invalid_grant\"}") == Fail{"invalid_grant"} : Result<&2, &2, String, String>}:
  {==}

def grant_invalid_client() -> {grant(401, "{\"error\":\"invalid_client\"}") == Fail{"invalid_client"} : Result<&2, &2, String, String>}:
  {==}

def grant_403() -> {grant(403, "{\"error\":\"invalid_grant\"}") == Fail{"invalid_grant"} : Result<&2, &2, String, String>}:
  {==}

def grant_other_error() -> {grant(400, "{\"error\":\"invalid_request\"}") == Fail{"transient"} : Result<&2, &2, String, String>}:
  {==}

def grant_marker_in_detail() -> {grant(400, "{\"error\":{\"detail\":\"invalid_grant\"}}") == Fail{"transient"} : Result<&2, &2, String, String>}:
  {==}

def grant_500_marker() -> {grant(500, "{\"error\":\"invalid_grant\"}") == Fail{"transient"} : Result<&2, &2, String, String>}:
  {==}

def grant_transport() -> {UCred.granted.cred(UCred.grant.result(Fail{"timeout"}, j(cred()), UCred.oauth.of(cred()), now())) == Fail{"transient"} : Result<&2, &2, String, String>}:
  {==}

# ---- consume gate ----------------------------------------------------------

def fp_rt() -> {UGate.fp("{\"claudeAiOauth\":{\"accessToken\":\"a\",\"refreshToken\":\"r1\"}}") == "rt:r1" : String}:
  {==}

def fp_same_lineage() -> {UGate.fp("{\"claudeAiOauth\":{\"accessToken\":\"b\",\"refreshToken\":\"r1\"}}") == UGate.fp("{\"claudeAiOauth\":{\"accessToken\":\"a\",\"refreshToken\":\"r1\"}}") : String}:
  {==}

def fp_full() -> {UGate.fp("sk-ant-api03-FAKE") == "full:sk-ant-api03-FAKE" : String}:
  {==}

def adopt_fresher() -> {UGate.adopt("{\"claudeAiOauth\":{\"accessToken\":\"new\",\"expiresAt\":1792999999000}}", "{\"claudeAiOauth\":{\"accessToken\":\"old\"}}", 1792756800) == True{} : Bool}:
  {==}

def adopt_same_access() -> {UGate.adopt("{\"claudeAiOauth\":{\"accessToken\":\"old\",\"expiresAt\":1792999999000}}", "{\"claudeAiOauth\":{\"accessToken\":\"old\"}}", 1792756800) == False{} : Bool}:
  {==}

def adopt_expired() -> {UGate.adopt("{\"claudeAiOauth\":{\"accessToken\":\"new\",\"expiresAt\":1000}}", "{\"claudeAiOauth\":{\"accessToken\":\"old\"}}", 1792756800) == False{} : Bool}:
  {==}

def enc_path() -> {UGate.enc.path("/r", "2", "a@x.test") == "/r/credentials/.creds-2-a@x.test.enc" : String}:
  {==}

def consume_path() -> {UGate.consume.path("/r", "2") == "/r/credentials/.consume-2.lock" : String}:
  {==}

# ---- the account a grant names (oauth._parse_token_account) -----------------

def acct_json(r: Result<&2, &2, String, Json.Json>) -> String:
  match r:
    case Fail{e}:
      "parse-fail"
    case Done{j}:
      Json.emit_py(UCred.token.account(j))

def acct_of(body: String) -> String:
  acct_json(Json.parse(body))

def acct_full() -> {acct_of("{\"account\":{\"uuid\":\" U-1 \",\"email_address\":\"a@b.c\"},\"organization\":{\"uuid\":\"O-1\"}}") == "{\"uuid\": \"U-1\", \"email\": \"a@b.c\", \"organizationUuid\": \"O-1\"}" : String}:
  {==}

def acct_no_org() -> {acct_of("{\"account\":{\"uuid\":\"U-1\"}}") == "{\"uuid\": \"U-1\", \"email\": null, \"organizationUuid\": null}" : String}:
  {==}

def acct_blank_uuid() -> {acct_of("{\"account\":{\"uuid\":\"  \"}}") == "null" : String}:
  {==}

def acct_absent() -> {acct_of("{\"access_token\":\"x\"}") == "null" : String}:
  {==}
