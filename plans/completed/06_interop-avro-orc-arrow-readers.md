# Plan: Avro, ORC, and Arrow IPC — real readers beyond fingerprints

## Status: **Completed** (2026-05-09)

### Delivered

| Area | API / module | Notes |
|------|----------------|-------|
| **Avro OCF** | `readAvroOcf`, `readAvroOcfFromBytes` | [`Columnar/Avro/Container.lean`](../../Columnar/Avro/Container.lean): null, **deflate**, **Snappy** (Avro framing: big-endian uncompressed size + Snappy payload). Schema JSON + binary decode to [`Columnar.Table`](../../Columnar/Table.lean). |
| **ORC** | `readOrcNumberOfRows`, `readOrcPrimitives`, `readOrcPrimitivesFromBytes` | Footer zlib + postscript ([`Columnar/Orc/Reader.lean`](../../Columnar/Orc/Reader.lean)); single-stripe **uncompressed** `struct{x:int}` stripe DATA decode via [`Columnar/Orc/RleV2.lean`](../../Columnar/Orc/RleV2.lean) + [`Columnar/Orc/FooterRead.lean`](../../Columnar/Orc/FooterRead.lean). |
| **Arrow IPC** | `ipcStreamMessageCount`, `readArrowIpcStreamFile`, `readArrowIpcStreamFromBytes` | [`Columnar/Arrow/Flatbuf.lean`](../../Columnar/Arrow/Flatbuf.lean) minimal vtable helpers; [`Columnar/Arrow/IPC.lean`](../../Columnar/Arrow/IPC.lean) stream loop with **padded body** + `Message.bodyLength`, Schema + RecordBatch → `Table` for flat primitives (int32/64, bool, float/double, utf8/binary). |
| **Conformance** | `scripts/export_interop_goldens.py` | Checked-in fixtures: `interop_minimal.avro`, `interop_minimal_snappy.avro`, `interop_orc_int32.orc`, `interop_arrow_int32_stream.arrow`; goldens under `Tests/goldens/interop_*`. |
| **Tests** | `Tests/Conformance/{Avro,Orc,Arrow}Interop.lean` | Avro null + Snappy (SKIP on missing Snappy / stub); ORC `TestOrcFile.test1.orc` row count (SKIP on zlib unavailable) + **interop int32** column golden; Arrow vendor message count + **stream decode** golden. |

### Explicitly deferred

| Item | Rationale |
|------|-----------|
| **Arrow IPC file** format (footer + record batches) | Stream path covers checked-in integration; file layout can reuse metadata/body stepping with different framing. |
| **ORC** full `TestOrcFile.test1.orc` stripe zlib + multi-column matrix | Lean path targets **uncompressed** single-stripe interop ORC; vendor `test1` remains row-count only unless extended. |
| **Avro** optional read-only `vendor/avro/share/test` corpus | Kept to exporter + small checked-in fixtures to avoid huge vendor-dependent matrices. |

### Verification checklist

| Step | Command / expectation |
|------|------------------------|
| Stub default CI | `lake build` && `lake exe tests` (Snappy Avro + zlib ORC footer SKIP with clear info when codecs stubbed). |
| Native codecs | `bash scripts/with_native_codecs.sh build tests` then `bash scripts/with_native_codecs.sh exe tests` on a machine with `libsnappy`, `zlib`, etc. (see [`docs/FFI.md`](../../docs/FFI.md)). |
| Regenerate interop bytes | `python3 scripts/export_interop_goldens.py` (`pip install fastavro pyarrow`). |
| macOS | Parquet-heavy groups unchanged: `COLUMNAR_PARQUET_READER_OSX=1` per [`docs/Conformance.md`](../../docs/Conformance.md). |

---

## Objective (historical)

Progress from **magic-byte / framing smoke tests** to minimal **record/stream decoding** aligned with **spec.md** phased multi-format support.

## Implementation requirements (historical)

### Avro OCF

- Parse container header + sync + metadata map; decode **schema JSON** to internal `AvroType` (replace throws in `Columnar/Avro/Schema.lean`).
- Read **deflate/snappy** blocks per container spec; emit records as `Table` or streaming iterator.
- Conformance: subset of `vendor/avro/share/test` with golden JSON from `fastavro` or `avro` tools (scripted).

### ORC

- Read **postscript + footer + stripe** index; decode selected primitive columns for a narrow type matrix.
- Conformance: `vendor/orc/examples` cross-check stripe stats + sample rows vs `orc-metadata` / Java tools.

### Arrow IPC

- Implement **IPC stream/file** message loop: schema + RecordBatch vectors for primitive types first.
- Conformance: small `.arrow` files from `vendor/arrow-testing` with pyarrow-exported sidecars.

### Shared

- Unified error type and `IO` resource management; keep format modules isolated behind `Columnar` namespaces.

## Acceptance criteria (historical)

- Each format has at least one **value-level** test (not only magic bytes) gated on vendor presence, mirroring Parquet Phase‑0 pattern.
- `Tests/Main.lean` registers real suites; shrink `Placeholder` messages accordingly.

## Key code (historical)

- `Columnar/Avro/Container.lean`, `Columnar/Avro/Schema.lean`, `Columnar/Orc/Reader.lean`, `Columnar/Arrow/IPC.lean`, `Tests/Conformance/InteropFingerprints.lean` (split per format)

## Dependencies (historical)

- **03** compression may overlap for Avro codec blocks.
