#!/bin/bash
set -e

. vars.env

# deploy nodes
tofu -chdir="$TERRAFORM_NODE_SOURCE" init -var-file="$TFVARS_FILE"
tofu -chdir="$TERRAFORM_NODE_SOURCE" apply -auto-approve -var-file="$TFVARS_FILE"

# setup RKE2
envsubst < $RKE2_PLAYBOOK_PATH/inventory-template.yml > $RKE2_INVENTORY

ssh-add -k $PRIVATE_KEY_FILE

ansible-inventory -i "$RKE2_INVENTORY" --graph --vars
ansible-playbook -i "$RKE2_INVENTORY" "$RKE2_PLAYBOOK" -vvvv -e "@$VARS_FILE"