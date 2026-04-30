import Init.Data.ByteArray
import Columnar.Core.Result
import Columnar.Core.Bytes
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

def decodeOne (phys : Nat) (b : ByteArray) (off : Nat) : P (PlainValue × Nat) :=
  if phys == PhysType.boolean then
    if h : off < b.size then
      let v := b.get off h
      pure (.bool (v != 0), off + 1)
    else throw "PLAIN bool EOF"
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
  else
    throw s!"PLAIN: unsupported physical type {phys}"

def decodeColumn (phys : Nat) (b : ByteArray) (start : Nat) (count : Nat) : P (Array PlainValue) := do
  let mut off := start
  let mut acc : Array PlainValue := #[]
  for _ in List.range count do
    let (v, off') ← decodeOne phys b off
    acc := acc.push v
    off := off'
  return acc

end Columnar.Parquet.Encoding.Plain
