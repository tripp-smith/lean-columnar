import Init.Data.ByteArray
import Columnar.Parquet.Encoding.Rle
import Columnar.Parquet.Encoding.Plain
import Columnar.Thrift.CompactWriter

namespace Columnar.Parquet.Writer.Encode.Levels

abbrev Err := Except String

open Columnar.Parquet.Encoding.Rle
open Columnar.Parquet.Encoding.Plain (PlainValue)
open Columnar.Thrift (uleb128)

private def prefixU32LE (innerLen : Nat) : ByteArray :=
  Columnar.Thrift.writeUInt32LE (UInt32.ofNat innerLen)

private partial def writeUIntLEWidth.go (x : Nat) (k : Nat) (acc : ByteArray) : ByteArray :=
  if k == 0 then acc
  else writeUIntLEWidth.go (x >>> 8) (k - 1) (acc.push (UInt8.ofNat (x &&& 0xff)))

private def writeUIntLEWidth (v : Nat) (byteWidth : Nat) : ByteArray :=
  writeUIntLEWidth.go v byteWidth ByteArray.empty

partial def findRunEnd (defs : Array Nat) (v : Nat) (j : Nat) (fuel : Nat) : Nat :=
  if fuel == 0 then j
  else if h : j < defs.size then
    if defs[j]'h == v then findRunEnd defs v (j + 1) (fuel - 1) else j
  else j

/-- Split `defs` into constant runs `(value, length)`. -/
partial def splitRuns (defs : Array Nat) (start : Nat) (acc : Array (Nat × Nat)) : Array (Nat × Nat) :=
  if h : start < defs.size then
    let v := defs[start]'h
    let endIdx := findRunEnd defs v (start + 1) defs.size
    splitRuns defs endIdx (acc.push (v, endIdx - start))
  else
    acc

/-- Hybrid body without u32 prefix. -/
private def encodeRleRuns (defs : Array Nat) (byteWidth : Nat) : ByteArray :=
  let runs := splitRuns defs 0 #[]
  runs.foldl (fun acc pr =>
    let (v, runLen) := pr
    let hdr := 2 * runLen
    acc ++ uleb128 hdr ++ writeUIntLEWidth v byteWidth) ByteArray.empty

/-- Definition levels (RLE/Hybrid) with u32 LE length prefix for data page v1. -/
def encodeDefinitionLevels (defs : Array Nat) (maxDef : Nat) : Err ByteArray := do
  let bw := packBitWidth maxDef
  if bw == 0 then
    pure ByteArray.empty
  else
    let byteWidth := (bw + 7) / 8
    let inner := encodeRleRuns defs byteWidth
    pure (prefixU32LE inner.size ++ inner)

def buildDefinitionLevels (cells : Array (Option PlainValue)) (maxDef : Nat) : Array Nat :=
  if maxDef == 0 then #[]
  else
    cells.foldl (fun acc ov =>
      match ov with
      | none | some .null => acc.push 0
      | some _ => acc.push maxDef) #[]

end Columnar.Parquet.Writer.Encode.Levels
