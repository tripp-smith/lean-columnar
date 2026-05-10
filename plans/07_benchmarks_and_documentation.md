# Plan: Benchmarks vs reference stacks and documentation parity

## Objective

Meet **spec.md** performance expectations in a measurable, reproducible way, and keep **README** / **Manual** / **Conformance** aligned with actual CLI flags and workflows.

## Implementation requirements

### Benchmark harness

- **Workload registry**: Versioned datasets (path, schema, cold vs warm cache) checked in or downloaded by script.
- **Comparison**: `lake exe bench` invokes Lean timings **and** subprocess `pyarrow` (or `polars`) scan for the same logical read; emit one JSON schema with both medians and git SHA.
- **Regression**: Wire `scripts/check_bench_regression.sh` to fail on configurable regression vs `BENCH_BASELINE_JSON` (document first-run baseline capture).

### Documentation

- **README.md**: Replace stale `lake exe bench -- --quick` with `COLUMNAR_BENCH_QUICK=1 lake exe bench` (or document both if wrapper added).
- **docs/Manual.md**: Document new APIs from **01–06** (writer options, mmap, SciLean flag, interop CLIs).
- **docs/Conformance.md**: Keep CI matrix tables updated as new `mustDecode` tiers and codec jobs appear.

### Optional

- Nightly larger corpus job (documented only) to avoid slowing default PR CI.

## Acceptance criteria

- `bench/results/last-quick.json` includes fields consumed by `check_bench_regression.sh` under default quick mode.
- README quick start matches successful local runs on a clean checkout (with and without `vendor/`).

## Key code

- `Bench/Main.lean`, `scripts/check_bench_regression.sh`, `README.md`, `docs/Manual.md`, `docs/Conformance.md`

## Dependencies

- **04** for meaningful mmap benchmarks; **01–02** for representative Parquet read/write workloads.
