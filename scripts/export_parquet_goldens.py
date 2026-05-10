#!/usr/bin/env python3
"""Export value sidecars used by Lean `Tests/Conformance/ParquetGoldens`.

Run after `scripts/fetch-fixtures.sh` (writes under Tests/goldens/).

Format per file (newline-separated):
  line 0 : column name
  line 1 : kind (`bool`, `int32`, `int64`, `byte_dec`,
                 `int32_decimal_unscaled`, `int64_decimal_unscaled`)
  remaining: payload rows (decimal unscaled assumes scale 2)
"""
from __future__ import annotations

from pathlib import Path

import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "vendor" / "parquet-testing" / "data"
OUT = ROOT / "Tests" / "goldens"


def write_col(rel: Path, parquet_name: str, col: str, kind: str) -> None:
    t = pq.read_table(DATA / parquet_name)
    c = t.column(col)
    lines = [col, kind]
    if kind == "bool":
        for v in c.to_pylist():
            lines.append("1" if v else "0")
    elif kind == "int32":
        for v in c.to_pylist():
            lines.append(str(int(v)))
    elif kind == "int64":
        for v in c.to_pylist():
            lines.append(str(int(v)))
    elif kind == "byte_dec":
        for v in c.to_pylist():
            lines.append(str(v[0] if len(v) > 0 else 0))
    elif kind == "int32_decimal_unscaled":
        for d in c.to_pylist():
            lines.append(str(int(d * 100)))
    elif kind == "int64_decimal_unscaled":
        for d in c.to_pylist():
            lines.append(str(int(d * 100)))
    else:
        raise ValueError(kind)
    path = OUT / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")
    print("wrote", path)


def main() -> None:
    if not DATA.is_dir():
        raise SystemExit(f"missing {DATA}; run scripts/fetch-fixtures.sh")
    OUT.mkdir(parents=True, exist_ok=True)
    write_col(Path("alltypes_plain__id.txt"), "alltypes_plain.parquet", "id", "int32")
    write_col(Path("alltypes_plain__bool_col.txt"), "alltypes_plain.parquet", "bool_col", "bool")
    write_col(Path("binary__foo.txt"), "binary.parquet", "foo", "byte_dec")
    write_col(Path("int32_decimal__value.txt"), "int32_decimal.parquet", "value", "int32_decimal_unscaled")
    write_col(Path("int64_decimal__value.txt"), "int64_decimal.parquet", "value", "int64_decimal_unscaled")


if __name__ == "__main__":
    main()
