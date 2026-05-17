import Init.Data.ByteArray
import Columnar.Core.Bytes
import Columnar.Compression.Gzip

namespace Columnar.Orc.Compress

open Columnar.ByteArrayOps

/-- ORC zlib blob: 3-byte little-endian uncompressed length, then raw-deflate payload. -/
def readOrcZlibOrigLen (b : ByteArray) : Nat :=
  if b.size < 3 then 0
  else
    (readU8 b 0).toNat ||| ((readU8 b 1).toNat <<< 8) ||| ((readU8 b 2).toNat <<< 16)

/-- Decompress ORC zlib blob (3-byte LE orig length + raw deflate). Throws if all strategies fail. -/
def decompressOrcZlibBlob (blob : ByteArray) (capHint : Nat) : IO ByteArray := do
  if blob.size < 3 then throw <| IO.userError "ORC zlib: blob too small"
  let orig := readOrcZlibOrigLen blob
  let cap := max orig (max capHint (blob.size * 8 + 65536))
  let payload := blob.extract 3 blob.size
  try
    return (← Columnar.Compression.Gzip.inflateRaw payload cap)
  catch _ =>
    pure ()
  try
    return (← Columnar.Compression.Gzip.decompress payload cap)
  catch _ =>
    pure ()
  try
    return (← Columnar.Compression.Gzip.decompress blob cap)
  catch _ =>
    pure ()
  throw <| IO.userError
    "ORC zlib: decompress failed (COLUMNAR_CODEC=1 when compiling, lake -Kcolumnar.codec=1, link -lz; docs/FFI.md)"

/-- Per-stream stripe chunk: strip the 3-byte ORC length prefix (payload is usually raw). -/
def orcStreamPayload (chunk : ByteArray) : IO ByteArray :=
  if chunk.size ≤ 3 then pure chunk else pure (chunk.extract 3 chunk.size)

end Columnar.Orc.Compress
