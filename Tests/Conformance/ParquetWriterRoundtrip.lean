import Columnar.Table
import Columnar.Parquet.Reader
import Columnar.Parquet.Writer
-- `writeParquetBytes` lives in `Columnar.Parquet.Writer`
import Columnar.Parquet.Encoding.Plain
import Tests.Harness

open Columnar
open Columnar.Parquet.Encoding.Plain
open Columnar.Parquet.Writer (WriteOptions)

namespace Tests.Conformance.ParquetWriterRoundtrip

private def pvEq (x y : PlainValue) : Bool :=
  match x, y with
  | .null, .null => true
  | .bool a, .bool b => a == b
  | .int32 a, .int32 b => a == b
  | .int64 a, .int64 b => a == b
  | .float a, .float b => Float.beq a b
  | .double a, .double b => Float.beq a b
  | .byteArray a, .byteArray b => a == b
  | _, _ => false

private def ovEq (a b : Option PlainValue) : Bool :=
  match a, b with
  | none, none => true
  | some x, some y => pvEq x y
  | _, _ => false

private def valsEq (va vb : Array (Option PlainValue)) : Bool :=
  va.size == vb.size &&
  (List.zip va.toList vb.toList).all fun pr => ovEq pr.1 pr.2

private def columnEq (a b : Column) : Bool :=
  a.name == b.name && valsEq a.values b.values

private def tablesEq (t u : Table) : Bool :=
  t.columns.size == u.columns.size &&
  (List.zip t.columns.toList u.columns.toList).all fun pr => columnEq pr.1 pr.2

private def roundTripIO (t : Table) : IO (Except String Table) := do
  match Columnar.Parquet.Writer.writeParquetBytes t with
  | .error e => return .error e
  | .ok bytes =>
    Columnar.Parquet.Reader.readParquetFromBytes bytes

private def roundTripAllRowGroupsIO (t : Table) (opts : WriteOptions) : IO (Except String Table) := do
  match Columnar.Parquet.Writer.writeParquetBytes t opts with
  | .error e => return .error e
  | .ok bytes =>
    Columnar.Parquet.Reader.readParquetAllRowGroupsFromBytes bytes

def run (ctx : Harness.Ctx) : IO Unit := do
  match ← Harness.skipHeavyParquetReaderOnOSX "Parquet writer round-trip" with
  | some msg =>
    Harness.info s!"Parquet writer round-trip: SKIP on macOS ({msg})"
    return
  | none => pure ()
  let emptyInt : Table := { columns := #[{ name := "x", values := #[] }] }
  match ← roundTripIO emptyInt with
  | .error e => Harness.fail ctx s!"writer rt empty: {e}"
  | .ok t2 =>
    Harness.check ctx "empty INT32 table round-trip" (tablesEq emptyInt t2)
  let seq7 :=
    { columns :=
      #[{ name := "x", values := (List.range 7).map (fun i => some (PlainValue.int32 (Int32.ofNat i))) |>.toArray }] }
  match ← roundTripIO seq7 with
  | .error e => Harness.fail ctx s!"writer rt seq: {e}"
  | .ok t3 =>
    Harness.check ctx "INT32 0..6 round-trip" (tablesEq seq7 t3)
  let seq6 :=
    { columns :=
      #[{ name := "x", values := (List.range 6).map (fun i => some (PlainValue.int32 (Int32.ofNat i))) |>.toArray }] }
  let opts3rg : WriteOptions := { WriteOptions.default with rowsPerRowGroup := 3 }
  match ← roundTripAllRowGroupsIO seq6 opts3rg with
  | .error e => Harness.fail ctx s!"writer rt multi-RG: {e}"
  | .ok tMr =>
    Harness.check ctx "multi row-group INT32 round-trip (rowsPerRowGroup=3)" (tablesEq seq6 tMr)
  let onlyFloat :=
    { columns := #[{ name := "f", values := #[some (.float (Float.ofNat 3))] }] }
  match ← roundTripIO onlyFloat with
  | .error e => Harness.fail ctx s!"writer rt onlyFloat: {e}"
  | .ok tOnly =>
    Harness.check ctx "FLOAT32 single-column round-trip" (tablesEq onlyFloat tOnly)
  let mixed :=
    { columns :=
      #[
        { name := "b", values := #[some (.bool true)] },
        { name := "i", values := #[some (.int32 (Int32.ofNat 42))] },
        { name := "f", values := #[some (.float (Float.ofNat 3))] }
      ] }
  match ← roundTripIO mixed with
  | .error e => Harness.fail ctx s!"writer rt mixed: {e}"
  | .ok t4 =>
    Harness.check ctx "mixed primitives round-trip" (tablesEq mixed t4)
  let nullable :=
    { columns :=
      #[{ name := "n", values := #[none, some (.int64 (Int64.ofNat 99))] }] }
  match ← roundTripIO nullable with
  | .error e => Harness.fail ctx s!"writer rt nullable: {e}"
  | .ok t5 =>
    Harness.check ctx "nullable INT64 round-trip" (tablesEq nullable t5)
  Harness.info "Parquet writer round-trip: OK"

end Tests.Conformance.ParquetWriterRoundtrip
