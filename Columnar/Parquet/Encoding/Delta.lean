import Init.Data.ByteArray
import Columnar.Core.Result
import Columnar.Core.Bits
import Columnar.Parquet.Types
import Columnar.Parquet.Encoding.Plain

/-! DELTA_BINARY_PACKED per parquet-format `Encodings.md`. -/

namespace Columnar.Parquet.Encoding.Delta

abbrev P := Except String

open Columnar
open Plain

private def emitInt (physBytes : Nat) (v : Int64) : PlainValue :=
  if physBytes == 4 then .int32 (Int64.toInt32 v) else .int64 v

private def bump (physBytes : Nat) (prev : Int64) (packed : UInt64) (minDelta : Int64) : Int64 × PlainValue :=
  let dd := Int64.ofUInt64 packed + minDelta
  let v := prev + dd
  (v, emitInt physBytes v)

/-- Iterative miniblock unpack (slot count can be in the hundreds; recursion overflowed the test binary). -/
private def unpackMB
    (physBytes bw slots : Nat) (br : BitReader) (fuel : Nat)
    (prev : Int64) (minDelta : Int64) (out : Array PlainValue) :
    P (Array PlainValue × BitReader × Int64) := do
  if fuel < slots then throw "DELTA_BINARY_PACKED: decode fuel"
  let mut out := out
  let mut br := br
  let mut prev := prev
  for _ in [:slots] do
    if bw == 0 then
      let (next, pv) := bump physBytes prev 0 minDelta
      out := out.push pv
      prev := next
    else
      let (bits, br1) ← BitReader.readBits br bw
      let (next, pv) := bump physBytes prev bits minDelta
      out := out.push pv
      br := br1
      prev := next
  return (out, br, prev)

private partial def consumeBlock
    (slice : ByteArray) (physBytes miniN perMini blockSize : Nat)
    (acc : Array PlainValue) (last : Int64) (pos remain : Nat) :
    P (Array PlainValue × Nat × Int64 × Nat) :=
  if remain == 0 then pure (acc, pos, last, 0)
  else do
    let (minDelta, q1) ← readZigZagInt64 slice pos
    let mut pos := q1
    let mut widths : Array Nat := #[]
    for _ in [:miniN] do
      if h : pos < slice.size then
        widths := widths.push (slice.get pos h).toNat
        pos := pos + 1
      else throw "DELTA_BINARY_PACKED: width byte EOF"
    let blockCap := Nat.min blockSize remain
    let mut produced := 0
    let mut br : BitReader := ⟨slice, pos, 0, 0⟩
    let mut acc := acc
    let mut last := last
    for k in [:miniN] do
      unless produced ≥ blockCap do
        let bw := (widths[k]?).getD 0
        let take := Nat.min perMini (blockCap - produced)
        let (chunk, br1, lst) ←
          unpackMB physBytes bw take br (take * (bw + 4) + 8) last minDelta #[]
        acc := acc ++ chunk
        last := lst
        br := BitReader.byteAlign br1
        produced := produced + take
    pure (acc, br.bytePos, last, produced)

/-- Iterative tail (no deep recursion) so large mini-blocks cannot overflow the native stack. -/
private partial def decodeBinaryPackedIter
    (slice : ByteArray) (physBytes miniN perMini blockSize : Nat)
    (first : Int64) (p3 : Nat) (tv : Nat) : P (Array PlainValue) :=
  Id.run do
    let mut acc : Array PlainValue := #[emitInt physBytes first]
    let mut pos := p3
    let mut remain := tv - 1
    let mut last := first
    let mut fuel := tv + 16
    while fuel > 0 do
      fuel := fuel - 1
      if remain == 0 then
        return Except.ok acc
      match consumeBlock slice physBytes miniN perMini blockSize acc last pos remain with
      | Except.error e => return Except.error e
      | Except.ok (acc', pos', last', used) =>
        if remain > 0 && used == 0 then
          return Except.error "DELTA_BINARY_PACKED: no progress (check block_size / miniblock layout)"
        acc := acc'
        pos := pos'
        last := last'
        remain := remain - used
    return Except.error "DELTA_BINARY_PACKED: fuel exhausted"

def decodeBinaryPacked (slice : ByteArray) (physBytes : Nat) (expectedVals : Nat) : P (Array PlainValue) :=
  if !(physBytes == 4 || physBytes == 8) then throw "DELTA_BINARY_PACKED: width"
  else do
    let (bsU, p0) ← readULEB128 slice 0
    let (miniU, p1) ← readULEB128 slice p0
    let (tvU, p2) ← readULEB128 slice p1
    let (first, p3) ← readZigZagInt64 slice p2
    let blockSize := bsU.toNat
    let miniN := miniU.toNat
    let tv := tvU.toNat
    if tv != expectedVals then throw s!"DELTA count {tv}!={expectedVals}"
    if tv == 0 then pure #[]
    else if blockSize == 0 || miniN == 0 || blockSize % miniN != 0 then throw "DELTA_BINARY_PACKED: miniblock layout"
    else
      let perMini := blockSize / miniN
      decodeBinaryPackedIter slice physBytes miniN perMini blockSize first p3 tv

end Columnar.Parquet.Encoding.Delta
