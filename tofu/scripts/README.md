# Tofu Scripts

This directory contains centralized utility scripts for OpenTofu/Terraform operations across all modules.

## new-workspace.sh

Interactive workspace creation with validation and naming suggestions.

### Usage

```bash
# From any tofu module directory
../../scripts/new-workspace.sh [path]

# Or using make (recommended)
make workspace-new              # Interactive creation
make workspace-new WORKSPACE=name  # Direct creation
```

### Features

- Interactive prompt with workspace naming suggestions
- Validates workspace name format (alphanumeric, hyphens, underscores)
- Prevents creation of 'default' (reserved by OpenTofu)
- Checks for duplicate workspace names
- Shows next steps after creation

### Examples

```bash
# Run interactive creation
make workspace-new

# Output:
# ╔════════════════════════════════════════════════════════════════╗
# ║  OpenTofu Workspace Creator                                   ║
# ║  Module: aws/modules/cluster_nodes                            ║
# ║  Current: default                                              ║
# ╚════════════════════════════════════════════════════════════════╝
#
# Workspace naming suggestions:
#   - Environment names: dev, staging, prod, test
#   - Feature names: feature-x, bugfix-123, experiment-1
#   - User names: username-workspace, personal-test
#   - Date-based: 2026-04-24-test, sprint-5
#
# Enter new workspace name (or 'cancel' to abort): dev-environment
#
# Creating workspace: dev-environment
# Module: aws/modules/cluster_nodes
#
# ✓ Workspace 'dev-environment' created successfully!
#
# Next steps:
#   1. Deploy infrastructure to this workspace:
#      make infra-up WORKSPACE=dev-environment
#
#   2. Or switch to it as your active workspace:
#      make workspace-select WORKSPACE=dev-environment
#      make infra-up
```

## select-workspace.sh

Interactive workspace selection menu for tofu/terraform modules.

### Usage

```bash
# From any tofu module directory
../../scripts/select-workspace.sh [path]

# Or using make (recommended)
make workspace-select              # Interactive menu
make workspace-select WORKSPACE=name  # Direct selection
```

### Features

- Lists all workspaces with current workspace marked with `*`
- Interactive numbered menu for easy selection
- Option to create new workspaces if none exist
- Cancel operation with option 0
- Shows current workspace after selection

### Examples

```bash
# Run interactive menu
make workspace-select

# Output:
# Available workspaces:
#
#   * default (current)
#
#     1. dev-environment
#     2. testing
#     0. cancel
#
# Select workspace (number or name): 1
#
# Selecting workspace 'dev-environment'...
# Switched to workspace "dev-environment"
#
# Current workspace: dev-environment
```

## delete-workspace.sh

Interactive workspace deletion with resource counts and safety confirmations.

### Usage

```bash
# From any tofu module directory
../../scripts/delete-workspace.sh [path]

# Or using make (recommended)
make workspace-delete              # Interactive deletion
make workspace-delete WORKSPACE=name  # Direct deletion
```

### Features

- Lists all workspaces with resource counts
- Excludes current workspace from deletion (prevents accidents)
- Shows resource count before deletion
- Multi-stage confirmation:
  - Non-empty workspaces: requires typing 'DELETE'
  - Empty workspaces: simple 'y/N' confirmation
- Shows remaining workspaces after deletion

### Examples

```bash
# Run interactive deletion
make workspace-delete

# Output:
# ╔════════════════════════════════════════════════════════════════╗
# ║  OpenTofu Workspace Deleter                                   ║
# ║  Module: aws/modules/cluster_nodes                            ║
# ╚════════════════════════════════════════════════════════════════╝
#
# Available workspaces to delete:
#
#   Current: default (cannot delete)
#
#     1. dev-environment           12 res
#     2. old-test                   0 res
#     0. cancel
#
# Select workspace to delete (number or name): 1
#
# Workspace to delete: dev-environment
# Resources in workspace: 12
#
# ⚠️  WARNING: This workspace contains 12 resource(s).
#
# Type 'DELETE' to confirm destruction of 12 resources: DELETE
#
# Deleting workspace 'dev-environment'...
#
# ✓ Workspace 'dev-environment' deleted successfully.
#
# Remaining workspaces:
#   default
#   old-test
```

### Safety Features

- **Cannot delete current workspace**: Must switch first with `make workspace-select`
- **Resource counts**: Shows how many resources will be destroyed
- **Type-to-confirm**: Non-empty workspaces require typing 'DELETE'
- **Empty workspace protection**: Simple confirmation for empty workspaces

## init-backend.sh

Centralized backend configuration script that generates `backend.tf` from templates and initializes the working directory.

### Usage

```bash
# From any tofu module directory
../../scripts/init-backend.sh <backend-type> [options]

# Or using make (recommended)
make backend-s3 BUCKET=my-bucket KEY=my-key REGION=us-east-1
make backend-local
```

### S3 Backend

```bash
../../scripts/init-backend.sh s3 \
  --bucket my-terraform-state \
  --key rke2-default/terraform.tfstate \
  --region us-east-1 \
  --dynamodb-table my-lock-table \
  --encrypt true
```

Or using make:
```bash
make backend-s3 BUCKET=my-terraform-state \
  KEY=rke2-default/terraform.tfstate \
  REGION=us-east-1 \
  DYNAMODB_TABLE=my-lock-table
```

### Local Backend

```bash
../../scripts/init-backend.sh local --path terraform.tfstate
```

Or using make:
```bash
make backend-local PATH=terraform.tfstate
```

### How It Works

1. Reads template from `tofu/templates/backend-{type}.tf.tmpl`
2. Substitutes placeholders with provided values
3. Writes `backend.tf` in current directory
4. Runs `tofu init -reconfigure` to apply new backend

### Adding New Backend Types

1. Create template in `tofu/templates/backend-{type}.tf.tmpl`
2. Add case handler in `init-backend.sh` for the new type
3. Update this README with usage examples

## Available Backend Types

- **s3**: AWS S3 with optional DynamoDB locking
- **local**: Local file storage

## Requirements

- OpenTofu (`tofu`) or Terraform (`terraform`) in PATH
- Appropriate cloud credentials for backend type

## Quick Reference

### Common Workflows

**1. Setup Backend:**
```bash
make backend-s3 BUCKET=my-state KEY=terraform.tfstate REGION=us-east-1
```

**2. Work with Workspaces:**
```bash
make workspace-list           # See all workspaces
make workspace-select         # Interactive menu with resource counts
make workspace-inspect        # Detailed workspace information
```

**3. Manage Infrastructure:**
```bash
make infra-scan               # See ALL infrastructure across modules
make infra-up                 # Deploy infrastructure
make infra-down               # Destroy with detailed confirmation
```

**4. Discovery:**
```bash
# What infrastructure exists?
make infra-ls                 # Quick list
make infra-scan              # Detailed view with resources

# What's in my current workspace?
make workspace-inspect       # Workspace details
make workspace-show          # Just show workspace name
```

### Understanding Module Context

The makefile automatically maps ENV variables to tofu modules:
- `ENV=default` → `tofu/aws/modules/cluster_nodes`
- `ENV=airgap` → `tofu/aws/modules/airgap`

Always check which module you're operating on:
```bash
make workspace-inspect       # Shows module path
make infra-down               # Shows target before destroying
```
