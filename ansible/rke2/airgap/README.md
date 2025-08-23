# RKE2 Airgap Installation with Ansible

This directory contains Ansible roles and playbooks for installing RKE2 in an airgap environment using the tarball installation method. It provides comprehensive SSH proxy configuration for true airgap deployments with no registry dependency.

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
  - Bastion: At least 5GB for RKE2 tarballs and temporary files
  - Airgap nodes: At least 20GB for RKE2 installation

## Directory Structure

```
airgap/
├── docs/
│   ├── configuration/
│   │   ├── CNI_CONFIGURATION_GUIDE.md
│   │   ├── GROUP_VARS_GUIDE.md
│   │   ├── INVENTORY_CONFIGURATION.md
│   │   ├── RKE2_UPGRADE_GUIDE.md
│   │   └── TARBALL_DEPLOYMENT_GUIDE.md
│   └── knowledge_base/
│       └── SSH_TROUBLESHOOTING.md
├── inventory/
│   ├── group_vars/
│   │   └── all.yml.template
│   └── inventory.yml.template
├── playbooks/
│   ├── debug/
│   │   ├── diagnose-registry.yml
│   │   ├── fix-checksum-issues.yml
│   │   ├── fix-rke2-config.yml
│   │   ├── test-ssh-connectivity.yml
│   │   └── validate-upgrade-readiness.yml
│   ├── deploy/
│   │   ├── rke2-tarball-playbook.yml
│   │   ├── rke2-upgrade-playbook.yml
│   │   └── rke2-registry-config-playbook.yml
│   └── setup/
│       ├── setup-agent-nodes.yml
│       ├── setup-kubectl-access.yml
│       └── setup-ssh-keys.yml
├── roles/
│   ├── rke2_install/
│   ├── rke2_tarball/
│   ├── rke2_upgrade/
│   ├── rke2_registry_config/
│   └── ssh_setup/
├── ansible.cfg
└── README.md
```

## Installation Method

This system uses the **Tarball Method** for pure airgap deployments:

- **Playbook**: `playbooks/deploy/rke2-tarball-playbook.yml`
- **Best for**: Pure airgap environments, simple deployments
- **Features**: Uses pre-downloaded RKE2 tarballs with embedded images (no registry required)
- **Status**: [OK] **Currently Working and Tested**

## Quick Start

### 1. Configure Inventory

*** Inventory is automatically generated after Tofu apply ***

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

### 2. Generate Inventory (Alternative Method)

If you need to manually generate the inventory from Terraform state:

```bash
ansible-playbook playbooks/setup/generate-inventory-from-terraform.yml
```

### 3. Setup SSH Keys

First, ensure SSH keys are properly distributed:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/setup/setup-ssh-keys.yml
```

### 4. Run Installation

Execute the tarball installation:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-tarball-playbook.yml
```

### 5. Setup kubectl Access (Optional)

After RKE2 installation, you can set up kubectl access on the bastion node:

```bash
# Setup kubectl and copy KUBECONFIG from airgap nodes
ansible-playbook -i inventory/inventory.yml playbooks/setup/setup-kubectl-access.yml
```

This will:
- Install kubectl on the bastion node
- Copy the KUBECONFIG from the first airgap node
- Configure kubectl for both root and the ansible user
- Test connectivity to the cluster

**Note**: The tarball playbook (`playbooks/deploy/rke2-tarball-playbook.yml`) automatically includes kubectl setup, so this step is only needed if you want to set up kubectl access separately.

### 6. Configure Private Registry (Optional)

If you need to configure RKE2 to use a private registry for pulling images after installation:

```bash
# Configure private registry settings on all airgap nodes
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-registry-config-playbook.yml
```

This will:
- Create `/etc/rancher/rke2/registries.yaml` on all airgap nodes
- Configure registry mirrors and authentication
- Restart RKE2 services to apply the changes
- Verify the configuration is properly applied

**Note**: This step should only be performed after RKE2 is successfully installed and running.

## Upgrading RKE2

### 1. Validate Upgrade Readiness

Before upgrading, run the validation playbook to ensure your cluster is ready:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/debug/validate-upgrade-readiness.yml
```

This will check:
- Current RKE2 versions on all nodes
- Service status and cluster health
- Disk space and system resources
- SSH connectivity and bastion host readiness
- Generate a comprehensive readiness report

### 2. Update Target Version

Edit `inventory/group_vars/all.yml` to specify the target RKE2 version:

```yaml
# RKE2 Configuration
rke2_version: "v1.31.11+rke2r1"  # Update to desired version
```

### 3. Run the Upgrade

Execute the upgrade playbook:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-upgrade-playbook.yml
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

For detailed upgrade procedures, troubleshooting, and best practices, see [`docs/configuration/RKE2_UPGRADE_GUIDE.md`](docs/configuration/RKE2_UPGRADE_GUIDE.md).

## Configuration

### Global Variables (`inventory/group_vars/all.yml`)
**Note**: The tarball playbook (`rke2-tarball-playbook.yml`) automatically includes kubectl setup, so this step is only needed if you want to set up kubectl access separately or after using other installation methods.

### 6. Configure Private Registry (Optional)

If you need to configure RKE2 to use a private registry for pulling images after installation:

```bash
# Configure private registry settings on all airgap nodes
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-registry-config-playbook.yml
```

This will:
- Create `/etc/rancher/rke2/registries.yaml` on all airgap nodes
- Configure registry mirrors and authentication
- Restart RKE2 services to apply the changes
- Verify the configuration is properly applied

**Note**: This step should only be performed after RKE2 is successfully installed and running.

## Upgrading RKE2

### 1. Validate Upgrade Readiness

Before upgrading, run the validation playbook to ensure your cluster is ready:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/debug/validate-upgrade-readiness.yml
```

This will check:
- Current RKE2 versions on all nodes
- Service status and cluster health
- Disk space and system resources
- SSH connectivity and bastion host readiness
- Generate a comprehensive readiness report

### 2. Update Target Version

Edit `inventory/group_vars/all.yml` to specify the target RKE2 version:

```yaml
# RKE2 Configuration
rke2_version: "v1.31.11+rke2r1"  # Update to desired version
```

### 3. Run the Upgrade

Execute the upgrade playbook:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-upgrade-playbook.yml
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

For detailed upgrade procedures, troubleshooting, and best practices, see [`docs/configuration/RKE2_UPGRADE_GUIDE.md`](docs/configuration/RKE2_UPGRADE_GUIDE.md).

## Upgrading RKE2

### 1. Validate Upgrade Readiness

Before upgrading, run the validation playbook to ensure your cluster is ready:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/debug/validate-upgrade-readiness.yml
```

This will check:
- Current RKE2 versions on all nodes
- Service status and cluster health
- Disk space and system resources
- SSH connectivity and bastion host readiness
- Generate a comprehensive readiness report

### 2. Update Target Version

Edit `inventory/group_vars/all.yml` to specify the target RKE2 version:

```yaml
# RKE2 Configuration
rke2_version: "v1.31.11+rke2r1"  # Update to desired version
```

### 3. Run the Upgrade

Execute the upgrade playbook:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-upgrade-playbook.yml
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

For detailed upgrade procedures, troubleshooting, and best practices, see [`docs/configuration/RKE2_UPGRADE_GUIDE.md`](docs/configuration/RKE2_UPGRADE_GUIDE.md).

## Configuration

### Global Variables (`inventory/group_vars/all.yml`)

Key configuration options:

```yaml
# RKE2 Configuration
rke2_version: "v1.31.11+rke2r1"

# SSH Configuration
ssh_private_key_file: "~/.ssh/id_rsa"

# Network Configuration
cluster_cidr: "10.42.0.0/16"
service_cidr: "10.43.0.0/16"
cluster_dns: "10.43.0.10"

# CNI Configuration
cni: "canal"  # Options: canal, calico, cilium, multus, none

# Security Configuration
disable_components:
  - rke2-snapshot-controller
  - rke2-snapshot-controller-crd
  - rke2-snapshot-validation-webhook

# Private Registry Configuration (optional)
enable_private_registry: false
private_registry_mirrors:
  - registry: "docker.io"
    endpoints:
      - "<PRIVATE_REGISTRY_URL>"
    rewrite:
      - pattern: "^(.*)"
        replacement: "proxycache/$1"
  - registry: "quay.io"
    endpoints:
      - "<PRIVATE_REGISTRY_URL>"
    rewrite:
      - pattern: "^(.*)"
        replacement: "quaycache/$1"

private_registry_configs:
  - registry: "<PRIVATE_REGISTRY_URL>"
    auth:
      username: "<PRIVATE_REGISTRY_USERNAME>"
      password: "<PRIVATE_REGISTRY_PASSWORD>"
    tls:
      insecure_skip_verify: true
```

## CNI (Container Network Interface) Configuration

The system supports multiple CNI plugins for different networking requirements:

### Available CNI Options

- **Canal (Default)**: Flannel + Calico for balanced features and performance
- **Calico**: Advanced networking with BGP support and network policies
- **Cilium**: eBPF-based networking with advanced security and observability
- **Multus**: Multiple network interfaces per pod
- **None**: Bring your own CNI solution

### Quick CNI Selection

Edit [`inventory/group_vars/all.yml`](inventory/group_vars/all.yml.template) to choose your CNI:

```yaml
# For default balanced networking
cni: "canal"

# For advanced networking and policies
cni: "calico"

# For security and observability
cni: "cilium"

# For multiple network interfaces
cni: "multus"

# For custom CNI solutions
cni: "none"
```

For detailed CNI configuration options, troubleshooting, and best practices, see [`docs/configuration/CNI_CONFIGURATION_GUIDE.md`](docs/configuration/CNI_CONFIGURATION_GUIDE.md).

## Private Registry Configuration

After RKE2 is installed, you can optionally configure it to use private registries for pulling container images. This is useful when you need to redirect image pulls to internal registries or mirror registries.

### Configuration Options

Edit `inventory/group_vars/all.yml` to configure private registry settings:

```yaml
# Enable private registry configuration
enable_private_registry: true

# Configure registry mirrors
private_registry_mirrors:
  - registry: "docker.io"
    endpoints:
      - "https://your-private-registry.com"
    rewrite:
      - pattern: "^(.*)"
        replacement: "proxycache/$1"

# Configure registry authentication and TLS
private_registry_configs:
  - registry: "your-private-registry.com"
    auth:
      username: "your-username"
      password: "your-password"
    tls:
      insecure_skip_verify: true
```

### Apply Registry Configuration

After RKE2 installation, run the registry configuration playbook:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-registry-config-playbook.yml
```

This playbook will:
- Create `/etc/rancher/rke2/registries.yaml` on all airgap nodes
- Configure containerd to use the specified registry mirrors
- Apply authentication and TLS settings
- Restart RKE2 services to apply the changes
- Verify the configuration is working

### Registry Configuration Features

- **Mirror Configuration**: Redirect pulls from public registries to private mirrors
- **Path Rewriting**: Transform image paths using regex patterns for different registry layouts
- **Authentication**: Support for username/password and token-based authentication
- **TLS Configuration**: Custom certificates or skip TLS verification for testing
- **Service Restart**: Automatic restart of RKE2 services to apply configuration changes

**Important**: Private registry configuration should only be applied after RKE2 is successfully installed and running.

## Verification

After installation, verify your cluster:

### From the Bastion Node (Recommended)

After running the tarball playbook or `setup-kubectl-access.yml`:

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
ansible-playbook -i inventory/inventory.yml playbooks/debug/validate-upgrade-readiness.yml

# Fix RKE2 checksum verification issues
ansible-playbook -i inventory/inventory.yml playbooks/debug/fix-checksum-issues.yml

# Fix RKE2 configuration issues
ansible-playbook -i inventory/inventory.yml playbooks/debug/fix-rke2-config.yml

# Setup agent nodes (for multi-node clusters)
ansible-playbook -i inventory/inventory.yml playbooks/setup/setup-agent-nodes.yml

# Setup kubectl access on bastion (if not done during installation)
ansible-playbook -i inventory/inventory.yml playbooks/setup/setup-kubectl-access.yml

# Configure private registries (after RKE2 installation)
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-registry-config-playbook.yml
```

### Common Issues

1. **Checksum Verification Failures**
   - **Error**: `download sha256 does not match` during RKE2 installation
   - **Cause**: Corrupted downloads, version mismatches, or cached files
   - **Solution**: Run the checksum fix playbook:
     ```bash
     ansible-playbook -i inventory/inventory.yml playbooks/debug/fix-checksum-issues.yml
     ```
   - **Prevention**: Ensure `rke2_version` in `inventory/group_vars/all.yml` matches an existing GitHub release

2. **SSH Connectivity Issues**
   - Ensure SSH keys are properly distributed: `playbooks/setup/setup-ssh-keys.yml`
   - Check SSH proxy configuration in inventory
   - Verify bastion host accessibility

3. **RKE2 Service Issues**
   - Check service status: `systemctl status rke2-server`
   - View logs: `journalctl -u rke2-server --no-pager -n 50`
   - Verify configuration: `cat /etc/rancher/rke2/config.yaml`

4. **Private Registry Issues**
   - **Error**: `failed to pull image` or `connection refused` errors for container images
   - **Cause**: Registry configuration not applied or incorrect registry settings
   - **Solution**: Verify registry configuration and connectivity:
     ```bash
     # Check registries.yaml exists and is correct
     cat /etc/rancher/rke2/registries.yaml
     
     # Test registry connectivity from airgap nodes
     curl -k https://your-private-registry.com/v2/
     
     # Re-apply registry configuration if needed
     ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-registry-config-playbook.yml
     ```
   - **Check containerd logs**: `/var/lib/rancher/rke2/agent/containerd/containerd.log`

5. **Configuration Issues**
   - Use `playbooks/debug/fix-rke2-config.yml` to regenerate configuration
   - Verify RKE2 version matches an existing GitHub release

### Debug Mode

Run with increased verbosity for troubleshooting:

```bash
ansible-playbook -vv -i inventory/inventory.yml playbooks/deploy/rke2-tarball-playbook.yml
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

- **[`docs/configuration/INVENTORY_CONFIGURATION.md`](docs/configuration/INVENTORY_CONFIGURATION.md)**: Complete inventory setup guide
- **[`docs/configuration/RKE2_UPGRADE_GUIDE.md`](docs/configuration/RKE2_UPGRADE_GUIDE.md)**: Comprehensive RKE2 upgrade procedures and troubleshooting
- **[`docs/configuration/CNI_CONFIGURATION_GUIDE.md`](docs/configuration/CNI_CONFIGURATION_GUIDE.md)**: Container Network Interface (CNI) configuration and selection
- **[`docs/configuration/GROUP_VARS_GUIDE.md`](docs/configuration/GROUP_VARS_GUIDE.md)**: Configuration variables reference
- **[`docs/configuration/TARBALL_DEPLOYMENT_GUIDE.md`](docs/configuration/TARBALL_DEPLOYMENT_GUIDE.md)**: Detailed tarball deployment instructions
- **[`docs/knowledge_base/SSH_TROUBLESHOOTING.md`](docs/knowledge_base/SSH_TROUBLESHOOTING.md)**: SSH connectivity troubleshooting guide

## Notes

- **Airgap Environment**: All communication between airgap nodes goes through the bastion host
- **SSH Proxy**: Automatic SSH proxy configuration for true airgap deployment
- **Tarball Method**: Uses pre-downloaded RKE2 tarballs with embedded images, eliminating registry dependency
- **Security**: TLS certificates, authentication, and secure communication by default
- **Simplicity**: Single, reliable deployment approach optimized for airgap environments
- **Diagnostics**: Comprehensive troubleshooting tools and documentation
