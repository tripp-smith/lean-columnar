import Init.Data.ByteArray
import Columnar.Core.Result
import Columnar.Parquet.Types
import Columnar.Parquet.Encoding.Plain

namespace Columnar.Parquet.Encoding.ByteStreamSplit

abbrev P := Except String

open Plain

private def gather (b : ByteArray) (base off count idx : Nat) : UInt8 :=
  let pos := base + off * count + idx
  if h : pos < b.size then b.get pos h else 0

private def blobForElem (b : ByteArray) (base elemCount elemIdx width : Nat) : ByteArray :=
  Id.run do
    let mut acc := ByteArray.empty
    for off in [:width] do
      acc := acc.push (gather b base off elemCount elemIdx)
    return acc

/-- Decode BYTE_STREAM_SPLIT payload (`Encodings.md` §BYTESTREAMSPLIT). -/
def decodePhys (phys : Nat) (b : ByteArray) (start : Nat) (elemCount : Nat) : P (Array PlainValue) := do
  let width := physWidth phys
  if elemCount * width + start > b.size then throw "BYTE_STREAM_SPLIT: truncated payload"
  let mut acc : Array PlainValue := #[]
  for i in [:elemCount] do
    let blob := blobForElem b start elemCount i width
    let (pv, _) ← decodeOne phys blob 0
    acc := acc.push pv
  pure acc

end Columnar.Parquet.Encoding.ByteStreamSplit
