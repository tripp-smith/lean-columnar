import Init.System.FilePath
import Init.System.IO

namespace Columnar

def readFileBytes (path : System.FilePath) : IO ByteArray :=
  IO.FS.readBinFile path

end Columnar
