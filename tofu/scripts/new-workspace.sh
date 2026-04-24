#!/usr/bin/bash
# Interactive workspace creation
# Usage: new-workspace.sh [tofu-module-dir]

set -euo pipefail

# Set PATH for basic commands
export PATH="/usr/bin:/bin:/usr/local/bin"

TOFU_DIR="${1:-.}"

if [ ! -d "$TOFU_DIR" ]; then
  echo "Error: Directory not found: $TOFU_DIR"
  exit 1
fi

cd "$TOFU_DIR"

# Get current workspace
CURRENT_WS=$(tofu workspace show)

# Get module context from directory path
MODULE_CONTEXT=$(echo "$TOFU_DIR" | sed 's|.*/tofu/||')

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  OpenTofu Workspace Creator                                   ║"
echo "║  Module: $MODULE_CONTEXT"
echo "║  Current: $CURRENT_WS"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Suggest workspace name based on common patterns
echo "Workspace naming suggestions:"
echo "  - Environment names: dev, staging, prod, test"
echo "  - Feature names: feature-x, bugfix-123, experiment-1"
echo "  - User names: username-workspace, personal-test"
echo "  - Date-based: 2026-04-24-test, sprint-5"
echo ""

read -p "Enter new workspace name (or 'cancel' to abort): " new_ws

if [ "$new_ws" = "cancel" ] || [ -z "$new_ws" ]; then
  echo "Cancelled. No workspace created."
  exit 0
fi

# Validate workspace name
if [ "$new_ws" = "default" ]; then
  echo "Error: 'default' is a reserved workspace name."
  echo "OpenTofu creates it automatically. Please select a different name."
  exit 1
fi

# Check if workspace already exists
if tofu workspace list | awk '{print $NF}' | grep -q "^$new_ws$"; then
  echo "Error: Workspace '$new_ws' already exists."
  echo "Choose a different name or select it with:"
  echo "  make workspace-select WORKSPACE=$new_ws"
  exit 1
fi

# Validate name format (basic checks)
if [[ ! "$new_ws" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: Workspace name contains invalid characters."
  echo "Use only: letters, numbers, hyphens, and underscores."
  exit 1
fi

echo ""
echo "Creating workspace: $new_ws"
echo "Module: $MODULE_CONTEXT"

if tofu workspace new "$new_ws" 2>&1; then
  echo ""
  echo "✓ Workspace '$new_ws' created successfully!"
  echo ""
  echo "Next steps:"
  echo "  1. Deploy infrastructure to this workspace:"
  echo "     make infra-up WORKSPACE=$new_ws"
  echo ""
  echo "  2. Or switch to it as your active workspace:"
  echo "     make workspace-select WORKSPACE=$new_ws"
  echo "     make infra-up"
  echo ""
  echo "Current workspace is still: $CURRENT_WS"
  echo "Run 'make workspace-show' to verify."
else
  echo "Error: Failed to create workspace."
  exit 1
fi
