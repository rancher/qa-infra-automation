# Combined Dockerfile for infrastructure automation
# Includes OpenTofu, Ansible, and supporting CLI tools
#
# Build command from root directory:
# docker build --build-arg TOFU_VERSION=1.11.6 -t infra-runner:latest .

FROM python:3.14-slim

ARG TOFU_VERSION=1.11.5

# Update package lists and install essential tools
RUN apt-get update && \
    apt-get install -y \
    curl \
    openssh-client \
    gettext \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install OpenTofu
RUN curl -fsSL -o /tmp/opentofu.tar.gz "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_amd64.tar.gz" && \
    tar -xzf /tmp/opentofu.tar.gz -C /usr/local/bin && \
    rm /tmp/opentofu.tar.gz

# Install Node.js and npm for steadybit
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x -o /tmp/nodesource_setup.sh && \
    bash /tmp/nodesource_setup.sh && \
    rm /tmp/nodesource_setup.sh && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install CLIs: steadybit, kubectl, and helm
RUN npm install -g steadybit

# Install kubectl
RUN arch="$(uname -m)" && \
    case "$arch" in \
      x86_64) kubectl_arch=amd64 ;; \
      aarch64|arm64) kubectl_arch=arm64 ;; \
      *) echo "Unsupported architecture for kubectl: $arch" >&2; exit 1 ;; \
    esac && \
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${kubectl_arch}/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install Helm
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && \
    ./get_helm.sh && \
    rm get_helm.sh

# Install Ansible and dependencies
RUN pip install --no-cache-dir ansible kubernetes && \
    ansible-galaxy collection install cloud.terraform kubernetes.core

# Set working directory
WORKDIR /workspace

# Default shell command (no entrypoint)
CMD ["/bin/sh"]
