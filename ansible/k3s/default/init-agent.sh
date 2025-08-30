#!/bin/bash

config="server: https://${KUBE_API_HOST}:6443
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

if [[ -n "$WORKER_FLAGS" ]] && [[ "$WORKER_FLAGS" == *"protect-kernel-defaults"* ]]; then
    printf "%s\n" "vm.panic_on_oom=0" "vm.overcommit_memory=1" "kernel.panic=10" "kernel.panic_on_oops=1" "kernel.keys.root_maxbytes=25000000" >> /etc/sysctl.d/90-kubelet.conf
    sysctl -p /etc/sysctl.d/90-kubelet.conf
    systemctl restart systemd-sysctl
fi

mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml <<- EOF
${config}
EOF

# Input validation
if [[ "${KUBERNETES_VERSION}" =~ [^a-zA-Z0-9.+_-] ]]; then
    echo "Error: Invalid characters in KUBERNETES_VERSION"
    exit 1
fi

if [[ -n "${CHANNEL}" ]] && [[ "${CHANNEL}" =~ [^a-zA-Z0-9._-] ]]; then
    echo "Error: Invalid characters in CHANNEL"
    exit 1
fi

export INSTALL_K3S_VERSION="${KUBERNETES_VERSION}"
export INSTALL_K3S_EXEC="agent"

if [ -n "${CHANNEL}" ]; then
    export INSTALL_K3S_CHANNEL="${CHANNEL}"
fi

if ! curl -sfL https://get.k3s.io | sh -; then
    echo "Failed to install k3s-agent"
    exit 1
fi

systemctl enable k3s-agent.service --now
RET=1
until [ ${RET} -eq 0 ]; do
        systemctl start k3s-agent.service
        RET=$?
        sleep 10
done
