import Init.Data.ByteArray

@[extern "columnar_snappy_decompress"]
opaque snappyDecompressImpl (input : @& ByteArray) (uncompressedLen : USize) : IO ByteArray

namespace Columnar.Compression.Snappy

def decompress (input : ByteArray) (uncompressedLen : Nat) : IO ByteArray :=
  snappyDecompressImpl input (USize.ofNat uncompressedLen)

end Columnar.Compression.Snappy
