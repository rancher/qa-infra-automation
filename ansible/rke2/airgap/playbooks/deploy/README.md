# Airgap Deploy Playbooks

**Recommended:** Use `make rancher` from the repository root for the full airgap workflow (infra + deploy). See the root [Makefile](../../../../..) for available targets.

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
| `rancher_system_default_registry` | No (airgap: yes) | Private registry passed as the chart's top-level `systemDefaultRegistry`; the chart pulls the server image from `<registry>/<rancher_image_repository>:<tag>` and rewrites system images (e.g. `shell-image`) at install time. See [role README](../../../../roles/airgap_rancher_helm_deploy/README.md). |

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

## add-downstream-cluster.yml

Registers an existing (already-installed) airgap RKE2/K3s cluster into Rancher as an
imported **downstream** cluster, then waits for the `cattle-cluster-agent` to connect and
the cluster to reach `active`.

### How it works

The imported cluster is created via the **Rancher v3 API** (not the `rancher2`
Terraform/OpenTofu provider):

1. Log in to Rancher → bearer token.
2. `GET /v3/clusters?name=<name>` — look up the cluster by name (idempotency: it is only
   created if absent, so re-runs do not duplicate it).
3. `POST /v3/clusters` — create the imported cluster (returns the id immediately).
4. `GET /v3/clusterregistrationtokens?clusterId=<id>` — fetch the registration token
   (Rancher generates it at create time; available immediately, even while the cluster is
   still `pending`).
5. (Second play, on the bastion) copy the target cluster's kubeconfig, download the import
   manifest, apply it to the target cluster, then wait for `cattle-cluster-agent` to become
   `Available` and the cluster to become `active`.

> **Why not the `rancher2` provider?** Its `rancher2_cluster` resource waits for the cluster
> to reach `active`/`provisioning` on Create. An imported cluster stays `pending` until the
> agent connects — and the agent is only deployed in step 5, *after* the create step returns.
> That ordering deadlocks the provider's create-waiter (it retried every 10s for its 30m
> default timeout). The API path returns immediately, so the manifest can be applied.

### Prerequisites

- Rancher already deployed and reachable (`rancher_hostname` / `external_lb_hostname`)
- RKE2/K3s already installed on the target cluster and reachable from the bastion
- Bastion host with SSH access to the target nodes

### Usage

```bash
# Makefile shortcut (recommended):
make downstream ENV=airgap TARGET_GROUP=downstream

# Raw Ansible equivalent (run from ansible/rke2/airgap):
ansible-playbook -i inventory/inventory.yml playbooks/deploy/add-downstream-cluster.yml \
  --extra-vars="target=downstream"
```

### Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `target` (or `TARGET_GROUP`) | Yes | Inventory group of the cluster to register (e.g. `downstream`) |
| `rancher_hostname` or `external_lb_hostname` | Yes | Rancher FQDN used for the API and manifest URL |
| `rancher_bootstrap_password` | Yes | Admin password used to log in to Rancher |
| `cluster_name` / `DOWNSTREAM_CLUSTER_NAME` | No | Fully custom cluster name; if unset a random `<prefix>-<suffix>` is generated |
| `downstream_cluster_name_prefix` / `DOWNSTREAM_CLUSTER_NAME_PREFIX` | No | Prefix for the generated name (default `ansible-created`) |
| `downstream_private_registry_url` | No | Private registry written to the imported cluster's `importedConfig.privateRegistryUrl` (default empty) |

The import manifest's agent image is derived from Rancher's `system-default-registry`
setting (set at Rancher deploy time via `rancher_system_default_registry`), so the
airgap registry is baked into the agent automatically — no extra configuration is needed
here for airgap.

## Related

- [`airgap_rancher_helm_deploy` role](../../../../roles/airgap_rancher_helm_deploy/) — Helm deployment role
- [`rancher_auth` role](../../../../roles/rancher_auth/) — Admin token generation
