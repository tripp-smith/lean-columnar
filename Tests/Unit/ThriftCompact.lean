import Init.Data.ByteArray
import Columnar.Thrift.Compact
import Tests.Harness

namespace Tests.Unit.ThriftCompact

open Columnar

def run (ctx : Harness.Ctx) : IO Unit := do
  let tr0 : Thrift.TReader := { bytes := ByteArray.mk #[0], pos := 0 }
  match Thrift.readTValue 11 tr0 with
  | .error e => Harness.fail ctx s!"Thrift empty map: {e}"
  | .ok (tv, tr') =>
      match tv with
      | .tmap _ _ xs =>
          Harness.check ctx "Thrift empty map size" (xs.size == 0)
          Harness.check ctx "Thrift empty map consumed 1 byte" (tr'.pos == 1)
      | _ => Harness.fail ctx "Thrift: expected tmap"
  let tr1 : Thrift.TReader := { bytes := ByteArray.mk #[0xff], pos := 0 }
  match Thrift.readTValue 3 tr1 with
  | .error e => Harness.fail ctx s!"Thrift byte: {e}"
  | .ok (tv, tr') =>
      match tv with
      | .ti32 n =>
          Harness.check ctx "Thrift BYTE sign-extends" (n == (-1 : Int32))
          Harness.check ctx "Thrift BYTE consumed" (tr'.pos == 1)
      | _ => Harness.fail ctx "Thrift: expected ti32"

end Tests.Unit.ThriftCompact
