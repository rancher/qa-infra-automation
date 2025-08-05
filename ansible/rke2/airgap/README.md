# RKE2 Airgap Installation with Ansible

This directory contains Ansible roles and playbooks for installing RKE2 in an airgap environment. It supports multiple installation methods with comprehensive SSH proxy configuration for true airgap deployments.

## Prerequisites

- Ansible 2.9+
- A bastion host with internet access
- One or more airgap nodes for the RKE2 cluster
- SSH key pair for node access:
  - Private key file (e.g., `~/.ssh/id_rsa`)
  - Public key file (e.g., `~/.ssh/id_rsa.pub`)
- SSH access to all nodes through the bastion host
- Sudo privileges on all nodes
- Sufficient disk space:
  - Bastion: At least 10GB for registry and images
  - Airgap nodes: At least 20GB for RKE2 installation

## Directory Structure

```
airgap/
├── docs/
├── group_vars/
├── inventory/
├── playbooks/
├── roles/
├── ansible.cfg
└── README.md
```

## Installation Methods

The system supports 4 different installation methods, each optimized for different scenarios:

### 1. **Tarball Method** (Recommended for Pure Airgap) ✅
- **Playbook**: `playbooks/rke2-tarball-playbook.yml`
- **Best for**: Pure airgap environments, simple deployments
- **Features**: Uses pre-downloaded RKE2 tarballs with embedded images (no registry required)
- **Status**: ✅ **Currently Working and Tested**

### 2. **Registry Distribution Method**
- **Playbook**: `playbooks/rke2-registry-distribution-playbook.yml`
- **Best for**: Centralized image management, multiple clusters
- **Features**: Sets up private registry on bastion and distributes images
- **Status**:  **In Progress**

### 3. **Docker Hub Method**
- **Playbook**: `playbooks/rke2-dockerhub-playbook.yml`
- **Best for**: Testing, development environments with internet access
- **Features**: Pulls images directly from Docker Hub (requires internet)
- **Status**:  **In Progress**

### 4. **Dynamic Images Method**
- **Playbook**: `playbooks/rke2-dynamic-images-playbook.yml`
- **Best for**: Latest versions, automated image discovery
- **Features**: Auto-discovers images from RKE2 GitHub releases
- **Status**:  **In Progress**

## Quick Start

### 1. Configure Installation Method

Edit `group_vars/all.yml` to set your preferred installation method:

```yaml
# Installation Method Configuration
# Available methods:
#   - "tarball": Uses pre-downloaded RKE2 tarballs with embedded images (no registry required)
#     Playbook: rke2-tarball-playbook.yml
#     Best for: Pure airgap environments, simple deployments
#
#   - "registry_distribution": Sets up private registry on bastion and distributes images
#     Playbook: rke2-registry-distribution-playbook.yml  
#     Best for: Centralized image management, multiple clusters
#
#   - "dockerhub": Pulls images directly from Docker Hub (requires internet)
#     Playbook: rke2-dockerhub-playbook.yml
#     Best for: Testing, development environments with internet access
#
#   - "dynamic_images": Auto-discovers images from RKE2 GitHub releases
#     Playbook: rke2-dynamic-images-playbook.yml
#     Best for: Latest versions, automated image discovery
installation_method: "tarball"
```

### 2. Configure Inventory

Update `inventory/inventory.yml` with your environment details:

```yaml
all:
  vars:
    # Global SSH configuration - update this path to match your environment
    ssh_private_key_file: "~/.ssh/id_rsa"
    bastion_user: "ubuntu"
    bastion_host: "<BASTION_PUBLIC_DNS>"
    
  children:
    bastion:
      hosts:
        bastion-node:
          ansible_host: "{{ bastion_host }}"
          ansible_user: "{{ bastion_user }}"
          ansible_ssh_private_key_file: "{{ ssh_private_key_file }}"
          
    airgap_nodes:
      vars:
        ansible_user: "ubuntu"
        ansible_ssh_private_key_file: "{{ ssh_private_key_file }}"
        ansible_ssh_common_args: "-o ProxyCommand='ssh -W %h:%p -i {{ ssh_private_key_file }} {{ bastion_user }}@{{ bastion_host }}' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
        
      hosts:
        rke2-server-0:
          ansible_host: "<AIRGAP_NODE_PRIVATE_IP>"
        rke2-server-1:
          ansible_host: "<AIRGAP_NODE_PRIVATE_IP>"
        rke2-server-2:
          ansible_host: "<AIRGAP_NODE_PRIVATE_IP>"
```

### 3. Setup SSH Keys

First, ensure SSH keys are properly distributed:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/setup-ssh-keys.yml
```

### 4. Run Installation

Choose your installation method:

```bash
# Tarball method
ansible-playbook -i inventory/inventory.yml playbooks/rke2-tarball-playbook.yml
```

### 5. Setup kubectl Access (Optional)

After RKE2 installation, you can set up kubectl access on the bastion node:

```bash
# Setup kubectl and copy KUBECONFIG from airgap nodes
ansible-playbook -i inventory/inventory.yml playbooks/setup-kubectl-access.yml
```

This will:
- Install kubectl on the bastion node
- Copy the KUBECONFIG from the first airgap node
- Configure kubectl for both root and the ansible user
- Test connectivity to the cluster

**Note**: The tarball playbook (`rke2-tarball-playbook.yml`) automatically includes kubectl setup, so this step is only needed if you want to set up kubectl access separately or after using other installation methods.

## Upgrading RKE2

### 1. Validate Upgrade Readiness

Before upgrading, run the validation playbook to ensure your cluster is ready:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/validate-upgrade-readiness.yml
```

This will check:
- Current RKE2 versions on all nodes
- Service status and cluster health
- Disk space and system resources
- SSH connectivity and bastion host readiness
- Generate a comprehensive readiness report

### 2. Update Target Version

Edit `group_vars/all.yml` to specify the target RKE2 version:

```yaml
# RKE2 Configuration
rke2_version: "v1.31.11+rke2r1"  # Update to desired version
```

### 3. Run the Upgrade

Execute the upgrade playbook:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/rke2-upgrade-playbook.yml
```

The upgrade process will:
- Download the new RKE2 version on the bastion host
- Upgrade the server node first (with automatic rollback on failure)
- Upgrade agent nodes one by one to maintain cluster availability
- Verify cluster functionality after each upgrade
- Update kubectl on the bastion host

### 4. Upgrade Features

- **Zero-downtime upgrades**: Agents are upgraded serially while maintaining cluster availability
- **Automatic rollback**: Failed upgrades trigger automatic rollback to previous version
- **Comprehensive validation**: Pre and post-upgrade checks ensure cluster health
- **Backup creation**: Automatic backups of configuration and binaries before upgrade
- **Progress monitoring**: Detailed logging and status reporting throughout the process

For detailed upgrade procedures, troubleshooting, and best practices, see [`docs/RKE2_UPGRADE_GUIDE.md`](docs/RKE2_UPGRADE_GUIDE.md).

## Configuration

### Global Variables (`group_vars/all.yml`)

Key configuration options:

```yaml
# RKE2 Configuration
rke2_version: "v1.31.11+rke2r1"
installation_method: "tarball"

# SSH Configuration
ssh_private_key_file: "~/.ssh/id_rsa"

# Network Configuration
cluster_cidr: "10.42.0.0/16"
service_cidr: "10.43.0.0/16"
cluster_dns: "10.43.0.10"

# Security Configuration
disable_components:
  - rke2-snapshot-controller
  - rke2-snapshot-controller-crd
  - rke2-snapshot-validation-webhook
```

### Bastion Configuration (`group_vars/bastion.yml`)

Registry and Docker configuration for the bastion host:

```yaml
# Registry Configuration
registry_port: 5000
registry_data_dir: "/opt/registry/data"
registry_certs_dir: "/opt/registry/certs"
registry_auth_dir: "/opt/registry/auth"

# Docker Configuration
docker_insecure_registries:
  - "localhost:5000"

# Network Configuration
registry_allowed_networks:
  - "172.31.0.0/16"  # Adjust to match your VPC CIDR
  - "10.0.0.0/8"     # Common private network range
```

## Verification

After installation, verify your cluster:

### From the Bastion Node (Recommended)

If you used the tarball playbook or ran `setup-kubectl-access.yml`:

```bash
# kubectl is automatically configured on the bastion node
kubectl get nodes -o wide
kubectl get pods -A
kubectl get services -A

# Check cluster info
kubectl cluster-info
```

### From the RKE2 Server Node

```bash
# On the RKE2 server node
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=$PATH:/var/lib/rancher/rke2/bin

# Check cluster status
kubectl get nodes -o wide
kubectl get pods -A
```

Expected output for a successful single-node deployment:
```
NAME              STATUS   ROLES                       AGE     VERSION          INTERNAL-IP    
ip-172-31-4-247   Ready    control-plane,etcd,master   8m19s   v1.31.1+rke2r1   172.31.4.247   
```

## Troubleshooting

### Diagnostic Tools

The project includes several diagnostic playbooks:

```bash
# Validate upgrade readiness
ansible-playbook -i inventory/inventory.yml playbooks/validate-upgrade-readiness.yml

# Check registry status
ansible-playbook -i inventory/inventory.yml playbooks/diagnose-registry.yml

# Fix RKE2 configuration issues
ansible-playbook -i inventory/inventory.yml playbooks/fix-rke2-config.yml

# Setup agent nodes (for multi-node clusters)
ansible-playbook -i inventory/inventory.yml playbooks/setup-agent-nodes.yml

# Setup kubectl access on bastion (if not done during installation)
ansible-playbook -i inventory/inventory.yml playbooks/setup-kubectl-access.yml
```

### Common Issues

1. **SSH Connectivity Issues**
   - Ensure SSH keys are properly distributed: `playbooks/setup-ssh-keys.yml`
   - Check SSH proxy configuration in inventory
   - Verify bastion host accessibility

2. **Registry Connection Issues** (for registry-based methods)
   - Check if registry service is running: `docker ps | grep registry`
   - Verify port 5000 is accessible: `nc -zv bastion-host 5000`
   - Check registry logs: `docker logs registry`

3. **RKE2 Service Issues**
   - Check service status: `systemctl status rke2-server`
   - View logs: `journalctl -u rke2-server --no-pager -n 50`
   - Verify configuration: `cat /etc/rancher/rke2/config.yaml`

4. **Installation Method Mismatch**
   - Ensure `installation_method` in `group_vars/all.yml` matches your chosen playbook
   - Use `playbooks/fix-rke2-config.yml` to regenerate configuration

### Debug Mode

Run with increased verbosity for troubleshooting:

```bash
ansible-playbook -vv -i inventory/inventory.yml playbooks/rke2-tarball-playbook.yml
```

## Advanced Configuration

### Multi-Node Clusters

The system supports multi-node clusters:
- First node in `airgap_nodes` becomes the server (control plane)
- Additional nodes become agents
- Token sharing is handled automatically
- SSH proxy configuration ensures proper communication

## Documentation

Detailed documentation is available in the `docs/` directory:

- **`INVENTORY_CONFIGURATION.md`**: Complete inventory setup guide
- **`RKE2_UPGRADE_GUIDE.md`**: Comprehensive RKE2 upgrade procedures and troubleshooting
- **`GROUP_VARS_GUIDE.md`**: Configuration variables reference
- **`TARBALL_DEPLOYMENT_GUIDE.md`**: Detailed tarball deployment instructions
- **`SSH_TROUBLESHOOTING.md`**: SSH connectivity troubleshooting guide

## Notes

- **Airgap Environment**: All communication between airgap nodes goes through the bastion host
- **SSH Proxy**: Automatic SSH proxy configuration for true airgap deployment
- **Installation Methods**: Templates automatically adapt based on `installation_method` setting
- **Security**: TLS certificates, authentication, and secure communication by default
- **Flexibility**: Multiple deployment approaches for different scenarios
- **Diagnostics**: Comprehensive troubleshooting tools and documentation

## Success Story

This deployment system has been successfully tested and deployed:
- ✅ **Working single-node RKE2 cluster** using tarball method
- ✅ **kubectl access from bastion node** with automatic KUBECONFIG setup
- ✅ **No registry dependency** for pure airgap environments
- ✅ **Proper SSH proxy configuration** for airgap communication
- ✅ **Comprehensive troubleshooting tools** for issue resolution
- ✅ **Multiple deployment methods** for different scenarios
- ✅ **Complete documentation** and configuration examples

The tarball method provides a robust, registry-free solution perfect for airgap environments, while other methods offer flexibility for different deployment scenarios. The automatic kubectl setup on the bastion node provides convenient cluster management without requiring direct access to airgap nodes.
