import Init.System.IO
import Tests.Harness
import Tests.Unit.CoreBits
import Tests.Unit.ThriftCompact
import Tests.Unit.SciLeanBridge
import Tests.Unit.PlainViews
import Tests.Unit.CodecContract
import Tests.Conformance.ParquetPhase0
import Tests.Conformance.ParquetMmap
import Tests.Conformance.ParquetGoldens
import Tests.Conformance.ParquetPhase1Encoding
import Tests.Conformance.ParquetNestedLevels
import Tests.Conformance.ParquetStreamPushdown
import Tests.Conformance.ParquetWriterRoundtrip
import Tests.Conformance.InteropFingerprints
import Tests.Conformance.AvroInterop
import Tests.Conformance.OrcInterop
import Tests.Conformance.ArrowInterop
import Tests.Conformance.Placeholder

open Tests.Harness

/-- `lake exe tests` — unit checks + optional parquet-testing conformance.

Interop vendor suites run **before** Parquet mmap/stream groups (native mmap teardown has faulted later
tests on some macOS builds).

`Tests.Unit.CodecContract` runs **last**: when native system codecs are linked, exercising them
before other tests has been observed to corrupt the heap on some setups (see `Tests/Harness.lean`).

On **macOS**, Parquet reader conformance is skipped unless `COLUMNAR_PARQUET_READER_OSX=1` (see
`Tests/Harness.skipHeavyParquetReaderOnOSX` and `docs/Conformance.md`). -/
def main : IO UInt32 := do
  let ctx ← mkCtx
  group "Unit: Core.Bits" (Tests.Unit.CoreBits.run ctx)
  group "Unit: Thrift compact (BYTE, I16, MAP)" (Tests.Unit.ThriftCompact.run ctx)
  group "Unit: SciLean tensor bridge shim" (Tests.Unit.SciLeanBridge.run ctx)
  group "Unit: Table plain packed views" (Tests.Unit.PlainViews.run ctx)
  -- Run interop before Parquet mmap/stream: native mmap teardown has faulted later groups on some macOS builds.
  group "Interop: vendor format fingerprints" (Tests.Conformance.InteropFingerprints.run ctx)
  group "Interop: Avro OCF values" (Tests.Conformance.AvroInterop.run ctx)
  group "Interop: Arrow IPC stream walk" (Tests.Conformance.ArrowInterop.run ctx)
  group "Interop: ORC footer rows" (Tests.Conformance.OrcInterop.run ctx)
  group "Conformance: Parquet value goldens" (Tests.Conformance.ParquetGoldens.run ctx)
  group "Conformance: mmap + streamRowGroups" (Tests.Conformance.ParquetMmap.run ctx)
  group "Conformance: Parquet Phase0 decode smoke" (Tests.Conformance.ParquetPhase0.run ctx)
  group "Conformance: nested levels (list_columns)" (Tests.Conformance.ParquetNestedLevels.run ctx)
  group "Conformance: stream + predicate stats" (Tests.Conformance.ParquetStreamPushdown.run ctx)
  group "Conformance: Phase1 encoding matrix" (Tests.Conformance.ParquetPhase1Encoding.run ctx)
  group "Conformance: Parquet writer round-trip (Lean)" (Tests.Conformance.ParquetWriterRoundtrip.run ctx)
  group "Roadmap: remaining stubs" do
    Tests.Conformance.Placeholder.runPhase2 ctx
    Tests.Conformance.Placeholder.runProperty ctx
  group "Unit: Codec FFI contract" (Tests.Unit.CodecContract.run ctx)
  finish ctx
