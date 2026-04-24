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

# Get list of workspaces (excluding current with *)
WORKSPACES=$(tofu workspace list | grep -v "^\*" | awk '{print $1}')

if [ -z "$WORKSPACES" ]; then
  echo "No workspaces found besides default."
  echo "Current: $(tofu workspace show)"
  echo ""
  read -p "Create a new workspace? (y/N): " create
  if [[ "$create" =~ ^[Yy]$ ]]; then
    read -p "Enter new workspace name: " new_ws
    if [ -n "$new_ws" ]; then
      tofu workspace new "$new_ws"
    fi
  fi
  exit 0
fi

echo "Available workspaces:"
echo ""

# Display current workspace
CURRENT=$(tofu workspace show)
echo "  * $CURRENT (current)"
echo ""

# Display numbered list
i=1
for ws in $WORKSPACES; do
  echo "    $i. $ws"
  i=$((i+1))
done

echo "    0. cancel"
echo ""

read -p "Select workspace (number or name): " selection

# Check if user entered a number
if [[ "$selection" =~ ^[0-9]+$ ]]; then
  if [ "$selection" = "0" ]; then
    echo "Cancelled."
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
tofu workspace select "$workspace"
echo ""
echo "Current workspace: $(tofu workspace show)"
