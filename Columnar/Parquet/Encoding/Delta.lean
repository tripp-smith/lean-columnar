import Columnar.Parquet.Types

/-! DELTA_* encodings (Phase 1). See plan §3.1. -/

namespace Columnar.Parquet.Encoding.Delta

def stubNote : String :=
  "Delta encodings: planned (DELTA_BINARY_PACKED, DELTA_LENGTH_BYTE_ARRAY, DELTA_BYTE_ARRAY)"

end Columnar.Parquet.Encoding.Delta
