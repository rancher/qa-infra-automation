#!/bin/bash

config="write-kubeconfig-mode: 644
cluster-init: true
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
    echo "$POLICY_YAML_CONTENT" > /var/lib/rancher/k3s/server/manifests/policy.yaml
    echo "$AUDIT_YAML_CONTENT" > /var/lib/rancher/k3s/server/audit.yaml
    echo "$CLUSTER_LEVEL_PSS_YAML_CONTENT" > /var/lib/rancher/k3s/server/cluster-level-pss.yaml  
    echo "$INGRESSPOLICY_YAML_CONTENT" > /var/lib/rancher/k3s/server/manifests/ingresspolicy.yaml
    printf "%s\n" "vm.panic_on_oom=0" "vm.overcommit_memory=1" "kernel.panic=10" "kernel.panic_on_oops=1" "kernel.keys.root_maxbytes=25000000" >> /etc/sysctl.d/90-kubelet.conf
    sysctl -p /etc/sysctl.d/90-kubelet.conf
    systemctl restart systemd-sysctl

    config="$config
$CIS_MASTER_CONFIG_YAML_CONTENT"
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
if [[ "$has_etcd" == false && "$has_cp" == true && "$has_worker" == false ]]; then
  echo "Configuring cp only node"
  config="$config
disable-etcd: true
node-taint:
  - node-role.kubernetes.io/control-plane:NoSchedule
node-label:
  - role-control-plane=true
"
fi
if [[ "$has_etcd" == false && "$has_cp" == true && "$has_worker" == true ]]; then
  echo "Configuring cp-worker node"
  config="$config
disable-etcd: true
node-label:
  - role-control-plane=true
  - role-worker=true
"
fi
if [[ "$has_etcd" == true && "$has_cp" == true && "$has_worker" == false ]]; then
  echo "Configuring etcd-cp node"
  config="$config
node-taint:
  - node-role.kubernetes.io/control-plane:NoSchedule
  - node-role.kubernetes.io/etcd:NoExecute
node-label:
  - role-etcd=true
  - role-control-plane=true
"
elif [[ "$has_etcd" == true && "$has_worker" == true && "$has_cp" == false ]]; then
  echo "Configuring etcd-worker node"
  config="$config
disable-apiserver: true
disable-controller-manager: true
disable-scheduler: true
node-label:
  - role-etcd=true
  - role-worker=true
"
elif [[ "$has_etcd" == true && "$has_cp" == false && "$has_worker" == false ]]; then
  echo "Configuring etcd-only node"
  config="$config
disable-apiserver: true
disable-controller-manager: true
disable-scheduler: true
node-taint:
  - node-role.kubernetes.io/etcd:NoExecute
node-label:
  - role-etcd=true
"
else 
  echo "Configuring node with all roles"
  config="$config
node-label:
  - role-etcd=true
  - role-control-plane=true
  - role-worker=true
"
fi

echo "${config}"

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

if [ -n "${CHANNEL}" ]; then
    export INSTALL_K3S_CHANNEL="${CHANNEL}"
fi

if ! curl -sfL https://get.k3s.io | sh -; then
    echo "Failed to install k3s-server"
    exit 1
fi

systemctl enable k3s.service
systemctl start k3s.service

sed -i "s/127.0.0.1/${FQDN}/g" /etc/rancher/k3s/k3s.yaml
