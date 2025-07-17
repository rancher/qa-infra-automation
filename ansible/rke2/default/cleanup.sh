#!/bin/bash
set -e

. vars.env

# destroy nodes
tofu -chdir="$TERRAFORM_NODE_SOURCE" destroy -auto-approve -var-file="$TFVARS_FILE"
