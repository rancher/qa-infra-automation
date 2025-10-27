# K3s Cluster Ansible Playbook

This playbook deploys a K3s Kubernetes cluster using Ansible roles for improved maintainability.

## Prerequisites

Before running the playbook, ensure you have the following in addition to the [general ansible prereqs](../../README.md):

- SSH access to the target nodes
- A valid inventory file (see inventory options below)
- A `vars.yaml` file with necessary variables

## Inventory Options

Choose one of the following inventory approaches:

### Option 1: Terraform/OpenTofu

For infrastructure managed by Terraform/OpenTofu:

```bash
# Set required environment variables
export TF_WORKSPACE="your-workspace"
export TERRAFORM_NODE_SOURCE="tofu/aws/modules/cluster_nodes"

# Use the Terraform inventory
ansible-playbook -i inventory-template.yml k3s-playbook.yml --extra-vars "@vars.yaml"
```

### Option 2: Generic Inventory

For "manually" managed infrastructure:

```bash
# Set required environment variables
export MASTER_IP="192.168.1.10"
export MASTER_ROLE="etcd,cp,worker"
export SERVER1_IP="192.168.1.11"            # Optional
export SERVER1_ROLE="etcd,cp,worker"        # Optional
export WORKER1_IP="192.168.1.20"            # Optional
export WORKER1_ROLE="worker"                # Optional
export ANSIBLE_USER="ubuntu"
export ANSIBLE_SSH_KEY="~/.ssh/id_rsa"

# Generate inventory from template
envsubst < inventory-template.yml > my-inventory.yml

# Use the generic inventory
ansible-playbook -i my-inventory.yml k3s-playbook.yml --extra-vars "@vars.yaml"
```

## Usage

### Basic Deployment

```bash
# Set ANSIBLE_CONFIG (optional)
export ANSIBLE_CONFIG=/path/to/qa-infra-automation/ansible/k3s/default/ansible.cfg

# Run with Terraform inventory
ansible-playbook -i inventory-template.yml k3s-playbook.yml --extra-vars "@vars.yaml" -vvv

# Or run with generic inventory
ansible-playbook -i my-inventory.yml k3s-playbook.yml --extra-vars "@vars.yaml"  -vvv
```

### Configuration Setup

Before running the playbook, create your `vars.yaml` file:

```bash
# Copy the example template
cp vars.yaml.example vars.yaml

# Edit with your specific values
vim vars.yaml
```

**Sample `vars.yaml`:**

```yaml
# K3s version and installation
kubernetes_version: 'v1.33.1+k3s1'
kubeconfig_file: './kubeconfig.yaml'
```

### Registry Support

If you would like to use a mirror or registry, upload a file to `roles/k3s_install/tasks/` named `k3s_registy.yaml`
