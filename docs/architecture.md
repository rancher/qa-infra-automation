# Architecture

This repository maintains a clear separation of concerns between infrastructure provisioning and product deployment, enabling consistent and reliable deployments across the SUSE Rancher Prime suite of products.

## High-Level Workflow

```
┌──────────────────┐     ┌───────────────────────┐     ┌────────────────────────┐
│  1. OpenTofu      │     │  2. Inventory Bridge    │     │  3. Ansible              │
│                    │     │                         │     │                          │
│  Provision VMs,    │────▶│  cluster_nodes_json     │────▶│  Install RKE2 / K3s      │
│  networks, LBs,   │     │  → generate_inventory.py │     │  Deploy Rancher          │
│  DNS records       │     │  → inventory.yml        │     │  Configure cluster       │
└──────────────────┘     └───────────────────────┘     └────────────────────────┘
       │                                                          │
       │  APIs: AWS, GCP, Harvester, ...             SSH to nodes │
       ▼                                                          ▼
  ┌──────────┐                                          ┌──────────────┐
  │  Cloud    │                                          │  Target       │
  │  Provider │                                          │  Nodes        │
  └──────────┘                                          └──────────────┘
```

**If you bring your own nodes**, you skip steps 1–2 and write the inventory file manually.

## Components

### 1. OpenTofu (`tofu/`)

**Purpose:** Infrastructure as Code (IaC). Defines and provisions cloud infrastructure in a repeatable, version-controlled manner.

**Structure:**
```
tofu/
├── aws/modules/
│   ├── cluster_nodes/    # EC2 instances, SSH keys, optional LB + Route53
│   ├── airgap/           # VPC, bastion, private subnet, airgap nodes
│   ├── ec2_instance/     # Standalone EC2 helper
│   ├── load_balancer/    # NLB module
│   ├── route53/          # DNS records
│   └── s3/               # S3 bucket
├── gcp/modules/
│   ├── compute_instance/ # GCE instances
│   └── elemental_nodes/  # Elemental on GCP
└── harvester/modules/
    ├── vm/               # Harvester VMs
    ├── loadbalancer/     # Harvester LB
    ├── ippool/           # IP pool management
    └── elemental-vm/     # Elemental on Harvester
```

**Key output:** Every `cluster_nodes` module produces a `cluster_nodes_json` output — a standardized JSON blob describing all provisioned nodes. This is the contract between Tofu and Ansible.

**Flow:** Tofu → Cloud Provider APIs → Resources created → JSON output

### 2. Inventory Bridge (`scripts/generate_inventory.py`)

**Purpose:** Converts Tofu's JSON output into an Ansible-compatible static inventory file.

This is the **only coupling** between the Tofu and Ansible layers. The schema file (`ansible/_inventory-schema.yaml`) maps node roles to Ansible host groups per distro and environment.

See [Inventory Format](reference/inventory-format.md) for the full schema and examples.

### 3. Ansible (`ansible/`)

**Purpose:** Configuration management and product deployment. Installs Kubernetes distributions (RKE2, K3s) and Rancher onto target nodes.

**Key design principle:** Ansible playbooks are **provider-agnostic**. They don't know or care whether nodes came from AWS, GCP, Harvester, or were manually provisioned. They only need a valid inventory file.

**Structure:**
```
ansible/
├── rke2/
│   ├── default/          # Standard RKE2 deployment
│   └── airgap/           # Airgap RKE2 deployment (tarball method)
├── k3s/
│   └── default/          # Standard K3s deployment
├── rancher/
│   ├── default-ha/       # Rancher HA deployment
│   ├── downstream/       # Downstream cluster management
│   └── token/            # Token management
└── roles/                # Reusable roles (rke2_install, rke2_cluster, etc.)
```

**Flow:** Ansible → SSH to nodes → Install software, configure services, form cluster

## Design Principles

1. **Separation of concerns:** Tofu handles infrastructure; Ansible handles software. They communicate through a well-defined JSON contract.

2. **Provider agnosticism:** Adding a new cloud provider requires only a new Tofu module that outputs the correct JSON shape. No Ansible changes needed. See [Adding a New Provider](adding-a-provider.md).

3. **Modularity:** Each Tofu module and Ansible role is self-contained and can be used independently. Roles handle distinct phases (setup, config, install, cluster, health check).

4. **BYO-friendly:** The Ansible layer works without Tofu entirely. Users with existing infrastructure write a manual inventory and run playbooks directly.
