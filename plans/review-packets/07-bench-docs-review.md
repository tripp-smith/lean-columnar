# Plan 07 review packet

## Definition of done (D1–D11)

| ID | Status | Evidence |
|----|--------|----------|
| D1 | OK | Multi-workload `lake exe bench`; `missing_file` skip when parquet path absent; no whole-run abort |
| D2 | OK | `bench/results/last-quick.json` — `schema_version`, `git_sha`, `timestamp_utc`, `columnar_codec_build`, `workloads[]` with Lean + reference fields |
| D3 | OK | `check_bench_regression.sh` per-workload `jq`; first-run points to `capture_bench_baseline.sh` |
| D4 | OK | `scripts/capture_bench_baseline.sh` |
| D5 | OK | README quick start + Benchmarks section; vendor optional |
| D6 | OK | Manual: Benchmarks env table, Parquet + interop + SciLean API rows, Interop/macOS/Native codecs |
| D7 | OK | FFI: `tests`/`bench` `meta if`, macOS `-L`, ORC raw deflate |
| D8 | OK | Conformance: benchmark artifacts, registry paths, CI matrix, nightly note |
| D9 | OK | `spec.md` §2/§7 qualified performance claims |
| D10 | OK | CI: Ubuntu `pyarrow`/`fastavro`, bench step, artifact upload |
| D11 | OK | Agent critical review (below); Claude initial gap (SciLean in Manual) fixed |

## Agent critical review (2026-05-17)

### Verdict: **COMPLETE**

### Gaps found and fixed in this pass

1. **Manual.md** — misplaced “Test order” paragraph under SciLean → moved back under **Native codecs**.
2. **`scripts/check_bench_regression.sh`** — regression OK line could print after a failed compare; fixed `if python3 … then … else failed=1`.
3. **`scripts/check_bench_regression.sh`** — documented first-run baseline capture when no `BENCH_BASELINE_JSON`.
4. **Path hygiene** — removed stale `Bench/results/` artifacts; canonical output is `bench/results/` (`.gitignore` adds `last-quick.json`).
5. **CI** — artifact upload `if-no-files-found: warn` when bench JSON missing on a failed matrix cell.

### Confirmed without change

- Registry workloads match plan §1.1; `avro_snappy` pre-skips on stub (avoids macOS SIGSEGV on Snappy decode attempt).
- `lakefile.lean` bench link mirrors `tests` (`meta if` native vs `columnarZlibOnlyLinkArgs`).
- V7: no `bench -- --quick` in runnable scripts/CI (only in completed plan prose).
- Plan moved to `plans/completed/07_benchmarks-and-documentation.md`; README Status links plan 07.

### Claude CLI (prior)

First run: **INCOMPLETE** (D6 SciLean missing in Manual). SciLean section + API rows added before this agent pass.

## Sample `bench/results/last-quick.json`

See committed run output: six workloads (`parquet_binary` … `arrow_file`), `avro_snappy` → `skip` / `requires_native_codec` on stub builds.

## Verification (re-run)

```text
lake build && COLUMNAR_BENCH_QUICK=1 lake exe bench  → exit 0
COLUMNAR_BENCH_FILE=/nonexistent.parquet COLUMNAR_BENCH_WORKLOADS=parquet_binary → skip missing_file
python3 -m json.tool bench/results/last-quick.json → valid
bash scripts/capture_bench_baseline.sh && BENCH_BASELINE_JSON=bench/results/baseline-quick.json bash scripts/check_bench_regression.sh → OK
lake exe tests → exit 0 (macOS: Parquet groups SKIP without COLUMNAR_PARQUET_READER_OSX=1)
```
