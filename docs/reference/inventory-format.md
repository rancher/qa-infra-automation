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
| `nodes[].name` | string | Node hostname. First etcd node **must** be `"master"` |
| `nodes[].roles` | list | Valid values: `etcd`, `cp`, `worker` |
| `nodes[].public_ip` | string | Used as `ansible_host` |
| `nodes[].private_ip` | string | Available but not used in standard deployments |

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
      servers:
        roles: [cp]
      workers:
        roles: [worker]

k3s:
  default:
    input_type: cluster_nodes
    ip_field: public_ip
    groups:
      master:
        roles: [cp]
        first_only: true
      servers:
        roles: [cp]
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
          rke2_node_role: master
          node_roles: [etcd, cp, worker]
    servers:
      hosts:
        cp-0:
          ansible_host: "1.2.3.5"
          ansible_user: "ec2-user"
          rke2_node_role: server
          node_roles: [cp]
    workers:
      hosts:
        worker-0:
          ansible_host: "1.2.3.6"
          ansible_user: "ec2-user"
          rke2_node_role: agent
          node_roles: [worker]
```

## Manual Inventory (BYO Nodes)

If you're not using Tofu, create the inventory file manually. The required structure depends on the distro.

### RKE2 Manual Inventory

See the [RKE2 BYO guide](../guides/rke2-default-byo.md#step-1-create-the-ansible-inventory) for a complete example.

Key requirements:
- First node must be in the `master` group and named `master`
- `rke2_node_role`: `master` (first node), `server` (additional CP), or `agent` (worker)
- `node_roles`: list of `etcd`, `cp`, `worker`
- `fqdn` and `kube_api_host` in `all.vars`

### K3s Manual Inventory

See the [K3s BYO guide](../guides/k3s-default-byo.md#step-1-create-the-ansible-inventory) for a complete example.

Key requirements:
- First node must be in the `master` group and named `master`
- Group membership determines role (no `rke2_node_role` or `node_roles` needed)
- `fqdn` and `kube_api_host` in `all.vars`

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
