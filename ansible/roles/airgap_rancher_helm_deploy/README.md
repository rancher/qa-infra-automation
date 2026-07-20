# airgap_rancher_helm_deploy Role

Deploys Rancher onto an (airgap) RKE2/K3s cluster using Helm, via a bastion host with
`kubectl` configured. Installs Helm and cert-manager if needed, installs/upgrades the
Rancher chart, and waits for the deployment to become ready.

## Requirements

- Bastion host with `kubectl` configured (`kubeconfig_path`)
- `python3-pip`, `python3-kubernetes`, `python3-yaml` on the bastion
- The `kubernetes.core` Ansible collection
- RKE2/K3s cluster already installed and reachable from the bastion

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `install_helm` | `true` | Install Helm 3 on the bastion if not present |
| `helm_version` | `v3.12.3` | Helm version to install |
| `kubeconfig_path` | `/home/{{ ansible_user }}/.kube/config` | Kubeconfig used for all Helm/kubectl calls |
| `rancher_namespace` | `cattle-system` | Namespace Rancher is deployed into |
| `rancher_helm_chart_repo_url` | `https://releases.rancher.com/server-charts/latest` | Rancher Helm chart repository URL |
| `rancher_helm_chart_repo_name` | `rancher-latest` | Name to register the chart repository under |
| `rancher_chart_version` | `""` | Pin a specific chart version (empty = latest) |
| `rancher_bootstrap_password` | `admin` | Bootstrap password set during Helm install |
| `rancher_image_tag` | _(unset)_ | Rancher image tag/version to deploy (e.g. `v2.12.2`) |
| `rancher_private_hostname` / `rancher_hostname` | _(unset)_ | Hostname used in the Rancher ingress/UI |
| `rancher_use_bundled_system_charts` | `true` | Use bundled system charts (`useBundledSystemChart`) |
| `rancher_tls_source` | `rancher` | TLS source: `rancher`, `letsEncrypt`, or `secret` |
| `cert_manager_version` | `""` | cert-manager chart version (SemVer, no `v`); empty = latest |
| `rancher_system_default_registry` | `""` | **Airgap:** private registry passed to the chart as `global.cattle.systemDefaultRegistry` |
| `rancher_advanced_values` | `{}` | Extra Helm values merged into the Rancher release |

### `rancher_system_default_registry` (airgap)

Set this to your private registry URL **without a scheme** (e.g.
`privateregistry.example.com:5000`). When non-empty it is passed to the Rancher Helm
chart as `global.cattle.systemDefaultRegistry`, so that at **install time** Rancher
rewrites its system images — including the `shell-image` setting (`rancher/shell:<tag>`,
used by any Rancher feature that runs a `kubectl`/rancher-shell job) — to
`<registry>/rancher/shell:<tag>`.

This is **required for airgap**: without it, `shell-image` stays as the public
`rancher/shell:<tag>` reference and cannot be pulled, which breaks anything that spawns a
shell job (for example the `WorkloadUpgradeTest` deployment-rollback path in
`rancher/tests`, failing with a misleading `resource name may not be empty`).

Notes:

- `shell-image` is seeded from `system-default-registry` at **Rancher startup** and is
  **not** rewritten when the setting is changed post-install, so it must be set at deploy
  time (which is what this variable does) — patching it after the fact requires a Rancher
  restart.
- `rancher/shell:<tag>` must exist at `<registry>/rancher/shell:<tag>`. Containerd registry
  *mirrors* (e.g. `docker.io` → `proxycache/...`) do not cover this verbatim reference, so
  the image must be mirrored to the registry root.
- Leave empty for internet-connected deployments (the chart treats `""` as no registry).

## Example

```yaml
# group_vars/all.yml
deploy_rancher: true
install_helm: true

rancher_hostname: "rancher.example.com"
rancher_bootstrap_password: "your-secure-password"
rancher_image_tag: v2.12.2
rancher_use_bundled_system_charts: true

# Airgap: private registry hosting rancher/shell and system images
rancher_system_default_registry: "privateregistry.example.com:5000"
```

```bash
ansible-playbook -i inventory/inventory.yml \
  ansible/rke2/airgap/playbooks/deploy/rancher-helm-deploy-playbook.yml
```

## Helm values applied

The role installs Rancher with (roughly):

```yaml
hostname: "{{ rancher_private_hostname }}"
bootstrapPassword: "{{ rancher_bootstrap_password }}"
useBundledSystemChart: "{{ rancher_use_bundled_system_charts }}"
rancherImageTag: "{{ rancher_image_tag }}"
ingress:
  tls:
    source: "{{ rancher_tls_source }}"
global:
  cattle:
    systemDefaultRegistry: "{{ rancher_system_default_registry }}"
```

## Related

- Deploy playbook: [`ansible/rke2/airgap/playbooks/deploy/rancher-helm-deploy-playbook.yml`](../../rke2/airgap/playbooks/deploy/rancher-helm-deploy-playbook.yml)
- Airgap guide: [`ansible/rke2/airgap/README.md`](../../rke2/airgap/README.md)
