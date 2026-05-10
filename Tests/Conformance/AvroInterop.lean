import Columnar.Avro.Container
import Tests.Fixtures
import Tests.GoldenFmt
import Tests.Harness

namespace Tests.Conformance.AvroInterop

def goldenPath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_avro_minimal__id.txt"]

def goldenSnappyPath : System.FilePath :=
  System.mkFilePath ["Tests", "goldens", "interop_avro_snappy__id.txt"]

private def needsCodecEnv (msg : String) : Bool :=
  ["snappy", "zstd", "zlib", "gzip", "brotli", "lz4"].any fun sub => msg.contains sub ||
  msg.contains "unavailable" || msg.contains "COLUMNAR_CODEC"

def run (ctx : Harness.Ctx) : IO Unit := do
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
      | .error e =>
        if needsCodecEnv e then
          Harness.info s!"Interop Avro Snappy: SKIP ({e})"
        else
          Harness.fail ctx s!"Interop Avro Snappy readAvroOcf: {e}"
      | .ok tbl2 =>
        match GoldenFmt.goldenMatches tbl2 gspec2 with
        | .error e => Harness.fail ctx s!"Interop Avro Snappy golden: {e}"
        | .ok _ => Harness.info "Interop Avro Snappy: OK interop_minimal_snappy.avro column «id»"
    catch e =>
      let msg := e.toString
      if needsCodecEnv msg then
        Harness.info s!"Interop Avro Snappy: SKIP (IO: {msg})"
      else
        Harness.fail ctx s!"Interop Avro Snappy: IO {msg}"

end Tests.Conformance.AvroInterop
