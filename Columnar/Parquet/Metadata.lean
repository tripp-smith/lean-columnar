import Init.Data.ByteArray
import Columnar.Core.Result
import Columnar.Core.Bytes
import Columnar.Thrift.Compact
import Columnar.Parquet.Types

open Columnar

namespace Columnar.Parquet

structure SchemaElement where
  name : Option String
  physType : Option Nat
  repetition : Option Nat
  numChildren : Option Int32
  deriving Repr

structure ColumnMetaDataParsed where
  physType : Nat
  path : Array String
  codec : Nat
  numValues : Nat
  dataPageOffset : Nat
  dictPageOffset : Option Nat
  encodings : Array Nat
  deriving Repr

structure ColumnChunkParsed where
  columnMeta : ColumnMetaDataParsed
  deriving Repr

structure RowGroupParsed where
  columns : Array ColumnChunkParsed
  numRows : Nat

structure FileMetaDataParsed where
  version : Int32
  schema : Array SchemaElement
  numRows : Nat
  rowGroups : Array RowGroupParsed

def thriftField (fields : Array (Nat × Thrift.TValue)) (id : Nat) : Option Thrift.TValue :=
  fields.findSome? fun (k, v) => if k == id then some v else none

def expectList (tv : Thrift.TValue) : P (Array Thrift.TValue) :=
  match tv with
  | .tlist _ xs => return xs
  | _ => throw "expected list"

def expectI32 (tv : Thrift.TValue) : P Int32 :=
  match tv with
  | .ti32 n => return n
  | _ => throw "expected i32"

def expectBool (tv : Thrift.TValue) : P Bool :=
  match tv with
  | .tbool b => return b
  | _ => throw "expected bool"

def expectI64 (tv : Thrift.TValue) : P Int64 :=
  match tv with
  | .ti64 n => return n
  | _ => throw "expected i64"

def expectString (tv : Thrift.TValue) : P String :=
  match tv with
  | .tstring s => return s
  | .tbinary b =>
    match String.fromUTF8? b with
    | none => throw "invalid utf8"
    | some s => return s
  | _ => throw "expected string"

def int32ToNat (i : Int32) : Nat := Int32.toNatClampNeg i

def int64ToNat (i : Int64) : Nat := Int64.toNatClampNeg i

def parseSchemaElement (tv : Thrift.TValue) : P SchemaElement := do
  let fields ←
    match tv with
    | .tstruct fs => pure fs
    | _ => throw "schema element: expected struct"
  let phys ←
    match thriftField fields 1 with
    | none => pure none
    | some v => do let i ← expectI32 v; pure (some (int32ToNat i))
  let repetition ←
    match thriftField fields 3 with
    | none => pure none
    | some v => do let i ← expectI32 v; pure (some (int32ToNat i))
  let name ←
    match thriftField fields 4 with
    | none => pure none
    | some v => do let s ← expectString v; pure (some s)
  let numChildren ←
    match thriftField fields 5 with
    | none => pure none
    | some v => do let i ← expectI32 v; pure (some i)
  return { physType := phys, repetition := repetition, name := name, numChildren := numChildren }

def parseColumnMetaData (tv : Thrift.TValue) : P ColumnMetaDataParsed := do
  let fields ←
    match tv with
    | .tstruct fs => pure fs
    | _ => throw "ColumnMetaData: struct expected"
  let pt ← expectI32 (← match thriftField fields 1 with | some v => pure v | none => throw "type")
  let pathTv ← match thriftField fields 3 with | some v => pure v | none => throw "path"
  let pathList ← expectList pathTv
  let mut path : Array String := #[]
  for p in pathList do
    path := path.push (← expectString p)
  let codec ← expectI32 (← match thriftField fields 4 with | some v => pure v | none => throw "codec")
  let numValues ← expectI64 (← match thriftField fields 5 with | some v => pure v | none => throw "num_values")
  let dpo ← expectI64 (← match thriftField fields 9 with | some v => pure v | none => throw "data_page_offset")
  let dictOffset ←
    match thriftField fields 11 with
    | none => pure none
    | some v => do let i ← expectI64 v; pure (some (int64ToNat i))
  let encTv ← match thriftField fields 2 with | some v => pure v | none => throw "encodings"
  let encList ← expectList encTv
  let mut encodings : Array Nat := #[]
  for e in encList do
    encodings := encodings.push (int32ToNat (← expectI32 e))
  return {
    physType := int32ToNat pt
    path := path
    codec := int32ToNat codec
    numValues := int64ToNat numValues
    dataPageOffset := int64ToNat dpo
    dictPageOffset := dictOffset
    encodings := encodings
  }

def parseColumnChunk (tv : Thrift.TValue) : P ColumnChunkParsed := do
  let fields ←
    match tv with
    | .tstruct fs => pure fs
    | _ => throw "ColumnChunk: struct"
  let colMetaTv ← match thriftField fields 3 with | some v => pure v | none => throw "meta_data"
  let colMeta ← parseColumnMetaData colMetaTv
  return { columnMeta := colMeta }

def parseRowGroup (tv : Thrift.TValue) : P RowGroupParsed := do
  let fields ←
    match tv with
    | .tstruct fs => pure fs
    | _ => throw "RowGroup: struct"
  let colsTv ← match thriftField fields 1 with | some v => pure v | none => throw "columns"
  let cols ← expectList colsTv
  let mut columns : Array ColumnChunkParsed := #[]
  for c in cols do
    columns := columns.push (← parseColumnChunk c)
  let nr ← expectI64 (← match thriftField fields 3 with | some v => pure v | none => throw "num_rows")
  return { columns := columns, numRows := int64ToNat nr }

def parseFileMetaData (footerBytes : ByteArray) : P FileMetaDataParsed := do
  let tr : Thrift.TReader := { bytes := footerBytes, pos := 0 }
  let (root, _) ← Thrift.readTValue 12 tr
  let fields ←
    match root with
    | .tstruct fs => pure fs
    | _ => throw "FileMetaData root"
  let ver ← expectI32 (← match thriftField fields 1 with | some v => pure v | none => throw "version")
  let schemaTv ← match thriftField fields 2 with | some v => pure v | none => throw "schema"
  let schemaList ← expectList schemaTv
  let mut schema : Array SchemaElement := #[]
  for s in schemaList do
    schema := schema.push (← parseSchemaElement s)
  let numRows ← expectI64 (← match thriftField fields 3 with | some v => pure v | none => throw "num_rows")
  let rgTv ← match thriftField fields 4 with | some v => pure v | none => throw "row_groups"
  let rgList ← expectList rgTv
  let mut rgs : Array RowGroupParsed := #[]
  for rg in rgList do
    rgs := rgs.push (← parseRowGroup rg)
  return {
    version := ver
    schema := schema
    numRows := int64ToNat numRows
    rowGroups := rgs
  }

def readFooterBytes (file : ByteArray) : P ByteArray := do
  let n := file.size
  if n < 8 then throw "file too small for parquet footer"
  let magic := file.extract (n - 4) n
  let expected := ByteArray.mk #[0x50, 0x41, 0x52, 0x31]
  if magic != expected then throw "invalid PAR1 magic"
  match Columnar.ByteArrayOps.readUInt32LE file (n - 8) with
  | none => throw "footer length"
  | some lenU =>
    let len := lenU.toNat
    if len > n - 8 then throw "invalid footer length"
    let start := n - 8 - len
    return file.extract start (n - 8)

end Columnar.Parquet
