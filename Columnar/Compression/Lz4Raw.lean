import Init.Data.ByteArray

@[extern "columnar_lz4_decompress"]
opaque lz4DecompressImpl (input : @& ByteArray) (uncompressedLen : USize) : IO ByteArray

namespace Columnar.Compression.Lz4Raw

def decompress (input : ByteArray) (uncompressedLen : Nat) : IO ByteArray :=
  lz4DecompressImpl input (USize.ofNat uncompressedLen)

end Columnar.Compression.Lz4Raw
