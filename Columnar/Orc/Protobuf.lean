import Init.Data.ByteArray
import Columnar.Core.Bytes

namespace Columnar.Orc.Protobuf

open Columnar.ByteArrayOps

abbrev P := Except String

/-- Decode protobuf varint (unsigned); returns value and new offset. -/
partial def readVarUInt64 (b : ByteArray) (pos : Nat) : P (UInt64 × Nat) :=
  if pos ≥ b.size then throw "ORC protobuf: truncated varint"
  else
    let rec step (acc : UInt64) (shift : Nat) (p : Nat) : P (UInt64 × Nat) :=
      if p ≥ b.size then throw "ORC protobuf: truncated varint"
      else
        let byte := (readU8 b p).toUInt64
        let acc' := acc ||| ((byte &&& 0x7f) <<< UInt64.ofNat shift)
        if byte &&& 0x80 != 0 then
          step acc' (shift + 7) (p + 1)
        else
          pure (acc', p + 1)
    step 0 0 pos

/-- Read tag (fieldNum << 3 | wireType). -/
def readTag (b : ByteArray) (pos : Nat) : P (Nat × Nat) := do
  let (t, p) ← readVarUInt64 b pos
  let tn := t.toNat
  pure (tn, p)

def wireType (tag : Nat) : Nat :=
  tag &&& 0x7

def fieldNumber (tag : Nat) : Nat :=
  tag >>> 3

/-- Skip one protobuf field starting at pos; returns new pos. -/
partial def skipField (b : ByteArray) (pos : Nat) (wire : Nat) : P Nat :=
  match wire with
  | 0 => do let (_, p) ← readVarUInt64 b pos; pure p
  | 1 => if pos + 8 ≤ b.size then pure (pos + 8) else throw "ORC protobuf: skip 64-bit"
  | 2 => do
    let (len, p) ← readVarUInt64 b pos
    let l := len.toNat
    if p + l > b.size then throw "ORC protobuf: bad length-delimited"
    pure (p + l)
  | 5 => if pos + 4 ≤ b.size then pure (pos + 4) else throw "ORC protobuf: skip 32-bit"
  | _ => throw "ORC protobuf: unsupported wire type"

/-- Walk message bytes until field `wantField` (varint) is found; return its UInt64 value. -/
partial def findVarintField (b : ByteArray) (pos : Nat) (endPos : Nat) (wantField : Nat) : P UInt64 :=
  if pos ≥ endPos then throw "ORC protobuf: field not found"
  else do
    let (tag, p1) ← readTag b pos
    let w := wireType tag
    let fn := fieldNumber tag
    if fn == wantField && w == 0 then
      let (v, p2) ← readVarUInt64 b p1
      if p2 ≤ endPos then pure v else throw "ORC protobuf: overrun"
    else do
      let p2 ← skipField b p1 w
      findVarintField b p2 endPos wantField

end Columnar.Orc.Protobuf
