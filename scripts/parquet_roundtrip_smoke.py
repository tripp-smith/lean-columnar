#!/usr/bin/env python3
"""
Verify `lake exe writer_roundtrip` output.

Prefers **PyArrow** when it can read the file; falls back to **pandas + fastparquet**
(PyArrow’s Thrift parser is stricter than fastparquet’s for our FileMetaData wire format).

Requires: pandas, fastparquet; optional: pyarrow (recommended). Skips if
COLUMNAR_SKIP_PYARROW=1 (historical name) or deps missing.
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run_writer(tmp: Path, extra_env: dict[str, str]) -> None:
    env = dict(os.environ)
    env["COLUMNAR_WRITER_PATH"] = str(tmp)
    env.update(extra_env)
    subprocess.run(
        ["lake", "exe", "writer_roundtrip"],
        cwd=ROOT,
        check=True,
        env=env,
    )


def read_parquet_df(path: Path):
    """Return a pandas DataFrame; try PyArrow first, then fastparquet."""
    import pandas as pd

    try:
        import pyarrow.parquet as pq

        try:
            return pq.read_table(str(path)).to_pandas()
        except OSError as e:
            if "thrift" in str(e).lower() or "deserialize" in str(e).lower():
                return pd.read_parquet(str(path), engine="fastparquet")
            raise
    except ImportError:
        return pd.read_parquet(str(path), engine="fastparquet")


def verify_int32_seq(tmp: Path, rows: int) -> None:
    df = read_parquet_df(tmp)
    assert list(df.columns) == ["x"]
    vals = df["x"].tolist()
    assert vals == list(range(rows)), vals


def verify_row_group_count(tmp: Path, expected_rg: int) -> None:
    """Prefer PyArrow; fall back to fastparquet on Thrift parse errors (Lean footer variance)."""
    n: int
    try:
        import pyarrow.parquet as pq

        try:
            n = pq.ParquetFile(str(tmp)).metadata.num_row_groups
        except OSError as e:
            err = str(e).lower()
            if "thrift" in err or "deserialize" in err:
                import fastparquet

                fp = fastparquet.ParquetFile(str(tmp))
                n = len(fp.row_groups)
            else:
                raise
    except ImportError:
        import fastparquet

        fp = fastparquet.ParquetFile(str(tmp))
        n = len(fp.row_groups)
    assert n == expected_rg, (n, expected_rg)


def verify_mixed(tmp: Path) -> None:
    df = read_parquet_df(tmp)
    assert list(df.columns) == ["b", "i", "f"]
    assert df["b"].tolist() == [True]
    assert df["i"].tolist() == [7]
    assert abs(float(df["f"].iloc[0]) - 3.0) < 1e-9


def verify_nullable(tmp: Path) -> None:
    df = read_parquet_df(tmp)
    assert list(df.columns) == ["n"]
    assert df["n"].isna().tolist() == [True, False]
    assert int(df["n"].iloc[1]) == 99


def main() -> int:
    if os.environ.get("COLUMNAR_SKIP_PYARROW") == "1":
        print("SKIP: COLUMNAR_SKIP_PYARROW=1")
        return 0
    try:
        import pandas as pd  # noqa: F401
        import fastparquet  # noqa: F401
    except ImportError:
        print("SKIP: pandas and/or fastparquet not installed")
        return 0

    rows = int(os.environ.get("COLUMNAR_WRITER_ROWS_DEMO", "7"))

    with tempfile.NamedTemporaryFile(suffix=".parquet", delete=False) as f:
        p_seq = Path(f.name)
    try:
        run_writer(p_seq, {"COLUMNAR_WRITER_ROWS": str(rows)})
        verify_int32_seq(p_seq, rows)
        print(f"OK: verified INT32 0..{rows - 1} ({p_seq.name})")
    finally:
        if p_seq.exists():
            p_seq.unlink(missing_ok=True)

    rg_demo_rows = int(os.environ.get("COLUMNAR_WRITER_RG_DEMO_ROWS", "10"))
    rg_demo_size = int(os.environ.get("COLUMNAR_WRITER_RG_DEMO_SIZE", "5"))
    expected_rg = (rg_demo_rows + rg_demo_size - 1) // rg_demo_size
    with tempfile.NamedTemporaryFile(suffix=".parquet", delete=False) as f:
        p_rg = Path(f.name)
    try:
        run_writer(
            p_rg,
            {
                "COLUMNAR_WRITER_ROWS": str(rg_demo_rows),
                "COLUMNAR_WRITER_RG_SIZE": str(rg_demo_size),
            },
        )
        verify_int32_seq(p_rg, rg_demo_rows)
        verify_row_group_count(p_rg, expected_rg)
        print(
            f"OK: verified multi row-group INT32 ({rg_demo_rows} rows, "
            f"rowsPerRowGroup={rg_demo_size}, num_row_groups={expected_rg})"
        )
    finally:
        if p_rg.exists():
            p_rg.unlink(missing_ok=True)

    with tempfile.NamedTemporaryFile(suffix=".parquet", delete=False) as f:
        p_mixed = Path(f.name)
    try:
        run_writer(p_mixed, {"COLUMNAR_WRITER_SCHEMA": "mixed"})
        verify_mixed(p_mixed)
        print(f"OK: verified mixed primitives ({p_mixed.name})")
    finally:
        if p_mixed.exists():
            p_mixed.unlink(missing_ok=True)

    with tempfile.NamedTemporaryFile(suffix=".parquet", delete=False) as f:
        p_null = Path(f.name)
    try:
        run_writer(p_null, {"COLUMNAR_WRITER_SCHEMA": "nullable"})
        verify_nullable(p_null)
        print(f"OK: verified nullable INT64 ({p_null.name})")
    finally:
        if p_null.exists():
            p_null.unlink(missing_ok=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
