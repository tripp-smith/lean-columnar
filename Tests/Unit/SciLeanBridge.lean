import Init.Data.Int
import Tests.Harness
import Columnar.Table
import Columnar.Parquet.Encoding.Plain
import Columnar.SciLean.Tensor

open Columnar
open Columnar.SciLean
open Columnar.Parquet.Encoding.Plain

namespace Tests.Unit.SciLeanBridge

def smallTable : Table :=
  let vals := (List.range 3).map (fun i => some (PlainValue.int32 (Int32.ofNat i))) |>.toArray
  { columns := #[{ name := "a", values := vals }] }

def run (ctx : Harness.Ctx) : IO Unit := do
  let b := TensorBridge.ofTable smallTable
  Harness.check ctx "TensorBridge row count tracks first column" (b.rows == 3)
  Harness.check ctx "TensorBridge cols" (b.cols == 1)
  Harness.info "SciLean bridge: OK (TensorBridge shim; real tensors: COLUMNAR_SCILEAN=1 lake update + scripts/with_scilean.sh)"

end Tests.Unit.SciLeanBridge
