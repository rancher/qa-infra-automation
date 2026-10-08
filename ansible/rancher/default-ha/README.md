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

### Upgrading the Rancher server via Makefile

`make rancher-upgrade` upgrades the Rancher server in place on the standing HA
cluster (helm upgrade of the `rancher` release with `--reuse-values`):

```bash
# Upgrade to the latest released version, community chart repo
make rancher-upgrade ENV=default DISTRO=rke2 PROVIDER=aws

# Pin the target (deterministic reproduction) and use the Prime chart repo
make rancher-upgrade ENV=default DISTRO=rke2 RANCHER_VERSION_TO_UPGRADE=2.15.2 \
     RANCHER_CHART_REPO_FLAVOR=prime

# Latest patch of the 2.15 line (resolved at runtime)
make rancher-upgrade ENV=default DISTRO=rke2 RANCHER_UPGRADE_LINE=2.15
```

Airgap runs the same target with `ENV=airgap`; the fqdn and ingress hostnames
are derived from the generated inventory, and the kubeconfig must have been
copied to `ansible/rke2/airgap/kubeconfig.yaml` (scp from the bastion):

```bash
make rancher-upgrade ENV=airgap DISTRO=rke2 RANCHER_UPGRADE_LINE=2.15 \
     RANCHER_UPGRADE_SYSTEM_DEFAULT_REGISTRY=privateregistry.qa.rancher.space/proxycache
```

| Make variable | Ansible variable | Default | Description |
|---|---|---|---|
| `RANCHER_VERSION_TO_UPGRADE` | `rancher_version_upgrade` | unset (latest) | When unset, a `vars.yaml` value applies; `latest`/empty resolves at runtime to the newest final release in the repo index; a pinned version passes through unchanged |
| `RANCHER_UPGRADE_LINE` | `rancher_upgrade_line` | — | Resolves at runtime to the newest final release of that line (e.g. `2.15`); cannot be combined with a pinned `RANCHER_VERSION_TO_UPGRADE` |
| `RANCHER_CHART_REPO_FLAVOR` | `rancher_chart_flavor` | unset (community) | When unset, a `vars.yaml` value applies; `community` (`releases.rancher.com/server-charts/latest`) or `prime` (`charts.rancher.com/server-charts/prime`) |
| `RANCHER_IMAGE_TAG_TO_UPGRADE` | `rancher_image_tag_upgrade` | unset (latest) | When unset, a `vars.yaml` value applies; `latest`/empty uses the target chart's `appVersion` |
| `RANCHER_CHART_UPGRADE_REPO_URL` | `rancher_chart_upgrade_repo_url` | — | Explicit chart repo URL; overrides the flavor mapping (airgap seam) |
| `RANCHER_UPGRADE_REPO_USERNAME`/`_PASSWORD` | `rancher_upgrade_repo_username`/`_password` | unset | Chart repo credentials, only passed when set (airgap seam) |
| `RANCHER_UPGRADE_SYSTEM_DEFAULT_REGISTRY` | `rancher_upgrade_system_default_registry` | unset | Sets the `systemDefaultRegistry` helm value when set (airgap seam) |
| `RANCHER_UPGRADE_FQDN`/`_PRIVATE_HOSTNAME`/`_PUBLIC_HOSTNAME` | `fqdn`/`rancher_private_hostname`/`rancher_public_hostname` | derived from the airgap inventory | Upgrade discovery for airgap (no fqdn in tofu state, private node IPs); also gate the post-upgrade Ingress re-patch for both hostnames. Unset in default env (tofu-state discovery) |

Version resolution is also usable standalone, which is how pipelines resolve
the deploy side (latest 2.14.x patch of the source version):

```bash
make rancher-resolve-version SOURCE_LINE=2.14
# {"chart_version": "2.14.3", "image_tag": "v2.14.3", ...}
```

The `rancher_version_upgrade`/`rancher_image_tag_upgrade` variables from the
legacy `-e "upgrade_mode=true"` flow still work when passed directly; the
image-tag `latest` -> `head` mapping is gone (pin `rancher_image_tag_upgrade=head`
for head builds).

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

See [QUICKSTART.md](./QUICKSTART.md) for step-by-step usage.

## Running the Rancher upgrade flow

The Rancher upgrade logic is implemented in `rancher-upgrade-tasks.yml`, invoked by
`rancher-upgrade-playbook.yml` (the `make rancher-upgrade` path above, which also
resolves `latest` targets at runtime). The legacy entry point through
`rancher-playbook.yml` is still available for pinned, pre-resolved inputs:

```bash
ansible-playbook ansible/rancher/default-ha/rancher-upgrade-playbook.yml \
  -e "rancher_version_upgrade=2.15.2"
```

The upgrade tasks perform the following actions:

- add the upgrade target Helm repository
- install the `helm-diff` plugin if it is not already present (the install tolerates helm 4's default plugin-source verification with a `--verify=false` retry; helm 3 is unaffected)
- run an in-place Helm upgrade of the `rancher` release with `reuse_values: true`
- wait for the `cattle-system/rancher` deployment to become fully ready
- wait for `https://<fqdn>` to return HTTP 200
- log in to Rancher with the permanent admin `password`
- print a fresh API token and overwrite `generated.tfvars` with the updated `fqdn` and `api_key`

Because `reuse_values` is enabled, the upgrade preserves the release's existing Helm
values such as hostname and replica count. `rancherImageTag` is deliberately omitted
from the upgrade values unless explicitly pinned, so the chart's own `appVersion`
(always consistent with the chart version) selects the image; the legacy
`latest` → `head` mapping is gone, and head builds are pinned explicitly via
`rancher_image_tag_upgrade=head`.

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
