import Columnar.Parquet.Encoding.Plain

namespace Columnar

structure Column where
  name : String
  values : Array (Option Parquet.Encoding.Plain.PlainValue)

structure Table where
  columns : Array Column

end Columnar
