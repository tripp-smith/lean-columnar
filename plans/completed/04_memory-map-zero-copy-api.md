# Plan: Memory-mapped I/O and zero-copy column API

**Status:** Completed (see completion summary at bottom).

## Objective

Move from “read whole `ByteArray` + materialize `Option PlainValue` columns” toward **spec.md** zero-copy and streaming: mmap-backed slices, stable handles, and optional materialization.

## Implementation requirements

### mmap

- Implement real **memory-mapped** file access in `Columnar/Core/MMap.lean` (platform-specific: POSIX `mmap`; document non-support on WASM if applicable).
- Plumb mmap into `readParquetMmap` / shared byte source for footer parse + page reads without duplicating full file in RAM for large inputs.

### API surface

- Introduce or evolve types toward **`ParquetFile` / `ColumnHandle`** (path + footer cache + optional mmap region) as in **spec.md** §4 sketch.
- **Column views**: Expose `SubArray UInt8` / typed slices for primitive runs where definition levels are trivially max; document when materialization to `Array (Option PlainValue)` is required (nulls, nested).

### Streaming

- Public **`streamRowGroups`** (or equivalent) yielding row-group scoped readers that reuse the mmap region and page index.

## Acceptance criteria

- Benchmark (`lake exe bench`) shows measurable RSS or wall-clock improvement vs `readBinFile` on a multi-GB synthetic file (document hardware + methodology).
- API docs (`docs/Manual.md`) describe lifetime/safety: who owns the mmap region, when it is unmapped.

## Key code

- `Columnar/Core/MMap.lean`, `Columnar/Parquet/Reader.lean`, `Columnar/Parquet/Stream.lean`, `Columnar/Table.lean`, `docs/Manual.md`

## Dependencies

- **01** (page decode correctness) should be stable before optimizing I/O around wrong bytes.

---

## Completion summary (2026)

Delivered in-tree:

- **POSIX mmap** (`Columnar/Core/MMap.lean`, `c/columnar_codec.c`) with macOS opt-in (`COLUMNAR_FORCE_MMAP=1`) and `COLUMNAR_DISABLE_MMAP` fallback.
- **`ParquetFile` / `openParquetFile` / `readParquetMmap`** with **`ParquetBacking.ofMmap`** retained for decode: footer via bounded `copyRange`, column/page walks via mmap-backed slice reads (no full-file `ByteArray` copy at open).
- **Public `streamRowGroups`** (`Columnar/Parquet/Stream.lean`) over shared backing until `dispose`.
- **Primitive packed views:** `Column.plainInt64PackedBytes?`, `Column.plainInt64PackedSubarray?`, `Column.plainInt32PackedBytes?`, `Column.plainInt32PackedSubarray?` in [`Columnar/Table/PlainViews.lean`](Columnar/Table/PlainViews.lean) — dense LE slabs after decode when every cell is non-null `(int32|int64)`; materializes packed bytes from boxed cells (documented).
- **Bench:** `COLUMNAR_BENCH_FILE`, **`COLUMNAR_BENCH_LARGE=1`** (defaults iterations to 1 when `COLUMNAR_BENCH_ITERS` unset), JSON **`file`** field; script **`scripts/bench_large_mmap.sh`** for synthetic multi-row-group corpus + timing; RSS methodology in **`docs/Manual.md`** (`/usr/bin/time -v`, etc.).
- **Debug harness:** `lake exe mmap_harness`, `scripts/run-mmap-harness.sh`.

Remaining stretch goals (optional follow-ups): full **`ColumnHandle`** lifecycle API per spec §4 fig-leaf; packed views wired **during** decode (true raw slab without `PlainValue` boxing); broader typed slices for float/double.
