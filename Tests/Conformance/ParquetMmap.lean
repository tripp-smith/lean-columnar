import Init.System.FilePath
import Columnar.Parquet.Reader
import Columnar.Parquet.Stream
import Columnar.Table
import Tests.Fixtures
import Tests.Harness
import Tests.MmapAssertions

namespace Tests.Conformance.ParquetMmap

open Columnar.Parquet.Reader
open Columnar.Parquet.Stream

def run (ctx : Harness.Ctx) : IO Unit := do
  match ← Harness.skipHeavyParquetReaderOnOSX "Parquet mmap/stream" with
  | some msg =>
    Harness.info s!"Parquet mmap/stream: SKIP on macOS ({msg})"
    return
  | none => pure ()
  let pq := Fixtures.parquetTesting "binary.parquet"
  unless ← Fixtures.parquetTestingRoot.pathExists do
    Harness.info "Parquet mmap: SKIP (vendor/parquet-testing missing)"
    return
  unless ← pq.pathExists do
    Harness.info "Parquet mmap: SKIP binary.parquet missing"
    return
  match ← readParquet pq with
  | .error e => Harness.fail ctx s!"Parquet mmap baseline readParquet: {e}"
  | .ok t0 =>
    match ← readParquetMmap pq with
    | .error e => Harness.fail ctx s!"Parquet mmap readParquetMmap: {e}"
    | .ok t1 =>
      Harness.check ctx "readParquet vs readParquetMmap binary.parquet" (Tests.MmapAssertions.tablesEqual t0 t1)
  let twoRg := Fixtures.twoRowGroupsPlain
  unless ← twoRg.pathExists do
    Harness.info "Parquet mmap stream: SKIP (Tests/fixtures/two_row_groups_plain.parquet missing)"
    return
  match ← openParquetFile twoRg with
  | .error e => Harness.fail ctx s!"openParquetFile two_row_groups: {e}"
  | .ok pf => do
    try
      match ← readParquetAllRowGroups twoRg with
      | .error e => Harness.fail ctx s!"readParquetAllRowGroups fixture: {e}"
      | .ok want => do
        let mut s := streamRowGroups pf
        match ← RowGroupDecodeStream.nextDecoded s with
        | .error e => Harness.fail ctx s!"stream first RG: {e}"
        | .ok none => Harness.fail ctx "stream: expected first row group"
        | .ok (some (t0, s1)) =>
          match ← RowGroupDecodeStream.nextDecoded s1 with
          | .error e => Harness.fail ctx s!"stream second RG: {e}"
          | .ok none => Harness.fail ctx "stream: expected second row group"
          | .ok (some (t1, s2)) =>
            match ← RowGroupDecodeStream.nextDecoded s2 with
            | .error e => Harness.fail ctx s!"stream end: {e}"
            | .ok (some _) => Harness.fail ctx "stream: expected exactly 2 row groups"
            | .ok none =>
              match Columnar.Table.appendRows t0 t1 with
              | .error e => Harness.fail ctx s!"appendRows: {e}"
              | .ok got =>
                Harness.check ctx "streamRowGroups vs readParquetAllRowGroups" (Tests.MmapAssertions.tablesEqual got want)
    finally
      pf.dispose
  Harness.info "Parquet mmap/stream: OK"

end Tests.Conformance.ParquetMmap
