#!/usr/bin/env bash
# Copy the latest quick bench JSON to the optional regression baseline.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/bench/results/last-quick.json}"
DST="$ROOT/bench/results/baseline-quick.json"
if [[ ! -f "$SRC" ]]; then
  echo "capture_bench_baseline: missing $SRC (run lake exe bench first)"
  exit 1
fi
mkdir -p "$(dirname "$DST")"
cp "$SRC" "$DST"
echo "Captured baseline → $DST"
echo "Commit bench/results/baseline-quick.json when the regression threshold is intentional."
