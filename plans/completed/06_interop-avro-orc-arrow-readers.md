# Plan: Avro, ORC, and Arrow IPC — real readers beyond fingerprints

## Status: **Completed** (2026-05-16)

### Delivered

| Area | API / module | Notes |
|------|----------------|-------|
| **Avro OCF** | `readAvroOcf`, `readAvroOcfFromBytes` | [`Columnar/Avro/Container.lean`](../../Columnar/Avro/Container.lean): null, **deflate**, **Snappy** blocks; schema JSON + binary decode to [`Table`](../../Columnar/Table.lean). |
| **Avro vendor** | `Tests/Fixtures.avroVendorSimple` | Gated golden on `vendor/avro/share/test/data/schemas/simple/data.avro` column `text` (`interop_avro_vendor_simple__text.txt`). |
| **ORC** | `readOrcNumberOfRows`, `readOrcPrimitives` | Footer + stripe zlib via raw deflate ([`Columnar/Orc/Compress.lean`](../../Columnar/Orc/Compress.lean), `columnar_zlib_inflate_raw`); stripe footer stream index ([`Columnar/Orc/StripeDecode.lean`](../../Columnar/Orc/StripeDecode.lean)); `TestOrcFile.test1.orc` columns `int1` / `boolean1` + checked-in `interop_orc_int32.orc`. |
| **Arrow IPC** | `readArrowIpcStreamFile`, `readArrowIpcFile` | Stream + **file** (`ARROW1` footer, inline `Block` structs, footer schema field 1) in [`Columnar/Arrow/IPC.lean`](../../Columnar/Arrow/IPC.lean). |
| **Harness / CI** | `Tests/Harness.interopStrict`, `.github/workflows/ci.yml` | Vendor vs checked-in tests split (no early `return`); full `scripts/fetch-fixtures.sh` on conformance jobs; `COLUMNAR_INTEROP_STRICT=1` on native-codecs job. |
| **Goldens** | `scripts/export_interop_goldens.py` | Checked-in fixtures + vendor-gated goldens (`interop_orc_test1__*`, `interop_arrow_int32_file*`, vendor Avro simple). |

### Verification checklist

| Step | Command / expectation |
|------|------------------------|
| Regenerate | `python3 scripts/export_interop_goldens.py` (with `vendor/` present for test1 + vendor Avro goldens). |
| Stub CI | `lake build && lake exe tests` — checked-in interop **OK**; vendor zlib ORC / Snappy Avro **SKIP** with clear messages. |
| Native local | `lake clean && COLUMNAR_CODEC=1 bash scripts/with_native_codecs.sh build tests && bash scripts/with_native_codecs.sh exe tests` — ORC footer + test1 columns **OK**; Snappy Avro **OK** when `-lsnappy` resolves. |
| Native CI | Job `conformance-parquet-native-codecs`: `COLUMNAR_CODEC=1`, `lake clean`, `COLUMNAR_INTEROP_STRICT=1`. |
| macOS | Interop runs before Parquet mmap groups; Arrow IPC runs before ORC zlib decode (avoids heap interaction on some builds). Parquet reader groups still need `COLUMNAR_PARQUET_READER_OSX=1`. |

### Key modules

- `Columnar/Avro/*`, `Columnar/Orc/{FooterProto,Compress,TypeParse,StripeDecode,RleByte,RleV2,Reader}.lean`, `Columnar/Arrow/IPC.lean`
- `Tests/Conformance/{Avro,Orc,Arrow}Interop.lean`, `Tests/GoldenFmt.lean` (utf8 / bool sidecar lines)
- `c/columnar_codec.c` (`columnar_zlib_inflate_raw`), `lakefile.lean` (`COLUMNAR_CODEC` + `meta if` codec link on `tests`)

---

## Objective (historical)

Progress from **magic-byte / framing smoke tests** to minimal **record/stream decoding** aligned with **spec.md** phased multi-format support.
