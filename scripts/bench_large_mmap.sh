#!/usr/bin/env bash
# Generate a multi-row-group INT32 Parquet file with `lake exe writer_roundtrip`, then run `lake exe bench`
# comparing readParquet vs readParquetMmap. Record RSS separately with `/usr/bin/time -v` (Linux) or `time -l` (macOS).
#
# Env overrides:
#   COLUMNAR_BENCH_TMP   directory for generated file (default /tmp)
#   COLUMNAR_BENCH_GEN_ROWS      row count (default 5000000)
#   COLUMNAR_BENCH_GEN_RG        rows per row group (default 500000)
#   COLUMNAR_FORCE_MMAP=1        on macOS, use native mmap in mmapOpenTry (optional)
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="${COLUMNAR_BENCH_TMP:-/tmp}"
ROWS="${COLUMNAR_BENCH_GEN_ROWS:-5000000}"
RG="${COLUMNAR_BENCH_GEN_RG:-500000}"
OUT="${TMP}/columnar_mmap_bench.parquet"

echo "bench_large_mmap: writing ${OUT} (${ROWS} rows, rowsPerRowGroup=${RG})..."
COLUMNAR_WRITER_PATH="$OUT" COLUMNAR_WRITER_ROWS="$ROWS" COLUMNAR_WRITER_RG_SIZE="$RG" lake exe writer_roundtrip

echo "bench_large_mmap: timing readParquet vs readParquetMmap (LARGE=1 → 1 iteration by default)..."
COLUMNAR_BENCH_FILE="$OUT" COLUMNAR_BENCH_LARGE=1 COLUMNAR_BENCH_MMAP=1 lake exe bench

echo "bench_large_mmap: results in bench/results/last-quick.json — for RSS run e.g."
echo "  /usr/bin/time -v lake exe bench   # with same COLUMNAR_* env as above"
