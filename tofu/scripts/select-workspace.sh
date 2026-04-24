#!/usr/bin/bash
# Interactive workspace selector
# Usage: select-workspace.sh [tofu-module-dir]

set -euo pipefail

# Set PATH for basic commands
export PATH="/usr/bin:/bin:/usr/local/bin"

TOFU_DIR="${1:-.}"

if [ ! -d "$TOFU_DIR" ]; then
  echo "Error: Directory not found: $TOFU_DIR"
  exit 1
fi

cd "$TOFU_DIR"

# Get current workspace before we switch
CURRENT_WS=$(tofu workspace show)

# Get list of workspaces (excluding current with *)
WORKSPACES=$(tofu workspace list | grep -v "^\*" | awk '{print $1}')

# Get module context from directory path
MODULE_CONTEXT=$(echo "$TOFU_DIR" | sed 's|.*/tofu/||')

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  OpenTofu Workspace Selector                                  ║"
echo "║  Module: $MODULE_CONTEXT"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ -z "$WORKSPACES" ]; then
  echo "No workspaces found besides default."
  echo "Current: $CURRENT_WS"
  echo ""
  read -p "Create a new workspace? (y/N): " create
  if [[ "$create" =~ ^[Yy]$ ]]; then
    read -p "Enter new workspace name: " new_ws
    if [ -n "$new_ws" ]; then
      tofu workspace new "$new_ws"
      echo ""
      echo "Switched to new workspace: $new_ws"
    fi
  fi
  exit 0
fi

echo "Available workspaces:"
echo ""

# Display current workspace with resource count
CURRENT_COUNT=$(tofu state list 2>/dev/null | wc -l || echo "0")
printf "  * %-40s [%s resource(s)]\n" "$CURRENT_WS" "$CURRENT_COUNT"
echo ""

# Display numbered list with resource counts
i=1
for ws in $WORKSPACES; do
  # Temporarily switch to count resources
  if tofu workspace select "$ws" >/dev/null 2>&1; then
    count=$(tofu state list 2>/dev/null | wc -l || echo "0")
    printf "    %d. %-40s [%s resource(s)]\n" "$i" "$ws" "$count"
  else
    printf "    %d. %-40s [error reading state]\n" "$i" "$ws"
  fi
  i=$((i+1))
done

echo "    0. cancel"
echo ""

# Switch back to current workspace
tofu workspace select "$CURRENT_WS" >/dev/null 2>&1 || true

read -p "Select workspace (number or name): " selection

# Check if user entered a number
if [[ "$selection" =~ ^[0-9]+$ ]]; then
  if [ "$selection" = "0" ]; then
    echo "Cancelled. Current workspace: $CURRENT_WS"
    exit 0
  fi

  # Get the workspace at that index
  workspace=$(echo "$WORKSPACES" | sed -n "${selection}p")
  if [ -z "$workspace" ]; then
    echo "Error: Invalid selection."
    exit 1
  fi
else
  # User entered a name directly
  workspace="$selection"
fi

echo ""
echo "Selecting workspace '$workspace'..."

# Save current directory to return after tofu commands
ORIG_DIR=$(pwd)

if tofu workspace select "$workspace" 2>&1; then
  echo ""
  echo "✓ Switched to workspace: $workspace"

  # Show what's in this workspace
  resource_count=$(tofu state list 2>/dev/null | wc -l || echo "0")
  if [ "$resource_count" -gt 0 ]; then
    echo "  Resources in workspace: $resource_count"
    echo ""
    echo "Sample resources:"
    tofu state list 2>/dev/null | head -5 | sed 's/^/  /'
    if [ "$resource_count" -gt 5 ]; then
      echo "  ... and $((resource_count - 5)) more"
    fi
  else
    echo "  No resources found (empty workspace)"
  fi

  # Show next steps
  echo ""
  echo "Next steps for this workspace:"
  echo "  make infra-up     # Deploy infrastructure"
  echo "  make infra-down   # Destroy infrastructure"
  echo "  make infra-plan   # View changes"
else
  echo "Error: Failed to select workspace."
  exit 1
fi
