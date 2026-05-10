#!/usr/bin/env python3
"""Emit Tests/fixtures/codecs/*.bin for Codec contract tests.

Requires (pip): python-snappy, zstandard, brotli, lz4
Run from repo root: python3 scripts/gen_codec_contract_fixtures.py

The gzip Parquet codec maps to zlib `uncompress` in c/columnar_codec.c; fixtures use zlib.compress.
LZ4 raw fixtures use lz4.block.compress(..., store_size=False) to match LZ4_decompress_safe.
"""
from __future__ import annotations

import pathlib
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "Tests" / "fixtures" / "codecs"

PLAINTEXT = b"columnar_codec_contract_plaintext_v1\n"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "plaintext.bin").write_bytes(PLAINTEXT)

    import snappy

    (OUT / "snappy.bin").write_bytes(snappy.compress(PLAINTEXT))

    (OUT / "zlib.bin").write_bytes(zlib.compress(PLAINTEXT))

    import zstandard as zstd

    (OUT / "zstd.bin").write_bytes(zstd.ZstdCompressor().compress(PLAINTEXT))

    import brotli

    (OUT / "brotli.bin").write_bytes(brotli.compress(PLAINTEXT))

    import lz4.block

    (OUT / "lz4_raw.bin").write_bytes(lz4.block.compress(PLAINTEXT, store_size=False))

    print(f"Wrote fixtures under {OUT} (plaintext bytes = {len(PLAINTEXT)})")


if __name__ == "__main__":
    main()
