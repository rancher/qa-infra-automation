#!/usr/bin/bash
# Interactive workspace deletion
# Usage: delete-workspace.sh [tofu-module-dir]

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

# Get list of workspaces (excluding current)
WORKSPACES=$(tofu workspace list | grep -v "^\*" | grep -v "^$CURRENT_WS$" | awk '{print $NF}')

# Get module context from directory path
MODULE_CONTEXT=$(echo "$TOFU_DIR" | sed 's|.*/tofu/||')

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  OpenTofu Workspace Deleter                                   ║"
echo "║  Module: $MODULE_CONTEXT"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ -z "$WORKSPACES" ]; then
  echo "No workspaces found to delete (only default exists)."
  echo "Current workspace: $CURRENT_WS"
  exit 0
fi

echo "Available workspaces to delete:"
echo ""
echo "  Current: $CURRENT_WS (cannot delete)"
echo ""

# Display numbered list with resource counts
i=1
declare -a workspace_array
for ws in $WORKSPACES; do
  # Temporarily switch to count resources
  if tofu workspace select "$ws" >/dev/null 2>&1; then
    count=$(tofu state list 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    # Compact format
    short_name="${ws:0:22}"
    [ ${#ws} -gt 22 ] && short_name="${short_name}.."
    printf "    %d. %-24s %3s res\n" "$i" "$short_name" "$count"
  else
    printf "    %d. %-24s error\n" "$i" "$ws"
  fi
  workspace_array[$i]="$ws"
  i=$((i+1))
done

echo "    0. cancel"
echo ""

read -p "Select workspace to delete (number or name): " selection

# Check if user entered a number
if [[ "$selection" =~ ^[0-9]+$ ]]; then
  if [ "$selection" = "0" ]; then
    echo "Cancelled."
    exit 0
  fi

  # Get the workspace at that index (1-based)
  workspace="${workspace_array[$selection]}"
  if [ -z "$workspace" ]; then
    echo "Error: Invalid selection."
    exit 1
  fi
else
  # User entered a name directly
  workspace="$selection"
fi

# Validate workspace exists
if ! tofu workspace list | awk '{print $NF}' | grep -q "^$workspace$"; then
  echo "Error: Workspace '$workspace' not found."
  exit 1
fi

# Check if trying to delete current workspace
if [ "$workspace" = "$CURRENT_WS" ]; then
  echo "Error: Cannot delete current workspace '$CURRENT_WS'."
  echo "Switch to another workspace first:"
  echo "  make workspace-select"
  exit 1
fi

# Get resource count before deletion
tofu workspace select "$workspace" >/dev/null 2>&1
resource_count=$(tofu state list 2>/dev/null | wc -l | tr -d ' ' || echo "0")

# Switch back to current workspace
tofu workspace select "$CURRENT_WS" >/dev/null 2>&1

echo ""
echo "Workspace to delete: $workspace"
echo "Resources in workspace: $resource_count"

if [ "$resource_count" -gt 0 ]; then
  echo ""
  echo "⚠️  WARNING: This workspace contains $resource_count resource(s)."
  echo ""
  read -p "Type 'DELETE' to confirm destruction of $resource_count resources: " confirm
  if [ "$confirm" != "DELETE" ]; then
    echo "Cancelled. Workspace not deleted."
    exit 0
  fi
else
  echo ""
  read -p "Delete empty workspace '$workspace'? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Cancelled. Workspace not deleted."
    exit 0
  fi
fi

echo ""
echo "Deleting workspace '$workspace'..."

if tofu workspace delete "$workspace" 2>&1; then
  echo ""
  echo "✓ Workspace '$workspace' deleted successfully."
  echo ""
  echo "Remaining workspaces:"
  tofu workspace list
else
  echo "Error: Failed to delete workspace."
  exit 1
fi
