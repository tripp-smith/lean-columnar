import Columnar.Table

/-! Optional SciLean bridge (see plan §3.4).

Add `SciLean` as a Lake dependency and build with your project's config flag when ready.
This module stays dependency-free so the default package builds without SciLean.
-/

namespace Columnar.SciLean

/-- Shape hints for SciLean conversion (`rows × cols`). See `Columnar.SciLean.Convert` when built with `-Kcolumnar.scilean=1`. -/
structure TensorBridge where
  /-- Row count from the table (first column length). -/
  rows : Nat
  /-- Number of columns in the table. -/
  cols : Nat

def TensorBridge.ofTable (t : Columnar.Table) : TensorBridge :=
  { rows := Columnar.Table.rowCount t, cols := t.columns.size }

end Columnar.SciLean
