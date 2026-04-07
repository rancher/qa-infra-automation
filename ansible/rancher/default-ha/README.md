# Rancher Deployment Playbook

This directory contains the Ansible playbooks for deploying Rancher in HA mode on
an existing Kubernetes cluster and for performing follow-up upgrade operations.

## Prerequisites

Before running the playbooks, ensure you have the [general Ansible prerequisites](../../README.md) plus:

- A reachable Kubernetes cluster and a valid `kubeconfig` file.
- `helm` installed on the machine running Ansible. The Rancher upgrade flow installs
  the `helm-diff` plugin automatically because `kubernetes.core.helm` uses
  `reuse_values: true`.
- Ansible `kubernetes.core` collection:
  ```bash
  ansible-galaxy collection install kubernetes.core
  ```
- A `vars.yaml` file in this directory. Both `rancher-playbook.yml` and
  `downstream-upgrade-playbook.yml` load it automatically.

## Usage

### Via Makefile (recommended)

From the repository root, with an existing cluster:

```bash
make rancher ENV=default DISTRO=rke2 PROVIDER=aws
```

### Manually

1. Create `vars.yaml` in this directory (see [QUICKSTART.md](./QUICKSTART.md) for the template).

2. Run from the repository root:

```bash
ansible-playbook ansible/rancher/default-ha/rancher-playbook.yml
```

> **Important:** Run all commands from the repository root, not from inside `ansible/`.

## Configuration

All configuration is in `vars.yaml`. Key variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `rancher_version` | Yes | Rancher version to install (e.g. `latest` for HEAD, or `v2.13.0`) |
| `cert_manager_version` | Yes | cert-manager version, without `v` prefix (e.g. `1.19.1`) |
| `kubeconfig_file` | No | Path to kubeconfig. Set automatically via `KUBECONFIG_FILE` env var when using `make rancher`; only needed when running manually |
| `fqdn` | Yes | FQDN for the Rancher UI (e.g. `1.2.3.4.sslip.io`) |
| `bootstrap_password` | Yes | Initial admin bootstrap password |
| `password` | Yes | Admin password after first login |
| `rancher_chart_repo` | No | Helm repo name (default: `rancher-latest`) |
| `rancher_chart_repo_url` | No | Helm repo URL (default: latest releases) |
| `rancher_image_tag` | No | Image tag (default: `latest`; use `head` for dev/HEAD builds) |

### Additional variables for Rancher upgrades

`rancher-upgrade-tasks.yml` is included by `rancher-playbook.yml` when you run the
playbook with `-e "upgrade_mode=true"`. The upgrade tasks expect:

| Variable | Description |
|----------|-------------|
| `rancher_chart_repo_upgrade` | Helm repo name for upgrade (default: `rancher-latest`) |
| `rancher_chart_upgrade_repo_url` | Helm repo URL for upgrade |
| `rancher_version_upgrade` | Target Rancher version (e.g. `latest` for HEAD, or `v2.13.0`) |
| `rancher_image_tag_upgrade` | Optional image tag override |

The upgrade tasks authenticate to Rancher with the permanent `password`, not
`bootstrap_password`, because the bootstrap password is no longer valid after the
initial setup changes the admin password.

The install flow:

- validates `kubeconfig_file` and `fqdn`
- installs cert-manager when `cert_manager_version` is set
- installs Rancher with Helm
- waits for the Rancher and Fleet deployments to become ready
- logs in with `bootstrap_password`, sets the permanent admin `password`, and sets `server-url`
- writes `generated.tfvars` with the Rancher URL and API token

## Running the Rancher upgrade flow

The Rancher upgrade logic is implemented in `rancher-upgrade-tasks.yml` and is invoked
through `rancher-playbook.yml`:

```bash
ansible-playbook ansible/rancher/default-ha/rancher-playbook.yml \
  -e "upgrade_mode=true"
```

The upgrade tasks perform the following actions:

- add the upgrade target Helm repository
- install the `helm-diff` plugin if it is not already present
- run an in-place Helm upgrade of the `rancher` release with `reuse_values: true`
- wait for the `cattle-system/rancher` deployment to become fully ready
- wait for `https://<fqdn>` to return HTTP 200
- log in to Rancher with the permanent admin `password`
- print a fresh API token and overwrite `generated.tfvars` with the updated `fqdn` and `api_key`

Because `reuse_values` is enabled, the upgrade preserves the release's existing Helm
values such as hostname and replica count. The upgrade-specific inputs are primarily
used to select the target chart repository, chart version, and optional image tag.

## Upgrading the downstream cluster Kubernetes version

To upgrade the Kubernetes version of a downstream cluster managed by Rancher:

```bash
ansible-playbook ansible/rancher/downstream/downstream-upgrade-playbook.yml \
  -e "k8s_upgrade_mode=true" \
  -e "kubernetes_version_upgrade=v1.31.0"
```

Replace `v1.31.0` with the target Kubernetes version. The playbook updates both the
selected downstream cluster and Rancher's local cluster to the same Kubernetes version.

If `k8s_downstream_cluster_name` is set in `vars.yaml`, it must exactly match the
Rancher downstream cluster resource name. If it is omitted, the playbook auto-detects
the cluster name by selecting the first downstream cluster name in sorted order from
`fleet-default`.

> `k8s_upgrade_mode` defaults to `false`; the playbook does nothing unless you set it to `true`.

## Outputs

On completion:

- `generated.tfvars` is written to the playbook directory containing the Rancher URL and API token:
  ```hcl
  fqdn    = "https://<fqdn>"
  api_key = "<token>"
  ```
- The API token is printed in the playbook debug output.
- A persistent (non-expiring) API token is created via the `rancher_auth` role and the temporary login token is cleaned up automatically.

## Related

- [QUICKSTART.md](./QUICKSTART.md) — step-by-step guide
- [RKE2 default playbook](../../rke2/default/README.md) — deploy the cluster first
