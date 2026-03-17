# Quickstart

## Prerequisites

1. Kubernetes Cluster: You must have a k3s or rke2 cluster.

## Steps

### Step 1. Create Config

Create `vars.yaml` in this folder with your desired settings, including the FQDN for your rancher UI. This can resolve to a load balanced endpoint, or you can use a wildcard dns with one of your node's public IPs.

```yaml
# Version information
rancher_version: "v2.13.0"
cert_manager_version: "1.19.1" # Without the 'v' prefix

# Absolute path to kubeconfig file for the cluster to install rancher into
kubeconfig_file: ../k3s/default/kubeconfig.yaml

# Must match the DNS/IP used for your K8s cluster Load Balancer
fqdn: "a.b.c.d.sslip.io"

# Initial bootstrap and login passwords for the 'admin' user. Do not leave these blank.
bootstrap_password: ""
password: ""
```

### Step 2. Run Playbook

> **Important:** All `ansible-playbook` commands must be run from the **repository root**, not from inside the `ansible/` subdirectory.

```sh
ansible-playbook ansible/rancher/default-ha/rancher-playbook.yml
```

### Step 3. Verify

Open your browser and navigate to `https://<fqdn>`.

Log in with the username `admin` and the `password` you defined.

---

## Upgrading the Downstream Cluster Kubernetes Version

To upgrade the Kubernetes version of a downstream cluster managed by Rancher, use `k8s-upgrade-playbook.yml`.

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
ansible-playbook ansible/rancher/default-ha/k8s-upgrade-playbook.yml \
  -e "k8s_upgrade_mode=true" \
  -e "kubernetes_version_upgrade=v1.31.0"
```

Replace `v1.31.0` with your target Kubernetes version.

> `k8s_upgrade_mode` is `false` by default — the playbook is a no-op unless you pass `-e "k8s_upgrade_mode=true"`.
