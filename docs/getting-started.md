# Getting Started

This repository automates the deployment of Kubernetes clusters and the Rancher management platform. It is built around two layers:

1. **OpenTofu** provisions cloud infrastructure (VMs, networks, load balancers, DNS)
2. **Ansible** deploys Kubernetes distributions and Rancher onto those machines

The Ansible playbooks are **provider-agnostic** — they work the same whether your nodes come from AWS, GCP, Harvester, or are bare-metal machines you manage yourself.

## What Can I Deploy?

| Kubernetes Distro | Environment | Infrastructure Providers |
|---|---|---|
| **RKE2** | Default (internet-connected) | AWS, BYO / on-premise |
| **RKE2** | Airgap (offline) | AWS |
| **K3s** | Default (internet-connected) | AWS, BYO / on-premise |

**Rancher** can be installed on top of any of the above clusters.

> **GCP** and **Harvester** have Tofu modules for specific use cases (Elemental, VMs) but do not yet have a full `cluster_nodes` module. See [Adding a New Provider](adding-a-provider.md) to contribute one.

## How It Works

```
┌─────────────────────┐      ┌───────────────────┐      ┌──────────────────────┐
│  1. Tofu             │      │  2. Inventory      │      │  3. Ansible           │
│  Provision VMs       │─────▶│  generate_inventory│─────▶│  Deploy K8s + Rancher │
│  (or bring your own) │      │  .py               │      │                       │
└─────────────────────┘      └───────────────────┘      └──────────────────────┘
```

1. **Tofu** creates cloud resources and outputs a JSON blob describing the nodes
2. **`generate_inventory.py`** converts that JSON into an Ansible inventory file
3. **Ansible** reads the inventory and runs playbooks to install RKE2/K3s and optionally Rancher

If you bring your own nodes, you skip steps 1–2 and write the inventory file manually.

The **Makefile** orchestrates all three steps so the common case is a single command:

```bash
make all                    # RKE2 + Rancher on AWS (default)
make all DISTRO=k3s         # K3s + Rancher on AWS
make all ENV=airgap         # RKE2 + Rancher in airgap on AWS
```

## Pick a Guide

Not sure where to start? Follow this decision tree:

```
Do you have existing nodes (bare metal, VMs, etc.)?
│
├── YES → Which distro?
│         ├── RKE2 → docs/guides/rke2-default-byo.md
│         └── K3s  → docs/guides/k3s-default-byo.md
│
└── NO (need to provision) → Which cloud?
          │
          ├── AWS → Which environment?
          │         ├── Default (internet)  → Which distro?
          │         │                         ├── RKE2 → docs/guides/rke2-default-aws.md
          │         │                         └── K3s  → docs/guides/k3s-default-aws.md
          │         └── Airgap (offline)    → docs/guides/rke2-airgap-aws.md
          │
          └── Other → See docs/adding-a-provider.md
```

Or go straight to the [guide index](guides/README.md).

## What's Next After the Cluster?

- [Install Rancher](guides/rancher-ha.md) for cluster management
- [Import a downstream cluster](import_cluster_on_airgap.md) into an airgapped Rancher

## Further Reading

- [Prerequisites](prerequisites.md) — tools, dependencies, credentials
- [Architecture](architecture.md) — detailed design of the Tofu and Ansible layers
- [Makefile Reference](reference/makefile.md) — all `make` targets and variables
- [FAQ](faq.md) — common questions
