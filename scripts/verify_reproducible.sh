#!/usr/bin/env bash
# Proves the build is reproducible: two independent builds of the same
# commit, in two different build directories, with ccache disabled (so
# there's no possibility of the result just being replayed from cache),
# must produce byte-identical binaries.
#
# Usage: scripts/verify_reproducible.sh BOARD_A|BOARD_B
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/common.sh

BOARD="${1:?Usage: $0 BOARD_A|BOARD_B}"
export SOURCE_DATE_EPOCH="$(git log -1 --format=%ct 2>/dev/null || echo 0)"

for N in 1 2; do
  DIR="build-repro/${BOARD}/run${N}"
  rm -rf "${DIR}"
  echo "==> Build ${N}/2 into ${DIR}..."
  cmake -S . -B "${DIR}" -DBOARD="${BOARD}" >/dev/null
  cmake --build "${DIR}" >/dev/null
done

SHA_1="$(shasum -a 256 "build-repro/${BOARD}/run1/envsensor_fw" | awk '{print $1}')"
SHA_2="$(shasum -a 256 "build-repro/${BOARD}/run2/envsensor_fw" | awk '{print $1}')"

echo ""
echo "run1 sha256: ${SHA_1}"
echo "run2 sha256: ${SHA_2}"

if [[ "${SHA_1}" == "${SHA_2}" ]]; then
  echo "PASS: builds are bit-for-bit reproducible."
else
  echo "FAIL: builds differ — something is leaking non-determinism (timestamps, absolute paths, uninitialized memory in build metadata, etc.)."
  exit 1
fi
