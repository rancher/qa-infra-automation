# K3s Cluster Ansible Playbook

This playbook deploys a K3s Kubernetes cluster and can be used either with or without Terraform/OpenTofu infrastructure provisioning.

## Prerequisites

Before running the playbook, ensure you have the following in addition to the [general ansible prereqs](../README.md):

* SSH access to the target nodes
* A valid inventory file (see options below)
* A `vars.yaml` file with necessary variables

## Usage Options

The playbook supports two deployment modes. Choose the appropriate template for your infrastructure:

### Option 1: With Terraform/OpenTofu (Infrastructure + Kubernetes)

For this mode, you'll need:
* `ansible-inventory-terraform` installed
* Terraform/OpenTofu state file available

1. **Use Terraform Inventory:**
   ```bash
   # Use the ready-made Terraform inventory
   cp inventory-terraform.yml inventory.yml
   
   # Copy and configure vars
   cp vars.yml vars.yaml
   ```

2. **Set Environment Variables:**
   ```bash
   export ANSIBLE_CONFIG=/path/to/go/src/github.com/rancher/qa-infra-automation/ansible/k3s/default/ansible.cfg
   export TF_WORKSPACE=your-workspace
   export TERRAFORM_NODE_SOURCE=tofu/aws/modules/cluster_nodes
   ```

3. **Run the Playbook:**
   ```bash
   ansible-playbook -i inventory.yml k3s-playbook.yml --extra-vars "@vars.yaml"
   ```

### Option 2: Standalone (Kubernetes only)

For this mode, you bring your own infrastructure and just install K3s:

1. **Configure Your Infrastructure:**
   Set environment variables for your nodes:
   ```bash
   # Required: Master node
   export MASTER_IP=10.0.1.10
   export MASTER_ROLE=etcd,cp
   export ANSIBLE_USER=ubuntu
   export ANSIBLE_SSH_KEY=~/.ssh/your-key.pem
   
   # Optional: Additional servers (for HA) - add as many as needed
   export SERVERS_SECTION="servers:
     hosts:
       server1:
         ansible_host: 10.0.1.11
         ansible_role: etcd,cp
       server2:
         ansible_host: 10.0.1.12
         ansible_role: etcd,cp"
   
   # Optional: Workers - add as many as needed
   export WORKERS_SECTION="workers:
     hosts:
       worker1:
         ansible_host: 10.0.1.13
         ansible_role: worker
       worker2:
         ansible_host: 10.0.1.14
         ansible_role: worker"
   ```

2. **Generate Inventory:**
   ```bash
   envsubst < inventory-static.yml > inventory.yml
   envsubst < vars.yml > vars.yaml
   ```

3. **Configure Variables:**
   Edit `vars.yaml` and ensure:
   ```yaml
   kube_api_host_override: "10.0.1.10"  # Your master IP
   ```

4. **Run the Playbook:**
   ```bash
   ansible-playbook -i inventory.yml k3s-playbook.yml --extra-vars "@vars.yaml"
   ```

## Flexible Node Configuration

The static template supports any number of nodes:

### Single Node (Master only):
```bash
export MASTER_IP=10.0.1.10
export MASTER_ROLE=etcd,cp
export SERVERS_SECTION=""
export WORKERS_SECTION=""
```

### HA Setup (Master + 6 Servers):
```bash
export MASTER_IP=10.0.1.10
export MASTER_ROLE=etcd,cp
export SERVERS_SECTION="servers:
  hosts:
    server1:
      ansible_host: 10.0.1.11
      ansible_role: etcd,cp
    server2:
      ansible_host: 10.0.1.12
      ansible_role: etcd,cp
    # ... add up to server6"
export WORKERS_SECTION=""
```

### Mixed Setup (3 Servers + 6 Workers):
```bash
# Set SERVERS_SECTION with 3 servers
# Set WORKERS_SECTION with 6 workers
```

## Configuration

### With Terraform
The playbook automatically reads configuration from Terraform state when `TF_WORKSPACE` is set.

### Without Terraform (Standalone)
Configure these variables in your `vars.yaml`:

```yaml
# Required for standalone mode
kube_api_host_override: "your-master-ip"
fqdn_override: "your-cluster-fqdn.example.com"  # Optional

# Standard configuration
kubernetes_version: 'v1.28.15+k3s1'
kubeconfig_file: './kubeconfig.yaml'

# Optional server/worker flags
server_flags: |
  disable:
    - traefik
  cluster-cidr: "10.42.0.0/16"
  service-cidr: "10.43.0.0/16"

worker_flags: |
  node-label:
    - "environment=production"
```