import Columnar.Parquet.Metadata

namespace Columnar.Parquet.Stream

/-- Lazy row-group iterator (placeholder). -/
structure RowGroupStream where
  fileMeta : FileMetaDataParsed
  idx : Nat

def Stream.init (fileMeta : FileMetaDataParsed) : RowGroupStream := { fileMeta, idx := 0 }

end Columnar.Parquet.Stream
