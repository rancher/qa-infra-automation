# Deployment Guides

End-to-end guides for deploying Kubernetes clusters. Each guide takes you from zero to a running cluster with copy-pasteable commands.

**Before you start:** Complete the [prerequisites](../prerequisites.md).

## Guide Index

| Guide | Distro | Environment | Infra Provider | Complexity |
|-------|--------|-------------|----------------|------------|
| [RKE2 on AWS](rke2-default-aws.md) | RKE2 | Default | AWS (Tofu) | ⭐ Easiest starting point |
| [RKE2 on your own nodes](rke2-default-byo.md) | RKE2 | Default | BYO / on-premise | ⭐ No cloud needed |
| [RKE2 airgap on AWS](rke2-airgap-aws.md) | RKE2 | Airgap | AWS (Tofu) | ⭐⭐⭐ Advanced |
| [K3s on AWS](k3s-default-aws.md) | K3s | Default | AWS (Tofu) | ⭐ |
| [K3s on your own nodes](k3s-default-byo.md) | K3s | Default | BYO / on-premise | ⭐ |
| [Rancher HA](rancher-ha.md) | — | — | Any existing cluster | ⭐⭐ |

## RKE2 vs K3s — Which Should I Choose?

| | RKE2 | K3s |
|---|---|---|
| **Focus** | Security, compliance, FIPS | Lightweight, simplicity |
| **Default CNI** | Canal (Calico + Flannel) | Flannel |
| **Bundled components** | etcd, containerd, CNI, ingress | SQLite/etcd, containerd, Traefik |
| **Resource requirements** | Higher (production workloads) | Lower (edge, dev, CI) |
| **Best for** | Production, regulated environments | Edge, IoT, development, testing |

Both are fully CNCF-conformant Kubernetes distributions from SUSE/Rancher.

## Default vs Airgap

- **Default** (internet-connected): Nodes download RKE2/K3s binaries directly from the internet during installation.
- **Airgap**: Nodes have no internet access. Installation uses pre-downloaded tarballs transferred through a bastion host. A private registry may be configured for container images.

## What Happens After the Cluster?

Once you have a running cluster, you typically:

1. **Install Rancher** → [Rancher HA guide](rancher-ha.md)
2. **Add more workers** → Update your inventory and re-run the cluster playbook
3. **Import downstream clusters** → See [importing clusters in airgap](../import_cluster_on_airgap.md)

## Adding a New Provider

Want to deploy on GCP, Linode, Azure, or Hetzner? See [Adding a New Provider](../adding-a-provider.md) — you only need to implement a Tofu module; Ansible works unchanged.
