# Running the CAPI Playbook

This README provides instructions on how to run the Ansible playbook for deploying CAPI cluster.

## Prerequisites

Before running the playbook, ensure you have the following in addition to the [general ansible prereqs](../../README.md):
*   **Kubernetes Cluster:** A running Kubernetes cluster (e.g., RKE2, K3s, or a managed Kubernetes service).  The playbook assumes you have a `kubeconfig` file that allows access to this cluster.
*   **Environment Variables:**  You'll need to set the following environment variables:
    *   `VARS_FILE`: The full path to your variables file (e.g., `vars.yaml`).

## Configuration

1.  **Set Environment Variables**

    Before running the playbook, set the necessary environment variables. Since the playbook is run from the root of the repository, the paths are relative to that location. For example:

    ```bash
    export VARS_FILE="/path/to/vars.yaml"
    ```

    Replace `/path/to/vars.yaml` with the actual paths to your files.

2.  **Configure CAPI Files**

    Prepare your CAPI configuration file defining charts, inventory, ISO, and cluster details.
    Follow the example in the reference [capiconfig.yaml](./capiconfig.yaml):

3.  **Customize variables:**

    Review and adjust the parameters in your vars.yaml file according to your environment and desired configuration.

    *   `capiconfig_file`: Path to the CAPI YAML configuration file (e.g., "./capiconfig.yaml").
    *   `capi_pool_name`: CAPI cluster pool name. (e.g., "capi-cluster-fire-pool").
    *   `kubeconfig_file`: Path to the kubeconfig file providing access to the target Kubernetes cluster. Ensure this file is accessible from where Ansible is running

## Running the Playbook

Execute the playbook using the following command:

```bash
ansible-playbook ansible/rancher/downstream/capi/capi-playbook.yml -vvvv -e "@$VARS_FILE"
```

## Outputs

This playbook does not produce any direct outputs.
The deployment results are reflected within the Kubernetes cluster and the configured CAPI resources.
