import Init.System.IO
import Columnar.Arrow.IPC
import Tests.Fixtures
import Tests.GoldenFmt
import Tests.Harness

namespace Tests.Conformance.ArrowInterop

def goldenMessagesPath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_arrow_schema_v6_messages.txt"]

def goldenInt32StreamXPath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_arrow_int32_stream__x.txt"]

def goldenInt32FileXPath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_arrow_int32_file__x.txt"]

private def expectNatGolden (path : System.FilePath) : IO (Except String Nat) := do
  let t ← IO.FS.readFile path
  let line := (String.trimAscii t).toString
  match line.toNat? with
  | none => return .error "golden: expected decimal Nat line"
  | some n => return .ok n

def runVendorMessageCount (ctx : Harness.Ctx) : IO Unit := do
  let p := Fixtures.arrowSchemaV6
  unless ← p.pathExists do
    Harness.info "Interop Arrow IPC: SKIP vendor schema_v6 (vendor/arrow-testing missing)"
    return
  unless ← goldenMessagesPath.pathExists do
    Harness.fail ctx "Interop Arrow IPC: golden sidecar missing"
    return
  match ← expectNatGolden goldenMessagesPath with
  | .error e => Harness.fail ctx e
  | .ok want =>
    let bytes ← IO.FS.readBinFile p
    match Columnar.Arrow.IPC.ipcStreamMessageCount bytes with
    | .error e => Harness.fail ctx s!"Arrow IPC walk: {e}"
    | .ok got =>
      Harness.check ctx s!"Arrow IPC schema_v6.arrow message count ({got})" (got == want)
      Harness.info s!"Interop Arrow IPC: OK messages={got}"

def runInteropStream (ctx : Harness.Ctx) : IO Unit := do
  let p := Fixtures.interopArrowInt32Stream
  unless ← p.pathExists do
    Harness.info "Interop Arrow IPC stream: SKIP (Tests/fixtures/interop_arrow_int32_stream.arrow missing; run scripts/export_interop_goldens.py)"
    return
  unless ← goldenInt32StreamXPath.pathExists do
    Harness.fail ctx "Interop Arrow IPC stream: golden sidecar missing"
    return
  match ← GoldenFmt.parseFile goldenInt32StreamXPath with
  | .error e => Harness.fail ctx e
  | .ok gspec =>
    match ← Columnar.Arrow.IPC.readArrowIpcStreamFile p with
    | .error e => Harness.fail ctx s!"Arrow IPC readArrowIpcStreamFile: {e}"
    | .ok tbl =>
      match GoldenFmt.goldenMatches tbl gspec with
      | .error e => Harness.fail ctx s!"Interop Arrow IPC stream golden: {e}"
      | .ok _ => Harness.info "Interop Arrow IPC stream: OK interop_arrow_int32_stream.arrow column «x»"

def runInteropFile (ctx : Harness.Ctx) : IO Unit := do
  let p := Fixtures.interopArrowInt32File
  unless ← p.pathExists do
    Harness.info "Interop Arrow IPC file: SKIP (Tests/fixtures/interop_arrow_int32_file.arrow missing; run scripts/export_interop_goldens.py)"
    return
  unless ← goldenInt32FileXPath.pathExists do
    Harness.fail ctx "Interop Arrow IPC file: golden sidecar missing"
    return
  match ← GoldenFmt.parseFile goldenInt32FileXPath with
  | .error e => Harness.fail ctx e
  | .ok gspec =>
    match ← Columnar.Arrow.IPC.readArrowIpcFile p with
    | .error e => Harness.fail ctx s!"Arrow IPC readArrowIpcFile: {e}"
    | .ok tbl =>
      match GoldenFmt.goldenMatches tbl gspec with
      | .error e => Harness.fail ctx s!"Interop Arrow IPC file golden: {e}"
      | .ok _ => Harness.info "Interop Arrow IPC file: OK interop_arrow_int32_file.arrow column «x»"

def run (ctx : Harness.Ctx) : IO Unit := do
  runVendorMessageCount ctx
  runInteropStream ctx
  runInteropFile ctx

end Tests.Conformance.ArrowInterop
