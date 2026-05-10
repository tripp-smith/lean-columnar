import Columnar.Parquet.Types
import Columnar.Parquet.Encoding.Plain
import Columnar.Parquet.Writer.Encode.Plain

open Columnar.Parquet
open Columnar.Parquet.Encoding.Plain
open Columnar.Parquet.Writer.Encode.Plain

namespace Columnar.Parquet.Proofs

theorem phys_int32 : PhysType.int32 = 1 := rfl

/-! ## Minimal flat-schema DSL (parity-only; not full Parquet evolution). -/

inductive FlatPhys where
  | int32 | int64 | float | double | boolean | byte_array
  deriving DecidableEq, Repr

abbrev FlatSchema := List FlatPhys

def schemaCompatible (s1 s2 : FlatSchema) : Prop :=
  s1 = s2

instance decidableSchemaCompatible (s1 s2 : FlatSchema) :
    Decidable (schemaCompatible s1 s2) :=
  inferInstanceAs (Decidable (s1 = s2))

/-! ### PLAIN `int32` round-trip (illustrative constant)

The encoder and decoder agree definitionally for fixed literals; a uniform `∀ i : Int32` lemma is left
to Mathlib-grade bit-vector finishing (see discussion in `plainUInt32Bytes` / `readUInt32LE`).

Keep at least one non-trivial, `sorry`-free statement checked by CI: decoding an encoded PLAIN cell.
-/

/-- Same bytes as `encodePlainOne PhysType.int32` for `PlainValue.int32 (Int32.ofNat 7)`. -/
private def plainUInt32Bytes_demo : ByteArray :=
  appendUInt32LE ByteArray.empty (Int32.ofNat 7).toUInt32

/-- Constant-folded PLAIN `int32` round-trip (single cell, no nulls). -/
theorem plain_int32_roundtrip_demo :
    decodeOne PhysType.int32 plainUInt32Bytes_demo 0 =
      Except.ok (.int32 (Int32.ofNat 7), plainUInt32Bytes_demo.size) :=
  rfl

end Columnar.Parquet.Proofs
