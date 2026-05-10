import Init.System.FilePath
import Columnar.Table
import Columnar.Compression.Codec
import Columnar.Thrift.CompactWriter
import Columnar.Parquet.Types
import Columnar.Parquet.Writer.Schema
import Columnar.Parquet.Writer.Encode.Plain
import Columnar.Parquet.Writer.Encode.Levels
import Columnar.Parquet.Writer.Page
import Columnar.Parquet.Writer.Footer

namespace Columnar.Parquet.Writer

open Columnar.Parquet
open Columnar.Compression
open Columnar.Thrift
open Columnar.Parquet.Writer.Footer
open Columnar.Parquet.Writer.Encode.Levels
open Columnar.Parquet.Writer.Encode.Plain
open Columnar.Parquet.Writer.Page

def writeParquetBytes (t : Table) (opts : WriteOptions := WriteOptions.default) : Except String ByteArray := do
  if t.columns.isEmpty then throw "writeParquet: at least one column required"
  let rows ← validateTableShape t
  let ws ← inferWriteSchema t
  unless ws.columns.size == t.columns.size do
    throw "writeParquet: internal schema/column count mismatch"
  unless opts.rowsPerRowGroup > 0 do
    throw "writeParquet: rowsPerRowGroup must be positive"
  for wc in ws.columns do
    let cdc := opts.resolveCodec wc.name
    unless cdc == CodecId.uncompressed do
      throw s!"writeParquet: compression {repr cdc} not implemented (use UNCOMPRESSED)"
  let numRG :=
    if rows == 0 then 1
    else (rows + opts.rowsPerRowGroup - 1) / opts.rowsPerRowGroup
  let mut file := parquetMagic
  let mut rgStructs : Array ByteArray := #[]
  for rgIdx in [:numRG] do
    let start := rgIdx * opts.rowsPerRowGroup
    let rgLen :=
      if rows == 0 then 0
      else Nat.min opts.rowsPerRowGroup (rows - start)
    let sub ← Table.sliceRows t start rgLen
    let mut colChunks : Array ByteArray := #[]
    for pr in ws.columns.zip sub.columns do
      let (wc, col) := pr
      unless wc.name == col.name do
        throw "writeParquet: column name order mismatch"
      let maxDef := if wc.repetition == 1 then 1 else 0
      let defs := buildDefinitionLevels col.values maxDef
      let defBytes ← encodeDefinitionLevels defs maxDef
      let vals ← extractPlainPhysical wc.phys col.values maxDef
      let plainBytes ← encodePlain wc.phys vals
      let pageBody := defBytes ++ plainBytes
      let unc := pageBody.size
      let dph := serializeDataPageHeaderV1 rgLen Encoding.plain Encoding.rle Encoding.rle
      let ph := serializePageHeader unc unc dph
      let dataPageOffset := file.size
      file := file ++ ph ++ pageBody
      let chunkTotal := ph.size + pageBody.size
      let encIds : Array Nat := #[Encoding.plain, Encoding.rle]
      let codecId := CodecId.toParquet (opts.resolveCodec wc.name)
      let colMeta :=
        serializeColumnMetaData wc.phys codecId rgLen chunkTotal chunkTotal dataPageOffset encIds #[wc.name]
      colChunks := colChunks.push (serializeColumnChunk colMeta)
    let rg := serializeRowGroup colChunks rgLen
    rgStructs := rgStructs.push rg
  let schemaPay := serializeSchemaListPayload ws
  let fm :=
    serializeFileMetaData opts.version schemaPay rows rgStructs
  let out := file ++ fm ++ writeUInt32LE (UInt32.ofNat fm.size) ++ parquetMagic
  pure out

def writeParquet (t : Table) (path : System.FilePath) (opts : WriteOptions := WriteOptions.default) : IO Unit := do
  match writeParquetBytes t opts with
  | .error e => throw (IO.userError e)
  | .ok bytes => IO.FS.writeBinFile path bytes

end Columnar.Parquet.Writer
