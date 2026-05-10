import Init.Data.ByteArray
import Columnar.Core.Result
import Columnar.Core.Bits
import Columnar.Core.Bytes

open Columnar

namespace Columnar.Parquet.Encoding.Rle

private def uget (b : ByteArray) (i : Nat) : UInt8 :=
  if h : i < b.size then b.get i h else 0

def readUIntLEWidth (b : ByteArray) (pos : Nat) (byteWidth : Nat) : P (UInt64 × Nat) := do
  if pos + byteWidth > b.size then throw "readUIntLEWidth: EOF"
  let mut v : UInt64 := 0
  let mut p := pos
  for k in [:byteWidth] do
    v := v ||| ((uget b p).toUInt64 <<< UInt64.ofNat (8 * k))
    p := p + 1
  return (v, p)

/-- Parquet RLE/bit-pack hybrid. If `explicitBitWidth` is `some w`, the packed body is run data only (used for
repetition/definition levels with a u32 length prefix). If `none`, the first body byte is the bit width
(dictionary indices, booleans, etc.). -/
partial def decodeHybrid (b : ByteArray) (start : Nat) (totalValues : Nat) (hasLengthPrefix : Bool)
    (explicitBitWidth : Option Nat) : P (Array Nat) := do
  let (bodyStart, bodyEnd) ←
    if hasLengthPrefix then
      if start + 4 > b.size then throw "RLE: len prefix"
      else
        match Columnar.ByteArrayOps.readUInt32LE b start with
        | none => throw "RLE: u32"
        | some lenU =>
          let len := lenU.toNat
          let bs := start + 4
          if bs + len > b.size then throw "RLE: body OOB"
          pure (bs, bs + len)
    else
      pure (start, b.size)
  if bodyStart >= bodyEnd then throw "RLE: empty body"
  let (bitWidth, dataStart) ← match explicitBitWidth with
    | none =>
      let w := (uget b bodyStart).toNat
      pure (w, bodyStart + 1)
    | some w => pure (w, bodyStart)
  if bitWidth > 64 then throw "RLE: bitWidth"
  if bitWidth == 0 then
    let mut a : Array Nat := #[]
    for _ in [:totalValues] do
      a := a.push 0
    return a
  let byteWidth := (bitWidth + 7) / 8

  let rec go (out : Array Nat) (bytePos : Nat) (fuel : Nat) : P (Array Nat) := do
    if out.size >= totalValues then return out
    if fuel == 0 then throw "RLE: fuel exhausted"
    if bytePos > bodyEnd then throw "RLE: overrun"
    let (hdr, pos1) ← readULEB128 b bytePos
    if hdr &&& 1 == 0 then
      let runLen := hdr.toNat >>> 1
      let (v, pos2) ← readUIntLEWidth b pos1 byteWidth
      let take := Nat.min runLen (totalValues - out.size)
      let mut out := out
      for _ in [:take] do
        out := out.push v.toNat
      go out pos2 (fuel - 1)
    else
      let groupCount := hdr.toNat >>> 1
      let nVals := groupCount * 8
      let take := Nat.min nVals (totalValues - out.size)
      let mut br : BitReader := ⟨b, pos1, 0, 0⟩
      let mut out := out
      for _ in [:take] do
        let (bits, br') ← BitReader.readBits br bitWidth
        br := br'
        out := out.push bits.toNat
      let brDone := BitReader.byteAlign br
      go out brDone.bytePos (fuel - 1)

  go #[] dataStart (totalValues + (bodyEnd - bodyStart) + 32)

/-- Smallest `w` such that `2^w ≥ maxLevel + 1` (distinct level values); used by level encodings (Parquet thrift `Encoding`).
When `maxLevel == 0` callers skip decoding; returning `0` is safe. -/
partial def packBitWidthAux (bound pw w : Nat) : Nat :=
  if pw ≥ bound then w else packBitWidthAux bound (pw * 2) (w + 1)

def packBitWidth (maxLevel : Nat) : Nat :=
  if maxLevel == 0 then 0 else packBitWidthAux (maxLevel + 1) 1 0

private def readGlobBitMSB (b : ByteArray) (glob : Nat) : P Nat := do
  let bi := glob / 8
  let r := glob % 8
  if bi < b.size then
    let byte := (uget b bi).toNat
    pure (((byte >>> (7 - r)) &&& 1))
  else
    throw "RLE: bit-packed levels OOB"

/-- Deprecated `BIT_PACKED` (enum 4) for repetition/definition levels: MSB-first packing, no length prefix. -/
def decodeBitPackedDeprecatedLevels (b : ByteArray) (cursor slots maxLevel : Nat) : P (Array Nat × Nat) := do
  if slots == 0 then return (#[], cursor)
  let bw := packBitWidth maxLevel
  if bw == 0 then throw "RLE: bit-packed levels width 0 with maxLevel>0"
  let totalBits := slots * bw
  let totalBytes := (totalBits + 7) / 8
  let spanEnd := cursor + totalBytes
  if spanEnd > b.size then throw "RLE: bit-packed levels span OOB"
  let body := b.extract cursor spanEnd
  let mut out : Array Nat := #[]
  for i in [:slots] do
    let startGlob := i * bw
    let mut v : Nat := 0
    for j in [:bw] do
      let bit ← readGlobBitMSB body (startGlob + j)
      v := Nat.shiftLeft v 1 ||| bit
    out := out.push v
  pure (out, spanEnd)

/-- Byte-exclusive end offset of the Hybrid RLE/Bit-Pack block embedded in slice at `start`
(when prefixed with UInt32 LE length, skips `4 + length` bytes from `start`). -/
def hybridEncodedSpanExclusive (b : ByteArray) (start : Nat) (hasLengthPrefix : Bool) : P Nat := do
  let (_, bodyEnd) ←
    if hasLengthPrefix then
      if start + 4 > b.size then throw "RLE: len prefix"
      else
        match Columnar.ByteArrayOps.readUInt32LE b start with
        | none => throw "RLE: u32"
        | some lenU =>
          let len := lenU.toNat
          let bs := start + 4
          if bs + len > b.size then throw "RLE: body OOB"
          pure (bs, bs + len)
    else
      pure (start, b.size)
  pure bodyEnd

end Columnar.Parquet.Encoding.Rle
