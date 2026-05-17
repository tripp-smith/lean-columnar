# Conformance

Official Apache corpora are tracked under `vendor/` (submodules or `scripts/fetch-fixtures.sh`).

Repository fixtures:

- `Tests/goldens/*.txt` — value sidecars for parquet-testing columns (regenerate via `scripts/export_parquet_goldens.py` after fetching vendor).
- `Tests/fixtures/interop_minimal.avro` / `interop_minimal_snappy.avro` — tiny Avro OCF (null / Snappy blocks) for Lean decode (`scripts/export_interop_goldens.py`); goldens `interop_*` under `Tests/goldens/`.
- `Tests/fixtures/interop_orc_int32.orc` — single-stripe uncompressed ORC with one `int32` column (for `readOrcPrimitives`).
- `Tests/fixtures/interop_arrow_int32_stream.arrow` — Arrow IPC **stream** (`readArrowIpcStreamFile`).
- `Tests/fixtures/interop_arrow_int32_file.arrow` — Arrow IPC **file** (`readArrowIpcFile`).
- Vendor-gated: `vendor/orc/examples/TestOrcFile.test1.orc` (`int1`, `boolean1` goldens), `vendor/avro/.../simple/data.avro` (`text` golden).
- `Tests/fixtures/two_row_groups_plain.parquet` — two uncompressed row groups for stream metadata tests (`scripts/gen_two_row_fixture.py`).
- `Tests/fixtures/codecs/*` — tiny plaintext + per-codec compressed blobs for `Codec.decompress` (`scripts/gen_codec_contract_fixtures.py`).

## Automation

- `lake exe tests` — unit checks; codec FFI contract (`Tests/Unit/CodecContract`); Parquet suites (see macOS note); **interop** Avro (null, Snappy, vendor simple), ORC (footer rows, `test1` columns, int32 fixture), Arrow IPC (vendor message count, stream + file decode), plus vendor fingerprints. Interop groups run **before** Parquet mmap/stream; Arrow IPC runs **before** ORC zlib on macOS.
- `python3 scripts/parquet_roundtrip_smoke.py` — canonical `writeParquet` × pyarrow verify (needs pyarrow).
- `bash scripts/export_parquet_goldens.py` — refreshes Parquet golden sidecars from `vendor/parquet-testing/data`.
- `python3 scripts/export_interop_goldens.py` — regenerates checked-in Avro / ORC / Arrow interop fixtures and `Tests/goldens/interop_*` sidecars (`pip install fastavro pyarrow`). Snappy Avro and zlib ORC paths need native codecs when exercising those checks (see [`docs/FFI.md`](./FFI.md)); tests **SKIP** with an informative message when decompression is unavailable.
- `bash scripts/gen-conformance-report.sh` — writes `docs/conformance-report.json` (stub grid).

## Codec / conformance CI matrix

| Job / setting | Native codecs | Expectation |
|---------------|-----------------|---------------|
| Default `lake build` / job `build` + `conformance-parquet` | C stubs only (`COLUMNAR_CODEC` unset; no `-Kcolumnar.codec`) | Snappy/Zstd/Brotli/etc. parquet files SKIP in Phase‑0 smoke; FFI returns clear error strings. |
| Workflow job `conformance-parquet-native-codecs` (Ubuntu) | `bash scripts/fetch-fixtures.sh`; `lake clean`; `COLUMNAR_CODEC=1`; `lake build -Kcolumnar.codec=1`; `lake exe tests -Kcolumnar.codec=1` with `COLUMNAR_INTEROP_STRICT=1` | Native codecs + full interop (Snappy Avro and zlib ORC footer must not SKIP). `COLUMNAR_ENCODING_TIER_STRICT=1` for Phase‑1. |
| Workflow job `scilean-bridge` (Ubuntu) | `libopenblas-dev`; `COLUMNAR_SCILEAN=1 lake update`, then `lake build -Kcolumnar.scilean=1 ColumnarSciLean` and `lake exe scilean_tests -Kcolumnar.scilean=1` | Optional SciLean + LeanBLAS stack; see [`README.md`](../README.md) and `scripts/with_scilean.sh`. |

Parquet-encoding tiers (Phase‑1 harness):

| Env | Behaviour |
|-----|-----------|
| default | `mustDecode` regressions print `SKIP mustDecode SOFT` (non-zero exit still only on hard Harness failures). |
| `COLUMNAR_ENCODING_TIER_STRICT=1` | `mustDecode` files fail the job if decoding errors. |

## Environment flags

| Variable | Effect |
|----------|--------|
| `COLUMNAR_CODEC=1` | Compile `columnar_codec.c` with system headers; set when building/testing native codecs (`scripts/with_native_codecs.sh` exports it). |
| (Lake) `-Kcolumnar.codec=1` | Pass to `lake build` / `lake exe` alongside `COLUMNAR_CODEC=1`; links codec libs on `tests` (see `lakefile.lean`). |
| `COLUMNAR_INTEROP_STRICT=1` | Interop harness: codec-related SKIP (e.g. Snappy Avro, zlib ORC footer) becomes **FAIL** (used on CI native-codecs job). |
| `COLUMNAR_PHASE0_STRICT=1` | Require every Phase-0 Parquet file to pass (not only `mustPass`). |
| `COLUMNAR_ENCODING_TIER_STRICT=1` | Phase‑1 manifest `mustDecode` entries fail on decode errors. |
| `COLUMNAR_PHASE1_EXPLORE=1` | Run Phase‑1 optional `explore` parquet files (delta / page‑v2 samples). Default is **off** so `lake exe tests` stays stable; enable locally or in dedicated jobs when investigating reader coverage. |
| `COLUMNAR_DECODE_LIST_COLUMNS=1` | Nested conformance: run full `readParquet` on `list_columns.parquet` (default skips full decode to avoid unstable paths). |
| `COLUMNAR_PARQUET_READER_OSX=1` | **macOS only:** run Parquet-heavy conformance (goldens, mmap, Phase‑0/1, nested/stream smoke, writer round-trip). Default on macOS is **SKIP** those groups (SIGSEGV in the Parquet reader binary on some builds); CI Linux runs them unchanged. |
| `COLUMNAR_BENCH_QUICK=1` | `lake exe bench` uses fewer iterations. |
| `COLUMNAR_BENCH_ITERS=N` | Override bench iteration count. |
| `COLUMNAR_BENCH_FILE` | Parquet path for `parquet_binary` / `parquet_mmap` bench workloads. |
| `COLUMNAR_BENCH_MMAP=1` | Include `parquet_mmap` in bench registry. |
| `COLUMNAR_BENCH_LARGE=1` | Default 1 iteration when `COLUMNAR_BENCH_ITERS` unset. |
| `COLUMNAR_BENCH_SKIP_REFERENCE=1` | Lean-only bench timings. |
| `COLUMNAR_BENCH_WORKLOADS=id1,id2` | Bench subset (`parquet_binary`, `avro_minimal`, …). |
| `BENCH_BASELINE_JSON` | Baseline for `scripts/check_bench_regression.sh`. |
| `BENCH_MAX_REGRESSION_PCT` | Regression threshold (default 25). |
| `BENCH_WORKLOAD_IDS` | Optional filter for regression compare. |
| Writer demo | `COLUMNAR_WRITER_PATH`, optional `COLUMNAR_WRITER_SCHEMA`, `COLUMNAR_WRITER_ROWS` for `lake exe writer_roundtrip`. |

## Benchmark artifacts

- **Output:** `bench/results/last-quick.json` — `schema_version`, `git_sha`, `columnar_codec_build`, `workloads[]` with `lean_mean_ms` / `reference_mean_ms`.
- **Registry paths:** `vendor/parquet-testing/data/binary.parquet` (vendor); `Tests/fixtures/interop_minimal.avro`, `interop_minimal_snappy.avro`, `interop_orc_int32.orc`, `interop_arrow_int32_stream.arrow`, `interop_arrow_int32_file.arrow` (checked-in). `vendor/orc/examples/TestOrcFile.test1.orc` is conformance-only (not in quick bench).
- **Baseline:** `bash scripts/capture_bench_baseline.sh` → `bench/results/baseline-quick.json` (optional commit).
- **Regression:** `BENCH_BASELINE_JSON=bench/results/baseline-quick.json bash scripts/check_bench_regression.sh` (maintainers; PR CI does not fail on missing baseline).

### Nightly benchmarks (optional)

Manual or scheduled jobs: `COLUMNAR_BENCH_LARGE=1`, `scripts/bench_large_mmap.sh`, multi-GB `COLUMNAR_BENCH_FILE`, artifact retention — not wired to default PR CI.

## SciLean

The default manifest has **no** SciLean packages (`lake-manifest.json` ships with `"packages": []`). To resolve SciLean + Mathlib transitively, run `COLUMNAR_SCILEAN=1 lake update` (Lake `meta if` cannot read `-K` flags when deciding whether to `require` SciLean). Link OpenBLAS via `-Kcolumnar.scilean=1` on `lake build` / `lake exe`; **`scripts/with_scilean.sh`** sets `COLUMNAR_SCILEAN` and forwards `-Kcolumnar.scilean=1`.

`Columnar.SciLean.TensorBridge` stays SciLean‑free; real conversions live in `Columnar.SciLean.Convert` behind `ColumnarSciLean`. Smoke tests: `Tests/Unit/SciLeanBridge.lean` (always on); `lake exe scilean_tests` when the optional library is built.

## CI

GitHub Actions:

| Job | Bench / artifacts |
|-----|-------------------|
| **`build`** (matrix OS) | `pip install pyarrow fastavro` on Ubuntu before `COLUMNAR_BENCH_QUICK=1 lake exe bench`; uploads `bench/results/last-quick.json` with conformance report. |
| **`conformance-parquet`** | `lake exe tests` + writer smoke (no bench gate). |
| **`conformance-parquet-native-codecs`** | Native codecs + `COLUMNAR_INTEROP_STRICT=1`. |
| **`scilean-bridge`** | Optional SciLean stack. |

See [`docs/Manual.md`](./Manual.md) and [`docs/FFI.md`](./FFI.md) for bench env flags and native link model.
