#!/usr/bin/env bash
# Attach a signed certification record to the most recent published build
# for a given board, using JFrog Evidence. The evidence is a DSSE envelope
# signed with the key setup_artifactory.sh generated, permanently bound to
# the artifact's SHA-256 — verifiable for the life of a fielded device,
# independent of whether the CI system that built it still exists.
#
# Usage: scripts/certify.sh BOARD_A|BOARD_B "Certifying Engineer" "Certifying Body"
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/common.sh

BOARD="${1:?Usage: $0 BOARD_A|BOARD_B [engineer] [body]}"
ENGINEER="${2:-$(whoami)}"
BODY="${3:-Internal Quality Engineering}"

[[ -f .last_build ]] || { echo "No builds recorded yet — run scripts/build.sh ${BOARD} first." >&2; exit 1; }

LINE="$(grep "envsensor-fw/${BOARD}/" .last_build | tail -1 || true)"
[[ -n "${LINE}" ]] || { echo "No recorded build found for ${BOARD} in .last_build." >&2; exit 1; }

read -r REPO_PATH SHA256 B_NAME B_NUMBER <<< "${LINE}"
VERSION="1.0.0"
GIT_COMMIT="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"

mkdir -p evidence/generated
PREDICATE_FILE="evidence/generated/${B_NAME}-${B_NUMBER}.json"

sed \
  -e "s/__CERTIFYING_BODY__/${BODY}/" \
  -e "s/__CERTIFYING_ENGINEER__/${ENGINEER}/" \
  -e "s/__CERTIFICATION_DATE__/$(date -u +%Y-%m-%dT%H:%M:%SZ)/" \
  -e "s/__BUILD_NAME__/${B_NAME}/" \
  -e "s/__BUILD_NUMBER__/${B_NUMBER}/" \
  -e "s/__BOARD__/${BOARD}/" \
  -e "s/__FW_VERSION__/${VERSION}/" \
  -e "s/__GIT_COMMIT__/${GIT_COMMIT}/" \
  -e "s/__ARTIFACT_SHA256__/${SHA256}/" \
  evidence/cert-template.json > "${PREDICATE_FILE}"

echo "==> Predicate written to ${PREDICATE_FILE}"
echo "==> Signing and attaching evidence to ${REPO_PATH}..."

jf evd create-evidence \
  --predicate "${PREDICATE_FILE}" \
  --predicate-type "https://jfrog.com/evidence/envsensor-fw/certification/v1" \
  --subject-repo-path "${REPO_PATH}" \
  --key evidence-keys/envsensor-cert.key \
  --key-alias envsensor-cert-key \
  --server-id="${SERVER_ID}"

echo "==> Also stamping quick-glance properties for UI/AQL filtering..."
jf rt set-props "${REPO_PATH}" \
  "cert.status=certified;cert.standard=functional-safety-demo;cert.date=$(date -u +%Y-%m-%d);cert.engineer=${ENGINEER}" \
  --server-id="${SERVER_ID}"

echo "==> Certification attached to ${REPO_PATH}."
echo "==> Verify anytime with: jf evd verify --subject-repo-path ${REPO_PATH} --use-artifactory-keys --server-id=${SERVER_ID}"
