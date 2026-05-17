#!/usr/bin/env bash
# Compare bench/results/last-quick.json per-workload lean_mean_ms to an optional baseline.
# Usage:
#   BENCH_BASELINE_JSON=bench/results/baseline-quick.json \
#   BENCH_MAX_REGRESSION_PCT=25 \
#   bash scripts/check_bench_regression.sh
set -euo pipefail
NEW="${NEW_JSON:-bench/results/last-quick.json}"
BASE="${BENCH_BASELINE_JSON:-}"
PCT="${BENCH_MAX_REGRESSION_PCT:-25}"
FILTER="${BENCH_WORKLOAD_IDS:-}"

if [[ ! -f "$NEW" ]]; then
  echo "bench regression: missing $NEW"
  exit 1
fi

if [[ -z "$BASE" || ! -f "$BASE" ]]; then
  echo "bench regression: no baseline (set BENCH_BASELINE_JSON); skip"
  echo "bench regression: first run? bash scripts/capture_bench_baseline.sh after lake exe bench"
  exit 0
fi

need_jq () {
  command -v jq >/dev/null 2>&1 || { echo "bench regression: jq required with baseline"; exit 1; }
}
need_jq

# Legacy single-workload JSON (one release backward compat)
if ! jq -e 'has("workloads")' "$NEW" >/dev/null 2>&1; then
  new_mean="$(jq -r '.mean_ms // empty' "$NEW")"
  base_mean="$(jq -r '.mean_ms // empty' "$BASE")"
  if [[ -n "$new_mean" && -n "$base_mean" && "$new_mean" != "null" && "$base_mean" != "null" ]]; then
    python3 - <<PY
import os, sys
new = float("${new_mean}")
base = float("${base_mean}")
pct = float(os.environ.get("BENCH_MAX_REGRESSION_PCT", "${PCT}"))
if base <= 0 or (new - base) / base <= pct / 100.0:
    sys.exit(0)
sys.exit(1)
PY
    rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "bench regression: legacy mean_ms regressed beyond ${PCT}% ($base_mean → $new_mean)"
      exit 1
    fi
    echo "bench regression: OK (legacy parquet_binary mean within ${PCT}%)"
    exit 0
  fi
fi

ids="$(jq -r '.workloads[].id' "$BASE")"
if [[ -n "$FILTER" ]]; then
  filtered=""
  IFS=',' read -ra want <<< "$FILTER"
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    for w in "${want[@]}"; do
      w="$(echo "$w" | xargs)"
      if [[ "$w" == "$id" ]]; then
        filtered+="$id"$'\n'
        break
      fi
    done
  done <<< "$ids"
  ids="$filtered"
fi

failed=0
while IFS= read -r id; do
  [[ -z "$id" ]] && continue
  new_mean="$(jq -r --arg id "$id" '.workloads[] | select(.id==$id) | .lean_mean_ms // empty' "$NEW")"
  base_mean="$(jq -r --arg id "$id" '.workloads[] | select(.id==$id) | .lean_mean_ms // empty' "$BASE")"
  if [[ -z "$new_mean" || "$new_mean" == "null" ]]; then
    echo "bench regression: $id — skip (no new lean_mean_ms)"
    continue
  fi
  if [[ -z "$base_mean" || "$base_mean" == "null" ]]; then
    echo "bench regression: $id — skip (no baseline lean_mean_ms)"
    continue
  fi
  if python3 - <<PY
import sys
new = float("${new_mean}")
base = float("${base_mean}")
pct = float("${PCT}")
if base <= 0:
    sys.exit(0)
if (new - base) / base <= pct / 100.0:
    sys.exit(0)
sys.exit(1)
PY
  then
    echo "bench regression: $id OK ($base_mean → $new_mean)"
  else
    echo "bench regression: $id regressed beyond ${PCT}% ($base_mean → $new_mean)"
    failed=1
  fi
done <<< "$ids"

if [[ $failed -ne 0 ]]; then
  exit 1
fi
echo "bench regression: all compared workloads within ${PCT}%"
