# lean-columnar

High-performance, zero-copy-oriented columnar formats for **Lean 4**: Parquet **reader** and
**writer** (flat tables) with **optional native decompression** (Snappy, Zstd, gzip/zlib, Brotli,
LZ4_RAW) when system libs are linked; broader Parquet/spec coverage is still in flight.

**Interop readers:** Avro **OCF** (`readAvroOcf`, null / deflate / Snappy blocks), ORC **footer** row count (`readOrcNumberOfRows`) plus **primitive** single-stripe decode (`readOrcPrimitives` for the checked-in int32 fixture), and Arrow IPC **stream** walk (`ipcStreamMessageCount`) plus **RecordBatch → `Table`** (`readArrowIpcStreamFile`). Vendor-gated conformance plus checked-in interop fixtures; see [`plans/completed/06_interop-avro-orc-arrow-readers.md`](plans/completed/06_interop-avro-orc-arrow-readers.md), [`docs/Conformance.md`](docs/Conformance.md), and [`spec.md`](spec.md).

## Quick start

```bash
lake build
lake exe tests
COLUMNAR_BENCH_QUICK=1 lake exe bench
```

Optional Apache reference data:

```bash
bash scripts/fetch-fixtures.sh   # or: git submodule update --init
```

Optional **native codecs** (off by default): see [`docs/FFI.md`](docs/FFI.md), or run
`bash scripts/with_native_codecs.sh exe tests` after installing the `-dev`/Homebrew packages listed there.

Optional **SciLean / OpenBLAS** tensor bridge (off by default): install OpenBLAS (`libopenblas-dev` on Ubuntu; `brew install openblas` on macOS), then resolve deps and link with the wrapper that sets both `COLUMNAR_SCILEAN` (Lake `meta if` guard for the SciLean `require`) and `-Kcolumnar.scilean=1` (linker flags):

```bash
bash scripts/with_scilean.sh update              # or: COLUMNAR_SCILEAN=1 lake update
bash scripts/with_scilean.sh build ColumnarSciLean
bash scripts/with_scilean.sh exe scilean_tests
```

## Docs

- [`docs/Manual.md`](docs/Manual.md) — usage, mmap/streaming API, bench flags  
- [`docs/FFI.md`](docs/FFI.md) — native codec + mmap C build  
- [`docs/Conformance.md`](docs/Conformance.md) — test corpora and CI  

## Status

Parquet **reader** and **writer** (flat schemas, PLAIN + RLE levels, multiple row groups, multi-RG
read) are in place; see [`plans/completed/01_parquet-reader-full-coverage.md`](plans/completed/01_parquet-reader-full-coverage.md) and
[`plans/completed/02_parquet-writer-and-roundtrip.md`](plans/completed/02_parquet-writer-and-roundtrip.md). **Compression FFI** (stubs by
default, native decompress when enabled) is described in
[`plans/completed/03_compression-codecs-and-io-policy.md`](plans/completed/03_compression-codecs-and-io-policy.md) and
[`docs/FFI.md`](docs/FFI.md).

**POSIX mmap** (`readParquetMmap`, `openParquetFile`, `streamRowGroups`) and optional **packed primitive column views** (`plainInt64PackedBytes?`, etc.) are described in
[`plans/completed/04_memory-map-zero-copy-api.md`](plans/completed/04_memory-map-zero-copy-api.md) and
[`docs/Manual.md`](docs/Manual.md) (lifetimes, macOS opt-in `COLUMNAR_FORCE_MMAP=1`, WASM limits, large-file bench script `scripts/bench_large_mmap.sh`). Optional **SciLean** tensor export (`Columnar.SciLean.Convert`, `lake exe scilean_tests`) is summarized in [`plans/completed/05_scilean-bridge-and-schema-proofs.md`](plans/completed/05_scilean-bridge-and-schema-proofs.md). **Avro / ORC / Arrow IPC** readers (including Snappy Avro, ORC stripe primitives on the interop file, and Arrow stream decode) are summarized in [`plans/completed/06_interop-avro-orc-arrow-readers.md`](plans/completed/06_interop-avro-orc-arrow-readers.md).
