import Base
import ../src/fs.bend as Fs

# The pure parts of fs: the IO paths run in tests/fs_it.sh.

def names_drops_empty() -> {Fs.names(["a", "", "b"]) == ["a", "b"] : List<&2, String>}:
  {==}

def names_empty_list() -> {Fs.names([]) == [] : List<&2, String>}:
  {==}

def list_of_splits_lines() -> {Fs.list.of(Done{"x\ny\n"}) == Done{["x", "y"]} : Fs.Res(List<&2, String>)}:
  {==}

def list_of_keeps_failure() -> {Fs.list.of(Fail{(2, "gone")}) == Fail{(2, "gone")} : Fs.Res(List<&2, String>)}:
  {==}

def tool_zero_is_ok() -> {Fs.tool.out(Done{(0, ("out", ""))}) == Done{"out"} : Fs.Res(String)}:
  {==}

def tool_nonzero_fails_with_stderr() -> {Fs.tool.out(Done{(1, ("", "boom"))}) == Fail{(1, "boom")} : Fs.Res(String)}:
  {==}

def tool_spawn_failure_passes_through() -> {Fs.tool.out(Fail{(2, "no such file")}) == Fail{(2, "no such file")} : Fs.Res(String)}:
  {==}

def exists_status_zero() -> {Fs.exists.of(Done{(0, ("", ""))}) == True{} : Bool}:
  {==}

def exists_status_one() -> {Fs.exists.of(Done{(1, ("", ""))}) == False{} : Bool}:
  {==}

def dirname_nested() -> {Fs.dirname("a/b/c") == "a/b" : String}:
  {==}

def dirname_absolute() -> {Fs.dirname("/home/x/lock") == "/home/x" : String}:
  {==}

def dirname_root_child() -> {Fs.dirname("/x") == "/" : String}:
  {==}

def dirname_bare() -> {Fs.dirname("x") == "." : String}:
  {==}
