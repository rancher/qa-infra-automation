# QA Infrastructure Automation

Deploy Kubernetes clusters (RKE2, K3s) and Rancher across AWS, GCP, Harvester, or your own nodes. This repo combines **OpenTofu** for infrastructure provisioning with **Ansible** for product deployment.

## Choose Your Path

| I want to… | Guide |
|---|---|
| Deploy **RKE2** on **AWS** | [rke2-default-aws](docs/guides/rke2-default-aws.md) |
| Deploy **RKE2** on **my own nodes** (BYO / on-premise) | [rke2-default-byo](docs/guides/rke2-default-byo.md) |
| Deploy **RKE2** in an **airgap** on AWS | [rke2-airgap-aws](docs/guides/rke2-airgap-aws.md) |
| Deploy **K3s** on **AWS** | [k3s-default-aws](docs/guides/k3s-default-aws.md) |
| Deploy **K3s** on **my own nodes** (BYO / on-premise) | [k3s-default-byo](docs/guides/k3s-default-byo.md) |
| Install **Rancher** on an existing cluster | [rancher-ha](docs/guides/rancher-ha.md) |
| Add a **new cloud provider** | [adding-a-provider](docs/adding-a-provider.md) |
| See **all guides** | [docs/guides/](docs/guides/README.md) |

## The Impatient Path

Full RKE2 cluster + Rancher on AWS in three commands:

```bash
# 1. Configure  tofu/aws/modules/cluster_nodes/terraform.tfvars  (see guide)
# 2. Configure  ansible/rke2/default/vars.yaml                   (see guide)

make all    # provisions infra → deploys RKE2 → installs Rancher
```

For an airgap deployment: `make all ENV=airgap`. For K3s: `make all DISTRO=k3s`.

See [prerequisites](docs/prerequisites.md) first.

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](docs/getting-started.md) | Project overview, supported configurations, where to go next |
| [Prerequisites](docs/prerequisites.md) | Tools, Python packages, cloud credentials, SSH keys |
| [Architecture](docs/architecture.md) | How the Tofu and Ansible layers work together |
| [Makefile Reference](docs/reference/makefile.md) | All `make` targets, variables, and examples |
| [Inventory Format](docs/reference/inventory-format.md) | Ansible inventory schema for BYO and Tofu-generated inventories |
| [Variables Reference](docs/reference/variables.md) | All Ansible variables across playbooks and roles |
| [Troubleshooting](docs/reference/troubleshooting.md) | Common issues and fixes |
| [FAQ](docs/faq.md) | Frequently asked questions |

## Directory Structure

```
├── ansible/                    # Product deployment (provider-agnostic)
│   ├── rke2/                   #   RKE2 playbooks (default, airgap)
│   ├── k3s/                    #   K3s playbooks (default)
│   ├── rancher/                #   Rancher playbooks (HA, downstream)
│   └── roles/                  #   Reusable Ansible roles
│
├── tofu/                       # Infrastructure provisioning
│   ├── aws/modules/            #   AWS (cluster_nodes, airgap, ...)
│   ├── gcp/modules/            #   GCP (elemental_nodes, ...)
│   └── harvester/modules/      #   Harvester (vm, loadbalancer, ...)
│
├── docs/                       # Documentation
│   ├── guides/                 #   End-to-end deployment guides
│   └── reference/              #   Reference material
│
└── scripts/                    # Helper scripts (inventory generation, etc.)
```

## Contributing

All are welcome and encouraged to contribute! Please keep changes generalized, easy to understand, and reusable.

- Follow the [OpenTofu style guide](https://opentofu.org/docs/language/syntax/style/) and [Ansible best practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html)
- New Ansible playbooks and Tofu modules must include a README with usage, inputs, outputs, and examples
- Reusable task collections should be Ansible roles
- Use variables for environment-specific values with descriptions
- Add yourself to [CODEOWNERS](./CODEOWNERS) for paths you own

If you're familiar with Terraform but not OpenTofu, see [migrating from Terraform to Tofu](https://opentofu.org/docs/intro/migration/) — they are nearly identical.
