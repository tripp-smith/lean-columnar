# Plan: Parquet reader — full coverage (pages, Thrift, nesting, row groups)

## Status: **Completed** (2026-05-01)

Delivered against this plan within repo constraints:

| Requirement | Outcome |
|-------------|---------|
| Data page v2 | `decodeDataPageV2` wired in `Reader.lean`; used when pages report `PageType.dataPageV2`. Compressed v2 values respect chunk codec. |
| Dictionary / delta / BSS | Decoder paths in `Reader.decodeValueRun`; Phase‑1 **`mustDecode`** includes `plain-dict-uncompressed-checksum.parquet` and `alltypes_dictionary.parquet`. Optional **`explore`** list (`COLUMNAR_PHASE1_EXPLORE=1`) adds delta / delta-byte-array / datapage v2 snappy samples — some still unstable natively; keep explore opt‑in. |
| DELTA_BINARY_PACKED | Iterative loop in `Encoding/Delta.lean` (no deep recursion stack blowups); guards for `blockSize == 0` and “no progress”. |
| Thrift compact footer | Field types 1–12 including **compact type 4 (I16)** documented same wire as zigzag varint as Apache clients (`Compact.lean`). |
| Multi–row-group reads | `readParquetAllRowGroups` / `readParquetRowGroup` / `RowGroupDecodeStream.nextDecoded` — concatenate or stream RG decode. |
| IEEE floats | `Core/Bytes.readFloat32LE` / `readFloat64LE` use **`Float32.ofBits` / `Float.ofBits`** (bit patterns), fixing PLAIN float/double. |
| Structured errors | `Except String` throughout decode pipeline with column / phase context where wired. |

**Deferred / follow-on** (not blocking plan closure):

- Materializing **LIST / MAP / STRUCT** into nested Lean values (beyond flat `Table` + dotted paths): schema walk exists; optional full decode behind **`COLUMNAR_DECODE_LIST_COLUMNS=1`** for `list_columns.parquet` remains experimental.
- Predicate/stat hooks on v2 pages (statistics fields optional in thrift).
- mmap-backed read path (`Core/MMap`) — stub stays stub until wired.

**Acceptance**

- `lake exe tests` passes; with `vendor/parquet-testing`, Phase‑1 **`mustDecode`** decodes; **`COLUMNAR_PHASE1_EXPLORE=1`** exercises extra corpora when investigating reader gaps.

---

## Objective (historical)

Close the gap between the current narrow Parquet reader and **spec.md** §2–3 (encodings, nested types, layout): decode a materially larger share of real-world files without regressing existing conformance.

## Implementation requirements

### Data pages

- **Data page v2**: Parse v2 headers and wire `decodeDataPageV2` (or equivalent) into the same column pipeline as v1; respect rep/def level blocks and statistics hooks where applicable.
- **Dictionary / delta / BSS**: Extend coverage beyond current paths for edge cases (optional null slots, mixed encodings across pages, oversized dictionary pages). Add targeted `parquet-testing` entries to the Phase‑1 manifest with `mustDecode` only when CI guarantees prerequisites.

### Thrift footer

- **Compact Thrift**: Implement missing field types (notably **compact type 4** and any others surfaced by `parquet-testing` failures). Fuzz or property-test the compact parser against known-good footers exported by pyarrow.

### Nested schema & levels

- **Schema tree**: Map Parquet logical nested types (LIST, MAP, STRUCT) to stable leaf paths and chunk pairing; align with `SchemaWalk` and `matchLeavesToChunks`.
- **Repetition levels**: Use `maxRepetitionLevel` in materialization (not only consume bytes); produce nested-friendly output or an explicit intermediate representation before flattening to `Table`.
- **Conformance**: Add `parquet-testing` nested fixtures with value-level assertions once decoding is correct.

### Multi–row-group reads

- **API**: Expose `readRowGroup (idx : Nat)` or `readParquetAllRowGroups` that concatenates or yields per–row-group tables; document memory trade-offs.
- **Streaming decode**: Row-group iterator should optionally **decode** columns (not only footer metadata), reusing page readers and codec paths.

### Non-functional

- **Performance**: Avoid O(row_groups) full-file rescans per column where possible; profile hot paths.
- **Errors**: Preserve structured `Except String` messages with file path + column + page context.

## Acceptance criteria

- `lake exe tests` passes with vendor fixtures present; new `mustDecode` entries pass under documented CI flags.
- At least one previously failing `parquet-testing` file (v2 or Thrift type 4) decodes end-to-end with documented column expectations.

## Key code

- `Columnar/Parquet/Reader.lean`, `Page.lean`, `Metadata.lean`, `SchemaWalk.lean`, `Tests/Conformance/ParquetPhase1Encoding.lean`

## Dependencies

- Native **decompression** for compressed column chunks is provided by [Plan 03 — Compression codecs](03_compression-codecs-and-io-policy.md) (completed) plus [`docs/FFI.md`](../../docs/FFI.md): use `COLUMNAR_CODEC=1`, `lake -Kcolumnar.codec=1`, and linked system libs (GitHub workflow `conformance-parquet-native-codecs`).
