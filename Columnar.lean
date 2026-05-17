import Columnar.Core.Result
import Columnar.Core.Bytes
import Columnar.Core.Bits
import Columnar.Core.MMap
import Columnar.Thrift.Compact
import Columnar.Thrift.CompactWriter
import Columnar.Compression.Codec
import Columnar.Compression.Snappy
import Columnar.Compression.Zstd
import Columnar.Compression.Gzip
import Columnar.Compression.Brotli
import Columnar.Compression.Lz4Raw
import Columnar.Parquet.Types
import Columnar.Parquet.Metadata
import Columnar.Parquet.Page
import Columnar.Parquet.Encoding.Plain
import Columnar.Parquet.Encoding.Rle
import Columnar.Parquet.Encoding.Dictionary
import Columnar.Parquet.Encoding.Delta
import Columnar.Parquet.Encoding.ByteStreamSplit
import Columnar.Parquet.Encoding.Levels
import Columnar.Parquet.Reader
import Columnar.Parquet.Stream
import Columnar.Parquet.Filter
import Columnar.Parquet.Writer
import Columnar.Parquet.Proofs
import Columnar.Avro.Schema
import Columnar.Avro.Binary
import Columnar.Avro.Container
import Columnar.Avro.Resolution
import Columnar.Orc.Protobuf
import Columnar.Orc.Schema
import Columnar.Orc.Reader
import Columnar.Orc.Writer
import Columnar.Arrow.Flatbuf
import Columnar.Arrow.IPC
import Columnar.Table
import Columnar.Table.PlainViews
import Columnar.SciLean.Tensor

/-- Read a Parquet file into a columnar `Table`. -/
abbrev readParquet := Columnar.Parquet.Reader.readParquet

abbrev readParquetFromBytes := Columnar.Parquet.Reader.readParquetFromBytes

abbrev readParquetMmap := Columnar.Parquet.Reader.readParquetMmap

abbrev openParquetFile := Columnar.Parquet.Reader.openParquetFile

abbrev ParquetFile := Columnar.Parquet.Reader.ParquetFile

abbrev ParquetFile.dispose := Columnar.Parquet.Reader.ParquetFile.dispose

abbrev streamRowGroups := Columnar.Parquet.Stream.streamRowGroups

abbrev RowGroupDecodeStream := Columnar.Parquet.Reader.RowGroupDecodeStream

abbrev RowGroupDecodeStream.nextDecoded := Columnar.Parquet.Reader.RowGroupDecodeStream.nextDecoded

abbrev readParquetRowGroup := Columnar.Parquet.Reader.readParquetRowGroup

abbrev readParquetRowGroupFromBytes := Columnar.Parquet.Reader.readParquetRowGroupFromBytes

abbrev readParquetAllRowGroups := Columnar.Parquet.Reader.readParquetAllRowGroups

abbrev readParquetAllRowGroupsFromBytes := Columnar.Parquet.Reader.readParquetAllRowGroupsFromBytes

abbrev readTableForRowGroup := Columnar.Parquet.Reader.readTableForRowGroup

abbrev appendTableRows := Columnar.Table.appendRows

abbrev sliceTableRows := Columnar.Table.sliceRows

abbrev plainInt64PackedBytes? := Columnar.Table.Column.plainInt64PackedBytes?

abbrev plainInt64PackedSubarray? := Columnar.Table.Column.plainInt64PackedSubarray?

abbrev plainInt32PackedBytes? := Columnar.Table.Column.plainInt32PackedBytes?

abbrev plainInt32PackedSubarray? := Columnar.Table.Column.plainInt32PackedSubarray?

abbrev writeParquet := Columnar.Parquet.Writer.writeParquet

abbrev writeParquetBytes := Columnar.Parquet.Writer.writeParquetBytes

abbrev readAvroOcf := Columnar.Avro.Container.readAvroOcf

abbrev readAvroOcfFromBytes := Columnar.Avro.Container.readAvroOcfFromBytes

abbrev readOrcNumberOfRows := Columnar.Orc.Reader.readOrcNumberOfRows

abbrev ipcStreamMessageCount := Columnar.Arrow.IPC.ipcStreamMessageCount

abbrev readArrowIpcStreamFile := Columnar.Arrow.IPC.readArrowIpcStreamFile
abbrev readArrowIpcFile := Columnar.Arrow.IPC.readArrowIpcFile

abbrev readOrcPrimitives := Columnar.Orc.Reader.readOrcPrimitives
