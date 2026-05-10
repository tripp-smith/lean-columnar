import Init.Data.ByteArray
import Init.Data.Float32
import Columnar.Core.Bytes
import Columnar.Parquet.Types
import Columnar.Parquet.Encoding.Plain

open Columnar.Parquet
open Columnar.Parquet.Encoding.Plain

namespace Columnar.Parquet.Writer.Encode.Plain

abbrev Err := Except String

def physMatches (phys : Nat) (pv : PlainValue) : Bool :=
  match pv with
  | .bool _ => phys == PhysType.boolean
  | .int32 _ => phys == PhysType.int32
  | .int64 _ => phys == PhysType.int64
  | .float _ => phys == PhysType.float
  | .double _ => phys == PhysType.double
  | .byteArray _ => phys == PhysType.byteArray
  | .null => false

/-- Values for PLAIN payload (non-null slots only when `maxDef > 0`). -/
def extractPlainPhysical (phys : Nat) (cells : Array (Option PlainValue)) (maxDef : Nat) : Err (Array PlainValue) :=
  if maxDef == 0 then
    cells.mapM fun ov =>
      match ov with
      | none => throw "writeParquet: null cell in REQUIRED column"
      | some .null => throw "writeParquet: PlainValue.null in REQUIRED column"
      | some pv =>
        if physMatches phys pv then pure pv else throw "writeParquet: physical type mismatch"
  else do
    let mut acc : Array PlainValue := #[]
    for ov in cells do
      match ov with
      | none | some .null => pure ()
      | some pv =>
        unless physMatches phys pv do throw "writeParquet: physical type mismatch"
        acc := acc.push pv
    pure acc

/-- Little-endian packing for PLAIN `UInt32` payloads (shared by lemmas). -/
def appendUInt32LE (a : ByteArray) (u : UInt32) : ByteArray :=
  let n := u.toNat
  (((a.push (UInt8.ofNat (n &&& 0xff))).push (UInt8.ofNat ((n >>> 8) &&& 0xff))).push
      (UInt8.ofNat ((n >>> 16) &&& 0xff))).push (UInt8.ofNat ((n >>> 24) &&& 0xff))

private def appendUInt64LE (a : ByteArray) (u : UInt64) : ByteArray :=
  let n := u.toNat
  let a1 := a.push (UInt8.ofNat (n &&& 0xff))
  let a2 := a1.push (UInt8.ofNat ((n >>> 8) &&& 0xff))
  let a3 := a2.push (UInt8.ofNat ((n >>> 16) &&& 0xff))
  let a4 := a3.push (UInt8.ofNat ((n >>> 24) &&& 0xff))
  let a5 := a4.push (UInt8.ofNat ((n >>> 32) &&& 0xff))
  let a6 := a5.push (UInt8.ofNat ((n >>> 40) &&& 0xff))
  let a7 := a6.push (UInt8.ofNat ((n >>> 48) &&& 0xff))
  a7.push (UInt8.ofNat ((n >>> 56) &&& 0xff))

/-- LSB-first packing within each byte (matches `decodePlainBoolsPacked`). -/
def encodePlainBoolsPacked (vals : Array PlainValue) : Err ByteArray := do
  let mut out : ByteArray := ByteArray.empty
  let mut buf : Nat := 0
  let mut nbits : Nat := 0
  for i in [:vals.size] do
    match vals[i]? with
    | none => throw "writeParquet: bool pack internal"
    | some (.bool b) =>
      let bit := if b then 1 else 0
      buf := buf ||| (bit <<< nbits)
      nbits := nbits + 1
      if nbits == 8 then
        out := out.push (UInt8.ofNat buf)
        buf := 0
        nbits := 0
    | some _ => throw "writeParquet: expected bool in BOOLEAN column"
  if nbits > 0 then
    out := out.push (UInt8.ofNat buf)
  pure out

def encodePlainOne (phys : Nat) (v : PlainValue) : Err ByteArray := do
  match v with
  | .bool b =>
    unless phys == PhysType.boolean do throw "PLAIN: bool"
    encodePlainBoolsPacked #[.bool b]
  | .int32 i =>
    unless phys == PhysType.int32 do throw "PLAIN: int32"
    pure (appendUInt32LE ByteArray.empty i.toUInt32)
  | .int64 i =>
    unless phys == PhysType.int64 do throw "PLAIN: int64"
    pure (appendUInt64LE ByteArray.empty i.toUInt64)
  | .float f =>
    unless phys == PhysType.float do throw "PLAIN: float"
    pure (appendUInt32LE ByteArray.empty (Float32.toBits (Float.toFloat32 f)))
  | .double f =>
    unless phys == PhysType.double do throw "PLAIN: double"
    pure (appendUInt64LE ByteArray.empty (Float.toBits f))
  | .byteArray b =>
    unless phys == PhysType.byteArray do throw "PLAIN: byte_array"
    pure (appendUInt32LE ByteArray.empty (UInt32.ofNat b.size) ++ b)
  | .null => throw "PLAIN: unexpected null PlainValue"

/-- Concatenate PLAIN encodings for a run of defined values. -/
def encodePlain (phys : Nat) (vals : Array PlainValue) : Err ByteArray := do
  if phys == PhysType.boolean then
    encodePlainBoolsPacked vals
  else
    let mut acc := ByteArray.empty
    for v in vals do
      let chunk ← encodePlainOne phys v
      acc := acc ++ chunk
    pure acc

end Columnar.Parquet.Writer.Encode.Plain
