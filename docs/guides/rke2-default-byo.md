# Deploy RKE2 on Your Own Nodes (BYO / On-Premise)

> **Estimated time:** ~10 minutes (nodes already provisioned)
>
> **What you'll end up with:** An RKE2 Kubernetes cluster deployed on your existing machines, with a kubeconfig on your local machine.

This guide is for when you already have nodes — bare metal servers, VMs from any provider, or cloud instances provisioned outside this repo. No OpenTofu required.

## Prerequisites

- Complete the [general prerequisites](../prerequisites.md) (Python, Ansible, SSH key) — you can skip OpenTofu
- **SSH access** from your workstation to all target nodes
- **Nodes running a supported OS:** SLES 15, SLE Micro, RHEL, or Ubuntu
- **Minimum resources per node:** 2 vCPU, 4 GB RAM, 40 GB disk
- **Network requirements:** Nodes can reach each other on ports 6443, 9345, 10250, and the CNI port range. See the [RKE2 networking requirements](https://docs.rke2.io/install/requirements#networking).

## Step 1: Create the Ansible Inventory

Create the file `ansible/rke2/default/inventory/inventory.yml`:

```yaml
all:
  vars:
    # Disable SSH host key checking for automation
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

    # Cluster networking — fqdn is used in TLS SANs, kube_api_host is the
    # address Ansible uses to reach the API server after bootstrap.
    # For a single-node or no-LB setup, use the first node's public IP.
    # For multi-CP with a load balancer, use the LB address.
    fqdn: "1.2.3.4.sslip.io"
    kube_api_host: "1.2.3.4"

  children:
    # The initial control-plane node — must be named "master"
    master:
      hosts:
        master:
          ansible_host: "1.2.3.4"
          ansible_user: "root"
          rke2_node_role: master
          node_roles:
            - etcd
            - cp
            - worker

    # Additional control-plane / etcd nodes (optional)
    servers:
      hosts:
        server-1:
          ansible_host: "5.6.7.8"
          ansible_user: "root"
          rke2_node_role: server
          node_roles:
            - etcd
            - cp

    # Worker-only nodes (optional)
    workers:
      hosts:
        worker-0:
          ansible_host: "9.10.11.12"
          ansible_user: "root"
          rke2_node_role: agent
          node_roles:
            - worker
        worker-1:
          ansible_host: "13.14.15.16"
          ansible_user: "root"
          rke2_node_role: agent
          node_roles:
            - worker
```

### Key fields explained

| Field | Description |
|-------|-------------|
| `ansible_host` | IP or hostname Ansible uses to SSH into the node |
| `ansible_user` | SSH user (must have sudo privileges) |
| `rke2_node_role` | `master` for the first node, `server` for additional CP nodes, `agent` for workers |
| `node_roles` | List of Kubernetes roles: `etcd`, `cp`, `worker` |
| `fqdn` | Fully-qualified domain name for TLS SANs. Use `<ip>.sslip.io` as a wildcard DNS shortcut |
| `kube_api_host` | IP address of the Kubernetes API endpoint (first node or LB) |

### Single-node cluster

For a single all-in-one node, keep just the `master` group and omit `servers` and `workers`:

```yaml
all:
  vars:
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    fqdn: "1.2.3.4.sslip.io"
    kube_api_host: "1.2.3.4"
  children:
    master:
      hosts:
        master:
          ansible_host: "1.2.3.4"
          ansible_user: "root"
          rke2_node_role: master
          node_roles: [etcd, cp, worker]
    servers:
      hosts: {}
    workers:
      hosts: {}
```

### Using a private key file

If SSH requires a specific key:

```yaml
all:
  vars:
    ansible_ssh_private_key_file: "~/.ssh/my_key"
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
```

### Verify the inventory

```bash
ansible-inventory -i ansible/rke2/default/inventory/inventory.yml --list
```

Test SSH connectivity:

```bash
ansible -i ansible/rke2/default/inventory/inventory.yml all -m ping
```

## Step 2: Configure the Cluster

Create the file `ansible/rke2/default/vars.yaml`:

```yaml
# RKE2 version — find versions at https://github.com/rancher/rke2/releases
kubernetes_version: 'v1.34.2+rke2r1'

# CNI plugin (calico, canal, or cilium)
cni: "calico"

# Kubeconfig output location
kubeconfig_file: './kubeconfig.yaml'
```

## Step 3: Deploy the Cluster

```bash
make cluster
```

Or manually:

```bash
ansible-playbook \
  -i ansible/rke2/default/inventory/inventory.yml \
  ansible/rke2/default/rke2-playbook.yml
```

## Step 4: Verify

```bash
kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get nodes -o wide
```

All nodes should show `Ready`. Check system pods:

```bash
kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get pods -A
```

## Step 5: (Optional) Deploy Rancher

See the [Rancher HA guide](rancher-ha.md).

## Troubleshooting

**Ansible can't reach nodes (`ping` fails)**
- Verify `ansible_host` IPs are reachable from your workstation
- Check that `ansible_user` can SSH in: `ssh <user>@<ip>`
- Ensure the user has passwordless sudo (or add `-K` to prompt for the sudo password)

**"Permission denied" during RKE2 install**
- The SSH user needs sudo privileges. On SLES: `usermod -aG wheel <user>`

**Nodes join but aren't Ready**
- Check that nodes can communicate on ports 6443, 9345, 10250
- Check CNI pod status: `kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get pods -n kube-system`

**FQDN / TLS errors**
- `fqdn` must resolve to the API server IP (or use `<ip>.sslip.io`)
- If using a load balancer, set `fqdn` and `kube_api_host` to the LB address

For more, see [Troubleshooting](../reference/troubleshooting.md).

## Next Steps

- [Deploy Rancher](rancher-ha.md) on top of your cluster
- [Run specific playbook phases](../../ansible/rke2/default/README.md) using Ansible tags (e.g., `--tags health` to re-run just health checks)
