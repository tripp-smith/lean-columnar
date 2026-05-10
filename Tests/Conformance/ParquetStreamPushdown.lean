import Init.System.FilePath
import Columnar.Parquet.Filter
import Columnar.Parquet.Reader
import Columnar.Parquet.Stream
import Tests.Fixtures
import Tests.Harness

namespace Tests.Conformance.ParquetStreamPushdown

open Columnar.Parquet.Reader
open Columnar.Parquet.Stream
open Columnar.Parquet.Filter

def run (ctx : Harness.Ctx) : IO Unit := do
  match ← Harness.skipHeavyParquetReaderOnOSX "Parquet stream/pushdown" with
  | some msg =>
    Harness.info s!"Parquet stream/pushdown: SKIP on macOS ({msg})"
    return
  | none => pure ()
  let p := Fixtures.twoRowGroupsPlain
  unless ← p.pathExists do
    Harness.info "Stream/pushdown: SKIP (Tests/fixtures/two_row_groups_plain.parquet missing; run scripts/gen_two_row_fixture.py)"
    return
  match ← readFileMeta p with
  | .error e => Harness.fail ctx s!"stream Meta: {e}"
  | .ok fm =>
    Harness.check ctx "sort_columns has 2 row groups" (fm.rowGroups.size == 2)
    let n := RowGroupStream.countStreamed (RowGroupStream.init fm)
    Harness.check ctx "RowGroupStream visits all row groups" (n == fm.rowGroups.size)
    let noStats : StatsAssoc := #[]
    Harness.check ctx "ltInt conservative w/o stats"
      (Pred.matches (Pred.ltInt "x" 5) noStats)
    let stats : StatsAssoc := #[
      ("x", ({ minI64 := some (Int64.ofNat 10), maxI64 := none } : ColumnStats))
    ]
    Harness.check ctx "ltInt excludes when min >= threshold"
      (!(Pred.matches (Pred.ltInt "x" 5) stats))
    Harness.info "Parquet stream/pushdown: OK"

end Tests.Conformance.ParquetStreamPushdown
