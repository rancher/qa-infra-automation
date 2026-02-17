# Quickstart

## Overview

This playbook uses a **role-based architecture** to deploy RKE2 clusters. The deployment is broken into 5 distinct roles that execute sequentially:

1. **rke2_setup** - Python interpreter discovery and NetworkManager configuration
2. **rke2_config** - Generate RKE2 configuration files for servers/agents
3. **rke2_install** - Install RKE2 binaries via tar or RPM
4. **rke2_cluster** - Form cluster (master → servers → agents with token distribution)
5. **rke2_health_check** - Validate cluster health and ingress controller readiness

Each role can be executed independently using Ansible tags.

## Prerequisites

1. Infrastructure Deployed: You must have nodes to install rke2 on, either by running `tofu apply` successfully or bringing your own. [Example tofu module](../../../tofu/aws/modules/cluster_nodes/QUICKSTART.md).
2. Ansible Installed: Ensure you have `ansible` installed locally.

## Steps

### Step 1: Setup Ansible Inventory

Before running the playbook, verify that your inventory file is correctly populated with the relevant data. Do one of the two steps below:

- **If you brought up infrastructure from Tofu**, the inventory file is automatically generated:
  1. Run `tofu apply` in your infrastructure module (e.g., `tofu/aws/modules/cluster_nodes`)
  2. Tofu will generate `inventory.yml` in the module directory containing all node information
  3. The inventory includes global variables (`fqdn`, `kube_api_host`) and host groups (`master`, `server`, `worker`, `etcd`, `cp`)

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
            node_roles: "etcd,cp,worker"  # Must include etcd for first node
      worker:
        hosts:
          node2:
            ansible_host: "5.6.7.8"
            ansible_user: "ec2-user"
            rke2_node_role: worker
            node_roles: "worker"
  ```

Once you have your inventory file, verify it has the correct data. Ensure you see your nodes listed in the JSON output with IPs, SSH users, and node roles.

```sh
# From the repository root (adjust path to your inventory.yml location)
ansible-inventory -i tofu/aws/modules/cluster_nodes/inventory.yml --list
```

### Step 2: Define Ansible Variables

You must tell Ansible which version of RKE2 to install and configure other deployment specifics. Create a file named `vars.yaml` in the `ansible/rke2/default/` directory.

**Note:** If using Tofu-generated infrastructure, `fqdn` and `kube_api_host` are automatically included in the inventory file and do not need to be specified here.

`vars.yaml` Template:

```yaml
# rke2 version
kubernetes_version: 'v1.34.2+rke2r1'

# where to store the kubeconfig file
kubeconfig_file: './kubeconfig.yaml'

# network configuration
cni: "calico"

# Only required if using manual inventory (not Tofu-generated):
# fqdn: a.b.c.d.sslip.io # Your FQDN, or a wildcard DNS like sslip.io with your IP
# kube_api_host: a.b.c.d # Your initial node IP
```

### Step 3: Run the Playbook

Run the playbook targeting the Tofu-generated inventory file.

```sh
# Syntax: ansible-playbook -i <inventory_path> <playbook_path>
# If using Tofu-generated inventory:
ansible-playbook -i tofu/aws/modules/cluster_nodes/inventory.yml ansible/rke2/default/rke2-playbook.yml

# If using manual inventory in ansible/rke2/default/:
ansible-playbook -i ansible/rke2/default/inventory.yml ansible/rke2/default/rke2-playbook.yml
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
ansible-playbook -i inventory.yml ansible/rke2/default/rke2-playbook.yml --tags health

# Run only setup and config (skip installation and cluster formation)
ansible-playbook -i inventory.yml ansible/rke2/default/rke2-playbook.yml --tags setup,config

# Skip setup phase (if nodes already prepared)
ansible-playbook -i inventory.yml ansible/rke2/default/rke2-playbook.yml --skip-tags setup

# Run full deployment with verbose output
ansible-playbook -i inventory.yml ansible/rke2/default/rke2-playbook.yml -vvv
```

### Step 4: Verify RKE2 Installation

Once the playbook completes successfully, verify the cluster status. You should be able to do this with kubectl locally, from the root of this repo.

```sh
kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get nodes,pods -A -o wide
```
