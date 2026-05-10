import Tests.Harness
import Columnar.Table
import Columnar.Parquet.Encoding.Plain
import Columnar.SciLean.Convert
import SciLean.Util.SorryProof

open Columnar
open Columnar.Parquet.Encoding.Plain
open Columnar.SciLean.Convert

namespace Tests.SciLean.Unit

def approxEq (a b : Float) (ε : Float := 1e-9) : Bool :=
  Float.abs (a - b) ≤ ε || (a.isNaN && b.isNaN)

def tinyTable : Table :=
  { columns := #[
      { name := "x", values := #[some (.double 1.0), some (.double 2.0)] },
      { name := "y", values := #[some (.double 3.0), some (.double 4.0)] }
    ] }

def run (ctx : Harness.Ctx) : IO Unit := do
  match tableToFloatDataArray tinyTable with
  | Except.error e => Harness.fail ctx s!"tableToFloatDataArray: {e}"
  | Except.ok (da, rows, cols, _) =>
    Harness.check ctx "shape rows" (rows == 2)
    Harness.check ctx "shape cols" (cols == 2)
    Harness.check ctx "flat length" (da.size == 4)
    -- row-major: (0,0)=1 (0,1)=3 (1,0)=2 (1,1)=4
    let v00 := da.get ⟨USize.ofNat 0, sorry_proof⟩
    let v01 := da.get ⟨USize.ofNat 1, sorry_proof⟩
    let v10 := da.get ⟨USize.ofNat 2, sorry_proof⟩
    let v11 := da.get ⟨USize.ofNat 3, sorry_proof⟩
    Harness.check ctx "v00" (approxEq v00 1.0)
    Harness.check ctx "v01" (approxEq v01 3.0)
    Harness.check ctx "v10" (approxEq v10 2.0)
    Harness.check ctx "v11" (approxEq v11 4.0)
    match floatDataArrayToTable rows cols da #["x", "y"] with
    | Except.error e => Harness.fail ctx s!"floatDataArrayToTable: {e}"
    | Except.ok t2 =>
      match tableToFloatDataArray t2 with
      | Except.error e => Harness.fail ctx s!"round-trip encode: {e}"
      | Except.ok (da2, _, _, _) =>
        Harness.check ctx "round-trip size" (da2.size == da.size)
        for i in [:da.size] do
          let a := da.get ⟨USize.ofNat i, sorry_proof⟩
          let b := da2.get ⟨USize.ofNat i, sorry_proof⟩
          unless approxEq a b do Harness.fail ctx s!"round-trip idx {i}"

end Tests.SciLean.Unit
