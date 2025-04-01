#!/bin/bash

config="server: https://${KUBE_API_HOST}:9345
token: ${NODE_TOKEN}
"

mkdir -p /etc/rancher/rke2
cat > /etc/rancher/rke2/config.yaml <<- EOF
${config}
EOF

# Install RKE2 Agent with the specified Kubernetes version
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="${KUBERNETES_VERSION}" INSTALL_RKE2_TYPE="agent" sh -

systemctl enable rke2-agent.service --now
RET=1
until [ ${RET} -eq 0 ]; do
        systemctl start rke2-agent.service
        RET=$?
        sleep 10
done