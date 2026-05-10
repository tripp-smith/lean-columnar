import Init.Data.ByteArray
import Columnar.Core.Bytes
import Columnar.Avro.Schema
import Columnar.Parquet.Encoding.Plain

namespace Columnar.Avro.Binary

open Columnar.ByteArrayOps
open Columnar.Parquet.Encoding.Plain

abbrev P := Except String

private def natFromNonNegInt64 (x : Int64) : Nat :=
  Int.natAbs (Int64.toInt x)

partial def readUnsignedVarLong (b : ByteArray) (pos : Nat) : P (UInt64 × Nat) :=
  if pos ≥ b.size then throw "Avro varlong: truncated"
  else
    let rec step (acc : UInt64) (shift : Nat) (p : Nat) : P (UInt64 × Nat) :=
      if p ≥ b.size then throw "Avro varlong: truncated"
      else
        let byte := (ByteArrayOps.readU8 b p).toUInt64
        let acc' := acc ||| ((byte &&& 0x7f) <<< UInt64.ofNat shift)
        if byte &&& 0x80 != 0 then
          step acc' (shift + 7) (p + 1)
        else
          pure (acc', p + 1)
    step 0 0 pos

def zigzagToInt64 (u : UInt64) : Int64 :=
  let x := u >>> 1
  let mask : UInt64 := if u &&& 1 == 1 then 0xffffffffffffffff else 0
  UInt64.toInt64 (x ^^^ mask)

def readLong (b : ByteArray) (pos : Nat) : P (Int64 × Nat) := do
  let (u, p) ← readUnsignedVarLong b pos
  pure (zigzagToInt64 u, p)

def readInt (b : ByteArray) (pos : Nat) : P (Int32 × Nat) := do
  let (v, p) ← readUnsignedVarLong b pos
  let z := zigzagToInt64 v
  pure (z.toInt32, p)

def readFloat (b : ByteArray) (pos : Nat) : P (Float × Nat) :=
  if pos + 4 ≤ b.size then
    match ByteArrayOps.readFloat32LE b pos with
    | none => throw "Avro float: bad offset"
    | some f => pure (f, pos + 4)
  else throw "Avro float: truncated"

def readDouble (b : ByteArray) (pos : Nat) : P (Float × Nat) :=
  if pos + 8 ≤ b.size then
    match ByteArrayOps.readFloat64LE b pos with
    | none => throw "Avro double: bad offset"
    | some f => pure (f, pos + 8)
  else throw "Avro double: truncated"

/-- Avro string and bytes lengths are encoded as zigzag `long`, not raw unsigned varlong. -/
def readString (b : ByteArray) (pos : Nat) : P (String × Nat) := do
  let (lenL, p0) ← readLong b pos
  if lenL < 0 then throw "Avro string: negative length"
  let len := natFromNonNegInt64 lenL
  if p0 + len > b.size then throw "Avro string: truncated"
  let slice := b.extract p0 (p0 + len)
  match String.fromUTF8? slice with
  | none => throw "Avro string: invalid UTF-8"
  | some s => pure (s, p0 + len)

def readBytes (b : ByteArray) (pos : Nat) : P (ByteArray × Nat) := do
  let (lenL, p0) ← readLong b pos
  if lenL < 0 then throw "Avro bytes: negative length"
  let len := natFromNonNegInt64 lenL
  if p0 + len > b.size then throw "Avro bytes: truncated"
  pure (b.extract p0 (p0 + len), p0 + len)

def readBool (b : ByteArray) (pos : Nat) : P (Bool × Nat) :=
  if pos < b.size then
    let v := ByteArrayOps.readU8 b pos
    if v == 0 then pure (false, pos + 1)
    else if v == 1 then pure (true, pos + 1)
    else throw "Avro bool: expected 0 or 1"
  else throw "Avro bool: truncated"

partial def decodeValue (ty : AvroType) (b : ByteArray) (pos : Nat) : P (PlainValue × Nat) :=
  match ty with
  | .null => pure (.null, pos)
  | .boolean => do let (x, p) ← readBool b pos; pure (.bool x, p)
  | .int => do let (n, p) ← readInt b pos; pure (.int32 n, p)
  | .long => do let (n, p) ← readLong b pos; pure (.int64 n, p)
  | .float => do let (f, p) ← readFloat b pos; pure (.float f, p)
  | .double => do let (f, p) ← readDouble b pos; pure (.double f, p)
  | .string => do
    let (s, p) ← readString b pos
    pure (.byteArray s.toUTF8, p)
  | .bytes => do let (ba, p) ← readBytes b pos; pure (.byteArray ba, p)
  | .union opts => do
    let (idx, p1) ← readLong b pos
    if idx < 0 then throw "Avro union: negative branch"
    let i := Int.natAbs (Int64.toInt idx)
    if h : i < opts.length then
      decodeValue (opts.get ⟨i, h⟩) b p1
    else throw "Avro union: branch index out of range"
  | .array _ => throw "Avro: array value not supported for Table decode"
  | .map _ => throw "Avro: map value not supported for Table decode"
  | .record .. => throw "Avro: nested record value — use decodeRecordRow"

/-- Decode record row as column-aligned field values. -/
partial def decodeRecordRow (schema : AvroType) (b : ByteArray) (pos : Nat) : P (Array PlainValue × Nat) :=
  match schema with
  | .record _ fs =>
    let rec go (rest : List (String × AvroType)) (p : Nat) (acc : Array PlainValue) : P (Array PlainValue × Nat) :=
      match rest with
      | [] => pure (acc, p)
      | (_, ft) :: tl => do
        let (v, p1) ← decodeValue ft b p
        go tl p1 (acc.push v)
    go fs pos #[]
  | _ => throw "Avro decodeRecordRow: root must be record"

end Columnar.Avro.Binary
