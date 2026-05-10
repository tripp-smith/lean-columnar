import Init.Data.ByteArray
import Columnar.Core.Bytes

namespace Columnar.Arrow.Flatbuf

open Columnar.ByteArrayOps

/-- Follow a `uoffset_t` stored at `slot` (relative to `slot` itself, Arrow / FlatBuffers wire rule used here). -/
def followUOffset (b : ByteArray) (slot : Nat) : Option Nat :=
  if slot + 4 ≤ b.size then
    match readUInt32LE b slot with
    | none => none
    | some u => some (slot + u.toNat)
  else none

def readUInt16LE (b : ByteArray) (off : Nat) : Option UInt16 :=
  if off + 2 ≤ b.size then
    some <|
      (readU8 b off).toUInt16 |||
      ((readU8 b (off + 1)).toUInt16 <<< 8)
  else none

def readInt16LE (b : ByteArray) (off : Nat) : Option Int16 :=
  match readUInt16LE b off with
  | none => none
  | some u => some (UInt16.toInt16 u)

/-- Vtable address for a table object at `obj` (first `soffset_t` points backward). -/
def tableVtable (b : ByteArray) (obj : Nat) : Option Nat := do
  let so ← readInt32LE b obj
  let d := Int32.toInt so
  if d ≤ 0 then none
  else pure (obj - Int.toNat d)

def vtableSizes (b : ByteArray) (vtable : Nat) : Option (Nat × Nat) := do
  let vs ← readUInt16LE b vtable
  let os ← readUInt16LE b (vtable + 2)
  pure (vs.toNat, os.toNat)

/-- Number of field slots in vtable (excluding the two size words). -/
def vtableFieldSlotCount (vtableSizeBytes : Nat) : Nat :=
  if vtableSizeBytes < 4 then 0 else (vtableSizeBytes - 4) / 2

def vtableFieldOffset (b : ByteArray) (vtable : Nat) (fieldIdx : Nat) : Option Nat := do
  let (vs, _) ← vtableSizes b vtable
  let n := vtableFieldSlotCount vs
  if fieldIdx ≥ n then none
  else
    let fo ← readUInt16LE b (vtable + 4 + fieldIdx * 2)
    if fo.toNat == 0 then none else pure fo.toNat

def fieldAddr (obj : Nat) (vtableRel : Nat) : Nat :=
  obj + vtableRel

def readStringFromSlot (b : ByteArray) (obj : Nat) (vtableRel : Nat) : Option String := do
  let slot := fieldAddr obj vtableRel
  let vstart ← followUOffset b slot
  if vstart + 4 > b.size then none
  else
    match readUInt32LE b vstart with
    | none => none
    | some lenU =>
      let len := lenU.toNat
      let start := vstart + 4
      if start + len > b.size then none
      else String.fromUTF8? (b.extract start (start + len))

def readI64 (b : ByteArray) (off : Nat) : Option Int64 :=
  readInt64LE b off

def readI32 (b : ByteArray) (off : Nat) : Option Int32 :=
  readInt32LE b off

end Columnar.Arrow.Flatbuf
