# Makefile for RKE2 Airgap Environment Setup
# Simplifies running Tofu and Ansible commands for airgap deployments

# Configuration
SHELL := /bin/bash
.DEFAULT_GOAL := help

# Paths
TOFU_DIR := ../../../tofu/aws/modules/airgap
ANSIBLE_DIR := .
INVENTORY := inventory/inventory.yml
GROUP_VARS := inventory/group_vars/all.yml
ANSIBLE_CFG := ansible.cfg

# Ansible settings
export ANSIBLE_CONFIG := $(ANSIBLE_DIR)/$(ANSIBLE_CFG)
export ANSIBLE_HOST_KEY_CHECKING := False

# ============================================================================
# HELP
# ============================================================================

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo "RKE2 Airgap Environment Setup"
	@echo "=============================="
	@echo ""
	@echo "Quick Start:"
	@echo "  1. Configure $(TOFU_DIR)/terraform.tfvars"
	@echo "  2. Run: make infra-up"
	@echo "  3. Configure $(GROUP_VARS) if needed"
	@echo "  4. Run: make cluster"
	@echo "  5. Run: make rancher"
	@echo ""
	@echo "Available targets:"
	@echo ""
	@echo "INFRASTRUCTURE (Tofu):"
	@echo "  infra-init          Initialize Tofu (downloads providers)"
	@echo "  infra-plan          Plan infrastructure changes"
	@echo "  infra-up            Create infrastructure (generates inventory)"
	@echo "  infra-down          Destroy infrastructure"
	@echo "  infra-output        Show Tofu outputs"
	@echo "  infra-refresh       Refresh Tofu state"
	@echo ""
	@echo "CLUSTER (Ansible):"
	@echo "  cluster             Install RKE2 cluster (tarball method)"
	@echo "  agents              Setup additional agent nodes"
	@echo "  rancher             Deploy Rancher to cluster"
	@echo "  rke2-upgrade        Upgrade RKE2 cluster"
	@echo "  kubectl-setup       Setup kubectl access on bastion"
	@echo ""
	@echo "UTILITIES:"
	@echo "  status              Show cluster status"
	@echo "  test-ssh            Test SSH connectivity to all nodes"
	@echo "  ssh-bastion         SSH to bastion host"
	@echo "  ping                Ping all hosts"
	@echo "  validate-upgrade    Validate cluster readiness for upgrade"
	@echo "  inventory-graph     Show inventory structure"
	@echo "  clean-local         Clean local temporary files"
	@echo ""
	@echo "COMBINED WORKFLOWS:"
	@echo "  all                 Full setup: infrastructure + RKE2 + Rancher"
	@echo "  full-cluster        Install RKE2 and setup all agents"
	@echo "  setup-from-infra    Setup cluster and Rancher (infra already exists)"
	@echo ""
	@echo "EXTRA VARS:"
	@echo "  Pass extra vars like: make cluster EXTRA_VARS=\"rke2_version=v1.31.0+rke2r1\""
	@echo ""

# ============================================================================
# PREREQUISITES CHECK
# ============================================================================

.PHONY: check-prereqs
check-prereqs: ## Check all prerequisites are installed
	@echo "Checking prerequisites..."
	@command -v tofu >/dev/null 2>&1 || { echo "Error: tofu is not installed"; exit 1; }
	@command -v ansible >/dev/null 2>&1 || { echo "Error: ansible is not installed"; exit 1; }
	@command -v ansible-playbook >/dev/null 2>&1 || { echo "Error: ansible-playbook is not installed"; exit 1; }
	@echo "All prerequisites found"

.PHONY: check-inventory
check-inventory: ## Verify inventory file exists
	@if [ ! -f "$(INVENTORY)" ]; then \
		echo "Error: Inventory file not found at $(INVENTORY)"; \
		echo "Run 'make infra-up' first to generate inventory"; \
		exit 1; \
	fi

.PHONY: check-tofu-vars
check-tofu-vars: ## Verify Tofu variables file exists
	@if [ ! -f "$(TOFU_DIR)/terraform.tfvars" ]; then \
		echo "Error: terraform.tfvars not found at $(TOFU_DIR)/terraform.tfvars"; \
		echo "Copy terraform.tfvars.example and configure it"; \
		exit 1; \
	fi

# ============================================================================
# INFRASTRUCTURE (TOFU)
# ============================================================================

.PHONY: infra-init
infra-init: check-prereqs check-tofu-vars ## Initialize Tofu (downloads providers)
	@echo "Initializing Tofu..."
	cd $(TOFU_DIR) && tofu init

.PHONY: infra-plan
infra-plan: infra-init ## Plan infrastructure changes
	@echo "Planning infrastructure..."
	cd $(TOFU_DIR) && tofu plan -var-file=terraform.tfvars

.PHONY: infra-up
infra-up: infra-init ## Create infrastructure (generates inventory)
	@echo "Creating infrastructure..."
	cd $(TOFU_DIR) && tofu apply -var-file=terraform.tfvars -auto-approve
	@echo "Infrastructure created. Inventory generated at $(INVENTORY)"

.PHONY: infra-down
infra-down: check-tofu-vars ## Destroy infrastructure
	@echo "Warning: This will destroy all infrastructure"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	cd $(TOFU_DIR) && tofu destroy -var-file=terraform.tfvars -auto-approve

.PHONY: infra-output
infra-output: ## Show Tofu outputs
	cd $(TOFU_DIR) && tofu output

.PHONY: infra-refresh
infra-refresh: ## Refresh Tofu state
	cd $(TOFU_DIR) && tofu refresh -var-file=terraform.tfvars

# ============================================================================
# CLUSTER DEPLOYMENT (ANSIBLE)
# ============================================================================

.PHONY: cluster
cluster: check-inventory ## Install RKE2 cluster (tarball method)
	@echo "Installing RKE2 cluster..."
	ansible-playbook -i $(INVENTORY) playbooks/deploy/rke2-tarball-playbook.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: agents
agents: check-inventory ## Setup additional agent nodes
	@echo "Setting up agent nodes..."
	ansible-playbook -i $(INVENTORY) playbooks/setup/setup-agent-nodes.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: rancher
rancher: check-inventory ## Deploy Rancher to cluster
	@echo "Deploying Rancher..."
	ansible-playbook -i $(INVENTORY) playbooks/deploy/rancher-helm-deploy-playbook.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: rke2-upgrade
rke2-upgrade: check-inventory ## Upgrade RKE2 cluster
	@echo "Upgrading RKE2 cluster..."
	ansible-playbook -i $(INVENTORY) playbooks/deploy/rke2-upgrade-playbook.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: kubectl-setup
kubectl-setup: check-inventory ## Setup kubectl access on bastion
	@echo "Setting up kubectl access..."
	ansible-playbook -i $(INVENTORY) playbooks/setup/setup-kubectl-access.yml -v $(ANSIBLE_EXTRA_VARS)

# ============================================================================
# UTILITIES
# ============================================================================

.PHONY: test-ssh
test-ssh: check-inventory ## Test SSH connectivity to all nodes
	@echo "Testing SSH connectivity..."
	ansible-playbook -i $(INVENTORY) playbooks/debug/test-ssh-connectivity.yml -v

.PHONY: validate-upgrade
validate-upgrade: check-inventory ## Validate cluster readiness for upgrade
	@echo "Validating upgrade readiness..."
	ansible-playbook -i $(INVENTORY) playbooks/debug/validate-upgrade-readiness.yml -v

.PHONY: status
status: check-inventory ## Show cluster status
	@echo "Checking cluster status..."
	@echo ""
	@echo "=== Nodes ==="
	@ansible -i $(INVENTORY) bastion -m shell -a "kubectl get nodes -o wide" 2>/dev/null || echo "Could not get cluster status"
	@echo ""
	@echo "=== Rancher Pods ==="
	@ansible -i $(INVENTORY) bastion -m shell -a "kubectl get pods -n cattle-system 2>/dev/null || echo 'Rancher not deployed'" 2>/dev/null || true

.PHONY: ssh-bastion
ssh-bastion: check-inventory ## SSH to bastion host
	@BASTION=$$(ansible-inventory -i $(INVENTORY) --host bastion-node 2>/dev/null | grep ansible_host | cut -d'"' -f4); \
	KEY=$$(ansible-inventory -i $(INVENTORY) --host bastion-node 2>/dev/null | grep ansible_ssh_private_key_file | cut -d'"' -f4); \
	USER=$$(ansible-inventory -i $(INVENTORY) --host bastion-node 2>/dev/null | grep ansible_user | cut -d'"' -f4); \
	echo "Connecting to bastion: $$USER@$$BASTION"; \
	ssh -i $$KEY -o StrictHostKeyChecking=no $$USER@$$BASTION

.PHONY: clean-local
clean-local: ## Clean local temporary files
	@echo "Cleaning local temporary files..."
	rm -f /tmp/ansible-rke2-bundle.tar.gz
	rm -f /tmp/rke2-*.yaml
	rm -f rke2-upgrade-readiness-*.txt
	@echo "Local cleanup complete"

# ============================================================================
# COMBINED WORKFLOWS
# ============================================================================

.PHONY: all
all: infra-up cluster rancher ## Full setup: infrastructure + RKE2 + Rancher
	@echo ""
	@echo "Full airgap environment setup complete!"
	@echo ""
	@$(MAKE) status

.PHONY: full-cluster
full-cluster: cluster agents ## Install RKE2 and setup all agents
	@echo "Cluster setup complete!"

.PHONY: setup-from-infra
setup-from-infra: check-inventory cluster rancher ## Setup cluster and Rancher (infra already exists)
	@echo ""
	@echo "Cluster and Rancher setup complete!"
	@echo ""
	@$(MAKE) status

# ============================================================================
# ADVANCED / DEBUG
# ============================================================================

.PHONY: diagnose-registry
diagnose-registry: check-inventory ## Diagnose registry issues
	ansible-playbook -i $(INVENTORY) playbooks/debug/diagnose-registry.yml -v

.PHONY: fix-checksums
fix-checksums: check-inventory ## Fix checksum issues
	ansible-playbook -i $(INVENTORY) playbooks/debug/fix-checksum-issues.yml -v

.PHONY: inventory-graph
inventory-graph: check-inventory ## Show inventory structure
	ansible-inventory -i $(INVENTORY) --graph --vars

.PHONY: ping
ping: check-inventory ## Ping all hosts
	ansible -i $(INVENTORY) all -m ping

# Extra vars support - use like: make cluster EXTRA_VARS="rke2_version=v1.31.0+rke2r1"
ifdef EXTRA_VARS
ANSIBLE_EXTRA_VARS := --extra-vars "$(EXTRA_VARS)"
else
ANSIBLE_EXTRA_VARS :=
endif
