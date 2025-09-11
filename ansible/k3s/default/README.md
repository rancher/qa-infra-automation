# K3S Cluster Ansible Playbook

This playbook deploys an K3S Kubernetes cluster.

## Prerequisites

Before running the playbook, ensure you have the following in addition to the [general ansible prereqs](../README.md):

* `ansible-inventory-terraform` installed
* SSH access to the target nodes
* A valid inventory file (e.g., `terraform-inventory.yml`)
* A `vars.yaml` file with necessary variables

## Usage

Before running the playbook, you may need to set the `ANSIBLE_CONFIG` environment variable to point to the `ansible.cfg` file in this directory:
    ```bash
    export ANSIBLE_CONFIG=/path/to/go/src/github.com/rancher/qa-infra-automation/ansible/k3s/default/ansible.cfg
    ```

1. **Generate and Check Inventory:**
    If using terraform to create your nodes, you can use the inventory-template.yml to dynamically generate the inventory.
    To check the inventory and view variables and the host graph run the following command.

    ```bash
    envsubst < inventory-template.yml > terraform-inventory.yml
    ansible-inventory -i terraform-inventory.yml --graph --vars
    ```

2. **Run the Playbook with Verbose output:**

    ```bash
    ansible-playbook -i terraform-inventory.yml k3s-playbook.yml -vvvv --extra-vars "@vars.yaml"
    ```

    The `-vvvv` flag provides very verbose output, which is helpful for debugging. The `--extra-vars "@vars.yaml"` flag loads variables from the `vars.yaml` file.

## Inventory

The inventory file should contain the target nodes' IP addresses and SSH connection details. The `terraform-inventory.yml` file dynamically generates this inventory from Terraform outputs.

## Sample `vars.yaml`

```yaml
kubernetes_version: 'v1.28.15+k3s1'
kubeconfig_file: './kubeconfig.yaml'
