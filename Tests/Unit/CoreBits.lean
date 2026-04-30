import Columnar.Core.Bits
import Columnar.Core.Result
import Tests.Harness

open Columnar

namespace Tests.Unit.CoreBits

/-- ULEB128 of 127 is single byte 0x7f -/
def testULEB127 (log : Harness.ErrLog) : IO Unit := do
  let b : ByteArray := ByteArray.mk #[0x7f]
  match readULEB128 b 0 with
  | Except.error e => Harness.fail log s!"ULEB127: {e}"
  | Except.ok (v, pos) =>
    Harness.check log "ULEB127 value" (v == 127)
    Harness.check log "ULEB127 pos" (pos == 1)

def testZigZag (log : Harness.ErrLog) : IO Unit := do
  Harness.check log "zigzag 0" (zigzagDecode 0 == 0)
  Harness.check log "zigzag 1" (zigzagDecode 1 == -1)

def run (log : Harness.ErrLog) : IO Unit := do
  testULEB127 log
  testZigZag log

end Tests.Unit.CoreBits
