import Base
import ../src/json.bend as J
import ../src/fmt/shape.bend as Sh

# Ground equations for the CSV shapes of the command documents.

def csv(key: String, js: String) -> String:
  Sh.csv_of(key, J.unwrap(J.parse(js)))

def list_doc() -> String:
  "{\"schemaVersion\":1,\"activeAccountNumber\":1,\"accounts\":[{\"number\":1,\"email\":\"a@x.test\",\"organizationName\":\"A, Inc\",\"organizationUuid\":\"u\",\"isOrganization\":true,\"active\":true,\"usageStatus\":\"ok\",\"usage\":{\"fiveHour\":{\"pct\":20.0,\"resetsAt\":\"2026-10-24T07:00:00+00:00\"},\"sevenDay\":{\"pct\":40.5,\"resetsAt\":\"2026-10-27T05:00:00+00:00\"}},\"usageFetchedAt\":\"2026-10-24T05:00:00Z\"},{\"number\":2,\"email\":\"b@x.test\",\"organizationName\":\"\",\"active\":false,\"usageStatus\":\"unavailable\",\"usage\":null,\"usageError\":\"network\"}]}"

def t_list() -> {csv("list", list_doc()) == "slot,email,org,kind,active,5h_pct,5h_reset,7d_pct,7d_reset,fetched_at,error\n1,a@x.test,\"A, Inc\",ok,true,20.0,2026-10-24T07:00:00+00:00,40.5,2026-10-27T05:00:00+00:00,2026-10-24T05:00:00Z,\n2,b@x.test,,unavailable,false,,,,,,network\n" : String}:
  {==}

def t_list_empty() -> {csv("list", "{\"schemaVersion\":1,\"activeAccountNumber\":null,\"accounts\":[]}") == "slot,email,org,kind,active,5h_pct,5h_reset,7d_pct,7d_reset,fetched_at,error\n" : String}:
  {==}

def t_status() -> {csv("status", "{\"schemaVersion\":1,\"active\":{\"number\":3,\"email\":\"c@x.test\",\"organizationName\":\"\",\"usageStatus\":\"api_key\",\"usage\":null},\"totalManagedAccounts\":4}") == "slot,email,org,kind,active,5h_pct,5h_reset,7d_pct,7d_reset,fetched_at,error\n3,c@x.test,,api_key,true,,,,,,\n" : String}:
  {==}

def t_status_none() -> {csv("status", "{\"schemaVersion\":1,\"active\":null}") == "slot,email,org,kind,active,5h_pct,5h_reset,7d_pct,7d_reset,fetched_at,error\n" : String}:
  {==}

def t_config_list() -> {csv("config-list", "{\"schemaVersion\":1,\"path\":\"/p\",\"settings\":[{\"key\":\"autoswitch.threshold\",\"value\":90.0,\"isSet\":false},{\"key\":\"autoswitch.model\",\"value\":null,\"isSet\":true}]}") == "key,value,is_set\nautoswitch.threshold,90.0,false\nautoswitch.model,,true\n" : String}:
  {==}

def t_profile_list() -> {csv("profile-list", "{\"schemaVersion\":1,\"active\":null,\"profiles\":[{\"name\":\"default\",\"builtin\":true,\"stored\":false,\"active\":true,\"strategy\":\"best\",\"threshold\":null,\"models\":null,\"cooldown_s\":null,\"interval_s\":null,\"effective\":{\"strategy\":\"best\",\"threshold\":90.0,\"models\":[\"opus\",\"sonnet\"],\"cooldown_s\":300,\"interval_s\":60}}]}") == "name,builtin,stored,active,strategy,threshold,models,cooldown_s,interval_s\ndefault,true,false,true,best,90.0,opus;sonnet,300,60\n" : String}:
  {==}

def t_wide() -> {csv("config-get", "{\"schemaVersion\":1,\"key\":\"autoswitch.threshold\",\"value\":90.0,\"isSet\":false}") == "schemaVersion,key,value,isSet\n1,autoswitch.threshold,90.0,false\n" : String}:
  {==}

def t_wide_nested() -> {csv("switch", "{\"schemaVersion\":1,\"from\":{\"number\":1,\"email\":\"a@x.test\"},\"to\":{\"number\":2},\"warnings\":[],\"message\":\"Switched, ok\"}") == "schemaVersion,from.number,from.email,to.number,warnings,message\n1,1,a@x.test,2,,\"Switched, ok\"\n" : String}:
  {==}

def t_error() -> {csv("list", "{\"schemaVersion\":1,\"error\":{\"type\":\"ConfigError\",\"message\":\"no \\\"x\\\"\"}}") == "schemaVersion,error.type,error.message\n1,ConfigError,\"no \"\"x\"\"\"\n" : String}:
  {==}

def t_export() -> {csv("export", "{\"autoswitch\":{\"threshold\":85.0,\"model\":\"opus,sonnet\"},\"profiles\":{\"x\":{\"models\":[\"a\",\"b\"]}},\"extra\":{}}") == "key,value\nautoswitch.threshold,85.0\nautoswitch.model,\"opus,sonnet\"\nprofiles.x.models,a;b\nextra,{}\n" : String}:
  {==}

def t_event_header() -> {Sh.event_header() == "event,ts,profile,strategy,active_slot,from_slot,to_slot,trigger,reason,detail,message,threshold,seconds,until,slot,email,dry_run,earliest_reset_at\n" : String}:
  {==}

def t_event_switch() -> {Sh.event_row(J.unwrap(J.parse("{\"schemaVersion\":1,\"event\":\"switch\",\"ts\":\"2026-10-24T05:00:00Z\",\"trigger\":\"proactive\",\"from\":{\"number\":1,\"email\":\"a@x.test\"},\"to\":{\"number\":2,\"email\":\"b@x.test\"},\"warnings\":[],\"dryRun\":false}"))) == "switch,2026-10-24T05:00:00Z,,,,1,2,proactive,,,,,,,,,false," : String}:
  {==}

def t_event_poll() -> {Sh.event_row(J.unwrap(J.parse("{\"schemaVersion\":1,\"event\":\"poll\",\"ts\":\"t\",\"active\":{\"number\":1,\"email\":\"a\"},\"headroomPct\":{\"1\":10.0},\"threshold\":90.0}"))) == "poll,t,,,1,,,,,,,90.0,,,,,," : String}:
  {==}
