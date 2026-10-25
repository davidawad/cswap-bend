import Base
import ../../src/clock.bend as Clock

def report(+t: U32) -> IO(Unit):
  IO.print(U32.show(t) ++ " " ++ Clock.iso8601_utc(t))

def main() -> IO(Unit):
  do IO<Unit>:
    t : U32 <- Clock.now_s()
    report(t)
