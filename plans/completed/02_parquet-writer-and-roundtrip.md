# Plan: Parquet writer — general table output and round-trip verification

## Status: **Completed** (2026-05-01)

| Requirement | Outcome |
|-------------|---------|
| Schema + footer | `WriteSchema` + `serializeSchemaListPayload` / `serializeFileMetaData` — multi–row-group footer list (`Footer.serializeRowGroupList`). Root schema matches common writers (field 3 repetition). |
| Column chunks | PLAIN physical encoding + RLE definition levels; `codec` enforced UNCOMPRESSED until FFI compression path is implemented. |
| Row groups & pages | **`WriteOptions.rowsPerRowGroup`** splits output into multiple Parquet row groups (`Writer/File.lean`). Each RG emits one data page per column (multi-page-per-column when `data_page_target_size` exceeded — **deferred** as future milestone). |
| API | `writeParquet` / `writeParquetBytes` with `WriteOptions`. |
| Lean verification | `Tests/Conformance/ParquetWriterRoundtrip` — empty, seq, **multi-RG** (`readParquetAllRowGroupsFromBytes`), float, mixed, nullable. Pure Lean, no Python. |
| Python verification | `scripts/parquet_roundtrip_smoke.py` — INT32 seq, mixed, nullable; **multi row-group** check via `COLUMNAR_WRITER_RG_SIZE` + `verify_row_group_count`. PyArrow preferred, fastparquet fallback. |
| CI | `lake exe writer_roundtrip` target; workflow runs smoke with pandas/fastparquet/pyarrow. |

**Deferred**

- Dictionary / delta / RLE value encodings on write.
- **Column compression on write** (Snappy/Zstd/etc. encode path + writer integration): still deferred; this is separate from [Plan 03](03_compression-codecs-and-io-policy.md) (completed), which delivers **decompress** FFI for the reader. Reading Snappy/Zstd-compressed files works when native codecs are enabled per [`docs/FFI.md`](../../docs/FFI.md).

---

## Objective (historical)

Replace the early **canonical-only** prototype with a writer that matches **spec.md** goals: arbitrary flat schemas (then nested), correct metadata, and verified **write ∘ read** invariants. (Template byte blobs and `gen_writer_templates.py` are **retired**; serialization is fully runtime.)

## Implementation requirements

### Writer core

- **Schema emission**: Write Thrift `FileMetaData` + schema elements from `Table` (or a richer `WriteSchema` view): physical types, repetition, optional logical types.
- **Column chunks**: Plain encoding first; then dictionary / RLE / delta as phased milestones. Respect `codec` per column (SNAPPY, etc.) when FFI is available; otherwise error or fall back per policy.
- **Row groups & pages**: Configurable `rows_per_row_group` and `data_page_target_size`; multiple data pages per column when needed.
- **API**: `writeParquet (t : Table) (path : FilePath) (opts : WriteOptions)` with validation errors for unsupported combinations.

### Templates / codegen

- **Done**: template blobs removed; no separate codegen step for Parquet bytes.

### Verification

- **Lean tests**: Round-trip `writeParquet` → `readParquet` for generated tables (small deterministic + edge cases: empty table, single row, max nulls).
- **Python**: `scripts/parquet_roundtrip_smoke.py` verifies writer output with **pandas + fastparquet** (PyArrow’s thrift reader rejects our FileMetaData encoding until aligned with Apache thrift wire expectations).
- **CI**: Gate on `lake exe writer_roundtrip` + smoke (`pandas`, `fastparquet`).

## Acceptance criteria

- Writer produces files pyarrow can open with **matching schema and cell values** for at least: all-primitive flat schema, nullable columns, two row groups.
- `lake exe tests` includes at least one writer round-trip test that does not depend on pyarrow (pure Lean).

## Key code

- `Columnar/Parquet/Writer/File.lean`, `scripts/parquet_roundtrip_smoke.py`, `lakefile.lean` (`writer_roundtrip` target)

## Dependencies

- Reader stability for the same subset (**01** reader plan) to make round-trip meaningful.
