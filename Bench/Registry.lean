import Init.System.FilePath
import Columnar.Table
import Columnar.Parquet.Reader
import Columnar.Avro.Container
import Columnar.Orc.Reader
import Columnar.Arrow.IPC
open Columnar.Table (rowCount)

namespace Bench

inductive ReferenceFormat where
  | parquet | avro | orc | arrow_stream | arrow_file
  deriving Repr, BEq

def ReferenceFormat.toCli (f : ReferenceFormat) : String :=
  match f with
  | .parquet => "parquet"
  | .avro => "avro"
  | .orc => "orc"
  | .arrow_stream => "arrow_stream"
  | .arrow_file => "arrow_file"

structure BenchWorkload where
  id : String
  defaultPath : System.FilePath
  requiresVendor : Bool := false
  requiresNativeCodec : Bool := false
  referenceFormat : ReferenceFormat
  /-- Run one decode; return row count on success. -/
  leanRunner : System.FilePath → IO (Except String Nat)

def defaultParquetPath : System.FilePath :=
  System.mkFilePath ["vendor", "parquet-testing", "data", "binary.parquet"]

def parquetPathFromEnv : IO System.FilePath := do
  match (← IO.getEnv "COLUMNAR_BENCH_FILE") with
  | some p => pure (System.FilePath.mk (String.trimAscii p).toString)
  | none => pure defaultParquetPath

def runParquet (path : System.FilePath) : IO (Except String Nat) := do
  match ← Columnar.Parquet.Reader.readParquet path with
  | .error e => pure (.error e)
  | .ok t => pure (.ok (rowCount t))

def runParquetMmap (path : System.FilePath) : IO (Except String Nat) := do
  match ← Columnar.Parquet.Reader.readParquetMmap path with
  | .error e => pure (.error e)
  | .ok t => pure (.ok (rowCount t))

def runAvro (path : System.FilePath) : IO (Except String Nat) := do
  match ← Columnar.Avro.Container.readAvroOcf path with
  | .error e => pure (.error e)
  | .ok t => pure (.ok (rowCount t))

def runOrcInt32 (path : System.FilePath) : IO (Except String Nat) := do
  match ← Columnar.Orc.Reader.readOrcPrimitives path ["x"] with
  | .error e => pure (.error e)
  | .ok t => pure (.ok (rowCount t))

def runArrowStream (path : System.FilePath) : IO (Except String Nat) := do
  match ← Columnar.Arrow.IPC.readArrowIpcStreamFile path with
  | .error e => pure (.error e)
  | .ok t => pure (.ok (rowCount t))

def runArrowFile (path : System.FilePath) : IO (Except String Nat) := do
  match ← Columnar.Arrow.IPC.readArrowIpcFile path with
  | .error e => pure (.error e)
  | .ok t => pure (.ok (rowCount t))

def allWorkloads : Array BenchWorkload := #[
  { id := "parquet_binary"
    defaultPath := defaultParquetPath
    requiresVendor := true
    referenceFormat := .parquet
    leanRunner := runParquet },
  { id := "parquet_mmap"
    defaultPath := defaultParquetPath
    requiresVendor := true
    referenceFormat := .parquet
    leanRunner := runParquetMmap },
  { id := "avro_minimal"
    defaultPath := System.mkFilePath ["Tests", "fixtures", "interop_minimal.avro"]
    referenceFormat := .avro
    leanRunner := runAvro },
  { id := "avro_snappy"
    defaultPath := System.mkFilePath ["Tests", "fixtures", "interop_minimal_snappy.avro"]
    requiresNativeCodec := true
    referenceFormat := .avro
    leanRunner := runAvro },
  { id := "orc_int32"
    defaultPath := System.mkFilePath ["Tests", "fixtures", "interop_orc_int32.orc"]
    referenceFormat := .orc
    leanRunner := runOrcInt32 },
  { id := "arrow_stream"
    defaultPath := System.mkFilePath ["Tests", "fixtures", "interop_arrow_int32_stream.arrow"]
    referenceFormat := .arrow_stream
    leanRunner := runArrowStream },
  { id := "arrow_file"
    defaultPath := System.mkFilePath ["Tests", "fixtures", "interop_arrow_int32_file.arrow"]
    referenceFormat := .arrow_file
    leanRunner := runArrowFile }]

def resolvePath (w : BenchWorkload) : IO System.FilePath := do
  if w.id == "parquet_binary" || w.id == "parquet_mmap" then
    parquetPathFromEnv
  else
    pure w.defaultPath

def parseWorkloadFilter (s : String) : List String :=
  (s.splitOn ",").map (fun x => (String.trimAscii x).toString) |>.filter (· ≠ "")

def selectedWorkloads : IO (Array BenchWorkload) := do
  let includeMmap := (← IO.getEnv "COLUMNAR_BENCH_MMAP") == some "1"
  let ids? ← IO.getEnv "COLUMNAR_BENCH_WORKLOADS"
  let base ← match ids? with
    | some s =>
      let want := parseWorkloadFilter s
      pure (allWorkloads.filter fun w => want.contains w.id)
    | none =>
      pure (allWorkloads.filter fun w => includeMmap || w.id ≠ "parquet_mmap")
  pure base

end Bench
