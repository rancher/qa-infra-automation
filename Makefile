# Makefile for QA Infrastructure Automation
# Supports multiple Kubernetes distributions, environments, and cloud providers

# ============================================================================
# CONFIGURATION
# ============================================================================

SHELL := /usr/bin/bash
.DEFAULT_GOAL := help

# Configurable parameters (override with: make <target> DISTRO=k3s ENV=default WORKSPACE=myworkspace)
DISTRO   ?= rke2
ENV      ?= default
PROVIDER ?= aws
WORKSPACE ?= default

# Derived paths
ANSIBLE_DIR := ansible/$(DISTRO)/$(ENV)
GROUP_VARS  := $(ANSIBLE_DIR)/inventory/group_vars/all.yml
INVENTORY   := $(ANSIBLE_DIR)/inventory/inventory.yml

# Environment-specific paths
ifeq ($(ENV),default)
TOFU_DIR         := tofu/$(PROVIDER)/modules/cluster_nodes
CLUSTER_PLAYBOOK := $(ANSIBLE_DIR)/$(DISTRO)-playbook.yml
RANCHER_PLAYBOOK := ansible/rancher/default-ha/rancher-playbook.yml
REGISTRY_TARGET  :=
else ifeq ($(ENV),airgap)
TOFU_DIR         := tofu/$(PROVIDER)/modules/$(ENV)
CLUSTER_PLAYBOOK := $(ANSIBLE_DIR)/playbooks/deploy/$(DISTRO)-tarball-playbook.yml
RANCHER_PLAYBOOK := $(ANSIBLE_DIR)/playbooks/deploy/rancher-helm-deploy-playbook.yml
REGISTRY_TARGET  := registry
else
TOFU_DIR         := tofu/$(PROVIDER)/modules/$(ENV)
CLUSTER_PLAYBOOK := $(ANSIBLE_DIR)/playbooks/deploy/$(DISTRO)-install-playbook.yml
RANCHER_PLAYBOOK := $(ANSIBLE_DIR)/playbooks/deploy/rancher-helm-deploy-playbook.yml
REGISTRY_TARGET  :=
endif

# Kubeconfig written by the cluster role; rancher needs to know where it is.
KUBECONFIG_FILE := $(CURDIR)/$(ANSIBLE_DIR)/kubeconfig.yaml

# Ansible settings
export ANSIBLE_HOST_KEY_CHECKING := False

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
	@echo "  WORKSPACE = $(WORKSPACE)    (tofu workspace name)"
	@echo ""
	@echo "Override with: make <target> DISTRO=k3s ENV=default PROVIDER=aws WORKSPACE=myworkspace"
	@echo "At the moment this only supports rke2, default/airgap, and aws"
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
	@echo "BACKEND MANAGEMENT:"
	@echo "  backend-s3          Configure S3 backend (requires BUCKET= KEY= REGION=)"
	@echo "  backend-local       Configure local backend (optional: PATH=)"
	@echo "  backend-init        Run tofu init in current module"
	@echo ""
	@echo "WORKSPACE MANAGEMENT:"
	@echo "  workspace-list      List all workspaces"
	@echo "  workspace-show      Show current workspace"
	@echo "  workspace-select    Select workspace interactively or use WORKSPACE=name"
	@echo "  workspace-inspect   Show detailed info about current workspace"
	@echo "  workspace-new       Create new workspace interactively or use WORKSPACE=name"
	@echo "  workspace-delete    Delete workspace interactively or use WORKSPACE=name)"
	@echo ""
	@echo "INFRASTRUCTURE (Tofu):"
	@echo "  infra-init          Initialize Tofu (downloads providers)"
	@echo "  infra-plan          Plan infrastructure changes"
	@echo "  infra-up            Create infrastructure (generates inventory)"
	@echo "  infra-down          Destroy infrastructure for current DISTRO/ENV/PROVIDER/WORKSPACE"
	@echo "  infra-output        Show Tofu outputs"
	@echo "  infra-ls            List ALL active infrastructure across every module/workspace"
	@echo "  infra-scan          Detailed scan of all infrastructure with resource counts"
	@echo "  infra-nuke          Destroy ALL active infrastructure (end-of-day cleanup)"
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
	@echo "  verify              Verify supply chain integrity"
	@echo "  clean               Clean local temporary files"
	@echo ""
	@echo "COMBINED WORKFLOWS:"
	@echo "  all                 Full setup: infrastructure + cluster + Rancher"
	@echo "  setup-from-infra    Setup cluster + Rancher (infra already exists)"
	@echo ""
	@echo "EXAMPLES:"
	@echo "  make all                                    # RKE2 default on AWS (default)"
	@echo "  make all ENV=airgap                         # RKE2 airgap on AWS"
	@echo "  make all DISTRO=k3s                         # K3s default on AWS"
	@echo "  make cluster ENV=airgap                     # Just RKE2 airgap cluster"
	@echo "  make status                                 # Check current cluster"
	@echo ""
	@echo "Backend Configuration:"
	@echo "  make backend-s3 BUCKET=my-bucket KEY=my-key REGION=us-east-1"
	@echo "  make backend-local PATH=terraform.tfstate"
	@echo ""
	@echo "Workspace Examples:"
	@echo "  make workspace-list                          # List all workspaces"
	@echo "  make workspace-show                          # Show current workspace"
	@echo "  make workspace-select                        # Interactive selection menu"
	@echo "  make workspace-select WORKSPACE=my-test      # Direct selection"
	@echo "  make workspace-inspect                       # Show workspace details"
	@echo "  make workspace-new                            # Create workspace interactively"
	@echo "  make workspace-new WORKSPACE=my-test          # Create workspace directly"
	@echo "  make infra-up WORKSPACE=my-test               # Deploy to workspace"
	@echo "  make infra-down WORKSPACE=my-test             # Destroy workspace resources"
	@echo "  make workspace-delete                         # Delete workspace interactively"
	@echo "  make workspace-delete WORKSPACE=my-test       # Delete workspace directly"
	@echo ""
	@echo "Infrastructure Discovery:"
	@echo "  make infra-ls                                # List all active infrastructure"
	@echo "  make infra-scan                              # Detailed scan with resource counts"
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
	@python3 -c "import yaml" 2>/dev/null || { echo "Installing Python dependencies..."; if [ -n "$$VIRTUAL_ENV" ]; then pip3 install -r requirements.txt; else pip3 install --user -r requirements.txt; fi; }
	@ansible-galaxy collection list 2>/dev/null | grep -q kubernetes.core || { echo "Installing Ansible collections..."; ansible-galaxy collection install -r requirements.yml; }
	@echo "All prerequisites found"

.PHONY: collections
collections: ## Install pinned Ansible collections
	ansible-galaxy collection install -r requirements.yml

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
check-inventory: ## Verify inventory exists and is not stale
	@if [ ! -f "$(INVENTORY)" ]; then \
		echo "Error: Inventory file not found at $(INVENTORY)"; \
		echo "Run 'make infra-up' first to generate inventory"; \
		exit 1; \
	fi
	@if [ -f "$(ANSIBLE_DIR)/inventory/.inventory-manifest.json" ]; then \
		python3 scripts/verify_inventory.py --manifest $(ANSIBLE_DIR)/inventory/.inventory-manifest.json; \
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
# BACKEND MANAGEMENT
# ============================================================================

.PHONY: backend-s3
backend-s3: ## Configure S3 backend for current module (use BUCKET= KEY= REGION=)
	@if [ -z "$(BUCKET)" ] || [ -z "$(KEY)" ] || [ -z "$(REGION)" ]; then \
		echo "Error: BUCKET, KEY, and REGION are required"; \
		echo "Usage: make backend-s3 BUCKET=my-bucket KEY=my-key REGION=us-east-1 [DYNAMODB_TABLE=table] [ENCRYPT=true]"; \
		exit 1; \
	fi
	@echo "Configuring S3 backend for $(TOFU_DIR)..."
	@(cd $(TOFU_DIR) && $(CURDIR)/tofu/scripts/init-backend.sh s3 --bucket "$(BUCKET)" --key "$(KEY)" --region "$(REGION)" $(if $(DYNAMODB_TABLE),--dynamodb-table "$(DYNAMODB_TABLE)") $(if $(ENCRYPT),--encrypt "$(ENCRYPT)"))

.PHONY: backend-local
backend-local: ## Configure local backend for current module (use PATH=terraform.tfstate)
	@echo "Configuring local backend for $(TOFU_DIR)..."
	@(cd $(TOFU_DIR) && $(CURDIR)/tofu/scripts/init-backend.sh local $(if $(PATH),--path "$(PATH)"))

.PHONY: backend-init
backend-init: ## Run tofu init in current module (for manual backend configuration)
	@echo "Initializing Tofu for $(TOFU_DIR)..."
	cd $(TOFU_DIR) && tofu init

# ============================================================================
# WORKSPACE MANAGEMENT
# ============================================================================

.PHONY: workspace-list
workspace-list: check-tofu-dir ## List all workspaces
	@echo "Listing workspaces for $(TOFU_DIR)..."
	cd $(TOFU_DIR) && tofu workspace list

.PHONY: workspace-show
workspace-show: check-tofu-dir ## Show current workspace
	@echo "Current workspace for $(TOFU_DIR):"
	cd $(TOFU_DIR) && tofu workspace show

.PHONY: workspace-select
workspace-select: check-tofu-dir ## Select workspace (use WORKSPACE=name or select interactively)
	@if [ "$(origin WORKSPACE)" = "command line" ]; then \
		echo "Selecting workspace '$(WORKSPACE)' for $(TOFU_DIR)..."; \
		cd $(TOFU_DIR) && tofu workspace select $(WORKSPACE); \
	else \
		$(CURDIR)/tofu/scripts/select-workspace.sh $(TOFU_DIR); \
	fi

.PHONY: workspace-new
workspace-new: check-tofu-dir ## Create new workspace (interactive or use WORKSPACE=name)
	@if [ "$(origin WORKSPACE)" = "command line" ]; then \
		if [ "$(WORKSPACE)" = "default" ]; then \
			echo "Error: 'default' is a reserved workspace name."; \
			echo "Please choose a different name."; \
			exit 1; \
		fi; \
		echo "Creating new workspace '$(WORKSPACE)' for $(TOFU_DIR)..."; \
		cd $(TOFU_DIR) && tofu workspace new $(WORKSPACE); \
	else \
		$(CURDIR)/tofu/scripts/new-workspace.sh $(TOFU_DIR); \
	fi

.PHONY: workspace-delete
workspace-delete: check-tofu-dir ## Delete workspace (interactive or use WORKSPACE=name)
	@if [ "$(origin WORKSPACE)" = "command line" ]; then \
		if [ "$(WORKSPACE)" = "default" ]; then \
			echo "Error: Cannot delete 'default' workspace."; \
			exit 1; \
		fi; \
		echo "Deleting workspace '$(WORKSPACE)' for $(TOFU_DIR)..."; \
		cd $(TOFU_DIR) && tofu workspace delete $(WORKSPACE); \
	else \
		$(CURDIR)/tofu/scripts/delete-workspace.sh $(TOFU_DIR); \
	fi

.PHONY: workspace-inspect
workspace-inspect: check-tofu-dir ## Show detailed info about current workspace
	@echo "Workspace Details for $(TOFU_DIR):"
	@echo ""
	@cd $(TOFU_DIR) && echo "  Current Workspace: $$(tofu workspace show)"
	@cd $(TOFU_DIR) && echo "  Module: $(TOFU_DIR)" | sed 's|tofu/||'
	@cd $(TOFU_DIR) && echo "  Resources: $$(tofu state list 2>/dev/null | wc -l)"
	@echo ""
	@echo "  Resources in workspace:"
	@cd $(TOFU_DIR) && tofu state list 2>/dev/null | head -20 | sed 's/^/    /' || echo "    (empty or error)"
	@echo ""

# ============================================================================
# INFRASTRUCTURE (TOFU)
# ============================================================================

.PHONY: infra-init
infra-init: check-prereqs check-tofu-dir ## Initialize Tofu
	@echo "Initializing Tofu for $(PROVIDER)/$(ENV)/$(WORKSPACE)..."
	cd $(TOFU_DIR) && tofu init
	@if [ "$(WORKSPACE)" != "default" ]; then \
		echo "Selecting workspace '$(WORKSPACE)'..."; \
		cd $(TOFU_DIR) && tofu workspace select $(WORKSPACE) || (echo "Workspace '$(WORKSPACE)' not found. Create it with: make workspace-new WORKSPACE=$(WORKSPACE)" && exit 1); \
	fi

.PHONY: infra-plan
infra-plan: infra-init ## Plan infrastructure changes
	@echo "Planning infrastructure for workspace '$(WORKSPACE)'..."
	cd $(TOFU_DIR) && tofu plan -var-file=terraform.tfvars

.PHONY: infra-up
infra-up: infra-init ## Create infrastructure (generates Ansible inventory automatically)
	@echo "Creating $(PROVIDER) infrastructure for $(ENV)/$(WORKSPACE)..."
	cd $(TOFU_DIR) && tofu apply -var-file=terraform.tfvars -auto-approve
	@echo "Generating Ansible inventory..."
	@if cd $(CURDIR)/$(TOFU_DIR) && tofu output -raw airgap_inventory_json > /tmp/tofu-nodes-airgap-$(DISTRO)-$(ENV).json 2>/dev/null && [ -s /tmp/tofu-nodes-airgap-$(DISTRO)-$(ENV).json ]; then \
		cp /tmp/tofu-nodes-airgap-$(DISTRO)-$(ENV).json /tmp/tofu-nodes-$(DISTRO)-$(ENV).json; \
		echo "Using airgap inventory output"; \
	elif cd $(CURDIR)/$(TOFU_DIR) && tofu output -raw cluster_nodes_json > /tmp/tofu-nodes-cluster-$(DISTRO)-$(ENV).json 2>/dev/null && [ -s /tmp/tofu-nodes-cluster-$(DISTRO)-$(ENV).json ]; then \
		cp /tmp/tofu-nodes-cluster-$(DISTRO)-$(ENV).json /tmp/tofu-nodes-$(DISTRO)-$(ENV).json; \
		echo "Using cluster_nodes inventory output"; \
	else \
		echo "Error: No inventory JSON output found in Tofu module $(TOFU_DIR). Has 'make infra-up' been run?"; \
		exit 1; \
	fi
	@python3 scripts/generate_inventory.py \
		--input /tmp/tofu-nodes-$(DISTRO)-$(ENV).json \
		--distro $(DISTRO) \
		--env $(ENV) \
		--schema ansible/_inventory-schema.yaml \
		--output-dir $(ANSIBLE_DIR)/inventory
	@[ -f "$(INVENTORY)" ] && echo "" && echo "Infrastructure created. Inventory generated at $(INVENTORY)" || (echo "Error: Inventory generation failed" && exit 1)

.PHONY: infra-down
infra-down: check-tofu-dir ## Destroy infrastructure
	@echo "═══════════════════════════════════════════════════════════════"
	@echo "  Infrastructure Destroy - $(PROVIDER)/$(ENV)/$(WORKSPACE)"
	@echo "═══════════════════════════════════════════════════════════════"
	@echo ""
	@if [ "$(WORKSPACE)" != "default" ]; then \
		echo "Selecting workspace '$(WORKSPACE)'..."; \
		cd $(TOFU_DIR) && tofu workspace select $(WORKSPACE); \
	fi
	@echo "Target Configuration:"
	@echo "  Provider:  $(PROVIDER)"
	@echo "  ENV:      $(ENV)"
	@echo "  Module:   $(TOFU_DIR)"
	@echo "  Workspace: $(WORKSPACE)"
	@echo ""
	@echo "Resources to be destroyed:"
	@(cd $(TOFU_DIR); \
	resources=$$(tofu state list 2>/dev/null | wc -l); \
	if [ "$$resources" -eq 0 ]; then \
		echo "  No resources found (workspace is empty)"; \
		echo ""; \
		echo "Current workspace: $$(tofu workspace show)"; \
		echo ""; \
		read -p "Continue anyway? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1; \
	else \
		tofu state list 2>/dev/null | head -10 | sed 's/^/  /'; \
		if [ $$resources -gt 10 ]; then \
			echo "  ... and $$((resources - 10)) more"; \
		fi; \
		echo ""; \
		echo "Total: $$resources resource(s)"; \
		echo ""; \
		read -p "Destroy all $(PROVIDER)/$(ENV)/$(WORKSPACE) infrastructure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1; \
	fi)
	@echo ""
	@echo "Destroying..."
	cd $(TOFU_DIR) && tofu destroy -var-file=terraform.tfvars -auto-approve
	@echo ""
	@echo "✓ Destroy complete"

.PHONY: infra-output
infra-output: ## Show Tofu outputs
	@if [ "$(WORKSPACE)" != "default" ]; then \
		cd $(TOFU_DIR) && tofu workspace select $(WORKSPACE); \
	fi
	cd $(TOFU_DIR) && tofu output

.PHONY: infra-ls
infra-ls: ## List all modules with active Tofu state across all providers/envs/distros
	@echo "Scanning for active infrastructure..."
	@echo ""
	@found=0; \
	while IFS= read -r state_file; do \
		resources=$$(python3 -c "import json; \
			d=json.load(open('$$state_file')); \
			print(len([r for r in d.get('resources',[]) if r.get('mode')=='managed']))" 2>/dev/null || echo 0); \
		if [ "$$resources" -gt 0 ]; then \
			if echo "$$state_file" | grep -q 'terraform.tfstate.d'; then \
				ws=$$(echo "$$state_file" | sed 's|.*/terraform.tfstate.d/\([^/]*\)/.*|\1|'); \
				module=$$(echo "$$state_file" | sed 's|/terraform.tfstate.d/.*||'); \
			else \
				ws="default"; \
				module=$$(dirname "$$state_file"); \
			fi; \
			printf "  ACTIVE  %-50s  [%s]  (%s resources)\n" "$$module" "$$ws" "$$resources"; \
			found=1; \
		fi; \
	done < <(find tofu -name "terraform.tfstate" 2>/dev/null | sort); \
	echo ""; \
	if [ "$$found" -eq 0 ]; then \
		echo "  No active infrastructure found."; \
	else \
		echo "Run 'make infra-scan' for detailed view, 'make infra-nuke' to destroy all."; \
	fi

.PHONY: infra-scan
infra-scan: ## Detailed scan of all infrastructure across modules/workspaces
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║  Infrastructure Scanner - All Modules & Workspaces             ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@found=0; \
	while IFS= read -r state_file; do \
		resources=$$(python3 -c "import json; \
			d=json.load(open('$$state_file')); \
			print(len([r for r in d.get('resources',[]) if r.get('mode')=='managed']))" 2>/dev/null || echo 0); \
		if [ "$$resources" -gt 0 ]; then \
			if echo "$$state_file" | grep -q 'terraform.tfstate.d'; then \
				ws=$$(echo "$$state_file" | sed 's|.*/terraform.tfstate.d/\([^/]*\)/.*|\1|'); \
				module=$$(echo "$$state_file" | sed 's|/terraform.tfstate.d/.*||'); \
			else \
				ws="default"; \
				module=$$(dirname "$$state_file"); \
			fi; \
			module_display=$$(echo "$$module" | sed 's|^tofu/||'); \
			printf "📍 %s [%s]\n" "$$module_display" "$$ws"; \
			printf "   Resources: %s\n" "$$resources"; \
			printf "   State: %s\n" "$$state_file"; \
			cd "$$module" && tofu workspace select "$$ws" >/dev/null 2>&1 && \
				tofu state list 2>/dev/null | head -5 | sed 's/^/     /'; \
			echo ""; \
			found=1; \
		fi; \
	done < <(find tofu -name "terraform.tfstate" 2>/dev/null | sort); \
	if [ "$$found" -eq 0 ]; then \
		echo "  No active infrastructure found."; \
	fi

.PHONY: infra-nuke
infra-nuke: ## Destroy ALL active infrastructure across all modules (end-of-day cleanup)
	@echo "WARNING: This will destroy ALL active Tofu-managed infrastructure."
	@echo ""
	@$(MAKE) --no-print-directory infra-ls
	@echo ""
	@read -p "Destroy all listed infrastructure? [y/N] " confirm && [ "$$confirm" = "y" ] || { echo "Aborted."; exit 1; }
	@echo ""
	@errors=0; \
	while IFS= read -r state_file; do \
		resources=$$(python3 -c "import json; \
			d=json.load(open('$$state_file')); \
			print(len([r for r in d.get('resources',[]) if r.get('mode')=='managed']))" 2>/dev/null || echo 0); \
		if [ "$$resources" -gt 0 ]; then \
			if echo "$$state_file" | grep -q 'terraform.tfstate.d'; then \
				ws=$$(echo "$$state_file" | sed 's|.*/terraform.tfstate.d/\([^/]*\)/.*|\1|'); \
				module=$$(echo "$$state_file" | sed 's|/terraform.tfstate.d/.*||'); \
			else \
				ws="default"; \
				module=$$(dirname "$$state_file"); \
			fi; \
			if [ ! -f "$$module/terraform.tfvars" ]; then \
				echo "  SKIP  $$module [$$ws] — terraform.tfvars not found, destroy manually"; \
				continue; \
			fi; \
			echo "Destroying $$module [$$ws]..."; \
			if [ "$$ws" = "default" ]; then \
				(cd "$$module" && tofu destroy -var-file=terraform.tfvars -auto-approve) || errors=$$((errors+1)); \
			else \
				(cd "$$module" && tofu workspace select "$$ws" 2>/dev/null && tofu destroy -var-file=terraform.tfvars -auto-approve) || errors=$$((errors+1)); \
			fi; \
		fi; \
	done < <(find tofu -name "terraform.tfstate" 2>/dev/null | sort); \
	echo ""; \
	if [ "$$errors" -gt 0 ]; then \
		echo "WARNING: $$errors module(s) failed to destroy. Check output above."; \
		exit 1; \
	else \
		echo "All infrastructure destroyed."; \
	fi

# ============================================================================
# CLUSTER DEPLOYMENT (ANSIBLE)
# ============================================================================

.PHONY: bootstrap-python
bootstrap-python: check-inventory ## Bootstrap Python 3.9+ on target nodes
	@echo "Bootstrapping Python on target nodes..."
	@export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg; \
	ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/bootstrap-python.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: cluster
cluster: check-inventory bootstrap-python ## Install Kubernetes cluster
	@echo "Installing $(DISTRO) cluster ($(ENV) environment)..."
	@export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg; \
	ansible-playbook -i $(INVENTORY) $(CLUSTER_PLAYBOOK) -v $(ANSIBLE_EXTRA_VARS)

.PHONY: agents
agents: check-inventory ## Setup additional agent nodes
	@echo "Setting up agent nodes..."
	@export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg; \
	ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/setup/setup-agent-nodes.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: rancher
rancher: check-inventory ## Deploy Rancher to cluster
	@echo "Deploying Rancher..."
	@export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg KUBECONFIG_FILE=$(KUBECONFIG_FILE); \
	ansible-playbook -i $(INVENTORY) $(RANCHER_PLAYBOOK) -v $(ANSIBLE_EXTRA_VARS)

.PHONY: registry
registry: check-inventory ## Configure private registry on cluster nodes
	@echo "Configuring private registry..."
	@export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg; \
	ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy/rke2-registry-config-playbook.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: upgrade-cluster
upgrade: check-inventory ## Upgrade Kubernetes cluster
	@echo "Upgrading $(DISTRO) cluster..."
	@export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg; \
	ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/deploy/$(DISTRO)-upgrade-playbook.yml -v $(ANSIBLE_EXTRA_VARS)

.PHONY: kubectl-setup
kubectl-setup: check-inventory ## Setup kubectl access on bastion
	@echo "Setting up kubectl access..."
	@export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg; \
	ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/setup/setup-kubectl-access.yml -v $(ANSIBLE_EXTRA_VARS)

# ============================================================================
# UTILITIES
# ============================================================================

.PHONY: test-ssh
test-ssh: check-inventory ## Test SSH connectivity to all nodes
	@echo "Testing SSH connectivity..."
	@export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg; \
	ansible-playbook -i $(INVENTORY) $(ANSIBLE_DIR)/playbooks/debug/test-ssh-connectivity.yml -v

.PHONY: status
status: check-inventory ## Show cluster status
	@echo "Cluster Status ($(DISTRO)/$(ENV)):"
	@echo ""
	@if [ "$(ENV)" = "airgap" ]; then \
		echo "=== Nodes ==="; \
		export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg; \
		ansible -i $(INVENTORY) bastion -m shell -a "kubectl get nodes -o wide" 2>/dev/null || echo "Could not get cluster status"; \
		echo ""; \
		echo "=== Rancher Pods ==="; \
		ansible -i $(INVENTORY) bastion -m shell -a "kubectl get pods -n cattle-system 2>/dev/null || echo 'Rancher not deployed'" 2>/dev/null || true; \
	elif [ -f "$(KUBECONFIG_FILE)" ]; then \
		echo "=== Nodes ==="; \
		kubectl --kubeconfig $(KUBECONFIG_FILE) get nodes -o wide || echo "Could not get cluster status"; \
		echo ""; \
		echo "=== Rancher Pods ==="; \
		kubectl --kubeconfig $(KUBECONFIG_FILE) get pods -n cattle-system 2>/dev/null || echo "Rancher not deployed"; \
	else \
		echo "No kubeconfig found at $(KUBECONFIG_FILE)"; \
		echo "Run 'make cluster' first to deploy the cluster."; \
	fi

.PHONY: ssh-bastion
ssh-bastion: check-inventory ## SSH to bastion host
	@export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg; \
	BASTION=$$(ansible-inventory -i $(INVENTORY) --host bastion-node 2>/dev/null | grep '"bastion_host"' | cut -d'"' -f4); \
	KEY=$$(ansible-inventory -i $(INVENTORY) --host bastion-node 2>/dev/null | grep '"ssh_private_key_file"' | cut -d'"' -f4); \
	USER=$$(ansible-inventory -i $(INVENTORY) --host bastion-node 2>/dev/null | grep '"bastion_user"' | cut -d'"' -f4); \
	KEY=$$(eval echo $$KEY); \
	echo "Connecting to bastion: $$USER@$$BASTION"; \
	ssh -i $$KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=none $$USER@$$BASTION

.PHONY: ping
ping: check-inventory ## Ping all hosts
	@export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg; \
	ansible -i $(INVENTORY) all -m ping

.PHONY: inventory-graph
inventory-graph: check-inventory ## Show inventory structure
	@export ANSIBLE_CONFIG=$(ANSIBLE_DIR)/ansible.cfg; \
	ansible-inventory -i $(INVENTORY) --graph

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
all: infra-up cluster $(REGISTRY_TARGET) rancher ## Full setup: infrastructure + cluster + Rancher
	@echo ""
	@echo "Full $(DISTRO) $(ENV) environment setup complete!"
	@echo ""
	@$(MAKE) status DISTRO=$(DISTRO) ENV=$(ENV) PROVIDER=$(PROVIDER)

.PHONY: setup-from-infra
setup-from-infra: check-inventory cluster $(REGISTRY_TARGET) rancher ## Setup cluster + Rancher (infra exists)
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
	@echo "  TOFU_DIR         = $(TOFU_DIR)"
	@echo "  ANSIBLE_DIR      = $(ANSIBLE_DIR)"
	@echo "  INVENTORY        = $(INVENTORY)"
	@echo "  CLUSTER_PLAYBOOK = $(CLUSTER_PLAYBOOK)"
	@echo "  RANCHER_PLAYBOOK = $(RANCHER_PLAYBOOK)"
	@echo "  KUBECONFIG_FILE  = $(KUBECONFIG_FILE)"
	@echo "  GROUP_VARS       = $(GROUP_VARS)"
	@echo ""
	@echo "Directory Status:"
	@echo "  Tofu dir exists:       $$([ -d "$(TOFU_DIR)" ] && echo "yes" || echo "no")"
	@echo "  Ansible dir exists:    $$([ -d "$(ANSIBLE_DIR)" ] && echo "yes" || echo "no")"
	@echo "  Inventory exists:      $$([ -f "$(INVENTORY)" ] && echo "yes" || echo "no")"
	@echo "  Cluster playbook exists: $$([ -f "$(CLUSTER_PLAYBOOK)" ] && echo "yes" || echo "no")"
	@echo "  Rancher playbook exists: $$([ -f "$(RANCHER_PLAYBOOK)" ] && echo "yes" || echo "no")"

# Extra vars support
ifdef EXTRA_VARS
ANSIBLE_EXTRA_VARS := --extra-vars "$(EXTRA_VARS)"
else
ANSIBLE_EXTRA_VARS :=
endif

# ============================================================================
# SUPPLY CHAIN VERIFICATION
# ============================================================================

.PHONY: verify
verify: ## Verify supply chain integrity (checksums, pins, lock files)
	@echo "Verifying supply chain integrity..."
	@echo ""
	@echo "Checking requirements.txt version pins..."
	@grep -q '==' requirements.txt && echo "  OK: requirements.txt has pinned versions" || (echo "  FAIL: requirements.txt missing pinned versions" && exit 1)
	@echo "Checking requirements.yml version pins..."
	@grep -q 'version:' requirements.yml && echo "  OK: requirements.yml has pinned versions" || (echo "  FAIL: requirements.yml missing pinned versions" && exit 1)
	@echo "Checking .terraform.lock.hcl files..."
	@found=0; \
	while IFS= read -r lockfile; do \
		printf "  Found: %s\n" "$$lockfile"; \
		found=1; \
	done < <(find tofu -name '.terraform.lock.hcl' 2>/dev/null | sort); \
	if [ "$$found" -eq 0 ]; then \
		echo "  WARNING: No .terraform.lock.hcl files found. Run 'tofu init' in each module."; \
	fi
	@echo ""
	@echo "Checking download_verify role exists..."
	@test -f ansible/roles/download_verify/tasks/main.yml && echo "  OK: download_verify role present" || (echo "  FAIL: download_verify role missing" && exit 1)
	@echo ""
	@echo "All supply chain checks passed."
