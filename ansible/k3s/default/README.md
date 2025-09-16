# K3s Cluster Ansible Playbook

This playbook deploys a K3s Kubernetes cluster using Ansible roles for improved maintainability and idempotency.

## Features

- **Ansible Roles**: Uses modular Ansible roles instead of bash scripts
- **Terraform Integration**: Works with or without Terraform/OpenTofu
- **Security Hardening**: Optional CIS hardening with kernel security parameters
- **Flexible Node Roles**: Supports etcd, control-plane, and worker role combinations
- **Idempotent**: Ansible tracks what's been done and won't redo completed tasks

## Prerequisites

Before running the playbook, ensure you have the following in addition to the [general ansible prereqs](../../README.md):

- SSH access to the target nodes
- A valid inventory file (see inventory options below)
- A `vars.yaml` file with necessary variables

## Inventory Options

Choose one of the following inventory approaches:

### Option 1: Terraform/OpenTofu (Dynamic)

For infrastructure managed by Terraform/OpenTofu:

```bash
# Set required environment variables
export TF_WORKSPACE="your-workspace"
export TERRAFORM_NODE_SOURCE="tofu/aws/modules/cluster_nodes"

# Use the Terraform inventory
ansible-playbook -i inventory-terraform.yml k3s-playbook.yml --extra-vars "@vars.yaml"
```

### Option 2: Static Inventory

For manually managed infrastructure:

```bash
# Set required environment variables
export MASTER_IP="192.168.1.10"
export MASTER_ROLE="etcd,cp"
export SERVER1_IP="192.168.1.11"  # Optional
export SERVER1_ROLE="etcd,cp"     # Optional
export WORKER1_IP="192.168.1.20"  # Optional
export WORKER1_ROLE="worker"       # Optional
export ANSIBLE_USER="ubuntu"
export ANSIBLE_SSH_KEY="~/.ssh/id_rsa"

# Generate inventory from template
envsubst < inventory-static.yml > my-inventory.yml

# Use the static inventory
ansible-playbook -i my-inventory.yml k3s-playbook.yml --extra-vars "@vars.yaml"
```

## Usage

### Basic Deployment

```bash
# Set ANSIBLE_CONFIG (optional)
export ANSIBLE_CONFIG=/path/to/qa-infra-automation/ansible/k3s/default/ansible.cfg

# Run with Terraform inventory
ansible-playbook -i inventory-terraform.yml k3s-playbook.yml --extra-vars "@vars.yaml"

# Or run with static inventory
ansible-playbook -i my-inventory.yml k3s-playbook.yml --extra-vars "@vars.yaml"
```

### Verbose Output for Debugging

```bash
ansible-playbook -i inventory-terraform.yml k3s-playbook.yml --extra-vars "@vars.yaml" -vvv
```

## Configuration

### Sample `vars.yaml`

```yaml
# K3s version and installation
kubernetes_version: 'v1.28.15+k3s1'
kubeconfig_file: './kubeconfig.yaml'

# Required for standalone mode (when not using Terraform)
kube_api_host: "${KUBE_API_HOST}"
fqdn: "${FQDN:-}"

# Optional server/worker flags
server_flags: |
  disable:
    - traefik
  cluster-cidr: "10.42.0.0/16"
  service-cidr: "10.43.0.0/16"

worker_flags: |
  node-label:
    - "environment=production"

# Optional channel for K3s installation
channel: ""
```

### Node Roles

The playbook supports flexible node role combinations:

- **etcd**: Runs etcd database
- **cp**: Runs control-plane components (API server, scheduler, controller-manager)  
- **worker**: Runs workloads

Common combinations:

- `etcd,cp,worker`: All-in-one node (default)
- `etcd,cp`: Control-plane + etcd (no workloads)
- `cp`: Control-plane only (external etcd)
- `worker`: Worker node only

## Architecture

### Ansible Role Structure

```text
roles/k3s_install/
├── defaults/main.yml     # Default variables
├── handlers/main.yml     # Service restart handlers
├── tasks/main.yml        # Main installation tasks
└── templates/
    ├── server-config.yaml.j2  # K3s server configuration
    └── agent-config.yaml.j2   # K3s agent configuration
```

### Benefits of Ansible Roles

- **Idempotency**: Won't redo completed tasks
- **Better error handling**: Ansible's built-in error handling
- **Conditional execution**: Tasks run only when needed
- **Maintainability**: Modular, reusable code
- **Debugging**: Better visibility into what's happening
