# Rancher Token Generation

This directory contains playbooks for generating Rancher API tokens.

## Playbooks

### generate-admin-token.yml

Generates a Rancher admin API token for automation and CI/CD pipelines.

**Quick Start:**
```bash
# Using environment variables
RANCHER_URL=https://rancher.example.com \
RANCHER_ADMIN_PASSWORD=mypassword \
  ansible-playbook ansible/rancher/token/generate-admin-token.yml

# Using inventory
ansible-playbook -i inventory.yml ansible/rancher/token/generate-admin-token.yml

# Using extra vars
ansible-playbook ansible/rancher/token/generate-admin-token.yml \
  -e rancher_url=https://rancher.example.com \
  -e rancher_token_password=mypassword
```

**See also:** [ansible/roles/rancher_token/README.md](../../roles/rancher_token/README.md) for complete documentation of all options.
