# Quickstart

## Prerequisites

1. Cluster Ready: You have a k3s or rke2 cluster.

## Steps

### Step 1. Create Config

Create `vars.yaml` in this folder with your desired settings.

**Important: `fqdn` must resolve to your Load Balancer or Master Node IP (same as the `FQDN` you used for the K8s cluster).**

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

Run this from the repository root.

```sh
ansible-playbook ansible/rancher/default-ha/rancher-playbook.yml
```

### Step 3. Verify

Open your browser and navigate to `https://<fqdn>`.

Log in with the username `admin` and the `password` you defined.