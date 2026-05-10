import Columnar.Thrift.CompactWriter
import Columnar.Parquet.Writer.Schema

namespace Columnar.Parquet.Writer.Footer

open Columnar.Thrift
open Columnar.Parquet.Writer

/-- One schema leaf (`SchemaElement`). -/
def serializeSchemaLeaf (phys rep : Nat) (colName : String) : ByteArray :=
  let (l1, h1) := writeFieldBegin (0 : Int32) 1 ctI32
  let s1 := h1 ++ writeZigZag32 (Int32.ofNat phys)
  let (l3, h3) := writeFieldBegin l1 3 ctI32
  let s3 := h3 ++ writeZigZag32 (Int32.ofNat rep)
  let (_, h4) := writeFieldBegin l3 4 ctBinary
  s1 ++ s3 ++ h4 ++ writeString colName ++ writeFieldStop

/-- Synthetic root (`schema`, `num_children`).
Field 3 `repetition_type` (REQUIRED=0) before name/children — matches common writers (e.g. Arrow)
and keeps Thrift field ids ascending within the struct. -/
def serializeSchemaRoot (numCols : Nat) : ByteArray :=
  let (l3, h3) := writeFieldBegin (0 : Int32) 3 ctI32
  let s3 := h3 ++ writeZigZag32 (Int32.ofNat 0)
  let (l4, h4) := writeFieldBegin l3 4 ctBinary
  let s4 := h4 ++ writeString "schema"
  let (_, h5) := writeFieldBegin l4 5 ctI32
  s3 ++ s4 ++ h5 ++ writeZigZag32 (Int32.ofNat numCols) ++ writeFieldStop

def serializeSchemaListPayload (ws : WriteSchema) : ByteArray :=
  let root := serializeSchemaRoot ws.columns.size
  let leaves :=
    ws.columns.foldl (fun acc c => acc ++ serializeSchemaLeaf c.phys c.repetition c.name) ByteArray.empty
  writeListBegin ctStruct (ws.columns.size + 1) ++ root ++ leaves

/-- `ColumnMetaData` Thrift compact (includes STOP). -/
def serializeColumnMetaData
    (phys : Nat) (codecParquet : Nat) (numRows : Nat)
    (totalUncompressed totalCompressed : Nat) (dataPageOffset : Nat)
    (encodings : Array Nat) (pathParts : Array String) : ByteArray :=
  let (l1, h1) := writeFieldBegin (0 : Int32) 1 ctI32
  let s1 := h1 ++ writeZigZag32 (Int32.ofNat phys)
  let (l2, h2) := writeFieldBegin l1 2 ctList
  let encVals :=
    encodings.foldl (fun acc e => acc ++ writeZigZag32 (Int32.ofNat e)) ByteArray.empty
  let s2 := h2 ++ writeListBegin ctI32 encodings.size ++ encVals
  let (l3, h3) := writeFieldBegin l2 3 ctList
  let pathVals := pathParts.foldl (fun acc p => acc ++ writeString p) ByteArray.empty
  let s3 := h3 ++ writeListBegin ctBinary pathParts.size ++ pathVals
  let (l4, h4) := writeFieldBegin l3 4 ctI32
  let s4 := h4 ++ writeZigZag32 (Int32.ofNat codecParquet)
  let (l5, h5) := writeFieldBegin l4 5 ctI64
  let s5 := h5 ++ writeZigZag64 (Int64.ofNat numRows)
  let (l6, h6) := writeFieldBegin l5 6 ctI64
  let s6 := h6 ++ writeZigZag64 (Int64.ofNat totalUncompressed)
  let (l7, h7) := writeFieldBegin l6 7 ctI64
  let s7 := h7 ++ writeZigZag64 (Int64.ofNat totalCompressed)
  let (_, h9) := writeFieldBegin l7 9 ctI64
  let s9 := h9 ++ writeZigZag64 (Int64.ofNat dataPageOffset)
  s1 ++ s2 ++ s3 ++ s4 ++ s5 ++ s6 ++ s7 ++ s9 ++ writeFieldStop

def serializeColumnChunk (metaInner : ByteArray) : ByteArray :=
  let (_, h3) := writeFieldBegin (0 : Int32) 3 ctStruct
  h3 ++ metaInner ++ writeFieldStop

def serializeRowGroup (columnChunks : Array ByteArray) (numRows : Nat) : ByteArray :=
  let (l1, h1) := writeFieldBegin (0 : Int32) 1 ctList
  let chunksInner := columnChunks.foldl (· ++ ·) ByteArray.empty
  let s1 := h1 ++ writeListBegin ctStruct columnChunks.size ++ chunksInner
  let (_, h3) := writeFieldBegin l1 3 ctI64
  s1 ++ h3 ++ writeZigZag64 (Int64.ofNat numRows) ++ writeFieldStop

/-- One serialized `RowGroup` struct per element (same wire as `serializeRowGroup` output). -/
def serializeRowGroupList (rowGroupStructs : Array ByteArray) : ByteArray :=
  let inner := rowGroupStructs.foldl (· ++ ·) ByteArray.empty
  writeListBegin ctStruct rowGroupStructs.size ++ inner

def serializeFileMetaData (version : Int32) (schemaPayload : ByteArray) (numRows : Nat) (rowGroupStructs : Array ByteArray) : ByteArray :=
  let (l1, h1) := writeFieldBegin (0 : Int32) 1 ctI32
  let s1 := h1 ++ writeZigZag32 version
  let (l2, h2) := writeFieldBegin l1 2 ctList
  let s2 := h2 ++ schemaPayload
  let (l3, h3) := writeFieldBegin l2 3 ctI64
  let s3 := h3 ++ writeZigZag64 (Int64.ofNat numRows)
  let (_, h4) := writeFieldBegin l3 4 ctList
  let s4 := h4 ++ serializeRowGroupList rowGroupStructs
  s1 ++ s2 ++ s3 ++ s4 ++ writeFieldStop

def parquetMagic : ByteArray :=
  ByteArray.mk #[0x50, 0x41, 0x52, 0x31]

end Columnar.Parquet.Writer.Footer
