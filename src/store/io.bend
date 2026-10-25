import Base
import ../json.bend as Json
import ../b64.bend as B64
import ../fs.bend as Fs
import ../act.bend as Act
import ../clock.bend as Clock
import ../fs/write.bend as FsW
import ./base.bend as SBase
import ./seq.bend as SSeq

# `do ActM<A>:` needs the monad defined in the file that uses it.
def ActM(-A: Type) -> Type:
  Act.of(A)

def ActM.pure(-A: Type, x: A) -> Act.of(A):
  Act.pure(A, x)

def ActM.bind(-A: Type, -B: Type, m: Act.of(A), f: A -> Act.of(B)) -> Act.of(B):
  Act.bind(A, B, m, f)

# ---- IO: directories, log, files -------------------------------------------------------

def now_iso() -> Act.of(String):
  do ActM<String>:
    t : U32 <- Act.lift(U32, Clock.now_s())
    return Clock.iso8601_utc(t)

def swallow(r: Fs.Res(Unit)) -> Act.of(Unit):
  Act.pure(Unit, Unit{})

def log_write(+root: String, +ts: String, +level: String, +msg: String) -> Act.of(Unit):
  IO.bind(Fs.Res(Unit), Fs.Res(Unit), FsW.append(SBase.log_path(root), SBase.log_line(ts, level, msg)), r => IO.pure(Fs.Res(Unit), Done{Unit{}}))

# One line in claude-swap.log, in the reference's format. A log that cannot be
# written never fails the operation.
def log(+root: String, +level: String, +msg: String) -> Act.of(Unit):
  do ActM<Unit>:
    ts : String <- now_iso()
    log_write(root, ts, level, msg)

def secure_dir(+path: String) -> Act.of(Unit):
  do ActM<Unit>:
    FsW.mkdir_p(path)
    FsW.chmod("700", path)

# The backup root, credentials/ and configs/, all 0700.
def setup_dirs(+root: String) -> Act.of(Unit):
  do ActM<Unit>:
    secure_dir(root)
    secure_dir(SBase.creds_dir(root))
    secure_dir(SBase.configs_dir(root))

def write_secret(+path: String, +text: String) -> Act.of(Unit):
  FsW.write_atomic(path, text, "600")

def write_seq(+root: String, +j: Json.Json) -> Act.of(Unit):
  write_secret(SBase.seq_path(root), Json.emit_pretty(j))

def parse_seq(+path: String, r: Result<&2, &2, String, Json.Json>) -> Act.of(Maybe<&2, Json.Json>):
  match r:
    case Fail{e}:
      Act.fail(Maybe<&2, Json.Json>, 1, path ++ " exists but could not be parsed (" ++ e ++ "). Repair or move it, then retry — refusing to overwrite it unread.")
    case Done{j}:
      Act.pure(Maybe<&2, Json.Json>, Some{j})

def read_seq2(+ex: Bool, +path: String) -> Act.of(Maybe<&2, Json.Json>):
  match ex:
    case False{}:
      Act.pure(Maybe<&2, Json.Json>, None{})
    case True{}:
      do ActM<Maybe<&2, Json.Json>>:
        text : String <- Fs.read_file(path)
        parse_seq(path, Json.parse(text))

# sequence.json, or None when there is none yet. A torn file is an error and
# is never replaced.
def read_seq(+root: String) -> Act.of(Maybe<&2, Json.Json>):
  do ActM<Maybe<&2, Json.Json>>:
    ex : Bool <- Act.lift(Bool, Fs.exists(SBase.seq_path(root)))
    read_seq2(ex, SBase.seq_path(root))

def ensure_seq2(+m: Maybe<&2, Json.Json>, +root: String, +ts: String) -> Act.of(Json.Json):
  match m:
    case Some{j}:
      Act.pure(Json.Json, j)
    case None{}:
      do ActM<Json.Json>:
        write_seq(root, SSeq.seq_fresh(ts))
        return SSeq.seq_fresh(ts)

# sequence.json, written fresh first when it does not exist.
def ensure_seq(+root: String, +ts: String) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    m : Maybe<&2, Json.Json> <- read_seq(root)
    ensure_seq2(m, root, ts)

def decoded(+m: Maybe<&2, String>) -> String:
  SSeq.str_or(m, "")

def read_cred2(+ex: Bool, +path: String) -> Act.of(String):
  match ex:
    case False{}:
      Act.pure(String, "")
    case True{}:
      do ActM<String>:
        text : String <- Fs.read_file(path)
        return decoded(B64.decode(String.trim(text)))

# A slot's stored credential: the decoded text, "" when absent or undecodable.
def read_cred(+root: String, +slot: String, +email: String) -> Act.of(String):
  do ActM<String>:
    ex : Bool <- Act.lift(Bool, Fs.exists(SBase.enc_path(root, slot, email)))
    read_cred2(ex, SBase.enc_path(root, slot, email))

def keep_prev(+keep: Bool, +root: String, +slot: String, +email: String, +cur: String) -> Act.of(Unit):
  Act.cond(Unit, keep, write_secret(SBase.prev_path(root, slot, email), B64.encode(cur)), Act.pure(Unit, Unit{}))

# Store a slot's credential (0600). The generation it replaces is kept as
# `.enc.prev` when it was readable and different.
def write_cred(+root: String, +slot: String, +email: String, +creds: String) -> Act.of(Unit):
  do ActM<Unit>:
    +cur : String <- read_cred(root, slot, email)
    keep_prev(SBase.nonempty(cur) && SBase.not_(String.eq(cur, creds)), root, slot, email, cur)
    write_secret(SBase.enc_path(root, slot, email), B64.encode(creds))

def write_config(+root: String, +slot: String, +email: String, +text: String) -> Act.of(Unit):
  write_secret(SBase.config_path(root, slot, email), text)

def read_config(+root: String, +slot: String, +email: String) -> Act.of(String):
  Fs.read_file(SBase.config_path(root, slot, email))

# ---- archiving: a slot's files are moved aside, never deleted ----------------------

def mv_keep2(+ex: Bool, +src: String, +dst: String) -> Act.of(Unit):
  match ex:
    case False{}:
      Act.pure(Unit, Unit{})
    case True{}:
      do ActM<Unit>:
        FsW.rename(src, dst)
        FsW.chmod("600", dst)

def mv_keep(+src: String, +dst: String) -> Act.of(Unit):
  do ActM<Unit>:
    ex : Bool <- Act.lift(Bool, Fs.exists(src))
    mv_keep2(ex, src, dst)

# Move the slot's .enc (and .prev, legacy copy, config) under .removed/ with a
# UTC time stamp. This is where `remove` and every slot displacement send a
# credential: the reference deletes them, which lost the only full login once.
def archive_dirs(+root: String) -> Act.of(Unit):
  do ActM<Unit>:
    secure_dir(SBase.removed_dir(root))
    secure_dir(SBase.removed_configs_dir(root))

def archive_mv(+root: String, +slot: String, +email: String, +ts: String) -> Act.of(Unit):
  do ActM<Unit>:
    mv_keep(SBase.enc_path(root, slot, email), SBase.removed_enc_path(root, ts, slot, email))
    mv_keep(SBase.prev_path(root, slot, email), SBase.removed_enc_path(root, ts, slot, email) ++ ".prev")
    mv_keep(SBase.enc_path(root, "None", email), SBase.removed_enc_path(root, ts, "None", email))
    mv_keep(SBase.config_path(root, slot, email), SBase.removed_config_path(root, ts, slot, email))

def archive_slot(+root: String, +slot: String, +email: String, +ts: String) -> Act.of(Unit):
  do ActM<Unit>:
    archive_dirs(root)
    archive_mv(root, slot, email, ts)
    log(root, "INFO", "Archived slot " ++ slot ++ " (" ++ email ++ ") to " ++ SBase.removed_enc_path(root, ts, slot, email) ++ "; credentials are moved aside, never deleted")

def slot_email2(+m: Maybe<&2, Json.Json>) -> String:
  match m:
    case None{}:
      ""
    case Some{r}:
      SSeq.field_str(r, "email")

def slot_email(+seq: Json.Json, +num: String) -> String:
  slot_email2(SSeq.slot_record(seq, num))

# Archive a slot's files and forget its record; sequence.json is rewritten.
def drop_slot(+root: String, +seq: Json.Json, +num: String, +ts: String) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    archive_slot(root, num, slot_email(seq, num), ts)
    +next : Json.Json = SSeq.stamp(SSeq.drop_account(seq, num), ts)
    write_seq(root, next)
    return next

def drop_opt(+root: String, +seq: Json.Json, +m: Maybe<&2, String>, +ts: String) -> Act.of(Json.Json):
  match m:
    case None{}:
      Act.pure(Json.Json, seq)
    case Some{n}:
      drop_slot(root, seq, n, ts)

# Archive what a displaced and a migrated slot held, in that order.
def drop_pair(+root: String, +seq: Json.Json, +displace: Maybe<&2, String>, +migrate: Maybe<&2, String>, +ts: String) -> Act.of(Json.Json):
  do ActM<Json.Json>:
    s1 : Json.Json <- drop_opt(root, seq, displace, ts)
    drop_opt(root, s1, migrate, ts)
