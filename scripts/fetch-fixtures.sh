#!/usr/bin/env bash
# Shallow-clone Apache reference corpora into vendor/ (alternative: git submodule update --init).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "${ROOT}/vendor"

clone_shallow () {
  local name="$1" url="$2"
  if [[ -d "${ROOT}/vendor/${name}/.git" ]]; then
    echo "vendor/${name}: already present"
    return
  fi
  echo "Cloning ${name}…"
  git clone --depth 1 "${url}" "${ROOT}/vendor/${name}"
}

clone_shallow parquet-testing https://github.com/apache/parquet-testing.git
clone_shallow avro https://github.com/apache/avro.git
clone_shallow orc https://github.com/apache/orc.git
clone_shallow arrow-testing https://github.com/apache/arrow-testing.git

echo "Done. Vendored trees under vendor/{parquet-testing,avro,orc,arrow-testing}."
