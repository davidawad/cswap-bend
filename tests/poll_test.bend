import Base
import ../src/pollrow.bend as Pollrow
import ../src/poll.bend as Poll
import ../src/json.bend as Json

def j(s: String) -> Json.Json:
  Json.unwrap(Json.parse(s))

def now() -> U32:
  10000

def usage(h5: String, d7: String) -> Json.Json:
  j("{\"five_hour\":{\"pct\":" ++ h5 ++ ",\"resets_at\":\"1970-01-01T04:51:40+00:00\"},\"seven_day\":{\"pct\":" ++ d7 ++ ",\"resets_at\":\"1970-01-04T02:00:00+00:00\"}}")

def none() -> Json.Json:
  Json.JNull{}

# ---- percentages and windows ----------------------------------------------------

def t_tenths() -> {Poll.tenths("42.5") == Some{425} : Maybe<&2, U32>}:
  {==}

def t_tenths_int() -> {Poll.tenths("100") == Some{1000} : Maybe<&2, U32>}:
  {==}

def t_tenths_round() -> {Poll.tenths("12.35") == Some{124} : Maybe<&2, U32>}:
  {==}

def t_tenths_bad() -> {Poll.tenths("x") == None{} : Maybe<&2, U32>}:
  {==}

def t_binding() -> {Poll.binding(usage("20.0", "40.0"), []) == Some{400} : Maybe<&2, U32>}:
  {==}

def t_binding_none() -> {Poll.binding(none(), []) == None{} : Maybe<&2, U32>}:
  {==}

def scoped() -> Json.Json:
  j("{\"five_hour\":{\"pct\":10.0},\"scoped\":[{\"name\":\"Opus\",\"pct\":95.0},{\"name\":\"Fable\",\"pct\":20.0}]}")

def t_scoped_ignored() -> {Poll.binding(scoped(), []) == Some{100} : Maybe<&2, U32>}:
  {==}

def t_scoped_named() -> {Poll.binding(scoped(), ["opus"]) == Some{950} : Maybe<&2, U32>}:
  {==}

def t_scoped_all() -> {Poll.binding(scoped(), ["all"]) == Some{950} : Maybe<&2, U32>}:
  {==}

def t_scoped_other() -> {Poll.binding(scoped(), ["fable"]) == Some{200} : Maybe<&2, U32>}:
  {==}

# ---- poll plans (fixtures 08 and 09) -------------------------------------------------

def t_plan_active_first() -> {Poll.plan_after_fetch(None{}, none(), usage("25.0", "50.0"), True{}, 900, [], False{}, now()) == Poll.Sched{10180, 180} : Poll.Sched}:
  {==}

def t_plan_candidate_first() -> {Poll.plan_after_fetch(None{}, none(), usage("10.0", "30.0"), False{}, 900, [], False{}, now()) == Poll.Sched{10300, 300} : Poll.Sched}:
  {==}

def t_plan_exhausted() -> {Poll.plan_after_fetch(None{}, none(), usage("100.0", "80.0"), False{}, 900, [], False{}, now()) == Poll.Sched{10600, 600} : Poll.Sched}:
  {==}

def t_plan_still_backs_off() -> {Poll.plan_after_fetch(Some{180}, usage("20.0", "40.0"), usage("20.0", "40.0"), True{}, 900, [], False{}, now()) == Poll.Sched{10270, 270} : Poll.Sched}:
  {==}

def t_plan_moving_halves() -> {Poll.plan_after_fetch(Some{600}, usage("20.0", "40.0"), usage("25.0", "45.0"), False{}, 900, [], False{}, now()) == Poll.Sched{10300, 300} : Poll.Sched}:
  {==}

def t_plan_urgent() -> {Poll.plan_after_fetch(Some{180}, usage("80.0", "40.0"), usage("85.0", "40.0"), True{}, 900, [], False{}, now()) == Poll.Sched{10060, 60} : Poll.Sched}:
  {==}

def t_plan_recent_429() -> {Poll.plan_after_fetch(Some{300}, usage("20.0", "40.0"), usage("20.0", "40.0"), False{}, 900, [], True{}, now()) == Poll.Sched{10450, 450} : Poll.Sched}:
  {==}

def t_plan_reset_cap() -> {Poll.plan_after_fetch(None{}, none(), j("{\"five_hour\":{\"pct\":5.0,\"resets_at\":\"1970-01-01T02:47:10+00:00\"}}"), False{}, 900, [], False{}, now()) == Poll.Sched{10090, 300} : Poll.Sched}:
  {==}

# ---- backoff -------------------------------------------------------------------------

def t_backoff_curve() -> {Pollrow.failure_backoff(1, None{}, False{}) == 30 : U32}:
  {==}

def t_backoff_curve3() -> {Pollrow.failure_backoff(3, None{}, False{}) == 120 : U32}:
  {==}

def t_backoff_cap() -> {Pollrow.failure_backoff(40, None{}, False{}) == 600 : U32}:
  {==}

def t_backoff_retry_after() -> {Pollrow.failure_backoff(1, Some{120}, True{}) == 120 : U32}:
  {==}

def t_backoff_zero_429() -> {Pollrow.failure_backoff(1, Some{0}, True{}) == 300 : U32}:
  {==}

def t_backoff_zero_other() -> {Pollrow.failure_backoff(1, Some{0}, False{}) == 30 : U32}:
  {==}

def t_backoff_margin() -> {Pollrow.failure_backoff(1, Some{3600}, True{}) == 4500 : U32}:
  {==}

def t_backoff_no_margin_non429() -> {Pollrow.failure_backoff(1, Some{700}, False{}) == 700 : U32}:
  {==}

def t_backoff_cap_non429() -> {Pollrow.failure_backoff(1, Some{9000}, False{}) == 3600 : U32}:
  {==}

# ---- rows --------------------------------------------------------------------------------

def row(s: String) -> Pollrow.Row:
  Pollrow.row.of(j(s))

def t_row_eligible_cold() -> {Pollrow.row_eligible(row("{}"), now(), True{}, True{}) == True{} : Bool}:
  {==}

def t_row_fresh_not_eligible() -> {Pollrow.row_eligible(row("{\"fetchedAt\":9970.5,\"nextPollAt\":10150}"), now(), True{}, True{}) == False{} : Bool}:
  {==}

def t_row_stale_and_due() -> {Pollrow.row_eligible(row("{\"fetchedAt\":9200,\"nextPollAt\":9900}"), now(), True{}, True{}) == True{} : Bool}:
  {==}

def t_row_stale_not_due() -> {Pollrow.row_eligible(row("{\"fetchedAt\":9200,\"nextPollAt\":10200}"), now(), True{}, True{}) == False{} : Bool}:
  {==}

def t_row_backoff() -> {Pollrow.row_eligible(row("{\"backoffUntil\":10100}"), now(), True{}, True{}) == False{} : Bool}:
  {==}

def t_row_held() -> {Pollrow.row_eligible(row("{\"fetchedAt\":9200,\"heldUntil\":10600}"), now(), True{}, True{}) == False{} : Bool}:
  {==}

def t_row_claimed() -> {Pollrow.row_eligible(row("{\"claimUntil\":10050}"), now(), True{}, True{}) == False{} : Bool}:
  {==}

def t_row_claim_expired() -> {Pollrow.row_eligible(row("{\"claimUntil\":9900,\"claimId\":\"x\"}"), now(), True{}, True{}) == True{} : Bool}:
  {==}

def t_row_dead() -> {Pollrow.row_eligible(row("{\"authDeadStrikes\":1}"), now(), True{}, True{}) == False{} : Bool}:
  {==}

def t_row_overslept() -> {Pollrow.row_eligible(row("{\"fetchedAt\":9200,\"nextPollAt\":1792999999,\"pollIntervalS\":180.0}"), now(), True{}, True{}) == True{} : Bool}:
  {==}

def t_row_overslept_not_repaired() -> {Pollrow.row_eligible(row("{\"fetchedAt\":9200,\"nextPollAt\":1792999999,\"pollIntervalS\":180.0}"), now(), True{}, False{}) == False{} : Bool}:
  {==}

# ---- decision trust ---------------------------------------------------------------------

def lg() -> String:
  "\"lastGood\":{\"five_hour\":{\"pct\":10.0,\"resets_at\":\"1970-01-01T04:51:40+00:00\"}}"

def t_decision_recent() -> {Pollrow.decision_usage(row("{" ++ lg() ++ ",\"fetchedAt\":9900}"), [], now()) == j("{\"five_hour\":{\"pct\":10.0,\"resets_at\":\"1970-01-01T04:51:40+00:00\"}}") : Json.Json}:
  {==}

def t_decision_old() -> {Pollrow.decision_usage(row("{" ++ lg() ++ ",\"fetchedAt\":9200}"), [], now()) == Json.JNull{} : Json.Json}:
  {==}

def t_decision_planned() -> {Pollrow.decision_usage(row("{" ++ lg() ++ ",\"fetchedAt\":9200,\"nextPollAt\":10200}"), [], now()) == j("{\"five_hour\":{\"pct\":10.0,\"resets_at\":\"1970-01-01T04:51:40+00:00\"}}") : Json.Json}:
  {==}

def t_decision_failing() -> {Pollrow.decision_usage(row("{" ++ lg() ++ ",\"fetchedAt\":9200,\"consecutiveFailures\":2}"), [], now()) == j("{\"five_hour\":{\"pct\":10.0,\"resets_at\":\"1970-01-01T04:51:40+00:00\"}}") : Json.Json}:
  {==}

def t_decision_failing_too_old() -> {Pollrow.decision_usage(row("{" ++ lg() ++ ",\"fetchedAt\":5200,\"consecutiveFailures\":2}"), [], now()) == Json.JNull{} : Json.Json}:
  {==}

def t_decision_429_until_reset() -> {Pollrow.decision_usage(row("{" ++ lg() ++ ",\"fetchedAt\":3200,\"consecutiveFailures\":1,\"lastError\":\"http-429\"}"), [], now()) == j("{\"five_hour\":{\"pct\":10.0,\"resets_at\":\"1970-01-01T04:51:40+00:00\"}}") : Json.Json}:
  {==}

def t_decision_429_after_reset() -> {Pollrow.decision_usage(row("{" ++ lg() ++ ",\"fetchedAt\":3200,\"consecutiveFailures\":1,\"lastError\":\"http-429\"}"), [], 17600) == Json.JNull{} : Json.Json}:
  {==}

def t_decision_no_fetch() -> {Pollrow.decision_usage(row("{" ++ lg() ++ "}"), [], now()) == Json.JNull{} : Json.Json}:
  {==}
