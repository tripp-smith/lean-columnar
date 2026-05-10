import Columnar.Table
import Columnar.Table.PlainViews
import Columnar.Core.Bytes
import Columnar.Parquet.Encoding.Plain
import Init.Data.SInt.Float
import SciLean.Data.DataArray.DataArray
import SciLean.Data.DataArray.Float
import SciLean.Util.SorryProof

open Columnar
open Columnar.Parquet.Encoding.Plain
open Columnar.ByteArrayOps
open SciLean

namespace Columnar.SciLean.Convert

inductive FloatKind where
  | float32
  | float64
  | int32
  deriving DecidableEq, Repr

/-- Read one column as dense floats (`PlainValue.float`, `.double`, or `.int32`; no nulls). -/
def columnFloats (c : Column) : Except String (FloatKind × Array Float) :=
  Id.run do
    let mut fk : Option FloatKind := none
    let mut acc : Array Float := #[]
    for ov in c.values do
      match ov with
      | none => return throw "SciLean.Convert: null cell"
      | some (.float f) =>
        match fk with
        | none => fk := some .float32
        | some .float32 => pure ()
        | some _ => return throw "SciLean.Convert: mixed numeric kinds in column"
        acc := acc.push f
      | some (.double f) =>
        match fk with
        | none => fk := some .float64
        | some .float64 => pure ()
        | some _ => return throw "SciLean.Convert: mixed numeric kinds in column"
        acc := acc.push f
      | some (.int32 i) =>
        match fk with
        | none => fk := some .int32
        | some .int32 => pure ()
        | some _ => return throw "SciLean.Convert: mixed numeric kinds in column"
        acc := acc.push (Int32.toFloat i)
      | some _ => return throw "SciLean.Convert: unsupported cell type for tensor export"
    match fk with
    | none => pure (.float64, #[])
    | some k => pure (k, acc)

/-- Row-major index for `rows × cols` layout. -/
@[inline]
def rowMajorIndex (row col cols : Nat) : Nat :=
  row * cols + col

/-- When every column is dense non-null `int32` and `plainInt32PackedBytes?` succeeds, fill row-major floats without scanning boxed cells. -/
private def tablePackedInt32FloatArray? (t : Table) (rows cols : Nat)
    : Option (DataArray Float × FloatKind) :=
  Id.run do
    for j in [:cols] do
      match (t.columns[j]!).plainInt32PackedBytes? with
      | none => return none
      | some b => if b.size != rows * 4 then return none else pure ()
    let cells := rows * cols
    let mut da := DataArray.mkZero cells
    let mut i : Nat := 0
    for r in [:rows] do
      for c in [:cols] do
        let b ← match (t.columns[c]!).plainInt32PackedBytes? with
          | none => return none
          | some b => pure b
        match readInt32LE b (r * 4) with
        | none => return none
        | some iv =>
          da := da.set ⟨USize.ofNat i, sorry_proof⟩ (Int32.toFloat iv)
          i := i + 1
    some (da, .int32)

/-- Pack a flat table into row-major `DataArray Float` (shape `rows × cols`).

Uses `PlainViews` packed `int32` slabs when possible; otherwise scans cells.

Homogeneous columns only: all `float`, all `double`, or all `int32` (lifted to `Float` via `Int32.toFloat`).
-/
def tableToFloatDataArray (t : Table) : Except String (DataArray Float × Nat × Nat × FloatKind) := do
  let rows := rowCount t
  let cols := t.columns.size
  if cols == 0 then throw "SciLean.Convert: empty table (no columns)"
  match tablePackedInt32FloatArray? t rows cols with
  | some (da, fk) => return (da, rows, cols, fk)
  | none =>
    let mut kind : Option FloatKind := none
    let mut colVals : Array (Array Float) := #[]
    for j in [:cols] do
      let (fk, vs) ← columnFloats (t.columns[j]!)
      if vs.size != rows then throw "SciLean.Convert: column length mismatch"
      match kind with
      | none => kind := some fk
      | some k0 =>
        if fk != k0 then throw "SciLean.Convert: mixed numeric kinds across columns"
      colVals := colVals.push vs
    let cells := rows * cols
    let mut da := DataArray.mkZero cells
    let mut i : Nat := 0
    for r in [:rows] do
      for c in [:cols] do
        let v := colVals[c]![r]!
        da := da.set ⟨USize.ofNat i, sorry_proof⟩ v
        i := i + 1
    match kind with
    | none => pure (da, rows, cols, .float64)
    | some fk => pure (da, rows, cols, fk)

/-- Inverse of `tableToFloatDataArray` for dense double columns (stores `PlainValue.double`). -/
def floatDataArrayToTable (rows cols : Nat) (da : DataArray Float) (names : Array String)
    : Except String Table := do
  if names.size != cols then throw "SciLean.Convert: name count must match column count"
  if da.size != rows * cols then throw "SciLean.Convert: data size must be rows×cols"
  let mut out : Array Column := #[]
  for c in [:cols] do
    let mut vals : Array (Option PlainValue) := #[]
    for r in [:rows] do
      let idx := rowMajorIndex r c cols
      let v := da.get ⟨USize.ofNat idx, sorry_proof⟩
      vals := vals.push (some (.double v))
    out := out.push { name := names[c]!, values := vals }
  return { columns := out }

end Columnar.SciLean.Convert
