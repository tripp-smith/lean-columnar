#!/usr/bin/env bash
# Optional SciLean / LeanBLAS / OpenBLAS bridge: exports COLUMNAR_SCILEAN for Lake `meta if`
# (Lake cannot read `-K` flags inside `meta if` via `get_config?`), then forwards to lake with
# `-Kcolumnar.scilean=1` for linker args (`moreLinkArgs`).
set -euo pipefail
export COLUMNAR_SCILEAN="${COLUMNAR_SCILEAN:-1}"
exec lake -Kcolumnar.scilean=1 "$@"
