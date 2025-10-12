# Use a minimal base image with Python, as Ansible requires it
FROM python:3.14-slim

# Update package lists and install curl
RUN apt-get update && \
    apt-get install -y curl

# Install NodeJS and NPM, then remove package lists
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install relevant CLIs: steadybit, kubectl, and helm
RUN npm install -g steadybit

RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && \
    ./get_helm.sh && \
    rm get_helm.sh

# Set working directory inside the container
WORKDIR /ansible

# Install Ansible
RUN pip install ansible kubernetes

# Set an entrypoint to make the container act as an executable for ansible-playbook
ENTRYPOINT ["ansible-playbook"]

