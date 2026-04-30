import Init.Data.ByteArray

@[extern "columnar_zstd_decompress"]
opaque zstdDecompressImpl (input : @& ByteArray) (uncompressedLen : USize) : IO ByteArray

namespace Columnar.Compression.Zstd

def decompress (input : ByteArray) (uncompressedLen : Nat) : IO ByteArray :=
  zstdDecompressImpl input (USize.ofNat uncompressedLen)

end Columnar.Compression.Zstd
