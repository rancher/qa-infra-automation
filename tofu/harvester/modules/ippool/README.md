

# Harvester IP Pool

This module deploys an ippool and requires an existing VM network.

## Variables

Refer to `variables.tf` for a list of configurable variables.

## Outputs

Refer to `outputs.tf` for a list of exported values.

## Sample

`terraform.tfvars`

```terraform
generate_name = "tf"

subnet_cidr = "1.1.1.1/23" 

gateway_ip = "255.255.255.254"

backend_network_name = "existing-vm-network" 

range_ip_end = "1.1.1.255"

range_ip_start = "1.1.1.2"

namespace = "default"
```