# Native compression (FFI)

`c/columnar_codec.c` exposes decompress entry points used from Lean via `@[extern …]`, and (on
POSIX) the `columnar_mmap_*` symbols used by `Columnar.Core.MMap` for read-only file mapping.

## Default: stubs

Unless `COLUMNAR_CODEC=1` is set in the environment when Lake compiles `columnar_codec.c`, **no**
system codec headers are included and every entry point returns a Lean `IO` user error with a
message naming the codec (see contract tests in `Tests/Unit/CodecContract.lean`). This keeps
`lake build` portable (including minimal CI images).

## Enabling system libraries

You need **both**:

1. **`COLUMNAR_CODEC=1`** when Lake compiles `columnar_codec.c` so the C file is built with
   `-DCOLUMNAR_WITH_SYSTEM_CODECS` and system headers are included.
2. **`lake … -Kcolumnar.codec=1`** so the root package’s `moreLinkArgs` link `-lsnappy`, `-lzstd`,
   `-lz`, `-lbrotlidec`, and `-llz4` (see [`lakefile.lean`](../lakefile.lean)).

Convenience wrapper (sets `COLUMNAR_CODEC` and passes `-Kcolumnar.codec=1`):

```bash
bash scripts/with_native_codecs.sh build
bash scripts/with_native_codecs.sh exe tests
COLUMNAR_CODEC=1 bash scripts/with_native_codecs.sh build bench
```

### `tests` and `bench` link model

[`lakefile.lean`](../lakefile.lean) uses `meta if columnarNativeCodecsPkg` (driven by `COLUMNAR_CODEC=1` at Lake load) for **`lake exe tests`** and **`lake exe bench`**:

- **Native:** `columnarCodecLinkSearchPaths` plus `-lsnappy`, `-lzstd`, `-lz`, `-lbrotlidec`, `-llz4` (macOS adds SDK and Homebrew `-L` paths under `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib`, `/opt/homebrew/lib`, …).
- **Stub:** `columnarZlibOnlyLinkArgs` — zlib only (ORC raw deflate via `columnar_zlib_inflate_raw`); Snappy/Zstd/Brotli/LZ4 remain stubbed in C.

After changing codec settings, run `lake clean` then rebuild so `columnar_codec.o` and executables
pick up the new flags.

### ORC zlib (raw deflate)

ORC stripe payloads use a **3-byte little-endian original length** prefix followed by **raw deflate** (`columnar_zlib_inflate_raw` with `inflateInit2(-15)`), not the zlib `uncompress` wrapper used for Parquet GZIP pages.

### OS matrix

| OS | Install | Include / link hints |
|----|---------|-------------------------|
| Debian / Ubuntu | `sudo apt-get install libsnappy-dev libzstd-dev zlib1g-dev libbrotli-dev liblz4-dev` | Usually none; pkg-config / default `/usr/lib` works. |
| macOS (Homebrew) | `brew install snappy zstd xz brotli lz4` | If `cc` cannot find headers, extend the `columnar_codec_o` compile flags in [`lakefile.lean`](../lakefile.lean) with e.g. `-I/opt/homebrew/include` (Apple Silicon) or `-I/usr/local/include`, and add `-L/opt/homebrew/lib` / `-L/usr/local/lib` only if the linker cannot resolve `-lsnappy` etc. |
| Windows | vcpkg or conda | Pass matching `-I` / `-L` (or MSVC equivalents) on the `columnar_codec_o` target and ensure `moreLinkArgs` can find the `.lib` files. |

## Contract fixtures

Small checked-in blobs under `Tests/fixtures/codecs/` verify each codec without large corpora.
Regenerate after changing the canonical plaintext:

```bash
pip install python-snappy zstandard brotli lz4  # plus deps for snappy’s native lib
python3 scripts/gen_codec_contract_fixtures.py
```

The gzip / Parquet `GZIP` codec path uses **zlib** `uncompress` in C; generated files are named
`zlib.bin` and are exercised as `CodecId.gzip`.

## Future work (optional)

A **pure-Lean or bundled Snappy** (or other codec) decompress path would let CI exercise compressed
pages without system `-dev` packages—policy choice among stub-only, partial, or full
implementations. Until then, the default stub build stays portable; native behavior requires the
steps above.
