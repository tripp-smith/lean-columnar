namespace Columnar.Parquet.Filter

inductive Pred where
  | eqStr (col : String) (v : String)
  | ltInt (col : String) (v : Int)
  | and (a b : Pred)
  deriving Repr

structure ColumnStats where
  minI64 : Option Int64 := none
  maxI64 : Option Int64 := none

abbrev StatsAssoc := Array (String × ColumnStats)

def lookupStats (stats : StatsAssoc) (col : String) : Option ColumnStats :=
  stats.findSome? fun (k, v) => if k == col then some v else none

/-- Conservatively decides whether *any* row in the referenced row-group could satisfy `pred`.
When no stats exist for `col`, returns `true` (don't skip).

`ltInt`: if `col` stores only values ≥ threshold (min ≥ `v`), the row-group can be skipped. -/
def Pred.matches (p : Pred) (stats : StatsAssoc) : Bool :=
  match p with
  | .eqStr _ _ =>
    -- Without string min/max histograms treat as potentially matching.
    true
  | .ltInt col v =>
      match lookupStats stats col with
      | none => true
      | some s =>
        match s.minI64 with
        | none => true
        | some mn => mn.toInt < v
  | .and a b => Pred.matches a stats && Pred.matches b stats

end Columnar.Parquet.Filter
