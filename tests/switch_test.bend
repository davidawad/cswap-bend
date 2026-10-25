import Base
import ../src/json.bend as Json
import ../src/store.bend as Store
import ../src/swbase.bend as SwBase
import ../src/swcreds.bend as SwCreds
import ../src/swpick.bend as SwPick
import ../src/store/plan.bend as SPlan

# The pure parts of switch: the files and locks run in tests/switch_it.sh and
# tests/switch_replay.py (parity fixtures 11-18).

def cfg() -> Json.Json:
  Json.unwrap(Json.parse("{\"numStartups\": 42, \"oauthAccount\": {\"emailAddress\": \"a@x.test\", \"displayName\": \"A\"}, \"theme\": \"dark\", \"primaryApiKey\": \"sk-ant-api03-OLD\"}"))

def oauth() -> Json.Json:
  Json.unwrap(Json.parse("{\"emailAddress\": \"b@x.test\", \"accountUuid\": \"\", \"organizationUuid\": null}"))

# ---- ~/.claude.json: only oauthAccount changes, in place ----

def m_merge_in_place() -> {Json.emit(SwBase.merge_oauth(cfg(), oauth())) == "{\"numStartups\":42,\"oauthAccount\":{\"emailAddress\":\"b@x.test\",\"accountUuid\":\"\",\"organizationUuid\":null},\"theme\":\"dark\",\"primaryApiKey\":\"sk-ant-api03-OLD\"}" : String}:
  {==}

def m_merge_appends_when_absent() -> {Json.emit(SwBase.merge_oauth(Json.unwrap(Json.parse("{\"a\": 1}")), oauth())) == "{\"a\":1,\"oauthAccount\":{\"emailAddress\":\"b@x.test\",\"accountUuid\":\"\",\"organizationUuid\":null}}" : String}:
  {==}

def m_oauth_target_drops_managed_key() -> {Json.emit(SwBase.activate_config(cfg(), oauth(), "{\"claudeAiOauth\": {}}")) == "{\"numStartups\":42,\"oauthAccount\":{\"emailAddress\":\"b@x.test\",\"accountUuid\":\"\",\"organizationUuid\":null},\"theme\":\"dark\"}" : String}:
  {==}

def m_api_key_target_sets_managed_key() -> {Json.emit(SwBase.activate_config(Json.unwrap(Json.parse("{\"x\": 1, \"oauthAccount\": {\"emailAddress\": \"a@x.test\"}}")), oauth(), "sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ")) == "{\"x\":1,\"oauthAccount\":{\"emailAddress\":\"b@x.test\",\"accountUuid\":\"\",\"organizationUuid\":null},\"customApiKeyResponses\":{\"approved\":[\"GHIJKLMNOPQRSTUVWXYZ\"],\"rejected\":[]},\"primaryApiKey\":\"sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ\"}" : String}:
  {==}

def m_api_key_already_approved() -> {Json.emit(SwBase.activate_config(Json.unwrap(Json.parse("{\"customApiKeyResponses\": {\"approved\": [\"GHIJKLMNOPQRSTUVWXYZ\"], \"rejected\": [\"q\"]}}")), oauth(), "sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ")) == "{\"customApiKeyResponses\":{\"approved\":[\"GHIJKLMNOPQRSTUVWXYZ\"],\"rejected\":[\"q\"]},\"primaryApiKey\":\"sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ\",\"oauthAccount\":{\"emailAddress\":\"b@x.test\",\"accountUuid\":\"\",\"organizationUuid\":null}}" : String}:
  {==}

def m_approved_form() -> {SwBase.approved_form("sk-ant-api03-ABCDEFGHIJKLMNOPQRSTUVWXYZ") == "GHIJKLMNOPQRSTUVWXYZ" : String}:
  {==}

# ---- the credential written live ----

def c_target() -> String:
  "{\"claudeAiOauth\": {\"accessToken\": \"T\", \"scopes\": [\"user:inference\"]}, \"mcpOAuth\": {\"old\": 1}}"

def c_live() -> String:
  "{\"claudeAiOauth\": {\"accessToken\": \"L\"}, \"mcpOAuth\": {\"srv\": {\"t\": 1}}, \"pluginSecrets\": {\"p\": 2}, \"other\": 3}"

def c_shared_ride_along() -> {SwCreds.prepare_activation(c_target(), c_live()) == "{\"claudeAiOauth\": {\"accessToken\": \"T\", \"scopes\": [\"user:inference\"]}, \"mcpOAuth\": {\"srv\": {\"t\": 1}}, \"pluginSecrets\": {\"p\": 2}}" : String}:
  {==}

def c_live_without_shared_drops_target_shared() -> {SwCreds.prepare_activation(c_target(), "{\"claudeAiOauth\": {\"accessToken\": \"L\"}}") == "{\"claudeAiOauth\": {\"accessToken\": \"T\", \"scopes\": [\"user:inference\"]}}" : String}:
  {==}

def c_live_api_key_leaves_target() -> {SwCreds.prepare_activation(c_target(), "sk-ant-api03-X") == c_target() : String}:
  {==}

def c_target_api_key_untouched() -> {SwCreds.prepare_activation("sk-ant-api03-X", c_live()) == "sk-ant-api03-X" : String}:
  {==}

def c_no_live() -> {SwCreds.prepare_activation(c_target(), "") == c_target() : String}:
  {==}

# ---- what the live credential is ----

def full(at: String, rt: String) -> String:
  "{\"claudeAiOauth\": {\"accessToken\": \"" ++ at ++ "\", \"refreshToken\": \"" ++ rt ++ "\"}}"

def k_own_bytes() -> {SwCreds.classify(full("a", "r"), full("a", "r"), []) == SwCreds.KOwnBytes{} : SwCreds.CKind}:
  {==}

def k_own_family() -> {SwCreds.classify(full("a2", "r"), full("a", "r"), []) == SwCreds.KOwnFamily{} : SwCreds.CKind}:
  {==}

def k_wiped() -> {SwCreds.classify(full("", ""), full("a", "r"), []) == SwCreds.KWiped{} : SwCreds.CKind}:
  {==}

def k_other_slot_holds_it() -> {SwCreds.classify(full("b", "rb"), full("a", "r"), [SwCreds.Other{"2", full("b", "rb")}]) == SwCreds.KForeignSynced{"2"} : SwCreds.CKind}:
  {==}

def k_unresolved() -> {SwCreds.classify(full("z", "rz"), full("a", "r"), [SwCreds.Other{"2", full("b", "rb")}]) == SwCreds.KUnresolved{} : SwCreds.CKind}:
  {==}

def k_setup_token_same_bytes() -> {SwCreds.classify("{\"claudeAiOauth\": {\"accessToken\": \"s\"}}", "{\"claudeAiOauth\": {\"accessToken\": \"s\"}}", []) == SwCreds.KOwnBytes{} : SwCreds.CKind}:
  {==}

def seq() -> Json.Json:
  Json.unwrap(Json.parse("{\"activeAccountNumber\": 1, \"sequence\": [1, 2], \"accounts\": {\"1\": {\"email\": \"a@x.test\", \"uuid\": \"u1\", \"organizationUuid\": \"o1\"}, \"2\": {\"email\": \"b@x.test\", \"uuid\": \"u2\", \"organizationUuid\": \"\"}}}"))

def prof(u: String, e: String, o: String) -> SPlan.Prof:
  SPlan.Prof{u, Some{e}, Some{o}}

def r_same_uuid_is_own() -> {SwCreds.resolved_kind(seq(), "1", full("z", "rz"), [], prof("u1", "a@x.test", "o1")) == SwCreds.KOwnFamily{} : SwCreds.CKind}:
  {==}

def r_rotated_owner_by_email() -> {SwCreds.resolved_kind(seq(), "1", full("z", "rz"), [], prof("", "a@x.test", "o1")) == SwCreds.KOwnFamily{} : SwCreds.CKind}:
  {==}

def r_unmanaged_identity_is_alien() -> {SwCreds.resolved_kind(seq(), "1", full("z", "rz"), [], prof("uz", "z@x.test", "oz")) == SwCreds.KAlien{} : SwCreds.CKind}:
  {==}

def r_other_slot_is_foreign() -> {SwCreds.resolved_kind(seq(), "1", full("z", "rz"), [], prof("u2", "b@x.test", "")) == SwCreds.KForeign{"2"} : SwCreds.CKind}:
  {==}

def r_other_slot_wrong_uuid_is_alien() -> {SwCreds.resolved_kind(seq(), "1", full("z", "rz"), [], prof("u9", "b@x.test", "")) == SwCreds.KAlien{} : SwCreds.CKind}:
  {==}

def r_none_stays_unresolved() -> {SwCreds.resolved_kind(seq(), "1", full("z", "rz"), [], SPlan.ProfNone{}) == SwCreds.KUnresolved{} : SwCreds.CKind}:
  {==}

def r_partial_identity_stays_unresolved() -> {SwCreds.resolved_kind(seq(), "1", full("z", "rz"), [], SPlan.Prof{"uz", Some{"z@x.test"}, None{}}) == SwCreds.KUnresolved{} : SwCreds.CKind}:
  {==}

# ---- choosing the target ----

def cand(slot: String, dis: Bool, sw: Bool, h: Maybe<&2, U32>) -> SwPick.Cand:
  SwPick.Cand{slot, dis, sw, h}

def n_first_usable() -> {SwPick.select_next([cand("2", False{}, True{}, None{}), cand("3", False{}, True{}, None{})], False{}) == SwPick.SelOk{"2", []} : SwPick.Sel}:
  {==}

def n_skips_disabled() -> {SwPick.select_next([cand("2", True{}, True{}, None{}), cand("3", False{}, True{}, None{})], False{}) == SwPick.SelOk{"3", ["Skipped Account-2 (disabled)"]} : SwPick.Sel}:
  {==}

def n_skips_unswitchable() -> {SwPick.select_next([cand("2", False{}, False{}, None{}), cand("3", False{}, True{}, None{})], False{}) == SwPick.SelOk{"3", ["Skipped Account-2 (no stored credentials/config)"]} : SwPick.Sel}:
  {==}

def n_next_available_skips_exhausted() -> {SwPick.select_next([cand("2", False{}, True{}, Some{0}), cand("3", False{}, True{}, Some{500})], True{}) == SwPick.SelOk{"3", ["Skipped Account-2 (at 5h/7d limit)"]} : SwPick.Sel}:
  {==}

def n_plain_rotation_ignores_usage() -> {SwPick.select_next([cand("2", False{}, True{}, Some{0})], False{}) == SwPick.SelOk{"2", []} : SwPick.Sel}:
  {==}

def n_unknown_headroom_is_not_skipped() -> {SwPick.select_next([cand("2", False{}, True{}, None{})], True{}) == SwPick.SelOk{"2", []} : SwPick.Sel}:
  {==}

def n_all_exhausted() -> {SwPick.select_next([cand("2", False{}, True{}, Some{0})], True{}) == SwPick.SelNone{["Skipped Account-2 (at 5h/7d limit)"], True{}} : SwPick.Sel}:
  {==}

def n_nothing_valid() -> {SwPick.select_next([cand("2", True{}, True{}, None{})], False{}) == SwPick.SelNone{["Skipped Account-2 (disabled)"], False{}} : SwPick.Sel}:
  {==}

def n_rotated_order() -> {SwPick.rotated(["1", "2", "3", "4"], Some{"2"}) == ["3", "4", "1"] : List<&2, String>}:
  {==}

def n_rotated_unknown_anchor_counts_as_first() -> {SwPick.rotated(["1", "2", "3"], Some{"9"}) == ["2", "3"] : List<&2, String>}:
  {==}

def b_pick_strictly_more() -> {SwPick.select_best(Some{3000}, [cand("2", False{}, True{}, Some{6000}), cand("3", False{}, True{}, Some{6000})]) == SwPick.BPick{"2"} : SwPick.BestOut}:
  {==}

def b_tie_stays() -> {SwPick.select_best(Some{6000}, [cand("2", False{}, True{}, Some{6000})]) == SwPick.BNote{"stay"} : SwPick.BestOut}:
  {==}

def b_current_unknown() -> {SwPick.select_best(None{}, [cand("2", False{}, True{}, Some{6000})]) == SwPick.BNote{"current-unavailable"} : SwPick.BestOut}:
  {==}

def b_nothing_to_compare() -> {SwPick.select_best(Some{1000}, [cand("2", False{}, True{}, None{})]) == SwPick.BNote{"no-comparison"} : SwPick.BestOut}:
  {==}

def b_incomplete() -> {SwPick.select_best(Some{6000}, [cand("2", False{}, True{}, Some{1000}), cand("3", False{}, True{}, None{})]) == SwPick.BNote{"incomplete-comparison"} : SwPick.BestOut}:
  {==}

def b_exhausted() -> {SwPick.select_best(Some{0}, [cand("2", False{}, True{}, Some{0})]) == SwPick.BNote{"exhausted"} : SwPick.BestOut}:
  {==}

def b_no_others() -> {SwPick.select_best(Some{0}, []) == SwPick.BNote{"none"} : SwPick.BestOut}:
  {==}

def row() -> Json.Json:
  Json.unwrap(Json.parse("{\"five_hour\": {\"pct\": 90.0}, \"seven_day\": {\"pct\": 40.5}, \"scoped\": [{\"name\": \"Opus\", \"pct\": 95.25}, {\"name\": \"Sonnet\", \"pct\": 10.0}]}"))

def h_five_hour_binds() -> {SwPick.headroom(row(), []) == Some{1000} : Maybe<&2, U32>}:
  {==}

def h_model_binds() -> {SwPick.headroom(row(), ["opus"]) == Some{475} : Maybe<&2, U32>}:
  {==}

def h_other_model_does_not_bind() -> {SwPick.headroom(row(), ["sonnet"]) == Some{1000} : Maybe<&2, U32>}:
  {==}

def h_all_models() -> {SwPick.headroom(row(), ["all"]) == Some{475} : Maybe<&2, U32>}:
  {==}

def h_no_windows() -> {SwPick.headroom(Json.JNull{}, []) == None{} : Maybe<&2, U32>}:
  {==}

def h_over_100_is_zero() -> {SwPick.headroom(Json.unwrap(Json.parse("{\"five_hour\": {\"pct\": 130.0}}")), []) == Some{0} : Maybe<&2, U32>}:
  {==}

def h_pct_parse() -> {SwPick.pct_hundredths("12.34") == 1234 : U32}:
  {==}

def h_pct_parse_whole() -> {SwPick.pct_hundredths("7") == 700 : U32}:
  {==}

# ---- results (contract 2.3) ----

def op() -> Json.Json:
  Json.unwrap(Json.parse("{\"from\": {\"number\": 1, \"email\": \"a@x.test\"}, \"to\": {\"number\": 3, \"email\": \"c@x.test\"}, \"warnings\": [\"w\"]}"))

def x_switched() -> {Json.emit(SwBase.result_of_op(op(), "direct", ["pre"])) == "{\"schemaVersion\":1,\"switched\":true,\"from\":{\"number\":1,\"email\":\"a@x.test\"},\"to\":{\"number\":3,\"email\":\"c@x.test\"},\"strategy\":\"direct\",\"reason\":\"switched\",\"message\":\"Switched to Account-3 (c@x.test)\",\"warnings\":[\"pre\",\"w\"]}" : String}:
  {==}

def x_same_is_already_active() -> {Json.emit(SwBase.result_of_op(Json.unwrap(Json.parse("{\"from\": {\"number\": 2, \"email\": \"b\"}, \"to\": {\"number\": 2, \"email\": \"b\"}, \"warnings\": []}")), "rotation", [])) == "{\"schemaVersion\":1,\"switched\":false,\"from\":{\"number\":2,\"email\":\"b\"},\"to\":{\"number\":2,\"email\":\"b\"},\"strategy\":\"rotation\",\"reason\":\"already-active\",\"message\":\"Already on Account-2 (b)\",\"warnings\":[]}" : String}:
  {==}

def x_unmanaged_from_has_null_number() -> {Json.emit(SwBase.from_ref("z@x.test", None{})) == "{\"number\":null,\"email\":\"z@x.test\"}" : String}:
  {==}

def x_logged_out_has_null_from() -> {Json.emit(SwBase.from_ref("", None{})) == "null" : String}:
  {==}

def x_forced_self_switch_is_activated() -> {Json.emit(SwBase.forced_result(True{}, SwBase.result_of_op(Json.unwrap(Json.parse("{\"from\": {\"number\": 1, \"email\": \"a\"}, \"to\": {\"number\": 1, \"email\": \"a\"}, \"warnings\": []}")), "direct", []))) == "{\"schemaVersion\":1,\"switched\":false,\"from\":{\"number\":1,\"email\":\"a\"},\"to\":{\"number\":1,\"email\":\"a\"},\"strategy\":\"direct\",\"reason\":\"activated\",\"message\":\"Activated Account-1 (a) from stored backup\",\"warnings\":[]}" : String}:
  {==}

def x_error_envelope() -> {Json.emit(SwBase.error_envelope(3, "Account-9 does not exist")) == "{\"schemaVersion\":1,\"error\":{\"type\":\"AccountNotFoundError\",\"message\":\"Account-9 does not exist\"}}" : String}:
  {==}

def x_override_envelope() -> {Json.emit(SwBase.error_envelope(SwBase.e_overridden(), "m")) == "{\"schemaVersion\":1,\"error\":{\"type\":\"live-login-overridden\",\"message\":\"m\"}}" : String}:
  {==}

def x_override_message() -> {SwBase.override_msg("2", "b@x.test", "a@x.test") == "live-login-overridden: after switching to Account-2 (b@x.test) the live login reads a@x.test; a Claude Code keychain login is overriding cswap; remove the 'Claude Code-credentials' keychain item" : String}:
  {==}

def x_models_ride_along() -> {Json.emit(SwBase.with_models(Json.JObj{Json.JNil{}}, ["Opus"], "cli")) == "{\"models\":[\"Opus\"],\"modelSource\":\"cli\"}" : String}:
  {==}

def x_no_models_no_keys() -> {Json.emit(SwBase.with_models(Json.JObj{Json.JNil{}}, [], "cli")) == "{}" : String}:
  {==}
