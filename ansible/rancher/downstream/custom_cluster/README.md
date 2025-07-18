# Custom Cluster Ansible Playbook

This playbook registers nodes to a rancher custom cluster.

## Prerequisites

Before running the playbook, ensure you have the following in addition to the [general ansible prereqs](../README.md):

* `ansible-inventory-terraform` installed
* SSH access to the target nodes
* A valid inventory file (e.g., `terraform-inventory.yml`)
* A `vars.yaml` file with necessary variables
* A valid rancher custom cluster token

## Usage

Before running the playbook, you may need to set the `ANSIBLE_CONFIG` environment variable to point to the `ansible.cfg` file in this directory:
    ```bash
    export ANSIBLE_CONFIG=/path/to/go/src/github.com/rancher/qa-infra-automation/ansible/rancher/downstream/custom_cluster/ansible.cfg
    ```
1.  **Generate and Check Inventory:**
    If using terraform to create your nodes, you can use the inventory-template.yml to dynamically generate the inventory.
    To check the inventory and view variables and the host graph run the following command.
    ```bash
    envsubst < inventory-template.yml > terraform-inventory.yml
    ansible-inventory -i terraform-inventory.yml --graph --vars
    ```

2.  **Run the Playbook with Verbose output:**

    ```bash
    ansible-playbook -i terraform-inventory.yml custom-cluster-playbook.yml
    ```

## Inventory

The inventory file should contain the target nodes' IP addresses and SSH connection details. The `terraform-inventory.yml` file dynamically generates this inventory from Terraform outputs.
