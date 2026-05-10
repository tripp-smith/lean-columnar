# Conformance

Official Apache corpora are tracked under `vendor/` (submodules or `scripts/fetch-fixtures.sh`).

Repository fixtures:

- `Tests/goldens/*.txt` — value sidecars for parquet-testing columns (regenerate via `scripts/export_parquet_goldens.py` after fetching vendor).
- `Tests/fixtures/interop_minimal.avro` / `interop_minimal_snappy.avro` — tiny Avro OCF (null / Snappy blocks) for Lean decode (`scripts/export_interop_goldens.py`); goldens `interop_*` under `Tests/goldens/`.
- `Tests/fixtures/interop_orc_int32.orc` — single-stripe uncompressed ORC with one `int32` column (for `readOrcPrimitives`).
- `Tests/fixtures/interop_arrow_int32_stream.arrow` — Arrow IPC **stream** with schema + one RecordBatch (for `readArrowIpcStreamFile`).
- `Tests/fixtures/two_row_groups_plain.parquet` — two uncompressed row groups for stream metadata tests (`scripts/gen_two_row_fixture.py`).
- `Tests/fixtures/codecs/*` — tiny plaintext + per-codec compressed blobs for `Codec.decompress` (`scripts/gen_codec_contract_fixtures.py`).

## Automation

- `lake exe tests` — unit checks; codec FFI contract (`Tests/Unit/CodecContract`); Parquet goldens / Phase‑0 / Phase‑1 / mmap / stream suites (see macOS note below); **interop** Avro OCF (null + Snappy), ORC footer rows + primitive int32 fixture, Arrow IPC message walk + stream decode to `Table` (`Tests/Conformance/{Avro,Orc,Arrow}Interop.lean`), plus vendor fingerprints.
- `python3 scripts/parquet_roundtrip_smoke.py` — canonical `writeParquet` × pyarrow verify (needs pyarrow).
- `bash scripts/export_parquet_goldens.py` — refreshes Parquet golden sidecars from `vendor/parquet-testing/data`.
- `python3 scripts/export_interop_goldens.py` — regenerates checked-in Avro / ORC / Arrow interop fixtures and `Tests/goldens/interop_*` sidecars (`pip install fastavro pyarrow`). Snappy Avro and zlib ORC paths need native codecs when exercising those checks (see [`docs/FFI.md`](./FFI.md)); tests **SKIP** with an informative message when decompression is unavailable.
- `bash scripts/gen-conformance-report.sh` — writes `docs/conformance-report.json` (stub grid).

## Codec / conformance CI matrix

| Job / setting | Native codecs | Expectation |
|---------------|-----------------|---------------|
| Default `lake build` / job `build` + `conformance-parquet` | C stubs only (`COLUMNAR_CODEC` unset; no `-Kcolumnar.codec`) | Snappy/Zstd/Brotli/etc. parquet files SKIP in Phase‑0 smoke; FFI returns clear error strings. |
| Workflow job `conformance-parquet-native-codecs` (Ubuntu) | `COLUMNAR_CODEC=1` and `lake -Kcolumnar.codec=1` after installing `libsnappy-dev`, `libzstd-dev`, `zlib1g-dev`, `libbrotli-dev`, `liblz4-dev` | Native `Codec.decompress` contract + full `lake exe tests`; `COLUMNAR_ENCODING_TIER_STRICT=1` enforces Phase‑1 `mustDecode` without soft SKIP. |
| Workflow job `scilean-bridge` (Ubuntu) | `libopenblas-dev`; `COLUMNAR_SCILEAN=1 lake update`, then `lake build -Kcolumnar.scilean=1 ColumnarSciLean` and `lake exe scilean_tests -Kcolumnar.scilean=1` | Optional SciLean + LeanBLAS stack; see [`README.md`](../README.md) and `scripts/with_scilean.sh`. |

Parquet-encoding tiers (Phase‑1 harness):

| Env | Behaviour |
|-----|-----------|
| default | `mustDecode` regressions print `SKIP mustDecode SOFT` (non-zero exit still only on hard Harness failures). |
| `COLUMNAR_ENCODING_TIER_STRICT=1` | `mustDecode` files fail the job if decoding errors. |

## Environment flags

| Variable | Effect |
|----------|--------|
| `COLUMNAR_CODEC=1` | Compile C codec shims against system headers when Lake builds `columnar_codec.c`. |
| (Lake) `-Kcolumnar.codec=1` | Link `-lsnappy -lzstd -lz -lbrotlidec -llz4` via `package` `moreLinkArgs` (required together with `COLUMNAR_CODEC=1` for working native decompress). |
| `COLUMNAR_PHASE0_STRICT=1` | Require every Phase-0 Parquet file to pass (not only `mustPass`). |
| `COLUMNAR_ENCODING_TIER_STRICT=1` | Phase‑1 manifest `mustDecode` entries fail on decode errors. |
| `COLUMNAR_PHASE1_EXPLORE=1` | Run Phase‑1 optional `explore` parquet files (delta / page‑v2 samples). Default is **off** so `lake exe tests` stays stable; enable locally or in dedicated jobs when investigating reader coverage. |
| `COLUMNAR_DECODE_LIST_COLUMNS=1` | Nested conformance: run full `readParquet` on `list_columns.parquet` (default skips full decode to avoid unstable paths). |
| `COLUMNAR_PARQUET_READER_OSX=1` | **macOS only:** run Parquet-heavy conformance (goldens, mmap, Phase‑0/1, nested/stream smoke, writer round-trip). Default on macOS is **SKIP** those groups (SIGSEGV in the Parquet reader binary on some builds); CI Linux runs them unchanged. |
| `COLUMNAR_BENCH_QUICK=1` | `lake exe bench` uses fewer iterations (`Bench/Main`). |
| `COLUMNAR_BENCH_ITERS=N` | Override bench iteration count. |
| Writer demo | `COLUMNAR_WRITER_PATH`, optional `COLUMNAR_WRITER_SCHEMA`, `COLUMNAR_WRITER_ROWS` for `lake exe writer_roundtrip`. |

Bench regression helper: `bash scripts/check_bench_regression.sh` compares `bench/results/last-quick.json` to `BENCH_BASELINE_JSON` (optional) with `BENCH_MAX_REGRESSION_PCT`.

## SciLean

The default manifest has **no** SciLean packages (`lake-manifest.json` ships with `"packages": []`). To resolve SciLean + Mathlib transitively, run `COLUMNAR_SCILEAN=1 lake update` (Lake `meta if` cannot read `-K` flags when deciding whether to `require` SciLean). Link OpenBLAS via `-Kcolumnar.scilean=1` on `lake build` / `lake exe`; **`scripts/with_scilean.sh`** sets `COLUMNAR_SCILEAN` and forwards `-Kcolumnar.scilean=1`.

`Columnar.SciLean.TensorBridge` stays SciLean‑free; real conversions live in `Columnar.SciLean.Convert` behind `ColumnarSciLean`. Smoke tests: `Tests/Unit/SciLeanBridge.lean` (always on); `lake exe scilean_tests` when the optional library is built.

## CI

GitHub Actions: `leanprover/lean-action` (build + `lake test`), `COLUMNAR_BENCH_QUICK=1 lake exe bench`, `conformance-parquet` (stub codecs: fetch `vendor/*`, `lake exe tests`, Python writer smoke), **`conformance-parquet-native-codecs`** (Ubuntu: codec `-dev` packages, `COLUMNAR_CODEC=1`, `lake build -Kcolumnar.codec=1`, `lake exe tests -Kcolumnar.codec=1` with strict Phase‑1 tier), and **`scilean-bridge`** (Ubuntu: OpenBLAS + optional SciLean build + `scilean_tests`).
