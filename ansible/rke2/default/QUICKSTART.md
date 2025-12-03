# Quickstart

## Prerequisites

1. Infrastructure Deployed: You must have run `tofu apply` successfully to bring up infrastructure.
2. Inventory Generated: You must have the `terraform-inventory.yml` file in the repository root (generated via `envsubst` in the quickstart guide for `aws/modules/cluster_nodes`). You may need to update the `project_path` there to be a path relative to the `ansible/` directory.
3. Ansible Installed: Ensure you have `ansible` installed locally.

## Steps

### Step 1: Verify Inventory

Before running the playbook, verify that your inventory file is correctly populated with the IP addresses from your Tofu deployment.

```sh
# From the repository root
ansible-inventory -i terraform-inventory.yml --list
```

Ensure you see your nodes listed in the JSON output - the IPs, ssh users, and node roles.

### Step 2: Prepare Ansible Environment

Navigate to the ansible directory.

```sh
cd ansible
```

### Step 3: Define Ansible Variables

You must tell Ansible which version of RKE2 to install and configure other deployment specifics. Create a file named `vars.yaml` in the `ansible/rke2/default/` directory.

`vars.yaml` Template:

```yaml
# rke2 version
kubernetes_version: 'v1.34.2+rke2r1'

# where to store the kubeconfig file
kubeconfig_file: './kubeconfig.yaml'

# cni configuration
cni: "calico"
```

### Step 4: Run the Playbook

Set a few environment variables, then run the playbook targeting the inventory file located in the root directory.

```sh
export FQDN=a.b.c.d.sslip.io # Your FQDN, or a wildcard DNS like sslip.io with your IP
export KUBE_API_HOST=a.b.c.d # Your initial node IP

# Syntax: ansible-playbook -i <inventory_path> <playbook_path>
ansible-playbook -i ../terraform-inventory.yml rke2/default/rke2-playbook.yml
```

### Step 5: Verify RKE2 Installation

Once the playbook completes successfully, verify the cluster status. You should be able to do this with kubectl locally.

```sh
kubectl --kubeconfig rke2/default/kubeconfig.yaml get nodes,pods -A -o wide
```
