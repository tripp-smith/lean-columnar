import Columnar.Table
import Columnar.Parquet.Types
import Columnar.Parquet.Encoding.Plain
import Columnar.Compression.Codec

namespace Columnar.Parquet.Writer

open Columnar.Compression

abbrev Err := Except String

structure WriteColumn where
  name : String
  phys : Nat
  /-- Parquet `RepetitionType`: 0 = REQUIRED, 1 = OPTIONAL -/
  repetition : Nat
  deriving Repr

structure WriteSchema where
  columns : Array WriteColumn
  deriving Repr

structure WriteOptions where
  version : Int32 := 2
  rowsPerRowGroup : Nat := 65536
  dataPageTargetSize : Nat := 1048576
  defaultCodec : CodecId := .uncompressed
  /-- Override codec per column name (first match wins). -/
  columnCodecs : Array (String × CodecId) := #[]
  createdBy : String := "lean-columnar"

def WriteOptions.default : WriteOptions :=
  { version := 2
    rowsPerRowGroup := 65536
    dataPageTargetSize := 1048576
    defaultCodec := .uncompressed
    columnCodecs := #[]
    createdBy := "lean-columnar" }

def WriteOptions.resolveCodec (o : WriteOptions) (colName : String) : CodecId :=
  match o.columnCodecs.findSome? fun (n, c) => if n == colName then some c else none with
  | some c => c
  | none => o.defaultCodec

private def physOfPlain (v : Parquet.Encoding.Plain.PlainValue) : Err Nat :=
  match v with
  | .null => throw "PlainValue.null is not a concrete cell type"
  | .bool _ => pure PhysType.boolean
  | .int32 _ => pure PhysType.int32
  | .int64 _ => pure PhysType.int64
  | .float _ => pure PhysType.float
  | .double _ => pure PhysType.double
  | .byteArray _ => pure PhysType.byteArray

/-- Infer writer schema: columns keep table order; OPTIONAL iff any row is `none` or `some .null`. -/
def inferWriteSchema (t : Table) : Err WriteSchema := do
  let mut cols : Array WriteColumn := #[]
  for c in t.columns do
    let mut phys? : Option Nat := none
    let mut optional := false
    if c.values.isEmpty then
      -- Zero rows: default physical type INT32, REQUIRED (see writer round-trip tests).
      cols := cols.push { name := c.name, phys := PhysType.int32, repetition := 0 }
    else
      for ov in c.values do
        match ov with
        | none => optional := true
        | some .null => optional := true
        | some pv =>
          let p ← physOfPlain pv
          match phys? with
          | none => phys? := some p
          | some q =>
            unless p == q do
              throw s!"writeParquet: column «{c.name}» mixes physical types"
            pure ()
      match phys? with
      | none =>
        throw s!"writeParquet: column «{c.name}» has no non-null values (cannot infer type)"
      | some phys =>
        let rep := if optional then 1 else 0
        cols := cols.push { name := c.name, phys := phys, repetition := rep }
  return { columns := cols }

/-- Column-regular row count check (all columns same length). -/
def validateTableShape (t : Table) : Err Nat := do
  if h : 0 < t.columns.size then
    let n0 := (t.columns[0]'h).values.size
    for c in t.columns do
      unless c.values.size == n0 do
        throw s!"writeParquet: column «{c.name}» length {c.values.size} ≠ {n0}"
    pure n0
  else
    pure 0

end Columnar.Parquet.Writer
