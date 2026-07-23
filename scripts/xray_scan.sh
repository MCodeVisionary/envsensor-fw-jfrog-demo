#!/usr/bin/env bash
#
# xray_scan.sh — publish an "SCA-flavoured" build-info that declares the
# vendored third-party C sources (zlib, FFmpeg) so Xray can match them
# against its CVE database.
#
# Rationale: this project has no package manager, so the natively-published
# build-info from build.sh has an empty dependency graph and Xray SCA reports
# "no vulnerable dependencies". This script generates a *parallel* build-info
# whose modules[].dependencies list the vendored upstream libs by
# Conan-style component ID (name:version) + SHA-256, uploads it via
# /api/build, then triggers a scan. It never overwrites the real build-info
# produced by build.sh — a distinct build name (${BUILD_NAME}-xray-cpp) is
# used so the certification/reproducibility record stays intact.
#
# Follows JFrog's documented pattern for C/C++ scanning without Conan:
# https://jfrog.com/help/r/jfrog-artifactory-documentation/conan-and-c/c-support-in-xray
#
# Usage:
#   ./scripts/xray_scan.sh BOARD_A [BUILD_NUMBER]
#
# Deps: jf (configured), jq, sha256sum (coreutils) or shasum (macOS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

BOARD="${1:?usage: xray_scan.sh BOARD_A|BOARD_B [BUILD_NUMBER]}"
BUILD_NUMBER="${2:-${GITHUB_RUN_NUMBER:-$(date +%s)}}"

# Real build-info name published by build.sh is ${BUILD_NAME}. We publish
# our injected one under a *different* name so the two never collide.
: "${BUILD_NAME:?BUILD_NAME must be set by common.sh}"
XRAY_BUILD_NAME="${BUILD_NAME}-xray-cpp"

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
THIRD_PARTY_DIR="${REPO_ROOT}/third_party"

# ---------------------------------------------------------------------------
# Declared vendored components. Edit component_id when a different upstream
# version is dropped in — Xray matches CVE data on these IDs.
# ---------------------------------------------------------------------------
# Format: "component_id|path_relative_to_repo_root"
VENDORED_COMPONENTS=(
  "zlib:1.2.11|third_party/zlib-1.2.11/crc32.c"
  "ffmpeg:n6.1|third_party/ffmpeg-n6.1/crc.c"
  "sqlite3:299.1.0.8|third_party/sqlite3-299.1.0.8/sqlite3_stub.c"
  "poco:1.9.0.0|third_party/poco-1.9.0.0/poco_stub.c"
)

# ---------------------------------------------------------------------------

sha256_of() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{print $1}'
  else
    echo "ERROR: need sha256sum or shasum on PATH" >&2
    exit 1
  fi
}

echo "==> Building dependency list from vendored sources"
DEPENDENCIES_JSON="[]"
for entry in "${VENDORED_COMPONENTS[@]}"; do
  component_id="${entry%%|*}"
  rel_path="${entry##*|}"
  abs_path="${REPO_ROOT}/${rel_path}"

  if [[ ! -f "${abs_path}" ]]; then
    echo "  ! ${rel_path} not found — skipping ${component_id}" >&2
    continue
  fi

  sha256="$(sha256_of "${abs_path}")"
  echo "  + ${component_id}  <-  ${rel_path}  (sha256=${sha256:0:12}…)"

  DEPENDENCIES_JSON="$(
    jq --arg id "${component_id}" \
       --arg sha "${sha256}" \
       --arg path "${rel_path}" \
       '. + [{"type":"cpp","id":$id,"sha256":$sha,"requestedBy":[[$path]]}]' \
       <<<"${DEPENDENCIES_JSON}"
  )"
done

if [[ "$(jq 'length' <<<"${DEPENDENCIES_JSON}")" -eq 0 ]]; then
  echo "ERROR: no vendored components found under ${THIRD_PARTY_DIR}" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

echo "==> Seeding skeleton build-info via 'jf rt bp --dry-run'"
jf rt bp \
  --dry-run=true \
  --server-id="${SERVER_ID}" \
  "${XRAY_BUILD_NAME}" "${BUILD_NUMBER}" \
  > "${WORK_DIR}/skeleton.json"

# 'jf rt bp --dry-run' may or may not include a modules array depending on
# whether prior 'jf rt bce' / 'jf rt ba' calls populated one. Force it to
# exist so our jq expression is well-defined. Also force top-level
# "version" — Artifactory's build-info deserializer requires it and rejects
# the whole payload with an opaque "unable to parse JSON" 400 if it's
# missing, which newer 'jf rt bp --dry-run' output doesn't always stamp in.
jq 'if has("modules") | not then . + {"modules":[]} else . end
    | if has("version") | not then . + {"version":"1.0.1"} else . end' \
  "${WORK_DIR}/skeleton.json" > "${WORK_DIR}/with_modules.json"

echo "==> Injecting cpp module + vendored dependencies"
MODULE_ID="envsensor_fw:${BOARD}"
jq --arg mid "${MODULE_ID}" \
   --argjson deps "${DEPENDENCIES_JSON}" \
   '.modules = [{
        "id": $mid,
        "type": "cpp",
        "dependencies": $deps
    }]' \
   "${WORK_DIR}/with_modules.json" > "${WORK_DIR}/build_info_xray.json"

echo "==> Injected build-info:"
jq '.' "${WORK_DIR}/build_info_xray.json"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Xray build-info — ${XRAY_BUILD_NAME} #${BUILD_NUMBER} (${BOARD})"
    echo '```json'
    jq '.' "${WORK_DIR}/build_info_xray.json"
    echo '```'
  } >> "${GITHUB_STEP_SUMMARY}"
fi

echo "==> Publishing to /api/build"
jf rt curl \
  -XPUT /api/build \
  -H "Content-Type: application/json" \
  -T "${WORK_DIR}/build_info_xray.json" \
  --server-id="${SERVER_ID}"

echo
echo "==> Triggering Xray build scan"
# --fail=false so a demo run with real CVEs doesn't kill CI while we're
# still wiring things up. Flip to --fail=true once the pipeline is
# expected to gate promotion on scan results.
jf build-scan \
  "${XRAY_BUILD_NAME}" "${BUILD_NUMBER}" \
  --server-id="${SERVER_ID}" \
  --fail=false \
  --format=table \
  --vuln=true || true

echo
echo "Done. View in the Artifactory UI:"
echo "  Builds > ${XRAY_BUILD_NAME} > ${BUILD_NUMBER} > Xray Data"
echo
echo "Note: the build must be added to Xray > Indexed Resources > Builds"
echo "before scan results appear. setup_artifactory.sh handles this for"
echo "the primary build; add '${XRAY_BUILD_NAME}' there too on first run."