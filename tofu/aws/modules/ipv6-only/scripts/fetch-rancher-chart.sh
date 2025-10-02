#!/bin/bash
set -euo pipefail

RANCHER_CHART_REPO_URL=$1   # e.g. https://releases.rancher.com/server-charts/prime
RANCHER_CHART_VERSION=$2    # e.g. 2.11.3

# ===== Check Helm =====
if ! command -v helm >/dev/null 2>&1; then
    echo "[ERROR] Helm is not installed on this machine."
    echo "Please install Helm (https://helm.sh/docs/intro/install/) and retry."
    exit 1
fi

# ===== Add Helm repo =====
echo "[INFO] Adding Rancher chart repo..."
helm repo add --force-update rancher-charts "${RANCHER_CHART_REPO_URL}"
helm repo update

# ===== Fetch Chart =====
echo "[INFO] Pulling Rancher chart..."
helm pull rancher-charts/rancher --version "${RANCHER_CHART_VERSION}"

echo "[SUCCESS] Chart fetched successfully."
