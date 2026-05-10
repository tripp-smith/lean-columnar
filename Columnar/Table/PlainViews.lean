import Init.Data.Array.Subarray
import Columnar.Parquet.Encoding.Plain
import Columnar.Table

namespace Columnar.Table

open Columnar.Parquet.Encoding.Plain

/-- Pack little-endian bytes for one `UInt64` value. -/
private def UInt64.toByteArrayLE (u : UInt64) : ByteArray :=
  Id.run do
    let mut r := ByteArray.empty
    let mut x := u
    for _ in [:8] do
      r := r.push (UInt8.ofNat (UInt64.toNat (x &&& 255)))
      x := x >>> 8
    r

/-- Pack little-endian bytes for one `UInt32` value. -/
private def UInt32.toByteArrayLE (u : UInt32) : ByteArray :=
  Id.run do
    let mut r := ByteArray.empty
    let mut x := u
    for _ in [:4] do
      r := r.push (UInt8.ofNat (UInt32.toNat (x &&& 255)))
      x := x >>> 8
    r

private def byteArrayAppendByteArray (a b : ByteArray) : ByteArray :=
  b.foldl (fun acc u => acc.push u) a

private def byteArrayToUInt8Array (b : ByteArray) : Array UInt8 :=
  Array.ofFn fun (i : Fin b.size) => b.get! i.val

/-- Contiguous packed LE bytes when **every** row is a non-null `PlainValue.int64`.

Materializes one dense slab from boxed cells (post-decode). Use when definition levels are trivially
max (no nulls in column). -/
def Column.plainInt64PackedBytes? (c : Column) : Option ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    for v in c.values do
      match v with
      | none => return none
      | some (.int64 n) =>
        acc := byteArrayAppendByteArray acc (UInt64.toByteArrayLE (Int64.toUInt64 n))
      | some _ => return none
    some acc

/-- Same payload as `plainInt64PackedBytes?`, as `Subarray UInt8` over the packed slab. -/
def Column.plainInt64PackedSubarray? (c : Column) : Option (Subarray UInt8) :=
  match Column.plainInt64PackedBytes? c with
  | none => none
  | some b => some (byteArrayToUInt8Array b).toSubarray

/-- Same as `plainInt64PackedBytes?` for `PlainValue.int32`. -/
def Column.plainInt32PackedBytes? (c : Column) : Option ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    for v in c.values do
      match v with
      | none => return none
      | some (.int32 n) =>
        acc := byteArrayAppendByteArray acc (UInt32.toByteArrayLE (Int32.toUInt32 n))
      | some _ => return none
    some acc

def Column.plainInt32PackedSubarray? (c : Column) : Option (Subarray UInt8) :=
  match Column.plainInt32PackedBytes? c with
  | none => none
  | some b => some (byteArrayToUInt8Array b).toSubarray

end Columnar.Table
