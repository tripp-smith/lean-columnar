import Init.Data.ByteArray
import Columnar.Core.Bytes

namespace Columnar.Orc.RleV2

open Columnar.ByteArrayOps

abbrev P := Except String

/-- ORC `decodeBitWidth` for `fbo` in DIRECT/DELTA/PATCHED headers (subset matching tiny integers). -/
def decodeBitWidth (fbo : Nat) : Nat :=
  if fbo > 0 && fbo < 25 then fbo + 1
  else if fbo == 24 then 32
  else 0

private def unZigZagUInt64 (v : UInt64) : Int64 :=
  let x := v >>> 1
  let mask : UInt64 := if v &&& 1 == 1 then 0xffffffffffffffff else 0
  UInt64.toInt64 (x ^^^ mask)

private partial def readPackedInt32Literals (b : ByteArray) (start : Nat) (nRows : Nat) (bytesPer : Nat)
    : P (Array Int32) :=
  let need := start + nRows * bytesPer
  if need > b.size then throw "ORC RLEv2: truncated literal run"
  else
    let rec gatherBytes (k : Nat) (vv : UInt64) (pp : Nat) : Nat × UInt64 :=
      if k == 0 then (pp, vv)
      else gatherBytes (k - 1) ((vv <<< 8) ||| (readU8 b pp).toUInt64) (pp + 1)
    let rec go (idx : Nat) (p : Nat) (acc : Array Int32) : P (Array Int32) :=
      if idx == nRows then pure acc
      else
        let (p2, vv) := gatherBytes bytesPer 0 p
        let z := unZigZagUInt64 vv
        go (idx + 1) p2 (acc.push z.toInt32)
    go 0 start #[]

/-- Decode signed int32 column DATA stream (RLE v2), no nulls, DIRECT encoding only.

Covers tiny ORC files where integers are stored as DIRECT runs with byte-aligned widths
multiple of 8 (e.g. 8-bit zigzag literals), matching `interop_orc_int32.orc`. -/
def decodeInt32DataNoNulls (b : ByteArray) (nRows : Nat) : P (Array Int32) :=
  if b.size < 2 then throw "ORC RLEv2: buffer too small"
  else
    let first := readU8 b 0
    let enc := (first.toNat >>> 6) &&& 3
    if enc != 1 then throw s!"ORC RLEv2: only DIRECT encoding supported (enc={enc})"
    else
      let fbo := (first.toNat >>> 1) &&& 0x1f
      let bitW := decodeBitWidth fbo
      if bitW == 0 || bitW % 8 != 0 then throw s!"ORC RLEv2: unsupported bit width {bitW}"
      else
        let rlLow := first.toNat &&& 1
        let rlHigh := (readU8 b 1).toNat
        let runLen := rlLow * 256 + rlHigh + 1
        if runLen < nRows then throw s!"ORC RLEv2: run length {runLen} < rows {nRows}"
        else
          let bytesPer := bitW / 8
          readPackedInt32Literals b 2 nRows bytesPer

end Columnar.Orc.RleV2
