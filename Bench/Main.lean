import Init.System.FilePath
import Bench.BuildInfo
import Bench.Registry
import Bench.Reference

open Bench

def escapeJson (s : String) : String :=
  s.foldl
    (fun acc c =>
      if c == '"' then acc ++ "\\\""
      else if c == '\\' then acc ++ "\\\\"
      else if c == '\n' then acc ++ "\\n"
      else if c == '\r' then acc ++ "\\r"
      else if c.toNat < 32 then acc
      else acc.push c)
    ""

def gitShortSha : IO String := do
  try
    let out ← IO.Process.output { cmd := "git", args := #["rev-parse", "--short", "HEAD"] }
    if out.exitCode == 0 then pure out.stdout.trim else pure "unknown"
  catch _ =>
    pure "unknown"

def utcTimestamp : IO String := do
  try
    let out ← IO.Process.output { cmd := "date", args := #["-u", "+%Y-%m-%dT%H:%M:%SZ"] }
    if out.exitCode == 0 then pure out.stdout.trim else pure "unknown"
  catch _ =>
    pure "unknown"

def resolveIterations : IO Nat := do
  let mut iters : Nat := 40
  if (← IO.getEnv "COLUMNAR_BENCH_QUICK") == some "1" then iters := 30
  if (← IO.getEnv "COLUMNAR_BENCH_LARGE") == some "1" && (← IO.getEnv "COLUMNAR_BENCH_ITERS").isNone then
    iters := 1
  match (← IO.getEnv "COLUMNAR_BENCH_ITERS").bind (·.trimAscii.toString.toNat?) with
  | some n => if n > 0 then iters := n else pure ()
  | none => pure ()
  pure iters

structure WorkloadResult where
  id : String
  file : String
  status : String
  skipReason : Option String
  leanElapsedMsTotal : Option Nat
  leanMeanMs : Option Float
  reference : String
  referenceElapsedMsTotal : Option Nat
  referenceMeanMs : Option Float
  rowCount : Option Nat

def jsonNullOrNat (n : Option Nat) : String :=
  match n with | none => "null" | some v => v.repr

def jsonNullOrFloat (n : Option Float) : String :=
  match n with
  | none => "null"
  | some v =>
    let s := toString v
    if s.contains '.' then s else s ++ ".0"

def jsonNullOrStr (s : Option String) : String :=
  match s with | none => "null" | some v => "\"" ++ escapeJson v ++ "\""

def workloadToJson (w : WorkloadResult) : String :=
  "{"
    ++ "\"id\":\"" ++ escapeJson w.id ++ "\","
    ++ "\"file\":\"" ++ escapeJson w.file ++ "\","
    ++ "\"status\":\"" ++ w.status ++ "\","
    ++ "\"skip_reason\":" ++ jsonNullOrStr w.skipReason ++ ","
    ++ "\"lean_elapsed_ms_total\":" ++ jsonNullOrNat w.leanElapsedMsTotal ++ ","
    ++ "\"lean_mean_ms\":" ++ jsonNullOrFloat w.leanMeanMs ++ ","
    ++ "\"reference\":\"" ++ w.reference ++ "\","
    ++ "\"reference_elapsed_ms_total\":" ++ jsonNullOrNat w.referenceElapsedMsTotal ++ ","
    ++ "\"reference_mean_ms\":" ++ jsonNullOrFloat w.referenceMeanMs ++ ","
    ++ "\"row_count\":" ++ jsonNullOrNat w.rowCount
    ++ "}"

def timeLeanRunner (runner : System.FilePath → IO (Except String Nat)) (path : System.FilePath)
    (iters : Nat) : IO WorkloadResult := do
  let fileStr := path.toString
  -- warm-up (discard)
  if iters > 0 then
    match ← runner path with
    | .ok _ => pure ()
    | .error _ => pure ()
  let t0 ← IO.monoMsNow
  let mut lastRows : Option Nat := none
  let mut errMsg : Option String := none
  for _ in [:iters] do
    match ← runner path with
    | .error e => errMsg := some e
    | .ok n => lastRows := some n
  let t1 ← IO.monoMsNow
  match errMsg with
  | some e =>
    pure
      { id := ""
        file := fileStr
        status := "error"
        skipReason := some ("lean_error:" ++ e)
        leanElapsedMsTotal := none
        leanMeanMs := none
        reference := "pyarrow"
        referenceElapsedMsTotal := none
        referenceMeanMs := none
        rowCount := none }
  | none =>
    let elapsed := t1 - t0
    let mean := if iters == 0 then 0.0 else elapsed.toFloat / iters.toFloat
    pure
      { id := ""
        file := fileStr
        status := "ok"
        skipReason := none
        leanElapsedMsTotal := some elapsed
        leanMeanMs := some mean
        reference := "pyarrow"
        referenceElapsedMsTotal := none
        referenceMeanMs := none
        rowCount := lastRows }

def skipResult (id file reason : String) : WorkloadResult :=
  { id := id, file := file, status := "skip", skipReason := some reason
    leanElapsedMsTotal := none, leanMeanMs := none, reference := "pyarrow"
    referenceElapsedMsTotal := none, referenceMeanMs := none, rowCount := none }

def codecUnavailable? (msg : String) : Bool :=
  msg.contains "unavailable" || msg.contains "COLUMNAR_CODEC"

def runOneWorkload (w : BenchWorkload) (iters : Nat) (codecBuild : String) : IO WorkloadResult := do
  let path ← resolvePath w
  let fileStr := path.toString
  if w.requiresNativeCodec && codecBuild == "stub" then
    pure (skipResult w.id fileStr "requires_native_codec")
  else if !(← path.pathExists) then
    pure (skipResult w.id fileStr "missing_file")
  else do
    let mut r ← timeLeanRunner w.leanRunner path iters
    r := { r with id := w.id }
    if r.status != "ok" then
      pure r
    else do
      let refResult ← runReferenceTiming w.referenceFormat path iters
      match refResult with
      | .ok ref =>
        pure
          { r with
            referenceElapsedMsTotal := some ref.elapsedMsTotal
            referenceMeanMs := some ref.meanMs
            rowCount := r.rowCount <|> some ref.rowCount }
      | .error e => do
        IO.eprintln s!"bench: {w.id} reference skip: {e}"
        pure { r with skipReason := some ("reference_unavailable:" ++ e) }

def main : IO UInt32 := do
  let iters ← resolveIterations
  let workloads ← selectedWorkloads
  let codecBuild ← columnarCodecBuildLabelIO
  let sha ← gitShortSha
  let ts ← utcTimestamp
  let mode :=
    if (← IO.getEnv "COLUMNAR_BENCH_QUICK") == some "1" then "quick" else "default"
  let mut results : Array WorkloadResult := #[]
  for w in workloads do
    let r ← runOneWorkload w iters codecBuild
    results := results.push r
    let leanStr :=
      match r.leanMeanMs with | none => "null" | some m => toString m
    let refStr :=
      match r.referenceMeanMs with | none => "null" | some m => toString m
    IO.println s!"bench: {r.id} status={r.status} lean_mean_ms={leanStr} ref_mean_ms={refStr}"
  let workloadsJson := String.intercalate "," (results.map workloadToJson).toList
  let json :=
    "{"
      ++ "\"schema_version\":1,"
      ++ "\"git_sha\":\"" ++ escapeJson sha ++ "\","
      ++ "\"timestamp_utc\":\"" ++ escapeJson ts ++ "\","
      ++ "\"mode\":\"" ++ mode ++ "\","
      ++ "\"columnar_codec_build\":\"" ++ codecBuild ++ "\","
      ++ "\"iterations\":" ++ iters.repr ++ ","
      ++ "\"workloads\":[" ++ workloadsJson ++ "]"
      ++ "}\n"
  IO.FS.createDirAll "bench/results"
  IO.FS.writeFile (System.mkFilePath ["bench", "results", "last-quick.json"]) json
  return 0
