import Init.Data.ByteArray
import Columnar.Core.MMap
import Columnar.Core.Bytes

namespace Columnar

/-- Random-access byte source for Parquet decode (whole `ByteArray` or POSIX mmap). -/
inductive ParquetBacking where
  | ofByteArray (b : ByteArray)
  | ofMmap (m : MmapRegion)

def ParquetBacking.fileSize : ParquetBacking → Nat
  | .ofByteArray b => b.size
  | .ofMmap m => m.byteLen

def ParquetBacking.copyRange (p : ParquetBacking) (off len : Nat) : IO ByteArray := do
  let n := p.fileSize
  if off + len > n then
    throw (IO.userError "ParquetBacking.copyRange: range exceeds file size")
  match p with
  | .ofByteArray b => return b.extract off (off + len)
  | .ofMmap m => m.copyRange off len

/-- Read the raw Thrift footer blob (without the length+PAR1 suffix). -/
def readParquetFooterIO (p : ParquetBacking) : IO (Except String ByteArray) :=
  try
    let n := p.fileSize
    if n < 8 then return .error "file too small for parquet footer"
    let tail8 ← p.copyRange (n - 8) 8
    let magic := tail8.extract 4 8
    let expected := ByteArray.mk #[0x50, 0x41, 0x52, 0x31]
    if magic != expected then return .error "invalid PAR1 magic"
    match Columnar.ByteArrayOps.readUInt32LE tail8 0 with
    | none => return .error "footer length"
    | some lenU =>
      let len := lenU.toNat
      if len > n - 8 then return .error "invalid footer length"
      let start := n - 8 - len
      let footer ← p.copyRange start len
      return .ok footer
  catch e =>
    return .error (toString e)

end Columnar
