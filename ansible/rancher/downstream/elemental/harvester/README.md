# Running the Elemental Playbook

This document describes how to run the Ansible playbook responsible for configuring Elemental on Rancher, as well as creating and uploading the Elemental ISO to an S3 bucket.

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

2.  **Configure Elemental Files**

    Prepare your Elemental configuration file defining charts, inventory, ISO, and cluster details.
    Follow the example in the reference [elementalconfig.yaml](./elementalconfig.yaml):

3.  **Create an S3 Bucket**
    Create an S3 bucket with public access to store the Elemental ISO image, follow the instructions in the referenced [README.md](../../../../../tofu/aws/modules/s3/README.md) to create S3 with public access
    This bucket will be used by the playbook to upload and reference the generated ISO.

4.  **Customize variables:**

    Review and adjust the parameters in your vars.yaml file according to your environment and desired configuration.

    *   `elementalconfig_file`: Path to the Elemental YAML configuration file (e.g., "./elementalconfig.yaml").
    *   `elemental_pool_name`: Elemental cluster pool name. (e.g., "elemental-cluster-fire-pool").
    *   `kubeconfig_file`: Path to the kubeconfig file providing access to the target Kubernetes cluster. Ensure this file is accessible from where Ansible is running
    *   `s3_bucket`: S3 bucket name
    *   `aws_access_key`: AWS access key
    *   `aws_secret_key`: AWS secret key
    *   `aws_region`: AWS region

## Running the Playbook

Execute the playbook using the following command:

```bash
ansible-playbook ansible/rancher/downstream/elemental/harvester/elemental-playbook.yml -vvvv -e "@$VARS_FILE"
```

## Outputs

This playbook does not produce any direct outputs.
The deployment results are reflected within the Kubernetes cluster, S3 bucket and the configured Elemental resources.

## Create Elemental VMs on Harvester
Create a elemental VMS on Harvester using the Tofu module setup instructions located at [README.md](../../../../../tofu/harvester/modules/elemental-vm/README.md)
