#!/bin/bash
set -e

. vars.env

# destroy empty cluster
tofu -chdir="$TERRAFORM_CLUSTER_SOURCE" destroy -auto-approve -var-file="$TFVARS_FILE" &

# destroy nodes
tofu -chdir="$TERRAFORM_NODE_SOURCE" destroy -auto-approve -var-file="$TFVARS_FILE" &
wait
