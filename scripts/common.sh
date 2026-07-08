#!/usr/bin/env bash
# Shared config sourced by every scripts/*.sh. Edit these to point the demo
# at a different JFrog Platform instance/project.
set -euo pipefail

SERVER_ID="mcodevisionaryorg"
GENERIC_REPO="emb-airgap-demo-generic-local"
CCACHE_REPO="emb-airgap-demo-ccache-local"
BUILD_NAME="envsensor-fw"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

# Pulls ARTIFACTORY_URL / ARTIFACTORY_USER / ARTIFACTORY_CCACHE_TOKEN written
# by setup_artifactory.sh. This file is gitignored — it holds a live token.
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi
