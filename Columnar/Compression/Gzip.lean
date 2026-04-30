import Init.Data.ByteArray

@[extern "columnar_zlib_decompress"]
opaque zlibDecompressImpl (input : @& ByteArray) (uncompressedLen : USize) : IO ByteArray

namespace Columnar.Compression.Gzip

def decompress (input : ByteArray) (uncompressedLen : Nat) : IO ByteArray :=
  zlibDecompressImpl input (USize.ofNat uncompressedLen)

end Columnar.Compression.Gzip
