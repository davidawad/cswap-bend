import Base
import ../../src/daemon/entry.bend as Entry

# A driver that speaks the CLI's `auto` argv, for tests/daemon_it.sh and the
# parity replay of fixtures 21-31 and 33:
#   daemon-it auto [--once] [--json] [--dry-run] [--threshold T] [--model M]
#                  [--strategy S] [--interval N] [--cooldown N]
#                  [--include-api-key-accounts]

def dup(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      []
    case Con{+h, t}:
      h <> dup(t)

def run(args: List<String>) -> IO(Unit):
  match args:
    case Con{prog, Con{cmd, rest}}:
      Entry.auto_main(dup(rest), "cswap-bend 0.0.1")
    case _:
      IO.die(Unit, 2, "usage: daemon-it auto [flags]")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), run)
