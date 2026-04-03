# Quickstart

## Prerequisites

1. Kubernetes cluster: You must have a reachable K3s, RKE2, or other supported Kubernetes cluster.
2. Kubeconfig: You need a kubeconfig file that gives Ansible access to that cluster.
3. Helm: The Rancher upgrade flow installs the `helm-diff` plugin locally, so `helm` must be available where you run Ansible.

## Steps

### Step 1. Create Config

Create `vars.yaml` in this folder with your desired settings, including the FQDN for your Rancher UI. The FQDN can resolve to a load-balanced endpoint, or you can use wildcard DNS with one of your node public IPs.

```yaml
# Version information
rancher_version: "v2.13.0"
cert_manager_version: "1.19.1" # Without the 'v' prefix

# Must match the DNS/IP used for your K8s cluster Load Balancer
fqdn: "a.b.c.d.sslip.io"

# Initial bootstrap and login passwords for the 'admin' user. Do not leave these blank.
bootstrap_password: ""
password: ""
```

If you plan to upgrade Rancher later, add these upgrade-specific variables now or before running the upgrade flow:

```yaml
rancher_chart_repo_upgrade: rancher-latest
rancher_chart_upgrade_repo_url: https://releases.rancher.com/server-charts/latest
rancher_version_upgrade: "v2.13.0"
rancher_image_tag_upgrade: latest # Optional
```

### Step 2. Run Playbook

When running via `make rancher`, the kubeconfig path is set automatically from the cluster step. If running manually, set `kubeconfig_file` in `vars.yaml`:

```yaml
kubeconfig_file: "/absolute/path/to/kubeconfig.yaml"
```

**Via Makefile (recommended)** — run from the repository root:

```sh
make rancher
```

**Manually** — set `KUBECONFIG_FILE` to point to your cluster's kubeconfig, then run from the repository root:

```sh
KUBECONFIG_FILE=/path/to/kubeconfig.yaml ansible-playbook ansible/rancher/default-ha/rancher-playbook.yml
```

### Step 3. Verify

Open your browser and navigate to `https://<fqdn>`.

Log in with the username `admin` and the `password` you defined.

### Step 4. Upgrade Rancher (optional)

The Rancher upgrade logic lives in `rancher-upgrade-tasks.yml` and is executed through `rancher-playbook.yml` when `upgrade_mode=true`.

```sh
ansible-playbook ansible/rancher/default-ha/rancher-playbook.yml \
  -e "upgrade_mode=true"
```

What the upgrade tasks do:

- add the target Rancher Helm repository
- install the `helm-diff` plugin if needed
- upgrade the existing `rancher` Helm release in place with `reuse_values: true`
- wait for the `cattle-system/rancher` deployment to become ready
- wait for `https://<fqdn>` to return HTTP 200
- log in with the permanent `password`
- print a fresh Rancher API token and write it to `generated.tfvars`

> The upgrade flow uses `password`, not `bootstrap_password`, because the bootstrap password is only valid during the first-time setup.

---

## Upgrading the Downstream Cluster Kubernetes Version

To upgrade the Kubernetes version of a downstream cluster managed by Rancher, use `downstream-upgrade-playbook.yml`.

### Step 1. Ensure `vars.yaml` exists

The playbook reads `vars.yaml` from the same directory. At minimum it must define:

```yaml
kubeconfig_file: /absolute/path/to/kubeconfig.yaml
```

You can optionally define:

```yaml
k8s_downstream_cluster_name: "my-cluster"
```

If `k8s_downstream_cluster_name` is set, it must exactly match the Rancher
downstream cluster resource name. If it is omitted, the playbook auto-detects
the cluster name by selecting the first downstream cluster name in sorted order
from `fleet-default`.

### Step 2. Run the k8s upgrade playbook

Run this from the **repository root**:

```sh
ansible-playbook ansible/rancher/downstream/downstream-upgrade-playbook.yml \
  -e "k8s_upgrade_mode=true" \
  -e "kubernetes_version_upgrade=v1.31.0"
```

Replace `v1.31.0` with your target Kubernetes version. The playbook updates both the
selected downstream cluster and Rancher's local cluster to the same Kubernetes version.

> `k8s_upgrade_mode` is `false` by default — the playbook is a no-op unless you pass `-e "k8s_upgrade_mode=true"`.
