# Running the Rancher Playbook

This directory contains the Ansible playbooks for deploying Rancher in HA mode on
an existing Kubernetes cluster and for performing follow-up upgrade operations.

## Prerequisites

Before running the playbooks, ensure you have the [general Ansible prerequisites](../../README.md) plus:

- A reachable Kubernetes cluster and a valid `kubeconfig` file.
- `helm` installed on the machine running Ansible. The Rancher upgrade flow installs
  the `helm-diff` plugin automatically because `kubernetes.core.helm` uses
  `reuse_values: true`.
- A `vars.yaml` file in this directory. Both `rancher-playbook.yml` and
  `k8s-upgrade-playbook.yml` load it automatically.

## Configuration

Create `ansible/rancher/default-ha/vars.yaml` with the values needed for your environment.

### Minimum variables for a fresh Rancher install

```yaml
rancher_version: "v2.13.0"
cert_manager_version: "1.19.1"
kubeconfig_file: /absolute/path/to/kubeconfig.yaml
fqdn: "rancher.example.com"
bootstrap_password: "initial-admin-password"
password: "permanent-admin-password"
```

### Common optional variables

```yaml
rancher_chart_repo: rancher-latest
rancher_chart_repo_url: https://releases.rancher.com/server-charts/latest
rancher_image_tag: latest
```

### Additional variables for Rancher upgrades

`rancher-upgrade-tasks.yml` is included by `rancher-playbook.yml` when you run the
playbook with `-e "upgrade_mode=true"`. The upgrade tasks expect:

```yaml
rancher_chart_repo_upgrade: rancher-latest
rancher_chart_upgrade_repo_url: https://releases.rancher.com/server-charts/latest
rancher_version_upgrade: "v2.13.0"   # use "latest" to let Helm resolve the newest chart
rancher_image_tag_upgrade: latest    # optional; use "latest" to map to the "head" image tag
```

The upgrade tasks authenticate to Rancher with the permanent `password`, not
`bootstrap_password`, because the bootstrap password is no longer valid after the
initial setup changes the admin password.

## Running the Rancher install playbook

> **Important:** Run all commands from the repository root, not from inside `ansible/`.

```bash
ansible-playbook ansible/rancher/default-ha/rancher-playbook.yml
```

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
ansible-playbook ansible/rancher/default-ha/k8s-upgrade-playbook.yml \
  -e "k8s_upgrade_mode=true" \
  -e "kubernetes_version_upgrade=v1.31.0"
```

Replace `v1.31.0` with the target Kubernetes version.

If `k8s_downstream_cluster_name` is set in `vars.yaml`, it must exactly match the
Rancher downstream cluster resource name. If it is omitted, the playbook auto-detects
the cluster name by selecting the first downstream cluster name in sorted order from
`fleet-default`.

> `k8s_upgrade_mode` defaults to `false`; the playbook does nothing unless you set it to `true`.

## Outputs

Both the install flow and the Rancher upgrade flow print a Rancher API token in the
debug output and write `generated.tfvars` containing:

```hcl
fqdn = "https://<fqdn>"
api_key = "<rancher-api-token>"
```
