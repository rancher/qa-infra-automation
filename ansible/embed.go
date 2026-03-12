package ansible

import "embed"

// Files contains all Ansible playbooks, roles, inventories, and configuration.
// Use [github.com/rancher/qa-infra-automation/fsutil.WriteToDisk] to extract
// these files to a temporary directory before running ansible-playbook.
//
//go:embed all:chaos all:k3s all:rancher all:rke2 all:roles ansible.cfg vars.yaml
var Files embed.FS
