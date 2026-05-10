import Columnar.Thrift.CompactWriter
import Columnar.Parquet.Types

namespace Columnar.Parquet.Writer.Page

open Columnar.Thrift

/-- `DataPageHeader` v1 Thrift compact (includes STOP). -/
def serializeDataPageHeaderV1 (numValues encoding defLevelEnc repLevelEnc : Nat) : ByteArray :=
  let (l1, h1) := writeFieldBegin (0 : Int32) 1 ctI32
  let s1 := h1 ++ writeZigZag32 (Int32.ofNat numValues)
  let (l2, h2) := writeFieldBegin l1 2 ctI32
  let s2 := h2 ++ writeZigZag32 (Int32.ofNat encoding)
  let (l3, h3) := writeFieldBegin l2 3 ctI32
  let s3 := h3 ++ writeZigZag32 (Int32.ofNat defLevelEnc)
  let (_, h4) := writeFieldBegin l3 4 ctI32
  let s4 := h4 ++ writeZigZag32 (Int32.ofNat repLevelEnc)
  s1 ++ s2 ++ s3 ++ s4 ++ writeFieldStop

/-- `PageHeader` for a v1 data page (`uncompressedPageSize` / `compressedPageSize` are page **body** sizes). -/
def serializePageHeader (uncompressedPageSize compressedPageSize : Nat) (dphInner : ByteArray) : ByteArray :=
  let (l1, h1) := writeFieldBegin (0 : Int32) 1 ctI32
  let s1 := h1 ++ writeZigZag32 (Int32.ofNat PageType.dataPage)
  let (l2, h2) := writeFieldBegin l1 2 ctI32
  let s2 := h2 ++ writeZigZag32 (Int32.ofNat uncompressedPageSize)
  let (l3, h3) := writeFieldBegin l2 3 ctI32
  let s3 := h3 ++ writeZigZag32 (Int32.ofNat compressedPageSize)
  let (_, h5) := writeFieldBegin l3 5 ctStruct
  s1 ++ s2 ++ s3 ++ h5 ++ dphInner ++ writeFieldStop

end Columnar.Parquet.Writer.Page
