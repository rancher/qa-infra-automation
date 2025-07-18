# Downstream Rancher Cluster rke2/k3s module

This module deploys a downstream cluster on your rancher setup

## Prerequisites

* An api_key from your rancher setup
* tofu installed on your client machine

## Usage

1.  **Create the downstream cluster**
    * see the [variables section](#sample) to configure the cluster
    ```bash
    tofu -chdir=tofu/rancher/custom_cluster apply -auto-approve -var-file=/path/to/vars.tfvars
    ```

    Create a `vars.tfvars` file or use the `-var` flag to provide values for the variables defined in `variables.tf`.

2.  **Destroy the downstream cluster:**

    ```bash
    tofu -chdir=tofu/rancher/custom_cluster destroy -auto-approve -var-file=/path/to/vars.tfvars
    ```

    Use the same `vars.tfvars` file or `-var` flags used during `apply`.

## Outputs
`cluster_registration_token` -- the (insecure) registration token for the rancher custom cluster (with no roles).

## Sample

`vars.tfvars`
```tofu
kubernetes_version = "v1.32.5+rke2r1"
is_network_policy = false
fqdn = "https://rancher-setup.example"
api_key =  ""

insecure = true
```