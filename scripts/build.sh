#!/usr/bin/env bash
# Build one board's firmware through ccache backed by the Artifactory
# ccache repo, then publish the artifact + build-info to Artifactory.
#
# Usage: scripts/build.sh BOARD_A|BOARD_B
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/common.sh

BOARD="${1:?Usage: $0 BOARD_A|BOARD_B}"
if [[ "${BOARD}" != "BOARD_A" && "${BOARD}" != "BOARD_B" ]]; then
  echo "Unknown board '${BOARD}'. Valid values: BOARD_A, BOARD_B" >&2
  exit 1
fi

if [[ -z "${ARTIFACTORY_CCACHE_TOKEN:-}" ]]; then
  echo "Missing ARTIFACTORY_CCACHE_TOKEN — run scripts/setup_artifactory.sh first." >&2
  exit 1
fi

command -v ccache >/dev/null || { echo "ccache not found — install it first (brew install ccache)." >&2; exit 1; }
command -v zip >/dev/null || { echo "zip not found — install it first (apt-get install zip / brew install zip)." >&2; exit 1; }

# --- Bring up the local HTTP->HTTPS cache proxy in front of Artifactory ---
PROXY_PORT="${CCACHE_PROXY_PORT:-8081}"
PROXY_PID=""
if ! curl -s -o /dev/null "http://127.0.0.1:${PROXY_PORT}/"; then
  # CACHE_PROXY_INSECURE=1 or CACHE_PROXY_CA_BUNDLE=/path/ca.pem: only needed
  # if this machine sits behind a TLS-inspecting corporate proxy whose root
  # cert curl/jf CLI trust via the OS keychain but Python's OpenSSL doesn't.
  python3 scripts/artifactory_cache_proxy.py \
    "${PROXY_PORT}" "${ARTIFACTORY_URL}" "${CCACHE_REPO}" "${ARTIFACTORY_CCACHE_TOKEN}" &
  PROXY_PID=$!
  trap '[[ -n "${PROXY_PID}" ]] && kill "${PROXY_PID}" 2>/dev/null || true' EXIT
  sleep 0.5
fi

export CCACHE_DIR="${REPO_ROOT}/.ccache-local"
export CCACHE_REMOTE_STORAGE="http://127.0.0.1:${PROXY_PORT}|@layout=flat"
# Reproducibility: pin the embedded build timestamp to the last commit time,
# not wall-clock "now", so rebuilding the same commit anywhere is identical.
export SOURCE_DATE_EPOCH="$(git log -1 --format=%ct 2>/dev/null || echo 0)"

BUILD_DIR="build/${BOARD}"
echo "==> Configuring ${BOARD} (ccache remote: Artifactory/${CCACHE_REPO})..."
cmake -S . -B "${BUILD_DIR}" -DBOARD="${BOARD}" -DCMAKE_C_COMPILER_LAUNCHER=ccache >/dev/null

echo "==> Building ${BOARD}..."
cmake --build "${BUILD_DIR}" --clean-first

echo "==> ccache stats for this build:"
CCACHE_DIR="${CCACHE_DIR}" ccache -s | grep -E "cache hit|cache miss|Hits|Misses" || true

ARTIFACT="${BUILD_DIR}/envsensor_fw"
VERSION="$(cat VERSION)"
BUILD_NUMBER="${BOARD}.$(date +%Y%m%d%H%M%S)"

# Xray only scans archive/compressed formats in generic repos (zip, tar, 7z,
# etc.) -- it never opens a raw single binary to look for embedded
# components: https://docs.jfrog.com/security/docs/supported-technologies-xray
# So the published artifact is a zip, not the raw ELF. Pin the zipped
# entry's mtime to SOURCE_DATE_EPOCH (same value used for the compile
# itself) and strip extra file attributes (-X) so re-zipping an identical
# binary on any machine produces byte-identical zip output too -- the zip
# step must stay reproducible, not just the binary inside it.
ARTIFACT_ZIP="${BUILD_DIR}/envsensor_fw.zip"
touch -t "$(date -u -d "@${SOURCE_DATE_EPOCH}" +%Y%m%d%H%M.%S 2>/dev/null || date -u -r "${SOURCE_DATE_EPOCH}" +%Y%m%d%H%M.%S)" "${ARTIFACT}"
rm -f "${ARTIFACT_ZIP}"
zip -X -j "${ARTIFACT_ZIP}" "${ARTIFACT}" >/dev/null

SHA256="$(shasum -a 256 "${ARTIFACT_ZIP}" | awk '{print $1}')"
REPO_PATH="${GENERIC_REPO}/envsensor-fw/${BOARD}/${VERSION}/envsensor_fw.zip"

echo "==> Publishing build-info (build=${BUILD_NAME}/${BUILD_NUMBER})..."
jf rt build-collect-env "${BUILD_NAME}" "${BUILD_NUMBER}"
jf rt build-add-git "${BUILD_NAME}" "${BUILD_NUMBER}"

jf rt upload "${ARTIFACT_ZIP}" "${REPO_PATH}" \
  --build-name="${BUILD_NAME}" --build-number="${BUILD_NUMBER}" \
  --target-props="board=${BOARD};fw.version=${VERSION};git.commit=$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)" \
  --server-id="${SERVER_ID}"

jf rt build-publish "${BUILD_NAME}" "${BUILD_NUMBER}" --server-id="${SERVER_ID}"

echo "==> Scanning published build-info with Xray..."
# --fail=false: this project has no package manager, so there's no
# dependency graph for Xray SCA to match against — nothing to gate on today,
# but this is where a real project's build would block promotion/
# certification on Xray findings. --vuln surfaces raw vulnerability data
# even without a project/watch configured (violations require one).
jf build-scan "${BUILD_NAME}" "${BUILD_NUMBER}" --fail=false --vuln --server-id="${SERVER_ID}"

echo ""
echo "==> Done."
echo "      artifact : ${REPO_PATH}"
echo "      sha256   : ${SHA256}"
echo "      build    : ${BUILD_NAME}/${BUILD_NUMBER}"
echo ""
echo "${REPO_PATH} ${SHA256} ${BUILD_NAME} ${BUILD_NUMBER}" >> .last_build
