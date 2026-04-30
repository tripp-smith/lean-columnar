import Init.System.FilePath
import Init.System.IO

def writeQuickResult : IO Unit := do
  let dir := System.mkFilePath ["bench", "results"]
  IO.FS.createDirAll dir
  let p := System.mkFilePath ["bench", "results", "last-quick.json"]
  let json :=
    "{\n  \"mode\": \"quick\",\n  \"note\": \"placeholder timing harness; extend with real workloads\"\n}\n"
  IO.FS.writeFile p json

/-- `lake exe bench -- --quick` (arguments after `--` reserved for future workloads). -/
def main : IO UInt32 := do
  writeQuickResult
  IO.println "bench: wrote bench/results/last-quick.json"
  return 0
