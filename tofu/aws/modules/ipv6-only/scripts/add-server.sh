#!/bin/bash
set -e

K8S_VERSION=$1
RKE2_SERVER_IP=$2
RKE2_NEW_SERVER_IP=$3
HOSTNAME=$4
RKE2_TOKEN=$5
CNI=$6
CLUSTER_CIDR=$7
SERVICE_CIDR=$8

echo "=========================================="
echo "        RKE2 Server Installation          "
echo "=========================================="
echo "K8s Version:        $K8S_VERSION"
echo "RKE2 Server IP:     $RKE2_SERVER_IP"
echo "New Server IP:      $RKE2_NEW_SERVER_IP"
echo "Hostname:           $HOSTNAME"
echo "RKE2 Token:         $RKE2_TOKEN"
echo "CNI:                $CNI"
echo "Cluster CIDR:       $CLUSTER_CIDR"
echo "Service CIDR:       $SERVICE_CIDR"
echo "=========================================="


echo "=== Starting RKE2 server installation on ${RKE2_NEW_SERVER_IP} ==="

# Set hostname
sudo hostnamectl set-hostname "${RKE2_NEW_SERVER_IP}"

echo "[INFO] Ensure ::1 localhost exists"
sudo grep -q '^::1[[:space:]]\\+localhost' /etc/hosts || echo '::1       localhost' | sudo tee -a /etc/hosts

# Prepare config
sudo mkdir -p /etc/rancher/rke2
sudo touch /etc/rancher/rke2/config.yaml

if [ -n "${CLUSTER_CIDR}" ]; then
  cat <<CFG | sudo tee /etc/rancher/rke2/config.yaml > /dev/null
server: https://${RKE2_SERVER_IP}:9345
write-kubeconfig-mode: 644
node-ip: ${RKE2_NEW_SERVER_IP}
node-external-ip: ${RKE2_NEW_SERVER_IP}
cni: ${CNI}
token: ${RKE2_TOKEN}
cluster-cidr: ${CLUSTER_CIDR}
service-cidr: ${SERVICE_CIDR}
tls-san:
  - ${HOSTNAME}
CFG
else
  cat <<CFG | sudo tee /etc/rancher/rke2/config.yaml > /dev/null
server: https://${RKE2_SERVER_IP}:9345
cni: ${CNI}
token: ${RKE2_TOKEN}
tls-san:
  - ${HOSTNAME}
CFG
fi


# Install RKE2
curl -sfL https://get.rke2.io --output install.sh
# Replace github.com with gh-v6.com in the install script
sudo sed -i 's|github\.com|gh-v6.com|g' install.sh
sudo chmod +x install.sh
sudo INSTALL_RKE2_VERSION=${K8S_VERSION} INSTALL_RKE2_TYPE="server" sh ./install.sh


# Enable and start RKE2
sudo systemctl enable rke2-server
sudo systemctl start rke2-server

echo "=== RKE2 server installation complete ==="
