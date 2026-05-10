import Columnar.Parquet.Metadata
import Columnar.Parquet.Reader

namespace Columnar.Parquet.Stream

structure RowGroupStream where
  fileMeta : FileMetaDataParsed
  idx : Nat

def RowGroupStream.init (fileMeta : FileMetaDataParsed) : RowGroupStream := ⟨fileMeta, 0⟩

def RowGroupStream.next? (s : RowGroupStream) : Option (RowGroupParsed × RowGroupStream) :=
  if h : s.idx < s.fileMeta.rowGroups.size then
    some (s.fileMeta.rowGroups[s.idx]'h, { s with idx := s.idx + 1 })
  else none

private partial def countStreamedAux (pulls : Nat) (cur : RowGroupStream) (fuel : Nat) : Nat :=
  if fuel == 0 then pulls
  else
    match RowGroupStream.next? cur with
    | none => pulls
    | some (_, cur') => countStreamedAux (pulls + 1) cur' (fuel - 1)

/-- Count pulls from `next?` starting at `s` (bounded — corrupt footers might advertise huge RG counts). -/
def RowGroupStream.countStreamed (s : RowGroupStream) : Nat :=
  let cap := Nat.min (s.fileMeta.rowGroups.size + 1) 100001
  countStreamedAux 0 s cap

/-- Row-group decode stream over an opened `ParquetFile` (reuse `backing` until `ParquetFile.dispose`). -/
abbrev streamRowGroups (pf : Columnar.Parquet.Reader.ParquetFile) : Columnar.Parquet.Reader.RowGroupDecodeStream :=
  Columnar.Parquet.Reader.RowGroupDecodeStream.init pf.backing pf.fileMeta

end Columnar.Parquet.Stream
