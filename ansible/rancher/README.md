# Running the Rancher Playbook

This README provides instructions on how to run the Ansible playbook for deploying Rancher.

## Prerequisites

Before running the playbook, ensure you have the following:

*   **Ansible:** Version 2.9 or later is recommended.
*   **Python 3.11:**  Along with the `ansible` and `kubernetes` packages.
*   **Kubernetes Cluster:** A running Kubernetes cluster (e.g., RKE2, K3s, or a managed Kubernetes service).  The playbook assumes you have a `kubeconfig` file that allows access to this cluster.
*   **Terraform (Optional):** If you're using the provided Terraform inventory, you'll need Terraform installed and configured to manage your infrastructure.
*   **Environment Variables:**  You'll need to set the following environment variables:
    *   `RANCHER_PLAYBOOK_PATH`:  The full path to your `rancher-playbook.yml` file.
    *   `VARS_FILE`: The full path to your variables file (e.g., `vars.yaml`).

## Installation

1.  **Install required Python packages:**

    ```bash
    python3.11 -m pip install ansible kubernetes
    ```

## Configuration

1.  **Set environment variables:**

    Before running the playbook, set the necessary environment variables. Since the playbook is run from the root of the repository, the paths are relative to that location. For example:

    ```bash
    export VARS_FILE="/path/to/vars.yaml"
    ```

    Replace `/path/to/rancher-playbook.yml` and `/path/to/vars.yaml` with the actual paths to your files.

2.  **Customize variables (optional):**

    Review and modify the variables in your `vars.yaml` file to match your desired Rancher configuration.  Key variables include:

    *   `rancher_version`: The Rancher version to install (e.g., "v2.10.3").
    *   `rancher_image_tag`: The Rancher image tag (e.g., "head").  If not specified, the latest stable release will be used.
    *   `cert_manager_version`: The cert-manager version to install (e.g., "1.11.0").
    *   `kubeconfig_file`: The path to your `kubeconfig` file.  **Ensure this path is accessible from the environment where Ansible is running (e.g., within a Docker container if applicable).**
    *   `bootstrap_password`: The initial password for the Rancher admin user.

## Running the Playbook

To run the playbook, use the following command:

```bash
ansible-playbook "ansible/rancher/rancher-playbook.yml" -vvvv -e "@$VARS_FILE"
