#!/bin/bash

config="server: https://${KUBE_API_HOST}:9345
token: ${NODE_TOKEN}
"

if [ -n "${PUBLIC_IP}" ]; then
    config="$config
node-external-ip: ${PUBLIC_IP}"
fi

if [ -n "${WORKER_FLAGS}" ]; then
    config="$config
$(printf '%b' "${WORKER_FLAGS}")"
fi

mkdir -p /etc/rancher/rke2
cat > /etc/rancher/rke2/config.yaml <<- EOF
${config}
EOF

# Input validation
if [[ "${KUBERNETES_VERSION}" =~ [^a-zA-Z0-9.+_-] ]]; then
    echo "Error: Invalid characters in KUBERNETES_VERSION"
    exit 1
fi

if [[ -n "${INSTALL_METHOD}" ]] && [[ "${INSTALL_METHOD}" =~ [^a-zA-Z0-9._-] ]]; then
    echo "Error: Invalid characters in INSTALL_METHOD"
    exit 1
fi

if [[ -n "${CHANNEL}" ]] && [[ "${CHANNEL}" =~ [^a-zA-Z0-9._-] ]]; then
    echo "Error: Invalid characters in CHANNEL"
    exit 1
fi

export INSTALL_RKE2_VERSION="${KUBERNETES_VERSION}"
export INSTALL_RKE2_TYPE="agent"

if [ -n "${CHANNEL}" ]; then
    export INSTALL_RKE2_CHANNEL="${CHANNEL}"
fi

if [ -n "${INSTALL_METHOD}" ]; then
    export INSTALL_RKE2_METHOD="${INSTALL_METHOD}"
fi

if ! curl -sfL https://get.rke2.io | sh -; then
    echo "Failed to install rke2-agent"
    exit 1
fi

systemctl enable rke2-agent.service --now
RET=1
until [ ${RET} -eq 0 ]; do
        systemctl start rke2-agent.service
        RET=$?
        sleep 10
done