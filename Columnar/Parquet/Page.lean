import Init.Data.ByteArray
import Columnar.Core.Result
import Columnar.Thrift.Compact
import Columnar.Parquet.Types
import Columnar.Parquet.Metadata

open Columnar

namespace Columnar.Parquet

structure DataPageHeaderV1 where
  numValues : Nat
  encoding : Nat
  defLevelEncoding : Nat
  repLevelEncoding : Nat
  deriving Repr

structure PageHeaderParsed where
  pageType : Nat
  uncompressedSize : Nat
  compressedSize : Nat
  dataV1 : Option DataPageHeaderV1
  dictPage : Bool
  deriving Repr

def parseDataPageHeaderV1 (tv : Thrift.TValue) : P DataPageHeaderV1 := do
  let fields ←
    match tv with
    | .tstruct fs => pure fs
    | _ => throw "DataPageHeader v1"
  let nv ← expectI32 (← match thriftField fields 1 with | some v => pure v | none => throw "nv")
  let enc ← expectI32 (← match thriftField fields 2 with | some v => pure v | none => throw "enc")
  let de ← expectI32 (← match thriftField fields 3 with | some v => pure v | none => throw "defEnc")
  let re ← expectI32 (← match thriftField fields 4 with | some v => pure v | none => throw "repEnc")
  return {
    numValues := int32ToNat nv
    encoding := int32ToNat enc
    defLevelEncoding := int32ToNat de
    repLevelEncoding := int32ToNat re
  }

def parsePageHeader (b : ByteArray) (off : Nat) : P (PageHeaderParsed × Nat) := do
  if off >= b.size then throw "page header OOB"
  let tr : Thrift.TReader := { bytes := b, pos := off }
  let (root, tr) ← Thrift.readTValue 12 tr
  let fields ←
    match root with
    | .tstruct fs => pure fs
    | _ => throw "PageHeader root"
  let ty ← expectI32 (← match thriftField fields 1 with | some v => pure v | none => throw "type")
  let unc ← expectI32 (← match thriftField fields 2 with | some v => pure v | none => throw "uncompressed")
  let cmp ← expectI32 (← match thriftField fields 3 with | some v => pure v | none => throw "compressed")
  let pageType := int32ToNat ty
  let mut dataV1 : Option DataPageHeaderV1 := none
  let mut dictPage := false
  if pageType == PageType.dataPage then
    let dph ← match thriftField fields 5 with | some v => parseDataPageHeaderV1 v | none => throw "data_page_header"
    dataV1 := some dph
  else if pageType == PageType.dictionaryPage then
    dictPage := true
  return ({
    pageType := pageType
    uncompressedSize := int32ToNat unc
    compressedSize := int32ToNat cmp
    dataV1 := dataV1
    dictPage := dictPage
  }, tr.pos)

end Columnar.Parquet
