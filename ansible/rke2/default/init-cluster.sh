#!/bin/bash

config="write-kubeconfig-mode: 644
cni: ${CNI}
tls-san:
  - ${FQDN}
  - ${KUBE_API_HOST}
"

# Parse NODE_ROLE into an array (comma-separated)
IFS=',' read -r -a ROLES <<< "$NODE_ROLE"

# Initialize role flags
has_etcd=false
has_cp=false
has_worker=false

# Check for specific roles
for role in "${ROLES[@]}"; do
  case "$role" in
    etcd) has_etcd=true ;;
    cp) has_cp=true ;;
    worker) has_worker=true ;;
  esac
done

# Configure RKE2 based on the role combinations
if [[ "$has_etcd" == true && "$has_cp" == true && "$has_worker" == false ]]; then
  echo "Configuring etcd-cp node"
  config="$config
node-taint:
  - node-role.kubernetes.io/control-plane:NoSchedule
  - node-role.kubernetes.io/etcd:NoExecute
"
elif [[ "$has_etcd" == true && "$has_worker" == true && "$has_cp" == false ]]; then
  echo "Configuring etcd-worker node"
  config="$config
disable-apiserver: true
disable-controller-manager: true
disable-scheduler: true
"
elif [[ "$has_etcd" == true && "$has_cp" == false && "$has_worker" == false ]]; then
  echo "Configuring etcd-only node"
  config="$config
disable-apiserver: true
disable-controller-manager: true
disable-scheduler: true
node-taint:
  - node-role.kubernetes.io/etcd:NoExecute
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
