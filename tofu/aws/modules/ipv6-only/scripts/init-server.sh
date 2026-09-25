#!/bin/bash
# Usage:
# ./init-server.sh <USER> <GROUP> <K8S_VERSION> <RKE2_SERVER_IP> <HOSTNAME> <RKE2_TOKEN> <CNI> <CLUSTER_CIDR> <SERVICE_CIDR>

USER=$1
GROUP=$2
K8S_VERSION=$3
RKE2_SERVER_IP=$4
HOSTNAME=$5
RKE2_TOKEN=$6
CNI=$7
CLUSTER_CIDR=$8
SERVICE_CIDR=$9

echo "=========================================="
echo "         RKE2 Server Initialization        "
echo "=========================================="
echo "User:              $USER"
echo "Group:             $GROUP"
echo "K8s Version:       $K8S_VERSION"
echo "RKE2 Server IP:    $RKE2_SERVER_IP"
echo "Hostname:          $HOSTNAME"
echo "RKE2 Token:        $RKE2_TOKEN"
echo "CNI:               $CNI"
echo "Cluster CIDR:      $CLUSTER_CIDR"
echo "Service CIDR:      $SERVICE_CIDR"
echo "=========================================="

set -e

echo "[INFO] Setting hostname..."
sudo hostnamectl set-hostname "${RKE2_SERVER_IP}"

echo "[INFO] Ensure ::1 localhost exists"
sudo grep -q '^::1[[:space:]]\\+localhost' /etc/hosts || echo '::1       localhost' | sudo tee -a /etc/hosts

echo "[INFO] Preparing RKE2 configuration directory..."
sudo mkdir -p /etc/rancher/rke2
sudo touch /etc/rancher/rke2/config.yaml

echo "[INFO] Writing config.yaml..."
if [ -n "${CLUSTER_CIDR}" ]; then
  sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
cni: ${CNI}
write-kubeconfig-mode: 644
node-ip: ${RKE2_SERVER_IP}
node-external-ip: ${RKE2_SERVER_IP}
token: ${RKE2_TOKEN}
cluster-cidr: ${CLUSTER_CIDR}
service-cidr: ${SERVICE_CIDR}
tls-san:
  - ${HOSTNAME}
EOF
else
  sudo tee /etc/rancher/rke2/config.yaml > /dev/null <<EOF
cni: ${CNI}
token: ${RKE2_TOKEN}
tls-san:
  - ${HOSTNAME}
EOF
fi

echo "[INFO] Installing RKE2 server..."
curl -sfL https://get.rke2.io --output install.sh
# Replace github.com with gh-v6.com in the install script
sudo sed -i 's|github\.com|gh-v6.com|g' install.sh
sudo chmod +x install.sh
sudo INSTALL_RKE2_VERSION="${K8S_VERSION}" INSTALL_RKE2_TYPE="server" ./install.sh

echo "[INFO] Enabling and starting RKE2 server..."
sudo systemctl enable rke2-server
sudo systemctl start rke2-server

echo "[INFO] Configuring kubeconfig for ${USER}..."
if [[ "${USER}" == "root" ]]; then
  sudo mkdir -p /root/.kube
  sudo cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
else
  sudo mkdir -p /home/${USER}/.kube
  sudo cp /etc/rancher/rke2/rke2.yaml /home/${USER}/.kube/config
  sudo chown -R ${USER}:${GROUP} /home/${USER}/.kube
fi

echo "[INFO] RKE2 installation completed successfully."
