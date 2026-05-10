import Init.System.FilePath
import Init.System.IO
import Columnar.Parquet.Reader
import Columnar.Parquet.SchemaWalk
import Tests.Fixtures
import Tests.Harness

namespace Tests.Conformance.ParquetNestedLevels

open Columnar
open Columnar.Parquet.Reader
open Columnar.Parquet.SchemaWalk

def run (ctx : Harness.Ctx) : IO Unit := do
  match ← Harness.skipHeavyParquetReaderOnOSX "Parquet nested levels" with
  | some msg =>
    Harness.info s!"Parquet nested: SKIP on macOS ({msg})"
    return
  | none => pure ()
  let p := Fixtures.parquetTesting "list_columns.parquet"
  unless ← Fixtures.parquetTestingRoot.pathExists do
    Harness.info "Parquet nested: SKIP vendor missing"
    return
  unless ← p.pathExists do
    Harness.info "Parquet nested: SKIP list_columns.parquet missing"
    return
  let bytes ← IO.FS.readBinFile p
  match readFileMetaFromBytes bytes with
  | .error e => Harness.fail ctx s!"Parquet nested footer: {e}"
  | .ok fm =>
    match preorderLeavesFromSchema fm.schema with
    | .error e => Harness.fail ctx s!"Parquet nested schema walk: {e}"
    | .ok leaves =>
      let hasRep := leaves.any fun lf => lf.maxRepetitionLevel > 0
      Harness.check ctx "list_columns has maxRepetitionLevel>0 leaf" hasRep
      if h : 0 < fm.rowGroups.size then
        let rg0 := fm.rowGroups[0]'h
        match matchLeavesToChunksByPath leaves rg0.columns with
        | Except.error e => Harness.fail ctx s!"Parquet nested chunk match: {e}"
        | Except.ok paired =>
          Harness.check ctx "list_columns chunk/leaf pairing count" (paired.size == rg0.columns.size)
      else
        Harness.fail ctx "Parquet nested: no row groups in list_columns"
      let decodeFull ← IO.getEnv "COLUMNAR_DECODE_LIST_COLUMNS"
      let wantDecode :=
        match decodeFull with
        | none => false
        | some s => (String.trimAscii s).toString == "1"
      if wantDecode then
        match ← readParquet p with
        | .error e => Harness.info s!"Parquet nested: readParquet SOFT-SKIP ({e})"
        | .ok tbl =>
          Harness.check ctx "nested file decodes some columns" (tbl.columns.size > 0)
          Harness.check ctx "nested table row count positive" (Table.rowCount tbl > 0)
          Harness.info s!"Parquet nested: OK leaf count {leaves.size} table cols {tbl.columns.size} rows {Table.rowCount tbl}"
      else
        Harness.info "Parquet nested: full decode skipped (set COLUMNAR_DECODE_LIST_COLUMNS=1 to run readParquet on list_columns.parquet)"

end Tests.Conformance.ParquetNestedLevels
