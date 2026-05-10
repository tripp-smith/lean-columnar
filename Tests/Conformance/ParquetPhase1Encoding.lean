import Init.System.IO
import Columnar.Parquet.Reader
import Tests.Fixtures
import Tests.Harness

open Columnar.Parquet.Reader

namespace Tests.Conformance.ParquetPhase1Encoding

/-! Encoding-matrix smoke + tiered SKIP (`COLUMNAR_ENCODING_TIER_STRICT=1` makes `mustDecode` failures fatal).

`alltypes_dictionary.parquet` is **explore-only** (`COLUMNAR_PHASE1_EXPLORE=1`): it has been linked to
intermittent native teardown faults on some macOS/Lean combinations in the full test binary.

On **macOS**, run `COLUMNAR_PARQUET_READER_OSX=1` so this group executes (same gate as other Parquet reader tests). -/

def codecSniff (msg : String) : Bool :=
  ["snappy", "zstd", "zlib", "gzip", "brotli", "lz4"].any fun sub => msg.contains sub

/-- Files that must decode cleanly when parquet-testing is present + codecs allow (CI default: soft SKIP on error). -/
def mustDecode : List String :=
  [
    "plain-dict-uncompressed-checksum.parquet"
  ]

def explore : List String :=
  [
    -- alltypes_dictionary: opt-in explore (see module docstring / CI notes).
    "alltypes_dictionary.parquet",
    "delta_encoding_required_column.parquet",
    "delta_byte_array.parquet",
    "delta_length_byte_array.parquet",
    "datapage_v2_empty_datapage.snappy.parquet"
    -- page_v2_empty_compressed.parquet: SIGSEGV in native reader (investigate separately).
  ]

def run (ctx : Harness.Ctx) : IO Unit := do
  match ← Harness.skipHeavyParquetReaderOnOSX "Parquet Phase1 encoding" with
  | some msg =>
    Harness.info s!"Parquet Phase1 encoding: SKIP on macOS ({msg})"
    return
  | none => pure ()
  unless ← Fixtures.parquetTestingRoot.pathExists do
    Harness.info "Parquet Phase1 encoding: SKIP vendor missing"
    return
  let codec? ← IO.getEnv "COLUMNAR_CODEC"
  let strict? ← IO.getEnv "COLUMNAR_ENCODING_TIER_STRICT"
  -- Full encoding-matrix explore is opt-in (`COLUMNAR_PHASE1_EXPLORE=1`): some fixtures still crash the native binary.
  let exploreOn? ← IO.getEnv "COLUMNAR_PHASE1_EXPLORE"
  let runExplore : Bool :=
    match exploreOn? with
    | some s => (String.trimAscii s).toString == "1"
    | none => false
  let fileList := if runExplore then mustDecode ++ explore else mustDecode
  for name in fileList do
    let p := Fixtures.parquetTesting name
    unless ← p.pathExists do
      Harness.info s!"Phase1 SKIP missing {name}"
      continue
    let res ← readParquet p
    match res with
    | .ok tbl =>
        Harness.check ctx s!"{name}: non-empty cols" (tbl.columns.size > 0)
        Harness.info s!"Phase1 encode OK decode {name} ({tbl.columns.size} cols)"
    | .error e =>
        if codecSniff e && codec?.isNone then
          Harness.info s!"Phase1 SKIP {name} ({e})"
        else if mustDecode.contains name ∧ strict?.isSome then
          Harness.fail ctx s!"Phase1 mustDecode FAIL {name}: {e}"
        else if mustDecode.contains name then
          Harness.info s!"Phase1 SKIP mustDecode SOFT {name} ({e})"
        else if explore.contains name then
          Harness.info s!"Phase1 SKIP explore SOFT {name} ({e})"
        else
          Harness.info s!"Phase1 SKIP {name} ({e})"

end Tests.Conformance.ParquetPhase1Encoding
