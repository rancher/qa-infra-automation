# Shared RKE2 Playbooks

This directory contains playbooks that are shared across all RKE2 deployment environments (default, airgap, proxy).

## Structure

```
shared/
├── bootstrap-python.yml              # Python 3.9+ bootstrap for minimal OS images
└── playbooks/
    ├── setup/
    │   ├── setup-kubectl-access.yml   # Configure kubectl on bastion
    │   └── setup-agent-nodes.yml     # Add agent nodes to cluster
    ├── deploy/
    │   └── rancher-helm-deploy-playbook.yml  # Deploy Rancher via Helm
    └── debug/
        └── validate-upgrade-readiness.yml    # Pre-upgrade validation
```

## Usage

These playbooks are referenced by the main Makefile and should not be called directly in most cases.

## Bootstrap Playbooks

### bootstrap-python.yml
Bootstraps Python 3.9+ on target nodes that don't have Python installed (e.g., SLE Micro).

**Purpose**: Ansible requires Python to run, but minimal OS images may not have Python pre-installed. This playbook uses a static binary build to bootstrap Python before other playbooks can execute.

**Method**: Downloads and installs pre-built Python binaries from indygreg/python-build-standalone.

**When to use**: Automatically called by `make cluster` when Python is not detected on target nodes.

## Setup Playbooks

### setup/setup-kubectl-access.yml
Configures kubectl on the bastion node with proper kubeconfig.

**Purpose**: Enables cluster management from the bastion host.

**Features**:
- Downloads kubectl matching the RKE2 version
- Fetches and configures kubeconfig from first cluster node
- Tests cluster connectivity

**Variables**:
- `target`: Target group (default: 'rancher')

**When to use**: Run `make kubectl-setup` after cluster deployment.

### setup/setup-agent-nodes.yml
Adds additional agent nodes to an existing RKE2 cluster.

**Purpose**: Scale out clusters by adding worker nodes.

**Features**:
- Fetches server token from first node
- Configures agents to join cluster
- Waits for nodes to become ready
- Supports parallel agent registration (serial: 3)

**Variables**:
- `target`: Target group (default: 'rancher')
- `agent_group`: Group containing agent nodes (default: 'airgap_nodes')

**When to use**: Run `make agents` to add worker nodes.

## Deploy Playbooks

### deploy/rancher-helm-deploy-playbook.yml
Deploys Rancher management server to RKE2 clusters using Helm.

**Purpose**: Install Rancher for centralized cluster management.

**Features**:
- Helm-based deployment
- Supports custom hostname configuration
- Configurable for internal/external load balancers

**Variables**:
- `rancher_hostname`: Rancher server hostname
- `internal_lb_hostname`: Internal load balancer hostname
- `external_lb_hostname`: External load balancer hostname (optional)

**When to use**: Run `make rancher` after cluster is ready.

## Debug Playbooks

### debug/validate-upgrade-readiness.yml
Validates cluster readiness before RKE2 upgrades.

**Purpose**: Pre-flight checks to ensure safe upgrades.

**Features**:
- Checks internet connectivity
- Validates disk space
- Verifies current cluster health
- Generates readiness report

**When to use**: Run before `make upgrade-cluster`.

## Environment-Agnostic Design

These playbooks work across all deployment environments by:
- Using variable-based group naming (not hardcoded 'airgap_nodes')
- Avoiding environment-specific assumptions
- Supporting both online and airgap deployments
- Working with any RKE2 installation method
