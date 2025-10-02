#!/bin/bash
set -euo pipefail

# ===== Arguments =====
RANCHER_CHART_REPO_URL=$1   # e.g. https://releases.rancher.com/server-charts/latest
RANCHER_CHART_VERSION=$2    # e.g. 2.11.3 TODO: drop this field as it is no needed anymore
CERT_MANAGER_VERSION=$3     # e.g. 1.14.3
CERT_TYPE=$4                # self-signed | lets-encrypt
HOSTNAME=$5                 # e.g. rancher.example.com
RANCHER_IMAGE=$6            # e.g. rancher/rancher
RANCHER_IMAGE_TAG=$7        # e.g. v2.11.3
BOOTSTRAP_PASSWORD=$8       # e.g. admin123
LETS_ENCRYPT_EMAIL=${9:-}   # optional, only needed for lets-encrypt

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# ===== Detect architecture =====
ARCH=$(uname -m)
case $ARCH in
  x86_64) KUBECTL_ARCH="amd64" ;;
  arm64|aarch64) KUBECTL_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ===== Install kubectl =====
echo "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/${KUBECTL_ARCH}/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

# ===== Install Helm =====
echo "Installing Helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod +x get_helm.sh && ./get_helm.sh && rm get_helm.sh

# ===== Add Helm repos =====
# echo "Adding Rancher chart repo..."
# helm repo add rancher-charts ${RANCHER_CHART_REPO_URL}

# ===== Install cert-manager =====
echo "Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version ${CERT_MANAGER_VERSION} \
  --set crds.enabled=true

kubectl get pods --namespace cert-manager

echo "Waiting 60 seconds for cert-manager..."
sleep 60

# ===== Install Rancher =====
echo "Installing Rancher with ${CERT_TYPE} certs..."
kubectl create ns cattle-system --dry-run=client -o yaml | kubectl apply -f -

HELM_BASE="helm upgrade --install rancher ./rancher.tgz \
  --namespace cattle-system \
  --set global.cattle.psp.enabled=false \
  --set hostname=${HOSTNAME} \
  --set rancherImage=${RANCHER_IMAGE} \
  --set rancherImageTag=${RANCHER_IMAGE_TAG} \
  --set agentTLSMode=system-store \
  --set bootstrapPassword=${BOOTSTRAP_PASSWORD}"

case "${CERT_TYPE}" in
  self-signed)
    $HELM_BASE
    ;;
  lets-encrypt)
    $HELM_BASE \
      --set ingress.tls.source=letsEncrypt \
      --set letsEncrypt.email=${LETS_ENCRYPT_EMAIL} \
      --set letsEncrypt.ingress.class=nginx
    ;;
  *)
    echo "Unsupported CERT_TYPE: ${CERT_TYPE}"
    exit 1
    ;;
esac

# ===== Wait for Rancher Deployment =====
echo "Waiting for Rancher rollout..."
kubectl -n cattle-system rollout status deploy/rancher
kubectl -n cattle-system get deploy rancher

echo "Rancher installation completed."
