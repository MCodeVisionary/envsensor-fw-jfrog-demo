#!/usr/bin/env bash
#
# xray_scan.sh — splice a declared C/C++ dependency graph into the
# already-published envsensor-fw build-info for one board, so Xray can
# match the vendored third-party sources against its CVE database.
#
# Rationale: this project has no package manager, so the build-info
# build.sh publishes only ever gets a "generic" module (the uploaded
# artifact) with no dependency graph for Xray SCA to match against — jf
# has nothing to derive one from. This script fetches that same build
# (same name + number build.sh already published, read from .last_build),
# adds a "dependencies" array listing the vendored upstream libs by
# Conan-style component ID (name:version) + SHA-256, and republishes it in
# place via PUT /api/build — same build name and number as the certified
# build, not a separate one, so it shows up as one build in Artifactory.
#
# Since evidence (scripts/certify.sh) is signed over the artifact's
# SHA-256 at its repo path, not over the build-info JSON, updating the
# build-info here afterward doesn't invalidate anything already certified.
#
# Follows JFrog's documented pattern for C/C++ scanning without Conan:
# https://jfrog.com/help/r/jfrog-artifactory-documentation/conan-and-c/c-support-in-xray
#
# Usage:
#   ./scripts/xray_scan.sh BOARD_A|BOARD_B
#
# Deps: jf (configured), jq, sha256sum (coreutils) or shasum (macOS)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "${SCRIPT_DIR}/common.sh"

BOARD="${1:?usage: xray_scan.sh BOARD_A|BOARD_B}"

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
THIRD_PARTY_DIR="${REPO_ROOT}/third_party"

[[ -f "${REPO_ROOT}/.last_build" ]] || { echo "No builds recorded yet — run scripts/build.sh ${BOARD} first." >&2; exit 1; }
LINE="$(grep "envsensor-fw/${BOARD}/" "${REPO_ROOT}/.last_build" | tail -1 || true)"
[[ -n "${LINE}" ]] || { echo "No recorded build found for ${BOARD} in .last_build — run scripts/build.sh ${BOARD} first." >&2; exit 1; }
read -r _REPO_PATH _SHA256 BUILD_NAME BUILD_NUMBER <<< "${LINE}"

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

sha1_of() {
  local file="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    sha1sum "${file}" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 1 "${file}" | awk '{print $1}'
  else
    echo "ERROR: need sha1sum or shasum on PATH" >&2
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
  # Xray's build-scan dependency matcher keys off sha1, same as every other
  # ecosystem's build-info dependencies -- omitting it (sha256 alone) means
  # the id matches Xray's catalog fine via direct component-summary lookup
  # but the build scanner itself doesn't pick up the vulnerability data.
  sha1="$(sha1_of "${abs_path}")"
  echo "  + ${component_id}  <-  ${rel_path}  (sha1=${sha1:0:12}…)"

  DEPENDENCIES_JSON="$(
    jq --arg id "${component_id}" \
       --arg sha "${sha256}" \
       --arg sha1 "${sha1}" \
       --arg path "${rel_path}" \
       '. + [{"type":"cpp","id":$id,"sha1":$sha1,"sha256":$sha,"requestedBy":[[$path]]}]' \
       <<<"${DEPENDENCIES_JSON}"
  )"
done

if [[ "$(jq 'length' <<<"${DEPENDENCIES_JSON}")" -eq 0 ]]; then
  echo "ERROR: no vendored components found under ${THIRD_PARTY_DIR}" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

echo "==> Fetching published build-info (build=${BUILD_NAME}/${BUILD_NUMBER})..."
jf rt curl -XGET "/api/build/${BUILD_NAME}/${BUILD_NUMBER}" \
  --server-id="${SERVER_ID}" \
  > "${WORK_DIR}/existing.json"

# Artifactory's GET /api/build/{name}/{number} wraps the payload in
# {"buildInfo": {...}} on some versions, returns it flat on others.
jq 'if has("buildInfo") then .buildInfo else . end' \
  "${WORK_DIR}/existing.json" > "${WORK_DIR}/unwrapped.json"

echo "==> Splicing vendored dependencies into modules[0]"
jq --argjson deps "${DEPENDENCIES_JSON}" \
   '.modules[0].type = "cpp" | .modules[0].dependencies = $deps' \
   "${WORK_DIR}/unwrapped.json" > "${WORK_DIR}/build_info_with_deps.json"

echo "==> Updated build-info:"
jq '.' "${WORK_DIR}/build_info_with_deps.json"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Xray build-info — ${BUILD_NAME} #${BUILD_NUMBER} (${BOARD})"
    echo '```json'
    jq '.' "${WORK_DIR}/build_info_with_deps.json"
    echo '```'
  } >> "${GITHUB_STEP_SUMMARY}"
fi

echo "==> Publishing updated build-info to /api/build"
jf rt curl \
  -XPUT /api/build \
  -H "Content-Type: application/json" \
  -T "${WORK_DIR}/build_info_with_deps.json" \
  --server-id="${SERVER_ID}"

echo

# BOARD_A and BOARD_B are separate build NUMBERS but the same build NAME
# (envsensor-fw), and both matrix jobs publish+scan at roughly the same
# moment. Confirmed empirically that this causes real contention, not just
# a generic indexing delay: retrying the losing board's scan (even with
# --rescan=true, even minutes later) kept returning an empty result, while
# the other board succeeded on its very first attempt. Stagger BOARD_B's
# start so the two boards don't hit Xray's indexing for the same build
# name at the same instant.
if [[ "${BOARD}" == "BOARD_B" ]]; then
  echo "==> Staggering scan start by 20s to avoid concurrent-board contention on Xray indexing for ${BUILD_NAME}"
  sleep 20
fi

echo "==> Triggering Xray build scan"
# --fail=false so a demo run with real CVEs doesn't kill CI while we're
# still wiring things up. Flip to --fail=true once the pipeline is
# expected to gate promotion on scan results.
#
# Xray indexing the just-published build-info is not instant, and firing
# the scan right after the PUT produced inconsistent results on live CI
# runs: a transient 404 "build doesn't exist or not indexed in Xray" on one
# board, a scan that completed but found nothing on another -- yet the
# same publish+scan sequence run by hand, with natural delay between
# commands, found the expected CVEs every time. So: retry until the scan
# actually reports something other than a clean "no vulnerabilities" (our
# declared components always carry known CVEs, so an empty result here
# means indexing hasn't caught up yet, not a genuine negative). The first
# attempt is a plain scan (this build has never been scanned before, so
# --rescan=true would itself 404); once that attempt has registered once,
# later retries need --rescan=true to force Xray to re-evaluate rather
# than return the earlier empty result.
MAX_ATTEMPTS=5
for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
  RESCAN_FLAG=""
  if [[ "${attempt}" -gt 1 ]]; then
    sleep 15
    RESCAN_FLAG="--rescan=true"
  fi
  SCAN_OUTPUT="$(jf build-scan "${BUILD_NAME}" "${BUILD_NUMBER}" --server-id="${SERVER_ID}" --fail=false ${RESCAN_FLAG} --format=table --vuln=true 2>&1)" || true
  echo "${SCAN_OUTPUT}"
  if ! grep -q "No vulnerable dependencies were found" <<<"${SCAN_OUTPUT}"; then
    break
  fi
  echo "==> attempt ${attempt}/${MAX_ATTEMPTS}: no vulnerabilities matched yet -- Xray may still be indexing this build"
done

echo
echo "Done. View in the Artifactory UI:"
echo "  Builds > ${BUILD_NAME} > ${BUILD_NUMBER} > Xray Data"
echo
echo "Note: the build must be added to Xray > Indexed Resources > Builds"
echo "before scan results appear. setup_artifactory.sh handles this for"
echo "the primary build."
