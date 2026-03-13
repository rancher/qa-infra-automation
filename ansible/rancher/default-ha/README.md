# Rancher Deployment Playbook

Deploys Rancher (via Helm) onto an existing Kubernetes cluster using cert-manager for TLS.

## Prerequisites

- A running Kubernetes cluster (RKE2, K3s, or other) with a valid kubeconfig
- `ansible` and `kubectl` installed locally
- Ansible `kubernetes.core` collection:
  ```bash
  ansible-galaxy collection install kubernetes.core
  ```

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

## Configuration

All configuration is in `vars.yaml`. Key variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `rancher_version` | Yes | Rancher version to install (e.g. `v2.13.0`) |
| `cert_manager_version` | Yes | cert-manager version, without `v` prefix (e.g. `1.19.1`) |
| `fqdn` | Yes | FQDN for the Rancher UI (e.g. `1.2.3.4.sslip.io`) |
| `bootstrap_password` | Yes | Initial admin bootstrap password |
| `password` | Yes | Admin password after first login |
| `kubeconfig_file` | No | Path to kubeconfig. Set automatically via `KUBECONFIG_FILE` env var when using `make rancher`; only needed when running manually |
| `rancher_chart_repo` | No | Helm repo name (default: `rancher-latest`) |
| `rancher_chart_repo_url` | No | Helm repo URL (default: latest releases) |

## Outputs

The Rancher API key is printed in the playbook debug output on completion.

## Related

- [QUICKSTART.md](./QUICKSTART.md) — step-by-step guide
- [RKE2 default playbook](../../rke2/default/README.md) — deploy the cluster first
