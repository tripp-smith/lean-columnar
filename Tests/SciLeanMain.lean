import Tests.Harness
import Tests.SciLean.Unit

open Tests.Harness

def main : IO UInt32 := do
  let ctx ← mkCtx
  group "SciLean: tensor bridge" (Tests.SciLean.Unit.run ctx)
  finish ctx
