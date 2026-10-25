import Base
import ../../src/tui/run.bend as Tui

# `cswap tui` on its own, for tests/tui_it.sh.

def rest(args: List<String>) -> List<String>:
  match args:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      t

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), a => Tui.main(rest(a), "cswap-bend 0.0.1"))
