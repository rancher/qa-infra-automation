#!/bin/bash

config="server: https://${KUBE_API_HOST}:6443
token: ${NODE_TOKEN}
write-kubeconfig-mode: 644
tls-san:
  - ${FQDN}
  - ${KUBE_API_HOST}
"

if [ -n "${PUBLIC_IP}" ]; then
    config="$config
node-external-ip: ${PUBLIC_IP}"
fi

if [ -n "${SERVER_FLAGS}" ]; then
    config="$config
$(printf '%b' "${SERVER_FLAGS}")"
fi

if [[ -n "$SERVER_FLAGS" ]] && [[ "$SERVER_FLAGS" == *"protect-kernel-defaults"* ]]; then
    echo "Applying security hardening configuration..."
    cat policy.yaml > /var/lib/rancher/k3s/server/manifests/policy.yaml
    cat audit.yaml > /var/lib/rancher/k3s/server/audit.yaml
    cat cluster-level-pss.yaml > /var/lib/rancher/k3s/server/cluster-level-pss.yaml  
    cat ingresspolicy.yaml > /var/lib/rancher/k3s/server/manifests/ingresspolicy.yaml
    printf "%s\n" "vm.panic_on_oom=0" "vm.overcommit_memory=1" "kernel.panic=10" "kernel.panic_on_oops=1" "kernel.keys.root_maxbytes=25000000" >> /etc/sysctl.d/90-kubelet.conf
    sysctl -p /etc/sysctl.d/90-kubelet.conf
    systemctl restart systemd-sysctl
    
    config="$config
$(cat cis_master_config.yaml)"
fi

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

# Configure K3s based on the role combinations
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

mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/config.yaml <<- EOF
${config}
EOF

# Input validation.
if [[ "${KUBERNETES_VERSION}" =~ [^a-zA-Z0-9.+_-] ]]; then
    echo "Error: Invalid characters in KUBERNETES_VERSION"
    exit 1
fi

if [[ -n "${CHANNEL}" ]] && [[ "${CHANNEL}" =~ [^a-zA-Z0-9._-] ]]; then
    echo "Error: Invalid characters in CHANNEL"
    exit 1
fi

export INSTALL_K3S_VERSION="${KUBERNETES_VERSION}"

if [ -n "${CHANNEL}" ]; then
    export INSTALL_K3S_CHANNEL="${CHANNEL}"
fi

if ! curl -sfL https://get.k3s.io | sh -; then
    echo "Failed to install k3s-server"
    exit 1
fi

systemctl enable k3s.service --now
RET=1
until [ ${RET} -eq 0 ]; do
        systemctl start k3s.service
        RET=$?
        sleep 10
done
