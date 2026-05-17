#!/usr/bin/env python3
"""Reference timings for lean-columnar bench (PyArrow / fastavro).

Prints one JSON line to stdout:
  {"elapsed_ms_total": N, "mean_ms": F, "row_count": R}

Requires: pyarrow (all formats); fastavro is optional fallback for Avro only.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path


def read_once(fmt: str, path: Path) -> int:
    if fmt == "parquet":
        import pyarrow.parquet as pq

        return pq.read_table(path).num_rows
    if fmt == "avro":
        from fastavro import reader as avro_reader

        with path.open("rb") as f:
            return sum(1 for _ in avro_reader(f))
    if fmt == "orc":
        import pyarrow.orc as orc

        return orc.ORCFile(path).read().num_rows
    if fmt == "arrow_stream":
        import pyarrow as pa

        with path.open("rb") as f:
            reader = pa.ipc.open_stream(f)
            return sum(b.num_rows for b in reader)
    if fmt == "arrow_file":
        import pyarrow as pa

        with pa.ipc.open_file(path.open("rb")) as reader:
            return sum(reader.get_batch(i).num_rows for i in range(reader.num_record_batches))
    raise ValueError(f"unknown format: {fmt}")


def main() -> int:
    p = argparse.ArgumentParser(description="lean-columnar bench reference reader")
    p.add_argument("--format", required=True, choices=["parquet", "avro", "orc", "arrow_stream", "arrow_file"])
    p.add_argument("--path", required=True, type=Path)
    p.add_argument("--iters", required=True, type=int)
    args = p.parse_args()
    if not args.path.is_file():
        print(f"missing file: {args.path}", file=sys.stderr)
        return 2
    if args.iters < 1:
        print("iters must be >= 1", file=sys.stderr)
        return 2
    rows = 0
    t0 = time.perf_counter()
    for _ in range(args.iters):
        rows = read_once(args.format, args.path)
    elapsed_ms = int((time.perf_counter() - t0) * 1000)
    mean_ms = elapsed_ms / args.iters
    out = {
        "elapsed_ms_total": elapsed_ms,
        "mean_ms_thousandths": int(round(mean_ms * 1000)),
        "row_count": rows,
    }
    print(json.dumps(out), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
