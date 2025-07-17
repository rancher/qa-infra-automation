#!/bin/bash
set -e

. vars.env

tofu -chdir="$TERRAFORM_NODE_SOURCE" init -var-file="$TFVARS_FILE" &
tofu -chdir="$TERRAFORM_CLUSTER_SOURCE" init -var-file="$TFVARS_FILE" &
wait

# deploy nodes
tofu -chdir="$TERRAFORM_NODE_SOURCE" apply -auto-approve -var-file="$TFVARS_FILE" &
# deploy empty cluster
tofu -chdir="$TERRAFORM_CLUSTER_SOURCE" apply -auto-approve -var-file="$TFVARS_FILE" &
wait

# setup for ansible
envsubst < $PLAYBOOK_PATH/inventory-template.yml > $PLAYBOOK_INVENTORY
ssh-add -k $PRIVATE_KEY_FILE

ansible-inventory -i "$PLAYBOOK_INVENTORY" --graph --vars
ansible-playbook -i "$PLAYBOOK_INVENTORY" "$PLAYBOOK" -vvvv
