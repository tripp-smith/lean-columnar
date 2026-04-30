namespace Columnar.Parquet.Filter

inductive Pred where
  | eqStr (col : String) (v : String)
  | ltInt (col : String) (v : Int)
  | and (a b : Pred)
  deriving Repr

/-- Predicate pushdown hook (statistics / page index wired in Phase 2). -/
def Pred.matches (_ : Pred) : Bool := true

end Columnar.Parquet.Filter
