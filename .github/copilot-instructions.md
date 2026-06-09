# Copilot Instructions for QA Infrastructure Automation

## Overview

This repository automates deployment of Kubernetes clusters (RKE2, K3s) and Rancher across cloud providers (AWS, GCP, Harvester) or bare-metal nodes. It combines **OpenTofu** for infrastructure provisioning with **Ansible** for product deployment, plus a thin **Go module** that embeds the Ansible and Tofu content for programmatic use.

## Commands

### Setup

```bash
# Install Python dependencies
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml

# Validate prerequisites (tofu, ansible, python libs, collections)
make validate
```

### Common Makefile targets

All targets accept `DISTRO` (rke2|k3s), `ENV` (default|airgap), `PROVIDER` (aws|gcp|harvester), `WORKSPACE`.

```bash
make all                          # Full pipeline: infra → cluster → Rancher
make all ENV=airgap               # Airgap variant
make all DISTRO=k3s               # K3s instead of RKE2

make infra-up                     # Provision infra + generate inventory
make infra-plan                   # Dry-run plan
make infra-down                   # Destroy infra (interactive confirm)
make cluster                      # Run Ansible cluster playbook only
make rancher                      # Deploy Rancher only

make workspace-new WORKSPACE=foo  # Create Tofu workspace
make workspace-select             # Interactive workspace picker
make infra-ls                     # List all active infra across all modules/workspaces
make infra-nuke                   # Destroy ALL infrastructure (end-of-day cleanup)
```

Pass `AUTO_APPROVE=yes` to skip interactive confirmation prompts in CI.

### Running tests

```bash
# All unit tests (Python)
python3 -m pytest tests/

# Single test file
python3 -m pytest tests/test_generate_inventory.py

# Single test case
python3 -m pytest tests/test_generate_inventory.py::TestValidateClusterNodes::test_valid_fixture_passes

# Run generate_inventory.py against a fixture (no live infra needed)
python3 scripts/generate_inventory.py \
  --input tests/fixtures/rke2_single_master.json \
  --distro rke2 --env default \
  --output-dir /tmp/test-inventory
```

### Ansible syntax check

```bash
ansible-playbook --syntax-check \
  -i ansible/rke2/default/inventory/inventory.yml \
  ansible/rke2/default/rke2-playbook.yml
```

### Go

```bash
go build ./...
go test ./...
```

## Architecture

Two layers connected by a single bridge script:

```
OpenTofu  →  cluster_nodes_json  →  generate_inventory.py  →  Ansible inventory  →  Ansible
```

1. **OpenTofu (`tofu/`)** provisions cloud resources and outputs a standardised JSON blob (`cluster_nodes_json` or `airgap_inventory_json`).
2. **`scripts/generate_inventory.py`** is the only coupling between layers. It reads the JSON blob and uses `ansible/_inventory-schema.yaml` to produce a static Ansible inventory.
3. **Ansible (`ansible/`)** is fully provider-agnostic — it only requires a valid inventory file. It handles RKE2/K3s installation, cluster formation, and Rancher deployment.

**If bringing your own nodes**, skip steps 1–2 and write the inventory manually from the template at `ansible/<distro>/<env>/inventory/inventory.yml.template`.

### Go module

The module (`github.com/rancher/qa-infra-automation`) embeds Ansible and Tofu content via `embed.FS` for programmatic use by test frameworks. The `fsutil` package provides helpers (`WriteToDisk`, `WriteToDiskTemp`) for extracting embedded files to a real directory.

## Key Conventions

### The Tofu→Ansible contract

Every Tofu module **must** output `cluster_nodes_json` with this exact shape:

```json
{
  "type": "cluster_nodes",
  "metadata": {
    "kube_api_host": "<first_etcd_node_public_ip>",
    "fqdn": "<dns_name>",
    "ssh_user": "<os_user>"
  },
  "nodes": [
    { "name": "master", "roles": ["etcd"], "public_ip": "...", "private_ip": "..." },
    { "name": "cp-0",   "roles": ["cp"],   "public_ip": "...", "private_ip": "..." },
    { "name": "worker-0", "roles": ["worker"], "public_ip": "...", "private_ip": "..." }
  ]
}
```

The first etcd node **must be named `"master"`**. The inventory schema and Ansible roles identify the initial cluster node by that name. This naming is enforced by a `locals` block that finds `first_etcd_index` and renames that node — copy this pattern for every new provider.

### Inventory schema

`ansible/_inventory-schema.yaml` maps Tofu node roles to Ansible host groups per distro/env. When adding a new distro or env variant, add the mapping here rather than hardcoding it in the generator script.

### Tofu module structure

Every module under `tofu/<provider>/modules/<name>/` must contain:
- `main.tf`, `variables.tf`, `outputs.tf`, `terraform.tf`
- `terraform.tfvars` (example values, never committed with real secrets)
- `README.md` (purpose, inputs, outputs, runnable example with dummy values)

The AWS `cluster_nodes` module is the canonical reference implementation.

### Ansible playbook layout

```
ansible/<distro>/<env>/
├── <distro>-playbook.yml       # Main entry point
├── vars.yaml                   # Runtime variables (not committed with real values)
└── inventory/
    ├── inventory.yml           # Generated by make infra-up (gitignored)
    ├── inventory.yml.template  # Checked-in template for BYO users
    └── group_vars/all.yml      # Host-level variables
```

Playbooks source variables from `vars.yaml` (via `vars_files`) and fall back to environment variable lookups. They validate required variables with an `assert` task at the start.

### Ansible roles

Reusable roles live in `ansible/roles/`. Roles handle distinct phases: `rke2_setup` → `rke2_config` → `rke2_install` → `rke2_cluster` → `rke2_health_check`. Each role has `tasks/main.yml` and `defaults/main.yml` with documented defaults. All tasks use `ansible.builtin.*` FQCN.

### Adding a new cloud provider

Only a Tofu module is needed — no Ansible changes required. The new module must output `cluster_nodes_json` in the required shape. See `docs/adding-a-provider.md` for the full checklist and the `tofu/aws/modules/cluster_nodes/` reference implementation.
