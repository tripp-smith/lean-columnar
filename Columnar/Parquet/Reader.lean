import Init.Data.ByteArray
import Init.System.FilePath
import Columnar.Core.MMap
import Columnar.Core.Result
import Columnar.Core.Bytes
import Columnar.Parquet.Metadata
import Columnar.Parquet.Page
import Columnar.Parquet.Types
import Columnar.Parquet.Encoding.Plain
import Columnar.Parquet.Encoding.Rle
import Columnar.Compression.Codec
import Columnar.Table

open Columnar
open Columnar.Parquet
open Columnar.Parquet.Encoding.Plain
open Columnar.Parquet.Encoding.Rle
open Columnar.Compression

namespace Columnar.Parquet.Reader

def schemaLeaves (schema : Array SchemaElement) : Array SchemaElement :=
  schema.filter fun e =>
    e.physType.isSome &&
      match e.numChildren with
      | none => true
      | some n => n == (0 : Int32)

def maxDef (e : SchemaElement) : Nat :=
  match e.repetition with
  | some 1 => 1
  | some 2 => 1
  | _ => 0

def readFirstDataPage (file : ByteArray) (start : Nat) : P (PageHeaderParsed × Nat) := do
  let mut off := start
  for _ in List.range 64 do
    let (ph, hdrEnd) ← parsePageHeader file off
    if ph.pageType == PageType.dictionaryPage then
      off := hdrEnd + ph.compressedSize
    else if ph.pageType == PageType.dataPage then
      return (ph, hdrEnd)
    else
      throw s!"unexpected page type {ph.pageType}"
  throw "readFirstDataPage: too many pages"

def readDataPageColumn (file : ByteArray) (phys : Nat) (codecId : Nat) (maxDefLevel : Nat)
    (page : PageHeaderParsed) (dph : DataPageHeaderV1) (bodyOff : Nat) : IO (Except String (Array (Option PlainValue))) := do
  let unc := page.uncompressedSize
  let wire := page.compressedSize
  let slice ←
    if codecId == 0 then
      if bodyOff + wire > file.size then return .error "page body OOB"
      pure (file.extract bodyOff (bodyOff + wire))
    else
      if bodyOff + wire > file.size then return .error "compressed page OOB"
      let comp := file.extract bodyOff (bodyOff + wire)
      let decompressed ← decompress (CodecId.fromParquet codecId) comp unc
      pure decompressed
  let defs : Array Nat ←
    if maxDefLevel > 0 then
      match decodeHybrid slice 0 dph.numValues true with
      | Except.error e => return (Except.error e)
      | Except.ok d => pure d
    else
      pure #[]
  let defBytes :=
    if maxDefLevel > 0 then
      match Columnar.ByteArrayOps.readUInt32LE slice 0 with
      | none => 0
      | some l => 4 + l.toNat
    else 0
  let valuesOff := defBytes
  if dph.encoding != Encoding.plain then return .error s!"unsupported page encoding {dph.encoding}"
  let valueCount := if maxDefLevel > 0 then (defs.filter (· == maxDefLevel)).size else dph.numValues
  let plainSlice := slice.extract valuesOff slice.size
  match decodeColumn phys plainSlice 0 valueCount with
  | Except.error e => return (Except.error e)
  | Except.ok values =>
    if maxDefLevel == 0 then
      return (Except.ok (values.map some))
    let mut out : Array (Option PlainValue) := #[]
    let mut vi := 0
    for i in List.range dph.numValues do
      let d := (defs[i]?).getD 0
      if d == maxDefLevel then
        let v := (values[vi]?).getD PlainValue.null
        out := out.push (some v)
        vi := vi + 1
      else
        out := out.push none
    return (Except.ok out)

def readParquetFromBytes (file : ByteArray) : IO (Except String Table) :=
  match readFooterBytes file with
  | Except.error e => return (Except.error e)
  | Except.ok footer =>
    match parseFileMetaData footer with
    | Except.error e => return (Except.error e)
    | Except.ok fileMeta => do
      let leaves := schemaLeaves fileMeta.schema
      if fileMeta.rowGroups.isEmpty then return (Except.error "no row groups")
      let rg ←
        match fileMeta.rowGroups[0]? with
        | none => return (Except.error "no row groups")
        | some g => pure g
      if rg.columns.size != leaves.size then
        return (Except.error s!"column count mismatch chunks={rg.columns.size} leaves={leaves.size}")
      let mut cols : Array Column := #[]
      let mut colIdx : Nat := 0
      for p in rg.columns.zip leaves do
        let (chunk, leaf) := p
        let phys := leaf.physType.getD 0
        let colName := leaf.name.getD s!"col{colIdx}"
        colIdx := colIdx + 1
        let m := chunk.columnMeta
        let off := m.dataPageOffset
        match readFirstDataPage file off with
        | Except.error e => return (Except.error e)
        | Except.ok (ph, hdrEnd) =>
          match ph.dataV1 with
          | none => return (Except.error "expected data page v1")
          | some dph => do
            let mdRes ← readDataPageColumn file phys m.codec (maxDef leaf) ph dph hdrEnd
            match mdRes with
            | Except.error e => return (Except.error e)
            | Except.ok c =>
              cols := cols.push { name := colName, values := c }
      return (Except.ok { columns := cols })

def readParquet (path : System.FilePath) : IO (Except String Table) := do
  let bytes ← readFileBytes path
  readParquetFromBytes bytes

end Columnar.Parquet.Reader
