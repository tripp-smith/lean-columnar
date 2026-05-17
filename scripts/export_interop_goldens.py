#!/usr/bin/env python3
"""Generate checked-in interop fixtures + golden sidecars for Lean conformance tests.

Requires: `pip install fastavro pyarrow` (pyorc optional for ORC row-count cross-check).

Writes:
  Tests/fixtures/interop_minimal.avro — tiny OCF (null codec)
  Tests/fixtures/interop_minimal_snappy.avro — same rows, Snappy OCF blocks
  Tests/goldens/interop_avro_minimal__id.txt — GoldenFmt int64 column
  Tests/goldens/interop_avro_snappy__id.txt — same golden as minimal (id column)
  Tests/fixtures/interop_orc_int32.orc — single-stripe uncompressed int32 column x
  Tests/goldens/interop_orc_int32__x.txt — GoldenFmt int32 column
  Tests/fixtures/interop_arrow_int32_stream.arrow — IPC stream schema + one RecordBatch
  Tests/goldens/interop_arrow_int32_stream__x.txt — GoldenFmt int32 column
  Tests/goldens/interop_orc_test1_rows.txt — single line = footer numberOfRows (decimal)
  Tests/goldens/interop_arrow_schema_v6_messages.txt — single line = IPC stream message count
"""
from __future__ import annotations

import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "Tests" / "fixtures"
OUT = ROOT / "Tests" / "goldens"


def write_avro_minimal() -> None:
    import fastavro

    FIX.mkdir(parents=True, exist_ok=True)
    schema = {
        "type": "record",
        "name": "InteropRow",
        "fields": [
            {"name": "id", "type": "long"},
            {"name": "flag", "type": "boolean"},
        ],
    }
    records = [{"id": 7, "flag": True}, {"id": 42, "flag": False}]
    path = FIX / "interop_minimal.avro"
    with path.open("wb") as fo:
        fastavro.writer(fo, schema, records)
    OUT.mkdir(parents=True, exist_ok=True)
    g = OUT / "interop_avro_minimal__id.txt"
    g.write_text("id\nint64\n7\n42\n")
    print("wrote", path, g)


def write_avro_snappy() -> None:
    import fastavro

    FIX.mkdir(parents=True, exist_ok=True)
    schema = {
        "type": "record",
        "name": "InteropRow",
        "fields": [
            {"name": "id", "type": "long"},
            {"name": "flag", "type": "boolean"},
        ],
    }
    records = [{"id": 7, "flag": True}, {"id": 42, "flag": False}]
    path = FIX / "interop_minimal_snappy.avro"
    with path.open("wb") as fo:
        fastavro.writer(fo, schema, records, codec="snappy")
    OUT.mkdir(parents=True, exist_ok=True)
    g = OUT / "interop_avro_snappy__id.txt"
    g.write_text("id\nint64\n7\n42\n")
    print("wrote", path, g)


def orc_footer_rows(path: Path) -> int:
    """Parse ORC tail without pyorc: read PostScript.footerLength + zlib Footer.numberOfRows."""
    data = path.read_bytes()
    ps_len = data[-1]
    ps_start = len(data) - 1 - ps_len
    postscript = data[ps_start : ps_start + ps_len]

    def uvarint(buf: bytes, i: int) -> tuple[int, int]:
        x = 0
        s = 0
        while True:
            b = buf[i]
            i += 1
            x |= (b & 0x7F) << s
            if (b & 0x80) == 0:
                return x, i
            s += 7

    # Walk protobuf fields in postscript for tag 1 (footer length) and 2 (compression)
    pos = 0
    footer_len = None
    compression = 0
    while pos < len(postscript):
        tag, pos = uvarint(postscript, pos)
        field = tag >> 3
        wtype = tag & 7
        if wtype == 0:
            val, pos = uvarint(postscript, pos)
            if field == 1:
                footer_len = val
            elif field == 2:
                compression = val
        elif wtype == 2:
            ln, pos = uvarint(postscript, pos)
            pos += ln
        else:
            raise RuntimeError(f"unsupported wire type {wtype}")

    if footer_len is None:
        raise RuntimeError("missing footerLength")

    footer_start = ps_start - footer_len
    footer_blob = data[footer_start : footer_start + footer_len]

    if compression == 1:
        import zlib

        footer_plain = zlib.decompress(footer_blob)
    elif compression == 0:
        footer_plain = footer_blob
    else:
        raise RuntimeError(f"compression {compression} not handled in exporter")

    # Footer protobuf: field 6 = numberOfRows (varint)
    pos = 0
    while pos < len(footer_plain):
        tag, pos = uvarint(footer_plain, pos)
        field = tag >> 3
        wtype = tag & 7
        if wtype == 0:
            val, pos = uvarint(footer_plain, pos)
            if field == 6:
                return int(val)
        elif wtype == 2:
            ln, pos = uvarint(footer_plain, pos)
            pos += ln
        elif wtype == 5:
            pos += 4
        elif wtype == 1:
            pos += 8
        else:
            raise RuntimeError(f"footer wire type {wtype}")
    raise RuntimeError("numberOfRows not found")


def write_orc_golden() -> None:
    p = ROOT / "vendor" / "orc" / "examples" / "TestOrcFile.test1.orc"
    if not p.is_file():
        print("skip ORC golden (vendor/orc missing)")
        return
    import pyarrow.orc as orc

    n = int(orc.ORCFile(str(p)).nrows)
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / "interop_orc_test1_rows.txt"
    dst.write_text(f"{n}\n")
    print("wrote", dst, "rows=", n)
    tbl = orc.ORCFile(str(p)).read()
    for col in ("int1", "boolean1"):
        if col not in tbl.column_names:
            print("skip ORC column golden", col)
            continue
        py_vals = tbl.column(col).to_pylist()
        kind = "int32" if col == "int1" else "bool"
        lines = [col, kind] + [str(v).lower() if kind == "bool" else str(v) for v in py_vals]
        g = OUT / f"interop_orc_test1__{col}.txt"
        g.write_text("\n".join(lines) + "\n")
        print("wrote", g)
    tbl = orc.ORCFile(str(p)).read()
    for col in ("int1", "boolean1"):
        if col not in tbl.column_names:
            print("skip ORC column golden", col)
            continue
        py_vals = tbl.column(col).to_pylist()
        kind = "int32" if col == "int1" else "bool"
        lines = [col, kind] + [str(v).lower() if kind == "bool" else str(v) for v in py_vals]
        gpath = OUT / f"interop_orc_test1__{col}.txt"
        gpath.write_text("\n".join(lines) + "\n")
        print("wrote", gpath)


def arrow_ipc_message_count(data: bytes) -> int:
    """Match Lean `ipcStreamMessageCount`: continuation + metadata + padded body + skip EOS (mlen==0)."""

    def message_body_length(meta: bytes) -> int:
        root = struct.unpack_from("<I", meta, 0)[0]
        obj = root
        vt_off = struct.unpack_from("<i", meta, obj)[0]
        vt = obj - vt_off
        vtsize = struct.unpack_from("<H", meta, vt)[0]
        nslots = (vtsize - 4) // 2
        offs = [struct.unpack_from("<H", meta, vt + 4 + 2 * i) for i in range(nslots)]
        if len(offs) <= 3 or not offs[3]:
            return 0
        return int(struct.unpack_from("<q", meta, obj + offs[3])[0])

    pos = 0
    count = 0
    while pos < len(data):
        if pos + 8 > len(data):
            break
        cont = struct.unpack_from("<I", data, pos)[0]
        p0 = pos + 4 if cont == 0xFFFFFFFF else pos
        mlen = struct.unpack_from("<i", data, p0)[0]
        if mlen < 0:
            raise RuntimeError("negative metadata length")
        if mlen == 0:
            break
        meta_start = p0 + 4
        meta = data[meta_start : meta_start + mlen]
        body_len = message_body_length(meta)
        after_meta = meta_start + mlen
        body_off = (after_meta + 7) // 8 * 8
        pos = body_off + body_len
        count += 1
    return count


def write_arrow_golden() -> None:
    p = ROOT / "vendor" / "arrow-testing" / "data" / "forward-compatibility" / "schema_v6.arrow"
    if not p.is_file():
        print("skip Arrow golden (vendor/arrow-testing missing)")
        return
    n = arrow_ipc_message_count(p.read_bytes())
    OUT.mkdir(parents=True, exist_ok=True)
    dst = OUT / "interop_arrow_schema_v6_messages.txt"
    dst.write_text(f"{n}\n")
    print("wrote", dst, "messages=", n)


def write_orc_int32_fixture() -> None:
    import pyarrow as pa

    FIX.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    tbl = pa.table({"x": pa.array([7, 42], type=pa.int32())})
    path = FIX / "interop_orc_int32.orc"
    with pa.OSFile(str(path), "wb") as sink:
        with pa.orc.ORCWriter(sink) as writer:
            writer.write(tbl)
    g = OUT / "interop_orc_int32__x.txt"
    g.write_text("x\nint32\n7\n42\n")
    print("wrote", path, g)


def write_arrow_int32_file_fixture() -> None:
    import pyarrow as pa
    import pyarrow.ipc as ipc

    FIX.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    schema = pa.schema([("x", pa.int32())])
    batch = pa.record_batch([pa.array([7, 42], type=pa.int32())], schema=schema)
    path = FIX / "interop_arrow_int32_file.arrow"
    with pa.OSFile(str(path), "wb") as sink:
        with ipc.new_file(sink, schema) as writer:
            writer.write(batch)
    g = OUT / "interop_arrow_int32_file__x.txt"
    g.write_text("x\nint32\n7\n42\n")
    print("wrote", path, g)


def write_avro_vendor_golden() -> None:
    p = ROOT / "vendor" / "avro" / "share" / "test" / "data" / "schemas" / "simple" / "data.avro"
    if not p.is_file():
        print("skip Avro vendor golden (vendor/avro missing)")
        return
    import fastavro

    OUT.mkdir(parents=True, exist_ok=True)
    with p.open("rb") as fo:
        rows = list(fastavro.reader(fo))
    if not rows:
        print("skip Avro vendor golden (empty data.avro)")
        return
    col = "text"
    vals = [r[col] for r in rows[:3]]
    lines = [col, "utf8"] + vals
    g = OUT / "interop_avro_vendor_simple__text.txt"
    g.write_text("\n".join(lines) + "\n")
    print("wrote", g, "col=", col)


def write_arrow_int32_stream_fixture() -> None:
    import pyarrow as pa
    import pyarrow.ipc as ipc

    FIX.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    schema = pa.schema([("x", pa.int32())])
    batch = pa.record_batch([pa.array([7, 42], type=pa.int32())], schema=schema)
    sink = pa.BufferOutputStream()
    with ipc.new_stream(sink, schema) as writer:
        writer.write_batch(batch)
    path = FIX / "interop_arrow_int32_stream.arrow"
    path.write_bytes(sink.getvalue().to_pybytes())
    g = OUT / "interop_arrow_int32_stream__x.txt"
    g.write_text("x\nint32\n7\n42\n")
    print("wrote", path, g)


def main() -> None:
    write_avro_minimal()
    write_avro_snappy()
    write_avro_vendor_golden()
    write_orc_golden()
    write_orc_int32_fixture()
    write_arrow_golden()
    write_arrow_int32_stream_fixture()
    write_arrow_int32_file_fixture()


if __name__ == "__main__":
    main()
