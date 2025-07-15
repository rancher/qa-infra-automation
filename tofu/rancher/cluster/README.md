# Downstream Rancher Cluster rke2/k3s module

This module deploys a downstream cluster on your rancher setup

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
    tofu -chdir=tofu/rancher/cluster apply -auto-approve -var-file=/path/to/vars.tfvars -var-file=$REPO_ROOT/ansible/rancher/generated.tfvars
    ```
    omit the last -var-file if not using rancher installed via ansible

    Create a `vars.tfvars` file or use the `-var` flag to provide values for the variables defined in `variables.tf`.

4.  **Destroy the downstream cluster:**

    ```bash
    tofu -chdir=tofu/rancher/cluster destroy -auto-approve -var-file=/path/to/vars.tfvars -var-file=$REPO_ROOT/ansible/rancher/generated.tfvars
    ```

    Use the same `vars.tfvars` file or `-var` flags used during `apply`.

## Outputs
Refer to [outputs.tf](./outputs.tf) for a list of exported values.

## Sample `vars.tfvars`
this will highly depend on the selected provider. This example includes options for aws. Sensitive info is omitted. 

```tofu

kubernetes_version = "v1.32.5+rke2r1"
is_network_policy = false
machine_pools = [ {
  control_plane_role = true
  worker_role = true
  etcd_role = true
  quantity = 1
} ]
create_new = true
generate_name = "tf"
node_config = {
  aws_access_key = ""
  aws_secret_key= ""

  aws_ami = "ami-0e01311d1f112d4d0"

  aws_instance_type = "t3a.2xlarge"
  aws_security_group = ["rancher-nodes"] 

  aws_subnet = "subnet-123"
  aws_availability_zone = "b"
  aws_vpc = "vpc-123"
  aws_region    = "us-west-1"

  aws_volume_size   = 50
  aws_volume_type   = "gp3"
  aws_hostname_prefix  = "tf"
  aws_route53_zone  = "qa.rancher.space"
}

fqdn = "https://rancher-setup.example"
api_key =  ""

cloud_provider = "aws"
insecure = true
```