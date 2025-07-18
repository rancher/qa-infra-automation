#!/bin/bash


# Parse NODE_ROLE into an array (comma-separated)
IFS=',' read -r -a ROLES <<< "$NODE_ROLE"

# Check for specific roles
for role in "${ROLES[@]}"; do
if [[ "$role" == "cp" ]]; then
    role="controlplane"
fi
  TOKEN="$TOKEN --$role"
done

TOKEN="$TOKEN --address $NODE_IP --node-name $NODE_NAME"

eval "$TOKEN"