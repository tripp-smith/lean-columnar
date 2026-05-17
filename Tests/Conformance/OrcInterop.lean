import Columnar.Orc.Reader
import Tests.Fixtures
import Tests.GoldenFmt
import Tests.Harness

namespace Tests.Conformance.OrcInterop

def goldenRowsPath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_orc_test1_rows.txt"]

def goldenInt32XPath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_orc_int32__x.txt"]

def goldenTest1Int1Path : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_orc_test1__int1.txt"]

def goldenTest1Boolean1Path : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_orc_test1__boolean1.txt"]

private def expectNatGolden (path : System.FilePath) : IO (Except String Nat) := do
  let t ← IO.FS.readFile path
  let line := (String.trimAscii t).toString
  match line.toNat? with
  | none => return .error "golden: expected decimal Nat line"
  | some n => return .ok n

private def needsCodecEnv (msg : String) : Bool :=
  ["snappy", "zstd", "zlib", "gzip", "brotli", "lz4"].any fun sub => msg.contains sub ||
  msg.contains "unavailable" || msg.contains "COLUMNAR_CODEC"

private def codecSkipOrFail (ctx : Harness.Ctx) (label : String) (msg : String) : IO Unit := do
  if needsCodecEnv msg then
    if ← Harness.interopStrict then
      Harness.fail ctx s!"{label}: codec required under COLUMNAR_INTEROP_STRICT ({msg})"
    else
      Harness.info s!"{label}: SKIP ({msg})"
  else
    Harness.fail ctx s!"{label}: {msg}"

def runVendorFooterRows (ctx : Harness.Ctx) : IO Unit := do
  let p := Fixtures.orcTest1
  unless ← p.pathExists do
    Harness.info "Interop ORC footer: SKIP (vendor/orc missing)"
    return
  unless ← goldenRowsPath.pathExists do
    Harness.fail ctx "Interop ORC: golden sidecar missing"
    return
  match ← expectNatGolden goldenRowsPath with
  | .error e => Harness.fail ctx e
  | .ok want =>
    try
      match ← Columnar.Orc.Reader.readOrcNumberOfRows p with
      | .error e => codecSkipOrFail ctx "Interop ORC footer" e
      | .ok got =>
        Harness.check ctx s!"ORC TestOrcFile.test1.orc footer rows ({got})" (got == want)
        Harness.info s!"Interop ORC: OK rows={got}"
    catch e =>
      codecSkipOrFail ctx "Interop ORC footer" e.toString

def runVendorTest1Columns (ctx : Harness.Ctx) : IO Unit := do
  let p := Fixtures.orcTest1
  unless ← p.pathExists do
    Harness.info "Interop ORC test1 columns: SKIP (vendor/orc missing)"
    return
  match ← Columnar.Orc.Reader.readOrcNumberOfRows p with
  | .error e =>
    codecSkipOrFail ctx "Interop ORC test1" e
    return
  | .ok _ => pure ()
  for (golden, col) in [(goldenTest1Int1Path, "int1"), (goldenTest1Boolean1Path, "boolean1")] do
    unless ← golden.pathExists do
      Harness.info s!"Interop ORC test1 «{col}»: SKIP (golden missing; run scripts/export_interop_goldens.py with vendor/orc)"
      continue
    match ← GoldenFmt.parseFile golden with
    | .error e => Harness.fail ctx s!"Interop ORC test1 «{col}»: {e}"
    | .ok gspec =>
      try
        match ← Columnar.Orc.Reader.readOrcPrimitives p [col] with
        | .error e => codecSkipOrFail ctx s!"Interop ORC test1 «{col}»" e
        | .ok tbl =>
          match GoldenFmt.goldenMatches tbl gspec with
          | .error e => Harness.fail ctx s!"Interop ORC test1 «{col}» golden: {e}"
          | .ok _ => Harness.info s!"Interop ORC test1: OK column «{col}»"
      catch e =>
        codecSkipOrFail ctx s!"Interop ORC test1 «{col}»" e.toString

def runInteropOrcInt32 (ctx : Harness.Ctx) : IO Unit := do
  let p := Fixtures.interopOrcInt32
  unless ← p.pathExists do
    Harness.info "Interop ORC int32: SKIP (Tests/fixtures/interop_orc_int32.orc missing; run scripts/export_interop_goldens.py)"
    return
  unless ← goldenInt32XPath.pathExists do
    Harness.fail ctx "Interop ORC int32: golden sidecar missing"
    return
  match ← GoldenFmt.parseFile goldenInt32XPath with
  | .error e => Harness.fail ctx s!"Interop ORC int32: {e}"
  | .ok gspec =>
    try
      match ← Columnar.Orc.Reader.readOrcPrimitives p ["x"] with
      | .error e => Harness.fail ctx s!"Interop ORC readOrcPrimitives: {e}"
      | .ok tbl =>
        match GoldenFmt.goldenMatches tbl gspec with
        | .error e => Harness.fail ctx s!"Interop ORC int32 golden: {e}"
        | .ok _ => Harness.info "Interop ORC int32: OK interop_orc_int32.orc column «x»"
    catch e =>
      Harness.fail ctx s!"Interop ORC int32: IO {e}"

def run (ctx : Harness.Ctx) : IO Unit := do
  runVendorFooterRows ctx
  runVendorTest1Columns ctx
  runInteropOrcInt32 ctx

end Tests.Conformance.OrcInterop
