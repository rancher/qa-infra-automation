# Inventory Format

This document describes the Ansible inventory format used by this repo — both the auto-generated version (from Tofu) and the manual version (for BYO nodes).

## How Inventory Generation Works

```
Tofu module  ──▶  cluster_nodes_json output  ──▶  generate_inventory.py  ──▶  inventory.yml
```

1. The Tofu module outputs a JSON blob (`cluster_nodes_json` or `airgap_inventory_json`)
2. `scripts/generate_inventory.py` reads that JSON and the schema file (`ansible/_inventory-schema.yaml`)
3. It produces a static `inventory.yml` file in the appropriate Ansible directory

`make infra-up` runs this automatically. You only need to understand this if you're creating a manual inventory or debugging.

## The `cluster_nodes_json` Contract

Every Tofu `cluster_nodes` module must output this exact JSON shape:

```json
{
  "type": "cluster_nodes",
  "metadata": {
    "kube_api_host": "1.2.3.4",
    "fqdn": "my-cluster.example.com",
    "ssh_user": "ec2-user"
  },
  "nodes": [
    {
      "name": "master",
      "roles": ["etcd", "cp", "worker"],
      "public_ip": "1.2.3.4",
      "private_ip": "10.0.1.1"
    },
    {
      "name": "worker-0",
      "roles": ["worker"],
      "public_ip": "1.2.3.5",
      "private_ip": "10.0.1.2"
    },
    {
      "name": "windows-worker-0",
      "roles": ["worker"],
      "public_ip": "1.2.3.6",
      "private_ip": "10.0.1.3",
      "os": "windows",
      "ssh_user": "Administrator"
    }
  ]
}
```

| Field | Type | Description |
|---|---|---|
| `type` | string | Always `"cluster_nodes"` |
| `metadata.kube_api_host` | string | IP of the Kubernetes API endpoint |
| `metadata.fqdn` | string | FQDN for TLS SANs and API access |
| `metadata.ssh_user` | string | OS SSH user for Ansible |
| `metadata.ssh_private_key` | string | Optional. Path to the SSH key; becomes `ansible_ssh_private_key_file` for every node |
| `nodes[].name` | string | Node hostname. First etcd node **must** be `"master"` |
| `nodes[].roles` | list | Valid values: `etcd`, `cp`, `worker` |
| `nodes[].public_ip` | string | Used as `ansible_host` |
| `nodes[].private_ip` | string | Available but not used in standard deployments |
| `nodes[].os` | string | Optional. `linux` (default when absent) or `windows` |
| `nodes[].ssh_user` | string | Optional per-node override of `metadata.ssh_user` |
| `nodes[].ssh_private_key` | string | Optional per-node override of `metadata.ssh_private_key` |

### Windows nodes

`os: windows` is only valid for RKE2, and only for `roles: ["worker"]` — RKE2 has no
Windows server role, so the generator rejects a Windows node carrying `cp` or `etcd`.
It also rejects a Windows node in a K3s inventory rather than letting it silently
vanish from every play.

Windows hosts get connection variables that Linux hosts do not:

```yaml
ansible_connection: ssh          # OpenSSH, not WinRM
ansible_shell_type: powershell
ansible_become: false            # the win_* modules already run as Administrator
ansible_pipelining: false        # pipelining is POSIX-only and breaks win_* modules
ansible_user: Administrator      # from nodes[].ssh_user
```

They land in the `windows_workers` group, never in `workers`. See the
[Windows agent guide](../guides/rke2-windows-agent-aws.md).

## Inventory Schema

The file `ansible/_inventory-schema.yaml` maps node roles to Ansible groups:

```yaml
rke2:
  default:
    input_type: cluster_nodes
    ip_field: public_ip
    groups:
      master:
        roles: [etcd]
        first_only: true        # Only the first matching node
        os: linux               # Optional; omit to match any OS
      servers:
        roles: [cp]
        os: linux
      workers:
        roles: [worker]
        os: linux
      windows_workers:
        roles: [worker]
        os: windows

k3s:
  default:
    input_type: cluster_nodes
    ip_field: public_ip
    groups:
      master:
        # Try each role list in order; pick the first node that matches.
        # K3s supports embedded etcd (master must have etcd) and external
        # datastore (cp-only, no etcd) topologies — this lets the schema
        # express "prefer etcd, fall back to cp".
        roles_priority: [[etcd], [cp]]
        first_only: true
      servers:
        # Any etcd-having or cp-having node installs as a K3s server.
        roles: [etcd, cp]
      workers:
        roles: [worker]
```

## Generated Inventory Structure (RKE2 Default)

```yaml
all:
  vars:
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    fqdn: "my-cluster.example.com"
    kube_api_host: "1.2.3.4"
  children:
    master:
      hosts:
        master:
          ansible_host: "1.2.3.4"
          ansible_user: "ec2-user"
          node_type: master
          node_roles: [etcd, cp, worker]
    servers:
      hosts:
        cp-0:
          ansible_host: "1.2.3.5"
          ansible_user: "ec2-user"
          node_type: server
          node_roles: [cp]
    workers:
      hosts:
        worker-0:
          ansible_host: "1.2.3.6"
          ansible_user: "ec2-user"
          node_type: agent
          node_roles: [worker]
    windows_workers:
      hosts:
        windows-worker-0:
          ansible_host: "1.2.3.7"
```

Groups with no members are still emitted (as `hosts: {}`) so that host patterns which
exclude them — the RKE2 playbook's `all:!windows_workers` — do not warn on Linux-only
clusters.

## Manual Inventory (BYO Nodes)

If you're not using Tofu, create the inventory file manually. The required structure depends on the distro.

### RKE2 Manual Inventory

See the [RKE2 BYO guide](../guides/rke2-default-byo.md#step-1-create-the-ansible-inventory) for a complete example.

Key requirements:
- Bootstrap node must be in the `master` group
- `node_type`: `master` (first node), `server` (additional CP), or `agent` (worker)
- `node_roles`: list of `etcd`, `cp`, `worker`
- `fqdn` and `kube_api_host` in `all.vars`

### K3s Manual Inventory

See the [K3s BYO guide](../guides/k3s-default-byo.md#step-1-create-the-ansible-inventory) for a complete example.

Key requirements:
- Bootstrap node must be in the `master` group
- `fqdn` and `kube_api_host` in `all.vars`
- **All-role topology** (every server has etcd + cp + worker): group membership
  alone is enough — `node_roles` is optional.
- **Split-role topology** (etcd-only servers, cp-only servers, etc.): each host
  must include `node_roles: [etcd]` / `[cp]` / `[etcd, worker]` / etc. Without
  it the K3s config template silently falls through to the all-role default
  (no `disable-apiserver` / `disable-etcd` flags, wrong labels), which is not
  what you want for split-role. See the K3s BYO guide's split-role example.

### Airgap Inventory

See the [airgap inventory configuration](../../ansible/rke2/airgap/docs/configuration/INVENTORY_CONFIGURATION.md).

Key differences:
- Includes a `bastion` group with SSH proxy configuration
- Airgap nodes use `ansible_ssh_common_args` with `ProxyCommand` through the bastion
- Uses private IPs for airgap nodes (they have no public IPs)

## Verifying Your Inventory

```bash
# List all hosts and variables
ansible-inventory -i <path-to-inventory.yml> --list

# Show inventory tree
ansible-inventory -i <path-to-inventory.yml> --graph

# Test SSH connectivity
ansible -i <path-to-inventory.yml> all -m ping
```
