import Init.Data.ByteArray
import Columnar.Orc.Protobuf

namespace Columnar.Orc.FooterProto

open Columnar.Orc.Protobuf

abbrev P := Except String

/-- Skip protobuf group started with wire type 3; ends at wire type 4 with same field number. -/
partial def skipGroup (b : ByteArray) (pos : Nat) (groupField : Nat) : P Nat :=
  let rec loop (p : Nat) : P Nat :=
    if p ≥ b.size then throw "ORC footer: unclosed group"
    else do
      let (tag, p1) ← readTag b p
      let w := wireType tag
      let fn := fieldNumber tag
      if w == 4 && fn == groupField then pure p1
      else if w == 3 then
        let p2 ← skipGroup b p1 fn
        loop p2
      else do
        let p2 ← skipField b p1 w
        loop p2
  loop pos

partial def skipFieldGroupAware (b : ByteArray) (pos : Nat) (wire : Nat) : P Nat :=
  match wire with
  | 3 => do
    let (tag, p1) ← readTag b pos
    skipGroup b p1 (fieldNumber tag)
  | 4 => do
    let (_, p1) ← readTag b pos
    pure p1
  | _ => skipField b pos wire

partial def collectDelimitedField (b : ByteArray) (pos : Nat) (endPos : Nat) (wantField : Nat)
    (acc : List ByteArray) : P (List ByteArray) :=
  if pos ≥ endPos then pure acc.reverse
  else do
    let (tag, p1) ← readTag b pos
    let w := wireType tag
    let fn := fieldNumber tag
    if fn == wantField && w == 2 then
      let (lenU, p2) ← readVarUInt64 b p1
      let ln := lenU.toNat
      if p2 + ln > endPos then throw "ORC footer: delimited OOB"
      else
        let blob := b.extract p2 (p2 + ln)
        collectDelimitedField b (p2 + ln) endPos wantField (blob :: acc)
    else do
      let p2 ← skipFieldGroupAware b p1 w
      collectDelimitedField b p2 endPos wantField acc
  termination_by pos endPos acc => endPos - pos

def collectTypeBlobs (footer : ByteArray) : P (List ByteArray) :=
  collectDelimitedField footer 0 footer.size 4 []

/-- `StripeInformation` blobs in the file footer (field 3). -/
def collectStripeBlobs (footer : ByteArray) : P (List ByteArray) :=
  collectDelimitedField footer 0 footer.size 3 []

/-- `Stream` blobs in a stripe footer (field 1). -/
def collectStreamBlobs (stripeFooter : ByteArray) : P (List ByteArray) :=
  collectDelimitedField stripeFooter 0 stripeFooter.size 1 []

partial def findFooterVarint (footer : ByteArray) (wantField : Nat) : P Nat :=
  let rec walk (pos : Nat) : P Nat :=
    if pos ≥ footer.size then throw "ORC footer: varint field not found"
    else do
      let (tag, p1) ← readTag footer pos
      let w := wireType tag
      let fn := fieldNumber tag
      if fn == wantField && w == 0 then
        let (v, _) ← readVarUInt64 footer p1
        pure v.toNat
      else do
        let p2 ← skipFieldGroupAware footer p1 w
        walk p2
  walk 0

end Columnar.Orc.FooterProto
