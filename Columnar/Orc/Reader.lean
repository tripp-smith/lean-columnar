import Init.Data.ByteArray
import Columnar.Core.Bytes
import Columnar.Orc.Protobuf
import Columnar.Orc.FooterRead
import Columnar.Orc.RleV2
import Columnar.Compression.Gzip
import Columnar.Table
import Columnar.Parquet.Encoding.Plain

namespace Columnar.Orc.Reader

open Columnar.ByteArrayOps
open Columnar.Parquet.Encoding.Plain

def fileMagicPrefix : ByteArray :=
  ByteArray.mk #[79, 82, 67] -- "ORC"

def bytesLikelyOrc (pfx : ByteArray) : Bool :=
  pfx.size ≥ 3 && pfx.extract 0 3 == fileMagicPrefix

def readOrcNumberOfRowsFromBytes (file : ByteArray) : IO (Except String Nat) := do
  if file.size < 8 then return Except.error "ORC: file too small"
  let psLen := (readU8 file (file.size - 1)).toNat
  if psLen == 0 || psLen ≥ file.size then return Except.error "ORC: bad postscript length"
  let psStart := file.size - 1 - psLen
  let postscript := file.extract psStart (psStart + psLen)
  let footerLenU ← match Columnar.Orc.Protobuf.findVarintField postscript 0 psLen 1 with
    | .error e => return Except.error e
    | .ok v => pure v
  let footerCompLen := footerLenU.toNat
  if footerCompLen == 0 || footerCompLen > psStart then return Except.error "ORC: bad footer length"
  let footerStart := psStart - footerCompLen
  let footerBlob := file.extract footerStart (footerStart + footerCompLen)
  let compression :=
    match Columnar.Orc.Protobuf.findVarintField postscript 0 psLen 2 with
    | .error _ => 0
    | .ok v => v.toNat
  let cap := min (footerCompLen * 64 + 65536) (256 * 1024 * 1024)
  let fb ←
    if compression == 0 then pure footerBlob
    else if compression == 1 then
      try
        Columnar.Compression.Gzip.decompress footerBlob cap
      catch _ =>
        return Except.error "ORC: footer zlib decompress failed (zlib)"
    else return Except.error "ORC: unsupported footer compression"
  match Columnar.Orc.Protobuf.findVarintField fb 0 fb.size 6 with
  | .error e => return Except.error e
  | .ok rowsU => return Except.ok rowsU.toNat

def readOrcNumberOfRows (path : System.FilePath) : IO (Except String Nat) := do
  let bytes ← IO.FS.readBinFile path
  readOrcNumberOfRowsFromBytes bytes

/-- Parse `Type` protobuf blob: field 1 = Kind enum, optional field 3 = UTF-8 name (interop subset). -/
private partial def parseTypeBlobKindAndName (b : ByteArray) : Except String (Nat × Option String) :=
  let rec go (pos : Nat) (kind : Option Nat) (nm : Option String) : Except String (Nat × Option String) :=
    if pos ≥ b.size then
      match kind with
      | none => throw "ORC Type: missing kind"
      | some k => pure (k, nm)
    else
      match Columnar.Orc.Protobuf.readTag b pos with
      | .error e => throw e
      | .ok (tag, p1) =>
        let w := Columnar.Orc.Protobuf.wireType tag
        let fn := Columnar.Orc.Protobuf.fieldNumber tag
        if w == 0 then
          match Columnar.Orc.Protobuf.readVarUInt64 b p1 with
          | .error e => throw e
          | .ok (v, p2) =>
            if fn == 1 then go p2 (some v.toNat) nm else go p2 kind nm
        else if w == 2 && fn == 3 then
          match Columnar.Orc.Protobuf.readVarUInt64 b p1 with
          | .error e => throw e
          | .ok (lenU, p2) =>
            let ln := lenU.toNat
            if p2 + ln > b.size then throw "ORC Type: bad string"
            else
              let slice := b.extract p2 (p2 + ln)
              match String.fromUTF8? slice with
              | none => throw "ORC Type: invalid UTF-8 name"
              | some s => go (p2 + ln) kind (some s)
        else
          match Columnar.Orc.Protobuf.skipField b p1 w with
          | .error e => throw e
          | .ok p2 => go p2 kind nm
  go 0 none none

/-- Collect Footer field 4 (`Type`) length-delimited blobs in wire order. -/
private partial def collectFooterTypeBlobs (footer : ByteArray) (pos : Nat) (acc : List ByteArray)
    : Except String (List ByteArray) :=
  if pos ≥ footer.size then pure acc.reverse
  else
    match Columnar.Orc.Protobuf.readTag footer pos with
    | .error e => throw e
    | .ok (tag, p1) =>
      let w := Columnar.Orc.Protobuf.wireType tag
      let fn := Columnar.Orc.Protobuf.fieldNumber tag
      if fn == 4 && w == 2 then
        match Columnar.Orc.Protobuf.readVarUInt64 footer p1 with
        | .error e => throw e
        | .ok (lenU, p2) =>
          let ln := lenU.toNat
          if p2 + ln > footer.size then throw "ORC: bad Type blob"
          else
            let blob := footer.extract p2 (p2 + ln)
            collectFooterTypeBlobs footer (p2 + ln) (blob :: acc)
      else
        match Columnar.Orc.Protobuf.skipField footer p1 w with
        | .error e => throw e
        | .ok p2 => collectFooterTypeBlobs footer p2 acc

/-- Read primitive `INT` column from a **single-stripe, uncompressed** ORC file with schema
`struct{x:int}` (matches `Tests/fixtures/interop_orc_int32.orc`). Other layouts return an error. -/
def readOrcPrimitivesFromBytes (file : ByteArray) (want : List String) : IO (Except String Columnar.Table) := do
  match ← Columnar.Orc.FooterRead.readFirstStripeLayout file with
  | .error e => return .error e
  | .ok (footerPlain, o, i, d, _f, r) =>
    match collectFooterTypeBlobs footerPlain 0 [] with
    | .error e => return .error e
    | .ok blobs =>
      match blobs with
      | [] | [_] => return .error "ORC readOrcPrimitives: expected ≥2 Type entries"
      | b0 :: b1 :: _ =>
        match parseTypeBlobKindAndName b0 with
        | .error e => return .error e
        | .ok (k0, name0) =>
          match parseTypeBlobKindAndName b1 with
          | .error e => return .error e
          | .ok (k1, _) =>
            let kindStruct := 12
            let kindInt := 3
            if k0 != kindStruct || k1 != kindInt then
              return .error "ORC readOrcPrimitives: expected STRUCT then INT types"
            else
              let colName :=
                match name0 with
                | none => "x"
                | some n => n
              let wantNorm := want.map fun s => (String.trimAscii s).toString
              let colNorm := (String.trimAscii colName).toString
              unless wantNorm == [colNorm] do
                return .error s!"ORC readOrcPrimitives: only single-column {repr colNorm} supported (want {repr want})"
              if o + i + d > file.size then return .error "ORC readOrcPrimitives: stripe data out of range"
              else
                let data := file.extract (o + i) (o + i + d)
                match Columnar.Orc.RleV2.decodeInt32DataNoNulls data r with
                | .error e => return .error e
                | .ok ints =>
                  let vals : Array (Option PlainValue) := ints.map fun n => some (PlainValue.int32 n)
                  return .ok { columns := #[{ name := colName, values := vals }] }

def readOrcPrimitives (path : System.FilePath) (want : List String) : IO (Except String Columnar.Table) := do
  let bytes ← IO.FS.readBinFile path
  readOrcPrimitivesFromBytes bytes want

end Columnar.Orc.Reader
