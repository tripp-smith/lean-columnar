import Init.Data.ByteArray
import Columnar.Orc.Protobuf
import Columnar.Orc.FooterProto
import Columnar.Orc.Schema

namespace Columnar.Orc.TypeParse

open Columnar.Orc.Protobuf
open Columnar.Orc.FooterProto
open Columnar.Orc.Schema

abbrev P := Except String

structure OrcTypeParsed where
  kind : Nat
  fieldNames : List String
  subtypes : List Nat
  deriving Inhabited

partial def parseTypeBlob (b : ByteArray) : P OrcTypeParsed :=
  let rec go (pos : Nat) (kind : Option Nat) (subs : List Nat) (names : List String) : P OrcTypeParsed :=
    if pos ≥ b.size then
      match kind with
      | none => throw "ORC Type: missing kind"
      | some k => pure { kind := k, fieldNames := names, subtypes := subs }
    else do
      let (tag, p1) ← readTag b pos
      let w := wireType tag
      let fn := fieldNumber tag
      if w == 0 then
        let (v, p2) ← readVarUInt64 b p1
        if fn == 1 then go p2 (some v.toNat) subs names
        else if fn == 2 then go p2 kind (subs ++ [v.toNat]) names
        else go p2 kind subs names
      else if w == 2 && fn == 3 then
        let (lenU, p2) ← readVarUInt64 b p1
        let ln := lenU.toNat
        if p2 + ln > b.size then throw "ORC Type: bad field name"
        else
          let slice := b.extract p2 (p2 + ln)
          match String.fromUTF8? slice with
          | none => throw "ORC Type: invalid UTF-8 field name"
          | some s => go (p2 + ln) kind subs (names ++ [s])
      else if w == 2 && fn == 2 then
        let (lenU, p2) ← readVarUInt64 b p1
        let ln := lenU.toNat
        if p2 + ln > b.size then throw "ORC Type: bad packed subtypes"
        else
          let rec readPacked (p : Nat) (acc : List Nat) : P (List Nat) :=
            if p ≥ p2 + ln then pure acc
            else do
              let (v, p') ← readVarUInt64 b p
              readPacked p' (acc ++ [v.toNat])
          let packed ← readPacked p2 []
          go (p2 + ln) kind (subs ++ packed) names
      else do
        let p2 ← skipFieldGroupAware b p1 w
        go p2 kind subs names
  go 0 none [] []

def parseAllTypes (footerPlain : ByteArray) : P (Array OrcTypeParsed) := do
  let blobs ← collectTypeBlobs footerPlain
  let mut out : Array OrcTypeParsed := #[]
  for blob in blobs do
    let t ← parseTypeBlob blob
    out := out.push t
  pure out

/-- Map top-level struct field name → ORC column id (type index of the child). -/
def columnNameToId (types : Array OrcTypeParsed) (want : String) : Option Nat :=
  if types.isEmpty then none
  else
    let root := types[0]!
    (root.fieldNames.zip root.subtypes).find? (fun (n, _) => n == want) |>.map Prod.snd

end Columnar.Orc.TypeParse
