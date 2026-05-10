import Columnar.Parquet.Encoding.Plain

namespace Columnar

structure Column where
  name : String
  values : Array (Option Parquet.Encoding.Plain.PlainValue)

structure Table where
  columns : Array Column

/-- Rows from the first column length (tables are column-regular in this codebase). -/
def Table.rowCount (t : Table) : Nat :=
  if h : 0 < t.columns.size then (t.columns[0]'h).values.size else 0

/-- Contiguous row slice: each column uses `Array.extract` on its value array. -/
def Table.sliceRows (t : Table) (start len : Nat) : Except String Table := do
  let n := rowCount t
  if start + len > n then throw "Table.sliceRows: range exceeds row count"
  let mut cols : Array Column := #[]
  for c in t.columns do
    if c.values.size != n then throw "Table.sliceRows: irregular column lengths"
    cols := cols.push { name := c.name, values := c.values.extract start (start + len) }
  return { columns := cols }

/-- Append rows from `b` to `a` (same column count, names, and order). -/
def Table.appendRows (a b : Table) : Except String Table := do
  if a.columns.size != b.columns.size then throw "appendRows: column count mismatch"
  let mut cols : Array Column := #[]
  for pr in a.columns.zip b.columns do
    let (ca, cb) := pr
    if ca.name != cb.name then throw s!"appendRows: column name mismatch {repr ca.name} vs {repr cb.name}"
    cols := cols.push { name := ca.name, values := ca.values ++ cb.values }
  return { columns := cols }

end Columnar
