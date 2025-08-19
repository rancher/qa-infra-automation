# RKE2 Airgap Deployment - Tarball Installation Guide

This guide explains how to perform a complete RKE2 airgap deployment using official RKE2 release tarballs with your existing Ansible roles.

## Overview

The tarball approach is the **most reliable method** for RKE2 airgap deployments because:
- **Official RKE2 releases** - Uses verified, official Rancher releases
- **Complete bundles** - Includes all necessary binaries and container images
- **No registry dependencies** - Doesn't require external registry access
- **Proven method** - This is Rancher's recommended approach for airgap installations

## Your Existing Roles

You already have excellent roles that handle the entire tarball deployment process:

### 1. **`rke2_tarball` Role**
**Purpose**: Downloads and prepares RKE2 release artifacts on the bastion host
**What it does**:
- Downloads RKE2 install script from GitHub
- Downloads RKE2 binary, images, and checksums for specified version
- Creates a compressed bundle with all artifacts
- Verifies file integrity and permissions

### 2. **`rke2_install` Role** 
**Purpose**: Installs RKE2 on airgap nodes using the prepared bundle
**What it does**:
- Copies bundle from bastion to airgap nodes via SCP
- Extracts and organizes RKE2 artifacts
- Runs RKE2 install script with offline artifacts
- Configures and starts RKE2 server/agent services
- Retrieves kubeconfig and node tokens
- Sets up cluster connectivity

## Files

- **`playbooks/deploy/rke2-tarball-playbook.yml`**: Main playbook orchestrating the deployment
- **`inventory/group_vars/all.yml`**: Configuration variables for tarball deployment
- **`roles/rke2_tarball/`**: Your existing role for artifact preparation
- **`roles/rke2_install/`**: Your existing role for RKE2 installation
- **`docs/configuration/TARBALL_DEPLOYMENT_GUIDE.md`**: This documentation

## Prerequisites

1. **Bastion Host**: Must have internet access to download RKE2 releases
2. **Airgap Nodes**: No internet access required
3. **SSH Access**: Bastion must be able to SSH to all airgap nodes
4. **Inventory**: Properly configured with bastion and airgap node groups

## Quick Start

### 1. **Run the Tarball Deployment**

```bash
cd ansible/rke2/airgap
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-tarball-playbook.yml
```

### 2. **What Happens**

**Phase 1: Artifact Preparation (Bastion Host)**
```
[bastion] → Downloads RKE2 v1.31.1+rke2r1 artifacts
[bastion] → Creates /opt/rke2-files/rke2-bundle.tar.gz
[bastion] → Verifies bundle integrity
```

**Phase 2: RKE2 Installation (Airgap Nodes)**
```
[airgap-nodes] → Copies bundle from bastion via SCP
[airgap-nodes] → Extracts RKE2 artifacts locally
[airgap-nodes] → Installs RKE2 server (first node)
[airgap-nodes] → Installs RKE2 agents (remaining nodes)
[airgap-nodes] → Starts services and joins cluster
```

**Phase 3: Verification**
```
[server-node] → Checks cluster status
[server-node] → Retrieves kubeconfig
[localhost] → Saves kubeconfig locally
```

## Configuration

### **Basic Configuration** (`inventory/group_vars/all.yml`)

```yaml
# RKE2 Version
rke2_version: "v1.31.1+rke2r1"

# SSH Key
ssh_private_key_file: "~/.ssh/your-key"

# Network Settings
cluster_cidr: "10.42.0.0/16"
service_cidr: "10.43.0.0/16"
cluster_dns: "10.43.0.10"
```

### **Advanced Configuration**

```yaml
# Security - Disable unnecessary components
disable_components:
  - rke2-snapshot-controller
  - rke2-snapshot-controller-crd
  - rke2-snapshot-validation-webhook

# Performance Tuning
max_pods_per_node: 110
node_cidr_mask_size: 24

# Timeouts
install_timeout: 300
service_start_timeout: 120
cluster_ready_timeout: 600
```

## Deployment Process Details

### **Phase 1: Bastion Preparation**

Your `rke2_tarball` role downloads these artifacts:

1. **Install Script**: `https://raw.githubusercontent.com/rancher/rke2/master/install.sh`
2. **RKE2 Binary**: `rke2.linux-amd64` 
3. **Container Images**: `rke2-images.linux-amd64.tar.gz`
4. **Checksums**: `sha256sum-amd64.txt`

All files are bundled into: `/opt/rke2-files/rke2-bundle.tar.gz`

### **Phase 2: Node Installation**

Your `rke2_install` role performs these steps:

1. **Bundle Transfer**: SCP from bastion to each airgap node
2. **Extraction**: Unpacks bundle to `/tmp/rke2-artifacts/`
3. **Server Install**: First node becomes RKE2 server
4. **Agent Install**: Remaining nodes join as agents
5. **Service Management**: Starts and enables systemd services

### **Phase 3: Cluster Setup**

1. **Token Retrieval**: Gets node token from server
2. **Agent Configuration**: Configures agents to join server
3. **Kubeconfig**: Retrieves and saves cluster access credentials

## Verification

### **Check Cluster Status**

```bash
# On the server node
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
/var/lib/rancher/rke2/bin/kubectl get nodes -o wide
```

### **Check Services**

```bash
# Server node
sudo systemctl status rke2-server

# Agent nodes  
sudo systemctl status rke2-agent
```

### **Access from Local Machine**

```bash
# If kubeconfig was copied locally
kubectl get nodes
kubectl get pods --all-namespaces
```

## Troubleshooting

### **Common Issues**

1. **Download Failures on Bastion**
   ```bash
   # Check internet connectivity
   curl -I https://github.com/rancher/rke2/releases/
   
   # Verify RKE2 version exists
   curl -I https://github.com/rancher/rke2/releases/tag/v1.31.1+rke2r1
   ```

2. **Bundle Transfer Failures**
   ```bash
   # Test SSH connectivity from bastion
   ssh -i ~/.ssh/your-key user@airgap-node 'echo "SSH OK"'
   
   # Check bundle exists on bastion
   ls -la /opt/rke2-files/rke2-bundle.tar.gz
   ```

3. **Installation Failures**
   ```bash
   # Check extracted artifacts
   ls -la /tmp/rke2-artifacts/
   
   # Check install script permissions
   ls -la /tmp/rke2-install.sh
   
   # Manual installation test
   sudo INSTALL_RKE2_ARTIFACT_PATH=/tmp/rke2-artifacts sh /tmp/rke2-install.sh
   ```

4. **Service Start Failures**
   ```bash
   # Check service logs
   sudo journalctl -u rke2-server -f
   sudo journalctl -u rke2-agent -f
   
   # Check configuration
   sudo cat /etc/rancher/rke2/config.yaml
   ```

### **Debug Commands**

```bash
# Check bundle contents
tar -tzf /opt/rke2-files/rke2-bundle.tar.gz

# Verify checksums
cd /tmp/rke2-artifacts
sha256sum -c sha256sum-amd64.txt

# Check RKE2 binary
/tmp/rke2-artifacts/rke2 --version

# Test container images
sudo ctr --address /run/k3s/containerd/containerd.sock images list
```

## Customization

### **Different RKE2 Version**

1. Update `inventory/group_vars/all.yml`:
```yaml
rke2_version: "v1.32.0+rke2r1"
```

2. Verify the version exists on [RKE2 Releases](https://github.com/rancher/rke2/releases)

### **Custom Network Configuration**

```yaml
cluster_cidr: "192.168.0.0/16"
service_cidr: "10.96.0.0/12" 
cluster_dns: "10.96.0.10"
```

### **Additional Node Configuration**

```yaml
node_labels:
  environment: "production"
  zone: "us-west-2a"

node_taints:
  - "dedicated=gpu:NoSchedule"
```

## Advantages of Tarball Approach

1. **[OK] Official Support**: Uses Rancher's recommended airgap method
2. **[OK] Complete Packages**: Includes all necessary components
3. **[OK] Version Consistency**: Ensures all components match RKE2 version
4. **[OK] No Registry Dependencies**: Works without external registries
5. **[OK] Reliable Downloads**: GitHub releases are highly available
6. **[OK] Integrity Verification**: Includes checksums for verification
7. **[OK] Proven Method**: Widely used in production environments

## Security Considerations

- RKE2 artifacts are downloaded from official GitHub releases
- Checksums are verified to ensure file integrity
- SSH keys are used for secure transfer between bastion and airgap nodes
- Bundle contains official, signed container images
- No external registry dependencies reduce attack surface

## Next Steps

After successful deployment:

1. **Configure Networking**: Set up ingress controllers and load balancers
2. **Install Applications**: Deploy your workloads using the distributed images
3. **Set up Monitoring**: Configure cluster monitoring and logging
4. **Backup Configuration**: Save cluster configuration and certificates
5. **Update Procedures**: Plan for future RKE2 version updates

This tarball approach provides the most reliable foundation for production RKE2 airgap deployments using your existing, well-designed Ansible roles.