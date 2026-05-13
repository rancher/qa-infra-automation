# Makefile Reference

The Makefile orchestrates the full deployment lifecycle. All targets are run from the **repository root**.

## Configuration Variables

Override these with `make <target> VAR=value`:

| Variable | Default | Options | Description |
|----------|---------|---------|-------------|
| `DISTRO` | `rke2` | `rke2`, `k3s` | Kubernetes distribution |
| `ENV` | `default` | `default`, `airgap`, `proxy` | Deployment environment |
| `PROVIDER` | `aws` | `aws`, `gcp`, `harvester` | Infrastructure provider |
| `EXTRA_VARS` | (empty) | any | Extra Ansible variables passed with `--extra-vars` |

**Example:**

```bash
make all DISTRO=k3s ENV=default PROVIDER=aws
```

## Targets

### Infrastructure (Tofu)

| Target | Description |
|--------|-------------|
| `make infra-init` | Initialize Tofu (download providers) |
| `make infra-plan` | Preview infrastructure changes |
| `make infra-up` | Create infrastructure and generate Ansible inventory |
| `make infra-down` | Destroy infrastructure (with confirmation prompt) |
| `make infra-output` | Show Tofu outputs |
| `make infra-ls` | List all active infrastructure across all modules/workspaces |
| `make infra-nuke` | Destroy ALL active infrastructure (end-of-day cleanup) |

### Cluster Deployment (Ansible)

| Target | Description |
|--------|-------------|
| `make cluster` | Install Kubernetes cluster |
| `make agents` | Set up additional agent nodes (airgap) |
| `make registry` | Configure private registry on cluster nodes (airgap) |
| `make rancher` | Deploy Rancher onto the cluster |
| `make upgrade-cluster` | Upgrade Kubernetes version |
| `make kubectl-setup` | Set up kubectl on the bastion host (airgap) |

### Utilities

| Target | Description |
|--------|-------------|
| `make status` | Show cluster node and Rancher pod status |
| `make test-ssh` | Test SSH connectivity to all nodes |
| `make ssh-bastion` | SSH into the bastion host (airgap) |
| `make ping` | Ansible ping all hosts |
| `make validate` | Check all prerequisites and configuration |
| `make verify` | Verify supply chain integrity (version pins, lock files) |
| `make clean` | Remove local temporary files |
| `make collections` | Install Ansible collections from `requirements.yml` |
| `make debug-vars` | Print all current variable values and path status |

### Combined Workflows

| Target | Description |
|--------|-------------|
| `make all` | Full setup: infra-up → cluster → rancher |
| `make setup-from-infra` | Cluster + rancher (infra already exists) |

## Common Invocations

```bash
# RKE2 on AWS (the default — all three variables match defaults)
make all

# K3s on AWS
make all DISTRO=k3s

# RKE2 airgap on AWS
make all ENV=airgap

# Just the cluster (no Rancher)
make infra-up && make cluster

# Just Rancher (cluster already running)
make rancher

# K3s cluster only, no Rancher, no infra provisioning
make cluster DISTRO=k3s

# Check what's running
make status

# Destroy everything
make infra-nuke

# Pass extra Ansible variables
make cluster EXTRA_VARS="kubernetes_version=v1.34.2+rke2r1"
```

## How Variables Determine Paths

The variables control which directories and playbooks are used:

| Variable | Path Component |
|----------|---------------|
| `DISTRO` + `ENV` | `ansible/$(DISTRO)/$(ENV)/` |
| `PROVIDER` + `ENV` | `tofu/$(PROVIDER)/modules/cluster_nodes/` (default) or `tofu/$(PROVIDER)/modules/$(ENV)/` (airgap) |

For example, `DISTRO=rke2 ENV=airgap PROVIDER=aws` maps to:
- Tofu: `tofu/aws/modules/airgap/`
- Ansible: `ansible/rke2/airgap/`
- Cluster playbook: `ansible/rke2/airgap/playbooks/deploy/rke2-tarball-playbook.yml`
- Rancher playbook: `ansible/rke2/airgap/playbooks/deploy/rancher-helm-deploy-playbook.yml`
