# Quickstart

## Overview

This playbook uses a **role-based architecture** to deploy RKE2 clusters. The deployment is broken into 5 distinct roles that execute sequentially:

1. **rke2_setup** - Perform initial host preparation and base configuration
2. **rke2_config** - Generate RKE2 configuration files for servers/agents
3. **rke2_install** - Install RKE2 using RPM packages
4. **rke2_cluster** - Form cluster (master → servers → agents with token distribution)
5. **rke2_health_check** - Validate overall RKE2 cluster health

Each role can be executed independently using Ansible tags.

## Prerequisites

1. Infrastructure Deployed: You must have nodes to install rke2 on, either by running `tofu apply` successfully or bringing your own. [Example tofu module](../../../tofu/aws/modules/cluster_nodes/QUICKSTART.md).
2. Ansible Installed: Ensure you have `ansible` installed locally.

## Steps

### Step 1: Setup Ansible Inventory

Before running the playbook, verify that your inventory file is correctly populated with the relevant data. Do one of the two steps below:

- **If you brought up infrastructure from Tofu via `make infra-up`**, the inventory file is automatically generated at `ansible/rke2/default/inventory/inventory.yml` and includes global variables (`fqdn`, `kube_api_host`) and host groups (`master`, `servers`, `workers`).

- **If bringing your own nodes or filling in manually**, create an inventory file with this structure:

  ```yaml
  # inventory.yml
  all:
    vars:
      ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      fqdn: your-cluster.example.com
      kube_api_host: 1.2.3.4
    children:
      master:
        hosts:
          master:                       # First node must be named "master"
            ansible_host: "1.2.3.4"    # node public IP
            ansible_user: "ec2-user"   # SSH user
            rke2_node_role: master
            node_roles:                # Must include etcd for first node
              - etcd
              - cp
              - worker
      servers:
        hosts:
          node2:
            ansible_host: "5.6.7.8"
            ansible_user: "ec2-user"
            rke2_node_role: server
            node_roles:
              - cp
      workers:
        hosts:
          node3:
            ansible_host: "9.10.11.12"
            ansible_user: "ec2-user"
            rke2_node_role: agent
            node_roles:
              - worker
  ```

Once you have your inventory file, verify it has the correct data:

```sh
ansible-inventory -i ansible/rke2/default/inventory/inventory.yml --list
```

### Step 2: Define Ansible Variables

You must tell Ansible which version of RKE2 to install and configure other deployment specifics. Create a file named `vars.yaml` in the `ansible/rke2/default/` directory.

**Note:** If using Tofu-generated infrastructure, `fqdn` and `kube_api_host` are automatically included in the inventory file and do not need to be specified here.

`vars.yaml` Template:

```yaml
# rke2 version
kubernetes_version: 'v1.34.2+rke2r1'

# network configuration
cni: "calico"

# Only required if using manual inventory (not Tofu-generated):
# fqdn: a.b.c.d.sslip.io # Your FQDN, or a wildcard DNS like sslip.io with your IP
# kube_api_host: a.b.c.d # Your initial node IP
```

The kubeconfig is written to `ansible/rke2/default/kubeconfig.yaml` on completion.

### Step 3: Run the Playbook

**Via Makefile (recommended)** — run from the repository root:

```sh
make cluster
```

**Manually** — run from the repository root:

```sh
ansible-playbook -i ansible/rke2/default/inventory/inventory.yml ansible/rke2/default/rke2-playbook.yml
```

#### Optional: Run Specific Phases Using Tags

The role-based architecture supports selective execution using Ansible tags. This is useful for:
- Re-running specific phases (e.g., just health checks)
- Skipping phases (e.g., skip setup on already-configured nodes)
- Debugging individual components

**Available Tags:**
- `setup` - Node preparation (Python, NetworkManager)
- `config` - RKE2 configuration file generation
- `install` - RKE2 binary installation
- `cluster` - Cluster formation and token distribution
- `health` - Health checks and validation
- `rke2` - All RKE2-related tasks (shorthand for all above)

**Examples:**

```sh
# Run only health checks (useful after cluster is already deployed)
ansible-playbook -i ansible/rke2/default/inventory/inventory.yml ansible/rke2/default/rke2-playbook.yml --tags health

# Run only setup and config (skip installation and cluster formation)
ansible-playbook -i ansible/rke2/default/inventory/inventory.yml ansible/rke2/default/rke2-playbook.yml --tags setup,config

# Skip setup phase (if nodes already prepared)
ansible-playbook -i ansible/rke2/default/inventory/inventory.yml ansible/rke2/default/rke2-playbook.yml --skip-tags setup

# Run full deployment with verbose output
ansible-playbook -i ansible/rke2/default/inventory/inventory.yml ansible/rke2/default/rke2-playbook.yml -vvv
```

### Step 4: Verify RKE2 Installation

Once the playbook completes successfully, verify the cluster status. You should be able to do this with kubectl locally, from the root of this repo.

```sh
kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get nodes,pods -A -o wide
```
