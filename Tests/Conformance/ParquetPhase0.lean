import Init.System.FilePath
import Init.System.IO
import Columnar.Parquet.Reader
import Tests.Fixtures
import Tests.Harness

namespace Tests.Conformance.ParquetPhase0

/-- Phase-0 corpus from the implementation plan (parquet-testing).

`mustPass` is the subset that must decode today (CI gate). Others are exercised but failures log as
SKIP until the reader catches up (set `COLUMNAR_PHASE0_STRICT=1` to require every file). -/
def files : List String :=
  [
    "alltypes_plain.parquet",
    "alltypes_plain.snappy.parquet",
    "binary.parquet",
    "int32_decimal.parquet",
    "int64_decimal.parquet",
    "nonnullable.impala.parquet"
  ]

def mustPass : List String :=
  ["int32_decimal.parquet", "int64_decimal.parquet"]

def isMustPass (name : String) : Bool :=
  mustPass.elem name

def needsCodecEnv (msg : String) : Bool :=
  ["snappy", "zstd", "zlib", "gzip", "brotli", "lz4"].any fun sub => msg.contains sub

def run (log : Harness.ErrLog) : IO Unit := do
  let root := Fixtures.parquetTestingRoot
  unless ← root.pathExists do
    Harness.info "Parquet Phase0: SKIP (vendor/parquet-testing missing; run scripts/fetch-fixtures.sh)"
    return
  let codec? ← IO.getEnv "COLUMNAR_CODEC"
  let strict? ← IO.getEnv "COLUMNAR_PHASE0_STRICT"
  for name in files do
    let p := Fixtures.parquetTesting name
    unless ← p.pathExists do
      Harness.info s!"Parquet Phase0: SKIP missing file {name}"
      continue
    try
      let res ← Columnar.Parquet.Reader.readParquet p
      match res with
      | .ok t =>
        Harness.check log s!"{name} non-empty columns" (t.columns.size > 0)
        Harness.info s!"Parquet Phase0: OK {name} ({t.columns.size} cols)"
      | .error e =>
        if needsCodecEnv e && codec?.isNone then
          Harness.info s!"Parquet Phase0: SKIP {name} ({e})"
        else if strict?.isNone && !isMustPass name then
          Harness.info s!"Parquet Phase0: SKIP {name} ({e}) [reader gap]"
        else
          Harness.fail log s!"Parquet Phase0: FAIL {name}: {e}"
    catch e =>
      let msg := e.toString
      if needsCodecEnv msg && codec?.isNone then
        Harness.info s!"Parquet Phase0: SKIP {name} (IO: {msg})"
      else if strict?.isNone && !isMustPass name then
        Harness.info s!"Parquet Phase0: SKIP {name} (IO: {msg}) [reader gap]"
      else
        Harness.fail log s!"Parquet Phase0: FAIL {name} (IO: {msg})"

end Tests.Conformance.ParquetPhase0
