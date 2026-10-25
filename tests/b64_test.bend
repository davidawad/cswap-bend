import Base
import ../src/b64.bend as B64

# RFC 4648 section 10 vectors, both directions.

def enc_empty() -> {B64.encode("") == "" : String}:
  {==}

def enc_f() -> {B64.encode("f") == "Zg==" : String}:
  {==}

def enc_fo() -> {B64.encode("fo") == "Zm8=" : String}:
  {==}

def enc_foo() -> {B64.encode("foo") == "Zm9v" : String}:
  {==}

def enc_foob() -> {B64.encode("foob") == "Zm9vYg==" : String}:
  {==}

def enc_fooba() -> {B64.encode("fooba") == "Zm9vYmE=" : String}:
  {==}

def enc_foobar() -> {B64.encode("foobar") == "Zm9vYmFy" : String}:
  {==}

def dec_empty() -> {B64.decode("") == Some{""} : Maybe<&2, String>}:
  {==}

def dec_f() -> {B64.decode("Zg==") == Some{"f"} : Maybe<&2, String>}:
  {==}

def dec_fo() -> {B64.decode("Zm8=") == Some{"fo"} : Maybe<&2, String>}:
  {==}

def dec_foobar() -> {B64.decode("Zm9vYmFy") == Some{"foobar"} : Maybe<&2, String>}:
  {==}

def dec_fooba() -> {B64.decode("Zm9vYmE=") == Some{"fooba"} : Maybe<&2, String>}:
  {==}

# Alphabet edges: 62 is +, 63 is / (bytes 0xFB 0xFF 0xBF).
def enc_alphabet() -> {B64.encode_bytes([251, 255, 191]) == "+/+/" : String}:
  {==}

def dec_alphabet() -> {B64.decode_bytes("+/+/") == Some{[251, 255, 191]} : Maybe<&2, List<&2, U32>>}:
  {==}

# Whitespace (a wrapped file) is ignored.
def dec_newline() -> {B64.decode("Zm9v\nYmFy\n") == Some{"foobar"} : Maybe<&2, String>}:
  {==}

def dec_bad_char() -> {B64.decode("Zm9*") == None{} : Maybe<&2, String>}:
  {==}

def dec_short() -> {B64.decode("Zm9vY") == None{} : Maybe<&2, String>}:
  {==}

# UTF-8 round trip: e-acute (2 bytes), euro (3), U+1F600 (4).
def enc_utf8() -> {B64.encode("é€😀") == "w6nigqzwn5iA" : String}:
  {==}

def rt_utf8() -> {B64.decode("w6nigqzwn5iA") == Some{"é€😀"} : Maybe<&2, String>}:
  {==}
