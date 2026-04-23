# Deploy Rancher HA

> **Estimated time:** ~10 minutes (cluster already running)
>
> **What you'll end up with:** Rancher management server running in HA mode on your existing Kubernetes cluster, accessible via a web UI.

This guide assumes you already have a running RKE2 or K3s cluster. If not, deploy one first:
- [RKE2 on AWS](rke2-default-aws.md) | [RKE2 on your own nodes](rke2-default-byo.md)
- [K3s on AWS](k3s-default-aws.md) | [K3s on your own nodes](k3s-default-byo.md)

## Prerequisites

- A running Kubernetes cluster (RKE2 or K3s) with a kubeconfig file
- [Helm](https://helm.sh/docs/intro/install/) installed locally
- Complete the [general prerequisites](../prerequisites.md)

## Step 1: Configure Rancher

Create the file `ansible/rancher/default-ha/vars.yaml`:

```yaml
# Rancher version — find versions at https://github.com/rancher/rancher/releases
rancher_version: "v2.13.2"
rancher_image_tag: "v2.13.2"

# cert-manager version (required by Rancher for TLS certificates)
cert_manager_version: "1.15.5"

# FQDN — must resolve to your cluster's load balancer or first node IP
# Use <ip>.sslip.io as a wildcard DNS shortcut
fqdn: "1.2.3.4.sslip.io"

# Passwords — do not leave blank
bootstrap_password: "your-bootstrap-password"
password: "your-admin-password"

# Kubeconfig location
# If using 'make rancher' after 'make cluster', this is set automatically.
# Otherwise, set the absolute path to your kubeconfig:
kubeconfig_file: "/absolute/path/to/kubeconfig.yaml"
```

### Key variables explained

| Variable | Description |
|----------|-------------|
| `rancher_version` | Rancher chart version. Use `"latest"` for HEAD builds. |
| `rancher_image_tag` | Docker image tag. Usually matches `rancher_version`. Use `"head"` for dev builds. |
| `cert_manager_version` | cert-manager version (without `v` prefix). Required for TLS. |
| `fqdn` | The URL you'll access Rancher at. Must resolve to your cluster. |
| `bootstrap_password` | First-time setup password (used once during initial login). |
| `password` | Permanent admin password (used for upgrades and API access). |

## Step 2: Deploy Rancher

**Via Makefile (recommended):**

```bash
# If you deployed the cluster with 'make cluster', kubeconfig is auto-detected:
make rancher

# For K3s clusters:
make rancher DISTRO=k3s

# For airgap environments:
make rancher ENV=airgap
```

**Manually:**

```bash
KUBECONFIG_FILE=/path/to/kubeconfig.yaml \
  ansible-playbook ansible/rancher/default-ha/rancher-playbook.yml
```

The playbook will:
1. Install cert-manager
2. Add the Rancher Helm chart repository
3. Deploy Rancher in the `cattle-system` namespace
4. Wait for the deployment to become ready

## Step 3: Verify

Open your browser and navigate to `https://<fqdn>`.

Log in with:
- **Username:** `admin`
- **Password:** the `password` value from `vars.yaml`

From the command line:

```bash
kubectl --kubeconfig /path/to/kubeconfig.yaml get pods -n cattle-system
kubectl --kubeconfig /path/to/kubeconfig.yaml get ingress -n cattle-system
```

Or use the Makefile:

```bash
make status
```

## (Optional) Upgrade Rancher

Add upgrade-specific variables to `vars.yaml`:

```yaml
rancher_chart_repo_upgrade: rancher-latest
rancher_chart_upgrade_repo_url: https://releases.rancher.com/server-charts/latest
rancher_version_upgrade: "latest"
rancher_image_tag_upgrade: "head"   # Optional
```

Then run:

```bash
ansible-playbook ansible/rancher/default-ha/rancher-playbook.yml \
  -e "upgrade_mode=true"
```

The upgrade uses `reuse_values: true` to preserve your existing Helm values, upgrades in place, waits for readiness, and verifies HTTPS access.

## Troubleshooting

**Rancher pods not starting**
```bash
kubectl --kubeconfig /path/to/kubeconfig.yaml get pods -n cattle-system
kubectl --kubeconfig /path/to/kubeconfig.yaml logs -n cattle-system -l app=rancher
```

**cert-manager issues**
```bash
kubectl --kubeconfig /path/to/kubeconfig.yaml get pods -n cert-manager
```

**Can't access `https://<fqdn>`**
- Verify DNS: `nslookup <fqdn>` — it must resolve to the cluster LB or node IP
- For local testing, add an `/etc/hosts` entry: `<node-ip>  <fqdn>`
- Check ingress: `kubectl get ingress -n cattle-system`
- Ensure ports 80 and 443 are open in your security group / firewall

**"bootstrap password" error on login**
- The `bootstrap_password` is only used during the first login
- For subsequent logins, use the `password` value

For more, see [Troubleshooting](../reference/troubleshooting.md).

## Next Steps

- [Rancher playbook details](../../ansible/rancher/default-ha/README.md) for advanced configuration
- [Upgrade downstream cluster Kubernetes version](../../ansible/rancher/default-ha/QUICKSTART.md#upgrading-the-downstream-cluster-kubernetes-version)
- [Import a downstream cluster in airgap](../import_cluster_on_airgap.md)
