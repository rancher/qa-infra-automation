# Adding a New Infrastructure Provider

This guide walks through adding a new cloud or virtualization provider to the Tofu layer.
The Ansible layer never needs to change — it is provider-agnostic by design.

## How the layers connect

```
Tofu module  →  cluster_nodes_json output  →  generate_inventory.py  →  Ansible inventory
```

`generate_inventory.py` is the only bridge between Tofu and Ansible.
It reads one JSON blob (`cluster_nodes_json`) and produces a static Ansible inventory.
As long as your new module outputs that JSON in the correct shape, everything downstream works unchanged.

## Step 1: Create the module directory

```
tofu/<provider>/modules/cluster_nodes/
├── main.tf           # Provider resources (instances, keys, networking)
├── variables.tf      # Input variables
├── outputs.tf        # Must include cluster_nodes_json
├── terraform.tf      # Provider version constraints
├── terraform.tfvars  # Example / default values for local testing
├── README.md         # Usage, inputs, outputs, examples
└── QUICKSTART.md     # Step-by-step for first-time users
```

Replace `<provider>` with the provider name in lowercase (e.g., `linode`, `azure`, `hetzner`).

## Step 2: Implement `outputs.tf` — the required contract

This is the only thing `generate_inventory.py` reads.
The shape must be exact.

```hcl
output "cluster_nodes_json" {
  description = "Complete node metadata for inventory generation"
  value = jsonencode({
    type = "cluster_nodes"
    metadata = {
      kube_api_host = <first_etcd_node_public_ip>
      fqdn          = <dns_name_or_public_ip>
      ssh_user      = var.ssh_user
    }
    nodes = [
      for node in local.node_names : {
        name       = node.name
        roles      = node.roles
        public_ip  = <provider_resource>[node.name].public_ip
        private_ip = <provider_resource>[node.name].private_ip
      }
    ]
  })
}
```

### Field reference

| Field | Type | Description |
|---|---|---|
| `type` | string | Always `"cluster_nodes"` |
| `metadata.kube_api_host` | string | Public IP of the first etcd node |
| `metadata.fqdn` | string | DNS name used by Ansible as the API endpoint |
| `metadata.ssh_user` | string | OS user for Ansible SSH connections |
| `nodes[].name` | string | Node hostname. First etcd node **must** be named `"master"` |
| `nodes[].roles` | list(string) | Roles from input. Valid values: `etcd`, `cp`, `worker` |
| `nodes[].public_ip` | string | Public IP — used by Ansible as `ansible_host` |
| `nodes[].private_ip` | string | Private IP — available but not used in standard deploys |

> **Why `"master"`?** The inventory schema and Ansible roles identify the initial cluster node
> by the group name `master`. The bridge script assigns `rke2_node_role: master` to any node
> named `"master"` in the JSON. Do not use any other name for the first etcd node.

## Step 3: Implement the node naming locals in `main.tf`

The naming logic is the same for every provider.
Copy this locals block and substitute your provider's resource references:

```hcl
locals {
  # Flatten the nodes input into a list of named objects
  temp_node_names = flatten([
    for group in var.nodes : [
      for i in range(group.count) : {
        name  = "${join("-", group.role)}-${i}"
        roles = group.role
      }
    ]
  ])

  # Find the first etcd node and rename it "master"
  first_etcd_index = index(
    [for node in local.temp_node_names : contains(node.roles, "etcd")],
    true
  )
  node_names = [
    for node in local.temp_node_names : {
      name  = node.name == local.temp_node_names[local.first_etcd_index].name ? "master" : node.name
      roles = node.roles
    }
  ]

  # Separate control plane nodes (used for load balancer targeting)
  cp_nodes = {
    for node in local.node_names : node.name => node
    if contains(node.roles, "cp")
  }
  cp_node_count = length(local.cp_nodes)
}
```

This produces node names like `master`, `cp-0`, `etcd-cp-0`, `worker-0`, matching what
the inventory schema expects.

## Step 4: Implement `variables.tf`

The `nodes` variable shape is standardised across all providers.
Provider-specific variables (credentials, region, image, etc.) are up to you.

```hcl
# Required — same shape for every provider
variable "nodes" {
  description = "Node groups with count and roles."
  type = list(object({
    count = number
    role  = list(string)  # e.g. ["etcd"], ["cp"], ["worker"], ["etcd", "cp"]
  }))
}

variable "ssh_user"   {}  # OS user for Ansible (e.g. "ubuntu", "ec2-user")
variable "public_ssh_key"  {}  # Path to public key installed on nodes

# Provider-specific variables
variable "region"        {}
variable "instance_type" {}
variable "image"         {}
variable "hostname_prefix" {}
# ... add whatever the provider requires
```

## Step 5: Implement `terraform.tf`

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    <provider> = {
      source  = "<registry>/<provider>"
      version = "~> <major.minor>"
    }
  }
}
```

Example for Linode:

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }
}
```

## Step 6: Verify the output shape

After `tofu apply`, validate the JSON before running inventory generation:

```bash
tofu -chdir=tofu/<provider>/modules/cluster_nodes output -raw cluster_nodes_json | python3 -m json.tool
```

The output should look like:

```json
{
  "type": "cluster_nodes",
  "metadata": {
    "kube_api_host": "1.2.3.4",
    "fqdn": "my-cluster.example.com",
    "ssh_user": "ubuntu"
  },
  "nodes": [
    {
      "name": "master",
      "roles": ["etcd"],
      "public_ip": "1.2.3.4",
      "private_ip": "10.0.1.1"
    },
    {
      "name": "cp-0",
      "roles": ["cp"],
      "public_ip": "1.2.3.5",
      "private_ip": "10.0.1.2"
    },
    {
      "name": "worker-0",
      "roles": ["worker"],
      "public_ip": "1.2.3.6",
      "private_ip": "10.0.1.3"
    }
  ]
}
```

## Step 7: Generate inventory and run Ansible

No changes to Ansible are required.

```bash
# Generate the static inventory
make generate-inventory \
  DISTRO=rke2 \
  ENV=default \
  INVENTORY_JSON="$(tofu -chdir=tofu/<provider>/modules/cluster_nodes output -raw cluster_nodes_json)"

# Deploy
ansible-playbook \
  -i ansible/rke2/default/inventory/inventory.yml \
  ansible/rke2/default/rke2-playbook.yml
```

Or use the full Makefile workflow:

```bash
make infra-apply PROVIDER=<provider>
make generate-inventory DISTRO=rke2 ENV=default PROVIDER=<provider>
make deploy DISTRO=rke2 ENV=default
```

## Optional: load balancer support

If your provider supports load balancers and you have more than one CP node,
add one conditionally (same pattern as AWS):

```hcl
# Only create LB when there are multiple CP nodes
resource "<provider>_load_balancer" "lb" {
  count = local.cp_node_count > 1 ? 1 : 0
  # ...
}
```

Expose ports `80`, `443`, `6443` (Kubernetes API), and `9345` (RKE2 supervisor).

When an LB is present, set `metadata.fqdn` to the LB hostname/IP rather than a single node IP,
and set `metadata.kube_api_host` to the same value.

## Reference: AWS implementation

The canonical implementation to reference is:

```
tofu/aws/modules/cluster_nodes/
```

It covers: EC2 instances, encrypted volumes, conditional NLB, Route53 DNS,
SSH key management, and both standard and airgap networking modes.

## Checklist

Before opening a PR for a new provider:

- [ ] `cluster_nodes_json` output matches the required shape exactly
- [ ] First etcd node is named `"master"`
- [ ] Both `public_ip` and `private_ip` are populated for every node
- [ ] `metadata.ssh_user` matches the OS default user for the chosen image
- [ ] `tofu validate` passes
- [ ] `tofu apply` + `generate_inventory.py` produces a valid inventory
- [ ] `ansible-playbook --syntax-check` passes against the generated inventory
- [ ] `README.md` documents all input variables and outputs
- [ ] `QUICKSTART.md` has end-to-end steps a new user can follow
