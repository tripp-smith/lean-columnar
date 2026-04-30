# lean-columnar

High-performance, zero-copy-oriented columnar formats for **Lean 4**: Parquet (in progress), then
Avro, ORC, and Arrow IPC per [`spec.md`](spec.md).

## Quick start

```bash
lake build
lake exe tests
lake exe bench -- --quick
```

Optional Apache reference data:

```bash
bash scripts/fetch-fixtures.sh   # or: git submodule update --init
```

## Docs

- [`docs/Manual.md`](docs/Manual.md) — usage and flags  
- [`docs/FFI.md`](docs/FFI.md) — native codec build  
- [`docs/Conformance.md`](docs/Conformance.md) — test corpora and CI  

## Status

Parquet reader MVP is underway (PLAIN + definition levels for a subset of `parquet-testing`).
Other modules are staged under `Columnar/Avro`, `Columnar/Orc`, and `Columnar/Arrow`.
