#!/usr/bin/env bash
# Emit a minimal JSON report for docs/Conformance.md automation (extend as suites grow).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${ROOT}/docs"
REPORT="${ROOT}/docs/conformance-report.json"
cat >"${REPORT}" <<'JSON'
{
  "generated_by": "scripts/gen-conformance-report.sh",
  "suites": [
    {"id": "parquet-phase0", "note": "run `lake exe tests` with vendor/parquet-testing"},
    {"id": "parquet-phase1", "status": "planned"},
    {"id": "avro", "status": "planned"},
    {"id": "orc", "status": "planned"},
    {"id": "arrow-ipc", "status": "planned"}
  ]
}
JSON
echo "Wrote ${REPORT}"
