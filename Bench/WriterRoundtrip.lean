import Init.System.FilePath
import Columnar.Table
import Columnar.Parquet.Encoding.Plain
import Columnar.Parquet.Writer

open Columnar
open Columnar.Parquet.Encoding.Plain
open Columnar.Parquet.Writer (WriteOptions)

def mkSeqTable (rows : Nat) : Table :=
  let vals :=
    (List.range rows).map (fun i : Nat => some (PlainValue.int32 (Int32.ofNat i))) |>.toArray
  { columns := #[{ name := "x", values := vals }] }

def mkMixedPrimitivesTable : Table :=
  { columns :=
    #[
      { name := "b", values := #[some (.bool true)] },
      { name := "i", values := #[some (.int32 (Int32.ofNat 7))] },
      { name := "f", values := #[some (.float (3.0 : Float))] }
    ] }

def mkNullableInt64Table : Table :=
  { columns := #[{ name := "n", values := #[none, some (.int64 (Int64.ofNat 99))] }] }

/-- Env: `COLUMNAR_WRITER_PATH` (required). Optional `COLUMNAR_WRITER_SCHEMA`:
default / unknown uses `COLUMNAR_WRITER_ROWS`; `mixed`, `nullable` use fixed tables. -/
def main : IO UInt32 := do
  let some pathStr ← pure (← IO.getEnv "COLUMNAR_WRITER_PATH") | do
    IO.eprintln "missing COLUMNAR_WRITER_PATH"
    return 1
  let path : System.FilePath := ⟨pathStr⟩
  let schemaOpt ← IO.getEnv "COLUMNAR_WRITER_SCHEMA"
    let writeSeq : IO UInt32 := do
    let some rnStr ← pure (← IO.getEnv "COLUMNAR_WRITER_ROWS") | do
      IO.eprintln "missing COLUMNAR_WRITER_ROWS (or set COLUMNAR_WRITER_SCHEMA=mixed|nullable)"
      return 1
    match (String.trimAscii rnStr).toString.toNat? with
    | none =>
      IO.eprintln "COLUMNAR_WRITER_ROWS not a Nat"
      return 1
    | some rn =>
      let rgStr? ← IO.getEnv "COLUMNAR_WRITER_RG_SIZE"
      let opts : WriteOptions :=
        match rgStr? with
        | some rs =>
          match (String.trimAscii rs).toString.toNat? with
          | some k =>
            if k == 0 then WriteOptions.default
            else { WriteOptions.default with rowsPerRowGroup := k }
          | none => WriteOptions.default
        | none => WriteOptions.default
      Columnar.Parquet.Writer.writeParquet (mkSeqTable rn) path opts
      IO.println s!"writer_roundtrip: wrote {pathStr} ({rn} INT32 rows, rowsPerRowGroup={opts.rowsPerRowGroup})"
      return 0
  match schemaOpt with
  | some s =>
    match (String.trimAscii s).toString with
    | "mixed" =>
      Columnar.Parquet.Writer.writeParquet mkMixedPrimitivesTable path
      IO.println s!"writer_roundtrip: wrote mixed primitives → {pathStr}"
      return 0
    | "nullable" =>
      Columnar.Parquet.Writer.writeParquet mkNullableInt64Table path
      IO.println s!"writer_roundtrip: wrote nullable INT64 → {pathStr}"
      return 0
    | _ => writeSeq
  | none => writeSeq
