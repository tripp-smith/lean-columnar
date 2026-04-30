import Init.Data.ByteArray
import Columnar.Core.Result

namespace Columnar

private def getU8 (b : ByteArray) (i : Nat) (h : i < b.size) : UInt8 :=
  b.get i h

/-- Unsigned LEB128 (Thrift / Parquet varint). -/
def readULEB128 (b : ByteArray) (i : Nat) : P (UInt64 × Nat) := do
  let mut pos := i
  let mut shift : Nat := 0
  let mut result : Nat := 0
  for _ in List.range 10 do
    if h : pos < b.size then
      let byte := (getU8 b pos h).toNat
      pos := pos + 1
      result := result ||| Nat.shiftLeft (byte &&& 0x7f) shift
      if (byte &&& 0x80) == 0 then
        return (UInt64.ofNat result, pos)
      shift := shift + 7
    else
      throw "ULEB128: unexpected EOF"
  throw "ULEB128: too long"

def zigzagDecode (z : UInt64) : Int64 :=
  let ui := z >>> 1
  if z &&& 1 == 0 then
    Int64.ofUInt64 ui
  else
    -Int64.ofUInt64 ui - 1

def readZigZagInt64 (b : ByteArray) (i : Nat) : P (Int64 × Nat) := do
  let (u, j) ← readULEB128 b i
  return (zigzagDecode u, j)

def readZigZagInt32 (b : ByteArray) (i : Nat) : P (Int32 × Nat) := do
  let (x, j) ← readZigZagInt64 b i
  return (x.toInt32, j)

/-- Bit reader with `Nat` buffer (low `bitsInBuffer` bits valid). -/
structure BitReader where
  data : ByteArray
  bytePos : Nat
  buffer : Nat
  bitsInBuffer : Nat
  deriving Inhabited

def BitReader.refill (br : BitReader) : P BitReader :=
  if h : br.bytePos < br.data.size then
    let byte := (getU8 br.data br.bytePos h).toNat
    return {
      br with
        bytePos := br.bytePos + 1
        buffer := br.buffer ||| Nat.shiftLeft byte br.bitsInBuffer
        bitsInBuffer := br.bitsInBuffer + 8
    }
  else
    throw "BitReader: EOF"

def BitReader.refillWhile (br : BitReader) (need : Nat) : P BitReader := do
  let mut br := br
  let fuel := br.data.size - br.bytePos + 16
  for _ in List.range fuel do
    if br.bitsInBuffer >= need then
      return br
    br ← br.refill
  if br.bitsInBuffer < need then throw "BitReader: incomplete" else return br

def BitReader.byteAlign (br : BitReader) : BitReader :=
  let r := br.bitsInBuffer % 8
  if r == 0 then br
  else { br with buffer := Nat.shiftRight br.buffer r, bitsInBuffer := br.bitsInBuffer - r }

def BitReader.readBits (br : BitReader) (n : Nat) : P (UInt64 × BitReader) := do
  if n > 64 then throw "BitReader.readBits: n > 64"
  let br ← br.refillWhile n
  if br.bitsInBuffer < n then
    throw "BitReader: insufficient bits"
  else
    let mask :=
      if n == 64 then
        (Nat.shiftLeft 1 64) - 1
      else
        (Nat.shiftLeft 1 n) - 1
    let vNat := br.buffer &&& mask
    let v := UInt64.ofNat vNat
    let br :=
      { br with
        buffer := Nat.shiftRight br.buffer n
        bitsInBuffer := br.bitsInBuffer - n }
    return (v, br)

end Columnar
