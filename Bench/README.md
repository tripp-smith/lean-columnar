# Benchmarks

Quick multi-format read benchmarks compare Lean decode time to PyArrow (or fastavro for Avro) on the same files.

## Run

```bash
lake build
COLUMNAR_BENCH_QUICK=1 lake exe bench
```

Output: [`results/last-quick.json`](results/last-quick.json) (`schema_version`, `workloads[]` with `lean_mean_ms` and `reference_mean_ms`).

Optional vendor Parquet: `bash scripts/fetch-fixtures.sh` (enables `parquet_binary`). Checked-in interop fixtures under `Tests/fixtures/` run without vendor.

Native codecs (Snappy Avro workload): `lake clean && COLUMNAR_CODEC=1 bash scripts/with_native_codecs.sh build bench && COLUMNAR_BENCH_QUICK=1 bash scripts/with_native_codecs.sh exe bench`.

Environment variables are listed in [`docs/Manual.md`](../docs/Manual.md#benchmarks).

## Baseline and regression

```bash
bash scripts/capture_bench_baseline.sh
BENCH_BASELINE_JSON=bench/results/baseline-quick.json bash scripts/check_bench_regression.sh
```

`BENCH_MAX_REGRESSION_PCT` (default 25) and `BENCH_WORKLOAD_IDS` (optional filter) control the checker. Commit `baseline-quick.json` only when updating the team baseline intentionally.

## Large / mmap runs

See `scripts/bench_large_mmap.sh` and `COLUMNAR_BENCH_LARGE=1` in the manual.
