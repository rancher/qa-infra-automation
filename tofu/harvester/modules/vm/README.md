# Harvester 

This module deploys airgap rancher on AWS.

## Prerequisites

* harvester's kubeconfig downloaded in this directory, named `local.yaml`
  * harvester should already have a vm network and the VM image to use available
* tofu installed

## Usage

1.  **Apply the Configuration:**

    ```bash
    tofu apply -var-file="terraform.tfvars"
    ```
    or
    ```bash
    tofu apply -var="<variable_name>=<variable_value>"
    ```

    Create a `terraform.tfvars` file or use the `-var` flag to provide values for the variables defined in `variables.tf`.

2.  **Destroy the Infrastructure:**

    ```bash
    tofu destroy -var-file="terraform.tfvars"
    ```
    or
    ```bash
    tofu destroy -var="<variable_name>=<variable_value>"
    ```

    Use the same `terraform.tfvars` file or `-var` flags used during `apply`.

## Variables

Refer to `variables.tf` for a list of configurable variables.

## Outputs

Refer to `outputs.tf` for a list of exported values.

## Sample `terraform.tfvars`

```terraform
nodes = [
  {
    count = 3
    role  = ["etcd", "cp", "worker"]
  }
]
ssh_key = "your-public-key"
hostname_prefix   = "hostnameprefix"
```