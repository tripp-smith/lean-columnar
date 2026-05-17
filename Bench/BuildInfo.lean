import Init.System.FilePath
import Columnar.Compression.Snappy

open Columnar.Compression.Snappy

namespace Bench

/-- Runtime probe: native Snappy decompress succeeds on the codec contract fixture. -/
def columnarCodecBuildLabelIO : IO String := do
  let snappyPath := System.mkFilePath ["Tests", "fixtures", "codecs", "snappy.bin"]
  let plainPath := System.mkFilePath ["Tests", "fixtures", "codecs", "plaintext.bin"]
  if !(← snappyPath.pathExists) || !(← plainPath.pathExists) then
    return "stub"
  let snappy ← IO.FS.readBinFile snappyPath
  let plain ← IO.FS.readBinFile plainPath
  try
    let out ← decompress snappy plain.size
    if out.size == plain.size then pure "native" else pure "stub"
  catch _ =>
    pure "stub"

end Bench
