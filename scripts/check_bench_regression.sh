#!/usr/bin/env bash
# Compare bench/results/last-quick.json median-of-means heuristic to an optional baseline.
# Usage:
#   BENCH_BASELINE_JSON=bench/results/baseline-quick.json \
#   BENCH_MAX_REGRESSION_PCT=15 \
#   bash scripts/check_bench_regression.sh
set -euo pipefail
NEW="${NEW_JSON:-bench/results/last-quick.json}"
BASE="${BENCH_BASELINE_JSON:-}"

if [[ ! -f "$NEW" ]]; then
  echo "bench regression: missing $NEW"
  exit 1
fi

if [[ -z "$BASE" || ! -f "$BASE" ]]; then
  echo "bench regression: no baseline (set BENCH_BASELINE_JSON=$BASE); skip"
  exit 0
fi

need_jq () {
  command -v jq >/dev/null 2>&1 || { echo "bench regression: jq required with baseline"; exit 1; }
}

need_jq
new_mean="$(jq -r '.mean_ms // empty' "$NEW")"
base_mean="$(jq -r '.mean_ms // empty' "$BASE")"

if [[ "$new_mean" == "null" || -z "$new_mean" ]]; then
  echo "bench regression: last-quick missing numeric mean_ms; skip"
  exit 0
fi
if [[ "$base_mean" == "null" || -z "$base_mean" ]]; then
  echo "bench regression: baseline missing mean_ms; skip"
  exit 0
fi

pct_env="${BENCH_MAX_REGRESSION_PCT:-25}"
python3 - <<PY
import os, sys
new = float("${new_mean}")
base = float("${base_mean}")
pct = float(os.environ.get("BENCH_MAX_REGRESSION_PCT", "${pct_env}"))
if base <= 0:
    sys.exit(0)
if (new - base) / base <= pct / 100.0:
    sys.exit(0)
sys.exit(1)
PY || {
  echo "bench regression: mean_ms regressed beyond ${pct_env}% ($base_mean → $new_mean)"
  exit 1
}
echo "bench regression: OK (within ${pct_env}%)"
