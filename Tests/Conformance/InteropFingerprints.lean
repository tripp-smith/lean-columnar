import Init.System.FilePath
import Columnar.Avro.Container
import Columnar.Arrow.IPC
import Columnar.Orc.Reader
import Tests.Fixtures
import Tests.Harness

namespace Tests.Conformance.InteropFingerprints

/-- Read at most `cap` bytes from the start of `path` (never loads the whole file). -/
def readPrefix (path : System.FilePath) (cap : Nat) : IO ByteArray := do
  let n := USize.ofNat cap
  IO.FS.withFile path .read fun h => h.read n

def run (ctx : Harness.Ctx) : IO Unit := do
  let avro := System.mkFilePath
    ["vendor", "avro", "share", "test", "interop", "rpc", "echo", "foo", "request.avro"]
  if ← avro.pathExists then
    let pre ← readPrefix avro 8
    Harness.check ctx "Avro OCF magic" (Columnar.Avro.Container.bytesLikelyOcf pre)
    Harness.info "Interop: Avro fingerprint OK"
  else
    Harness.info "Interop Avro: SKIP (vendor/avro)"

  let orc := System.mkFilePath ["vendor", "orc", "examples", "TestOrcFile.test1.orc"]
  if ← orc.pathExists then
    let pre ← readPrefix orc 8
    Harness.check ctx "ORC magic" (Columnar.Orc.Reader.bytesLikelyOrc pre)
    Harness.info "Interop: ORC fingerprint OK"
  else
    Harness.info "Interop ORC: SKIP (vendor/orc)"

  let arrow := System.mkFilePath
    ["vendor", "arrow-testing", "data", "forward-compatibility", "schema_v6.arrow"]
  if ← arrow.pathExists then
    let pre ← readPrefix arrow 8
    Harness.check ctx "Arrow IPC stream framing" (Columnar.Arrow.IPC.ipcStreamLooksFramed pre)
    Harness.info "Interop: Arrow IPC framing OK"
  else
    Harness.info "Interop Arrow: SKIP (vendor/arrow-testing)"

end Tests.Conformance.InteropFingerprints
