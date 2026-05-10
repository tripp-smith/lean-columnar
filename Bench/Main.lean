import Init.System.FilePath
import Columnar.Parquet.Reader
open Columnar.Parquet.Reader

/-- Read a Parquet file repeatedly when present; write JSON metrics.

Default input: `vendor/parquet-testing/data/binary.parquet`. Override with **`COLUMNAR_BENCH_FILE`**.

`COLUMNAR_BENCH_QUICK=1` selects a smaller iteration count; override count with `COLUMNAR_BENCH_ITERS`.
**`COLUMNAR_BENCH_LARGE=1`** defaults iterations to **1** when `COLUMNAR_BENCH_ITERS` is unset (multi-GB smoke).

Set `COLUMNAR_BENCH_MMAP=1` to also time `readParquetMmap` on the same file (see `docs/Manual.md` for RSS methodology on large files).
On macOS, `readParquetMmap` may use the `readBinFile` fallback unless `COLUMNAR_FORCE_MMAP=1`. -/
def main : IO UInt32 := do
  let mut iters : Nat := 40
  if (← IO.getEnv "COLUMNAR_BENCH_QUICK") == some "1" then iters := 30
  if (← IO.getEnv "COLUMNAR_BENCH_LARGE") == some "1" && (← IO.getEnv "COLUMNAR_BENCH_ITERS").isNone then
    iters := 1
  match (← IO.getEnv "COLUMNAR_BENCH_ITERS").bind (·.trimAscii.toString.toNat?) with
  | some n => if n > 0 then iters := n else pure ()
  | none => pure ()
  let pq ← match (← IO.getEnv "COLUMNAR_BENCH_FILE") with
    | some p =>
      let s := (String.trimAscii p).toString
      pure (System.FilePath.mk s)
    | none => pure (System.mkFilePath ["vendor", "parquet-testing", "data", "binary.parquet"])
  unless ← pq.pathExists do
    let fallbackJson :=
      "{\"workload\":\"missing\",\"iterations\":0,\"elapsed_ms_total\":0,\"mean_ms\":null,\"note\":\"bench input missing (set COLUMNAR_BENCH_FILE or vendor/parquet-testing)\"}\n"
    IO.FS.writeFile (System.mkFilePath ["bench", "results", "last-quick.json"]) fallbackJson
    IO.println "bench: input Parquet missing; wrote placeholder JSON"
    return 0
  let t0 ← IO.monoMsNow
  for _ in [:iters] do
    match (← readParquet pq) with
    | .error e => throw (IO.userError e)
    | .ok _ =>
      pure ()
  let t1 ← IO.monoMsNow
  let elapsed := t1 - t0
  let mean :=
    if iters == 0 then "null"
    else (elapsed / iters).repr
  let mmapJson ← do
    if (← IO.getEnv "COLUMNAR_BENCH_MMAP") == some "1" then do
      let u0 ← IO.monoMsNow
      for _ in [:iters] do
        match (← readParquetMmap pq) with
        | .error e => throw (IO.userError e)
        | .ok _ => pure ()
      let u1 ← IO.monoMsNow
      let el2 := u1 - u0
      let mean2 :=
        if iters == 0 then "null"
        else (el2 / iters).repr
      pure (", \"mmap_elapsed_ms_total\": " ++ el2.repr ++ ", \"mmap_mean_ms\": " ++ mean2)
    else
      pure ""
  IO.FS.createDirAll "bench/results"
  let pathEsc := pq.toString.replace "\"" "\\\""
  let json :=
    "{ \"workload\": \"readParquet\", \"file\": \"" ++ pathEsc ++ "\", \"iterations\": " ++ iters.repr ++
    ", \"elapsed_ms_total\": " ++ elapsed.repr ++ ", \"mean_ms\": " ++ mean ++
    mmapJson ++
    ", \"mode\": \"quick\" }\n"
  IO.FS.writeFile (System.mkFilePath ["bench", "results", "last-quick.json"]) json
  IO.println s!"bench: {iters} iterations, {elapsed} ms total (~{mean} ms mean) readParquet"
  if (← IO.getEnv "COLUMNAR_BENCH_MMAP") == some "1" then
    IO.println "bench: also ran readParquetMmap (see bench/results/last-quick.json mmap_* fields)"
  return 0
