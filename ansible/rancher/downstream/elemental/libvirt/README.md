# Running the Elemental Playbook

This README provides instructions on how to run the Ansible playbook for deploying Elemental cluster.

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

3.  **Obtain the Elemental Node Public IP and SSH Key**
    Create a compute instance using the Tofu module setup instructions located at [README.md](../../../../tofu/gcp/modules/elemental_nodes/README.md)

    Once deployed, retrieve the Elemental node public IP and SSH private key file.

4.  **Customize variables:**

    Review and adjust the parameters in your vars.yaml file according to your environment and desired configuration.

    *   `elementalconfig_file`: Path to the Elemental YAML configuration file (e.g., "./elementalconfig.yaml").
    *   `elemental_node_public_ip`: Public IP address of the Elemental node. (e.g., "136.112.191.63").
    *   `elemental_pool_name`: Elemental cluster pool name. (e.g., "elemental-cluster-fire-pool").
    *   `kubeconfig_file`: Path to the kubeconfig file providing access to the target Kubernetes cluster. Ensure this file is accessible from where Ansible is running
    *   `ssh_user`: SSH username for connecting to the Elemental node. (e.g., "ubuntu").
    *   `ssh_private_key_file`: Path to the SSH private key corresponding to the instance’s public key (e.g., "./private_key.pem").

## Running the Playbook

Execute the playbook using the following command:

```bash
ansible-playbook ansible/rancher/downstream/elemental/libvirt/elemental-playbook.yml -vvvv -e "@$VARS_FILE"
```

## Outputs

This playbook does not produce any direct outputs.
The deployment results are reflected within the Kubernetes cluster and the configured Elemental resources.
