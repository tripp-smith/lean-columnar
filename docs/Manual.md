# LeanColumnar manual

## Getting started

1. Install [Elan](https://github.com/leanprover/elan) and check out this repo.
2. `lake build` — builds the `Columnar` library (native codec object is **stubbed by default**).
3. `lake exe tests` — unit tests + optional Parquet conformance when `vendor/parquet-testing` exists.
4. `lake exe bench -- --quick` — writes a placeholder result under `bench/results/`.

## Vendored fixtures

Either add git submodules (see `.gitmodules`) or run:

```bash
bash scripts/fetch-fixtures.sh
```

## Parquet Phase-0 CI gate

With fixtures present, `int32_decimal.parquet` and `int64_decimal.parquet` must decode successfully.
Other Phase-0 files from the plan are attempted; failures are reported as **SKIP** unless
`COLUMNAR_PHASE0_STRICT=1` is set.

## Native codecs

See [FFI.md](FFI.md). Set `COLUMNAR_CODEC=1` at **compile time** for real `libsnappy` / `libzstd` / etc.,
and add matching `-l…` flags to `lakefile.lean` `package columnar` `moreLinkArgs`.

## Roadmap

Implementation follows `spec.md` and the phased plan: Parquet → Avro → ORC → Arrow IPC, each gated
on Apache reference corpora.
