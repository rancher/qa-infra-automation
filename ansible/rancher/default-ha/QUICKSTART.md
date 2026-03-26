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

# Must match the DNS/IP used for your K8s cluster Load Balancer
fqdn: "a.b.c.d.sslip.io"

# Initial bootstrap and login passwords for the 'admin' user. Do not leave these blank.
bootstrap_password: ""
password: ""
```

When running via `make rancher`, the kubeconfig path is set automatically from the cluster step. If running manually, you can override it:

```yaml
# Only needed when running manually (not via make):
kubeconfig_file: "/absolute/path/to/kubeconfig.yaml"
```

### Step 2. Run Playbook

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