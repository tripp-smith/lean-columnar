import Init.System.FilePath
import Columnar.Table

namespace Columnar.Parquet.Writer

/-- Write `Table` to Parquet (placeholder; full writer in Phase 2). -/
def writeParquet (_ : Table) (_path : System.FilePath) : IO Unit :=
  throw (IO.userError "writeParquet: not yet implemented (Phase 2)")

end Columnar.Parquet.Writer
