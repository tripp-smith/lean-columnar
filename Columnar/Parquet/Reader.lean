import Init.Data.ByteArray
import Init.System.FilePath
import Columnar.Core.MMap
import Columnar.Core.ParquetBacking
import Columnar.Core.Result
import Columnar.Parquet.Metadata
import Columnar.Parquet.Page
import Columnar.Parquet.SchemaWalk
import Columnar.Parquet.Types
import Columnar.Parquet.Encoding.Plain
import Columnar.Parquet.Encoding.Rle
import Columnar.Parquet.Encoding.Dictionary
import Columnar.Parquet.Encoding.Delta
import Columnar.Parquet.Encoding.ByteStreamSplit
import Columnar.Compression.Codec
import Columnar.Table

open Columnar
open Columnar.Parquet
open Columnar.Parquet.Encoding.Plain (PlainValue decodeColumn decodeColumnDrain physWidth)
open Columnar.Parquet.Encoding.Rle
  (decodeHybrid hybridEncodedSpanExclusive decodeBitPackedDeprecatedLevels packBitWidth)
open Columnar.Parquet.Encoding.Dictionary (decodeIndicesPlain decodeIndicesHybrid)
open Columnar.Parquet.Encoding.Delta (decodeBinaryPacked)
open Columnar.Parquet.Encoding.ByteStreamSplit (decodePhys)
open Columnar.Compression

namespace Columnar.Parquet.Reader

abbrev Err := Except String

def chunkStartOffset (m : ColumnMetaDataParsed) : Nat :=
  match m.dictPageOffset with
  | none => m.dataPageOffset
  | some d => Nat.min d m.dataPageOffset

def maxPageHeaderWindow : Nat :=
  16 * 1024 * 1024

def readNextPageHeaderByteArray (file : ByteArray) (off : Nat) : Err (PageHeaderParsed × Nat) := do
  let (ph, e) ← parsePageHeader file off
  if ph.pageType == PageType.dataPage || ph.pageType == PageType.dataPageV2 ||
      ph.pageType == PageType.dictionaryPage then
    pure (ph, e)
  else
    throw s!"unexpected page type {ph.pageType}"

/-- Windowed header parse for mmap (bounded `copyRange` + Thrift growth on EOF). -/
partial def readNextPageHeaderAux (p : ParquetBacking) (cursor : Nat) (win : Nat) (maxWinCap : Nat) (fuel : Nat) :
    IO (Err (PageHeaderParsed × Nat)) := do
  if fuel == 0 then return Except.error "readNextPageHeader: fuel"
  let n := p.fileSize
  if cursor >= n then return Except.error "page header OOB"
  let avail := n - cursor
  let win' := Nat.min win avail
  let maxWin' := Nat.min maxWinCap avail
  let buf ← p.copyRange cursor win'
  match parsePageHeader buf 0 with
  | Except.ok (ph, relEnd) =>
    if ph.pageType == PageType.dataPage || ph.pageType == PageType.dataPageV2 ||
        ph.pageType == PageType.dictionaryPage then
      return Except.ok (ph, cursor + relEnd)
    else
      return Except.error s!"unexpected page type {ph.pageType}"
  | Except.error e =>
    let growable := e == "Thrift: unexpected EOF" || e == "Thrift: readBytes past end"
    if growable then
      if win' >= maxWin' then
        return Except.error s!"page header thrift truncated at cursor {cursor}: {e}"
      else
        let nextWin := Nat.min (win' * 2) maxWin'
        readNextPageHeaderAux p cursor nextWin maxWinCap (fuel - 1)
    else
      return Except.error e

def readNextPageHeaderAt (p : ParquetBacking) (cursor : Nat) : IO (Err (PageHeaderParsed × Nat)) :=
  match p with
  | .ofByteArray b => return (readNextPageHeaderByteArray b cursor)
  | .ofMmap _ => do
    let n := p.fileSize
    if cursor >= n then return Except.error "page header OOB"
    let avail := n - cursor
    let initWin := Nat.min (256 * 1024) avail
    let maxWinCap := Nat.min maxPageHeaderWindow avail
    readNextPageHeaderAux p cursor initWin maxWinCap 48

def ioDecompressPageByteArray (codecId : Nat) (ph : PageHeaderParsed) (hdrEnd : Nat) (file : ByteArray) :
    IO (Err ByteArray) := do
  let wire := ph.compressedSize
  let unc := ph.uncompressedSize
  if hdrEnd + wire > file.size then return (Except.error "page wire OOB")
  else
    let raw := file.extract hdrEnd (hdrEnd + wire)
    try
      let out ←
        if codecId == 0 then pure raw
        else decompress (CodecId.fromParquet codecId) raw unc
      pure (Except.ok out)
    catch e =>
      pure (Except.error (toString e))

def ioDecompressPageBacked (codecId : Nat) (ph : PageHeaderParsed) (hdrEnd : Nat) (p : ParquetBacking) :
    IO (Err ByteArray) := do
  let wire := ph.compressedSize
  let unc := ph.uncompressedSize
  let n := p.fileSize
  match p with
  | .ofByteArray file => ioDecompressPageByteArray codecId ph hdrEnd file
  | .ofMmap _ =>
    if hdrEnd + wire > n then return (Except.error "page wire OOB")
    else do
      let raw ← p.copyRange hdrEnd wire
      try
        let out ←
          if codecId == 0 then pure raw
          else decompress (CodecId.fromParquet codecId) raw unc
        pure (Except.ok out)
      catch e =>
        pure (Except.error (toString e))

def interleaveDefs (defs : Array Nat) (values : Array PlainValue) (maxD : Nat) (slots : Nat)
    : Err (Array (Option PlainValue)) := do
  if maxD > 0 && defs.size != slots then throw "def level size"
  let mut v := 0
  let mut out : Array (Option PlainValue) := #[]
  for i in [:slots] do
    let d := if maxD > 0 then (defs[i]?).getD 0 else maxD
    if d == maxD then
      match values[v]? with
      | none => throw "value underrun"
      | some pv =>
        out := out.push (some pv)
        v := v + 1
    else
      out := out.push none
  if v != values.size then throw "value count mismatch"
  pure out

/-- Repetition levels consume the same slot count as definitions when present (`Encodings.md`, data page v1). -/
def consumeLevelPrefix
    (slice : ByteArray) (slotCount : Nat) (maxLevel : Nat) (levelEnc : Nat) (cursor : Nat) :
    Err (Array Nat × Nat) := do
  if maxLevel == 0 then pure (#[], cursor)
  else
    if levelEnc == Encoding.rle then do
      let bw := packBitWidth maxLevel
      let arr ← decodeHybrid slice cursor slotCount true (some bw)
      let endPos ← hybridEncodedSpanExclusive slice cursor true
      pure (arr, endPos)
    else if levelEnc == Encoding.bitPackedDeprecated then decodeBitPackedDeprecatedLevels slice cursor slotCount maxLevel
    else throw s!"unsupported repetition/definition level encoding {levelEnc}"

def decodeValueRun
    (enc : Nat) (dict : Option (Array PlainValue)) (phys : Nat) (physBytes : Nat) (blob : ByteArray) (count : Nat)
    : Err (Array PlainValue) := do
  if count == 0 then pure #[]
  else if let some d := dict then
    let idxs : Array Nat ←
      if enc == Encoding.plain || enc == Encoding.plainDictionary ||
          enc == Encoding.rleDictionary || enc == Encoding.rle then
        match decodeIndicesHybrid blob 0 count with
        | Except.ok r => pure r
        | Except.error _ => do
          let a ← decodeIndicesPlain blob 0 count
          pure (Array.map (fun u => u.toNat) a)
      else throw s!"dictionary data page encoding {enc}"
    let mut acc : Array PlainValue := #[]
    for t in idxs do
      if h : t < d.size then
        acc := acc.push d[t]
      else
        throw "dict index OOB"
    pure acc
  else if enc == Encoding.plain then decodeColumn phys blob 0 count
  else if enc == Encoding.deltaBinaryPacked then decodeBinaryPacked blob physBytes count
  else if enc == Encoding.byteStreamSplit then decodePhys phys blob 0 count
  else throw s!"unsupported data encoding {enc}"

def decodeDataPageV1
    (dict : Option (Array PlainValue)) (phys : Nat) (maxDef maxRep : Nat) (dph : DataPageHeaderV1) (slice : ByteArray) :
    Err (Array (Option PlainValue)) := do
  let slots := dph.numValues
  -- Parquet data page v1: repetition levels, then definition levels, then values.
  let (reps, cursorAfterRep) ← consumeLevelPrefix slice slots maxRep dph.repLevelEncoding 0
  let (defs, valuesStart) ← consumeLevelPrefix slice slots maxDef dph.defLevelEncoding cursorAfterRep
  if maxRep > 0 && reps.size != slots then throw "rep slots"
  -- Repetition levels: validated for slot count; flat `Option PlainValue` output (no nested assembly yet).
  let _ := reps
  let nonNull :=
    if maxDef > 0 then (defs.foldl (fun acc d => if d == maxDef then acc + 1 else acc) 0) else slots
  let physBytes :=
    if phys == PhysType.int32 || phys == PhysType.float then 4
    else if phys == PhysType.int64 || phys == PhysType.double then 8
    else physWidth phys
  let valuesBlob := slice.extract valuesStart slice.size
  let vals ← decodeValueRun dph.encoding dict phys physBytes valuesBlob nonNull
  if maxDef > 0 then interleaveDefs defs vals maxDef slots
  else pure (vals.map some)

def readDictionaryPage (phys : Nat) (slice : ByteArray) : Err (Array PlainValue) :=
  decodeColumnDrain phys slice 0

/-- V2 level blocks use RLE without a u32 length prefix; `sub` must be exactly one block (`Encodings.md`). -/
def decodeV2LevelBlock (sub : ByteArray) (slots : Nat) (maxLevel : Nat) : Err (Array Nat) := do
  if maxLevel == 0 then
    if sub.size != 0 then throw "v2: unexpected level bytes with maxLevel=0"
    pure #[]
  else if sub.size == 0 then throw "v2: missing level bytes"
  else do
    let bw := packBitWidth maxLevel
    let arr ← decodeHybrid sub 0 slots false (some bw)
    let endPos ← hybridEncodedSpanExclusive sub 0 false
    if endPos != sub.size then throw s!"v2: level RLE span {endPos} != {sub.size}"
    if arr.size != slots then throw "v2: level value count"
    pure arr

def decodeDataPageV2
    (dict : Option (Array PlainValue)) (phys : Nat) (maxDef maxRep : Nat) (dph : DataPageHeaderV2)
    (slice : ByteArray) (codecId : Nat) :
    IO (Err (Array (Option PlainValue))) := do
  let nv := dph.numValues
  let repLen := dph.repetitionLevelsByteLength
  let defLen := dph.definitionLevelsByteLength
  if dph.numNulls > nv then return (.error "v2: num_nulls > num_values")
  if repLen + defLen > slice.size then return (.error "v2: definition+repetition lengths OOB")
  let repSlice := slice.extract 0 repLen
  let defSlice := slice.extract repLen (repLen + defLen)
  let valuesRaw := slice.extract (repLen + defLen) slice.size
  match decodeV2LevelBlock repSlice nv maxRep with
  | .error e => return (.error e)
  | .ok reps =>
    let _ := reps
    match decodeV2LevelBlock defSlice nv maxDef with
    | .error e => return (.error e)
    | .ok defs =>
      let valuesBlob ←
        if dph.isCompressed && codecId != 0 then
          let want := slice.size - repLen - defLen
          if want == 0 && nv > dph.numNulls then
            return (.error "v2: empty values but non-null values expected")
          try
            let dec ← decompress (CodecId.fromParquet codecId) valuesRaw want
            pure dec
          catch e =>
            return (.error (toString e))
        else pure valuesRaw
      let nonNull :=
        if maxDef > 0 then (defs.foldl (fun acc d => if d == maxDef then acc + 1 else acc) 0) else nv
      let expectedNonNull := nv - dph.numNulls
      if maxDef > 0 && nonNull != expectedNonNull then
        return (.error s!"v2: non-null count {nonNull} != nv-num_nulls {expectedNonNull}")
      let physBytes :=
        if phys == PhysType.int32 || phys == PhysType.float then 4
        else if phys == PhysType.int64 || phys == PhysType.double then 8
        else physWidth phys
      match decodeValueRun dph.encoding dict phys physBytes valuesBlob nonNull with
      | .error e => return (.error e)
      | .ok vals =>
        if maxDef > 0 then
          match interleaveDefs defs vals maxDef nv with
          | .error e => return (.error e)
          | .ok out => return (.ok out)
        else return (.ok (vals.map some))

/-- Iterative page walk on an in-memory `ByteArray` (original code path). -/
def readPagesForColumnByteArray
    (file : ByteArray) (codecId : Nat) (phys : Nat) (maxDef maxRep : Nat) (targetCount : Nat)
    (mutCursor : Nat) (acc : Array (Option PlainValue)) (dict : Option (Array PlainValue)) (fuel : Nat) :
    IO (Err (Array (Option PlainValue) × Option (Array PlainValue))) := do
  let mut cursor := mutCursor
  let mut acc := acc
  let mut dict := dict
  for _ in [:fuel] do
    if acc.size ≥ targetCount then return (Except.ok (acc, dict))
    match readNextPageHeaderByteArray file cursor with
    | Except.error e => return (Except.error e)
    | Except.ok (ph, hdrEnd) =>
      let pageEnd := hdrEnd + ph.compressedSize
      match (← ioDecompressPageByteArray codecId ph hdrEnd file) with
      | Except.error msg => return (Except.error msg)
      | Except.ok uncompressed =>
        if ph.pageType == PageType.dictionaryPage then
          match readDictionaryPage phys uncompressed with
          | Except.error e => return (Except.error e)
          | Except.ok dvals =>
            dict := some dvals
            cursor := pageEnd
        else if ph.pageType == PageType.dataPage then
          match ph.dataV1 with
          | none => return (Except.error "data page v1: missing header")
          | some dph =>
            match decodeDataPageV1 dict phys maxDef maxRep dph uncompressed with
            | Except.error e => return (Except.error e)
            | Except.ok vals =>
              acc := acc ++ vals
              cursor := pageEnd
        else if ph.pageType == PageType.dataPageV2 then
          match ph.dataV2 with
          | none => return (Except.error "data page v2: missing header")
          | some dph =>
            match (← decodeDataPageV2 dict phys maxDef maxRep dph uncompressed codecId) with
            | Except.error e => return (Except.error e)
            | Except.ok vals =>
              acc := acc ++ vals
              cursor := pageEnd
        else
          return (Except.error "unexpected page")
  if acc.size ≥ targetCount then return (Except.ok (acc, dict))
  return (Except.error "readPagesForColumn fuel")

/-- Iterative page walk (mmap uses bounded copies; `ByteArray` uses the legacy fast path). -/
def readPagesForColumn
    (file : ParquetBacking) (codecId : Nat) (phys : Nat) (maxDef maxRep : Nat) (targetCount : Nat)
    (mutCursor : Nat) (acc : Array (Option PlainValue)) (dict : Option (Array PlainValue)) (fuel : Nat) :
    IO (Err (Array (Option PlainValue) × Option (Array PlainValue))) :=
  match file with
  | .ofByteArray b =>
    readPagesForColumnByteArray b codecId phys maxDef maxRep targetCount mutCursor acc dict fuel
  | .ofMmap _ => do
    let mut cursor := mutCursor
    let mut acc := acc
    let mut dict := dict
    for _ in [:fuel] do
      if acc.size ≥ targetCount then return (Except.ok (acc, dict))
      match ← readNextPageHeaderAt file cursor with
      | Except.error e => return (Except.error e)
      | Except.ok (ph, hdrEnd) =>
        let pageEnd := hdrEnd + ph.compressedSize
        match (← ioDecompressPageBacked codecId ph hdrEnd file) with
        | Except.error msg => return (Except.error msg)
        | Except.ok uncompressed =>
          if ph.pageType == PageType.dictionaryPage then
            match readDictionaryPage phys uncompressed with
            | Except.error e => return (Except.error e)
            | Except.ok dvals =>
              dict := some dvals
              cursor := pageEnd
          else if ph.pageType == PageType.dataPage then
            match ph.dataV1 with
            | none => return (Except.error "data page v1: missing header")
            | some dph =>
              match decodeDataPageV1 dict phys maxDef maxRep dph uncompressed with
              | Except.error e => return (Except.error e)
              | Except.ok vals =>
                acc := acc ++ vals
                cursor := pageEnd
          else if ph.pageType == PageType.dataPageV2 then
            match ph.dataV2 with
            | none => return (Except.error "data page v2: missing header")
            | some dph =>
              match (← decodeDataPageV2 dict phys maxDef maxRep dph uncompressed codecId) with
              | Except.error e => return (Except.error e)
              | Except.ok vals =>
                acc := acc ++ vals
                cursor := pageEnd
          else
            return (Except.error "unexpected page")
    if acc.size ≥ targetCount then return (Except.ok (acc, dict))
    return (Except.error "readPagesForColumn fuel")

/-- Max data/dictionary pages to scan per column chunk.

`readPagesForColumn` iterates **once per page** until `acc.size ≥ numValues`. The old
`Nat.max 8192 (numValues + 512)` treated `numValues` like a page count and made Lean build
`List.range` with millions of nodes for wide columns, which corrupted the heap and crashed at
process exit. Realistic Parquet columns have far fewer than a few thousand pages. -/
def pageReadFuel (_numValues : Nat) : Nat :=
  8192

/-- Decode one row group into a flat `Table` (`ByteArray` path — matches pre-backing behavior). -/
def readTableForRowGroupBytes (file : ByteArray) (fileMeta : FileMetaDataParsed) (rgIdx : Nat) : IO (Err Table) := do
  match SchemaWalk.preorderLeavesFromSchema fileMeta.schema with
  | .error e => return (.error s!"row group {rgIdx}: schema: {e}")
  | .ok leaves =>
    match fileMeta.rowGroups[rgIdx]? with
    | none => return (.error s!"readTableForRowGroup: row group index {rgIdx} out of range")
    | some rg =>
      match SchemaWalk.matchLeavesToChunks leaves rg.columns with
      | .error e => return (.error s!"row group {rgIdx}: {e}")
      | .ok leafMatched => do
        let mut cols : Array Column := #[]
        for pair in rg.columns.zip leafMatched do
          let (chunk, leaf) := pair
          let m := chunk.columnMeta
          let start := chunkStartOffset m
          match (← readPagesForColumnByteArray file m.codec leaf.phys leaf.maxDefinitionLevel leaf.maxRepetitionLevel m.numValues
                start #[] none (pageReadFuel m.numValues)) with
          | .error msg => return (.error s!"row group {rgIdx} column {".".intercalate leaf.pathParts.toList}: {msg}")
          | .ok (vals, _) =>
            let nm := ".".intercalate leaf.pathParts.toList
            cols := cols.push ⟨nm, vals⟩
        return (.ok { columns := cols })

/-- Decode one row group using a generic backing (mmap uses slice reads). -/
def readTableForRowGroup (backing : ParquetBacking) (fileMeta : FileMetaDataParsed) (rgIdx : Nat) : IO (Err Table) :=
  match backing with
  | .ofByteArray b => readTableForRowGroupBytes b fileMeta rgIdx
  | .ofMmap _ => do
    match SchemaWalk.preorderLeavesFromSchema fileMeta.schema with
    | .error e => return (.error s!"row group {rgIdx}: schema: {e}")
    | .ok leaves =>
      match fileMeta.rowGroups[rgIdx]? with
      | none => return (.error s!"readTableForRowGroup: row group index {rgIdx} out of range")
      | some rg =>
        match SchemaWalk.matchLeavesToChunks leaves rg.columns with
        | .error e => return (.error s!"row group {rgIdx}: {e}")
        | .ok leafMatched => do
          let mut cols : Array Column := #[]
          for pair in rg.columns.zip leafMatched do
            let (chunk, leaf) := pair
            let m := chunk.columnMeta
            let start := chunkStartOffset m
            match (← readPagesForColumn backing m.codec leaf.phys leaf.maxDefinitionLevel leaf.maxRepetitionLevel m.numValues
                  start #[] none (pageReadFuel m.numValues)) with
            | .error msg => return (.error s!"row group {rgIdx} column {".".intercalate leaf.pathParts.toList}: {msg}")
            | .ok (vals, _) =>
              let nm := ".".intercalate leaf.pathParts.toList
              cols := cols.push ⟨nm, vals⟩
          return (.ok { columns := cols })

def readParquetFromBytes (file : ByteArray) : IO (Err Table) :=
  match readFooterBytes file with
  | .error e => pure (.error e)
  | .ok footer =>
    match parseFileMetaData footer with
    | .error e => pure (.error e)
    | .ok fileMeta => do
      if fileMeta.rowGroups.isEmpty then return (.error "no row groups")
      readTableForRowGroupBytes file fileMeta 0

def readParquetFromBacking (backing : ParquetBacking) : IO (Err Table) := do
  match backing with
  | .ofByteArray b => readParquetFromBytes b
  | .ofMmap _ =>
    match ← readParquetFooterIO backing with
    | .error e => return (.error e)
    | .ok footer =>
      match parseFileMetaData footer with
      | .error e => return (.error e)
      | .ok fileMeta => do
        if fileMeta.rowGroups.isEmpty then return (.error "no row groups")
        readTableForRowGroup backing fileMeta 0

def readParquetRowGroupFromBytes (file : ByteArray) (rgIdx : Nat) : IO (Err Table) :=
  match readFooterBytes file with
  | .error e => pure (.error e)
  | .ok footer =>
    match parseFileMetaData footer with
    | .error e => pure (.error e)
    | .ok fm => do
      if fm.rowGroups.isEmpty then return (.error "no row groups")
      readTableForRowGroupBytes file fm rgIdx

def readParquetRowGroupFromBacking (backing : ParquetBacking) (rgIdx : Nat) : IO (Err Table) := do
  match backing with
  | .ofByteArray b => readParquetRowGroupFromBytes b rgIdx
  | .ofMmap _ =>
    match ← readParquetFooterIO backing with
    | .error e => return (.error e)
    | .ok footer =>
      match parseFileMetaData footer with
      | .error e => return (.error e)
      | .ok fm => do
        if fm.rowGroups.isEmpty then return (.error "no row groups")
        readTableForRowGroup backing fm rgIdx

def readParquetAllRowGroupsFromBytes (file : ByteArray) : IO (Err Table) :=
  match readFooterBytes file with
  | .error e => pure (.error e)
  | .ok footer =>
    match parseFileMetaData footer with
    | .error e => pure (.error e)
    | .ok fm => do
      if fm.rowGroups.isEmpty then return (.error "no row groups")
      match ← readTableForRowGroupBytes file fm 0 with
      | .error e => pure (.error e)
      | .ok t0 => do
        if fm.rowGroups.size == 1 then return (.ok t0)
        let mut acc := t0
        for offset in [:(fm.rowGroups.size - 1)] do
          let i := offset + 1
          match ← readTableForRowGroupBytes file fm i with
          | .error e => return (.error e)
          | .ok ti =>
            match Columnar.Table.appendRows acc ti with
            | .error e => return (.error e)
            | .ok acc' => acc := acc'
        return (.ok acc)

def readParquetAllRowGroupsFromBacking (backing : ParquetBacking) : IO (Err Table) := do
  match backing with
  | .ofByteArray b => readParquetAllRowGroupsFromBytes b
  | .ofMmap _ =>
    match ← readParquetFooterIO backing with
    | .error e => return (.error e)
    | .ok footer =>
      match parseFileMetaData footer with
      | .error e => return (.error e)
      | .ok fm => do
        if fm.rowGroups.isEmpty then return (.error "no row groups")
        match ← readTableForRowGroup backing fm 0 with
        | .error e => return (.error e)
        | .ok t0 => do
          if fm.rowGroups.size == 1 then return (.ok t0)
          let mut acc := t0
          for offset in [:(fm.rowGroups.size - 1)] do
            let i := offset + 1
            match ← readTableForRowGroup backing fm i with
            | .error e => return (.error e)
            | .ok ti =>
              match Columnar.Table.appendRows acc ti with
              | .error e => return (.error e)
              | .ok acc' => acc := acc'
          return (.ok acc)

def readParquetRowGroup (path : System.FilePath) (rgIdx : Nat) : IO (Err Table) := do
  let bytes ← readFileBytes path
  readParquetRowGroupFromBytes bytes rgIdx

def readParquetAllRowGroups (path : System.FilePath) : IO (Err Table) := do
  let bytes ← readFileBytes path
  readParquetAllRowGroupsFromBytes bytes

def readParquet (path : System.FilePath) : IO (Err Table) := do
  let bytes ← readFileBytes path
  readParquetFromBytes bytes

/-- Open footer metadata: tries `mmap` first, falls back to `readBinFile` if mmap is unavailable. -/
structure ParquetFile where
  backing : ParquetBacking
  fileMeta : FileMetaDataParsed

def ParquetFile.dispose (pf : ParquetFile) : IO Unit :=
  match pf.backing with
  | .ofByteArray _ => pure ()
  | .ofMmap m => m.close

def openParquetFile (path : System.FilePath) : IO (Except String ParquetFile) := do
  match ← mmapOpenTry path with
  | Except.ok m =>
    let backing := ParquetBacking.ofMmap m
    match ← readParquetFooterIO backing with
    | .error e =>
      let _ ← m.close
      return Except.error e
    | .ok footer =>
      match parseFileMetaData footer with
      | .error e =>
        let _ ← m.close
        return Except.error e
      | .ok fm => return Except.ok ⟨backing, fm⟩
  | Except.error _ =>
    let bytes ← readFileBytes path
    match readFooterBytes bytes with
    | .error e => return Except.error e
    | .ok footer =>
      match parseFileMetaData footer with
      | .error e => return Except.error e
      | .ok fm => return Except.ok ⟨ParquetBacking.ofByteArray bytes, fm⟩

/-- Read row group 0 via `openParquetFile` (mmap-backed slice reads when mmap succeeds; else `readBinFile`). -/
def readParquetMmap (path : System.FilePath) : IO (Err Table) := do
  match ← openParquetFile path with
  | .error e => return .error e
  | .ok pf => do
    try
      readTableForRowGroup pf.backing pf.fileMeta 0
    finally
      pf.dispose

def readFileMetaFromBytes (file : ByteArray) : Err FileMetaDataParsed :=
  match readFooterBytes file with
  | .error e => .error e
  | .ok footer =>
    match parseFileMetaData footer with
    | .error e => .error e
    | .ok fm => .ok fm

def readFileMeta (path : System.FilePath) : IO (Err FileMetaDataParsed) := do
  let bytes ← readFileBytes path
  return readFileMetaFromBytes bytes

def readFileMetaFromBacking (backing : ParquetBacking) : IO (Err FileMetaDataParsed) := do
  match backing with
  | .ofByteArray b =>
    match readFooterBytes b with
    | .error e => return .error e
    | .ok footer =>
      match parseFileMetaData footer with
      | .error e => return .error e
      | .ok fm => return .ok fm
  | .ofMmap _ =>
    match ← readParquetFooterIO backing with
    | .error e => return .error e
    | .ok footer =>
      match parseFileMetaData footer with
      | .error e => return .error e
      | .ok fm => return .ok fm

/-- Number of row-group entries in the footer (streaming / planning). -/
def parquetRowGroupCount (path : System.FilePath) : IO (Err Nat) := do
  match ← readFileMeta path with
  | .error e => return .error e
  | .ok fm => return .ok fm.rowGroups.size

/-- Row-group iterator with shared backing for on-demand decode (`readTableForRowGroup`). -/
structure RowGroupDecodeStream where
  backing : ParquetBacking
  fileMeta : FileMetaDataParsed
  idx : Nat

def RowGroupDecodeStream.init (backing : ParquetBacking) (fileMeta : FileMetaDataParsed) : RowGroupDecodeStream :=
  ⟨backing, fileMeta, 0⟩

/-- Decode the next row group; `ok none` = end of stream; `error` = decode failure. -/
def RowGroupDecodeStream.nextDecoded (s : RowGroupDecodeStream) : IO (Except String (Option (Table × RowGroupDecodeStream))) := do
  if s.idx < s.fileMeta.rowGroups.size then
    match ← readTableForRowGroup s.backing s.fileMeta s.idx with
    | .error e => return .error e
    | .ok tbl => return .ok (some (tbl, { s with idx := s.idx + 1 }))
  else return .ok none

end Columnar.Parquet.Reader
