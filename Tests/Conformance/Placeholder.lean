import Tests.Harness

/-! Full-suite gates for later phases (Avro / ORC / Arrow / property tests). -/

namespace Tests.Conformance.Placeholder

def runPhase1 (_ : Harness.ErrLog) : IO Unit :=
  Harness.info "Parquet Phase1 full corpus: PLANNED (dictionary/delta/v2/...)"

def runPhase2 (_ : Harness.ErrLog) : IO Unit :=
  Harness.info "Parquet Phase2 writer/stream/pushdown: PLANNED"

def runAvro (_ : Harness.ErrLog) : IO Unit :=
  Harness.info "Avro conformance: PLANNED (vendor/avro share/test)"

def runOrc (_ : Harness.ErrLog) : IO Unit :=
  Harness.info "ORC conformance: PLANNED (vendor/orc examples)"

def runArrow (_ : Harness.ErrLog) : IO Unit :=
  Harness.info "Arrow IPC conformance: PLANNED (vendor/arrow-testing)"

def runProperty (_ : Harness.ErrLog) : IO Unit :=
  Harness.info "Property tests (pyarrow round-trip): PLANNED (see scripts/)"

end Tests.Conformance.Placeholder
