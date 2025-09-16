This playbook deploys an RKE2 Kubernetes cluster.

## Prerequisites

Before running the playbook, ensure you have the following in addition to the [general ansible prereqs](../../README.md):

* SSH access to the target nodes
* A valid inventory file (e.g., `{your-inventory-name}-inventory.yml`)
* A `vars.yaml` file with necessary variables

## Optional

* `ansible-inventory-terraform` installed

## Usage

Before running the playbook, you may need to set the `ANSIBLE_CONFIG` environment variable to point to the `ansible.cfg` file in this directory:
    ```bash
    export ANSIBLE_CONFIG=/path/to/go/src/github.com/rancher/qa-infra-automation/ansible/rke2/default/ansible.cfg
    ```

1. **Generate and Check Inventory:**
    If using terraform to create your nodes, you can use the inventory-template.yml to dynamically generate the inventory.
    To check the inventory and view variables and the host graph run the following command.
    If you are using terraform to create your nodes, you can use the current inventory-template.yml to dynamically generate the inventory if not you need to provide your own inventory file or adding your data to vars.yaml file.

    ```bash
    envsubst < inventory-template.yml >  {your-inventory-name}-inventory.yml
    ansible-inventory -i {your-inventory-name}-inventory.yml --graph --vars
    ```

2. **Run the Playbook with Verbose output:**

    ```bash
    ansible-playbook -i {your-inventory-name}-inventory.yml rke2-playbook.yml -vvvv --extra-vars "@vars.yaml"
    ```

    The `-vvvv` flag provides very verbose output, which is helpful for debugging. The `--extra-vars "@vars.yaml"` flag loads variables from the `vars.yaml` file.

## Inventory

The inventory file should contain the target nodes' IP addresses and SSH connection details. The `{your-inventory-name}-inventory.yml` file dynamically generates this inventory from Terraform outputs or from the inventory file you provided.

## Sample `vars.yaml`

```yaml
kubernetes_version: 'v1.28.15+rke2r1'
kubeconfig_file: './kubeconfig.yaml'