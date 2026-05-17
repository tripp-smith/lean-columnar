# LeanColumnar manual

## Getting started

1. Install [Elan](https://github.com/leanprover/elan) and check out this repo.
2. `lake build` — builds the `Columnar` library (native codec object is **stubbed by default**).
3. `lake exe tests` — unit tests + optional Parquet conformance when `vendor/parquet-testing` exists.
4. `COLUMNAR_BENCH_QUICK=1 lake exe bench` — writes `bench/results/last-quick.json` (see **Benchmarks** below).

## Vendored fixtures

Either add git submodules (see `.gitmodules`) or run:

```bash
bash scripts/fetch-fixtures.sh
```

## Parquet Phase-0 CI gate

With fixtures present, `int32_decimal.parquet` and `int64_decimal.parquet` must decode successfully.
Other Phase-0 files from the plan are attempted; failures are reported as **SKIP** unless
`COLUMNAR_PHASE0_STRICT=1` is set.

## Native codecs

See [FFI.md](FFI.md). Set `COLUMNAR_CODEC=1` when building and pass **`lake -Kcolumnar.codec=1`** so
the package links system libs, or use `bash scripts/with_native_codecs.sh exe tests` / `build bench`.
Interop strict mode: `COLUMNAR_INTEROP_STRICT=1` (see [Conformance.md](Conformance.md)).

**Test order:** `lake exe tests` runs the codec FFI contract **last**, after Parquet conformance.
On some setups, linking real Snappy/Zstd/… and exercising them before other tests has been
observed to destabilize the same process; scheduling codec checks last avoids that.

## SciLean (optional)

Tensor export lives in `ColumnarSciLean` (`Columnar.SciLean.Convert`) behind Lake `meta if` guards. The default build has no SciLean dependency.

| Variable / flag | Effect |
|-----------------|--------|
| `COLUMNAR_SCILEAN=1` | `lake update` resolves SciLean + Mathlib (`scripts/with_scilean.sh`). |
| `-Kcolumnar.scilean=1` | Link OpenBLAS on `lake build` / `lake exe` for `ColumnarSciLean` and `scilean_tests`. |

```bash
bash scripts/with_scilean.sh update
bash scripts/with_scilean.sh build ColumnarSciLean
bash scripts/with_scilean.sh exe scilean_tests
```

Install OpenBLAS (`libopenblas-dev` on Ubuntu; `brew install openblas` on macOS). See [Conformance.md](Conformance.md) §SciLean and [`plans/completed/05_scilean-bridge-and-schema-proofs.md`](../plans/completed/05_scilean-bridge-and-schema-proofs.md).

## Memory mapping (`mmap`)

POSIX `mmap` is implemented in `c/columnar_codec.c` (same static archive as codec shims) and
surfaced through `Columnar.Core.MMap` / `Columnar.Core.ParquetBacking`.

- **`mmapSupported`:** `Columnar.mmapSupported` is `true` on POSIX desktop targets; it is `false`
  on WASM / non-Unix stubs.
- **macOS default:** `Columnar.Core.MMap.mmapOpenTry` does **not** call into native mmap unless
  `COLUMNAR_FORCE_MMAP=1` is set. The same Lean process has shown post-mmap heap corruption in later
  test groups on some macOS / Lean combinations; Linux CI keeps mmap enabled without this guard.
  Use `COLUMNAR_DISABLE_MMAP=1` on any host to force the `readBinFile` fallback without touching the
  mmap helpers.
- **`openParquetFile`:** When mmap open succeeds (non-macOS by default, or macOS with
  `COLUMNAR_FORCE_MMAP=1`), the footer is read via bounded `copyRange` slices and the returned
  `ParquetFile` keeps **`ParquetBacking.ofMmap`** until `dispose`. Column and page decode use
  mmap-backed **`copyRange`** windows (compressed pages are still decompressed into owned
  `ByteArray`s). If mmap is unavailable or fails, `IO.FS.readBinFile` supplies an in-memory
  `ByteArray` backing instead.
- **Lifetime:** Call `ParquetFile.dispose` when finished so **`MmapRegion.close`** runs for mmap
  backings; it is a no-op for `ofByteArray`. APIs such as `readParquetMmap` use `try`/`finally`
  with `dispose`.
- **`streamRowGroups`:** `Columnar.Parquet.Stream.streamRowGroups` builds a
  `RowGroupDecodeStream` over an opened `ParquetFile`; pull row groups with
  `RowGroupDecodeStream.nextDecoded` until it returns `ok none`.
- **Materialization / packed views:** General decode still builds `Table` /
  `Array (Option PlainValue)` (nulls, dictionary indirection, nested dotted columns). For columns
  where **every** row is a non-null `PlainValue.int32` or `.int64`, helpers in
  [`Columnar/Table/PlainViews.lean`](Columnar/Table/PlainViews.lean) expose **`plainInt32PackedBytes?` /
  `plainInt64PackedBytes?`** and matching **`…PackedSubarray?`** (`Subarray UInt8` over dense
  little-endian runs). These pack from decoded cells (post-page-decompress), not directly from the
  mmap window.

### Troubleshooting mmap / heap crashes

Use the **`mmap_harness`** executable (not the full `lake exe tests` suite) under lldb so runs stay small and easy to time-limit:

```bash
lake build mmap_harness
COLUMNAR_FORCE_MMAP=1 lake exe mmap_harness -- --scenario ffi --file Tests/fixtures/two_row_groups_plain.parquet
COLUMNAR_FORCE_MMAP=1 lake exe mmap_harness -- --scenario open --file Tests/fixtures/two_row_groups_plain.parquet
lake exe mmap_harness -- --scenario compare    # needs vendor/parquet-testing `binary.parquet`
COLUMNAR_FORCE_MMAP=1 lake exe mmap_harness -- --scenario stream --file Tests/fixtures/two_row_groups_plain.parquet
```

- **Env:** `COLUMNAR_MMAP_SCENARIO` sets the default scenario if you omit `--scenario`. `COLUMNAR_DISABLE_MMAP=1` forces the `readBinFile` path. On **macOS**, `open` and `stream` require **`COLUMNAR_FORCE_MMAP=1`**; the **`ffi`** scenario also needs it for `mmapOpenTry` to call into the C shim.
- **Wrapper:** `scripts/run-mmap-harness.sh` — use `--force-mmap`, optional **`--lldb`** and **`--timeout`** (uses `timeout` or `gtimeout` when available) to avoid hung lldb sessions.
- **Linux:** For deeper checks, run `mmap_harness` under Valgrind or rebuild `columnar_codec_o` with AddressSanitizer (see plan notes in repo discussions); CI runs a fast **`ffi`** smoke on **macOS** only.

### Large-file benchmarks (RSS / wall-clock)

For multi-GB inputs, compare `readParquet` vs `readParquetMmap` and record wall-clock + RSS:

- **Input path:** set **`COLUMNAR_BENCH_FILE`** to your corpus (defaults to `vendor/parquet-testing/data/binary.parquet`).
- **Iterations:** use **`COLUMNAR_BENCH_LARGE=1`** to default to **one** iteration when `COLUMNAR_BENCH_ITERS` is unset (long runs).
- **Generator:** `bash scripts/bench_large_mmap.sh` writes a multi-row-group INT32 file via `lake exe writer_roundtrip`, then runs `lake exe bench` with **`COLUMNAR_BENCH_MMAP=1`**. Tune **`COLUMNAR_BENCH_GEN_ROWS`** / **`COLUMNAR_BENCH_GEN_RG`** for size on disk.
- **JSON:** `bench/results/last-quick.json` uses `schema_version` and a `workloads[]` array. When **`COLUMNAR_BENCH_MMAP=1`**, the registry includes a `parquet_mmap` entry (Lean `readParquetMmap` vs PyArrow `read_table` on the same bytes for wall-clock only).
- **RSS:** On Linux wrap the **same** bench invocation with **`/usr/bin/time -v`** and compare `Maximum resident set size`; on macOS use **`time -l`** or Instruments. Document hardware, cold vs warm page cache, and generation env vars alongside the JSON artifact.

## Benchmarks

`lake exe bench` runs every selected workload in the registry ([`Bench/Registry.lean`](../Bench/Registry.lean)), writes [`bench/results/last-quick.json`](../bench/results/last-quick.json), and optionally times PyArrow via [`scripts/bench_reference.py`](../scripts/bench_reference.py). See [`bench/README.md`](../bench/README.md).

| Variable | Effect |
|----------|--------|
| `COLUMNAR_BENCH_QUICK=1` | Fewer iterations (30 vs 40 default). |
| `COLUMNAR_BENCH_ITERS=N` | Override iteration count. |
| `COLUMNAR_BENCH_FILE` | Parquet path for `parquet_binary` and `parquet_mmap`. |
| `COLUMNAR_BENCH_MMAP=1` | Include `parquet_mmap` workload. |
| `COLUMNAR_BENCH_LARGE=1` | Default **1** iteration when `COLUMNAR_BENCH_ITERS` unset. |
| `COLUMNAR_BENCH_SKIP_REFERENCE=1` | Lean-only timings (no Python subprocess). |
| `COLUMNAR_BENCH_WORKLOADS=id1,id2` | Run a subset of registry ids. |

**Stub vs native:** default builds use stub codecs except zlib for ORC raw inflate (macOS may link SDK zlib only). Snappy workloads (`avro_snappy`) need `COLUMNAR_CODEC=1` and `bash scripts/with_native_codecs.sh build bench`. Run `lake clean` after toggling codec link mode before comparing numbers.

**Regression:** `bash scripts/capture_bench_baseline.sh` then `BENCH_BASELINE_JSON=bench/results/baseline-quick.json bash scripts/check_bench_regression.sh` (`BENCH_MAX_REGRESSION_PCT`, optional `BENCH_WORKLOAD_IDS`).

## Interop (Avro / ORC / Arrow)

Checked-in fixtures under `Tests/fixtures/interop_*` back conformance and bench. Regenerate goldens (not bench correctness):

```bash
python3 scripts/export_interop_goldens.py
```

Vendor paths (`vendor/avro`, `vendor/orc`, …) require `bash scripts/fetch-fixtures.sh`. **Do not** use `lake exe bench` for golden verification — use `lake exe tests`.

## macOS testing

- **`COLUMNAR_PARQUET_READER_OSX=1`:** run Parquet-heavy conformance (default on macOS skips those groups).
- **`COLUMNAR_FORCE_MMAP=1`:** opt in to native mmap on macOS for bench/harness.
- **`lake exe tests`:** interop runs before Parquet mmap groups; Arrow IPC runs before ORC zlib decode.

## Parquet read/write API (high level)

| Operation | Entry point |
|-----------|----------------|
| Read full file (row group 0 only) | `Columnar.Parquet.Reader.readParquet` |
| Same, mmap-first backing (unmap in `readParquetMmap`) | `Columnar.Parquet.Reader.readParquetMmap` |
| Open footer + backing (`dispose` when done) | `Columnar.Parquet.Reader.openParquetFile` |
| Read all row groups concatenated | `Columnar.Parquet.Reader.readParquetAllRowGroups` |
| Read one row group by index | `Columnar.Parquet.Reader.readParquetRowGroup` |
| Stream decoded row groups | `Columnar.Parquet.Stream.streamRowGroups` + `RowGroupDecodeStream.nextDecoded` |
| Metadata-only row group pull | `Columnar.Parquet.Stream.RowGroupStream` |
| Write file | `Columnar.Parquet.Writer.writeParquet` / `writeParquetBytes` |
| Writer options | `Columnar.Parquet.Writer.WriteOptions` — `rowsPerRowGroup` splits output into multiple Parquet row groups (plain encoding, uncompressed codec in the current release). |
| Row slice helper | `Columnar.Table.Table.sliceRows` |
| Packed INT32/INT64 runs (`Subarray UInt8`) | `Columnar.Table.Column.plainInt32PackedSubarray?`, `plainInt64PackedSubarray?` (all-non-null columns only; see [`Columnar/Table/PlainViews.lean`](Columnar/Table/PlainViews.lean)) |
| Avro OCF → Table | `Columnar.Avro.Container.readAvroOcf` / `readAvroOcfFromBytes` |
| ORC row count | `Columnar.Orc.Reader.readOrcNumberOfRows` |
| ORC primitive columns | `Columnar.Orc.Reader.readOrcPrimitives` (column name list) |
| Arrow IPC stream | `Columnar.Arrow.IPC.readArrowIpcStreamFile` |
| Arrow IPC file | `Columnar.Arrow.IPC.readArrowIpcFile` |
| Table → float tensor data (optional) | `Columnar.SciLean.Convert.tableToFloatDataArray` (requires `ColumnarSciLean`) |
| SciLean smoke tests | `lake exe scilean_tests` with `-Kcolumnar.scilean=1` |

## Roadmap

Implementation follows `spec.md` and the phased plan: Parquet → Avro → ORC → Arrow IPC, each gated
on Apache reference corpora.
