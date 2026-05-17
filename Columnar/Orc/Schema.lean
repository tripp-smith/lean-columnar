namespace Columnar.Orc.Schema

/-- ORC `Type.Kind` values used by the interop reader (subset). -/
inductive OrcKind where
  | boolean | byte | short | int | long | float | double | string | binary | struct
  deriving Repr, BEq

def orcKindFromNat (k : Nat) : Option OrcKind :=
  match k with
  | 0 => some .boolean
  | 1 => some .byte
  | 2 => some .short
  | 3 => some .int
  | 4 => some .long
  | 5 => some .float
  | 6 => some .double
  | 7 => some .string
  | 8 => some .binary
  | 12 => some .struct
  | _ => none

structure OrcTypeNode where
  kind : OrcKind
  name : Option String
  subtypes : List Nat

end Columnar.Orc.Schema
