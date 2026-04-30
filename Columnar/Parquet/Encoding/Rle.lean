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
  for k in List.range byteWidth do
    v := v ||| ((uget b p).toUInt64 <<< UInt64.ofNat (8 * k))
    p := p + 1
  return (v, p)

partial def decodeHybrid (b : ByteArray) (start : Nat) (totalValues : Nat) (hasLengthPrefix : Bool) : P (Array Nat) := do
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
  let bitWidth := (uget b bodyStart).toNat
  if bitWidth > 64 then throw "RLE: bitWidth"
  if bitWidth == 0 then
    let mut a : Array Nat := #[]
    for _ in List.range totalValues do
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
      for _ in List.range take do
        out := out.push v.toNat
      go out pos2 (fuel - 1)
    else
      let groupCount := hdr.toNat >>> 1
      let nVals := groupCount * 8
      let take := Nat.min nVals (totalValues - out.size)
      let mut br : BitReader := ⟨b, pos1, 0, 0⟩
      let mut out := out
      for _ in List.range take do
        let (bits, br') ← BitReader.readBits br bitWidth
        br := br'
        out := out.push bits.toNat
      let brDone := BitReader.byteAlign br
      go out brDone.bytePos (fuel - 1)

  go #[] (bodyStart + 1) (totalValues + (bodyEnd - bodyStart) + 32)

end Columnar.Parquet.Encoding.Rle
