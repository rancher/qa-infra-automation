# FAQ

## Getting Started

### Which Kubernetes distro should I choose — RKE2 or K3s?

| | RKE2 | K3s |
|---|---|---|
| **Focus** | Security, compliance, FIPS | Lightweight, simplicity |
| **Best for** | Production, regulated environments | Edge, IoT, development, CI |
| **Resource needs** | Higher (2+ vCPU, 4+ GB RAM) | Lower (1+ vCPU, 2+ GB RAM) |

Both are CNCF-conformant. If unsure, start with RKE2 — it's the more common choice for QA testing of Rancher.

### How do I deploy on my own nodes without OpenTofu?

Skip the infrastructure step and write a manual Ansible inventory. See:
- [RKE2 on your own nodes](guides/rke2-default-byo.md)
- [K3s on your own nodes](guides/k3s-default-byo.md)

### What's the fastest way to get a cluster running?

```bash
# Configure terraform.tfvars and vars.yaml first (see guides)
make all
```

This provisions AWS infrastructure, deploys RKE2, and installs Rancher in one command.

## OS & Platform Support

### Which operating systems are supported?

Playbooks must work on **SLES** and **SLE Micro** at minimum. **RHEL** and **Ubuntu** are supported on a best-effort basis. If your playbook only supports specific OSes, note this in its README.

### Which cloud providers are supported?

**Full support (cluster_nodes module):** AWS

**Partial support (specialized modules):** GCP (Elemental), Harvester (VMs, Elemental)

**Adding more:** See [Adding a New Provider](adding-a-provider.md) — only a Tofu module is needed; Ansible works unchanged.

## Architecture & Design

### How do Tofu and Ansible communicate?

Through a JSON contract. Tofu outputs a `cluster_nodes_json` blob, `scripts/generate_inventory.py` converts it to an Ansible inventory file. See [Architecture](architecture.md) and [Inventory Format](reference/inventory-format.md).

### Do Ansible playbooks need to change for different cloud providers?

No. Playbooks are provider-agnostic by design. They only need a valid inventory file.

### What should the structure of READMEs look like?

Every new playbook or module needs a README with:
- Purpose and description
- Prerequisites
- Input variables with descriptions
- Output values
- Usage examples
- Any OS or provider limitations

### Do I need a design document before building a new module?

Not required. For complex features, consider a design discussion first. Always capture details in the README during implementation.

## Workflows

### How do I add more workers to an existing cluster?

1. Update the `nodes` variable in `terraform.tfvars` (increase worker count)
2. Re-run `make infra-up` — Tofu adds the new instances
3. Re-run `make cluster` — Ansible configures the new nodes

For BYO nodes, add the new hosts to your inventory and re-run the playbook.

### I always run Ansible after Tofu. Can I streamline this?

Use `make all` which runs `infra-up → cluster → rancher` in sequence. Or `make setup-from-infra` if infrastructure already exists.

### How do I run Tofu and Ansible from a test (Go, Python)?

There's a plan for a Go client. Until then, use [go-ansible](https://github.com/apenella/go-ansible), [terratest](https://terratest.gruntwork.io/), or [terraform-exec](https://github.com/hashicorp/terraform-exec).

### How do I run only part of the playbook?

Use Ansible tags. For RKE2:

```bash
# Only health checks
ansible-playbook -i <inventory> ansible/rke2/default/rke2-playbook.yml --tags health

# Skip setup phase
ansible-playbook -i <inventory> ansible/rke2/default/rke2-playbook.yml --skip-tags setup
```

Available RKE2 tags: `setup`, `config`, `install`, `cluster`, `health`, `rke2` (all).

## Troubleshooting

See the [Troubleshooting guide](reference/troubleshooting.md) for detailed solutions. Quick answers:

### Ansible says "Inventory file not found"

Run `make infra-up` first, or create a [manual inventory](reference/inventory-format.md).

### Nodes show NotReady after deployment

Wait 2–3 minutes for CNI pods to start. If still not ready, check that inter-node ports are open (6443, 9345, 10250, and CNI-specific ports).

### I'm familiar with Terraform, not OpenTofu

They are nearly identical. See [migrating from Terraform to Tofu](https://opentofu.org/docs/intro/migration/).
