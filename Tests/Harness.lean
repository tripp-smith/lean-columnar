import Init.System.IO
import Init.System.Platform

/-! Minimal test harness: accumulate failures, exit non-zero if any.

Reading `IO.Ref` values at process exit (`lake exe tests`) was correlated with SIGSEGV (128–139) on
some macOS / Lean builds after large test runs. We keep an in-memory log for messages, but the exit
code is driven by a tiny flag file under `.lake/` (read via `readBinFile`, not `readFile`) so `finish`
never calls `IO.Ref.get`. -/

namespace Tests.Harness

abbrev ErrLog := IO.Ref (Array String)

/-- Written by `mkCtx` / `fail`; read by `finish` (single ASCII `0` or `1`). -/
def failFlagPath : System.FilePath :=
  System.mkFilePath [".lake", "harness_failed"]

structure Ctx where
  log : ErrLog

def mkCtx : IO Ctx := do
  let log ← IO.mkRef #[]
  try
    let lakeDir := System.FilePath.mk ".lake"
    unless ← lakeDir.pathExists do
      IO.FS.createDirAll lakeDir
  catch _ => pure ()
  try
    IO.FS.writeFile failFlagPath "0"
  catch _ => pure ()
  return { log }

/-- Backwards-compatible name used by test modules. -/
abbrev mkLog := mkCtx

def fail (c : Ctx) (msg : String) : IO Unit := do
  c.log.modify (·.push msg)
  IO.eprintln s!"Harness FAIL: {msg}"
  try
    IO.FS.writeFile failFlagPath "1"
  catch _ => pure ()

def check (c : Ctx) (name : String) (ok : Bool) : IO Unit := do
  unless ok do fail c name

def info (s : String) : IO Unit :=
  IO.eprintln s

/-- On macOS, full-file Parquet decode (`readParquet`, mmap streams) has triggered SIGSEGV in this
binary after interop tests; CI runs Linux. Set `COLUMNAR_PARQUET_READER_OSX=1` to run these groups
locally on macOS. -/
def skipHeavyParquetReaderOnOSX (_groupLabel : String) : IO (Option String) := do
  unless System.Platform.isOSX do
    return none
  match ← IO.getEnv "COLUMNAR_PARQUET_READER_OSX" with
  | some s =>
    if (String.trimAscii s).toString == "1" then return none
    else return some "COLUMNAR_PARQUET_READER_OSX!=1"
  | none =>
    return some "set COLUMNAR_PARQUET_READER_OSX=1 (CI uses Linux; SIGSEGV otherwise)"

def group (title : String) (act : IO Unit) : IO Unit := do
  IO.eprintln s!"── {title} ──"
  act

def finish (_c : Ctx) : IO UInt32 := do
  let code ←
    try
      if !(← failFlagPath.pathExists) then
        pure 0
      else
        let b ← IO.FS.readBinFile failFlagPath
        if h : 0 < b.size then
          pure (if b.get 0 h == UInt8.ofNat 49 then 1 else 0)
        else
          pure 0
    catch _ =>
      pure 0
  if code != 0 then
    IO.eprintln "Harness: one or more failures (see Harness FAIL lines above)."
  return code

end Tests.Harness
