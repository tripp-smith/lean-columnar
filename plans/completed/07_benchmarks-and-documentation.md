# Plan: Benchmarks vs reference stacks and documentation parity

## Status: **Completed** (2026-05-17)

## Objective

Deliver **in one implementation pass** (no phased rollout):

1. A **multi-workload benchmark harness** that times Lean reads and PyArrow reference reads on the same bytes, writes versioned JSON artifacts, and supports regression checks.
2. **Documentation parity** across README, Manual, FFI, and Conformance for every public API and env flag shipped in plans **01–06** (Parquet, mmap/stream, codecs, SciLean, Avro/ORC/Arrow interop).
3. **CI and local workflows** that run quick bench on every matrix build and document how to capture baselines and run native-codec benches.

This satisfies **spec.md** §7 (*Benchmarks: vs. pyarrow, Polars, DuckDB on real ML datasets*) and §2 (*Performance: match or beat native C++ Arrow/Parquet on columnar scans*) in a **measurable, reproducible** way—with explicit workload names, stub vs native codec mode, and qualified claims until numbers exist.

## Definition of done

All items below must be true before the plan is closed. **Conformance correctness** stays in `lake exe tests`; **bench** is throughput/comparison only.

| # | Criterion |
|---|-----------|
| D1 | `lake exe bench` (default quick mode) runs **all registered workloads** that have present inputs; missing inputs produce structured skip entries in JSON, not crash. |
| D2 | `bench/results/last-quick.json` matches the **JSON schema** in this plan (git SHA, build mode, per-workload Lean + reference timings). |
| D3 | `scripts/check_bench_regression.sh` compares **each workload** (and optional aggregate) against `BENCH_BASELINE_JSON`; documents first-run baseline capture. |
| D4 | `scripts/capture_bench_baseline.sh` (or documented one-liner) copies `last-quick.json` → `bench/results/baseline-quick.json` with commit message guidance. |
| D5 | **README** quick start runs on clean checkout (stub codecs, no vendor) and documents vendor + native codec paths. |
| D6 | **docs/Manual.md** documents Parquet, mmap/stream, writer, SciLean, codecs, **and interop** APIs in one table + env flag section. |
| D7 | **docs/FFI.md** matches **lakefile.lean** (`COLUMNAR_CODEC`, `meta if` on `tests`/`bench` link, macOS `-L` paths, ORC raw deflate). |
| D8 | **docs/Conformance.md** lists interop fixtures, bench registry paths, CI bench step, regression env vars, and cross-links to Manual/FFI. |
| D9 | **spec.md** performance sentence qualified with “measured workloads” and link to bench JSON fields (no unqualified “beat Arrow” without data). |
| D10 | CI `build` job still runs `COLUMNAR_BENCH_QUICK=1 lake exe bench` and uploads or retains JSON artifact (existing artifact upload may include bench path). |
| D11 | **Claude CLI review** (final step): external review against spec.md agrees all plan-07 deliverables are complete; iterate until agreement. |

---

## 1. Benchmark harness (implement completely)

### 1.1 Workload registry

Implement a single registry (Lean `structure BenchWorkload` or `Bench/Registry.lean`)—**not** ad-hoc strings in `Main.lean`. Each entry:

| Field | Purpose |
|-------|---------|
| `id` | Stable key, e.g. `parquet_binary`, `avro_minimal`, `avro_snappy`, `orc_int32`, `arrow_stream`, `arrow_file`, `parquet_mmap` |
| `leanRunner` | IO action that performs one full read/decode |
| `defaultPath` | Repo-relative path |
| `requiresVendor` | If true, skip when path missing (no fail) |
| `requiresNativeCodec` | If true, skip with note when stub build |
| `referenceScript` | Which PyArrow/fastavro subprocess template to run |

**Required workloads (checked-in or env override):**

| `id` | Lean API | Default path | Vendor? | Native codec? | PyArrow / reference |
|------|----------|--------------|---------|---------------|---------------------|
| `parquet_binary` | `readParquet` | `vendor/parquet-testing/data/binary.parquet` | yes | per file | `pyarrow.parquet.read_table` |
| `parquet_mmap` | `readParquetMmap` | same as `COLUMNAR_BENCH_FILE` or default parquet | yes | per file | same (read_table after mmap N/A—document as Lean-only mmap path) |
| `avro_minimal` | `readAvroOcf` | `Tests/fixtures/interop_minimal.avro` | no | no | `pyarrow` Avro or `fastavro` reader |
| `avro_snappy` | `readAvroOcf` | `Tests/fixtures/interop_minimal_snappy.avro` | no | **Snappy** | same |
| `orc_int32` | `readOrcPrimitives` `["x"]` | `Tests/fixtures/interop_orc_int32.orc` | no | no | `pyarrow.orc.ORCFile.read` |
| `arrow_stream` | `readArrowIpcStreamFile` | `Tests/fixtures/interop_arrow_int32_stream.arrow` | no | no | `pyarrow.ipc.open_stream` |
| `arrow_file` | `readArrowIpcFile` | `Tests/fixtures/interop_arrow_int32_file.arrow` | no | no | `pyarrow.ipc.open_file` |

**Explicitly excluded from default quick bench** (conformance only): `vendor/orc/examples/TestOrcFile.test1.orc` (zlib stripe, macOS heap sensitivity).

**Env overrides (document in Manual):**

| Variable | Effect |
|----------|--------|
| `COLUMNAR_BENCH_QUICK=1` | Fewer iterations (existing; keep) |
| `COLUMNAR_BENCH_ITERS=N` | Override iteration count |
| `COLUMNAR_BENCH_FILE` | Override parquet (+ mmap) path |
| `COLUMNAR_BENCH_MMAP=1` | Include `parquet_mmap` workload |
| `COLUMNAR_BENCH_LARGE=1` | Default 1 iter when `ITERS` unset (existing) |
| `COLUMNAR_BENCH_SKIP_REFERENCE=1` | Lean-only timings (no Python subprocess) |
| `COLUMNAR_BENCH_WORKLOADS=id1,id2` | Run subset of registry ids |

### 1.2 JSON output schema

Write `bench/results/last-quick.json` (and same shape for baseline). Example:

```json
{
  "schema_version": 1,
  "git_sha": "<short sha>",
  "timestamp_utc": "<ISO8601>",
  "mode": "quick",
  "columnar_codec_build": "stub|native",
  "iterations": 30,
  "workloads": [
    {
      "id": "parquet_binary",
      "file": "vendor/parquet-testing/data/binary.parquet",
      "status": "ok|skip|error",
      "skip_reason": null,
      "lean_elapsed_ms_total": 120,
      "lean_mean_ms": 4.0,
      "reference": "pyarrow",
      "reference_elapsed_ms_total": 80,
      "reference_mean_ms": 2.67,
      "row_count": 1000
    }
  ]
}
```

- **`git_sha`**: `git rev-parse --short HEAD` from bench driver (shell or Lean `IO.Process`).
- **`columnar_codec_build`**: detect via small probe (e.g. try Snappy round-trip on codec fixture) or env `COLUMNAR_CODEC` at compile time recorded in a generated `Bench/BuildInfo.lean` if needed.
- **Backward compat**: `check_bench_regression.sh` may still read top-level `mean_ms` as `parquet_binary.lean_mean_ms` for one release, then drop legacy fields.

### 1.3 Lean bench driver

Refactor [`Bench/Main.lean`](../Bench/Main.lean):

- Import registry; loop workloads; warm-up optional (1 iter discard).
- Per workload: time Lean runner; on success optionally count rows (table column length).
- Invoke reference timing via `IO.Process.spawn` Python helper (see §1.4).
- On missing file / stub codec / error: set `status` + `skip_reason`, continue other workloads.
- Exit 0 if bench completed (skips allowed); non-zero only on internal failure.
- Print human summary: `bench: <id> lean_mean_ms=… ref_mean_ms=…`.

Add **`lake exe bench`** link args: same `columnarZlibOnlyLinkArgs` / native `meta if` as `tests` so ORC/Avro snappy benches work when built with `COLUMNAR_CODEC=1`.

### 1.4 Reference (PyArrow) subprocess

Add **`scripts/bench_reference.py`** (single entry):

- Args: `--format parquet|avro|orc|arrow_stream|arrow_file`, `--path PATH`, `--iters N`.
- Prints one JSON line to stdout: `{"elapsed_ms_total":…,"mean_ms":…,"row_count":…}`.
- Dependencies: `pyarrow`, `fastavro` (document in Manual + CI note: reference step **SKIP** if `python3 -c import pyarrow` fails on minimal CI—acceptable for Linux build job if Python not installed; **install pyarrow on ubuntu build job** for full comparison per spec).

**CI recommendation:** On `build` ubuntu job, `pip install pyarrow fastavro` before `lake exe bench` so D1 comparison runs in CI.

### 1.5 Regression tooling

Update [`scripts/check_bench_regression.sh`](../scripts/check_bench_regression.sh):

- Require `jq`.
- For each workload id in baseline and new JSON, compare `lean_mean_ms` (and optionally `reference_mean_ms`).
- Env: `BENCH_MAX_REGRESSION_PCT` (default 25), `BENCH_WORKLOAD_IDS` (optional filter).
- Fail if any compared workload regresses beyond threshold.
- If baseline missing: exit 0 with message (keep current behavior).

Add **`scripts/capture_bench_baseline.sh`**:

```bash
cp bench/results/last-quick.json bench/results/baseline-quick.json
echo "Captured baseline; commit bench/results/baseline-quick.json when intentional."
```

Document in Manual and Conformance.

### 1.6 Nightly / large corpus (documentation only)

Add subsection **“Nightly benchmarks (optional)”** in `docs/Conformance.md`:

- Describe a **manual or scheduled** workflow: `COLUMNAR_BENCH_LARGE=1`, `scripts/bench_large_mmap.sh`, multi-GB `COLUMNAR_BENCH_FILE`, artifact retention—not wired to default PR CI.

No separate implementation phase; **text only** in this pass.

---

## 2. Documentation (implement completely)

### 2.1 README.md

- Confirm quick start: `COLUMNAR_BENCH_QUICK=1 lake exe bench` (remove any `lake exe bench -- --quick` if still present anywhere in repo).
- Add **Benchmarks** bullet: multi-format quick bench, `bench/results/last-quick.json`, baseline capture, `check_bench_regression.sh`.
- Link to Manual bench section and Conformance CI row.
- Note: vendor optional for parquet workload; checked-in interop fixtures run without vendor.

### 2.2 docs/Manual.md

Add/update sections in **one edit**:

1. **Benchmarks** — all `COLUMNAR_BENCH_*` env vars; iteration defaults; mmap large-file cross-link to `bench_large_mmap.sh`; stub vs native; macOS partial link note (zlib without Snappy).
2. **API table** — extend existing Parquet table with:

   | Operation | Entry point |
   |-----------|-------------|
   | Avro OCF → Table | `readAvroOcf` / `readAvroOcfFromBytes` |
   | ORC row count | `readOrcNumberOfRows` |
   | ORC primitive columns | `readOrcPrimitives` (list of column names) |
   | Arrow IPC stream | `readArrowIpcStreamFile` |
   | Arrow IPC file | `readArrowIpcFile` |

3. **Interop** — regenerate `python3 scripts/export_interop_goldens.py`; vendor paths; **do not** use bench for golden correctness.
4. **Native codecs** — `lake clean`; `with_native_codecs.sh`; interop strict flag pointer.
5. **macOS testing** — `COLUMNAR_PARQUET_READER_OSX=1`; interop order (before Parquet mmap; Arrow before ORC); pointer to Conformance.

### 2.3 docs/FFI.md

- State that **`tests` and `bench` executables** get codec `-L`/`-l` flags when `COLUMNAR_CODEC=1` at Lake load (`meta if columnarNativeCodecsPkg`), plus macOS SDK zlib path.
- Add **ORC zlib**: 3-byte LE original length + **raw deflate** (`columnar_zlib_inflate_raw`, `inflateInit2(-15)`), not `uncompress` wrapper.
- Cross-link bench native build: `COLUMNAR_CODEC=1 bash scripts/with_native_codecs.sh build bench`.

### 2.4 docs/Conformance.md

- Add **Benchmark artifacts** section: schema_version, workload ids, regression script, baseline capture.
- Sync fixture list with bench registry paths (interop + `vendor/parquet-testing/...`).
- CI table: `build` job runs bench + optional pyarrow; note artifact `bench/results/last-quick.json`.
- Keep interop matrix (`COLUMNAR_INTEROP_STRICT`, `fetch-fixtures.sh`) aligned with plan 06.

### 2.5 spec.md

Edit §2 / §7 performance bullets to:

- Point to `bench/results/last-quick.json` and named workloads.
- Replace unqualified “match or beat” with “tracked on `parquet_binary`, `arrow_stream`, …; see docs/Conformance.md”.

---

## 3. CI and repo layout

| Change | Location |
|--------|----------|
| Install Python deps for reference bench | `.github/workflows/ci.yml` `build` job (ubuntu): `pip install pyarrow fastavro` before bench |
| Upload bench JSON | Extend existing conformance artifact upload or add `bench/results/last-quick.json` to artifact paths |
| Optional regression job | Document only: `BENCH_BASELINE_JSON=bench/results/baseline-quick.json bash scripts/check_bench_regression.sh` for maintainers (do not fail PR if baseline absent) |
| `bench/results/.gitkeep` | Keep; **do not** commit `last-quick.json`; **optionally** commit `baseline-quick.json` after first capture (team policy—document in Conformance) |

Add **`bench/README.md`** (short): schema, how to run, capture baseline, regression.

---

## 4. Implementation map (single pass — all files)

| File | Action |
|------|--------|
| `Bench/Registry.lean` | **New** — workload registry + runners |
| `Bench/Reference.lean` or inline in Main | Spawn `scripts/bench_reference.py` |
| `Bench/Main.lean` | **Rewrite** — multi-workload loop, JSON writer |
| `Bench/BuildInfo.lean` | **Optional** — stub vs native string from compile flag |
| `scripts/bench_reference.py` | **New** — PyArrow/fastavro timings |
| `scripts/check_bench_regression.sh` | **Update** — per-workload jq comparison |
| `scripts/capture_bench_baseline.sh` | **New** |
| `lakefile.lean` | Ensure `lean_exe bench` has same codec link `meta if` as `tests` |
| `README.md` | Bench + interop pointers |
| `docs/Manual.md` | Full API + bench + interop + macOS |
| `docs/FFI.md` | Link model + ORC raw deflate |
| `docs/Conformance.md` | Bench registry + CI |
| `spec.md` | Qualified performance claims |
| `bench/README.md` | **New** |
| `.github/workflows/ci.yml` | pyarrow pip + artifact path if needed |

**Do not** split into “phase 1 docs, phase 2 bench”—land registry, driver, scripts, and docs together so JSON schema and Manual stay consistent.

---

## 5. Verification matrix (run before Claude review)

| Step | Command | Pass |
|------|---------|------|
| V1 | `lake build && COLUMNAR_BENCH_QUICK=1 lake exe bench` | Exit 0; JSON has `schema_version`, `workloads[]` with checked-in interop **ok**; parquet **skip** if no vendor |
| V2 | `bash scripts/fetch-fixtures.sh && COLUMNAR_BENCH_QUICK=1 lake exe bench` | `parquet_binary` **ok**; Lean + reference means present |
| V3 | `python3 -m json.tool bench/results/last-quick.json` | Valid JSON |
| V4 | `bash scripts/capture_bench_baseline.sh && BENCH_BASELINE_JSON=bench/results/baseline-quick.json bash scripts/check_bench_regression.sh` | OK within threshold |
| V5 | `lake build && lake exe tests` | Exit 0 (stub); interop unchanged |
| V6 | `lake clean && COLUMNAR_CODEC=1 bash scripts/with_native_codecs.sh build bench tests && COLUMNAR_BENCH_QUICK=1 bash scripts/with_native_codecs.sh exe bench` | `avro_snappy` **ok** when Snappy links; JSON `columnar_codec_build=native` |
| V7 | Grep repo for `bench -- --quick` | No stale invocations |
| V8 | Read Manual API table | Parquet + Avro + ORC + Arrow rows present |
| V9 | CI green on PR | build matrix passes including bench step |

---

## 6. Pitfalls (mandatory reading for implementer)

1. **`lake clean`** after toggling `COLUMNAR_CODEC` before comparing stub vs native bench numbers.
2. **Bench ≠ tests** — no golden assertions in bench; row_count in JSON is informational only.
3. **macOS**: full Parquet conformance may SKIP (`COLUMNAR_PARQUET_READER_OSX=1`); bench can still run interop fixtures.
4. **Orc stream payloads**: per-stream chunks are usually **3-byte header strip only**—do not zlib-decompress every stream chunk in bench paths (see plan 06 / `orcStreamPayload`).
5. **Reference failures**: bench should SKIP reference timing if Python missing, not fail entire bench (Lean timings still valuable).
6. **Heap ordering**: running Arrow IPC bench after heavy ORC zlib in the **same process** as tests caused issues—bench is separate exe; for `lake exe tests`, keep Arrow before ORC in `Tests/Main.lean`.

---

## 7. Final step: Claude CLI spec review loop

After V1–V9 pass locally, run an **external completion review** with the Claude CLI. Goal: iterate until Claude agrees that **plan 07 and spec.md §2/§7** are satisfied—not merely that code exists.

### 7.1 Prepare review packet

Create **`plans/review-packets/07-bench-docs-review.md`** (commit in same PR) containing:

- Link to this plan’s **Definition of done** (D1–D11).
- Paste or summarize `bench/results/last-quick.json` from V2 (redact nothing material).
- List of doc files changed with one-line summary each.
- Excerpt of spec.md performance bullets **after** edit.
- Command outputs for V1, V4, V5 (truncated OK).

### 7.2 Run Claude CLI

From repo root (requires [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated):

```bash
claude -p "$(cat <<'EOF'
You are reviewing whether lean-columnar plan 07 (benchmarks + documentation) is COMPLETE against spec.md.

Read:
- spec.md (sections 2, 7)
- plans/07_benchmarks_and_documentation.md (Definition of done D1–D11)
- plans/review-packets/07-bench-docs-review.md
- bench/results/last-quick.json (if present)
- docs/Manual.md, docs/Conformance.md, docs/FFI.md, README.md (bench sections)

Output EXACTLY two sections:

## Verdict
One of: COMPLETE | INCOMPLETE

## Gaps
If INCOMPLETE: numbered list of specific missing items mapped to D1–D11 or spec.md quotes.
If COMPLETE: write "None" and cite evidence for benchmarks vs pyarrow and doc parity.

Be strict: unqualified performance claims, missing workload in JSON, or API table gaps = INCOMPLETE.
EOF
)"
```

If your CLI uses a different invocation (e.g. `claude chat`), equivalent is fine—**must** include spec.md + plan D1–D11 + artifacts.

### 7.3 Iterate until COMPLETE

1. If verdict is **INCOMPLETE**, implement every listed gap in the same branch (code + docs + bench JSON).
2. Re-run verification matrix V1–V9.
3. Update `plans/review-packets/07-bench-docs-review.md` with fresh outputs.
4. Re-run the Claude prompt.
5. Repeat until verdict is **COMPLETE**.

### 7.4 Close plan 07

When Claude returns **COMPLETE**:

- Move this file to `plans/completed/07_benchmarks-and-documentation.md` (or add **Status: Completed** header and date at top if you prefer in-place).
- Add one line to README status linking completed plan 07.

**Do not** mark the plan done without a **COMPLETE** Claude verdict in the PR description or review packet (paste final Claude output).

---

## Dependencies

| Plan | Requirement |
|------|-------------|
| **01–02** | Parquet read/write workloads and vendor parquet path |
| **03** | Native codec FFI (bench native mode, Snappy Avro workload) |
| **04** | `readParquetMmap`, `COLUMNAR_BENCH_MMAP`, large-file docs |
| **05** | SciLean flags documented in Manual (no bench required unless added to registry as optional `scilean` smoke) |
| **06** | Interop APIs + checked-in fixtures (registry rows) |

## Key code (summary)

`Bench/Registry.lean`, `Bench/Main.lean`, `scripts/bench_reference.py`, `scripts/check_bench_regression.sh`, `scripts/capture_bench_baseline.sh`, `lakefile.lean`, `README.md`, `docs/Manual.md`, `docs/FFI.md`, `docs/Conformance.md`, `spec.md`, `.github/workflows/ci.yml`, `bench/README.md`, `plans/review-packets/07-bench-docs-review.md`
