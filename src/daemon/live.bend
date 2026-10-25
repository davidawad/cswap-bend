import Base
import ../json.bend as Json
import ../fs.bend as Fs
import ../setload.bend as Setload
import ../profile.bend as P
import ./config.bend as Cfg

# The settings in force for one tick of `cswap auto`: settings.json, with the
# profile in force laid over its `autoswitch` block, with the command-line
# flags over both. The daemon reads settings.json again every tick, so
# `cswap profile use NAME` takes effect without a restart.
#
# The profile in force is `--profile NAME` if given, else `active_profile`;
# no profile, or a name that matches nothing, leaves the settings as they are.

# The profile and strategy a tick decided under, for the events and the log.
type Tag is Data:
  Tag{profile: String, strategy: String}

# What a run holds besides the settings it reads each tick.
type Live is Data:
  Live{flags: Cfg.Flags, over: Maybe<&2, String>, tag: Maybe<&2, Tag>}

def raw_of(+text: String) -> Json.Json:
  Setload.raw.parsed(Json.parse(text))

def laid(+c: Cfg.Cfg, +res: P.Res) -> Cfg.Cfg:
  match res:
    case P.ROk{p}:
      P.with_prof(c, p)
    case o:
      c

def cfg_res(+text: String, +fl: Cfg.Flags, +res: P.Res) -> Cfg.Cfg:
  Cfg.merge(laid(Cfg.from_text(text), res), fl)

def tag_of(+res: P.Res, +c: Cfg.Cfg) -> Maybe<&2, Tag>:
  match res:
    case P.ROk{p}:
      Some{Tag{P.name_of(p), Cfg.cfg_strategy(c)}}
    case o:
      None{}

# The effective settings of a tick.
def cfg_for(+text: String, +fl: Cfg.Flags, +over: Maybe<&2, String>) -> Cfg.Cfg:
  cfg_res(text, fl, P.resolve(raw_of(text), over))

def tag_for(+text: String, +fl: Cfg.Flags, +over: Maybe<&2, String>) -> Maybe<&2, Tag>:
  tag_of(P.resolve(raw_of(text), over), cfg_for(text, fl, over))

# A name given with `--profile` that matches no profile.
def unknown2(+res: P.Res, +over: Maybe<&2, String>) -> Maybe<&2, String>:
  match res over:
    case P.RUnknown{n} Some{o}:
      Some{n}
    case _ _:
      None{}

def unknown(+text: String, +over: Maybe<&2, String>) -> Maybe<&2, String>:
  unknown2(P.resolve(raw_of(text), over), over)

def live_for(+text: String, +fl: Cfg.Flags, +over: Maybe<&2, String>) -> Live:
  Live{fl, over, tag_for(text, fl, over)}

def live_flags(+l: Live) -> Cfg.Flags:
  match l:
    case Live{fl, over, tag}:
      fl

def live_over(+l: Live) -> Maybe<&2, String>:
  match l:
    case Live{fl, over, tag}:
      over

def live_tag(+l: Live) -> Maybe<&2, Tag>:
  match l:
    case Live{fl, over, tag}:
      tag

def text_of(r: Fs.Res(String)) -> String:
  match r:
    case Fail{e}:
      ""
    case Done{t}:
      t

# settings.json as text; "" when it cannot be read.
def read_text(+root: String) -> IO(String):
  IO.bind(Fs.Res(String), String, Fs.read_file(root ++ "/settings.json"), r => IO.pure(String, text_of(r)))

# ---- events

def kind_is(+k: Maybe<&2, Json.Json>, +name: String) -> Bool:
  match k:
    case Some{Json.JStr{s}}:
      String.eq(s, name)
    case _:
      False{}

def decision_event(+e: Json.Json) -> Bool:
  kind_is(Json.get("event", e), "switch") || kind_is(Json.get("event", e), "no-switch") || kind_is(Json.get("event", e), "all-exhausted")

def tag_one2(+decision: Bool, +t: Tag, +e: Json.Json) -> Json.Json:
  match decision t:
    case True{} Tag{p, s}:
      Json.set("strategy", Json.JStr{s}, Json.set("profile", Json.JStr{p}, e))
    case False{} _:
      e

# A decision event with the profile and strategy it was made under added at the end.
def tag_one(+t: Tag, +e: Json.Json) -> Json.Json:
  tag_one2(decision_event(e), t, e)

def tag_events2(+t: Tag, +es: List<&2, Json.Json>) -> List<&2, Json.Json>:
  match es:
    case Nil{}:
      []
    case Con{e, rest}:
      tag_one(t, e) <> tag_events2(t, rest)

def tag_events(+m: Maybe<&2, Tag>, +es: List<&2, Json.Json>) -> List<&2, Json.Json>:
  match m:
    case Some{t}:
      tag_events2(t, es)
    case None{}:
      es

# The log line with the profile and strategy added, when a profile is in force.
def tag_log(+m: Maybe<&2, Tag>, +j: Json.Json) -> Json.Json:
  match m:
    case Some{Tag{p, s}}:
      Json.set("strategy", Json.JStr{s}, Json.set("profile", Json.JStr{p}, j))
    case None{}:
      j
