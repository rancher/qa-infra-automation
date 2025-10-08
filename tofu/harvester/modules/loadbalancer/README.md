# Harvester Loadbalancer

This module deploys a loadbalancer and attaches/creates an ippool if specified.

## Variables

Refer to `variables.tf` for a list of configurable variables. ../ippool/README.md is a subresource of this one.

## Outputs

Refer to `outputs.tf` for a list of exported values.

## Sample

`terraform.tfvars`

```terraform
generate_name = "tf"


ippool_name = "existing-pool-name" // optional
```