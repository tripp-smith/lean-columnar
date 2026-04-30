import Init.Data.ByteArray

@[extern "columnar_brotli_decompress"]
opaque brotliDecompressImpl (input : @& ByteArray) (uncompressedLen : USize) : IO ByteArray

namespace Columnar.Compression.Brotli

def decompress (input : ByteArray) (uncompressedLen : Nat) : IO ByteArray :=
  brotliDecompressImpl input (USize.ofNat uncompressedLen)

end Columnar.Compression.Brotli
