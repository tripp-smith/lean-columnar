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

/-- `DataPageHeaderV2` from `parquet.thrift` (levels use RLE without u32 length prefix; see format spec). -/
structure DataPageHeaderV2 where
  numValues : Nat
  numNulls : Nat
  numRows : Nat
  encoding : Nat
  definitionLevelsByteLength : Nat
  repetitionLevelsByteLength : Nat
  /-- When true, the values subsection is compressed with the column chunk codec (after page-level decompress). -/
  isCompressed : Bool
  deriving Repr

structure PageHeaderParsed where
  pageType : Nat
  uncompressedSize : Nat
  compressedSize : Nat
  dataV1 : Option DataPageHeaderV1
  dataV2 : Option DataPageHeaderV2
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

def parseDataPageHeaderV2 (tv : Thrift.TValue) : P DataPageHeaderV2 := do
  let fields ←
    match tv with
    | .tstruct fs => pure fs
    | _ => throw "DataPageHeader v2: struct expected"
  let nv ← expectI32 (← match thriftField fields 1 with | some v => pure v | none => throw "v2 nv")
  let nn ← expectI32 (← match thriftField fields 2 with | some v => pure v | none => throw "v2 num_nulls")
  let nr ← expectI32 (← match thriftField fields 3 with | some v => pure v | none => throw "v2 num_rows")
  let enc ← expectI32 (← match thriftField fields 4 with | some v => pure v | none => throw "v2 enc")
  let dlen ← expectI32 (← match thriftField fields 5 with | some v => pure v | none => throw "v2 def len")
  let rlen ← expectI32 (← match thriftField fields 6 with | some v => pure v | none => throw "v2 rep len")
  let isCmp ←
    match thriftField fields 7 with
    | none => pure true
    | some v => expectBool v
  return {
    numValues := int32ToNat nv
    numNulls := int32ToNat nn
    numRows := int32ToNat nr
    encoding := int32ToNat enc
    definitionLevelsByteLength := int32ToNat dlen
    repetitionLevelsByteLength := int32ToNat rlen
    isCompressed := isCmp
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
  let mut dataV2 : Option DataPageHeaderV2 := none
  let mut dictPage := false
  if pageType == PageType.dataPage then
    let dph ← match thriftField fields 5 with | some v => parseDataPageHeaderV1 v | none => throw "data_page_header"
    dataV1 := some dph
  else if pageType == PageType.dataPageV2 then
    let dph ← match thriftField fields 8 with | some v => parseDataPageHeaderV2 v | none => throw "data_page_header_v2"
    dataV2 := some dph
  else if pageType == PageType.dictionaryPage then
    dictPage := true
  return ({
    pageType := pageType
    uncompressedSize := int32ToNat unc
    compressedSize := int32ToNat cmp
    dataV1 := dataV1
    dataV2 := dataV2
    dictPage := dictPage
  }, tr.pos)

end Columnar.Parquet
