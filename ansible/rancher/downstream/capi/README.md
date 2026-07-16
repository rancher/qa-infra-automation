# CAPI (Cluster API) Ansible Playbook

This playbook provisions a downstream Kubernetes cluster via [Cluster API](https://cluster-api.sigs.k8s.io/)
(CAPI) on an existing management cluster, with the Rancher Fleet addon enabled so the
resulting cluster is automatically imported into Rancher.

## What it does

1. Validates that the provided `kubeconfig_file` exists.
2. Downloads and SHA256-verifies the `clusterctl` binary (pinned via `clusterctl_version`).
3. Runs `clusterctl init --addon rancher-fleet` against the management cluster.
4. Installs `cert-manager` (required by CAPI providers).
5. Installs the `cluster-api-operator` Helm chart with the Rancher Fleet addon enabled.
6. Applies the CAPI provider manifests defined in `capiconfig_file`, retrying until the
   providers are ready.
7. Optionally applies a `ClusterClass` fetched from `clusterclass_url`.
8. Applies the CAPI `Cluster` manifest defined in `capiclusterconfig_file`.
9. Waits for the `MachineDeployment` matching `capi_pool_name` to be created and become `Ready`.

## Prerequisites

Before running the playbook, ensure you have the following in addition to the
[general ansible prereqs](../../../README.md):

* A running management Kubernetes cluster and a `kubeconfig` file with access to it.
* Network access to GitHub (to download `clusterctl` and the `cert-manager` manifest) and to
  the `cluster-api-operator` Helm repository.
* Ansible collection `kubernetes.core` (installed via `requirements.yml`).
* A `vars.yaml` file with the required variables (see below).

## Variables

Define these in a `vars.yaml` file (see [downstream/vars.yaml](../vars.yaml) for an example) or
pass them with `-e`:

| Variable                 | Required | Default  | Description                                                                 |
|---------------------------|----------|----------|-------------------------------------------------------------------------------|
| `kubeconfig_file`          | Yes      | —        | Path to the kubeconfig for the management cluster.                            |
| `capiconfig_file`          | Yes      | —        | Path to the CAPI provider manifest(s) (infrastructure/bootstrap/control-plane providers). |
| `capiclusterconfig_file`   | Yes      | —        | Path to the CAPI `Cluster` manifest to apply.                                 |
| `capi_pool_name`           | Yes      | —        | Name (or substring) used to match the target `MachineDeployment`.             |
| `clusterclass_url`         | No       | `""`     | URL to fetch a `ClusterClass` manifest from. Skipped when unset/empty.        |
| `clusterctl_version`       | No       | `1.13.3` | `clusterctl` release version to download and verify.                         |

## Usage

Run from the repository root:

```bash
ansible-playbook ansible/rancher/downstream/capi/capi-playbook.yml -e "@vars.yaml"
```

## Outputs

This playbook does not produce direct outputs. Results are reflected in the management
cluster (installed CAPI providers, `cert-manager`, `cluster-api-operator` release) and in the
new downstream cluster's resources (`Cluster`, `ClusterClass`, `MachineDeployment`), which is
imported into Rancher via the Fleet addon.
