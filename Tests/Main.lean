import Init.System.IO
import Tests.Harness
import Tests.Unit.CoreBits
import Tests.Conformance.ParquetPhase0
import Tests.Conformance.Placeholder

open Tests.Harness

/-- `lake exe tests` — unit checks + optional parquet-testing conformance. -/
def main : IO UInt32 := do
  let log ← mkLog
  group "Unit: Core.Bits" (Tests.Unit.CoreBits.run log)
  group "Conformance: Parquet Phase0" (Tests.Conformance.ParquetPhase0.run log)
  group "Roadmap gates" do
    Tests.Conformance.Placeholder.runPhase1 log
    Tests.Conformance.Placeholder.runPhase2 log
    Tests.Conformance.Placeholder.runAvro log
    Tests.Conformance.Placeholder.runOrc log
    Tests.Conformance.Placeholder.runArrow log
    Tests.Conformance.Placeholder.runProperty log
  finish log
