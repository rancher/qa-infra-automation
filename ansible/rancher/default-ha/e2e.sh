#!/bin/bash
set -e

. vars.env

if [ ! -f $KUBECONFIG_FILE ]; then
    . $RKE2_PLAYBOOK_PATH/e2e.sh
fi

# setup rancher
ansible-playbook "$RANCHER_PLAYBOOK" -vvvv -e "@$VARS_FILE"

# deploy downstream cluster to rancher
tofu -chdir="tofu/rancher/cluster" apply -auto-approve -var-file="vars.tfvars" -var-file="$REPO_ROOT/ansible/rancher/generated.tfvars"
