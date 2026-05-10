import Init.Data.ByteArray
import Columnar.Core.Result
import Columnar.Parquet.Types
import Columnar.Parquet.Encoding.Plain
import Columnar.Parquet.Encoding.Rle

namespace Columnar.Parquet.Encoding.Dictionary

abbrev P := Except String

open Columnar.Parquet.Encoding.Rle

/-- Decode indices for dictionary-encoded columns (PLAIN int32 strips or Hybrid RLE int bitwidth). -/
def decodeIndicesPlain (b : ByteArray) (start : Nat) (count : Nat) : P (Array UInt32) := do
  let mut off := start
  let mut xs : Array UInt32 := #[]
  for _ in [:count] do
    match Columnar.ByteArrayOps.readUInt32LE b off with
    | none => throw "dict indices LE32 eof"
    | some u =>
      xs := xs.push u
      off := off + 4
  return xs

def decodeIndicesHybrid (b : ByteArray) (start : Nat) (count : Nat) : P (Array Nat) :=
  -- Spec: no u32 length prefix on dictionary index runs; some writers still emit it (Impala legacy).
  -- Body includes leading bit-width byte (`explicitBitWidth := none`).
  match decodeHybrid b start count false none with
  | Except.ok r => pure r
  | Except.error _ => decodeHybrid b start count true none


def resolve (dict : Array PlainValue) (idx : UInt32) : P PlainValue :=
  let i := idx.toNat
  match dict[i]? with
  | none => throw "dict index OOB"
  | some v => pure v

end Columnar.Parquet.Encoding.Dictionary
