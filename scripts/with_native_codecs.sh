#!/usr/bin/env bash
# Run Lake with native codec link flags and compile `c/columnar_codec.c` against system headers.
# Requires: COLUMNAR_CODEC=1 for the C object (see lakefile `columnar_codec_o`) and
# -Kcolumnar.codec=1 so `package` `moreLinkArgs` links libsnappy, libzstd, etc.
set -euo pipefail
export COLUMNAR_CODEC="${COLUMNAR_CODEC:-1}"
exec lake -Kcolumnar.codec=1 "$@"
