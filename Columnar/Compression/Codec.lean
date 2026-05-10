import Init.Data.ByteArray
import Columnar.Compression.Snappy
import Columnar.Compression.Zstd
import Columnar.Compression.Gzip
import Columnar.Compression.Brotli
import Columnar.Compression.Lz4Raw

namespace Columnar.Compression

inductive CodecId where
  | uncompressed | snappy | gzip | brotli | zstd | lz4Raw
  deriving BEq, Repr

def CodecId.fromParquet (n : Nat) : CodecId :=
  match n with
  | 0 => .uncompressed
  | 1 => .snappy
  | 2 => .gzip
  | 3 => .uncompressed -- LZO deprecated
  | 4 => .brotli
  | 5 => .uncompressed -- LZ4 deprecated
  | 6 => .zstd
  | 7 => .lz4Raw
  | _ => .uncompressed

/-- Parquet `CompressionCodec` enum value (`parquet.thrift`). -/
def CodecId.toParquet (c : CodecId) : Nat :=
  match c with
  | .uncompressed => 0
  | .snappy => 1
  | .gzip => 2
  | .brotli => 4
  | .zstd => 6
  | .lz4Raw => 7

def decompress (id : CodecId) (input : ByteArray) (uncompressedSize : Nat) : IO ByteArray :=
  match id with
  | .uncompressed => return input
  | .snappy => Columnar.Compression.Snappy.decompress input uncompressedSize
  | .gzip => Columnar.Compression.Gzip.decompress input uncompressedSize
  | .brotli => Columnar.Compression.Brotli.decompress input uncompressedSize
  | .zstd => Columnar.Compression.Zstd.decompress input uncompressedSize
  | .lz4Raw => Columnar.Compression.Lz4Raw.decompress input uncompressedSize

end Columnar.Compression
