import Columnar.Core.Bits
import Columnar.Core.Result
import Columnar.Core.Bytes
import Tests.Harness

open Columnar
open Columnar.ByteArrayOps

namespace Tests.Unit.CoreBits

/-- ULEB128 of 127 is single byte 0x7f -/
def testULEB127 (ctx : Harness.Ctx) : IO Unit := do
  let b : ByteArray := ByteArray.mk #[0x7f]
  match readULEB128 b 0 with
  | Except.error e => Harness.fail ctx s!"ULEB127: {e}"
  | Except.ok (v, pos) =>
    Harness.check ctx "ULEB127 value" (v == 127)
    Harness.check ctx "ULEB127 pos" (pos == 1)

def testZigZag (ctx : Harness.Ctx) : IO Unit := do
  Harness.check ctx "zigzag 0" (zigzagDecode 0 == 0)
  Harness.check ctx "zigzag 1" (zigzagDecode 1 == -1)

/-- IEEE float32 3.0 as little-endian word 0x4040_0000 (bit pattern, not integer 1077936128). -/
def testFloat32Bits (ctx : Harness.Ctx) : IO Unit := do
  let b : ByteArray := ByteArray.mk #[0x00, 0x00, 0x40, 0x40]
  match readFloat32LE b 0 with
  | none => Harness.fail ctx "readFloat32LE: expected 4 bytes"
  | some f =>
    Harness.check ctx "float32 LE is bit-cast" (Float.beq f (Float.ofNat 3))

def run (ctx : Harness.Ctx) : IO Unit := do
  testULEB127 ctx
  testZigZag ctx
  testFloat32Bits ctx

end Tests.Unit.CoreBits
