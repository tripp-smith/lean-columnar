import Init.Data.ByteArray

namespace Columnar.Orc.Protobuf

/-- Minimal protobuf varint helpers for ORC (Phase 4). -/
def readVarInt (_ : ByteArray) (_pos : Nat) : Except String (UInt64 × Nat) :=
  throw "ORC protobuf: Phase 4"

end Columnar.Orc.Protobuf
