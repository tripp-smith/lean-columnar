#!/usr/bin/env bash
# Run isolated mmap scenarios (`Tests/Debug/MmapHarness.lean` via `lake exe mmap_harness`).
# Usage:
#   bash scripts/run-mmap-harness.sh [--force-mmap] [--lldb] [--timeout SEC] -- [args to mmap_harness...]
# Examples:
#   bash scripts/run-mmap-harness.sh --force-mmap -- --scenario ffi --file Tests/fixtures/two_row_groups_plain.parquet
#   bash scripts/run-mmap-harness.sh --lldb --timeout 120 --force-mmap -- --scenario stream --file Tests/fixtures/two_row_groups_plain.parquet
set -euo pipefail
cd "$(dirname "$0")/.."

FORCE_mmap=0
use_lldb=0
timeout_sec=120
extra=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-mmap)
      FORCE_mmap=1
      shift
      ;;
    --lldb)
      use_lldb=1
      shift
      ;;
    --timeout)
      timeout_sec="$2"
      shift 2
      ;;
    --)
      shift
      extra+=("$@")
      break
      ;;
    *)
      extra+=("$1")
      shift
      ;;
  esac
done

if [[ "${FORCE_mmap}" -eq 1 ]]; then
  export COLUMNAR_FORCE_MMAP=1
fi

lake build mmap_harness >/dev/null

bin=".lake/build/bin/mmap_harness"
if [[ ! -x "$bin" ]]; then
  echo "run-mmap-harness: missing executable $bin" >&2
  exit 1
fi

run_lldb() {
  local -a cmd=(lldb --batch -o run -o bt -o quit -- "$bin" "${extra[@]}")
  if command -v timeout >/dev/null 2>&1; then
    exec timeout "${timeout_sec}" "${cmd[@]}"
  elif command -v gtimeout >/dev/null 2>&1; then
    exec gtimeout "${timeout_sec}" "${cmd[@]}"
  else
    echo "run-mmap-harness: no timeout/gtimeout; running lldb without wall-clock limit" >&2
    exec "${cmd[@]}"
  fi
}

if [[ "${use_lldb}" -eq 1 ]]; then
  run_lldb
else
  exec lake exe mmap_harness -- "${extra[@]}"
fi
