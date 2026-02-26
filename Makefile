# Makefile for QA Infrastructure Automation
# Supports multiple Kubernetes distributions, environments, and cloud providers

# ============================================================================
# CONFIGURATION
# ============================================================================

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Configurable parameters (override with: make <target> DISTRO=k3s ENV=default)
DISTRO   ?= rke2
ENV      ?= airgap
PROVIDER ?= aws

# Derived paths
TOFU_DIR    := tofu/$(PROVIDER)/modules/$(ENV)
ANSIBLE_DIR := ansible/$(DISTRO)/$(ENV)
INVENTORY   := $(ANSIBLE_DIR)/inventory/inventory.yml
GROUP_VARS  := $(ANSIBLE_DIR)/inventory/group_vars/all.yml

# Ansible settings
export ANSIBLE_HOST_KEY_CHECKING := False
export ANSIBLE_CONFIG            := $(CURDIR)/ansible/ansible.cfg
export ANSIBLE_ROLES_PATH        := $(CURDIR)/ansible/roles

# Airgap deployments need a remote user and yaml output; set via env vars so the
# shared ansible.cfg does not need product-specific overrides.
ifeq ($(ENV),airgap)
export ANSIBLE_REMOTE_USER     := ec2-user
export ANSIBLE_STDOUT_CALLBACK := yaml
endif

# Validate configuration
VALID_DISTROS   := rke2 k3s
VALID_ENVS      := airgap default proxy
VALID_PROVIDERS := aws gcp harvester

# ============================================================================
# HELP
# ============================================================================

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "QA Infrastructure Automation"
	@echo "============================="
	@echo ""
	@echo "Current Configuration:"
	@echo "  DISTRO   = $(DISTRO)      (options: rke2, k3s)"
	@echo "  ENV      = $(ENV)     (options: airgap, default, proxy)"
	@echo "  PROVIDER = $(PROVIDER)       (options: aws, gcp, harvester)"
	@echo ""
	@echo "Override with: make <target> DISTRO=k3s ENV=default PROVIDER=aws"
	@echo "At the moment this only supports rke2, airgap, and aws"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. Configure $(TOFU_DIR)/terraform.tfvars"
	@echo "  2. Run: make infra-up"
	@echo "  3. Configure $(GROUP_VARS) if needed"
	@echo "  4. Run: make cluster"
	@echo "  5. Run: make registry    (for airgap environments)"
	@echo "  6. Run: make rancher"
	@echo ""
	@echo "Note: If not using 'make infra-up', create inventory manually:"
	@echo "  cp $(ANSIBLE_DIR)/inventory/inventory.yml.template $(INVENTORY)"
	@echo "  cp $(ANSIBLE_DIR)/inventory/group_vars/all.yml.template $(GROUP_VARS)"
	@echo ""
	@echo "INFRASTRUCTURE (Tofu):"
	@echo "  infra-init          Initialize Tofu (downloads providers)"
	@echo "  infra-plan          Plan infrastructure changes"
	@echo "  infra-up            Create infrastructure (generates inventory)"
	@echo "  infra-down          Destroy infrastructure"
	@echo "  infra-output        Show Tofu outputs"
	@echo ""
	@echo "CLUSTER (Ansible):"
	@echo "  cluster             Install Kubernetes cluster"
	@echo "  agents              Setup additional agent nodes"
	@echo "  registry            Configure private registry on cluster nodes"
	@echo "  rancher             Deploy Rancher to cluster"
	@echo "  upgrade-cluster     Upgrade Kubernetes cluster"
	@echo "  kubectl-setup       Setup kubectl access on bastion"
	@echo ""
	@echo "UTILITIES:"
	@echo "  status              Show cluster status"
	@echo "  test-ssh            Test SSH connectivity to all nodes"
	@echo "  ssh-bastion         SSH to bastion host"
	@echo "  ping                Ping all hosts"
	@echo "  validate            Validate configuration and prerequisites"
	@echo "  clean               Clean local temporary files"
	@echo ""
	@echo "COMBINED WORKFLOWS:"
	@echo "  all                 Full setup: infrastructure + cluster + Rancher"
	@echo "  setup-from-infra    Setup cluster + Rancher (infra already exists)"
	@echo ""
	@echo "EXAMPLES:"
	@echo "  make all                                    # RKE2 airgap on AWS (default)"
	@echo "  make all DISTRO=k3s ENV=default             # K3s default on AWS"
	@echo "  make cluster DISTRO=rke2 ENV=airgap         # Just RKE2 airgap cluster"
	@echo "  make status                                 # Check current cluster"
	@echo ""

# ============================================================================
# VALIDATION
# ============================================================================

.PHONY: validate
validate: check-prereqs check-config ## Validate configuration and prerequisites
	@echo "Validation complete"

.PHONY: check-prereqs
check-prereqs: ## Check all prerequisites are installed
	@echo "Checking prerequisites..."
	@command -v tofu >/dev/null 2>&1 || { echo "Error: tofu is not installed"; exit 1; }
	@command -v ansible >/dev/null 2>&1 || { echo "Error: ansible is not installed"; exit 1; }
	@command -v ansible-playbook >/dev/null 2>&1 || { echo "Error: ansible-playbook is not installed"; exit 1; }
	@echo "All prerequisites found"

.PHONY: check-config
check-config: ## Validate configuration parameters
	@echo "Validating configuration..."
	@echo "  DISTRO=$(DISTRO) ENV=$(ENV) PROVIDER=$(PROVIDER)"
	@if [ ! -d "$(ANSIBLE_DIR)" ]; then \
		echo "Error: Ansible directory not found: $(ANSIBLE_DIR)"; \
		echo "This DISTRO/ENV combination may not be implemented yet"; \
		exit 1; \
	fi
	@if [ ! -d "$(TOFU_DIR)" ]; then \
		echo "Warning: Tofu directory not found: $(TOFU_DIR)"; \
		echo "Infrastructure provisioning may not be available for this configuration"; \
	fi
	@echo "Configuration valid"

.PHONY: check-inventory
check-inventory:
	@if [ ! -f "$(INVENTORY)" ]; then \
		echo "Error: Inventory file not found at $(INVENTORY)"; \
		echo "Run 'make infra-up' first to generate inventory"; \
		exit 1; \
	fi

.PHONY: check-tofu-dir
check-tofu-dir:
	@if [ ! -d "$(TOFU_DIR)" ]; then \
		echo "Error: Tofu directory not found: $(TOFU_DIR)"; \
		echo "This PROVIDER/ENV combination may not be implemented yet"; \
		exit 1; \
	fi
	@if [ ! -f "$(TOFU_DIR)/terraform.tfvars" ]; then \
		echo "Error: terraform.tfvars not found at $(TOFU_DIR)/terraform.tfvars"; \
		exit 1; \
	fi

# ============================================================================
# INFRASTRUCTURE (TOFU)
# ============================================================================

.PHONY: infra-init
infra-init: check-prereqs check-tofu-dir ## Initialize Tofu
	@echo "Initializing Tofu for $(PROVIDER)/$(ENV)..."
	cd $(TOFU_DIR) && tofu init

.PHONY: infra-plan
infra-plan: infra-init ## Plan infrastructure changes
	@echo "Planning infrastructure..."
	cd $(TOFU_DIR) && tofu plan -var-file=terraform.tfvars

.PHONY: infra-up
infra-up: infra-init ## Create infrastructure
	@echo "Creating $(PROVIDER) infrastructure for $(ENV) environment..."
	cd $(TOFU_DIR) && tofu apply -var-file=terraform.tfvars -auto-approve
	@echo ""
	@echo "Infrastructure created. Inventory generated at $(INVENTORY)"

.PHONY: infra-down
infra-down: check-tofu-dir ## Destroy infrastructure
	@echo "Warning: This will destroy all $(PROVIDER)/$(ENV) infrastructure"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	cd $(TOFU_DIR) && tofu destroy -var-file=terraform.tfvars -auto-approve

.PHONY: infra-output
infra-output: ## Show Tofu outputs
	cd $(TOFU_DIR) && tofu output

# ============================================================================
# CLUSTER DEPLOYMENT (ANSIBLE)
# ============================================================================

.PHONY: cluster
cluster: check-inventory ## Install Kubernetes cluster
	@echo "Installing $(DISTRO) cluster ($(ENV) environment)..."
	@if [ "$(ENV)" = "airgap" ]; then \
		ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy/$(DISTRO)-tarball-playbook.yml -v $(ANSIBLE_EXTRA_VARS); \
	else \
		ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy/$(DISTRO)-install-playbook.yml -v $(ANSIBLE_EXTRA_VARS); \
	fi

.PHONY: agents
agents: check-inventory ## Setup additional agent nodes
	@echo "Setting up agent nodes..."
	@ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/setup/setup-agent-nodes.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: rancher
rancher: check-inventory ## Deploy Rancher to cluster
	@echo "Deploying Rancher..."
	@ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy/rancher-helm-deploy-playbook.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: registry
registry: check-inventory ## Configure private registry on cluster nodes
	@echo "Configuring private registry..."
	@ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy/rke2-registry-config-playbook.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: upgrade-cluster
upgrade: check-inventory ## Upgrade Kubernetes cluster
	@echo "Upgrading $(DISTRO) cluster..."
	@ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy/$(DISTRO)-upgrade-playbook.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: kubectl-setup
kubectl-setup: check-inventory ## Setup kubectl access on bastion
	@echo "Setting up kubectl access..."
	@ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/setup/setup-kubectl-access.yml -v $(ANSIBLE_EXTRA_VARS)

# ============================================================================
# UTILITIES
# ============================================================================

.PHONY: test-ssh
test-ssh: check-inventory ## Test SSH connectivity to all nodes
	@echo "Testing SSH connectivity..."
	@ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/debug/test-ssh-connectivity.yml -v

.PHONY: status
status: check-inventory ## Show cluster status
	@echo "Cluster Status ($(DISTRO)/$(ENV)):"
	@echo ""
	@echo "=== Nodes ==="
	@ansible -i $(INVENTORY) bastion -m shell -a "kubectl get nodes -o wide" 2>/dev/null || echo "Could not get cluster status"
	@echo ""
	@echo "=== Rancher Pods ==="
	@ansible -i $(INVENTORY) bastion -m shell -a "kubectl get pods -n cattle-system 2>/dev/null || echo 'Rancher not deployed'" 2>/dev/null || true

.PHONY: ssh-bastion
ssh-bastion: check-inventory ## SSH to bastion host
	@BASTION=$$(ansible-inventory -i $(INVENTORY) --host bastion-node 2>/dev/null | grep '"bastion_host"' | cut -d'"' -f4); \
	KEY=$$(ansible-inventory -i $(INVENTORY) --host bastion-node 2>/dev/null | grep '"ssh_private_key_file"' | cut -d'"' -f4); \
	USER=$$(ansible-inventory -i $(INVENTORY) --host bastion-node 2>/dev/null | grep '"bastion_user"' | cut -d'"' -f4); \
	KEY=$$(eval echo $$KEY); \
	echo "Connecting to bastion: $$USER@$$BASTION"; \
	ssh -i $$KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=none $$USER@$$BASTION

.PHONY: ping
ping: check-inventory ## Ping all hosts
	@ansible -i $(INVENTORY) all -m ping

.PHONY: inventory-graph
inventory-graph: check-inventory ## Show inventory structure
	@ansible-inventory -i $(INVENTORY) --graph

.PHONY: clean
clean: ## Clean local temporary files
	@echo "Cleaning local temporary files..."
	rm -f /tmp/ansible-rke2-bundle.tar.gz
	rm -f /tmp/ansible-k3s-bundle.tar.gz
	rm -f /tmp/rke2-*.yaml
	rm -f /tmp/k3s-*.yaml
	rm -f *-upgrade-readiness-*.txt
	@echo "Local cleanup complete"

# ============================================================================
# COMBINED WORKFLOWS
# ============================================================================

.PHONY: all
all: infra-up cluster registry rancher ## Full setup: infrastructure + cluster + Rancher
	@echo ""
	@echo "Full $(DISTRO) $(ENV) environment setup complete!"
	@echo ""
	@$(MAKE) status DISTRO=$(DISTRO) ENV=$(ENV) PROVIDER=$(PROVIDER)

.PHONY: setup-from-infra
setup-from-infra: check-inventory cluster registry rancher ## Setup cluster + Rancher (infra exists)
	@echo ""
	@echo "$(DISTRO) cluster and Rancher setup complete!"
	@echo ""
	@$(MAKE) status DISTRO=$(DISTRO) ENV=$(ENV) PROVIDER=$(PROVIDER)

# ============================================================================
# DEBUG
# ============================================================================

.PHONY: debug-vars
debug-vars: ## Show current variable values
	@echo "Configuration Variables:"
	@echo "  DISTRO      = $(DISTRO)"
	@echo "  ENV         = $(ENV)"
	@echo "  PROVIDER    = $(PROVIDER)"
	@echo ""
	@echo "Derived Paths:"
	@echo "  TOFU_DIR    = $(TOFU_DIR)"
	@echo "  ANSIBLE_DIR = $(ANSIBLE_DIR)"
	@echo "  INVENTORY   = $(INVENTORY)"
	@echo "  GROUP_VARS  = $(GROUP_VARS)"
	@echo ""
	@echo "Directory Status:"
	@echo "  Tofu dir exists:    $$([ -d "$(TOFU_DIR)" ] && echo "yes" || echo "no")"
	@echo "  Ansible dir exists: $$([ -d "$(ANSIBLE_DIR)" ] && echo "yes" || echo "no")"
	@echo "  Inventory exists:   $$([ -f "$(INVENTORY)" ] && echo "yes" || echo "no")"

# Extra vars support
ifdef EXTRA_VARS
ANSIBLE_EXTRA_VARS := --extra-vars "$(EXTRA_VARS)"
else
ANSIBLE_EXTRA_VARS :=
endif
