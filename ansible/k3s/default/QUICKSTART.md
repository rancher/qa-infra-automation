# Quickstart

## Overview

This playbook deploys K3s clusters using a static Ansible inventory. The inventory is generated automatically when provisioning infrastructure with Tofu via `make infra-up`.

## Prerequisites

1. Infrastructure Deployed: You must have nodes to install K3s on, either by running `tofu apply` successfully or bringing your own. [Example tofu module](../../../tofu/aws/modules/cluster_nodes/QUICKSTART.md).
2. Ansible Installed: Ensure you have `ansible` installed locally.

## Steps

### Step 1: Setup Ansible Inventory

Before running the playbook, verify that your inventory file is correctly populated with the relevant data. Do one of the two steps below:

- **If you brought up infrastructure from Tofu via `make infra-up`**, the inventory file is automatically generated at `ansible/k3s/default/inventory/inventory.yml` and includes global variables (`fqdn`, `kube_api_host`) and host groups (`master`, `servers`, `workers`).

- **If bringing your own nodes or filling in manually**, create an inventory file with this structure:

  ```yaml
  # ansible/k3s/default/inventory/inventory.yml
  all:
    vars:
      ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
      ansible_user: "ec2-user"
      fqdn: your-cluster.example.com
      kube_api_host: 1.2.3.4
    children:
      master:
        hosts:
          master:                        # First control-plane node; must be named "master"
            ansible_host: "1.2.3.4"
      servers:
        hosts:
          master:
            ansible_host: "1.2.3.4"
          node2:
            ansible_host: "5.6.7.8"    # Additional control-plane nodes
      workers:
        hosts:
          node3:
            ansible_host: "9.10.11.12"
  ```

Once you have your inventory file, verify it has the correct data:

```sh
ansible-inventory -i ansible/k3s/default/inventory.yml --list
```

### Step 2: Define Ansible Variables

Create a file named `vars.yaml` in the `ansible/k3s/default/` directory.

**Note:** If using Tofu-generated infrastructure, `fqdn` and `kube_api_host` are automatically included in the inventory file and do not need to be specified here.

`vars.yaml` Template:

```yaml
# k3s version
kubernetes_version: 'v1.35.2+k3s1'

# Optional channel for K3s installation (default: stable)
channel: "stable"

# Only required if using manual inventory (not Tofu-generated):
# fqdn: a.b.c.d.sslip.io
# kube_api_host: a.b.c.d
```

The kubeconfig is written to `ansible/k3s/default/kubeconfig.yaml` on completion.

### Step 3: Run the Playbook

**Via Makefile (recommended)** — run from the repository root:

```sh
make cluster DISTRO=k3s
```

**Manually** — run from the repository root:

```sh
ansible-playbook -i ansible/k3s/default/inventory.yml ansible/k3s/default/k3s-playbook.yml
```

### Step 4: Verify K3s Installation

Once the playbook completes successfully, verify the cluster status:

```sh
kubectl --kubeconfig ansible/k3s/default/kubeconfig.yaml get nodes,pods -A -o wide
```
