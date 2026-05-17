import Init.Data.ByteArray
import Columnar.Orc.Protobuf
import Columnar.Orc.FooterProto
import Columnar.Orc.Compress
import Columnar.Orc.TypeParse
import Columnar.Orc.RleV2
import Columnar.Orc.RleByte
import Columnar.Orc.Schema
import Columnar.Orc.FooterRead
import Columnar.Parquet.Encoding.Plain
import Columnar.Table

namespace Columnar.Orc.StripeDecode

open Columnar.Orc.Protobuf
open Columnar.Orc.FooterProto
open Columnar.Orc.Compress
open Columnar.Orc.TypeParse
open Columnar.Orc.RleV2
open Columnar.Orc.RleByte
open Columnar.Orc.Schema
open Columnar.Parquet.Encoding.Plain

abbrev P := Except String

structure StreamInfo where
  column : Nat
  kind : Nat
  length : Nat

partial def parseStreamBlob (b : ByteArray) : P StreamInfo :=
  let rec go (pos : Nat) (col kind len : Option Nat) : P StreamInfo :=
    if pos ≥ b.size then
      match col, kind, len with
      | some c, some k, some l => pure { column := c, kind := k, length := l }
      | _, _, _ => throw "ORC Stream: incomplete"
    else do
      let (tag, p1) ← readTag b pos
      let w := wireType tag
      let fn := fieldNumber tag
      if w == 0 then
        let (v, p2) ← readVarUInt64 b p1
        let vn := v.toNat
        if fn == 1 then go p2 (some vn) kind len
        else if fn == 2 then go p2 col (some vn) len
        else if fn == 3 then go p2 col kind (some vn)
        else go p2 col kind len
      else do
        let p2 ← skipField b p1 w
        go p2 col kind len
  go 0 none none none

def parseStripeStreamsFromFooter (stripeFooterPlain : ByteArray) : P (List StreamInfo) := do
  let blobs ← collectStreamBlobs stripeFooterPlain
  blobs.mapM parseStreamBlob

partial def parseStripeInformationBlob (b : ByteArray) : P (Nat × Nat × Nat × Nat × Nat) :=
  let rec go (pos : Nat) (off idx data foot rows : Option Nat) : P (Nat × Nat × Nat × Nat × Nat) :=
    if pos ≥ b.size then
      match off, idx, data, foot, rows with
      | some o, some i, some d, some f, some r => pure (o, i, d, f, r)
      | _, _, _, _, _ => throw "ORC: incomplete StripeInformation"
    else do
      let (tag, p1) ← readTag b pos
      let w := wireType tag
      let fn := fieldNumber tag
      if w == 0 then
        let (v, p2) ← readVarUInt64 b p1
        let vn := v.toNat
        if fn == 1 then go p2 (some vn) idx data foot rows
        else if fn == 2 then go p2 off (some vn) data foot rows
        else if fn == 3 then go p2 off idx (some vn) foot rows
        else if fn == 4 then go p2 off idx data (some vn) rows
        else if fn == 5 then go p2 off idx data foot (some vn)
        else go p2 off idx data foot rows
      else do
        let p2 ← skipFieldGroupAware b p1 w
        go p2 off idx data foot rows
  go 0 none none none none none

def tryDecodeStreamPayload (payload : ByteArray) (rows : Nat) (orcK : OrcKind) : Option (Array PlainValue) :=
  match orcK with
  | .boolean =>
    match decodeBooleanDataNoNulls payload rows with
    | .error _ => none
    | .ok bs => if bs.size == rows then some (bs.map fun b => PlainValue.bool b) else none
  | .int =>
    match decodeInt32DataNoNulls payload rows with
    | .error _ => none
    | .ok ints => if ints.size == rows then some (ints.map fun n => PlainValue.int32 n) else none
  | _ => none

/-- Zlib stripe file (`TestOrcFile.test1.orc`): footer + sequential streams, scan-decode by type. -/
def readOrcPrimitivesZlibStripe (file : ByteArray) (want : List String) : IO (P Table) := do
  match ← Columnar.Orc.FooterRead.readFirstStripeLayout file with
  | .error e => return .error e
  | .ok (footerPlain, o, indexLen, dataLen, footerLen, rows) =>
    match parseAllTypes footerPlain with
    | .error e => return .error e
    | .ok types =>
      let stripeTotal := indexLen + dataLen + footerLen
      if o + stripeTotal > file.size then return .error "ORC: stripe out of range"
      else
        let stripe := file.extract o (o + stripeTotal)
        let blob := stripe.extract 0 (indexLen + dataLen)
        let stripeFooterBlob := stripe.extract (indexLen + dataLen) stripe.size
        let footerPlainStripe ←
          if stripeFooterBlob.size ≥ 3 then
            decompressOrcZlibBlob stripeFooterBlob (stripeFooterBlob.size * 64)
          else pure stripeFooterBlob
        match parseStripeStreamsFromFooter footerPlainStripe with
        | .error e => return .error e
        | .ok streams => do
          let rec readWants (ws : List String) (ss : List StreamInfo) (pos : Nat) (acc : Array Column)
              : IO (P (Array Column)) :=
            match ws with
            | [] => pure (.ok acc)
            | w :: rest =>
              let wtrim := (String.trimAscii w).toString
              match columnNameToId types wtrim with
              | none => return .error s!"ORC: column {repr wtrim} not in schema"
              | some typeId =>
                if typeId ≥ types.size then return .error "ORC: bad type index"
                else
                  match orcKindFromNat types[typeId]!.kind with
                  | none => return .error s!"ORC: unsupported type kind"
                  | some orcK => do
                    let kindsFor :=
                      match orcK with
                      | .boolean => [1]
                      | .int => [4, 1]
                      | _ => []
                    let rec findCol (rem : List StreamInfo) (p : Nat) (best : Option (Nat × Array PlainValue))
                        : IO (P (Nat × Array PlainValue)) :=
                      match rem with
                      | [] =>
                        match best with
                        | some pair => return .ok pair
                        | none => return .error s!"ORC: no stream for column {repr wtrim}"
                      | s :: tail =>
                        if p + s.length > blob.size then return .error "ORC: stream OOB"
                        else do
                          let chunk := blob.extract p (p + s.length)
                          let p' := p + s.length
                          let best' ←
                            if kindsFor.contains s.kind then
                              do
                                let payload ← orcStreamPayload chunk
                                match tryDecodeStreamPayload payload rows orcK with
                                | some vals => pure (some (p', vals))
                                | none => pure best
                            else pure best
                          findCol tail p' best'
                    match ← findCol ss pos none with
                    | .error e => return .error e
                    | .ok (_, vals) =>
                      let col := { name := wtrim, values := vals.map some }
                      readWants rest ss 0 (acc ++ #[col])
          match ← readWants want streams 0 #[] with
          | .error e => return (.error e : P Table)
          | .ok cols => return .ok { columns := cols }

end Columnar.Orc.StripeDecode
