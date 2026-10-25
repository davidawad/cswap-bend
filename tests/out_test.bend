import Base
import ../src/cmd.bend as Cmd
import ../src/json.bend as J
import ../src/fmt/out.bend as O

# Ground equations for the format names and for converting a command's output.

def nm.of(m: Maybe<&2, O.Fmt>) -> String:
  match m:
    case Some{f}:
      O.name(f)
    case None{}:
      "?"

def nm(s: String) -> String:
  nm.of(O.of_name(s))

def n_text() -> {nm("text") == "text" : String}:
  {==}

def n_json() -> {nm("json") == "json" : String}:
  {==}

def n_csv() -> {nm("csv") == "csv" : String}:
  {==}

def n_yaml() -> {nm("yaml") == "yaml" : String}:
  {==}

def n_yml() -> {nm("yml") == "yaml" : String}:
  {==}

def n_toon() -> {nm("toon") == "toon" : String}:
  {==}

def n_bad() -> {nm("xml") == "?" : String}:
  {==}

def jsonout() -> String:
  "{\n  \"schemaVersion\": 1,\n  \"key\": \"autoswitch.threshold\",\n  \"value\": 90.0,\n  \"isSet\": false\n}\n"

def c_text_untouched() -> {O.convert(O.FText{}, "x", Cmd.Out{0, "hello\n", ""}) == Cmd.Out{0, "hello\n", ""} : Cmd.Out}:
  {==}

def c_json_native() -> {O.convert(O.FJson{}, "x", Cmd.Out{0, jsonout(), ""}) == Cmd.Out{0, jsonout(), ""} : Cmd.Out}:
  {==}

def c_json_text_command() -> {O.convert(O.FJson{}, "add", Cmd.Out{0, "Added Account 1: a@x.test\n", ""}) == Cmd.Out{0, "{\n  \"schemaVersion\": 1,\n  \"message\": \"Added Account 1: a@x.test\"\n}\n", ""} : Cmd.Out}:
  {==}

def c_json_error_on_stderr() -> {O.convert(O.FJson{}, "config", Cmd.Out{1, "", "Error: unknown setting\n"}) == Cmd.Out{1, "{\n  \"schemaVersion\": 1,\n  \"error\": {\n    \"type\": \"Error\",\n    \"message\": \"unknown setting\"\n  }\n}\n", ""} : Cmd.Out}:
  {==}

def c_usage_error_untouched() -> {O.convert(O.FJson{}, "x", Cmd.Out{2, "", "usage: x\n"}) == Cmd.Out{2, "", "usage: x\n"} : Cmd.Out}:
  {==}

def c_yaml() -> {O.convert(O.FYaml{}, "config-get", Cmd.Out{0, jsonout(), ""}) == Cmd.Out{0, "schemaVersion: 1\nkey: autoswitch.threshold\nvalue: 90.0\nisSet: false\n", ""} : Cmd.Out}:
  {==}

def c_toon() -> {O.convert(O.FToon{}, "config-get", Cmd.Out{0, jsonout(), ""}) == Cmd.Out{0, "schemaVersion: 1\nkey: autoswitch.threshold\nvalue: 90\nisSet: false\n", ""} : Cmd.Out}:
  {==}

def c_csv() -> {O.convert(O.FCsv{}, "config-get", Cmd.Out{0, jsonout(), ""}) == Cmd.Out{0, "schemaVersion,key,value,isSet\n1,autoswitch.threshold,90.0,false\n", ""} : Cmd.Out}:
  {==}

def c_csv_error_envelope() -> {O.convert(O.FCsv{}, "list", Cmd.Out{1, "{\n  \"schemaVersion\": 1,\n  \"error\": {\n    \"type\": \"ConfigError\",\n    \"message\": \"bad\"\n  }\n}\n", ""}) == Cmd.Out{1, "schemaVersion,error.type,error.message\n1,ConfigError,bad\n", ""} : Cmd.Out}:
  {==}

def c_yaml_text_command() -> {O.convert(O.FYaml{}, "remove", Cmd.Out{0, "Removed Account 2\n", ""}) == Cmd.Out{0, "schemaVersion: 1\nmessage: Removed Account 2\n", ""} : Cmd.Out}:
  {==}

def e() -> J.Json:
  J.unwrap(J.parse("{\"schemaVersion\":1,\"event\":\"no-switch\",\"ts\":\"2026-10-24T05:00:00Z\",\"reason\":\"below-threshold\",\"detail\":\"\"}"))

def ev_json() -> {O.event_text(O.FJson{}, e()) == "{\"schemaVersion\": 1, \"event\": \"no-switch\", \"ts\": \"2026-10-24T05:00:00Z\", \"reason\": \"below-threshold\", \"detail\": \"\"}" : String}:
  {==}

def ev_csv() -> {O.event_text(O.FCsv{}, e()) == "no-switch,2026-10-24T05:00:00Z,,,,,,,below-threshold,,,,,,,,," : String}:
  {==}

def ev_yaml() -> {O.event_text(O.FYaml{}, e()) == "---\nschemaVersion: 1\nevent: no-switch\nts: \"2026-10-24T05:00:00Z\"\nreason: below-threshold\ndetail: \"\"" : String}:
  {==}

def ev_toon() -> {O.event_text(O.FToon{}, e()) == "schemaVersion: 1\nevent: no-switch\nts: \"2026-10-24T05:00:00Z\"\nreason: below-threshold\ndetail: \"\"\n" : String}:
  {==}

def head_csv() -> {O.stream_head(O.FCsv{}) == "event,ts,profile,strategy,active_slot,from_slot,to_slot,trigger,reason,detail,message,threshold,seconds,until,slot,email,dry_run,earliest_reset_at\n" : String}:
  {==}

def head_json() -> {O.stream_head(O.FJson{}) == "" : String}:
  {==}
