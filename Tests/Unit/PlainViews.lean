import Columnar.Table
import Columnar.Table.PlainViews
import Columnar.Parquet.Encoding.Plain
import Tests.Harness

namespace Tests.Unit.PlainViews

open Columnar.Parquet.Encoding.Plain

def run (ctx : Harness.Ctx) : IO Unit := do
  let c : Columnar.Column :=
    { name := "x",
      values := #[some (.int64 (Int64.ofNat 1)), some (.int64 (Int64.ofNat 2))] }
  match Columnar.Table.Column.plainInt64PackedBytes? c with
  | none => Harness.fail ctx "plainInt64PackedBytes? expected some"
  | some b =>
    if b.size != 16 then Harness.fail ctx "packed int64 size"
    else pure ()
  match Columnar.Table.Column.plainInt64PackedSubarray? c with
  | none => Harness.fail ctx "plainInt64PackedSubarray? expected some"
  | some s =>
    if s.size != 16 then Harness.fail ctx "packed subarray byte length"
    else pure ()
  Harness.info "PlainViews: OK"

end Tests.Unit.PlainViews
