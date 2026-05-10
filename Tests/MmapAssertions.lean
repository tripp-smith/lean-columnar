import Columnar.Parquet.Encoding.Plain
import Columnar.Table

namespace Tests.MmapAssertions

open Columnar.Parquet.Encoding.Plain

mutual
  def plainValueEq (x y : PlainValue) : Bool :=
    match x, y with
    | .null, .null => true
    | .bool b1, .bool b2 => b1 == b2
    | .int32 n1, .int32 n2 => n1 == n2
    | .int64 n1, .int64 n2 => n1 == n2
    | .float f1, .float f2 => f1 == f2
    | .double f1, .double f2 => f1 == f2
    | .byteArray b1, .byteArray b2 => b1 == b2
    | _, _ => false

  def optPlainEq (x y : Option PlainValue) : Bool :=
    match x, y with
    | none, none => true
    | some a, some b => plainValueEq a b
    | _, _ => false
end

def columnValuesEq (va vb : Array (Option PlainValue)) : Bool :=
  va.size == vb.size && (va.zip vb).all fun p => optPlainEq p.1 p.2

def tablesEqual (a b : Columnar.Table) : Bool :=
  a.columns.size == b.columns.size &&
  (a.columns.zip b.columns).all fun pr =>
    let (ca, cb) := pr
    ca.name == cb.name && columnValuesEq ca.values cb.values

end Tests.MmapAssertions
