import Init.Data.ByteArray

namespace Columnar.Thrift

/-- Append-only Thrift *compact* protocol writer (structs, lists, primitives). Mirrors
`Columnar/Thrift/Compact.lean` read side. -/
abbrev Bytes := ByteArray

def empty : Bytes :=
  ByteArray.empty

def append (a : Bytes) (b : Bytes) : Bytes :=
  a ++ b

def pushUInt8 (a : Bytes) (u : UInt8) : Bytes :=
  a.push u

/-- Unsigned LEB128 (variable-length Nat payload). -/
partial def uleb128 (n : Nat) : Bytes :=
  let rec go (x : Nat) (acc : Bytes) : Bytes :=
    if x < 128 then
      acc.push (UInt8.ofNat x)
    else
      go (x >>> 7) (acc.push (UInt8.ofNat ((x &&& 0x7f) ||| 0x80)))
  go n empty

def zigZag32 (i : Int32) : UInt32 :=
  let u := i.toUInt32
  (u <<< 1) ^^^ (((u >>> 31) * UInt32.ofNat 0xffffffff))

def zigZag64 (i : Int64) : UInt64 :=
  let u := i.toUInt64
  (u <<< 1) ^^^ (((u >>> 63) * UInt64.ofNat 0xffffffffffffffff))

def writeZigZag32 (i : Int32) : Bytes :=
  uleb128 (zigZag32 i).toNat

def writeZigZag64 (i : Int64) : Bytes :=
  uleb128 (zigZag64 i).toNat

def writeBool (b : Bool) : Bytes :=
  pushUInt8 empty (if b then 1 else 2)

def writeUInt32LE (u : UInt32) : Bytes :=
  let n := u.toNat
  let b0 := pushUInt8 empty (UInt8.ofNat (n &&& 0xff))
  let b1 := pushUInt8 b0 (UInt8.ofNat ((n >>> 8) &&& 0xff))
  let b2 := pushUInt8 b1 (UInt8.ofNat ((n >>> 16) &&& 0xff))
  pushUInt8 b2 (UInt8.ofNat ((n >>> 24) &&& 0xff))

def writeUInt64LE (u : UInt64) : Bytes :=
  let n := u.toNat
  let b0 := pushUInt8 empty (UInt8.ofNat (n &&& 0xff))
  let b1 := pushUInt8 b0 (UInt8.ofNat ((n >>> 8) &&& 0xff))
  let b2 := pushUInt8 b1 (UInt8.ofNat ((n >>> 16) &&& 0xff))
  let b3 := pushUInt8 b2 (UInt8.ofNat ((n >>> 24) &&& 0xff))
  let b4 := pushUInt8 b3 (UInt8.ofNat ((n >>> 32) &&& 0xff))
  let b5 := pushUInt8 b4 (UInt8.ofNat ((n >>> 40) &&& 0xff))
  let b6 := pushUInt8 b5 (UInt8.ofNat ((n >>> 48) &&& 0xff))
  pushUInt8 b6 (UInt8.ofNat ((n >>> 56) &&& 0xff))

def writeInt32LE (i : Int32) : Bytes :=
  writeUInt32LE i.toUInt32

def writeInt64LE (i : Int64) : Bytes :=
  writeUInt64LE i.toUInt64

def writeDoubleLE (f : Float) : Bytes :=
  writeUInt64LE (Float.toBits f)

def writeBinary (b : Bytes) : Bytes :=
  append (uleb128 b.size) b

def writeString (s : String) : Bytes :=
  writeBinary s.toUTF8

/-- Thrift compact field types (subset used by Parquet metadata). -/
def ctBoolTrue : UInt8 := 1
def ctBoolFalse : UInt8 := 2
def ctI8 : UInt8 := 3
def ctI32 : UInt8 := 5
def ctI64 : UInt8 := 6
def ctDouble : UInt8 := 7
def ctBinary : UInt8 := 8
def ctList : UInt8 := 9
def ctStruct : UInt8 := 12

/-- Write field header; returns new `lastFieldId` (absolute id just written). -/
def writeFieldBegin (lastFieldId : Int32) (fieldId : Int32) (ty : UInt8) : Int32 × Bytes :=
  let lastNat := Int32.toNatClampNeg lastFieldId
  let fidNat := Int32.toNatClampNeg fieldId
  if fidNat > lastNat && fidNat - lastNat ≤ 15 then
    let delta := fidNat - lastNat
    let b := UInt8.ofNat ((delta <<< 4) ||| ty.toNat)
    (fieldId, pushUInt8 empty b)
  else
    let hdr := pushUInt8 empty (ty &&& 0x0f)
    (fieldId, append hdr (writeZigZag32 fieldId))

def writeFieldStop : Bytes :=
  pushUInt8 empty 0

/-- List header: element compact type + length (short form or ULEB when ≥ 15). -/
def writeListBegin (elemCt : UInt8) (len : Nat) : Bytes :=
  if len < 15 then
    pushUInt8 empty (UInt8.ofNat ((len <<< 4) ||| elemCt.toNat))
  else
    append (pushUInt8 empty (UInt8.ofNat ((15 <<< 4) ||| elemCt.toNat))) (uleb128 len)

def writeMapBegin (kt vt : UInt8) (len : Nat) : Bytes :=
  let hd :=
    if len == 0 then
      empty
    else
      pushUInt8 empty (UInt8.ofNat (((kt.toNat &&& 0x0f) <<< 4) ||| (vt.toNat &&& 0x0f)))
  append (append (uleb128 len) hd) empty

end Columnar.Thrift
