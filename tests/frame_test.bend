import Base
import ../src/frame.bend as Fr

# Ground equations for the rpc message framing.

def show(m: Maybe<&2, Fr.Cut>) -> String:
  match m:
    case None{}:
      "none"
    case Some{Fr.Cut{a, b}}:
      "[" ++ a ++ "|" ++ b ++ "]"

def l_one() -> {show(Fr.take(False{}, "{\"a\":1}\n{\"b\":2}\n")) == "[{\"a\":1}|{\"b\":2}\n]" : String}:
  {==}

def l_incomplete() -> {show(Fr.take(False{}, "{\"a\":1")) == "none" : String}:
  {==}

def l_empty_line() -> {show(Fr.take(False{}, "\nx\n")) == "[|x\n]" : String}:
  {==}

def l_crlf() -> {show(Fr.take(False{}, "a\r\nb")) == "[a\r|b]" : String}:
  {==}

def b_one() -> {show(Fr.take(True{}, "a: 1\nb: 2\n\nc: 3\n\n")) == "[a: 1\nb: 2\n|c: 3\n\n]" : String}:
  {==}

def b_incomplete() -> {show(Fr.take(True{}, "a: 1\nb: 2\n")) == "none" : String}:
  {==}

def b_crlf() -> {show(Fr.take(True{}, "a: 1\r\n\r\nb: 2")) == "[a: 1\r\n\r|b: 2]" : String}:
  {==}

def b_leading_blank() -> {show(Fr.take(True{}, "\n\na: 1\n\n")) == "[|\na: 1\n\n]" : String}:
  {==}

def b_none() -> {show(Fr.take(True{}, "")) == "none" : String}:
  {==}

def blank_yes() -> {Fr.blank(" \r\n\t") == True{} : Bool}:
  {==}

def blank_no() -> {Fr.blank(" x ") == False{} : Bool}:
  {==}
