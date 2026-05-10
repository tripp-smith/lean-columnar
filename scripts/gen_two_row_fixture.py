#!/usr/bin/env python3
"""Emit `Tests/fixtures/two_row_groups_plain.parquet` (two row groups, UNCOMPRESSED, INT32 «x»)."""
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq


def main() -> None:
    out = Path(__file__).resolve().parents[1] / "Tests" / "fixtures" / "two_row_groups_plain.parquet"
    out.parent.mkdir(parents=True, exist_ok=True)
    t = pa.table({"x": pa.array(list(range(24)), pa.int32())})
    pq.write_table(t, out, row_group_size=12, compression="NONE")
    f = pq.ParquetFile(out)
    assert f.num_row_groups == 2, (out, f.num_row_groups)
    print("wrote", out)


if __name__ == "__main__":
    main()
