#!/bin/bash

config="write-kubeconfig-mode: 644
cni: ${CNI}
tls-san:
  - ${FQDN}
  - ${KUBE_API_HOST}
"

# Configure RKE2 based on the NODE_ROLE
if [[ "$NODE_ROLE" == "etcd" ]]; then
  echo "Configuring etcd-only node"
  config="$config
disable-apiserver: true
disable-controller-manager: true
disable-scheduler: true
node-taint:
  - node-role.kubernetes.io/etcd:NoExecute
"
elif [[ "$NODE_ROLE" == *"etcd"* && "$NODE_ROLE" == *"cp"* ]]; then
  echo "Configuring etcd-cp node"
  config="$config
node-taint:
  - node-role.kubernetes.io/control-plane:NoSchedule
  - node-role.kubernetes.io/etcd:NoExecute
"
elif [[ "$NODE_ROLE" == *"etcd"* && "$NODE_ROLE" == *"worker"* ]]; then
  echo "Configuring etcd-worker node"
  config="$config
disable-apiserver: true
disable-controller-manager: true
disable-scheduler: true
"
fi

echo "${config}"

mkdir -p /etc/rancher/rke2
cat > /etc/rancher/rke2/config.yaml <<- EOF
${config}
EOF

curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="${KUBERNETES_VERSION}" sh -

systemctl enable rke2-server.service
systemctl start rke2-server.service

sed -i "s/127.0.0.1/${FQDN}/g" /etc/rancher/rke2/rke2.yaml
