# Conformance

Official Apache corpora are tracked under `vendor/` (submodules or `scripts/fetch-fixtures.sh`).

## Automation

- `lake exe tests` — Lean-side checks + Parquet Phase-0 subset (see `Tests/Conformance/`).
- `bash scripts/gen-conformance-report.sh` — writes `docs/conformance-report.json` (stub grid).
- Future: Arrow IPC goldens, Avro interop matrix, ORC `orc-tools` cross-checks (see plan).

## Environment flags

| Variable | Effect |
|----------|--------|
| `COLUMNAR_CODEC=1` | Compile C codec shims against system headers. |
| `COLUMNAR_PHASE0_STRICT=1` | Require every Phase-0 Parquet file to pass (not only `mustPass`). |

## CI

GitHub Actions runs `leanprover/lean-action` (build + `lake test`), `lake exe bench -- --quick`,
and a second job that fetches `parquet-testing` then runs the test executable again.
