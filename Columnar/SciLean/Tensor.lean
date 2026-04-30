import Columnar.Table

/-! Optional SciLean bridge (see plan §3.4).

Add `SciLean` as a Lake dependency and build with your project's config flag when ready.
This module stays dependency-free so the default package builds without SciLean.
-/

namespace Columnar.SciLean

/-- Placeholder for tensor / `DataArrayN` coercions from `Table`. -/
structure TensorBridge where
  /-- Row count hint for shape inference. -/
  rows : Nat

def TensorBridge.ofTable (_ : Columnar.Table) : TensorBridge :=
  { rows := 0 }

end Columnar.SciLean
