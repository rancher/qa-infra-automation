#!/bin/bash
# Wait for the rke2 or k3s node to register as Ready in Kubernetes.
#
# Phase 0: Poll until the distro binary appears on disk (handles async install).
# Phase 1: Wait for the distro service to become active.
# Phase 2: Wait for `kubectl get node <hostname>` to report Ready status.
#
# All phases share a single 900-second deadline.

set -uo pipefail

DEADLINE=$(( $(date +%s) + 900 ))
# NODE_NAME is the Kubernetes node name set during registration (--node-name).
# It is passed as an env var from the playbook (inventory_hostname).
# Fall back to hostname only if not provided.
NODE_NAME="${NODE_NAME:-$(hostname)}"

# ---------------------------------------------------------------------------
# Phase 0: Wait for the distro binary to appear (registration is async)
# ---------------------------------------------------------------------------
echo "Phase 0: Waiting for rke2 or k3s binary to appear..."
DISTRO=""
while true; do
    NOW=$(date +%s)
    if (( NOW >= DEADLINE )); then
        echo "ERROR: Timed out after 900s waiting for rke2 or k3s binary." >&2
        exit 1
    fi

    if [[ -x "/usr/local/bin/rke2" ]]; then
        DISTRO="rke2"
        break
    elif [[ -x "/usr/local/bin/k3s" ]]; then
        DISTRO="k3s"
        break
    fi

    echo "  No binary found yet, retrying in 10s..."
    sleep 10
done

echo "Detected distro: ${DISTRO}"

# ---------------------------------------------------------------------------
# Set distro-specific kubectl and kubeconfig paths
# ---------------------------------------------------------------------------
if [[ "${DISTRO}" == "rke2" ]]; then
    KUBECTL="/var/lib/rancher/rke2/bin/kubectl"
    KUBECONFIG="/etc/rancher/rke2/rke2.yaml"
else
    KUBECTL="/usr/local/bin/kubectl"
    KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
fi

# ---------------------------------------------------------------------------
# Determine which service to watch (server vs agent)
# Poll until the unit file is registered — it may appear shortly after binary.
# ---------------------------------------------------------------------------
echo "Detecting service name..."
SERVICE=""
while true; do
    NOW=$(date +%s)
    if (( NOW >= DEADLINE )); then
        echo "ERROR: Timed out after 900s waiting for a ${DISTRO} service unit to appear." >&2
        exit 1
    fi

    if [[ "${DISTRO}" == "rke2" ]]; then
        if systemctl list-unit-files rke2-server.service 2>/dev/null | grep -q rke2-server; then
            SERVICE="rke2-server"
            break
        elif systemctl list-unit-files rke2-agent.service 2>/dev/null | grep -q rke2-agent; then
            SERVICE="rke2-agent"
            break
        fi
    else
        # k3s server unit is named k3s.service; agent is k3s-agent.service
        if systemctl list-unit-files k3s.service 2>/dev/null | grep -q 'k3s\.service'; then
            SERVICE="k3s"
            break
        elif systemctl list-unit-files k3s-agent.service 2>/dev/null | grep -q 'k3s-agent'; then
            SERVICE="k3s-agent"
            break
        fi
    fi

    echo "  No ${DISTRO} service unit found yet, retrying in 10s..."
    sleep 10
done

echo "Watching service: ${SERVICE}"

# Agent nodes have no kubectl / kubeconfig — Phases 1+2 are enough for them.
IS_AGENT=false
if [[ "${SERVICE}" == "rke2-agent" || "${SERVICE}" == "k3s-agent" ]]; then
    IS_AGENT=true
fi

# ---------------------------------------------------------------------------
# Phase 1: Wait for the service to become active
# ---------------------------------------------------------------------------
echo "Phase 1: Waiting for ${SERVICE} to become active..."
while true; do
    NOW=$(date +%s)
    if (( NOW >= DEADLINE )); then
        echo "ERROR: Timed out after 900s waiting for ${SERVICE} to become active." >&2
        exit 1
    fi

    STATE=$(systemctl is-active "${SERVICE}" 2>/dev/null || true)
    if [[ "${STATE}" == "active" ]]; then
        echo "${SERVICE} is active."
        break
    fi

    echo "  ${SERVICE} state=${STATE:-unknown}, retrying in 10s..."
    sleep 10
done

# Agent nodes do not run the API server — skip the kubectl Ready check.
if [[ "${IS_AGENT}" == "true" ]]; then
    echo "Agent node: skipping Phase 2 (no kubectl on agent)."
    exit 0
fi

# ---------------------------------------------------------------------------
# Phase 2: Wait for the node to appear as Ready in Kubernetes
# ---------------------------------------------------------------------------
echo "Phase 2: Waiting for node ${NODE_NAME} to be Ready..."
while true; do
    NOW=$(date +%s)
    if (( NOW >= DEADLINE )); then
        echo "ERROR: Timed out after 900s waiting for node ${NODE_NAME} to be Ready." >&2
        exit 1
    fi

    READY=$(KUBECONFIG="${KUBECONFIG}" "${KUBECTL}" get node "${NODE_NAME}" \
        --request-timeout=10s \
        -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}' 2>/dev/null \
        | grep '^Ready=' | cut -d= -f2 || true)

    if [[ "${READY}" == "True" ]]; then
        echo "Node ${NODE_NAME} is Ready."
        exit 0
    fi

    echo "  Node ${NODE_NAME} status=${READY:-unknown}, retrying in 10s..."
    sleep 10
done
