# Downstream Rancher Cluster rke2/k3s module

This module deploys a downstream cluster using a cloud credential on your rancher setup

## Prerequisites

* An api_key from your rancher setup
* tofu installed on your client machine
* valid credentials to a provider that works with rancher's node drivers (i.e. aws, harvester)

## Usage

1.  **Create a Workspace:**

    ```bash
    tofu workspace new <workspace_name>
    ```

2.  **Select the Workspace:**

    ```bash
    tofu workspace select <workspace_name>
    ```

3.  **Create the downstream cluster**
    * see the [variables section](#sample) to configure the cluster
    ```bash
    tofu -chdir=tofu/rancher/cluster apply -auto-approve -var-file=/path/to/vars.tfvars
    ```

    Create a `vars.tfvars` file or use the `-var` flag to provide values for the variables defined in `variables.tf`.

4.  **Destroy the downstream cluster:**

    ```bash
    tofu -chdir=tofu/rancher/cluster destroy -auto-approve -var-file=/path/to/vars.tfvars
    ```

    Use the same `vars.tfvars` file or `-var` flags used during `apply`.

## Outputs
Refer to [outputs.tf](./outputs.tf) for a list of exported values.

## Sample `vars.tfvars`
this will highly depend on the selected provider. This example includes options for aws. Sensitive info is omitted. 

```tofu

api_key = ""
fqdn = "https://rancher.io"

cloud_provider = "aws"
create_new = true

node_config = {
  access_key = ""
  secret_key = ""

  aws_ami = "ami-0e01311d1f112d4d0"

  aws_instance_type = "t3a.xlarge"

  aws_security_group_names =   ["allopen-dualstack"]
  aws_vpc = "vpc-081cec85dbe35e9bd"
  aws_subnet = "subnet-0377a1ca391d51cae"
  aws_subnet    = "subnet-6d011e0a"
  airgap_setup  = false
  proxy_setup   = false
  aws_volume_size   = 50
  aws_volume_type   = "gp3"
  aws_hostname_prefix  = "tfex"
  aws_region    = "us-west-1"
  aws_route53_zone  = ""
  aws_availability_zone = "b"
  aws_ssh_user = "ec2-user"

}

kubernetes_version = "v1.31.9+rke2r1"
machine_pools = [
  {
    control_plane_role = true
    worker_role = true
    etcd_role = true
    quantity = 1
  }
]
```