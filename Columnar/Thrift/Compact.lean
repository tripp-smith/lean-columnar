import Init.Data.ByteArray
import Columnar.Core.Result
import Columnar.Core.Bytes
import Columnar.Core.Bits

open Columnar

/-! Minimal Apache Thrift *Compact* protocol reader (structs, lists, primitives). -/

namespace Columnar.Thrift

structure TReader where
  bytes : ByteArray
  pos : Nat
  deriving Inhabited

def TReader.readByte (tr : TReader) : P (UInt8 × TReader) :=
  if h : tr.pos < tr.bytes.size then
    let b := tr.bytes.get tr.pos h
    return (b, { tr with pos := tr.pos + 1 })
  else
    throw "Thrift: unexpected EOF"

def TReader.readBytes (tr : TReader) (len : Nat) : P (ByteArray × TReader) :=
  if _ : tr.pos + len ≤ tr.bytes.size then
    let slice := tr.bytes.extract tr.pos (tr.pos + len)
    return (slice, { tr with pos := tr.pos + len })
  else
    throw "Thrift: readBytes past end"

def TReader.readI32LE (tr : TReader) : P (Int32 × TReader) := do
  let (raw, tr) ← tr.readBytes 4
  match Columnar.ByteArrayOps.readInt32LE raw 0 with
  | none => throw "Thrift: i32"
  | some v => return (v, tr)

def TReader.readI64LE (tr : TReader) : P (Int64 × TReader) := do
  let (raw, tr) ← tr.readBytes 8
  match Columnar.ByteArrayOps.readInt64LE raw 0 with
  | none => throw "Thrift: i64"
  | some v => return (v, tr)

def TReader.readDoubleLE (tr : TReader) : P (Float × TReader) := do
  let (raw, tr) ← tr.readBytes 8
  match Columnar.ByteArrayOps.readFloat64LE raw 0 with
  | none => throw "Thrift: double"
  | some v => return (v, tr)

def TReader.readULEB (tr : TReader) : P (UInt64 × TReader) := do
  let (v, newPos) ← readULEB128 tr.bytes tr.pos
  return (v, { tr with pos := newPos })

def TReader.readZigZag32 (tr : TReader) : P (Int32 × TReader) := do
  let (v, newPos) ← readZigZagInt32 tr.bytes tr.pos
  return (v, { tr with pos := newPos })

def TReader.readZigZag64 (tr : TReader) : P (Int64 × TReader) := do
  let (v, newPos) ← readZigZagInt64 tr.bytes tr.pos
  return (v, { tr with pos := newPos })

def TReader.readBinary (tr : TReader) : P (ByteArray × TReader) := do
  let (lenU, tr) ← tr.readULEB
  let len := lenU.toNat
  tr.readBytes len

def TReader.readString (tr : TReader) : P (String × TReader) := do
  let (bin, tr) ← tr.readBinary
  match String.fromUTF8? bin with
  | none => throw "Thrift: invalid UTF-8"
  | some s => return (s, tr)

/-- Field header: `none` = STOP; `some (fid, type, tr)` -/
def TReader.readFieldHeader (tr : TReader) (lastId : Int32) : P (Option (Int32 × UInt8) × TReader) := do
  let (b, tr) ← tr.readByte
  if b == 0 then return (none, tr)
  let t := b &&& 0x0f
  let delta4 := (b >>> 4).toUInt32
  if delta4 != 0 then
    let fid := lastId + Int32.ofUInt32 delta4
    return (some (fid, t), tr)
  else
    let (fid, tr) ← tr.readZigZag32
    return (some (fid, t), tr)

inductive TValue where
  | tbool (b : Bool)
  | ti32 (n : Int32)
  | ti64 (n : Int64)
  | tdouble (d : Float)
  | tbinary (b : ByteArray)
  | tstring (s : String)
  | tlist (elemType : UInt8) (xs : Array TValue)
  | tstruct (fields : Array (Nat × TValue))
  deriving Inhabited

partial def readTValue (typeId : UInt8) (tr : TReader) : P (TValue × TReader) :=
  match typeId.toNat with
  | 1 => return (TValue.tbool true, tr)
  | 2 => return (TValue.tbool false, tr)
  | 5 => do let (n, tr) ← tr.readZigZag32; return (TValue.ti32 n, tr)
  | 6 => do let (n, tr) ← tr.readZigZag64; return (TValue.ti64 n, tr)
  | 7 => do let (d, tr) ← tr.readDoubleLE; return (TValue.tdouble d, tr)
  | 8 => do let (bin, tr) ← tr.readBinary; return (TValue.tbinary bin, tr)
  | 9 =>
    do
      let (hb, tr) ← tr.readByte
      let elemType := hb &&& 0x0f
      let sizeHi := (hb >>> 4).toNat
      let (len, tr) ←
        if sizeHi != 15 then pure (sizeHi, tr)
        else do let (u, tr) ← tr.readULEB; pure (u.toNat, tr)
      let mut tr := tr
      let mut xs : Array TValue := #[]
      for _ in List.range len do
        match readTValue elemType tr with
        | .error e => throw e
        | .ok (v, tr') =>
          xs := xs.push v
          tr := tr'
      return (TValue.tlist elemType xs, tr)
  | 12 =>
    let rec go (tr : TReader) (lastId : Int32) (acc : Array (Nat × TValue)) : P (TValue × TReader) := do
      let (hdr, tr) ← tr.readFieldHeader lastId
      match hdr with
      | none => return (TValue.tstruct acc, tr)
      | some (fid, ty) =>
        let (v, tr) ← readTValue ty tr
        go tr fid (acc.push (Int32.toNatClampNeg fid, v))
    go tr 0 #[]
  | _ => throw s!"Thrift: unsupported compact type {typeId.toNat}"

end Columnar.Thrift
