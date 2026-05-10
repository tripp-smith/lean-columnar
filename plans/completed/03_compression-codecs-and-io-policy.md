# Plan: Compression codecs and default I/O policy

## Status: **Completed** (2026-05-03)

Delivered against this plan:

| Requirement | Outcome |
|-------------|---------|
| FFI build matrix | [`docs/FFI.md`](../../docs/FFI.md) per-OS install/link notes; [`lakefile.lean`](../../lakefile.lean) `moreLinkArgs` via `lake -Kcolumnar.codec=1`; `COLUMNAR_CODEC=1` for `columnar_codec.c`; [`scripts/with_native_codecs.sh`](../../scripts/with_native_codecs.sh). |
| Contract tests | [`Tests/fixtures/codecs/`](../../Tests/fixtures/codecs/) blobs + [`scripts/gen_codec_contract_fixtures.py`](../../scripts/gen_codec_contract_fixtures.py); [`Tests/Unit/CodecContract.lean`](../../Tests/Unit/CodecContract.lean) wired from [`Tests/Main.lean`](../../Tests/Main.lean). |
| Errors & UX | [`c/columnar_codec.c`](../../c/columnar_codec.c) — uniform `columnar: …` strings naming codec + build/link hints. |
| CI + acceptance | Workflow job **`conformance-parquet-native-codecs`** (Ubuntu, `-dev` packages, `COLUMNAR_CODEC=1`, `lake build|exe … -Kcolumnar.codec=1`, optional `COLUMNAR_ENCODING_TIER_STRICT=1`); documented in [`docs/Conformance.md`](../../docs/Conformance.md). Stub default CI unchanged. |

**Optional / deferred** (per plan): pure-Lean or bundled Snappy — policy-only; noted under **Future work** in [`docs/FFI.md`](../../docs/FFI.md).

**Verification** (local): `lake build && lake exe tests` (stubs); `COLUMNAR_CODEC=1 lake build -Kcolumnar.codec=1 && COLUMNAR_CODEC=1 lake exe tests -Kcolumnar.codec=1` (native).

---

## Objective (historical)

Align with **spec.md** §3 (Snappy, Zstd, Gzip, Brotli, LZ4): reliable decompression in CI and clear operator story when system libraries are absent.

## Implementation requirements (historical)

### FFI layer

- **Build matrix**: Document and test `COLUMNAR_CODEC=1` with `lakefile.lean` `moreLinkArgs` per OS (Linux packages, macOS Homebrew paths optional).
- **Contract tests**: Small checked-in compressed blobs per codec verifying `Codec.decompress` round-trip to known plaintext (reduces reliance on large fixtures).

### Fallbacks (optional milestone)

- Pure-Lean or bundled **Snappy** (minimum) decompress path for CI without system libs, even if slower—policy decision: stub vs partial vs full.

### Errors & UX

- Uniform error strings: name codec, suggest env flag + link line; never silent failure in strict modes.

## Acceptance criteria (historical)

- CI job variant (documented in `docs/Conformance.md`) passes a **defined** compressed corpus subset with `COLUMNAR_CODEC=1`.
- Default stub build still passes `lake exe tests` with explicit SKIP reasons unchanged or tightened (no flaky crashes).

## Key code

- `c/columnar_codec.c`, `Columnar/Compression/Codec.lean`, `lakefile.lean`, `docs/FFI.md`, `docs/Conformance.md`

## Dependencies

- **Consumes**: stable Parquet read/write layers ([01](01_parquet-reader-full-coverage.md), [02](02_parquet-writer-and-roundtrip.md)) so compressed fixtures and round-trips stay meaningful.
- **Feeds**: reader coverage on Snappy/Zstd/GZIP/Brotli/LZ4_RAW column chunks (`COLUMNAR_CODEC=1` + `lake -Kcolumnar.codec=1`, see [`docs/FFI.md`](../../docs/FFI.md)); writer column compression remains a separate milestone (encode FFI + `Writer/File`).
