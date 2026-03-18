# Airgap Deploy Playbooks

Playbooks for deploying Rancher and related components onto an airgap RKE2 cluster via a bastion host.

## rancher-helm-deploy-playbook.yml

Deploys Rancher onto an airgap RKE2 cluster using Helm, then configures the admin account and generates a persistent API token.

### Prerequisites

- Bastion host with kubectl configured (`~/.kube/config`)
- Bastion host reachable from Ansible inventory
- `python3-pip`, `python3-kubernetes`, and `python3-yaml` installable on the bastion (or already present)
- `airgap_rancher_helm_deploy` role variables set (see that role's README)

### Usage

```bash
ansible-playbook \
  -i inventory/inventory.yml \
  ansible/rke2/airgap/playbooks/deploy/rancher-helm-deploy-playbook.yml
```

### Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `rancher_hostname` or `internal_lb_hostname` | Yes | Internal hostname for the Rancher UI |
| `public_hostname` or `external_lb_hostname` | No | External hostname; used to patch the Ingress if set |
| `rancher_namespace` | Yes | Namespace Rancher is deployed into (e.g. `cattle-system`) |
| `rancher_bootstrap_password` | Yes | Bootstrap password set during Helm install |
| `rancher_admin_password` | Yes | Permanent admin password to set after first login |
| `rancher_tls_source` | No | TLS source label written to the summary file |

Variables required by the `airgap_rancher_helm_deploy` role are documented in that role's README.

### Outputs

On completion:

- `~/rancher-admin-token.json` on the bastion — JSON file containing the Rancher URL, persistent API token, and metadata
- `~/rancher-deployment-summary.txt` on the bastion — human-readable summary with credentials and access instructions
- Admin password set to `rancher_admin_password`
- Rancher server URL configured
- Temporary login token cleaned up automatically

### Admin Setup

Admin account configuration is handled by the `rancher_auth` role, which:

1. Authenticates using `rancher_bootstrap_password`
2. Sets the permanent password to `rancher_admin_password`
3. Creates a persistent (non-expiring) API token
4. Cleans up the temporary login token

## Related

- [`airgap_rancher_helm_deploy` role](../../../../roles/airgap_rancher_helm_deploy/) — Helm deployment role
- [`rancher_auth` role](../../../../roles/rancher_auth/) — Admin token generation
