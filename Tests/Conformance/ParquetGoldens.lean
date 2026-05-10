import Init.System.FilePath
import Columnar.Parquet.Reader
import Tests.Fixtures
import Tests.GoldenFmt
import Tests.Harness

open Columnar.Parquet.Reader

namespace Tests.Conformance.ParquetGoldens

def goldenRoot : System.FilePath :=
  System.mkFilePath ["Tests", "goldens"]

/-- Parquet-testing file paired with exporter sidecar (`scripts/export_parquet_goldens.py`). -/
def cases : List (String × System.FilePath) :=
  [
    ("alltypes_plain.parquet", System.mkFilePath ["Tests", "goldens", "alltypes_plain__id.txt"]),
    ("alltypes_plain.parquet", System.mkFilePath ["Tests", "goldens", "alltypes_plain__bool_col.txt"]),
    ("binary.parquet", System.mkFilePath ["Tests", "goldens", "binary__foo.txt"]),
    ("int32_decimal.parquet", System.mkFilePath ["Tests", "goldens", "int32_decimal__value.txt"]),
    ("int64_decimal.parquet", System.mkFilePath ["Tests", "goldens", "int64_decimal__value.txt"])
  ]

def run (ctx : Harness.Ctx) : IO Unit := do
  match ← Harness.skipHeavyParquetReaderOnOSX "Parquet goldens" with
  | some msg =>
    Harness.info s!"Parquet goldens: SKIP on macOS ({msg})"
    return
  | none => pure ()
  unless ← Fixtures.parquetTestingRoot.pathExists do
    Harness.info "Parquet goldens: SKIP (vendor/parquet-testing missing)"
    return
  unless ← goldenRoot.pathExists do
    Harness.fail ctx "Parquet goldens: Tests/goldens directory missing"
    return
  for pr in cases do
    let (pqName, gpath) := pr
    let pq := Fixtures.parquetTesting pqName
    if !(← gpath.pathExists) then
      Harness.fail ctx s!"Parquet goldens: missing sidecar {gpath}"
    else if !(← pq.pathExists) then
      Harness.fail ctx s!"Parquet goldens: missing parquet-testing file {pqName}"
    else
      match ← GoldenFmt.parseFile gpath with
      | .error e => Harness.fail ctx s!"golden parse {gpath}: {e}"
      | .ok gspec =>
        match ← readParquet pq with
        | .error e =>
          Harness.fail ctx s!"readParquet {pqName}: {e}"
        | .ok tbl =>
          match GoldenFmt.goldenMatches tbl gspec with
          | .error e =>
            Harness.fail ctx s!"{pqName} value mismatch ({gpath}): {e}"
          | .ok _ =>
            Harness.info s!"Parquet golden OK {pqName} column «{gspec.column}»"

end Tests.Conformance.ParquetGoldens
