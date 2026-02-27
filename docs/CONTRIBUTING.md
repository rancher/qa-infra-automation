# Contributing Guide

## Prerequisites

Install the following tools before working with this repository:

- **[OpenTofu](https://opentofu.org/docs/intro/install/)** – Infrastructure provisioning (open-source Terraform alternative)
- **[Ansible](https://docs.ansible.com/ansible/latest/installation_guide/)** – Configuration management and deployment
- **Python packages**: `python3 -m pip install ansible kubernetes`
- **Ansible collection**: `ansible-galaxy collection install cloud.terraform`

## Development Setup

1. Clone the repository
2. Copy the example environment file: `cp vars.example-env .env` and fill in your values
3. Configure `tofu/<provider>/modules/<env>/terraform.tfvars` for your target environment
4. Copy inventory templates and configure group vars (see relevant QUICKSTART.md)

## Available Commands

### Configuration

Override defaults with `make <target> DISTRO=k3s ENV=default PROVIDER=aws`.

| Variable   | Default   | Valid Values               | Description                    |
|------------|-----------|----------------------------|--------------------------------|
| `DISTRO`   | `rke2`    | `rke2`, `k3s`              | Kubernetes distribution        |
| `ENV`      | `airgap`  | `airgap`, `default`, `proxy` | Deployment environment type  |
| `PROVIDER` | `aws`     | `aws`, `gcp`, `harvester`  | Cloud/infrastructure provider  |

### Infrastructure (Tofu)

| Command         | Description                                        |
|-----------------|----------------------------------------------------|
| `make infra-init`  | Initialize OpenTofu (downloads providers)       |
| `make infra-plan`  | Preview infrastructure changes                  |
| `make infra-up`    | Create infrastructure (generates inventory)     |
| `make infra-down`  | Destroy infrastructure (prompts for confirmation)|
| `make infra-output`| Show OpenTofu outputs                          |

### Cluster Deployment (Ansible)

| Command              | Description                                   |
|----------------------|-----------------------------------------------|
| `make cluster`       | Install Kubernetes cluster (RKE2 or K3s)      |
| `make agents`        | Set up additional agent nodes                 |
| `make registry`      | Configure private registry on cluster nodes   |
| `make rancher`       | Deploy Rancher to cluster                     |
| `make upgrade`       | Upgrade Kubernetes cluster                    |
| `make kubectl-setup` | Set up kubectl access on bastion              |

### Utilities

| Command              | Description                                   |
|----------------------|-----------------------------------------------|
| `make validate`      | Validate configuration and prerequisites      |
| `make status`        | Show cluster status (nodes and Rancher pods)  |
| `make test-ssh`      | Test SSH connectivity to all nodes            |
| `make ssh-bastion`   | Open SSH session to bastion host              |
| `make ping`          | Ping all inventory hosts                      |
| `make inventory-graph` | Show inventory structure                   |
| `make clean`         | Remove local temporary files                  |
| `make debug-vars`    | Show current variable values and derived paths|

### Combined Workflows

| Command               | Description                                              |
|-----------------------|----------------------------------------------------------|
| `make all`            | Full setup: infrastructure + cluster + registry + Rancher|
| `make setup-from-infra` | Cluster + Rancher setup (infrastructure already exists)|

## Environment Variables

The following variables can be set in an environment file (see `vars.example-env`):

| Variable                  | Description                                         |
|---------------------------|-----------------------------------------------------|
| `REPO_ROOT`               | Absolute path to repository root                    |
| `WORKSPACE_NAME`          | OpenTofu workspace name                             |
| `TERRAFORM_NODE_SOURCE`   | Relative path to tfstate location (used by Ansible) |
| `RKE2_PLAYBOOK_PATH`      | Path to RKE2 playbook                               |
| `TERRAFORM_INVENTORY`     | Path to generated Terraform inventory               |
| `ANSIBLE_CONFIG`          | Path to ansible.cfg                                 |
| `RANCHER_PLAYBOOK_PATH`   | Path to Rancher playbook                            |
| `TFVARS_FILE`             | Name of Terraform variables file                    |
| `KUBECONFIG_FILE`         | Path to kubeconfig output file                      |
| `VARS_FILE`               | Path to Ansible variables file                      |
| `PRIVATE_KEY_FILE`        | Path to SSH private key for node access             |

## Code Standards

- **Ansible playbooks must be provider-agnostic** — they should run regardless of how infrastructure was provisioned.
- **OpenTofu modules must be modular** — each module should work standalone or composed with others.
- **All new playbooks and modules require a README** with: purpose, inputs, outputs, and a usage example.
- **Reusable task collections must be Ansible roles** placed in `ansible/roles/`.
- **OS support**: All playbooks must work on SLES and SLE Micro at minimum; RHEL and Ubuntu are nice-to-have.
- **Variables over hardcoded values**: Any environment-specific value must be a variable with a description.

Follow the [OpenTofu style guide](https://opentofu.org/docs/language/syntax/style/) and [Ansible best practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html).

## Pull Request Checklist

- [ ] Changes are generalized and reusable
- [ ] New playbooks/modules include a README (usage, inputs, outputs, examples)
- [ ] New reusable task sets are implemented as Ansible roles in `ansible/roles/`
- [ ] Tested on SLES or SLE Micro
- [ ] Added yourself/your team to [CODEOWNERS](../CODEOWNERS) for owned paths

## Quickstart References

For step-by-step guides:

- **AWS Cluster Nodes**: `tofu/aws/modules/cluster_nodes/QUICKSTART.md`
- **RKE2 Deployment**: `ansible/rke2/default/QUICKSTART.md`
- **K3s Deployment**: `ansible/k3s/default/QUICKSTART.md`
- **Rancher HA**: `ansible/rancher/default-ha/QUICKSTART.md`
