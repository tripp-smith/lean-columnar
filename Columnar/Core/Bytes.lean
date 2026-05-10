import Init.Data.ByteArray
import Init.Data.Float
import Init.Data.Float32

namespace Columnar.ByteArrayOps

private def getU8 (b : ByteArray) (i : Nat) (h : i < b.size) : UInt8 :=
  b.get i h

/-- One byte at `i`, or `0` if out of range (bounded decoder offsets remain sound). -/
def readU8 (b : ByteArray) (i : Nat) : UInt8 :=
  if h : i < b.size then getU8 b i h else 0

def readUInt32LE (b : ByteArray) (off : Nat) : Option UInt32 :=
  if _ : off + 4 ≤ b.size then
    some <|
      (readU8 b off).toUInt32 |||
      ((readU8 b (off + 1)).toUInt32 <<< 8) |||
      ((readU8 b (off + 2)).toUInt32 <<< 16) |||
      ((readU8 b (off + 3)).toUInt32 <<< 24)
  else none

def readUInt32BE (b : ByteArray) (off : Nat) : Option UInt32 :=
  if _ : off + 4 ≤ b.size then
    some <|
      ((readU8 b off).toUInt32 <<< 24) |||
      ((readU8 b (off + 1)).toUInt32 <<< 16) |||
      ((readU8 b (off + 2)).toUInt32 <<< 8) |||
      (readU8 b (off + 3)).toUInt32
  else none

def readUInt64LE (b : ByteArray) (off : Nat) : Option UInt64 :=
  if _ : off + 8 ≤ b.size then
    some <|
      (readU8 b off).toUInt64 |||
      ((readU8 b (off + 1)).toUInt64 <<< 8) |||
      ((readU8 b (off + 2)).toUInt64 <<< 16) |||
      ((readU8 b (off + 3)).toUInt64 <<< 24) |||
      ((readU8 b (off + 4)).toUInt64 <<< 32) |||
      ((readU8 b (off + 5)).toUInt64 <<< 40) |||
      ((readU8 b (off + 6)).toUInt64 <<< 48) |||
      ((readU8 b (off + 7)).toUInt64 <<< 56)
  else none

def readInt32LE (b : ByteArray) (off : Nat) : Option Int32 :=
  match readUInt32LE b off with
  | none => none
  | some u => some (UInt32.toInt32 u)

def readInt64LE (b : ByteArray) (off : Nat) : Option Int64 :=
  match readUInt64LE b off with
  | none => none
  | some u => some (UInt64.toInt64 u)

def readFloat64LE (b : ByteArray) (off : Nat) : Option Float :=
  match readUInt64LE b off with
  | none => none
  | some u => some (Float.ofBits u)

def readFloat32LE (b : ByteArray) (off : Nat) : Option Float :=
  match readUInt32LE b off with
  | none => none
  | some u => some (Float32.ofBits u).toFloat

end Columnar.ByteArrayOps
