import Base

# Standard base64 (RFC 4648, padded). `.creds-*.enc` files are the base64 of
# the credential JSON, so text goes through UTF-8 first.

# ---- UTF-8 ----------------------------------------------------------------

def utf8.cat.pick(a: Bool, b: Bool, d: Bool, +c: U32, rest: List<&2, U32>) -> List<&2, U32>:
  match a b d:
    case True{} _ _:
      c <> rest
    case False{} True{} _:
      (192 .|. (c >> 6n) : U32) <> (128 .|. (c .&. 63) : U32) <> rest
    case False{} False{} True{}:
      (224 .|. (c >> 12n) : U32) <> (128 .|. ((c >> 6n) .&. 63) : U32) <> (128 .|. (c .&. 63) : U32) <> rest
    case False{} False{} False{}:
      (240 .|. (c >> 18n) : U32) <> (128 .|. ((c >> 12n) .&. 63) : U32) <> (128 .|. ((c >> 6n) .&. 63) : U32) <> (128 .|. (c .&. 63) : U32) <> rest

def utf8.cat(+c: U32, rest: List<&2, U32>) -> List<&2, U32>:
  utf8.cat.pick(U32.is_lt(c, 128), U32.is_lt(c, 2048), U32.is_lt(c, 65536), c, rest)

# The UTF-8 bytes of a string.
def utf8.encode(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      []
    case SCon{Chr{c}, t}:
      utf8.cat(c, utf8.encode(t))

def sel(c: Bool, x: U32, y: U32) -> U32:
  match c:
    case True{}:
      x
    case False{}:
      y

def sel.b(c: Bool, x: Bool, y: Bool) -> Bool:
  match c:
    case True{}:
      x
    case False{}:
      y

# Continuation bytes a lead byte announces.
def utf8.len(+b: U32) -> U32:
  sel(U32.is_lt(b, 128), 0, sel(U32.is_lt(b, 224), 1, sel(U32.is_lt(b, 240), 2, 3)))

def utf8.mask(+n: U32) -> U32:
  sel(U32.is_eq(n, 0), 255, sel(U32.is_eq(n, 1), 31, sel(U32.is_eq(n, 2), 15, 7)))

# The decoder state is (need, cp): continuation bytes still due and the code
# point so far. These three give the next need, the next cp, and whether cp
# is complete.
def utf8.need(+b: U32, +need: U32) -> U32:
  sel(U32.is_eq(need, 0), utf8.len(b), (need - 1 : U32))

def utf8.cp(+b: U32, +need: U32, +cp: U32) -> U32:
  sel(U32.is_eq(need, 0), (b .&. utf8.mask(utf8.len(b)) : U32), ((cp << 6n) .|. (b .&. 63) : U32))

def utf8.emit(+b: U32, +need: U32) -> Bool:
  sel.b(U32.is_eq(need, 0), U32.is_eq(utf8.len(b), 0), U32.is_eq(need, 1))

def utf8.put(emit: Bool, c: U32, rest: String) -> String:
  match emit:
    case True{}:
      SCon{Chr{c}, rest}
    case False{}:
      rest

# Decode UTF-8 bytes (lenient on malformed input).
def utf8.decode.go(bs: List<&2, U32>, +need: U32, +cp: U32) -> String:
  match bs:
    case Nil{}:
      SNil{}
    case Con{+b, t}:
      +cp2 = utf8.cp(b, need, cp)
      utf8.put(utf8.emit(b, need), cp2, utf8.decode.go(t, utf8.need(b, need), cp2))

def utf8.decode(bs: List<&2, U32>) -> String:
  utf8.decode.go(bs, 0, 0)

# ---- base64 ---------------------------------------------------------------

def b64.char(+n: U32) -> Char:
  Chr{sel(U32.is_lt(n, 26), (n + 65 : U32),
    sel(U32.is_lt(n, 52), (n + 71 : U32),
    sel(U32.is_lt(n, 62), (n - 4 : U32),
    sel(U32.is_eq(n, 62), 43, 47))))}

def b64.enc.go(bs: List<&2, U32>) -> String:
  match bs:
    case Nil{}:
      SNil{}
    case Con{+a, Nil{}}:
      SCon{b64.char((a >> 2n : U32)), SCon{b64.char(((a .&. 3) << 4n : U32)), "=="}}
    case Con{+a, Con{+b, Nil{}}}:
      SCon{b64.char((a >> 2n : U32)), SCon{b64.char((((a .&. 3) << 4n) .|. (b >> 4n) : U32)),
        SCon{b64.char(((b .&. 15) << 2n : U32)), "="}}}
    case Con{+a, Con{+b, Con{+c, t}}}:
      SCon{b64.char((a >> 2n : U32)), SCon{b64.char((((a .&. 3) << 4n) .|. (b >> 4n) : U32)),
        SCon{b64.char((((b .&. 15) << 2n) .|. (c >> 6n) : U32)), SCon{b64.char((c .&. 63 : U32)),
        b64.enc.go(t)}}}}

# Base64 of the bytes.
def encode_bytes(bs: List<&2, U32>) -> String:
  b64.enc.go(bs)

# Base64 of the UTF-8 form of the text.
def encode(s: String) -> String:
  encode_bytes(utf8.encode(s))

# 0..63 the sextet, 64 for `=`, 255 for anything else.
def b64.val(+c: U32) -> U32:
  sel(U32.is_ge(c, 65) && U32.is_le(c, 90), (c - 65 : U32),
  sel(U32.is_ge(c, 97) && U32.is_le(c, 122), (c - 71 : U32),
  sel(U32.is_ge(c, 48) && U32.is_le(c, 57), (c + 4 : U32),
  sel(U32.is_eq(c, 43), 62,
  sel(U32.is_eq(c, 47), 63,
  sel(U32.is_eq(c, 61), 64, 255))))))

def b64.quad.emit(p3: Bool, p4: Bool, a: U32, b: U32, c: U32, r: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match p3 p4:
    case True{} _:
      Some{a <> r}
    case False{} True{}:
      Some{a <> b <> r}
    case False{} False{}:
      Some{a <> b <> c <> r}

def b64.quad.pick(ok: Bool, p3: Bool, p4: Bool, +w: U32, +x: U32, +y: U32, +z: U32,
  rest: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match ok rest:
    case False{} _:
      None{}
    case True{} None{}:
      None{}
    case True{} Some{r}:
      b64.quad.emit(p3, p4, ((w << 2n) .|. (x >> 4n) : U32), (((x .&. 15) << 4n) .|. (y >> 2n) : U32),
        (((y .&. 3) << 6n) .|. z : U32), r)

def b64.dec.quad(+w: U32, +x: U32, +y: U32, +z: U32, rest: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  b64.quad.pick(U32.is_lt(w, 64) && U32.is_lt(x, 64) && (U32.is_lt(y, 64) || U32.is_eq(y, 64)) && (U32.is_lt(z, 64) || U32.is_eq(z, 64)),
    U32.is_eq(y, 64), U32.is_eq(z, 64), w, x, y, z, rest)

# The next four characters of the input as sextets, or the end, or a bad tail.
type Quad is Data:
  QEnd{}
  QBad{}
  Q{w: U32, x: U32, y: U32, z: U32, rest: String}

def b64.quad.of4(c1: U32, c2: U32, c3: U32, s: String) -> Quad:
  match s:
    case SCon{Chr{c4}, t}:
      Q{b64.val(c1), b64.val(c2), b64.val(c3), b64.val(c4), t}
    case _:
      QBad{}

def b64.quad.of3(c1: U32, c2: U32, s: String) -> Quad:
  match s:
    case SCon{Chr{c3}, t}:
      b64.quad.of4(c1, c2, c3, t)
    case _:
      QBad{}

def b64.quad.of2(c1: U32, s: String) -> Quad:
  match s:
    case SCon{Chr{c2}, t}:
      b64.quad.of3(c1, c2, t)
    case _:
      QBad{}

def b64.quad.of(s: String) -> Quad:
  match s:
    case SNil{}:
      QEnd{}
    case SCon{Chr{c1}, t}:
      b64.quad.of2(c1, t)
    case _:
      QBad{}

# `fuel` is the input length, at least the number of quads.
def b64.dec.go(fuel: Nat, q: Quad) -> Maybe<&2, List<&2, U32>>:
  match fuel q:
    case _ QEnd{}:
      Some{[]}
    case _ QBad{}:
      None{}
    case 0n _:
      None{}
    case 1n+p Q{w, x, y, z, t}:
      b64.dec.quad(w, x, y, z, b64.dec.go(p, b64.quad.of(t)))

def b64.dec.start(+s: String) -> Maybe<&2, List<&2, U32>>:
  b64.dec.go(String.length(s), b64.quad.of(s))

def b64.strip.put(sp: Bool, c: Char, rest: String) -> String:
  match sp:
    case True{}:
      rest
    case False{}:
      SCon{c, rest}

def b64.strip(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      b64.strip.put(Char.is_space(c), c, b64.strip(t))

# Decode to bytes; None on a bad character, bad padding or a short tail.
def decode_bytes(s: String) -> Maybe<&2, List<&2, U32>>:
  b64.dec.start(b64.strip(s))

def b64.text(m: Maybe<&2, List<&2, U32>>) -> Maybe<&2, String>:
  match m:
    case None{}:
      None{}
    case Some{bs}:
      Some{utf8.decode(bs)}

# Decode to UTF-8 text.
def decode(s: String) -> Maybe<&2, String>:
  b64.text(decode_bytes(s))
