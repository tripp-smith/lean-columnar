import Columnar.Orc.Reader
import Tests.Fixtures
import Tests.GoldenFmt
import Tests.Harness

namespace Tests.Conformance.OrcInterop

def goldenRowsPath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_orc_test1_rows.txt"]

def goldenInt32XPath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_orc_int32__x.txt"]

private def expectNatGolden (path : System.FilePath) : IO (Except String Nat) := do
  let t ← IO.FS.readFile path
  let line := (String.trimAscii t).toString
  match line.toNat? with
  | none => return .error "golden: expected decimal Nat line"
  | some n => return .ok n

private def needsCodecEnv (msg : String) : Bool :=
  ["snappy", "zstd", "zlib", "gzip", "brotli", "lz4"].any fun sub => msg.contains sub ||
  msg.contains "unavailable" || msg.contains "COLUMNAR_CODEC"

def run (ctx : Harness.Ctx) : IO Unit := do
  let p := Fixtures.orcTest1
  unless ← p.pathExists do
    Harness.info "Interop ORC: SKIP (vendor/orc missing)"
    return
  unless ← goldenRowsPath.pathExists do
    Harness.fail ctx "Interop ORC: golden sidecar missing"
    return
  match ← expectNatGolden goldenRowsPath with
  | .error e => Harness.fail ctx e
  | .ok want =>
    try
      match ← Columnar.Orc.Reader.readOrcNumberOfRows p with
      | .error e =>
        if needsCodecEnv e then
          Harness.info s!"Interop ORC: SKIP ({e})"
        else
          Harness.fail ctx s!"Interop ORC readFooter: {e}"
      | .ok got =>
        Harness.check ctx s!"ORC TestOrcFile.test1.orc footer rows ({got})" (got == want)
        Harness.info s!"Interop ORC: OK rows={got}"
    catch e =>
      let msg := e.toString
      if needsCodecEnv msg then
        Harness.info s!"Interop ORC: SKIP (IO: {msg})"
      else
        Harness.fail ctx s!"Interop ORC: IO {msg}"
  let p2 := Fixtures.interopOrcInt32
  unless ← p2.pathExists do
    Harness.info "Interop ORC int32: SKIP (Tests/fixtures/interop_orc_int32.orc missing; run scripts/export_interop_goldens.py)"
    return
  unless ← goldenInt32XPath.pathExists do
    Harness.fail ctx "Interop ORC int32: golden sidecar missing"
    return
  match ← GoldenFmt.parseFile goldenInt32XPath with
  | .error e => Harness.fail ctx s!"Interop ORC int32: {e}"
  | .ok gspec =>
    try
      match ← Columnar.Orc.Reader.readOrcPrimitives p2 ["x"] with
      | .error e => Harness.fail ctx s!"Interop ORC readOrcPrimitives: {e}"
      | .ok tbl =>
        match GoldenFmt.goldenMatches tbl gspec with
        | .error e => Harness.fail ctx s!"Interop ORC int32 golden: {e}"
        | .ok _ => Harness.info "Interop ORC int32: OK interop_orc_int32.orc column «x»"
    catch e =>
      Harness.fail ctx s!"Interop ORC int32: IO {e}"

end Tests.Conformance.OrcInterop
