import Init.Data.ByteArray
import Columnar.Core.Bytes
import Columnar.Orc.Protobuf
import Columnar.Compression.Gzip

namespace Columnar.Orc.FooterRead

open Columnar.ByteArrayOps
open Columnar.Orc.Protobuf

abbrev P := Except String

def decompressFooterBlob (footerBlob : ByteArray) (compression : Nat) : IO (Except String ByteArray) :=
  if compression == 0 then pure (.ok footerBlob)
  else if compression == 1 then
    let cap := min (footerBlob.size * 64 + 65536) (256 * 1024 * 1024)
    try
      let fb ← Columnar.Compression.Gzip.decompress footerBlob cap
      pure (.ok fb)
    catch _ =>
      pure (.error "ORC: footer zlib decompress failed (zlib)")
  else pure (.error "ORC: unsupported footer compression")

/-- Read postscript: footer compressed length (field 1) and compression kind (field 2). -/
partial def readPostscript (file : ByteArray) : P (Nat × Nat × Nat) :=
  if file.size < 8 then throw "ORC: file too small"
  else
    let psLen := (readU8 file (file.size - 1)).toNat
    if psLen == 0 || psLen ≥ file.size then throw "ORC: bad postscript length"
    else
      let psStart := file.size - 1 - psLen
      let postscript := file.extract psStart (psStart + psLen)
      let rec walk (pos : Nat) (footerLen : Option Nat) (compression : Nat) : P (Nat × Nat × Nat) :=
        if pos ≥ postscript.size then
          match footerLen with
          | none => throw "ORC: missing footer length in postscript"
          | some fl => pure (psStart, fl, compression)
        else do
          let (tag, p1) ← readTag postscript pos
          let w := wireType tag
          let fn := fieldNumber tag
          if w == 0 then do
            let (v, p2) ← readVarUInt64 postscript p1
            let vN := v.toNat
            if fn == 1 then walk p2 (some vN) compression
            else if fn == 2 then walk p2 footerLen vN
            else walk p2 footerLen compression
          else if w == 2 then do
            let (lenU, p2) ← readVarUInt64 postscript p1
            let ln := lenU.toNat
            if p2 + ln > postscript.size then throw "ORC: bad postscript delimited"
            else walk (p2 + ln) footerLen compression
          else if w == 5 then
            if p1 + 4 ≤ postscript.size then walk (p1 + 4) footerLen compression
            else throw "ORC: truncated postscript"
          else if w == 1 then
            if p1 + 8 ≤ postscript.size then walk (p1 + 8) footerLen compression
            else throw "ORC: bad postscript wire type"
          else throw "ORC: bad postscript wire type"
      walk 0 none 0

private partial def parseStripeInformationBlob (b : ByteArray) : P (Nat × Nat × Nat × Nat × Nat) :=
  let rec go (pos : Nat) (off idx data foot rows : Option Nat) : P (Nat × Nat × Nat × Nat × Nat) :=
    if pos ≥ b.size then
      match off, idx, data, foot, rows with
      | some o, some i, some d, some f, some r => pure (o, i, d, f, r)
      | _, _, _, _, _ => throw "ORC: incomplete StripeInformation"
    else do
      let (tag, p1) ← readTag b pos
      let w := wireType tag
      let fn := fieldNumber tag
      if w == 0 then do
        let (v, p2) ← readVarUInt64 b p1
        let vn := v.toNat
        if fn == 1 then go p2 (some vn) idx data foot rows
        else if fn == 2 then go p2 off (some vn) data foot rows
        else if fn == 3 then go p2 off idx (some vn) foot rows
        else if fn == 4 then go p2 off idx data (some vn) rows
        else if fn == 5 then go p2 off idx data foot (some vn)
        else go p2 off idx data foot rows
      else do
        let p2 ← skipField b p1 w
        go p2 off idx data foot rows
  go 0 none none none none none

/-- Parse first `StripeInformation` in Footer field 3 (offset, index, data, footer lengths, rows). -/
partial def parseFirstStripeInfo (footerPlain : ByteArray) : P (Nat × Nat × Nat × Nat × Nat) :=
  let rec walk (pos : Nat) : P (Nat × Nat × Nat × Nat × Nat) :=
    if pos ≥ footerPlain.size then throw "ORC: stripe info not found"
    else do
      let (tag, p1) ← readTag footerPlain pos
      let w := wireType tag
      let fn := fieldNumber tag
      if fn == 3 && w == 2 then do
        let (lenU, p2) ← readVarUInt64 footerPlain p1
        let ln := lenU.toNat
        if p2 + ln > footerPlain.size then throw "ORC: bad stripe delimited"
        else
          let blob := footerPlain.extract p2 (p2 + ln)
          parseStripeInformationBlob blob
      else do
        let p2 ← skipField footerPlain p1 w
        walk p2
  walk 0

/-- Decompressed footer + first stripe layout (single-stripe interop files). -/
def readFirstStripeLayout (file : ByteArray) : IO (P (ByteArray × Nat × Nat × Nat × Nat × Nat)) := do
  match readPostscript file with
  | .error e => return .error e
  | .ok (psStart, footerCompLen, compression) =>
    if footerCompLen == 0 || footerCompLen > psStart then return .error "ORC: bad footer length"
    else
      let footerStart := psStart - footerCompLen
      let footerBlob := file.extract footerStart (footerStart + footerCompLen)
      match ← decompressFooterBlob footerBlob compression with
      | .error e => return .error e
      | .ok footerPlain =>
        match parseFirstStripeInfo footerPlain with
        | .error e => return .error e
        | .ok (o, i, d, f, r) => return .ok (footerPlain, o, i, d, f, r)

end Columnar.Orc.FooterRead
