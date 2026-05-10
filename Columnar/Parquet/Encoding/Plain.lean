import Init.Data.ByteArray
import Columnar.Core.Result
import Columnar.Core.Bytes
import Columnar.Core.Bits
import Columnar.Parquet.Types

open Columnar
open Columnar.Parquet

namespace Columnar.Parquet.Encoding.Plain

inductive PlainValue where
  | null
  | bool (b : Bool)
  | int32 (n : Int32)
  | int64 (n : Int64)
  | float (f : Float)
  | double (f : Float)
  | byteArray (b : ByteArray)

abbrev P := Except String

/-- PLAIN physical booleans are bit-packed LSB-first across bytes (Parquet spec). -/
def decodePlainBoolsPacked (b : ByteArray) (start : Nat) (count : Nat) : P (Array PlainValue) := do
  let mut br : BitReader := ⟨b, start, 0, 0⟩
  let mut acc : Array PlainValue := #[]
  for _ in [:count] do
    let (bit, br') ← BitReader.readBits br 1
    br := br'
    acc := acc.push (.bool (bit.toNat != 0))
  pure acc

def decodeOne (phys : Nat) (b : ByteArray) (off : Nat) : P (PlainValue × Nat) :=
  if phys == PhysType.boolean then
    throw "PLAIN bool: use decodePlainBoolsPacked or RLE hybrid for data pages"
  else if phys == PhysType.int32 then
    match ByteArrayOps.readInt32LE b off with
    | none => throw "PLAIN int32"
    | some n => pure (.int32 n, off + 4)
  else if phys == PhysType.int64 then
    match ByteArrayOps.readInt64LE b off with
    | none => throw "PLAIN int64"
    | some n => pure (.int64 n, off + 8)
  else if phys == PhysType.float then
    match ByteArrayOps.readFloat32LE b off with
    | none => throw "PLAIN float"
    | some f => pure (.float f, off + 4)
  else if phys == PhysType.double then
    match ByteArrayOps.readFloat64LE b off with
    | none => throw "PLAIN double"
    | some f => pure (.double f, off + 8)
  else if phys == PhysType.byteArray then
    match ByteArrayOps.readUInt32LE b off with
    | none => throw "PLAIN byte_array len"
    | some lenU =>
      let len := lenU.toNat
      let start := off + 4
      if start + len > b.size then throw "PLAIN byte_array data"
      else pure (.byteArray (b.extract start (start + len)), start + len)
  else if phys == PhysType.int96 then
    let len := 12
    let start := off
    if start + len > b.size then throw "PLAIN int96 EOF"
    else pure (.byteArray (b.extract start (start + len)), start + len)
  else if phys == PhysType.fixedLenByteArray then
    throw "PLAIN: fixedLenByteArray needs column metadata FLBA width (not wired)"
  else
    throw s!"PLAIN: unsupported physical type {phys}"

def decodeColumn (phys : Nat) (b : ByteArray) (start : Nat) (count : Nat) : P (Array PlainValue) := do
  if phys == PhysType.boolean then decodePlainBoolsPacked b start count
  else
    let mut off := start
    let mut acc : Array PlainValue := #[]
    for _ in [:count] do
      let (v, off') ← decodeOne phys b off
      acc := acc.push v
      off := off'
    return acc

/-- Decode sequentially until exhaustion (dictionary pages usually PLAIN payloads). -/
partial def decodeColumnDrain (phys : Nat) (b : ByteArray) (start : Nat) : P (Array PlainValue) := do
  if start ≥ b.size then pure #[]
  else if phys == PhysType.boolean then do
    let bits := (b.size - start) * 8
    decodePlainBoolsPacked b start bits
  else do
    let (v, off') ← decodeOne phys b start
    let rest ← decodeColumnDrain phys b off'
    pure (#[v].append rest)

/-- Fixed physical width bytes for BSS / primitives (PLAIN). -/
def physWidth (phys : Nat) : Nat :=
  if phys == PhysType.boolean then 1
  else if phys == PhysType.int32 || phys == PhysType.float then 4
  else if phys == PhysType.double || phys == PhysType.int64 then 8
  else if phys == PhysType.int96 then 12
  else 1

end Columnar.Parquet.Encoding.Plain
