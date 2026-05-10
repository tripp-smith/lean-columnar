import Init.System.FilePath
import Init.System.IO
import Init.System.Platform
import Columnar.Core.MMap
import Columnar.Parquet.Reader
import Columnar.Parquet.Stream
import Columnar.Table
import Tests.Fixtures
import Tests.MmapAssertions

namespace Tests.Debug.MmapHarness

open Columnar
open Columnar.Parquet.Reader
open Columnar.Parquet.Stream

def usage : String :=
"mmap_harness: isolated mmap / Parquet scenarios for debugging.\n\
Usage: lake exe mmap_harness -- [--scenario ffi|open|compare|stream] [--file PATH] [PATH]\n\
  Scenario defaults to COLUMNAR_MMAP_SCENARIO or `ffi`.\n\
  On macOS, scenarios `open` and `stream` require COLUMNAR_FORCE_MMAP=1 (see docs/Manual.md).\n"

partial def parseArgsAux (scenario : String) (path? : Option System.FilePath) :
    List String → IO (String × Option System.FilePath)
  | [] => pure (scenario, path?)
  | "--scenario" :: s :: rest => parseArgsAux s path? rest
  | "--scenario" :: [] => throw (IO.userError "--scenario needs a value")
  | "--file" :: p :: rest => parseArgsAux scenario (some ⟨p⟩) rest
  | "--file" :: [] => throw (IO.userError "--file needs a path")
  | x :: rest =>
    if x.startsWith "--" then
      throw (IO.userError s!"unknown flag {x}\n{usage}")
    else
      parseArgsAux scenario (some ⟨x⟩) rest

def parseArgs (args : List String) : IO (String × Option System.FilePath) := do
  let envSc ← IO.getEnv "COLUMNAR_MMAP_SCENARIO"
  parseArgsAux (envSc.getD "ffi") none args

def requireMacosForceMmap (scenarioName : String) : IO Unit := do
  if System.Platform.isOSX then
    match ← IO.getEnv "COLUMNAR_FORCE_MMAP" with
    | some "1" => pure ()
    | _ =>
      IO.eprintln s!"mmap_harness: scenario `{scenarioName}` on macOS requires COLUMNAR_FORCE_MMAP=1"
      throw (IO.userError "missing COLUMNAR_FORCE_MMAP=1")

def scenarioFfi (path : System.FilePath) : IO UInt32 := do
  match ← mmapOpenTry path with
  | .error e =>
    IO.eprintln s!"mmap_harness ffi: mmapOpenTry failed: {e}"
    pure 1
  | .ok m => do
    try
      let n := m.byteLen
      if n > 0 then
        let takeHead := Nat.min 8 n
        let _ ← m.copyRange 0 takeHead
        pure ()
      if n >= 8 then
        let _ ← m.copyRange (n - 8) 8
        pure ()
      if n > 16 then
        let mid := n / 2
        let len := Nat.min 8 (n - mid)
        let _ ← m.copyRange mid len
        pure ()
      IO.println "mmap_harness ffi: OK"
      pure 0
    finally
      let _ ← m.close

def scenarioOpen (path : System.FilePath) : IO UInt32 := do
  requireMacosForceMmap "open"
  match ← openParquetFile path with
  | .error e =>
    IO.eprintln s!"mmap_harness open: {e}"
    pure 1
  | .ok pf => do
    try
      IO.println s!"mmap_harness open: OK (row groups := {pf.fileMeta.rowGroups.size})"
      pure 0
    finally
      pf.dispose

def scenarioCompare (path : System.FilePath) : IO UInt32 := do
  match ← readParquet path with
  | .error e =>
    IO.eprintln s!"mmap_harness compare readParquet: {e}"
    pure 1
  | .ok t0 =>
    match ← readParquetMmap path with
    | .error e =>
      IO.eprintln s!"mmap_harness compare readParquetMmap: {e}"
      pure 1
    | .ok t1 =>
      if Tests.MmapAssertions.tablesEqual t0 t1 then
        IO.println "mmap_harness compare: OK"
        pure 0
      else
        IO.eprintln "mmap_harness compare: tables differ"
        pure 1

def scenarioStream (path : System.FilePath) : IO UInt32 := do
  requireMacosForceMmap "stream"
  match ← openParquetFile path with
  | .error e =>
    IO.eprintln s!"mmap_harness stream openParquetFile: {e}"
    pure 1
  | .ok pf => do
    try
      match ← readParquetAllRowGroups path with
      | .error e =>
        IO.eprintln s!"mmap_harness stream readParquetAllRowGroups: {e}"
        pure 1
      | .ok want => do
        let mut s := streamRowGroups pf
        match ← RowGroupDecodeStream.nextDecoded s with
        | .error e =>
          IO.eprintln s!"mmap_harness stream first RG: {e}"
          pure 1
        | .ok none =>
          IO.eprintln "mmap_harness stream: expected first row group"
          pure 1
        | .ok (some (t0, s1)) =>
          match ← RowGroupDecodeStream.nextDecoded s1 with
          | .error e =>
            IO.eprintln s!"mmap_harness stream second RG: {e}"
            pure 1
          | .ok none =>
            IO.eprintln "mmap_harness stream: expected second row group"
            pure 1
          | .ok (some (t1, s2)) =>
            match ← RowGroupDecodeStream.nextDecoded s2 with
            | .error e =>
              IO.eprintln s!"mmap_harness stream end: {e}"
              pure 1
            | .ok (some _) =>
              IO.eprintln "mmap_harness stream: expected exactly 2 row groups"
              pure 1
            | .ok none =>
              match Columnar.Table.appendRows t0 t1 with
              | .error e =>
                IO.eprintln s!"mmap_harness stream appendRows: {e}"
                pure 1
              | .ok got =>
                if Tests.MmapAssertions.tablesEqual got want then
                  IO.println "mmap_harness stream: OK"
                  pure 0
                else
                  IO.eprintln "mmap_harness stream: tables differ"
                  pure 1
    finally
      pf.dispose

def defaultPath (scenario : String) : IO System.FilePath := do
  match scenario with
  | "compare" =>
    let pq := Fixtures.parquetTesting "binary.parquet"
    unless ← Fixtures.parquetTestingRoot.pathExists do
      throw (IO.userError "mmap_harness compare: vendor/parquet-testing missing (scripts/fetch-fixtures.sh)")
    unless ← pq.pathExists do
      throw (IO.userError "mmap_harness compare: binary.parquet missing")
    pure pq
  | "stream" =>
    let p := Fixtures.twoRowGroupsPlain
    unless ← p.pathExists do
      throw (IO.userError "mmap_harness stream: Tests/fixtures/two_row_groups_plain.parquet missing")
    pure p
  | _ =>
    let pq := Fixtures.parquetTesting "binary.parquet"
    if ← pq.pathExists then pure pq
    else
      let p := Fixtures.twoRowGroupsPlain
      unless ← p.pathExists do
        throw (IO.userError "mmap_harness: pass --file PATH or fetch fixtures (binary.parquet / two_row_groups_plain.parquet)")
      pure p

/-- Runnable entry; use [`Tests.MmapHarnessMain.main`] for `lake exe mmap_harness`. -/
def run (args : List String) : IO UInt32 := do
  let args := args.filter fun x => x != "--"
  if args.any fun x => x == "--help" || x == "-h" then
    IO.println usage
    return 0
  let (scenario, path?) ← parseArgs args
  let path ← match path? with
    | some p => pure p
    | none => defaultPath scenario
  match scenario with
  | "ffi" => scenarioFfi path
  | "open" => scenarioOpen path
  | "compare" => scenarioCompare path
  | "stream" => scenarioStream path
  | other =>
    IO.eprintln s!"unknown scenario `{other}` (use ffi|open|compare|stream)\n{usage}"
    pure 1

end Tests.Debug.MmapHarness
