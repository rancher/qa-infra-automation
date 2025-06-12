#!/bin/bash

config="write-kubeconfig-mode: 644
cni: ${CNI}
server: https://${KUBE_API_HOST}:9345
token: ${NODE_TOKEN}
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
if [[ "$has_etcd" == false && "$has_cp" == true && "$has_worker" == false ]]; then
  echo "Configuring cp-only node"
  config="$config
disable-etcd: true
node-taint:
  - node-role.kubernetes.io/control-plane:NoSchedule
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
elif [[ "$has_etcd" == true && "$has_cp" == true && "$has_worker" == false ]]; then
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
elif [[ "$has_etcd" == false && "$has_cp" == true && "$has_worker" == true ]]; then
  echo "Configuring cp-worker node"
  config="$config
disable-etcd: true
"
fi

mkdir -p /etc/rancher/rke2
cat > /etc/rancher/rke2/config.yaml <<- EOF
${config}
EOF

# Install RKE2 with the specified Kubernetes version
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="${KUBERNETES_VERSION}" sh -

systemctl enable rke2-server.service
RET=1
until [ ${RET} -eq 0 ]; do
	systemctl start rke2-server.service
	RET=$?
	sleep 10
done
