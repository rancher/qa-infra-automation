# Deploy K3s on Your Own Nodes (BYO / On-Premise)

> **Estimated time:** ~10 minutes (nodes already provisioned)
>
> **What you'll end up with:** A K3s Kubernetes cluster deployed on your existing machines, with a kubeconfig on your local machine.

K3s is a lightweight Kubernetes distribution ideal for edge, development, and resource-constrained environments. If you need a heavier, security-focused distribution, see the [RKE2 BYO guide](rke2-default-byo.md) instead.

## Prerequisites

- Complete the [general prerequisites](../prerequisites.md) (Python, Ansible, SSH key) — you can skip OpenTofu
- **SSH access** from your workstation to all target nodes
- **Nodes running a supported OS:** SLES 15, SLE Micro, RHEL, or Ubuntu
- **Minimum resources per node:** 1 vCPU, 2 GB RAM, 20 GB disk
- **Network requirements:** Nodes can reach each other on ports 6443, 10250, and 8472 (VXLAN). See [K3s networking requirements](https://docs.k3s.io/installation/requirements#networking).

## Step 1: Create the Ansible Inventory

Create the file `ansible/k3s/default/inventory/inventory.yml`:

```yaml
all:
  vars:
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    ansible_user: "root"
    fqdn: "1.2.3.4.sslip.io"
    kube_api_host: "1.2.3.4"

  children:
    # The initial control-plane node — must be named "master"
    master:
      hosts:
        master:
          ansible_host: "1.2.3.4"

    # All control-plane nodes (including master)
    servers:
      hosts:
        master:
          ansible_host: "1.2.3.4"
        server-1:
          ansible_host: "5.6.7.8"

    # Worker-only nodes (optional)
    workers:
      hosts:
        worker-0:
          ansible_host: "9.10.11.12"
```

> **Key difference from RKE2:** K3s inventory doesn't need `rke2_node_role` or `node_roles` fields. Group membership (`master`, `servers`, `workers`) determines the node role.

### Single-node cluster

```yaml
all:
  vars:
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    ansible_user: "root"
    fqdn: "1.2.3.4.sslip.io"
    kube_api_host: "1.2.3.4"
  children:
    master:
      hosts:
        master:
          ansible_host: "1.2.3.4"
    servers:
      hosts:
        master:
          ansible_host: "1.2.3.4"
    workers:
      hosts: {}
```

Verify the inventory:

```bash
ansible-inventory -i ansible/k3s/default/inventory/inventory.yml --list
```

Test connectivity:

```bash
ansible -i ansible/k3s/default/inventory/inventory.yml all -m ping
```

## Step 2: Configure the Cluster

Create the file `ansible/k3s/default/vars.yaml`:

```yaml
# K3s version — find versions at https://github.com/k3s-io/k3s/releases
kubernetes_version: 'v1.35.2+k3s1'

# Kubeconfig output location
kubeconfig_file: './kubeconfig.yaml'

# Optional: K3s release channel
channel: "stable"
```

## Step 3: Deploy the Cluster

```bash
make cluster DISTRO=k3s
```

Or manually:

```bash
ansible-playbook \
  -i ansible/k3s/default/inventory/inventory.yml \
  ansible/k3s/default/k3s-playbook.yml
```

## Step 4: Verify

```bash
kubectl --kubeconfig ansible/k3s/default/kubeconfig.yaml get nodes -o wide
```

All nodes should show `Ready`.

## Step 5: (Optional) Deploy Rancher

See the [Rancher HA guide](rancher-ha.md).

## Troubleshooting

**Ansible can't reach nodes**
- Verify `ansible_host` IPs are reachable: `ssh <user>@<ip>`
- Ensure the user has passwordless sudo

**K3s service fails to start**
- SSH in and check: `journalctl -u k3s --no-pager -n 50`
- Ensure ports 6443 and 10250 are open between nodes

**FQDN / TLS errors**
- `fqdn` must resolve to the API server IP (or use `<ip>.sslip.io`)

For more, see [Troubleshooting](../reference/troubleshooting.md).

## Next Steps

- [Deploy Rancher](rancher-ha.md) on top of your cluster
- [K3s playbook details](../../ansible/k3s/default/README.md) for advanced configuration
