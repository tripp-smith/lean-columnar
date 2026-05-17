import Columnar.Avro.Container
import Tests.Fixtures
import Tests.GoldenFmt
import Tests.Harness

namespace Tests.Conformance.AvroInterop

def goldenPath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_avro_minimal__id.txt"]

def goldenSnappyPath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_avro_snappy__id.txt"]

def goldenVendorSimplePath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_avro_vendor_simple__text.txt"]

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

def runMinimal (ctx : Harness.Ctx) : IO Unit := do
  let p := Fixtures.interopMinimalAvro
  unless ← p.pathExists do
    Harness.info "Interop Avro: SKIP (Tests/fixtures/interop_minimal.avro missing; run scripts/export_interop_goldens.py)"
    return
  unless ← goldenPath.pathExists do
    Harness.fail ctx "Interop Avro: golden sidecar missing"
    return
  match ← GoldenFmt.parseFile goldenPath with
  | .error e => Harness.fail ctx s!"Interop Avro: {e}"
  | .ok gspec =>
    match ← Columnar.Avro.Container.readAvroOcf p with
    | .error e => Harness.fail ctx s!"Interop Avro readAvroOcf: {e}"
    | .ok tbl =>
      match GoldenFmt.goldenMatches tbl gspec with
      | .error e => Harness.fail ctx s!"Interop Avro golden: {e}"
      | .ok _ => Harness.info "Interop Avro: OK interop_minimal.avro column «id»"

def runSnappy (ctx : Harness.Ctx) : IO Unit := do
  let ps := Fixtures.interopMinimalAvroSnappy
  unless ← ps.pathExists do
    Harness.info "Interop Avro Snappy: SKIP (Tests/fixtures/interop_minimal_snappy.avro missing; run scripts/export_interop_goldens.py)"
    return
  unless ← goldenSnappyPath.pathExists do
    Harness.fail ctx "Interop Avro Snappy: golden sidecar missing"
    return
  match ← GoldenFmt.parseFile goldenSnappyPath with
  | .error e => Harness.fail ctx s!"Interop Avro Snappy: {e}"
  | .ok gspec2 =>
    try
      match ← Columnar.Avro.Container.readAvroOcf ps with
      | .error e => codecSkipOrFail ctx "Interop Avro Snappy" e
      | .ok tbl2 =>
        match GoldenFmt.goldenMatches tbl2 gspec2 with
        | .error e => Harness.fail ctx s!"Interop Avro Snappy golden: {e}"
        | .ok _ => Harness.info "Interop Avro Snappy: OK interop_minimal_snappy.avro column «id»"
    catch e =>
      codecSkipOrFail ctx "Interop Avro Snappy" e.toString

def runVendorSimple (ctx : Harness.Ctx) : IO Unit := do
  let p := Fixtures.avroVendorSimple
  unless ← p.pathExists do
    Harness.info "Interop Avro vendor: SKIP (vendor/avro missing)"
    return
  unless ← goldenVendorSimplePath.pathExists do
    Harness.info "Interop Avro vendor: SKIP (golden missing; run scripts/export_interop_goldens.py with vendor/avro)"
    return
  match ← GoldenFmt.parseFile goldenVendorSimplePath with
  | .error e => Harness.fail ctx s!"Interop Avro vendor: {e}"
  | .ok gspec =>
    match ← Columnar.Avro.Container.readAvroOcf p with
    | .error e => Harness.fail ctx s!"Interop Avro vendor readAvroOcf: {e}"
    | .ok tbl =>
      match GoldenFmt.goldenMatches tbl gspec with
      | .error e => Harness.fail ctx s!"Interop Avro vendor golden: {e}"
      | .ok _ => Harness.info "Interop Avro vendor: OK schemas/simple/data.avro column «text»"

def run (ctx : Harness.Ctx) : IO Unit := do
  runMinimal ctx
  runSnappy ctx
  runVendorSimple ctx

end Tests.Conformance.AvroInterop
