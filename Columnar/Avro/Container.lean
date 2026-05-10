import Init.Data.ByteArray
import Columnar.Core.Bytes
import Columnar.Avro.Schema
import Columnar.Avro.Binary
import Columnar.Compression.Gzip
import Columnar.Compression.Snappy
import Columnar.Table
import Columnar.Parquet.Encoding.Plain

namespace Columnar.Avro.Container

open Columnar.ByteArrayOps
open Columnar.Parquet.Encoding.Plain
open Columnar.Avro

abbrev P := Except String

private def natFromNonNegInt64 (x : Int64) : Nat :=
  Int.natAbs (Int64.toInt x)

def objectContainerFileMagic : ByteArray :=
  ByteArray.mk #[79, 98, 106, 1]

def bytesLikelyOcf (pfx : ByteArray) : Bool :=
  pfx.size ≥ 4 && pfx.extract 0 4 == objectContainerFileMagic

partial def readMapStringBytes (b : ByteArray) (pos : Nat) : P (List (String × ByteArray) × Nat) :=
  let rec readBlocks (p : Nat) (acc : List (String × ByteArray)) : P (List (String × ByteArray) × Nat) := do
    let (cnt, p1) ← Columnar.Avro.Binary.readLong b p
    if cnt == 0 then pure (acc.reverse, p1)
    else if cnt < 0 then throw "Avro map: negative block count not implemented"
    else
      let n := natFromNonNegInt64 cnt
      let rec readPairs (k : Nat) (p : Nat) (a : List (String × ByteArray)) : P (List (String × ByteArray) × Nat) :=
        if k == 0 then pure (a, p)
        else do
          let (ks, p2) ← Columnar.Avro.Binary.readString b p
          let (vb, p3) ← Columnar.Avro.Binary.readBytes b p2
          readPairs (k - 1) p3 ((ks, vb) :: a)
      let (pairs, pN) ← readPairs n p1 []
      readBlocks pN (acc ++ pairs.reverse)
  readBlocks pos []

/-- Zlib decompress used by Avro `deflate` codec (`COLUMNAR_CODEC=1` + `-lz`). -/
partial def decompressDeflate (compressed : ByteArray) : IO (Except String ByteArray) := do
  let cap := min (compressed.size * 64 + 65536) (256 * 1024 * 1024)
  try
    let out ← Columnar.Compression.Gzip.decompress compressed cap
    pure (.ok out)
  catch _ =>
    pure (.error "Avro OCF: deflate decompress failed (zlib)")

/-- Avro OCF Snappy: each block is `u32_be uncompressed_size` + Snappy-compressed bytes (see Avro spec). -/
def decompressSnappyBlock (compressed : ByteArray) : IO (Except String ByteArray) := do
  if compressed.size < 4 then return .error "Avro OCF: snappy block too short"
  match Columnar.ByteArrayOps.readUInt32BE compressed 0 with
  | none => return .error "Avro OCF: snappy header read"
  | some ulen =>
    let ulenN := ulen.toNat
    let payload := compressed.extract 4 compressed.size
    try
      let out ← Columnar.Compression.Snappy.decompress payload ulenN
      pure (.ok out)
    catch e =>
      pure (.error s!"Avro OCF: snappy decompress failed ({e.toString})")

def decompressCodec (codec : String) (compressed : ByteArray) : IO (Except String ByteArray) :=
  if codec == "null" || codec == "" then pure (.ok compressed)
  else if codec == "deflate" then decompressDeflate compressed
  else if codec == "snappy" then decompressSnappyBlock compressed
  else pure (.error s!"Avro OCF: unknown codec {repr codec}")

partial def decodeSerialRows (schema : AvroType) (payload : ByteArray) (rowCount : Nat) (pos : Nat)
    (acc : Array (Array PlainValue)) : P (Array (Array PlainValue)) :=
  if rowCount == 0 then pure acc
  else do
    let (row, pos2) ← Columnar.Avro.Binary.decodeRecordRow schema payload pos
    decodeSerialRows schema payload (rowCount - 1) pos2 (acc.push row)

def rowsToTable (fieldNames : List String) (rows : Array (Array PlainValue)) : P Columnar.Table := do
  if fieldNames.length == 0 then throw "Avro OCF: empty schema fields"
  let width := fieldNames.length
  let nRows := rows.size
  let mut cols : Array Columnar.Column := #[]
  for fi in [:width] do
    let fname :=
      match (fieldNames.drop fi).head? with
      | none => "?"
      | some nm => nm
    let mut colVals : Array (Option PlainValue) := #[]
    for ri in [:nRows] do
      let row := rows[ri]!
      if row.size != width then throw "Avro OCF: irregular row width"
      if h : fi < row.size then
        colVals := colVals.push (some row[fi])
      else throw "Avro OCF: row index out of range"
    cols := cols.push { name := fname, values := colVals }
  pure { columns := cols }

partial def readAvroOcfFromBytesCore (b : ByteArray) (schema : AvroType) (fieldNames : List String)
    (sync : ByteArray) (pos : Nat) (accRows : Array (Array PlainValue)) (codec : String) :
    IO (P (Array (Array PlainValue))) := do
  if pos + 16 > b.size then pure (.ok accRows)
  else
    match Columnar.Avro.Binary.readLong b pos with
    | .error e => pure (.error e)
    | .ok (rowCount64, p2) =>
      if rowCount64 < 0 then pure (.error "Avro OCF: negative row count")
      else
        match Columnar.Avro.Binary.readLong b p2 with
        | .error e => pure (.error e)
        | .ok (blockLen64, p3) =>
          if blockLen64 < 0 then pure (.error "Avro OCF: negative block length")
          else
            let rowCount := natFromNonNegInt64 rowCount64
            let bl := natFromNonNegInt64 blockLen64
            if p3 + bl + 16 > b.size then pure (.error "Avro OCF: truncated block")
            else
              let blockBytes := b.extract p3 (p3 + bl)
              let pSync := p3 + bl
              let syncGot := b.extract pSync (pSync + 16)
              if syncGot != sync then pure (.error "Avro OCF: sync mismatch")
              else
                match ← decompressCodec codec blockBytes with
                | .error e => pure (.error e)
                | .ok payload =>
                  match decodeSerialRows schema payload rowCount 0 #[] with
                  | .error e => pure (.error e)
                  | .ok chunk =>
                    let merged := accRows ++ chunk
                    readAvroOcfFromBytesCore b schema fieldNames sync (pSync + 16) merged codec

def readAvroOcfFromBytes (b : ByteArray) : IO (P Columnar.Table) := do
  if b.size < 4 + 16 then return (.error "Avro OCF: file too small")
  unless b.extract 0 4 == objectContainerFileMagic do
    return (.error "Avro OCF: bad magic")
  match readMapStringBytes b 4 with
  | .error e => return (.error e)
  | .ok (hdrMeta, pos1) =>
    let schemaBytes? := hdrMeta.find? fun p => p.1 == "avro.schema"
    let codecEntry := hdrMeta.find? fun p => p.1 == "avro.codec"
    let codec :=
      match codecEntry with
      | none => "null"
      | some (_, raw) =>
        match String.fromUTF8? raw with
        | none => "null"
        | some s => s
    match schemaBytes? with
    | none => return (.error "Avro OCF: missing avro.schema")
    | some (_, raw) =>
      match String.fromUTF8? raw with
      | none => return (.error "Avro OCF: bad schema UTF-8")
      | some schemaStr =>
        match Columnar.Avro.parseSchemaJsonString schemaStr with
        | .error e => return (.error e)
        | .ok schema =>
          match schema with
          | .record _ fs =>
            let fieldNames := fs.map Prod.fst
            if pos1 + 16 > b.size then return (.error "Avro OCF: truncated header")
            let sync := b.extract pos1 (pos1 + 16)
            let pos := pos1 + 16
            match ← readAvroOcfFromBytesCore b schema fieldNames sync pos #[] codec with
            | .error e => return (.error e)
            | .ok rows =>
              match rowsToTable fieldNames rows with
              | .error e => return (.error e)
              | .ok tbl => return (.ok tbl)
          | _ => return (.error "Avro OCF: root must be record")

def readAvroOcf (path : System.FilePath) : IO (P Columnar.Table) := do
  let bytes ← IO.FS.readBinFile path
  readAvroOcfFromBytes bytes

end Columnar.Avro.Container
