# Quickstart

## Prerequisites

1. Infrastructure Ready: `tofu apply` is done.
2. Inventory Ready: `terraform-inventory.yml` is in the repo root (generated via `envsubst` in the quickstart guide for `aws/modules/cluster_nodes`). You may need to update the `project_path` there to be a path relative to the `ansible/` directory.
3. Ansible Installed.

## Steps 

### Step 1. Create Config

Create `vars.yaml` in this folder with your version and network settings.

```yaml
# K3s version
kubernetes_version: 'v1.34.2+k3s1'

# Where to store kubeconfig file locally
kubeconfig_file: './kubeconfig.yaml'
```

### Step 2. Run Playbook

Run this from the `ansible/` directory.

```sh
# CRITICAL: Set these to your Load Balancer DNS and Primary Server IP
export FQDN=a.b.c.d.sslip.io 
export KUBE_API_HOST=a.b.c.d

ansible-playbook -i ../terraform-inventory.yml k3s/default/k3s-playbook.yml
```

### Step 3. Verify Installation

Once the playbook completes successfully, verify the cluster status. You should be able to do this with kubectl locally.

```sh
kubectl --kubeconfig k3s/default/kubeconfig.yaml get nodes,pods -A -o wide
```
